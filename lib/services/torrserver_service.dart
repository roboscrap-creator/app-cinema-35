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
  final bool viaCloudCache;

  const TorrentStreamInfo({
    required this.playUrl,
    required this.fileName,
    required this.fileSizeBytes,
    required this.activePeers,
    required this.totalSeeds,
    required this.downloadSpeedBytes,
    this.viaCloudCache = false,
  });
}

class TorrServerService {
  static const MethodChannel _channel = MethodChannel('com.chiavegatti.cinema/torrserver');
  static const String baseUrl = 'http://127.0.0.1:8090';
  static Process? _process;
  static String ultimoErro = '';

  static Future<bool> _portaAberta() async {
    try {
      final s = await Socket.connect('127.0.0.1', 8090, timeout: const Duration(milliseconds: 350));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> garantirAtivo() async {
    if (await _portaAberta()) return true;
    try {
      final paths = await _channel.invokeMapMethod('getPaths');
      final nativeLibDir = (paths?['nativeLibDir'] ?? '').toString();
      final filesDir = (paths?['filesDir'] ?? '').toString();
      final binPath = '$nativeLibDir/libtorrserver.so';
      if (nativeLibDir.isEmpty || !await File(binPath).exists()) {
        ultimoErro = 'Binario TorrServer nao encontrado.';
        return false;
      }
      final dataDir = Directory('$filesDir/torrserver');
      if (!await dataDir.exists()) await dataDir.create(recursive: true);

      final tentativas = [
        ['-p', '8090', '-d', dataDir.path],
        ['--port', '8090', '--path', dataDir.path],
        ['']..clear(),
      ];

      for (final args in tentativas) {
        _process?.kill();
        _process = await Process.start(
          binPath,
          args,
          workingDirectory: dataDir.path,
          environment: {'HOME': filesDir, 'TMPDIR': dataDir.path},
        );
        for (int i = 0; i < 16; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (await _portaAberta()) {
            ultimoErro = '';
            return true;
          }
        }
      }
      ultimoErro = 'Timeout na porta 8090.';
      return false;
    } catch (e) {
      ultimoErro = 'Erro ao iniciar TorrServer: $e';
      return false;
    }
  }

  static Future _postJson(String endpoint, Map body) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await c.postUrl(Uri.parse('$baseUrl$endpoint'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 5));
      final txt = await utf8.decoder.bind(res).join();
      if (txt.trim().startsWith('{')) return jsonDecode(txt);
    } catch (_) {} finally {
      c.close(force: true);
    }
    return null;
  }

  static String _base32ParaHex(String b32) {
    const alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final clean = b32.toUpperCase().replaceAll('=', '');
    int bits = 0, val = 0;
    final bytes = [];
    for (int i = 0; i < clean.length; i++) {
      final idx = alpha.indexOf(clean[i]);
      if (idx < 0) return b32.toLowerCase();
      val = (val << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        bytes.add((val >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return bytes.map((b) => (b as int).toRadixString(16).padLeft(2, '0')).join();
  }

  static String _extrairHash(String magnet) {
    final m = RegExp(r'btih:([a-zA-Z0-9]{32,40})', caseSensitive: false).firstMatch(magnet);
    if (m == null) return '';
    final raw = m.group(1)!;
    return raw.length == 32 ? _base32ParaHex(raw) : raw.toLowerCase();
  }

  static String _enriquecerMagnet(String magnet) {
    var clean = magnet.trim().replaceFirstMapped(
      RegExp(r'(btih:)([a-zA-Z2-7]{32})(?=&|$)', caseSensitive: false),
      (m) => '${m.group(1)}${_base32ParaHex(m.group(2)!)}',
    );
    const trackers = [
      'http://tracker.opentrackr.org:1337/announce',
      'https://tracker.tamersunion.org:443/announce',
      'https://tracker.loligirl.cn:443/announce',
      'https://tracker.gbitt.info:443/announce',
      'http://93.158.213.92:1337/announce',
      'udp://tracker.opentrackr.org:1337/announce',
      'udp://93.158.213.92:1337/announce',
      'udp://open.stealth.si:80/announce',
      'udp://tracker.torrent.eu.org:451/announce',
    ];
    final sb = StringBuffer(clean);
    for (final tr in trackers) {
      if (!clean.toLowerCase().contains(Uri.encodeComponent(tr).toLowerCase())) {
        sb.write('&tr=${Uri.encodeComponent(tr)}');
      }
    }
    return sb.toString();
  }

  static Future<TorrentStreamInfo?> prepararMagnet(
    String magnetUrl, {
    void Function(String)? onStatus,
    void Function(double)? onProgress,
    bool Function()? cancelado,
  }) async {
    final cleanMagnet = _enriquecerMagnet(magnetUrl);
    final hash = _extrairHash(cleanMagnet);
    onProgress?.call(0.20);
    onStatus?.call('Iniciando motor TorrServer...');
    if (!await garantirAtivo()) return null;
    if (cancelado != null && cancelado()) return null;

    await _postJson('/torrents', {
      'action': 'add',
      'link': cleanMagnet,
      'title': 'Stream',
      'save_to_db': false,
    });

    int fileId = 1;
    String fileName = 'video.mkv';
    int fileSize = 0;
    bool encontrouArquivo = false;

    for (int i = 0; i < 40; i++) {
      if (cancelado != null && cancelado()) return null;
      await Future.delayed(const Duration(milliseconds: 500));
      onProgress?.call((0.25 + (i * 0.015)).clamp(0.25, 0.85));
      final info = await _postJson('/torrents', {'action': 'get', 'hash': hash});
      final files = info is Map ? info['file_stats'] : null;
      if (files is List && files.isNotEmpty) {
        Map? maior;
        for (final f in files) {
          if (f is Map) {
            final p = (f['path'] ?? '').toString().toLowerCase();
            final ehVid = p.endsWith('.mkv') || p.endsWith('.mp4') || p.endsWith('.avi') || p.endsWith('.ts');
            if (ehVid && (maior == null || (f['length'] ?? 0) > (maior['length'] ?? 0))) {
              maior = f;
            }
          }
        }
        maior ??= files.first as Map;
        fileId = (maior['id'] is int) ? maior['id'] as int : 1;
        fileName = (maior['path'] ?? 'video.mkv').toString().split('/').last;
        fileSize = (maior['length'] is int) ? maior['length'] as int : 0;
        encontrouArquivo = true;
        break;
      }
      final peers = info is Map ? (info['active_peers'] ?? 0) : 0;
      onStatus?.call('Buscando metadados do torrent (peers: $peers)...');
    }

    if (!encontrouArquivo) {
      ultimoErro = 'Torrent sem peers para baixar metadados no momento.';
      return null;
    }

    onProgress?.call(0.92);
    onStatus?.call('Iniciando reproducao de $fileName...');
    return TorrentStreamInfo(
      playUrl: '$baseUrl/play/$hash/$fileId',
      fileName: fileName,
      fileSizeBytes: fileSize,
      activePeers: 1,
      totalSeeds: 1,
      downloadSpeedBytes: 0,
    );
  }
}
