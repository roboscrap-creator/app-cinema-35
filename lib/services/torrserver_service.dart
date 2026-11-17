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
      if (!await File(binPath).exists()) {
        ultimoErro = 'Binário não encontrado em: $binPath';
        return false;
      }
      final dataDir = Directory('$filesDir/torrserver');
      if (!await dataDir.exists()) await dataDir.create(recursive: true);

      final tentativasArgs = <List<String>>[
        ['-p', '8090', '-d', dataDir.path],
        ['--port', '8090', '--path', dataDir.path],
        <String>[],
      ];
      final logs = <String>[];

      for (final args in tentativasArgs) {
        _process?.kill();
        _process = null;
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
          ? 'TorrServer encerrou: ${logs.join(" | ")}'
          : 'Timeout na porta 8090 ($binPath).';
      return false;
    } catch (e) {
      ultimoErro = 'Falha ao iniciar processo: $e';
      return false;
    }
  }

  static Future<dynamic> _postJson(String endpoint, Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl$endpoint'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final raw = await res.transform(utf8.decoder).join();
      if (raw.trim().isEmpty) return null;
      return jsonDecode(raw);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String _base32ParaHex(String base32) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final clean = base32.toUpperCase().replaceAll('=', '');
    int bits = 0;
    int value = 0;
    final bytes = <int>[];
    for (int i = 0; i < clean.length; i++) {
      final idx = alphabet.indexOf(clean[i]);
      if (idx < 0) return base32.toLowerCase();
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        bytes.add((value >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toLowerCase();
  }

  static String? _extrairHashHexDoMagnet(String magnet) {
    final m = RegExp(r'btih:([a-fA-F0-9]{40}|[a-zA-Z2-7]{32})', caseSensitive: false).firstMatch(magnet);
    final raw = m?.group(1);
    if (raw == null) return null;
    return raw.length == 32 ? _base32ParaHex(raw) : raw.toLowerCase();
  }

  static String _normalizarMagnetParaHex(String magnet) {
    return magnet.replaceFirstMapped(
      RegExp(r'(btih:)([a-zA-Z2-7]{32})(?=&|$)', caseSensitive: false),
      (m) => '${m.group(1)}${_base32ParaHex(m.group(2)!)}',
    );
  }

  static bool _ehArquivoVideo(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('sample')) return false;
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.m4v');
  }

  static const List<String> _trackersPublicos = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://93.158.213.92:1337/announce',
    'udp://185.148.3.231:80/announce',
    'udp://185.230.4.150:1337/announce',
    'udp://208.83.20.20:6969/announce',
    'udp://107.189.11.58:6969/announce',
    'http://93.158.213.92:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://tracker.bittor.pw:1337/announce',
    'udp://public.popcorn-tracker.org:6969/announce',
    'udp://tracker.dler.org:6969/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://open.demonii.com:1337/announce',
    'http://tracker.opentrackr.org:1337/announce',
  ];

  static String _enriquecerMagnetComTrackers(String magnet) {
    final clean = _normalizarMagnetParaHex(magnet.trim());
    if (!clean.toLowerCase().startsWith('magnet:?')) return clean;
    final lower = clean.toLowerCase();
    final sb = StringBuffer(clean);
    for (final tr in _trackersPublicos) {
      final encoded = Uri.encodeComponent(tr);
      if (!lower.contains(encoded.toLowerCase()) && !lower.contains(tr.toLowerCase())) {
        sb.write('&tr=$encoded');
      }
    }
    return sb.toString();
  }

  static Future<TorrentStreamInfo?> prepararMagnet(
    String magnetUrl, {
    void Function(String statusTelemetria)? onStatus,
    void Function(double progresso)? onProgress,
    bool Function()? cancelado,
  }) async {
    final ativo = await garantirAtivo();
    if (!ativo) return null;

    final cleanMagnet = _enriquecerMagnetComTrackers(magnetUrl);
    final hashPrevio = _extrairHashHexDoMagnet(cleanMagnet);
    if (hashPrevio != null && hashPrevio.isNotEmpty) {
      await _postJson('/torrents', {'action': 'rem', 'hash': hashPrevio});
    }
    onProgress?.call(0.08);
    onStatus?.call('Ativando DHT/P2P e trackers...');

    await _postJson('/settings', {
      'action': 'set',
      'sets': {
        'EnableDHT': true,
        'DisablePEX': false,
        'DisableUTP': false,
        'DisableUPNP': false,
        'EnableIPv6': false,
        'RetrackersMode': 1,
        'TorrentDisconnectTimeout': 60,
        'ConnectionsLimit': 120,
      },
    });

    final addResp = await _postJson('/torrents', {
      'action': 'add',
      'link': cleanMagnet,
      'title': 'Cinema Stream',
      'poster': '',
      'save_to_db': true,
    });

    String hash = '';
    if (addResp is Map<String, dynamic>) {
      hash = (addResp['hash'] ?? '').toString().trim().toLowerCase();
      if (hash.length == 32) hash = _base32ParaHex(hash);
    }
    if (hash.isEmpty) hash = _extrairHashHexDoMagnet(cleanMagnet) ?? '';

    if (hash.isEmpty) {
      ultimoErro = 'Não foi possível extrair o hash do magnet link.';
      return null;
    }

    unawaited(() async {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final r = await c.getUrl(Uri.parse('$baseUrl/stream?link=$hash&index=1&preload'));
        final resp = await r.close().timeout(const Duration(seconds: 12));
        await resp.drain();
      } catch (_) {
      } finally {
        c.close(force: true);
      }
    }());

    String ultimoStat = 'sem resposta';
    int ultimoPeers = 0;
    int ultimoSeeds = 0;

    for (int tentativa = 0; tentativa < 180; tentativa++) {
      if (cancelado != null && cancelado()) return null;

      dynamic info = await _postJson('/torrents', {'action': 'get', 'hash': hash});
      if (info == null) {
        final lista = await _postJson('/torrents', {'action': 'list'});
        if (lista is List) {
          for (final item in lista) {
            if (item is Map<String, dynamic> &&
                (item['hash'] ?? '').toString().toLowerCase() == hash) {
              info = item;
              break;
            }
          }
        }
      }

      if (info is Map<String, dynamic>) {
        final peers = (info['active_peers'] as num?)?.toInt() ?? 0;
        final seeds = (info['connected_seeders'] as num?)?.toInt() ?? 0;
        final speed = (info['download_speed'] as num?)?.toDouble() ?? 0.0;
        final rawStats = info['file_stats'];

        final statStr = (info['stat_string'] ?? '').toString().trim();
        final totalPeers = (info['total_peers'] as num?)?.toInt() ?? peers;
        if (statStr.isNotEmpty) ultimoStat = statStr;
        ultimoPeers = totalPeers;
        ultimoSeeds = seeds;
        final speedKb = (speed / 1024).toStringAsFixed(0);
        final pctBusca = (0.10 +
                (tentativa / 180.0) * 0.40 +
                (totalPeers > 0 ? 0.12 : 0.0) +
                (seeds > 0 ? 0.13 : 0.0))
            .clamp(0.10, 0.72);
        onProgress?.call(pctBusca);
        final estadoTxt = statStr.isNotEmpty ? statStr : 'Buscando metadados P2P';
        onStatus?.call('$estadoTxt...\nPeers: $peers/$totalPeers • Seeds: $seeds • Vel: $speedKb KB/s');

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

            onProgress?.call(0.80);
            onStatus?.call('Fazendo pré-buffer de $fileName...');
            final preloadClient = HttpClient()..connectionTimeout = const Duration(seconds: 6);
            try {
              final preloadReq = await preloadClient.getUrl(
                Uri.parse('$baseUrl/stream?link=$hash&index=$fileIndex&preload'),
              );
              final preloadRes = await preloadReq.close().timeout(const Duration(seconds: 10));
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

            onProgress?.call(0.95);
            onStatus?.call(
              'Iniciando ${streamInfo.fileName} (${streamInfo.tamanhoFormatado})\nPeers: $peers • Seeds: $seeds • ${streamInfo.velocidadeFormatada}',
            );
            return streamInfo;
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    ultimoErro = 'Timeout P2P (90s) | Estado: $ultimoStat | Peers: $ultimoPeers | Seeds: $ultimoSeeds | Hash: $hash';
    return null;
  }
}
