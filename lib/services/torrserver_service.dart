import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class TorrentStreamInfo {
  final String playUrl;
  final String fileName;
  final int fileSizeBytes;
  final int activePeers;
  final int totalSeeds;
  final double downloadSpeedBytes;

  const TorrentStreamInfo({
    required this.playUrl,
    required this.fileName,
    required this.fileSizeBytes,
    required this.activePeers,
    required this.totalSeeds,
    required this.downloadSpeedBytes,
  });

  String get velocidadeFormatada {
    if (downloadSpeedBytes <= 0) return '0 KB/s';
    final mb = downloadSpeedBytes / (1024 * 1024);
    if (mb >= 1.0) return '${mb.toStringAsFixed(1)} MB/s';
    final kb = downloadSpeedBytes / 1024;
    return '${kb.toStringAsFixed(0)} KB/s';
  }

  String get tamanhoFormatado {
    if (fileSizeBytes <= 0) return '';
    final gb = fileSizeBytes / (1024 * 1024 * 1024);
    if (gb >= 1.0) return '${gb.toStringAsFixed(2)} GB';
    final mb = fileSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }
}

class TorrServerService {
  static const MethodChannel _channel = MethodChannel('com.chiavegatti.cinema/torrserver');
  static const String baseUrl = 'http://127.0.0.1:8090';
  static Process? _process;
  static String ultimoErro = '';

  static Future<bool> _portaAberta() async {
    try {
      final socket = await Socket.connect('127.0.0.1', 8090, timeout: const Duration(milliseconds: 400));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> garantirAtivo() async {
    if (await _portaAberta()) return true;

    try {
      final paths = await _channel.invokeMapMethod<String, String>('getPaths');
      final nativeLibDir = paths?['nativeLibDir'] ?? '';
      final filesDir = paths?['filesDir'] ?? '';

      if (nativeLibDir.isEmpty || filesDir.isEmpty) {
        ultimoErro = 'Caminhos nativos vazios (nativeLibDir/filesDir).';
        return false;
      }

      final binPath = '$nativeLibDir/libtorrserver.so';
      final binFile = File(binPath);
      if (!await binFile.exists()) {
        ultimoErro = 'Binário não encontrado em: $binPath';
        return false;
      }

      final dataDir = Directory('$filesDir/torrserver');
      if (!await dataDir.exists()) {
        await dataDir.create(recursive: true);
      }

      final configFile = File('${dataDir.path}/config.yaml');
      await configFile.writeAsString(
        'port: 8090\n'
        'http_port: 8090\n'
        'listen: "127.0.0.1:8090"\n'
        'path: "${dataDir.path}"\n'
        'cache_path: "${dataDir.path}"\n'
        'use_disk: false\n'
        'rdb: true\n',
      );

      final tentativasArgs = <List<String>>[
        ['-c', configFile.path],
        <String>[],
      ];

      final logs = <String>[];

      for (final args in tentativasArgs) {
        if (_process != null) {
          _process!.kill();
          _process = null;
        }
        logs.clear();

        int? exitCodeCapturado;
        _process = await Process.start(
          binPath,
          args,
          workingDirectory: dataDir.path,
          environment: {'HOME': filesDir, 'TMPDIR': dataDir.path},
        );

        _process!.stdout.transform(utf8.decoder).listen((d) {
          final line = d.trim();
          if (line.isNotEmpty && logs.length < 15) logs.add(line);
        });
        _process!.stderr.transform(utf8.decoder).listen((d) {
          final line = d.trim();
          if (line.isNotEmpty && logs.length < 15) logs.add(line);
        });
        _process!.exitCode.then((code) => exitCodeCapturado = code);

        for (int i = 0; i < 16; i++) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (await _portaAberta()) {
            ultimoErro = '';
            return true;
          }
          if (exitCodeCapturado != null) break;
        }
      }

      ultimoErro = logs.isNotEmpty
          ? 'TorrServer encerrou: ${logs.join(" | ") }'
          : 'Timeout na porta 8090 ($binPath).';
      return false;
    } catch (e) {
      ultimoErro = 'Falha ao iniciar processo: $e';
      return false;
    }
  }

  static Future<Map<String, dynamic>?> _postJson(String endpoint, Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl$endpoint'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final raw = await res.transform(utf8.decoder).join();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static bool _ehArquivoVideo(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('Sample') || lower.contains('sample')) return false;
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.m4v');
  }

  static Future<TorrentStreamInfo?> prepararMagnet(
    String magnetUrl, {
    void Function(String statusTelemetria)? onStatus,
    bool Function()? cancelado,
  }) async {
    final ativo = await garantirAtivo();
    if (!ativo) return null;

    onStatus?.call('Adicionando magnet ao TorrServer...');
    final addResp = await _postJson('/torrents', {
      'action': 'add',
      'link': magnetUrl.trim(),
      'title': 'Cinema Stream',
      'save_to_db': false,
    });

    final hash = (addResp?['hash'] ?? '').toString().trim();
    if (hash.isEmpty) {
      final encoded = Uri.encodeComponent(magnetUrl.trim());
      return TorrentStreamInfo(
        playUrl: '$baseUrl/stream?link=$encoded&index=1&play',
        fileName: 'Stream P2P',
        fileSizeBytes: 0,
        activePeers: 0,
        totalSeeds: 0,
        downloadSpeedBytes: 0,
      );
    }

    for (int tentativa = 0; tentativa < 90; tentativa++) {
      if (cancelado != null && cancelado()) return null;

      final info = await _postJson('/torrents', {
        'action': 'get',
        'hash': hash,
      });

      if (info != null) {
        final peers = (info['active_peers'] as num?)?.toInt() ?? 0;
        final seeds = (info['connected_seeders'] as num?)?.toInt() ?? 0;
        final speed = (info['download_speed'] as num?)?.toDouble() ?? 0.0;
        final rawStats = info['file_stats'];

        final speedKb = (speed / 1024).toStringAsFixed(0);
        onStatus?.call(
          'Buscando metadados P2P...\nPeers: $peers • Seeds: $seeds • Vel: $speedKb KB/s',
        );

        if (rawStats is List && rawStats.isNotEmpty) {
          Map<String, dynamic>? melhorArquivo;
          int maiorTamanho = -1;

          for (final item in rawStats) {
            if (item is Map<String, dynamic>) {
              final nome = (item['path'] ?? '').toString();
              final tamanho = (item['length'] as num?)?.toInt() ?? 0;
              if (_ehArquivoVideo(nome) && tamanho > maiorTamanho) {
                maiorTamanho = tamanho;
                melhorArquivo = item;
              }
            }
          }

          if (melhorArquivo == null) {
            for (final item in rawStats) {
              if (item is Map<String, dynamic>) {
                final tamanho = (item['length'] as num?)?.toInt() ?? 0;
                if (tamanho > maiorTamanho) {
                  maiorTamanho = tamanho;
                  melhorArquivo = item;
                }
              }
            }
          }

          if (melhorArquivo != null) {
            final fileIndex = (melhorArquivo['id'] as num?)?.toInt() ?? 1;
            final fileName = (melhorArquivo['path'] ?? 'Vídeo P2P').toString().split('/').last;

            final preloadClient = HttpClient()..connectionTimeout = const Duration(seconds: 4);
            try {
              final preloadReq = await preloadClient.getUrl(
                Uri.parse('$baseUrl/stream?link=$hash&index=$fileIndex&preload'),
              );
              final preloadRes = await preloadReq.close().timeout(const Duration(seconds: 4));
              await preloadRes.drain();
            } catch (_) {
            } finally {
              preloadClient.close(force: true);
            }

            final streamInfo = TorrentStreamInfo(
              playUrl: '$baseUrl/stream?link=$hash&index=$fileIndex&play',
              fileName: fileName,
              fileSizeBytes: maiorTamanho > 0 ? maiorTamanho : 0,
              activePeers: peers,
              totalSeeds: seeds,
              downloadSpeedBytes: speed,
            );

            onStatus?.call(
              'Iniciando ${streamInfo.fileName} (${streamInfo.tamanhoFormatado})\nPeers: $peers • Seeds: $seeds • ${streamInfo.velocidadeFormatada}',
            );
            return streamInfo;
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    ultimoErro = 'Timeout aguardando peers/metadados do torrent (45s).';
    return null;
  }
}
