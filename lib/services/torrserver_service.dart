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
  static bool _configurado = false;
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

  static Future<void> _aplicarConfiguracoes() async {
    if (_configurado) return;
    try {
      await _postJson('/settings', {
        'action': 'set',
        'sets': {
          'CacheSize': 67108864,
          'ReaderReadAHead': 95,
          'PreloadCache': 15,
          'UseDisk': false,
          'ForceEncrypt': false,
          'RetrackersMode': 1,
          'TorrentDisconnectTimeout': 30,
          'EnableIPv6': true,
          'DisableTCP': false,
          'DisableUTP': false,
          'DisableUPNP': false,
          'DisableDHT': false,
          'DisablePEX': false,
          'DisableUpload': false,
          'ConnectionsLimit': 120,
          'PeersListenPort': 0,
        },
      });
      _configurado = true;
    } catch (_) {}
  }

  static Future<bool> garantirAtivo() async {
    if (await _portaAberta()) {
      await _aplicarConfiguracoes();
      return true;
    }
    try {
      final paths = await _channel.invokeMapMethod('getPaths');
      final nativeLibDir = (paths?['nativeLibDir'] ?? '').toString();
      final filesDir = (paths?['filesDir'] ?? '').toString();
      final binPath = '$nativeLibDir/libtorrserver.so';
      if (nativeLibDir.isEmpty || !await File(binPath).exists()) {
        ultimoErro = 'Binario TorrServer nao encontrado em $binPath.';
        return false;
      }
      final dataDir = Directory('$filesDir/torrserver');
      if (!await dataDir.exists()) await dataDir.create(recursive: true);

      try {
        await File('${dataDir.path}/resolv.conf').writeAsString('nameserver 8.8.8.8\nnameserver 1.1.1.1\n');
      } catch (_) {}

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
          environment: {
            'HOME': filesDir,
            'TMPDIR': dataDir.path,
            'RES_OPTIONS': 'ndots:0',
            'GODEBUG': 'netdns=go',
          },
        );
        for (int i = 0; i < 16; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (await _portaAberta()) {
            ultimoErro = '';
            await _aplicarConfiguracoes();
            return true;
          }
        }
      }
      ultimoErro = 'Timeout ao subir TorrServer na porta 8090.';
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

  static Future> _baixarTorrentCacheComDiag(String hashHex) async {
    final hUpper = hashHex.toUpperCase();
    final urls = [
      'https://itorrents.org/torrent/$hUpper.torrent',
      'https://torrage.info/torrent.php?h=$hUpper',
      'https://btcache.me/torrent/$hUpper',
    ];
    final logs = <String>[];
    for (final u in urls) {
      final host = Uri.parse(u).host;
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      try {
        final req = await c.getUrl(Uri.parse(u));
        req.headers.set('User-Agent', 'Mozilla/5.0');
        final res = await req.close().timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final bytes = await res.fold<List<int>>([], (prev, el) => prev..addAll(el));
          if (bytes.length > 100 && bytes.first == 100) {
            return {'bytes': bytes, 'diag': '$host:200(${bytes.length}B)'};
          }
          logs.add('$host:200(invalido)');
        } else {
          await res.drain();
          logs.add('$host:${res.statusCode}');
        }
      } catch (e) {
        logs.add('$host:erro');
      } finally {
        c.close(force: true);
      }
    }
    return {'bytes': null, 'diag': logs.join(', ')};
  }

  static Future<bool> _uploadTorrentParaServidor(List<int> bytes, String hashHex) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      const boundary = '----TorrServerBoundary7MA4YWxkTrZu0gW';
      final req = await c.postUrl(Uri.parse('$baseUrl/torrent/upload'));
      req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      final header = '--$boundary\r\n'
          'Content-Disposition: form-data; name="file"; filename="$hashHex.torrent"\r\n'
          'Content-Type: application/x-bittorrent\r\n\r\n';
      const footer = '\r\n--$boundary--\r\n';
      req.add(utf8.encode(header));
      req.add(bytes);
      req.add(utf8.encode(footer));
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
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

  static Future<String> _enriquecerMagnetComIps(String magnet) async {
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
      'udp://tracker.bittor.pw:1337/announce',
      'udp://exodus.desync.com:6969/announce',
    ];
    final sb = StringBuffer(clean);
    for (final tr in trackers) {
      if (!clean.toLowerCase().contains(Uri.encodeComponent(tr).toLowerCase())) {
        sb.write('&tr=${Uri.encodeComponent(tr)}');
      }
      try {
        final uri = Uri.parse(tr);
        if (InternetAddress.tryParse(uri.host) == null) {
          final ips = await InternetAddress.lookup(uri.host).timeout(const Duration(seconds: 2));
          if (ips.isNotEmpty) {
            final ipUrl = '${uri.scheme}://${ips.first.address}:${uri.port}${uri.path}';
            sb.write('&tr=${Uri.encodeComponent(ipUrl)}');
          }
        }
      } catch (_) {}
    }
    return sb.toString();
  }

  static Future<TorrentStreamInfo?> prepararMagnet(
    String magnetUrl, {
    void Function(String)? onStatus,
    void Function(double)? onProgress,
    bool Function()? cancelado,
  }) async {
    onProgress?.call(0.12);
    onStatus?.call('Resolvendo DNS dos trackers...');
    final cleanMagnet = await _enriquecerMagnetComIps(magnetUrl);
    final hash = _extrairHash(cleanMagnet);

    onProgress?.call(0.20);
    onStatus?.call('Iniciando motor TorrServer...');
    if (!await garantirAtivo()) return null;
    if (cancelado != null && cancelado()) return null;

    onProgress?.call(0.28);
    onStatus?.call('Consultando cache .torrent...');
    bool subiuTorrent = false;
    String diagCache = 'hash_invalido';
    if (hash.length == 40) {
      final cacheRes = await _baixarTorrentCacheComDiag(hash);
      diagCache = (cacheRes['diag'] ?? '').toString();
      final torrentBytes = cacheRes['bytes'] as List<int>?;
      if (torrentBytes != null) {
        subiuTorrent = await _uploadTorrentParaServidor(torrentBytes, hash);
      }
    }

    if (!subiuTorrent) {
      await _postJson('/torrents', {
        'action': 'add',
        'link': cleanMagnet,
        'title': 'Stream',
        'save_to_db': false,
      });
    }

    int fileId = 1;
    String fileName = 'video.mkv';
    int fileSize = 0;
    bool encontrouArquivo = false;
    String ultimoStat = 'sem_resposta';
    int ultPeers = 0;
    int ultSeeds = 0;
    int ultTotal = 0;

    for (int i = 0; i < 40; i++) {
      if (cancelado != null && cancelado()) return null;
      await Future.delayed(const Duration(milliseconds: 500));
      onProgress?.call((0.35 + (i * 0.014)).clamp(0.35, 0.88));
      final info = await _postJson('/torrents', {'action': 'get', 'hash': hash});
      if (info is Map) {
        ultimoStat = (info['stat_string'] ?? info['stat'] ?? 'desconhecido').toString();
        ultPeers = (info['active_peers'] is int) ? info['active_peers'] as int : 0;
        ultSeeds = (info['connected_seeders'] is int) ? info['connected_seeders'] as int : 0;
        ultTotal = (info['total_peers'] is int) ? info['total_peers'] as int : 0;
      }
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
      onStatus?.call('Buscando metadados ($ultimoStat • peers: $ultPeers/$ultTotal)...');
    }

    if (!encontrouArquivo) {
      ultimoErro = 'Sem metadados/peers.\nCache: $diagCache\nMotor: $ultimoStat (peers: $ultPeers/$ultTotal, seeds: $ultSeeds)\nHash: $hash';
      return null;
    }

    onProgress?.call(0.92);
    onStatus?.call('Iniciando reproducao de $fileName...');
    return TorrentStreamInfo(
      playUrl: '$baseUrl/play/$hash/$fileId',
      fileName: fileName,
      fileSizeBytes: fileSize,
      activePeers: ultPeers > 0 ? ultPeers : 1,
      totalSeeds: ultSeeds > 0 ? ultSeeds : 1,
      downloadSpeedBytes: 0,
    );
  }
}
}
