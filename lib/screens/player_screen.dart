import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../services/torrserver_service.dart';

class CinemaPlayerScreen extends StatefulWidget {
  final ObraAgrupada obra;
  final FonteMidia fonteInicial;
  final List<FonteMidia> listaEpisodios;

  const CinemaPlayerScreen({
    super.key,
    required this.obra,
    required this.fonteInicial,
    this.listaEpisodios = const [],
  });

  @override
  State<CinemaPlayerScreen> createState() => _CinemaPlayerScreenState();
}

class _CinemaPlayerScreenState extends State<CinemaPlayerScreen> {
  late final Player _player;
  late final VideoController _videoCtrl;
  late FonteMidia _fonteAtual;

  bool _controlesVisiveis = true;
  bool _tentouBackup = false;
  bool _carregandoStream = true;
  String? _erroPlayer;
  Timer? _hideTimer;
  Timer? _saveProgressTimer;

  Duration _posicao = Duration.zero;
  Duration _duracao = Duration.zero;
  bool _tocando = true;

  // Configurações de Legenda
  bool _legendaAtiva = true;
  double _tamanhoLegenda = 28.0;
  Color _corLegenda = Colors.white;
  String _legendaSelecionada = 'Nenhuma';

  @override
  void initState() {
    super.initState();
    _fonteAtual = widget.fonteInicial;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _player = Player();
    _videoCtrl = VideoController(_player);

    _player.stream.position.listen((p) {
      if (mounted) setState(() => _posicao = p);
    });
    _player.stream.duration.listen((d) {
      if (mounted) setState(() => _duracao = d);
    });
    _player.stream.playing.listen((pl) {
      if (mounted) setState(() => _tocando = pl);
    });
    _player.stream.buffering.listen((b) {
      if (mounted && !b) setState(() => _carregandoStream = false);
    });
    _player.stream.error.listen((err) {
      if (!mounted) return;
      if (!_tentouBackup && _fonteAtual.urlStreamBackup.isNotEmpty) {
        _tentouBackup = true;
        _abrirMidia(_fonteAtual.urlStreamBackup);
      } else {
        setState(() {
          _carregandoStream = false;
          _erroPlayer = 'Falha ao reproduzir stream: $err';
        });
      }
    });

    _iniciarFonte(_fonteAtual);
    _reiniciarTimerControles();

    _saveProgressTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _salvarProgressoAtual();
    });
  }

  Future<void> _iniciarFonte(FonteMidia fonte) async {
    setState(() {
      _fonteAtual = fonte;
      _tentouBackup = false;
      _carregandoStream = true;
      _erroPlayer = null;
    });
    SupabaseService.registrarVisualizacao(fonte.id);
    await _abrirMidia(fonte.urlStream);
  }

  Future<void> _abrirMidia(String url) async {
    try {
      String urlFinal = url.trim();
      final lower = urlFinal.toLowerCase();
      if (lower.startsWith('magnet:?') || lower.endsWith('.torrent')) {
        final info = await TorrServerService.prepararMagnet(
          urlFinal,
          cancelado: () => !mounted,
        );
        if (!mounted) return;
        if (info == null) {
          setState(() {
            _carregandoStream = false;
            _erroPlayer = TorrServerService.ultimoErro.isNotEmpty
                ? TorrServerService.ultimoErro
                : 'Não foi possível carregar o stream P2P no momento.';
          });
          return;
        }
        urlFinal = info.playUrl;
      }

      final headers = Map<String, String>.from(_fonteAtual.headers);
      if (!headers.containsKey('User-Agent')) {
        headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      }
      await _player.open(Media(urlFinal, httpHeaders: headers));
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregandoStream = false;
          _erroPlayer = e.toString();
        });
      }
    }
  }

  Future<void> _salvarProgressoAtual() async {
    if (_duracao.inSeconds <= 10) return;
    final pct = _posicao.inSeconds / _duracao.inSeconds;
    await SupabaseService.salvarProgressoAssistido(
      chaveGrupo: widget.obra.chaveGrupo,
      progresso: pct,
      etiquetaEp: _fonteAtual.etiquetaEpisodio,
    );
  }

  void _reiniciarTimerControles() {
    _hideTimer?.cancel();
    setState(() => _controlesVisiveis = true);
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _tocando) {
        setState(() => _controlesVisiveis = false);
      }
    });
  }

  FonteMidia? get _proximoEpisodio {
    if (widget.listaEpisodios.isEmpty) return null;
    final idx = widget.listaEpisodios.indexWhere((e) => e.id == _fonteAtual.id);
    if (idx >= 0 && idx + 1 < widget.listaEpisodios.length) {
      return widget.listaEpisodios[idx + 1];
    }
    return null;
  }

  void _pularAbertura() {
    final salto = Duration(seconds: widget.obra.aberturaSegundos);
    _player.seek(_posicao + salto);
    _reiniciarTimerControles();
  }

  String _formatarTempo(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _salvarProgressoAtual();
    _hideTimer?.cancel();
    _saveProgressTimer?.cancel();
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _abrirModalLegendas() {
    _reiniciarTimerControles();
    final buscaCtrl = TextEditingController(text: widget.obra.titulo);
    List<Map<String, dynamic>> resultadosSub = [];
    bool carregandoSub = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141822),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> buscarOpenSubtitles() async {
            final q = buscaCtrl.text.trim();
            if (q.isEmpty) return;
            setModal(() => carregandoSub = true);
            try {
              final uri = Uri.parse(
                'https://rest.opensubtitles.org/search/query-${Uri.encodeComponent(q)}/sublanguageid-pob,por,eng,spa',
              );
              final resp = await http.get(uri, headers: {'User-Agent': 'TemporaryUserAgent'}).timeout(const Duration(seconds: 8));
              if (resp.statusCode == 200) {
                final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
                setModal(() {
                  resultadosSub = list.take(12).map((e) => Map<String, dynamic>.from(e)).toList();
                });
              }
            } catch (_) {}
            setModal(() => carregandoSub = false);
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SizedBox(
              height: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Configurações de Legenda & OpenSubtitles', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Switch(
                        value: _legendaAtiva,
                        activeColor: const Color(0xFFF5B82E),
                        onChanged: (v) {
                          setState(() => _legendaAtiva = v);
                          setModal(() {});
                          if (!v) _player.setSubtitleTrack(SubtitleTrack.no());
                        },
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Tamanho:', style: TextStyle(color: Colors.white70)),
                      Expanded(
                        child: Slider(
                          value: _tamanhoLegenda,
                          min: 18,
                          max: 44,
                          activeColor: const Color(0xFFF5B82E),
                          onChanged: (v) {
                            setState(() => _tamanhoLegenda = v);
                            setModal(() {});
                          },
                        ),
                      ),
                      ...[Colors.white, const Color(0xFFF5B82E), Colors.cyanAccent].map(
                        (c) => GestureDetector(
                          onTap: () {
                            setState(() => _corLegenda = c);
                            setModal(() {});
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(color: _corLegenda == c ? Colors.redAccent : Colors.white54, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: buscaCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText: 'Buscar legenda no OpenSubtitles...',
                            filled: true,
                            fillColor: Colors.white10,
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5B82E), foregroundColor: Colors.black),
                        onPressed: buscarOpenSubtitles,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Buscar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: carregandoSub
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5B82E)))
                        : resultadosSub.isEmpty
                            ? Center(
                                child: Text(
                                  'Legenda ativa: $_legendaSelecionada\nToque em "Buscar" para baixar legendas online.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                                ),
                              )
                            : ListView.builder(
                                itemCount: resultadosSub.length,
                                itemBuilder: (_, i) {
                                  final item = resultadosSub[i];
                                  final nome = (item['SubFileName'] ?? 'Legenda').toString();
                                  final lang = (item['LanguageName'] ?? '').toString();
                                  final dl = (item['SubDownloadLink'] ?? '').toString().replaceAll('.gz', '');
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.subtitles, color: Color(0xFFF5B82E)),
                                    title: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                                    subtitle: Text(lang, style: const TextStyle(color: Colors.white54)),
                                    onTap: () async {
                                      if (dl.isNotEmpty) {
                                        await _player.setSubtitleTrack(SubtitleTrack.uri(dl, title: nome, language: lang));
                                        setState(() {
                                          _legendaAtiva = true;
                                          _legendaSelecionada = nome;
                                        });
                                        if (ctx.mounted) Navigator.pop(ctx);
                                      }
                                    },
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _abrirModalFontes() {
    _reiniciarTimerControles();
    final fontesMesmoEp = widget.obra.fontes.where((f) {
      if (_fonteAtual.episodio != null) {
        return f.temporada == _fonteAtual.temporada && f.episodio == _fonteAtual.episodio;
      }
      return true;
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141822),
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Resolução e Áudio', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...fontesMesmoEp.map(
            (f) => ListTile(
              leading: Icon(
                f.id == _fonteAtual.id ? Icons.check_circle : Icons.play_circle_outline,
                color: f.id == _fonteAtual.id ? const Color(0xFFF5B82E) : Colors.white54,
              ),
              title: Text(f.badgeResumo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: Text(f.formato.toUpperCase(), style: const TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(ctx);
                _iniciarFonte(f);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _abrirModalEpisodios() {
    _reiniciarTimerControles();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141822),
      builder: (ctx) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.listaEpisodios.length,
        itemBuilder: (_, idx) {
          final ep = widget.listaEpisodios[idx];
          final atual = ep.id == _fonteAtual.id;
          return ListTile(
            leading: Text(
              ep.etiquetaEpisodio.isNotEmpty ? ep.etiquetaEpisodio : 'Ep ${idx + 1}',
              style: TextStyle(color: atual ? const Color(0xFFF5B82E) : Colors.white70, fontWeight: FontWeight.w800),
            ),
            title: Text(ep.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
            trailing: Text(ep.resolucao, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () {
              Navigator.pop(ctx);
              _iniciarFonte(ep);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prox = _proximoEpisodio;
    final podePularAbertura = widget.obra.isSerie &&
        _posicao.inSeconds >= 5 &&
        _posicao.inSeconds <= (widget.obra.aberturaSegundos + 45);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (_controlesVisiveis) {
            setState(() => _controlesVisiveis = false);
          } else {
            _reiniciarTimerControles();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _videoCtrl,
              controls: NoVideoControls,
              subtitleViewConfiguration: SubtitleViewConfiguration(
                visible: _legendaAtiva,
                style: TextStyle(
                  fontSize: _tamanhoLegenda,
                  color: _corLegenda,
                  fontWeight: FontWeight.w700,
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
            if (_carregandoStream)
              const Center(child: CircularProgressIndicator(color: Color(0xFFF5B82E))),
            if (_erroPlayer != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
                      const SizedBox(height: 10),
                      Text(_erroPlayer!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _iniciarFonte(_fonteAtual),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            if (podePularAbertura)
              Positioned(
                right: 28,
                bottom: 92,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF5B82E),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onPressed: _pularAbertura,
                  icon: const Icon(Icons.fast_forward),
                  label: Text('Pular Abertura (+${widget.obra.aberturaSegundos}s)', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            if (_controlesVisiveis)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent, Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  children: [
                    // Barra Superior
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.obra.titulo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  '${_fonteAtual.etiquetaEpisodio} ${_fonteAtual.badgeResumo}'.trim(),
                                  style: const TextStyle(color: Color(0xFFF5B82E), fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Controles Centrais
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 38,
                          color: Colors.white,
                          icon: const Icon(Icons.replay_10),
                          onPressed: () {
                            _player.seek(_posicao - const Duration(seconds: 10));
                            _reiniciarTimerControles();
                          },
                        ),
                        const SizedBox(width: 28),
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: const Color(0xFFF5B82E),
                          child: IconButton(
                            iconSize: 34,
                            color: Colors.black,
                            icon: Icon(_tocando ? Icons.pause : Icons.play_arrow),
                            onPressed: () {
                              _player.playOrPause();
                              _reiniciarTimerControles();
                            },
                          ),
                        ),
                        const SizedBox(width: 28),
                        IconButton(
                          iconSize: 38,
                          color: Colors.white,
                          icon: const Icon(Icons.forward_10),
                          onPressed: () {
                            _player.seek(_posicao + const Duration(seconds: 10));
                            _reiniciarTimerControles();
                          },
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Barra Inferior (Progresso + Próximo Ep + Resolução/Áudio + Legendas)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(_formatarTempo(_posicao), style: const TextStyle(color: Colors.white, fontSize: 12)),
                              Expanded(
                                child: Slider(
                                  value: _duracao.inMilliseconds > 0
                                      ? _posicao.inMilliseconds.clamp(0, _duracao.inMilliseconds).toDouble()
                                      : 0,
                                  max: _duracao.inMilliseconds > 0 ? _duracao.inMilliseconds.toDouble() : 1,
                                  activeColor: const Color(0xFFF5B82E),
                                  inactiveColor: Colors.white24,
                                  onChanged: (v) {
                                    _player.seek(Duration(milliseconds: v.toInt()));
                                    _reiniciarTimerControles();
                                  },
                                ),
                              ),
                              Text(_formatarTempo(_duracao), style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                          Row(
                            children: [
                              if (prox != null)
                                TextButton.icon(
                                  onPressed: () => _iniciarFonte(prox),
                                  icon: const Icon(Icons.skip_next, color: Color(0xFFF5B82E)),
                                  label: Text('Próximo (${prox.etiquetaEpisodio})', style: const TextStyle(color: Colors.white)),
                                ),
                              if (widget.listaEpisodios.isNotEmpty)
                                TextButton.icon(
                                  onPressed: _abrirModalEpisodios,
                                  icon: const Icon(Icons.list, color: Colors.white),
                                  label: const Text('Episódios', style: TextStyle(color: Colors.white)),
                                ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _abrirModalFontes,
                                icon: const Icon(Icons.hd, color: Color(0xFFF5B82E)),
                                label: Text(_fonteAtual.resolucao, style: const TextStyle(color: Colors.white)),
                              ),
                              TextButton.icon(
                                onPressed: _abrirModalLegendas,
                                icon: const Icon(Icons.subtitles, color: Colors.white),
                                label: const Text('Legendas', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
