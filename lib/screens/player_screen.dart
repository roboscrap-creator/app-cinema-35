import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../services/torrserver_service.dart';

class PlayerScreen extends StatefulWidget {
  final ObraAgrupada obra;
  final FonteMidia fonteInicial;

  const PlayerScreen({super.key, required this.obra, required this.fonteInicial});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late FonteMidia _fonteAtual;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  WebViewController? _webController;
  bool _carregando = true;
  String _mensagemCarregamento = '';
  String _badgeTorrent = '';
  bool _modoWeb = false;
  bool _telaFechada = false;
  String? _erro;
  final Set<String> _urlsJaTestadas = {};

  @override
  void initState() {
    super.initState();
    _fonteAtual = widget.fonteInicial;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _iniciarStream(_fonteAtual.urlStream);
  }

  String? _extrairYoutubeId(String url) {
    final m = RegExp(
      r'(?:youtube\.com/(?:watch\?v=|embed/|shorts/)|youtu\.be/)([A-Za-z0-9_-]{6,})',
    ).firstMatch(url.trim());
    return m?.group(1);
  }

  bool _ehPaginaWebEmbed(String url) {
    final u = url.trim().toLowerCase();
    return u.contains('blogger.com/video-play.mp4') ||
        u.contains('drive.google.com') ||
        u.contains('streamtape.') ||
        u.contains('mixdrop.') ||
        u.contains('dood');
  }

  void _tentarProximoServidorOuFalhar(String motivo) {
    final candidatos = widget.obra.fontes.where((f) {
      final mesmoEp = f.temporada == _fonteAtual.temporada && f.episodio == _fonteAtual.episodio;
      return mesmoEp && f.urlStream.trim().isNotEmpty && !_urlsJaTestadas.contains(f.urlStream.trim());
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

  void _abrirYoutubeNoWebView(String videoId) {
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
    iframe { width: 100%; height: 100%; border: 0; }
  </style>
</head>
<body>
  <iframe
    src="https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&playsinline=1&rel=0&modestbranding=1"
    allow="autoplay; encrypted-media; fullscreen; picture-in-picture"
    allowfullscreen>
  </iframe>
</body>
</html>
''';

    final wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _carregando = false);
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
    final wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _carregando = false);
          },
          onWebResourceError: (err) {
            if (err.isForMainFrame == true) {
              _tentarProximoServidorOuFalhar('Erro web HTTP ${err.errorCode}.');
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

  Future<VideoPlayerController> _criarEInicializarNativo(
    Uri uri,
    VideoFormat? fmt,
    Map<String, String> headers,
  ) async {
    final controller = VideoPlayerController.networkUrl(
      uri,
      formatHint: fmt,
      httpHeaders: headers,
    );
    await controller.initialize();
    return controller;
  }

  Future<void> _iniciarStream(String url, {Duration? posicaoRetomar}) async {
    final cleanUrl = url.trim();
    _urlsJaTestadas.add(cleanUrl);
    final isMagnet = cleanUrl.toLowerCase().startsWith('magnet:?');

    setState(() {
      _carregando = true;
      _badgeTorrent = '';
      _mensagemCarregamento = isMagnet
          ? 'Iniciando motor TorrServer integrado...'
          : 'Carregando ${widget.obra.titulo} (${_fonteAtual.badgeResumo})...';
      _modoWeb = false;
      _webController = null;
      _erro = null;
    });

    final oldChewie = _chewieController;
    final oldVideo = _videoController;
    _chewieController = null;
    _videoController = null;
    await oldChewie?.pause();
    oldChewie?.dispose();
    await oldVideo?.dispose();

    String streamUrlFinal = cleanUrl;

    if (isMagnet) {
      final torrentInfo = await TorrServerService.prepararMagnet(
        cleanUrl,
        cancelado: () => _telaFechada || !mounted,
        onStatus: (status) {
          if (mounted) setState(() => _mensagemCarregamento = status);
        },
      );

      if (_telaFechada || !mounted) return;

      if (torrentInfo == null) {
        setState(() {
          _carregando = false;
          _erro = TorrServerService.ultimoErro.isNotEmpty
              ? TorrServerService.ultimoErro
              : 'Motor TorrServer integrado não respondeu em 127.0.0.1:8090.';
        });
        return;
      }

      streamUrlFinal = torrentInfo.playUrl;
      if (mounted) {
        setState(() {
          _badgeTorrent = 'P2P • ${torrentInfo.tamanhoFormatado} • ${torrentInfo.velocidadeFormatada}';
        });
      }
    } else {
      final ytId = _extrairYoutubeId(cleanUrl);
      if (ytId != null) {
        _abrirYoutubeNoWebView(ytId);
        return;
      }
      if (_ehPaginaWebEmbed(cleanUrl)) {
        _abrirUrlNoWebView(cleanUrl);
        return;
      }
    }

    try {
      final uri = Uri.parse(streamUrlFinal);
      final lower = streamUrlFinal.toLowerCase();
      final VideoFormat? fmt = (lower.contains('.m3u8') || _fonteAtual.formato.toLowerCase() == 'hls')
          ? VideoFormat.hls
          : null;

      VideoPlayerController controller;
      try {
        controller = await _criarEInicializarNativo(uri, fmt, _fonteAtual.headers);
      } catch (_) {
        final vlcHeaders = {
          'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
          ..._fonteAtual.headers,
        };
        controller = await _criarEInicializarNativo(uri, fmt, vlcHeaders);
      }

      if (posicaoRetomar != null && posicaoRetomar > Duration.zero) {
        await controller.seekTo(posicaoRetomar);
      }

      final chewie = ChewieController(
        videoPlayerController: controller,
        autoPlay: true,
        looping: widget.obra.categoria == 'TV ao Vivo',
        isLive: widget.obra.categoria == 'TV ao Vivo',
        allowFullScreen: false,
        allowMuting: true,
        showControlsOnInitialize: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFF2196F3),
          handleColor: const Color(0xFF2196F3),
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white12,
        ),
      );

      SupabaseService.registrarVisualizacao(_fonteAtual.id);
      if (!mounted) return;
      setState(() {
        _videoController = controller;
        _chewieController = chewie;
        _carregando = false;
      });
    } catch (e) {
      if (_fonteAtual.urlStreamBackup.trim().isNotEmpty &&
          !_urlsJaTestadas.contains(_fonteAtual.urlStreamBackup.trim())) {
        return _iniciarStream(_fonteAtual.urlStreamBackup.trim(), posicaoRetomar: posicaoRetomar);
      }
      _tentarProximoServidorOuFalhar(
        isMagnet
            ? 'Sem seeds ativos no torrent ou formato MKV/AC3 incompatível com ExoPlayer ($e).'
            : 'Fonte offline no servidor de origem (404 / Stream indisponível).',
      );
    }
  }

  Future<void> _trocarFonte(FonteMidia novaFonte) async {
    if (novaFonte.id == _fonteAtual.id) return;
    final pos = _videoController?.value.position;
    setState(() => _fonteAtual = novaFonte);
    await _iniciarStream(novaFonte.urlStream, posicaoRetomar: pos);
  }

  void _abrirSeletorFonteNoPlayer() {
    final opcoes = widget.obra.fontes
        .where((f) => f.temporada == _fonteAtual.temporada && f.episodio == _fonteAtual.episodio)
        .toList();
    final lista = opcoes.isNotEmpty ? opcoes : widget.obra.fontes;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16181D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Selecionar Áudio e Resolução',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...lista.take(8).map((f) {
                final ativo = f.id == _fonteAtual.id;
                final isTor = f.urlStream.trim().toLowerCase().startsWith('magnet:?');
                return ListTile(
                  leading: Icon(
                    ativo ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: ativo ? const Color(0xFF2196F3) : Colors.white54,
                  ),
                  title: Text('${f.tipoAudio} • ${f.resolucao}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(isTor ? 'TORRENT P2P (TorrServer)' : 'Formato: ${f.formato.toUpperCase()}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
    );
  }

  @override
  void dispose() {
    _telaFechada = true;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opcoesMesmoItem = widget.obra.fontes
        .where((f) => f.temporada == _fonteAtual.temporada && f.episodio == _fonteAtual.episodio)
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _carregando
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF2196F3)),
                        const SizedBox(height: 14),
                        Text(
                          _mensagemCarregamento,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  )
                : _modoWeb && _webController != null
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
                        : _chewieController != null
                            ? Chewie(controller: _chewieController!)
                            : const SizedBox.shrink(),
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
                if (opcoesMesmoItem.length > 1)
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
