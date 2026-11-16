import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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

  Future<Uri> _extrairStreamReal(Uri inicial, Map<String, String> headers) async {
    final urlStr = inicial.toString();
    if (urlStr.contains('blogger.com/video-play.mp4') || urlStr.contains('blogspot.com')) {
      try {
        final resp = await http.get(inicial, headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Referer': 'https://www.blogger.com/',
        }).timeout(const Duration(seconds: 10));
        final body = resp.body;
        final matches = RegExp(r'https?:\\?/\\?/[^"\\\s]+googlevideo\.com\\?/videoplayback[^"\\\s]+').allMatches(body);
        if (matches.isNotEmpty) {
          var raw = matches.last.group(0)!;
          raw = raw.replaceAll(r'\u0026', '&').replaceAll(r'\u003d', '=').replaceAll(r'\/', '/');
          return Uri.parse(raw);
        }
        final playUrl = RegExp(r'"play_url"\s*:\s*"([^"]+)"').firstMatch(body);
        if (playUrl != null) {
          final decoded = jsonDecode('"${playUrl.group(1)!}"') as String;
          if (decoded.startsWith('http')) return Uri.parse(decoded);
        }
      } catch (_) {}
    }

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      var atual = inicial;
      for (int i = 0; i < 4; i++) {
        final req = await client.getUrl(atual);
        req.followRedirects = false;
        headers.forEach((k, v) => req.headers.set(k, v));
        final resp = await req.close();
        await resp.drain();
        if (resp.isRedirect || (resp.statusCode >= 300 && resp.statusCode < 400)) {
          final loc = resp.headers.value(HttpHeaders.locationHeader);
          if (loc != null && loc.isNotEmpty) {
            atual = atual.resolve(loc);
            continue;
          }
        }
        break;
      }
      client.close(force: true);
      return atual;
    } catch (_) {
      return inicial;
    }
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
      final isBlogger = url.contains('blogger.com') || url.contains('googlevideo.com');
      final headers = <String, String>{
        'User-Agent': isBlogger
            ? 'Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
            : 'VLC/3.0.18 LibVLC/3.0.18',
        'Accept': '*/*',
        'Connection': 'keep-alive',
        if (isBlogger) 'Referer': 'https://www.blogger.com/',
        ..._fonteAtual.headers,
      };
      final uriFinal = await _extrairStreamReal(Uri.parse(url.trim()), headers);
      final lower = uriFinal.toString().toLowerCase();
      final VideoFormat? fmt = (lower.contains('.m3u8') || _fonteAtual.formato.toLowerCase() == 'hls')
          ? VideoFormat.hls
          : VideoFormat.other;

      final controller = VideoPlayerController.networkUrl(
        uriFinal,
        formatHint: fmt,
        httpHeaders: headers,
      );
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
      if (!_tentouBackup && _fonteAtual.urlStreamBackup.trim().isNotEmpty) {
        _tentouBackup = true;
        return _iniciarStream(_fonteAtual.urlStreamBackup.trim(), posicaoRetomar: posicaoRetomar);
      }
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Falha ao reproduzir: $e\nURL: ${url.trim()}';
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
              ...lista.map((f) {
                final ativo = f.id == _fonteAtual.id;
                return ListTile(
                  leading: Icon(
                    ativo ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: ativo ? const Color(0xFF2196F3) : Colors.white54,
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
    final opcoesMesmoItem = widget.obra.fontes
        .where((f) => f.temporada == _fonteAtual.temporada && f.episodio == _fonteAtual.episodio)
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _carregando
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF2196F3)),
                      const SizedBox(height: 12),
                      Text('Carregando ${widget.obra.titulo} (${_fonteAtual.badgeResumo})...',
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  )
                : _erro != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
                            const SizedBox(height: 8),
                            Text(_erro!,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 12)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
                              onPressed: () {
                                _tentouBackup = false;
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
                  child: Text(
                    '${widget.obra.titulo} ${_fonteAtual.etiquetaEpisodio}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
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
