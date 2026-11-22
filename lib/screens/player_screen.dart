import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../main.dart';
import '../widgets/cinema_widgets.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../services/torrserver_service.dart';
import '../services/cdn_stream_service.dart';

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

  int _retryAutoCount = 0;
  String? _osdTexto;
  IconData? _osdIcone;
  Timer? _osdTimer;
  final FocusNode _playerRootFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    CinemaOrientation.emPlayer = true;
    _fonteAtual = widget.fonteInicial;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    if (_player.platform is NativePlayer) {
      final np = _player.platform as NativePlayer;
      np.setProperty('demuxer-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
      np.setProperty('network-timeout', '30');
    }
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
      if (_retryAutoCount < 1 && (_fonteAtual.urlStream.toLowerCase().startsWith('magnet:') || _fonteAtual.urlStream.toLowerCase().endsWith('.torrent'))) {
        _retryAutoCount++;
        Future.delayed(const Duration(milliseconds: 1400), () {
          if (mounted) _abrirMidia(_fonteAtual.urlStream);
        });
        return;
      }
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
        CdnResolucaoInfo? cdnInfo;
        if (lower.startsWith('magnet:?')) {
          cdnInfo = await CdnStreamService.resolverMagnet(urlFinal);
        }

        if (!mounted) return;

        if (cdnInfo != null && cdnInfo.url.isNotEmpty) {
          urlFinal = cdnInfo.url;
        } else {
          final swP2p = Stopwatch()..start();
          final info = await TorrServerService.prepararMagnet(
            urlFinal,
            cancelado: () => !mounted,
          );
          swP2p.stop();
          if (!mounted) return;
          if (info == null) {
            setState(() {
              _carregandoStream = false;
              _erroPlayer = TorrServerService.ultimoErro.isNotEmpty
                  ? TorrServerService.ultimoErro
                  : 'Não foi possível carregar o stream no momento.';
            });
            return;
          }
          CdnStreamService.ultimoDiagnostico =
              'Origem: P2P Local (TorrServer) | ${swP2p.elapsedMilliseconds}ms';
          urlFinal = info.playUrl;
        }
      }

      final headers = Map<String, String>.from(_fonteAtual.headers);
      if (!headers.containsKey('User-Agent')) {
        headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      }
      try {
        final platform = _player.platform;
        if (platform is NativePlayer) {
          await platform.setProperty('network-timeout', '30');
          await platform.setProperty('demuxer-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
          await platform.setProperty('cache', 'yes');
          await platform.setProperty('demuxer-max-bytes', '33554432');
        }
      } catch (_) {}
      await _player.open(Media(urlFinal, httpHeaders: headers), play: true);
      await _player.play();
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
    _osdTimer?.cancel();
    _playerRootFocus.dispose();
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
    CinemaOrientation.emPlayer = false;
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
    bool carregandoSub = true;
    bool jaBuscou = false;
    bool iniciouAuto = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141822),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<String?> descobrirImdbId(String titulo) async {
            try {
              final limpo = titulo.replaceAll(RegExp(r'\(\d{4}\)'), '').trim();
              if (limpo.isEmpty) return null;
              final firstChar = limpo[0].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), 'x');
              final u = Uri.parse('https://v3.sg.media-imdb.com/suggestion/$firstChar/${Uri.encodeComponent(limpo)}.json');
              final r = await http.get(u, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 5));
              if (r.statusCode == 200) {
                final data = jsonDecode(utf8.decode(r.bodyBytes));
                final d = (data is Map ? data['d'] : null) as List<dynamic>? ?? [];
                for (final item in d) {
                  if (item is Map) {
                    final id = (item['id'] ?? '').toString();
                    if (id.startsWith('tt')) return id;
                  }
                }
              }
            } catch (_) {}
            return null;
          }

          Future<void> buscarMultiBancos() async {
            final q = buscaCtrl.text.trim();
            if (q.isEmpty) return;
            setModal(() {
              carregandoSub = true;
              jaBuscou = true;
              resultadosSub = [];
            });
            final encontrados = <Map<String, dynamic>>[];

            final imdbId = await descobrirImdbId(q);
            final temp = _fonteAtual.temporada ?? 1;
            final ep = _fonteAtual.episodio ?? 1;

            // 1. OpenSubtitles V3 via IMDb ID (retorna .srt/.vtt diretos em PT/EN/ES)
            if (imdbId != null && imdbId.startsWith('tt')) {
              try {
                final tipo = widget.obra.isSerie ? 'series' : 'movie';
                final idQuery = widget.obra.isSerie ? '$imdbId:$temp:$ep' : imdbId;
                final uOs3 = Uri.parse('https://opensubtitles-v3.strem.io/subtitles/$tipo/$idQuery.json');
                final rOs3 = await http.get(uOs3).timeout(const Duration(seconds: 6));
                if (rOs3.statusCode == 200) {
                  final data = jsonDecode(utf8.decode(rOs3.bodyBytes));
                  final subs = (data is Map ? data['subtitles'] : null) as List<dynamic>? ?? [];
                  for (final s in subs) {
                    if (s is Map && (s['url'] ?? '').toString().isNotEmpty) {
                      final lang = (s['lang'] ?? 'por').toString();
                      final langLow = lang.toLowerCase();
                      if (langLow.contains('por') || langLow.contains('pob') || langLow == 'pt' || langLow.contains('eng') || langLow.contains('spa')) {
                        encontrados.add({
                          'SubFileName': '${widget.obra.titulo} (${lang.toUpperCase()}) [OpenSubtitles]',
                          'LanguageName': lang.toUpperCase(),
                          'SubDownloadLink': s['url'].toString(),
                          'Prioridade': (langLow.contains('por') || langLow.contains('pob') || langLow == 'pt') ? 0 : 1,
                        });
                      }
                    }
                  }
                }
              } catch (_) {}

              // 2. Wyzie / SubSource API via IMDb ID (legendas SRT limpas)
              try {
                final uWy = widget.obra.isSerie
                    ? Uri.parse('https://sub.wyzie.ru/search?id=$imdbId&season=$temp&episode=$ep')
                    : Uri.parse('https://sub.wyzie.ru/search?id=$imdbId');
                final rWy = await http.get(uWy).timeout(const Duration(seconds: 6));
                if (rWy.statusCode == 200) {
                  final list = jsonDecode(utf8.decode(rWy.bodyBytes));
                  if (list is List) {
                    for (final s in list) {
                      if (s is Map && (s['url'] ?? '').toString().isNotEmpty) {
                        final lang = (s['display'] ?? s['language'] ?? 'PT').toString();
                        final langLow = lang.toLowerCase();
                        encontrados.add({
                          'SubFileName': '${s['release'] ?? widget.obra.titulo} ($lang) [SubSource]',
                          'LanguageName': lang,
                          'SubDownloadLink': s['url'].toString(),
                          'Prioridade': (langLow.contains('portug') || langLow == 'pt' || langLow == 'pb') ? 0 : 1,
                        });
                      }
                    }
                  }
                }
              } catch (_) {}
            }

            // Ordena colocando Portugues no topo
            encontrados.sort((a, b) => (a['Prioridade'] as int).compareTo(b['Prioridade'] as int));

            if (ctx.mounted) {
              setModal(() {
                resultadosSub = encontrados.take(15).toList();
                carregandoSub = false;
              });
            }
          }

          if (!iniciouAuto) {
            iniciouAuto = true;
            Future.microtask(buscarMultiBancos);
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SizedBox(
              height: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Legendas Online (OpenSubtitles & SubSource)',
                          style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800),
                        ),
                      ),
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
                            hintText: 'Título do filme ou série...',
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
                        onPressed: buscarMultiBancos,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Buscar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: carregandoSub
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Color(0xFFF5B82E)),
                                SizedBox(height: 10),
                                Text('Buscando legendas em Português...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          )
                        : resultadosSub.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (jaBuscou)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withOpacity(0.16),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.subtitles_off, color: Colors.redAccent, size: 18),
                                            SizedBox(width: 8),
                                            Text(
                                              'Legenda não encontrada para este título.',
                                              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Text(
                                      'Legenda ativa: $_legendaSelecionada\nTente buscar pelo título original em inglês se necessário.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 17),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Legenda encontrada! (${resultadosSub.length} opções)',
                                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700, fontSize: 12.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: resultadosSub.length,
                                      itemBuilder: (_, i) {
                                        final item = resultadosSub[i];
                                        final nome = (item['SubFileName'] ?? 'Legenda').toString();
                                        final idioma = (item['LanguageName'] ?? '').toString();
                                        final dl = (item['SubDownloadLink'] ?? '').toString();
                                        return ListTile(
                                          dense: true,
                                          leading: const Icon(Icons.subtitles, color: Color(0xFFF5B82E)),
                                          title: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                          subtitle: Text(idioma, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                          onTap: () async {
                                            if (dl.isNotEmpty) {
                                              await _player.setSubtitleTrack(SubtitleTrack.uri(dl, title: nome, language: idioma));
                                              setState(() {
                                                _legendaAtiva = true;
                                                _legendaSelecionada = nome;
                                              });
                                            }
                                            if (ctx.mounted) Navigator.pop(ctx);
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
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

  void _mostrarOsd(IconData icone, String texto) {
    _osdTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _osdIcone = icone;
      _osdTexto = texto;
    });
    _osdTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _osdTexto = null;
          _osdIcone = null;
        });
      }
    });
  }

  void _alternarPlayPause() {
    _player.playOrPause();
    final vaiPausar = _tocando;
    _mostrarOsd(vaiPausar ? Icons.pause_circle_filled : Icons.play_circle_filled, vaiPausar ? 'Pausado' : 'Reproduzindo');
    _reiniciarTimerControles();
  }

  void _buscarRelativo(int segundos) {
    final alvo = _posicao + Duration(seconds: segundos);
    final clamped = alvo < Duration.zero
        ? Duration.zero
        : (_duracao > Duration.zero && alvo > _duracao ? _duracao : alvo);
    _player.seek(clamped);
    _mostrarOsd(
      segundos < 0 ? Icons.replay_10 : Icons.forward_10,
      segundos < 0 ? '${segundos}s' : '+${segundos}s',
    );
    _reiniciarTimerControles();
  }

  bool _isConfirmKey(LogicalKeyboardKey k) {
    return k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.accept ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause;
  }

  @override
  Widget build(BuildContext context) {
    final podePularAbertura = widget.obra.aberturaSegundos > 0 &&
        _posicao.inSeconds >= 5 &&
        _posicao.inSeconds <= (widget.obra.aberturaSegundos + 45);
    final prox = _proximoEpisodio;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _playerRootFocus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final k = event.logicalKey;

          if (k == LogicalKeyboardKey.mediaPlayPause ||
              k == LogicalKeyboardKey.mediaPlay ||
              k == LogicalKeyboardKey.mediaPause) {
            _alternarPlayPause();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.mediaFastForward) {
            _buscarRelativo(10);
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.mediaRewind) {
            _buscarRelativo(-10);
            return KeyEventResult.handled;
          }

          if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
            if (_controlesVisiveis && !_carregandoStream) {
              setState(() => _controlesVisiveis = false);
              _playerRootFocus.requestFocus();
              return KeyEventResult.handled;
            }
            Navigator.pop(context);
            return KeyEventResult.handled;
          }

          if (!_controlesVisiveis) {
            if (_isConfirmKey(k)) {
              _alternarPlayPause();
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.arrowRight) {
              _buscarRelativo(10);
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.arrowLeft) {
              _buscarRelativo(-10);
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
              _reiniciarTimerControles();
              return KeyEventResult.handled;
            }
          } else {
            _reiniciarTimerControles();
            if (_playerRootFocus.hasPrimaryFocus) {
              if (_isConfirmKey(k)) {
                _alternarPlayPause();
                return KeyEventResult.handled;
              }
              if (k == LogicalKeyboardKey.arrowRight) {
                _buscarRelativo(10);
                return KeyEventResult.handled;
              }
              if (k == LogicalKeyboardKey.arrowLeft) {
                _buscarRelativo(-10);
                return KeyEventResult.handled;
              }
              if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
                FocusScope.of(context).nextFocus();
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () {
            if (_controlesVisiveis && !_carregandoStream) {
              setState(() => _controlesVisiveis = false);
              _playerRootFocus.requestFocus();
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
              if (_osdTexto != null && !_carregandoStream)
                Center(
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.78),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF5B82E), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_osdIcone != null) Icon(_osdIcone, color: const Color(0xFFF5B82E), size: 32),
                          const SizedBox(width: 10),
                          Text(
                            _osdTexto!,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                        CinemaFocusBox(
                          autofocus: true,
                          onTap: () => _iniciarFonte(_fonteAtual),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5B82E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Tentar novamente', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (podePularAbertura)
                Positioned(
                  right: 28,
                  bottom: 92,
                  child: CinemaFocusBox(
                    onTap: _pularAbertura,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5B82E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.fast_forward, color: Colors.black),
                          const SizedBox(width: 6),
                          Text(
                            'Pular Abertura (+${widget.obra.aberturaSegundos}s)',
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_controlesVisiveis && !_carregandoStream)
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            CinemaFocusBox(
                              borderRadius: 24,
                              onTap: () => Navigator.pop(context),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.arrow_back, color: Colors.white, size: 26),
                              ),
                            ),
                            const SizedBox(width: 10),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CinemaFocusBox(
                            borderRadius: 30,
                            scaleOnFocus: 1.12,
                            onTap: () => _buscarRelativo(-10),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.replay_10, color: Colors.white, size: 38),
                            ),
                          ),
                          const SizedBox(width: 28),
                          CinemaFocusBox(
                            autofocus: true,
                            borderRadius: 36,
                            scaleOnFocus: 1.12,
                            onTap: _alternarPlayPause,
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: const Color(0xFFF5B82E),
                              child: Icon(_tocando ? Icons.pause : Icons.play_arrow, size: 34, color: Colors.black),
                            ),
                          ),
                          const SizedBox(width: 28),
                          CinemaFocusBox(
                            borderRadius: 30,
                            scaleOnFocus: 1.12,
                            onTap: () => _buscarRelativo(10),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.forward_10, color: Colors.white, size: 38),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
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
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: CinemaFocusBox(
                                      borderRadius: 8,
                                      onTap: () => _iniciarFonte(prox),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.skip_next, color: Color(0xFFF5B82E), size: 20),
                                            const SizedBox(width: 4),
                                            Text('Próximo (${prox.etiquetaEpisodio})', style: const TextStyle(color: Colors.white)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                if (widget.listaEpisodios.isNotEmpty)
                                  CinemaFocusBox(
                                    borderRadius: 8,
                                    onTap: _abrirModalEpisodios,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.list, color: Colors.white, size: 20),
                                          SizedBox(width: 4),
                                          Text('Episódios', style: TextStyle(color: Colors.white)),
                                        ],
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                CinemaFocusBox(
                                  borderRadius: 8,
                                  onTap: _abrirModalFontes,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.hd, color: Color(0xFFF5B82E), size: 20),
                                        const SizedBox(width: 4),
                                        Text(_fonteAtual.resolucao, style: const TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                CinemaFocusBox(
                                  borderRadius: 8,
                                  onTap: _abrirModalLegendas,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.subtitles, color: Colors.white, size: 20),
                                        SizedBox(width: 4),
                                        Text('Legendas', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
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
      ),
    );
  }
}
