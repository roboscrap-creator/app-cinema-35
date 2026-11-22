import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/cinema_widgets.dart';

class AppUpdaterService {
  static const String _repoApiUrl =
      'https://api.github.com/repos/roboscrap-creator/app-cinema-35/releases/tags/latest-apk';
  static const String _prefUltimoAssetId = 'cinema_ultimo_apk_asset_id';
  static const String _prefUltimoUpdatedAt = 'cinema_ultimo_apk_updated_at';
  static const MethodChannel _channel = MethodChannel('com.chiavegatti.cinema/torrserver');

  static Future<void> verificarAtualizacao(
    BuildContext context, {
    bool silencioso = true,
  }) async {
    try {
      final resp = await http
          .get(Uri.parse(_repoApiUrl), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        if (!silencioso && context.mounted) {
          _mostrarMensagem(context, 'Não foi possível verificar atualizações agora.');
        }
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final assets = (data['assets'] as List<dynamic>? ?? []);
      Map<String, dynamic>? apkAsset;
      for (final a in assets) {
        if (a is Map<String, dynamic> &&
            (a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
          apkAsset = a;
          break;
        }
      }

      if (apkAsset == null) {
        if (!silencioso && context.mounted) {
          _mostrarMensagem(context, 'Nenhuma atualização encontrada.');
        }
        return;
      }

      final assetId = (apkAsset['id'] ?? '').toString();
      final updatedAt = (apkAsset['updated_at'] ?? '').toString();
      final downloadUrl = (apkAsset['browser_download_url'] ?? '').toString();
      final sizeBytes = (apkAsset['size'] as num?)?.toInt() ?? 0;
      final chaveVersao = '${assetId}_$updatedAt';

      final prefs = await SharedPreferences.getInstance();
      final jaInstalada = prefs.getString(_prefUltimoUpdatedAt) ?? '';

      // Na primeira abertura após instalar manualmente, registra a versão atual como base
      if (jaInstalada.isEmpty && silencioso) {
        await prefs.setString(_prefUltimoUpdatedAt, chaveVersao);
        await prefs.setString(_prefUltimoAssetId, assetId);
        return;
      }

      if (jaInstalada == chaveVersao) {
        if (!silencioso && context.mounted) {
          _mostrarMensagem(context, 'Seu aplicativo já está na versão mais recente!');
        }
        return;
      }

      if (!context.mounted) return;
      _exibirDialogoAtualizacao(
        context: context,
        downloadUrl: downloadUrl,
        sizeBytes: sizeBytes,
        updatedAt: updatedAt,
        onConcluido: () async {
          await prefs.setString(_prefUltimoUpdatedAt, chaveVersao);
          await prefs.setString(_prefUltimoAssetId, assetId);
        },
      );
    } catch (_) {
      if (!silencioso && context.mounted) {
        _mostrarMensagem(context, 'Erro de conexão ao verificar atualização.');
      }
    }
  }

  static void _mostrarMensagem(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF1A202C),
      ),
    );
  }

  static void _exibirDialogoAtualizacao({
    required BuildContext context,
    required String downloadUrl,
    required int sizeBytes,
    required String updatedAt,
    required Future<void> Function() onConcluido,
  }) {
    final mb = sizeBytes > 0 ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '';
    final dataFmt = updatedAt.length >= 10 ? updatedAt.substring(0, 10) : updatedAt;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool baixando = false;
        double progresso = 0.0;
        String status = 'Uma nova versão do Cinema está disponível${mb.isNotEmpty ? " ($mb)" : ""}.
Publicado em: $dataFmt';

        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> iniciarDownloadEInstalar() async {
              if (baixando) return;
              setModal(() {
                baixando = true;
                progresso = 0.0;
                status = 'Baixando atualização... 0%';
              });

              try {
                final paths = await _channel.invokeMapMethod<String, dynamic>('getPaths');
                final filesDir = (paths?['filesDir'] ?? Directory.systemTemp.path).toString();
                final apkFile = File('$filesDir/cinema_update.apk');
                if (await apkFile.exists()) {
                  await apkFile.delete();
                }

                final client = http.Client();
                final req = http.Request('GET', Uri.parse(downloadUrl));
                final streamed = await client.send(req);
                final total = streamed.contentLength ?? sizeBytes;
                int recebido = 0;

                final sink = apkFile.openWrite();
                await for (final chunk in streamed.stream) {
                  sink.add(chunk);
                  recebido += chunk.length;
                  if (total > 0 && ctx.mounted) {
                    final pct = (recebido / total).clamp(0.0, 1.0);
                    setModal(() {
                      progresso = pct;
                      status = 'Baixando atualização... ${(pct * 100).toStringAsFixed(0)}%';
                    });
                  }
                }
                await sink.flush();
                await sink.close();
                client.close();

                if (ctx.mounted) {
                  setModal(() {
                    status = 'Abrindo instalador do Android...';
                  });
                }

                final res = await _channel.invokeMethod<String>('installApk', {
                  'path': apkFile.path,
                });

                if (res == 'PERMISSION_NEEDED') {
                  if (ctx.mounted) {
                    setModal(() {
                      baixando = false;
                      status =
                          'Permita "Instalar apps desconhecidos" para o Cinema nas configurações e clique em Atualizar Agora novamente.';
                    });
                  }
                  return;
                }

                await onConcluido();
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  setModal(() {
                    baixando = false;
                    status = 'Falha ao baixar atualização: $e';
                  });
                }
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF141821),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFF5B82E), width: 1.8),
              ),
              title: const Row(
                children: [
                  Icon(Icons.system_update, color: Color(0xFFF5B82E), size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Atualização Disponível',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  if (baixando) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progresso > 0 ? progresso : null,
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF5B82E)),
                    ),
                  ],
                ],
              ),
              actions: baixando
                  ? []
                  : [
                      CinemaFocusBox(
                        borderRadius: 8,
                        onTap: () => Navigator.pop(ctx),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text('Depois', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      CinemaFocusBox(
                        autofocus: true,
                        borderRadius: 8,
                        onTap: iniciarDownloadEInstalar,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5B82E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Atualizar Agora',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
            );
          },
        );
      },
    );
  }
}
