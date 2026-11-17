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
EOFcat << 'EOF' >> lib/services/torrserver_service.dart

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
      if (!await File(binPath).exists()) {
        ultimoErro = 'Binário não encontrado em: $binPath';
        return false;
      }
      final dataDir = Directory('$filesDir/torrserver');
      if (!await dataDir.exists()) await dataDir.create(recursive: true);

      final tentativas = [
        ['--port', '8090', '--path', dataDir.path, '--rdb'],
        ['-p', '8090', '-d', dataDir.path],
      ];
      final logs = <String>[];
      for (final args in tentativas) {
        _process?.kill();
        _process = null;
        logs.clear();
        int? exitCode;
        _process = await Process.start(
          binPath,
          args,
          workingDirectory: dataDir.path,
          environment: {'HOME': filesDir, 'TMPDIR': dataDir.path},
        );
        _process!.stdout.transform(utf8.decoder).listen((d) {
          if (d.trim().isNotEmpty && logs.length < 12) logs.add(d.trim());
        });
        _process!.stderr.transform(utf8.decoder).listen((d) {
          if (d.trim().isNotEmpty && logs.length < 12) logs.add(d.trim());
        });
        _process!.exitCode.then((c) => exitCode = c);
        for (int i = 0; i < 16; i++) {
          await Future.delayed(const Duration(milliseconds: 250));
          if (await _portaAberta()) {
            ultimoErro = '';
            return true;
          }
          if (exitCode != null) break;
        }
      }
      ultimoErro = logs.isNotEmpty ? 'TorrServer: ${logs.join(" | ")}' : 'Timeout porta 8090 ($binPath)';
      return false;
    } catch (e) {
      ultimoErro = 'Falha processo: $e';
      return false;
    }
  }
EOFcat << 'EOF' >> lib/services/torrserver_service.dart

  static Future?> _postJson(String ep, Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl$ep'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final raw = await res.transform(utf8.decoder).join();
      if (raw.trim().isEmpty) return null;
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static bool _ehVideo(String p) {
    final l = p.toLowerCase();
    if (l.contains('sample')) return false;
    return l.endsWith('.mp4') || l.endsWith('.mkv') || l.endsWith('.avi') || l.endsWith('.mov') || l.endsWith('.webm') || l.endsWith('.ts') || l.endsWith('.m4v');
  }

  static Future<TorrentStreamInfo?> prepararMagnet(
    String magnetUrl, {
    void Function(String status)? onStatus,
    bool Function()? cancelado,
  }) async {
    if (!await garantirAtivo()) return null;
    onStatus?.call('Adicionando magnet ao TorrServer...');
    final addResp = await _postJson('/torrents', {
      'action': 'add',
      'link': magnetUrl.trim(),
      'title': 'Cinema Stream',
      'save_to_db': false,
    });
    final hash = (addResp?['hash'] ?? '').toString().trim();
    if (hash.isEmpty) {
      final enc = Uri.encodeComponent(magnetUrl.trim());
      return TorrentStreamInfo(
        playUrl: '$baseUrl/stream?link=$enc&index=1&play',
        fileName: 'Stream P2P',
        fileSizeBytes: 0,
        activePeers: 0,
        totalSeeds: 0,
        downloadSpeedBytes: 0,
      );
    }

    for (int t = 0; t < 90; t++) {
      if (cancelado != null && cancelado()) return null;
      final info = await _postJson('/torrents', {'action': 'get', 'hash': hash});
      if (info != null) {
        final peers = (info['active_peers'] as num?)?.toInt() ?? 0;
        final seeds = (info['connected_seeders'] as num?)?.toInt() ?? 0;
        final speed = (info['download_speed'] as num?)?.toDouble() ?? 0.0;
        final stats = info['file_stats'];
        onStatus?.call('Buscando metadados P2P...\nPeers: $peers • Seeds: $seeds • Vel: ${(speed / 1024).toStringAsFixed(0)} KB/s');

        if (stats is List && stats.isNotEmpty) {
          Map<String, dynamic>? melhor;
          int maior = -1;
          for (final item in stats) {
            if (item is Map<String, dynamic>) {
              final nome = (item['path'] ?? '').toString();
              final tam = (item['length'] as num?)?.toInt() ?? 0;
              if (_ehVideo(nome) && tam > maior) {
                maior = tam;
                melhor = item;
              }
            }
          }
          if (melhor == null) {
            for (final item in stats) {
              if (item is Map<String, dynamic>) {
                final tam = (item['length'] as num?)?.toInt() ?? 0;
                if (tam > maior) {
                  maior = tam;
                  melhor = item;
                }
              }
            }
          }
          if (melhor != null) {
            final fid = (melhor['id'] as num?)?.toInt() ?? 1;
            final fname = (melhor['path'] ?? 'Vídeo P2P').toString().split('/').last;
            final c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
            try {
              final req = await c.getUrl(Uri.parse('$baseUrl/stream?link=$hash&index=$fid&preload'));
              final res = await req.close().timeout(const Duration(seconds: 4));
              await res.drain();
            } catch (_) {
            } finally {
              c.close(force: true);
            }
            final si = TorrentStreamInfo(
              playUrl: '$baseUrl/stream?link=$hash&index=$fid&play',
              fileName: fname,
              fileSizeBytes: maior > 0 ? maior : 0,
              activePeers: peers,
              totalSeeds: seeds,
              downloadSpeedBytes: speed,
            );
            onStatus?.call('Iniciando ${si.fileName} (${si.tamanhoFormatado})\nPeers: $peers • Seeds: $seeds • ${si.velocidadeFormatada}');
            return si;
          }
        }
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    ultimoErro = 'Timeout aguardando peers/metadados (45s).';
    return null;
  }
}
