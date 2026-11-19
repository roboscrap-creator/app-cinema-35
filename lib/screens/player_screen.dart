import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../services/torrserver_service.dart';

class PlayerScreen extends StatefulWidget {
  final ObraAgrupada obra;
  final FonteMidia fonteInicial;

  const PlayerScreen({
    super.key,
    required this.obra,
    required this.fonteInicial,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late FonteMidia _fonteAtual;
  late final Player _player;
  late final VideoController _videoController;
  WebViewController? _webController;

  StreamSubscription<String>? _erroSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration>? _durationSub;

  bool _carregando = true;
  double _progressoCarregamento = 0.0;
  Timer? _timerProgresso;
  Timer? _timeoutStream;
  String _mensagemCarregamento = '';
  String _badgeTorrent = '';
  bool _modoWeb = false;
  bool _telaFechada = false;
  bool _visualizacaoRegistrada = false;
  String? _erro;
  Duration? _posicaoPendente;
  final Set<String> _urlsJaTestadas = {};

  void _cancelarTimers() {
    _timerProgresso?.cancel();
    _timeoutStream?.cancel();
  }

  void _finalizarCarregamento() {
    _cancelarTimers();
    if (!mounted) return;
    setState(() {
      _progressoCarregamento = 1.0;
      _carregando = false;
    });
  }

  void _iniciarTimerProgresso({required bool isMagnet}) {
    _cancelarTimers();
    _timerProgresso = Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (!mounted || !_carregando) {
        t.cancel();
        return;
      }
      setState(() {
        final teto = isMagnet ? 0.90 : 0.94;
        if (_progressoCarregamento < teto) {
          final passo = isMagnet ? 0.008 : 0.04;
          _progressoCarregamento = (_progressoCarregamento + passo).clamp(0.0, teto);
        }
      });
    });

    _timeoutStream = Timer(Duration(seconds: isMagnet ? 45 : 20), () {
      if (mounted && _carregando && !_modoWeb && _erro == null) {
        _tentarProximoServidorOuFalhar(
          isMagnet
              ? 'Torrent sem seeds ativos no momento (45s). Tente outra fonte.'
              : 'Servidor demorou para responder (20s).',
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _fonteAtual = widget.fonteInicial;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 24 * 1024 * 1024,
        logLevel: MPVLogLevel.warn,
      ),
    );
    _videoController = VideoController(_player);

    _erroSub = _player.stream.error.listen((err) {
      if (_responderErroPlayer(err)) {
        _tentarProximoServidorOuFalhar('Falha no player: $err');
      }
    });

    _bufferingSub = _player.stream.buffering.listen((buf) {
      if (!buf && _carregando && !_modoWeb && _erro == null && _player.state.duration > Duration.zero) {
        _finalizarCarregamento();
      }
    });

    _durationSub = _player.stream.duration.listen((dur) {
      if (dur > Duration.zero) {
        if (!_visualizacaoRegistrada) {
          _visualizacaoRegistrada = true;
          SupabaseService.registrarVisualizacao(_fonteAtual.id);
        }
        if (_posicaoPendente != null) {
          final pos = _posicaoPendente!;
          _posicaoPendente = null;
          _player.seek(pos);
        }
        if (_carregando) {
          _finalizarCarregamento();
        }
      }
    });

    _iniciarStream(_fonteAtual.urlStream);
  }

  bool _responderErroPlayer(String err) {
    final l = err.toLowerCase();
    return l.contains('failed to open') ||
        l.contains('error opening') ||
        l.contains('unrecognized file format') ||
        l.contains('http error') ||
        l.contains('connection refused') ||
        l.contains('timed out');
  }

  void _tentarProximoServidorOuFalhar(String motivo) {
    _cancelarTimers();
    final backup = _fonteAtual.urlStreamBackup.trim();
    if (backup.isNotEmpty && !_urlsJaTestadas.contains(backup)) {
      _iniciarStream(backup);
      return;
    }

    final candidatos = widget.obra.fontes.where((f) {
      final mesmoEp = f.temporada == _fonteAtual.temporada &&
          f.episodio == _fonteAtual.episodio;
      return mesmoEp &&
          f.urlStream.trim().isNotEmpty &&
          !_urlsJaTestadas.contains(f.urlStream.trim());
    }).toList();

    if (candidatos.isNotEmpty) {
      final prox = candidatos.first;
      setState(() => _fonteAtual = prox);
      _iniciarStream(prox.urlStream);
      return;
    }

    if (!mounted) return;
    setState(() {
      _carregando = false;
      _modoWeb = false;
      _erro = motivo;
    });
  }

  String? _extrairYoutubeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if (host.contains('youtube.com') || host.contains('youtube-nocookie.com')) {
      if (uri.queryParameters['v'] != null) return uri.queryParameters['v'];
      if (uri.pathSegments.length >= 2 &&
          (uri.pathSegments[0] == 'embed' ||
              uri.pathSegments[0] == 'shorts' ||
              uri.pathSegments[0] == 'live')) {
        return uri.pathSegments[1];
      }
    }
    return null;
  }

  bool _ehPaginaWebEmbed(String url) {
    final l = url.toLowerCase();
    if (l.startsWith('magnet:?') ||
        l.contains('.m3u8') ||
        l.contains('.mp4') ||
        l.contains('.mkv') ||
        l.contains('.avi') ||
        l.contains('.ts')) {
      return false;
    }
    return l.contains('/embed') ||
        l.contains('player.') ||
        l.contains('streamtape') ||
        l.contains('dood') ||
        l.contains('mixdrop') ||
        l.contains('filemoon') ||
        l.contains('vidsrc') ||
        l.contains('drivedirect') ||
        l.contains('dailymotion.com/video/') ||
        l.contains('geo.dailymotion.com') ||
        l.contains('dai.ly/');
  }

  Future _resolverUrlHttp(String url, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      req.followRedirects = true;
      req.maxRedirects = 5;
      final res = await req.close().timeout(const Duration(seconds: 6));
      final finalUrl = res.redirects.isNotEmpty ? res.redirects.last.location.toString() : url;
      final contentType = (res.headers.contentType?.mimeType ?? '').toLowerCase();
      await res.drain();
      final isHtml = contentType.contains('text/html') || contentType.contains('application/xhtml');
      return {'url': finalUrl, 'isHtml': isHtml, 'status': res.statusCode, 'ok': true};
    } catch (e) {
      return {'url': url, 'isHtml': false, 'status': 0, 'ok': false, 'erro': e.toString()};
    } finally {
      client.close(force: true);
    }
  }

  void _abrirYoutubeNoWebView(String videoId) {
    _cancelarTimers();
    final html = '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no"><style>html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}iframe{width:100%;height:100%;border:0}</style></head><body><iframe src="https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&playsinline=1&rel=0&modestbranding=1" allow="autoplay; fullscreen; encrypted-media" allowfullscreen></iframe></body></html>';

    final wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _finalizarCarregamento(),
          onWebResourceError: (err) {
            if (err.isForMainFrame == true) {
              _tentarProximoServidorOuFalhar('Erro YouTube HTTP ${err.errorCode}.');
            }
          },
        ),
      )
      ..loadHtmlString(html, baseUrl: 'https://www.youtube-nocookie.com');

    SupabaseService.registrarVisualizacao(_fonteAtual.id);
    if (!mounted) return;
    setState(() {
      _webController = wc;
      _modoWeb = true;
      _erro = null;
      _carregando = false;
    });
  }

  void _abrirUrlNoWebView(String url) {
    _cancelarTimers();
    final wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _finalizarCarregamento(),
          onWebResourceError: (err) {
            if (err.isForMainFrame == true) {
              _tentarProximoServidorOuFalhar('Servidor web indisponivel (HTTP ${err.errorCode}).');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    SupabaseService.registrarVisualizacao(_fonteAtual.id);
    if (!mounted) return;
    setState(() {
      _webController = wc;
      _modoWeb = true;
      _erro = null;
      _carregando = false;
    });
  }

  
  Future<String?> _resolverViaTorBoxCloud(String magnet) async {
    try {
      final resp = await http
          .post(
            Uri.parse('https://roboscrap-backend-l9t8.onrender.com/stream-torbox'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'magnet': magnet}),
          )
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final url = (data['url'] ?? '').toString().trim();
        if (url.startsWith('http')) return url;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _iniciarStream(String url, {Duration? posicaoRetomar}) async {
    final cleanUrl = url.trim();
    _urlsJaTestadas.add(cleanUrl);
    final isMagnet = cleanUrl.toLowerCase().startsWith('magnet:?');

    setState(() {
      _carregando = true;
      _progressoCarregamento = 0.05;
      _badgeTorrent = '';
      _mensagemCarregamento = isMagnet
          ? 'Conectando motor P2P e buscando peers...'
          : 'Carregando ${widget.obra.titulo} (${_fonteAtual.badgeResumo})...';
      _modoWeb = false;
      _webController = null;
      _erro = null;
      _visualizacaoRegistrada = false;
      _posicaoPendente = posicaoRetomar;
    });

    _iniciarTimerProgresso(isMagnet: isMagnet);
    await _player.stop();

    String streamUrlFinal = cleanUrl;

    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      if (streamUrlFinal.contains('dailymotion')) 'Referer': 'https://www.dailymotion.com/',
      ..._fonteAtual.headers,
    };

    if (isMagnet) {
      if (mounted) {
        setState(() {
          _mensagemCarregamento = 'Conectando nuvem TorBox CDN...';
          _progressoCarregamento = 0.25;
        });
      }
      final torboxUrl = await _resolverViaTorBoxCloud(cleanUrl);
      if (_telaFechada || !mounted) return;

      if (torboxUrl != null) {
        streamUrlFinal = torboxUrl;
        if (mounted) {
          setState(() {
            _badgeTorrent = 'CLOUD CDN';
            _progressoCarregamento = 0.85;
            _mensagemCarregamento = 'Iniciando stream direto da nuvem...';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _mensagemCarregamento = 'Buscando peers no motor P2P local...';
          });
        }
        final torrentInfo = await TorrServerService.prepararMagnet(
        cleanUrl,
        cancelado: () => _telaFechada || !mounted,
        onProgress: (p) {
          if (mounted && p > _progressoCarregamento) {
            setState(() => _progressoCarregamento = p.clamp(0.0, 0.95));
          }
        },
        onStatus: (status) {
          if (mounted) setState(() => _mensagemCarregamento = status);
        },
      );

      if (_telaFechada || !mounted) return;

      if (torrentInfo == null) {
        final msgErro = TorrServerService.ultimoErro.isNotEmpty
            ? TorrServerService.ultimoErro
            : 'Motor TorrServer integrado nao respondeu.';
        _tentarProximoServidorOuFalhar(msgErro);
        return;
      }

        streamUrlFinal = torrentInfo.playUrl;
        if (mounted) {
          setState(() {
            _badgeTorrent = torrentInfo.viaCloudCache ? 'CLOUD CDN • INSTANTANEO' : 'P2P • TORRSERVER';
          });
        }
      }
    } else {
      final ytId = _extrairYoutubeId(cleanUrl);
      if (ytId != null) {
        _abrirYoutubeNoWebView(ytId);
        return;
      }
      if (cleanUrl.startsWith('http')) {
        final res = await _resolverUrlHttp(cleanUrl, headers);
        if (_telaFechada || !mounted) return;
        if (res['ok'] != true) {
          _tentarProximoServidorOuFalhar('Link offline ou dominio expirado.');
          return;
        }
        final resolved = (res['url'] ?? cleanUrl).toString();
        final isHtml = res['isHtml'] == true;
        if (isHtml || _ehPaginaWebEmbed(resolved)) {
          _abrirUrlNoWebView(resolved);
          return;
        }
        streamUrlFinal = resolved;
      } else if (_ehPaginaWebEmbed(cleanUrl)) {
        _abrirUrlNoWebView(cleanUrl);
        return;
      }
    }

    try {
      await _player.open(
        Media(streamUrlFinal, httpHeaders: headers),
        play: true,
      );
    } catch (e) {
      _tentarProximoServidorOuFalhar('Falha ao iniciar stream: $e');
    }
  }

  Future<void> _trocarFonte(FonteMidia novaFonte) async {
    if (novaFonte.id == _fonteAtual.id) return;
    final pos = _player.state.position;
    setState(() => _fonteAtual = novaFonte);
    await _iniciarStream(novaFonte.urlStream, posicaoRetomar: pos);
  }

  void _abrirSeletorFonteNoPlayer() {
    final opcoes = widget.obra.fontes
        .where((f) =>
            f.temporada == _fonteAtual.temporada &&
            f.episodio == _fonteAtual.episodio)
        .toList();
    final lista = opcoes.isNotEmpty ? opcoes : widget.obra.fontes;
    final audioTracks = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final subTracks = _player.state.tracks.subtitle
        .where((t) => t.id != 'auto')
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16181D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (audioTracks.isNotEmpty) ...[
                  const Text(
                    'Faixa de Audio (libmpv)',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ...audioTracks.map((t) {
                    final ativo = _player.state.track.audio.id == t.id;
                    final label = [t.title, t.language].where((s) => s != null && s.isNotEmpty).join(' • ');
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        ativo ? Icons.audiotrack : Icons.audiotrack_outlined,
                        color: ativo ? const Color(0xFF2196F3) : Colors.white54,
                      ),
                      title: Text(label.isEmpty ? 'Faixa ${t.id}' : label, style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        _player.setAudioTrack(t);
                        Navigator.pop(context);
                      },
                    );
                  }),
                  const Divider(color: Colors.white12),
                ],
                if (subTracks.isNotEmpty) ...[
                  const Text(
                    'Legendas Embutidas',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  ...subTracks.map((t) {
                    final ativo = _player.state.track.subtitle.id == t.id;
                    final label = t.id == 'no'
                        ? 'Desativada'
                        : [t.title, t.language].where((s) => s != null && s.isNotEmpty).join(' • ');
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        ativo ? Icons.subtitles : Icons.subtitles_outlined,
                        color: ativo ? const Color(0xFF2196F3) : Colors.white54,
                      ),
                      title: Text(label.isEmpty ? 'Legenda ${t.id}' : label, style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        _player.setSubtitleTrack(t);
                        Navigator.pop(context);
                      },
                    );
                  }),
                  const Divider(color: Colors.white12),
                ],
                const Text(
                  'Servidores e Resolucao',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...lista.take(10).map((f) {
                  final ativo = f.id == _fonteAtual.id;
                  final isTor = f.urlStream.trim().toLowerCase().startsWith('magnet:?');
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      ativo ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: ativo ? const Color(0xFF2196F3) : Colors.white54,
                    ),
                    title: Text('${f.tipoAudio} • ${f.resolucao}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      isTor ? 'TORRENT P2P / CLOUD' : 'Formato: ${f.formato.toUpperCase()}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _trocarFonte(f);
                    },
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cancelarTimers();
    _telaFechada = true;
    _erroSub?.cancel();
    _bufferingSub?.cancel();
    _durationSub?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _modoWeb && _webController != null
                ? WebViewWidget(controller: _webController!)
                : _erro != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                            const SizedBox(height: 8),
                            Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
                              onPressed: () {
                                _urlsJaTestadas.clear();
                                _iniciarStream(_fonteAtual.urlStream);
                              },
                              icon: const Icon(Icons.refresh, color: Colors.white),
                              label: const Text('Tentar Novamente', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      )
                    : Video(controller: _videoController),
          ),
          if (_carregando)
            Container(
              color: Colors.black54,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 76,
                        height: 76,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 76,
                              height: 76,
                              child: CircularProgressIndicator(
                                value: _progressoCarregamento > 0.01 ? _progressoCarregamento : null,
                                strokeWidth: 5.5,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
                              ),
                            ),
                            Text(
                              '${(_progressoCarregamento * 100).round().clamp(0, 100)}%',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _mensagemCarregamento,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.obra.titulo} ${_fonteAtual.etiquetaEpisodio}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_badgeTorrent.isNotEmpty)
                        Text(
                          _badgeTorrent,
                          style: const TextStyle(color: Color(0xFF64B5F6), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _abrirSeletorFonteNoPlayer,
                  icon: const Icon(Icons.subtitles, color: Colors.white, size: 18),
                  label: Text(_fonteAtual.badgeResumo, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
