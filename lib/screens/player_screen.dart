import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';

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
  bool _carregando = true;
  String? _erro;
  bool _tentouBackup = false;

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

  Future<void> _iniciarStream(String url, {Duration? posicaoRetomar}) async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    final oldChewie = _chewieController;
    final oldVideo = _videoController;
    _chewieController = null;
    _videoController = null;
    await oldChewie?.pause();
    oldChewie?.dispose();
    await oldVideo?.dispose();

    try {
      final headers = <String, String>{
        'User-Agent': 'VLC/3.0.18 LibVLC/3.0.18',
        ..._fonteAtual.headers,
      };
      final controller = VideoPlayerController.networkUrl(Uri.parse(url), httpHeaders: headers);
      await controller.initialize();
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
          playedColor: const Color(0xFFE50914),
          handleColor: const Color(0xFFE50914),
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
      if (!_tentouBackup && _fonteAtual.urlStreamBackup.trim().isNotEmpty) {
        _tentouBackup = true;
        return _iniciarStream(_fonteAtual.urlStreamBackup.trim(), posicaoRetomar: posicaoRetomar);
      }
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Falha ao reproduzir este link.\nTroque o áudio/qualidade no botão acima.';
      });
    }
  }

  Future<void> _trocarFonte(FonteMidia novaFonte) async {
    if (novaFonte.id == _fonteAtual.id) return;
    final pos = _videoController?.value.position;
    setState(() {
      _fonteAtual = novaFonte;
      _tentouBackup = false;
    });
    await _iniciarStream(novaFonte.urlStream, posicaoRetomar: pos);
  }

  void _abrirSeletorFonteNoPlayer() {
    final opcoes = widget.obra.categoria == 'Série'
        ? widget.obra.fontes
            .where((f) => f.temporada == _fonteAtual.temporada && f.episodio == _fonteAtual.episodio)
            .toList()
        : widget.obra.fontes;

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
              ...opcoes.map((f) {
                final ativo = f.id == _fonteAtual.id;
                return ListTile(
                  leading: Icon(
                    ativo ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: ativo ? const Color(0xFFE50914) : Colors.white54,
                  ),
                  title: Text('${f.tipoAudio} • ${f.resolucao}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text('Formato: ${f.formato.toUpperCase()}',
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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opcoesMesmoItem = widget.obra.categoria == 'Série'
        ? widget.obra.fontes
            .where((f) => f.temporada == _fonteAtual.temporada && f.episodio == _fonteAtual.episodio)
            .toList()
        : widget.obra.fontes;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _carregando
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFFE50914)),
                      const SizedBox(height: 12),
                      Text('Carregando ${widget.obra.titulo} (${_fonteAtual.badgeResumo})...',
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  )
                : _erro != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
                          const SizedBox(height: 10),
                          Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                            onPressed: () => _iniciarStream(_fonteAtual.urlStream),
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            label: const Text('Tentar Novamente', style: TextStyle(color: Colors.white)),
                          ),
                        ],
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
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.obra.titulo} ${_fonteAtual.etiquetaEpisodio}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                        ),
                      ),
                      Text(_fonteAtual.badgeResumo,
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (opcoesMesmoItem.length > 1)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.white30),
                    ),
                    onPressed: _abrirSeletorFonteNoPlayer,
                    icon: const Icon(Icons.subtitles, size: 18, color: Colors.amberAccent),
                    label: Text('Áudio / Qualidade (${opcoesMesmoItem.length})',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
