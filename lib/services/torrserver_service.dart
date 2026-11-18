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

  String get velocidadeFormatada {
    if (viaCloudCache) return 'CDN Cloud';
    if (downloadSpeedBytes <= 0) return 'P2P Direto';
    final mb = downloadSpeedBytes / (1024 * 1024);
    if (mb >= 1.0) return '${mb.toStringAsFixed(1)} MB/s';
    return '${(downloadSpeedBytes / 1024).toStringAsFixed(0)} KB/s';
  }

  String get tamanhoFormatado {
    if (fileSizeBytes <= 0) return '';
    final gb = fileSizeBytes / (1024 * 1024 * 1024);
    if (gb >= 1.0) return '${gb.toStringAsFixed(2)} GB';
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

class TorrServerService {
  static const MethodChannel _channel = MethodChannel('com.chiavegatti.cinema/torrserver');
  static const String baseUrl = 'http://127.0.0.1:8090';
  static Process? _process;
  static String ultimoErro = '';
  static String torboxApiKey = '';

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
      final paths = await _channel.invokeMapMethod<String, String>('getPaths');
      final nativeLibDir = paths?['nativeLibDir'] ?? '';
      final filesDir = paths?['filesDir'] ?? '';
      final binPath = '$nativeLibDir/libtorrserver.so';
      if (nativeLibDir.isEmpty || !await File(binPath).exists()) {
        ultimoErro = 'Binario TorrServer nao encontrado.';
        return false;
      }
      final dataDir = Directory('$filesDir/torrserver');
      if (!await dataDir.exists()) await dataDir.create(recursive: true);

      for (final args in [['-p', '8090', '-d', dataDir.path], ['--port', '8090', '--path', dataDir.path], <String>[]]) {
        _process?.kill();
        _process = await Process.start(binPath, args, workingDirectory: dataDir.path, environment: {'HOME': filesDir, 'TMPDIR': dataDir.path});
        for (int i = 0; i < 16; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (await _portaAberta()) { ultimoErro = ''; return true; }
        }
      }
      ultimoErro = 'Timeout na porta 8090.';
      return false;
    } catch (e) {
      ultimoErro = 'Erro ao iniciar TorrServer: $e';
      return false;
    }
  }

  static Future<void> _postJson(String endpoint, Map<String, dynamic> body) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await c.postUrl(Uri.parse('$baseUrl$endpoint'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain();
    } catch (_) {} finally { c.close(force: true); }
  }

  static String _base32ParaHex(String b32) {
    const alpha = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final clean = b32.toUpperCase().replaceAll('=', '');
    int bits = 0, val = 0;
    final bytes = <int>[];
    for (int i = 0; i < clean.length; i++) {
      final idx = alpha.indexOf(clean[i]);
      if (idx < 0) return b32.toLowerCase();
      val = (val << 5) | idx;
      bits += 5;
      if (bits >= 8) { bytes.add((val >> (bits - 8)) & 0xFF); bits -= 8; }
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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
    onProgress?.call(0.25);
    onStatus?.call('Conectando motor TorrServer...');
    if (!await garantirAtivo()) return null;
    if (cancelado != null && cancelado()) return null;

    unawaited(_postJson('/settings', {'action': 'set', 'sets': {'CacheSize': 67108864, 'ReaderReadAHead': 95, 'PreloadCache': 15, 'EnableDHT': true, 'EnableIPv6': false, 'RetrackersMode': 1, 'ConnectionsLimit': 150}}));
    unawaited(_postJson('/torrents', {'action': 'add', 'link': cleanMagnet, 'title': 'Stream', 'save_to_db': false}));

    onProgress?.call(0.75);
    onStatus?.call('Buscando peers e pre-carregando video...');
    return TorrentStreamInfo(
      playUrl: '$baseUrl/stream/video.mkv?link=${Uri.encodeComponent(cleanMagnet)}&index=1&play',
      fileName: 'Torrent P2P',
      fileSizeBytes: 0,
      activePeers: 0,
      totalSeeds: 0,
      downloadSpeedBytes: 0,
    );
  }
}
