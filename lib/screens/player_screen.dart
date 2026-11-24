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
import '../services/catalog_audit_service.dart';

class CinemaPlayerScreen extends StatefulWidget {
  final ObraAgrupada obra;
  final FonteMidia fonteInicial;
  final List<FonteMidia> listaEpisodios;
  final double progressoInicial;

  const CinemaPlayerScreen({
    super.key,
    required this.obra,
    required this.fonteInicial,
    this.listaEpisodios = const [],
    this.progressoInicial = 0.0,
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
  String _statusCarregamento = 'Preparando vídeo...';
  double? _progressoCarregamento;
  String? _erroPlayer;
  Timer? _hideTimer;
  Timer? _saveProgressTimer;

  Duration _posicao = Duration.zero;
  Duration _duracao = Duration.zero;
  final ValueNotifier<Duration> _posNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durNotifier = ValueNotifier(Duration.zero);
  final List<StreamSubscription> _subs = [];
  bool _tocando = true;

  // Configurações de Legenda
  bool _legendaAtiva = true;
  double _tamanhoLegenda = 28.0;
  Color _corLegenda = Colors.white;
  String _legendaSelecionada = 'Nenhuma';

  int _retryAutoCount = 0;
  int _geracaoPlayback = 0;
  String _viaAtual = '';
  bool _forcandoP2pNaSessao = false;
  Duration _ultimaPosicaoBoa = Duration.zero;
  int _segundosTravado = 0;
  int _recuperacoesSessao = 0;
  Timer? _watchdogTimer;
  bool _operacaoWatchdogEmAndamento = false;
  bool _retomadaAplicada = false;
  bool _mostrarBotaoInicio = false;
  bool _preAqueceuProx = false;
  int _contagemAutoPlay = 0;
  Timer? _autoPlayTimer;
  int _introInicio = 5;
  int _introFim = 0;
  String _origemIntro = 'padrao';
  final Set<String> _fontesTentadas = {};
  String? _osdTexto;
  IconData? _osdIcone;
  Timer? _osdTimer;
  final FocusNode _playerRootFocus = FocusNode();
  final FocusNode _voltarFocus = FocusNode();
  final FocusNode _centroControlsFocus = FocusNode();
  DateTime _ultSeek = DateTime.fromMillisecondsSinceEpoch(0);
  int _ultDir = 0;
  final FocusNode _sliderFocus = FocusNode();
  final FocusNode _barraInferiorFocus = FocusNode();
  final FocusNode _sliderInternalFocus = FocusNode(canRequestFocus: false, skipTraversal: true);

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
        bufferSize: 12 * 1024 * 1024,
      ),
    );
    if (_player.platform is NativePlayer) {
      final np = _player.platform as NativePlayer;
      np.setProperty('hwdec', 'auto-safe');
      np.setProperty('demuxer-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
      np.setProperty('network-timeout', '30');
    }
    _videoCtrl = VideoController(_player);

    _subs.add(_player.stream.position.listen((p) {
      _posicao = p;
      if (p.inSeconds > 2) {
        _ultimaPosicaoBoa = p;
        _segundosTravado = 0;
      }
      _posNotifier.value = p;
      final proxEp = _proximoEpisodio;
      if (proxEp != null && _duracao.inSeconds > 90 && _erroPlayer == null) {
        final faltam = _duracao.inSeconds - p.inSeconds;
        if (faltam <= 35 && !_preAqueceuProx) {
          _preAqueceuProx = true;
          CdnStreamService.preAquecerMagnet(proxEp.urlStream);
        }
        if (faltam <= 15 && faltam > 0 && _contagemAutoPlay == 0 && _autoPlayTimer == null && mounted) {
          setState(() => _contagemAutoPlay = 10);
          _autoPlayTimer = Timer.periodic(const Duration(seconds: 1), (tm) {
            if (!mounted) { tm.cancel(); return; }
            if (_contagemAutoPlay <= 1) {
              tm.cancel();
              _autoPlayTimer = null;
              setState(() => _contagemAutoPlay = 0);
              _iniciarFonte(proxEp);
            } else {
              setState(() => _contagemAutoPlay--);
            }
          });
        }
      }
    }));
    _subs.add(_player.stream.duration.listen((d) {
      _duracao = d;
      _durNotifier.value = d;
      if (_ultimaPosicaoBoa.inSeconds > 5 && d > _ultimaPosicaoBoa + const Duration(seconds: 5)) {
        final alvo = _ultimaPosicaoBoa;
        _ultimaPosicaoBoa = Duration.zero;
        _player.seek(alvo);
        _mostrarOsd(Icons.sync, 'Retomado em ${_formatarTempo(alvo)}');
      } else if (!_retomadaAplicada && widget.progressoInicial > 0.04 && widget.progressoInicial < 0.94 && d.inSeconds > 60) {
        _retomadaAplicada = true;
        final alvo = Duration(seconds: (d.inSeconds * widget.progressoInicial).round());
        _player.seek(alvo);
        if (mounted) {
          setState(() => _mostrarBotaoInicio = true);
          _mostrarOsd(Icons.history, 'Retomado de ${_formatarTempo(alvo)}');
          Future.delayed(const Duration(seconds: 8), () { if (mounted) setState(() => _mostrarBotaoInicio = false); });
        }
      }
    }));
    _subs.add(_player.stream.playing.listen((pl) {
      if (mounted) setState(() { _tocando = pl; if (pl) { _erroPlayer = null; _carregandoStream = false; } });
    }));
    _subs.add(_player.stream.buffering.listen((b) {
      if (mounted && !b) setState(() => _carregandoStream = false);
    }));
    _subs.add(_player.stream.error.listen((err) async {
      if (!mounted) return;
      final errLow = err.toLowerCase();
      if (errLow.contains('could not open codec') || errLow.contains('subtitle')) return;
      final ger = _geracaoPlayback;
      if (_posicao.inSeconds > 2) _ultimaPosicaoBoa = _posicao;

      // Se falhou na CDN HTTP, invalida cache e cai imediatamente para P2P TorrServer
      if (_viaAtual == 'cdn' && !_forcandoP2pNaSessao) {
        CdnStreamService.invalidarCache(_fonteAtual.urlStream);
        _forcandoP2pNaSessao = true;
        if (mounted) setState(() { _carregandoStream = true; _statusCarregamento = 'CDN indisponível, alternando para P2P...'; });
        if (ger == _geracaoPlayback) await _abrirMidia(_fonteAtual.urlStream, geracao: ger);
        return;
      }

      if (_retryAutoCount < 1 && (_fonteAtual.urlStream.toLowerCase().startsWith('magnet:') || _fonteAtual.urlStream.toLowerCase().endsWith('.torrent'))) {
        _retryAutoCount++;
        CdnStreamService.invalidarCache(_fonteAtual.urlStream);
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted && ger == _geracaoPlayback) await _abrirMidia(_fonteAtual.urlStream, geracao: ger);
        return;
      }

      final trocou = await _tentarProximaFonteOuBackup(err, geracao: ger);
      if (!trocou && mounted && ger == _geracaoPlayback) {
        setState(() {
          _carregandoStream = false;
          _erroPlayer = 'Falha ao reproduzir stream: $err';
        });
      }
    }));

    _iniciarFonte(_fonteAtual);
    _reiniciarTimerControles();

    _saveProgressTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _salvarProgressoAtual();
    });

    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_operacaoWatchdogEmAndamento) return;
      _operacaoWatchdogEmAndamento = true;
      try {
      if (!mounted || _carregandoStream || _erroPlayer != null || !_tocando) return;
      if (_player.state.buffering) {
        _segundosTravado += 2;
        if (_segundosTravado >= 12 && _recuperacoesSessao < 2) {
          _segundosTravado = 0;
          _recuperacoesSessao++;
          final ger = _geracaoPlayback;
          if (_posicao.inSeconds > 2) _ultimaPosicaoBoa = _posicao;
          if (_viaAtual == 'cdn') {
            CdnStreamService.invalidarCache(_fonteAtual.urlStream);
            _forcandoP2pNaSessao = true;
            _mostrarOsd(Icons.swap_horiz, 'Oscilação na CDN, alternando para P2P...');
            await _abrirMidia(_fonteAtual.urlStream, geracao: ger);
          } else {
            _mostrarOsd(Icons.swap_horiz, 'Buscando fonte mais rápida...');
            await _tentarProximaFonteOuBackup('Buffering prolongado (>12s)', geracao: ger);
          }
        }
      } else {
        _segundosTravado = 0;
      }
      } finally {
        _operacaoWatchdogEmAndamento = false;
      }
    });
  }

  Future<void> _carregarIntroEpisodio() async {
    if (!widget.obra.isSerie) return;
    final t = _fonteAtual.temporada ?? 1;
    final e = _fonteAtual.episodio ?? 1;
    final chave = '${widget.obra.tmdbId ?? widget.obra.chaveGrupo}_s${t}_e$e';
    if (mounted) setState(() { _introInicio = 5; _introFim = widget.obra.aberturaSegundos > 0 ? (5 + widget.obra.aberturaSegundos) : 0; _origemIntro = 'padrao'; });
    try {
      final key = await SupabaseService.getAnonKey();
      final uri = Uri.parse('${SupabaseService.baseUrl}/rest/v1/episodio_intros?chave_ep=eq.${Uri.encodeComponent(chave)}&select=inicio_seg,fim_seg,origem');
      final r = await http.get(uri, headers: {'apikey': key, 'Authorization': 'Bearer $key'}).timeout(const Duration(seconds: 4));
      if (r.statusCode == 200) {
        final rows = jsonDecode(utf8.decode(r.bodyBytes)) as List;
        if (rows.isNotEmpty && rows.first is Map && mounted) {
          setState(() {
            _introInicio = (rows.first['inicio_seg'] as num?)?.toInt() ?? 5;
            _introFim = (rows.first['fim_seg'] as num?)?.toInt() ?? _introFim;
            _origemIntro = (rows.first['origem'] ?? 'nuvem').toString();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _salvarIntroNuvem(int ini, int fim, String origem) async {
    if (!widget.obra.isSerie || fim <= ini + 15) return;
    final t = _fonteAtual.temporada ?? 1;
    final e = _fonteAtual.episodio ?? 1;
    final chave = '${widget.obra.tmdbId ?? widget.obra.chaveGrupo}_s${t}_e$e';
    try {
      final key = await SupabaseService.getAnonKey();
      await http.post(
        Uri.parse('${SupabaseService.baseUrl}/rest/v1/episodio_intros'),
        headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode({'chave_ep': chave, 'tmdb_id': widget.obra.tmdbId, 'temporada': t, 'episodio': e, 'inicio_seg': ini, 'fim_seg': fim, 'origem': origem}),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> _iniciarFonte(FonteMidia fonte, {bool limparHistoricoTentativas = true}) async {
    final ger = ++_geracaoPlayback;
    if (limparHistoricoTentativas) {
      _fontesTentadas.clear();
      _ultimaPosicaoBoa = Duration.zero;
      _recuperacoesSessao = 0;
    } else if (_fonteAtual.urlStream.isNotEmpty) {
      TorrServerService.removerTorrent(_fonteAtual.urlStream);
    }
    _fontesTentadas.add(fonte.id);
    _retryAutoCount = 0;
    _forcandoP2pNaSessao = false;
    _viaAtual = '';
    _segundosTravado = 0;
    try { await _player.stop(); } catch (_) {}
    if (!mounted || ger != _geracaoPlayback) return;
    setState(() {
      _fonteAtual = fonte;
      _tentouBackup = false;
      _carregandoStream = true;
      _erroPlayer = null;
      _osdTexto = null;
      _preAqueceuProx = false;
      _contagemAutoPlay = 0;
    });
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    SupabaseService.registrarVisualizacao(fonte.id);
    _carregarIntroEpisodio();
    await _abrirMidia(fonte.urlStream, geracao: ger);
  }

  Future<bool> _tentarProximaFonteOuBackup(String motivoFalha, {int? geracao}) async {
    final ger = geracao ?? _geracaoPlayback;
    if (ger != _geracaoPlayback) return true;
    if (!_tentouBackup && _fonteAtual.urlStreamBackup.isNotEmpty) {
      _tentouBackup = true;
      _forcandoP2pNaSessao = false;
      if (mounted) setState(() { _carregandoStream = true; _erroPlayer = null; _statusCarregamento = 'Tentando link alternativo...'; });
      await _abrirMidia(_fonteAtual.urlStreamBackup, geracao: ger);
      return true;
    }
    final alternativas = widget.obra.fontes.where((f) {
      if (_fontesTentadas.contains(f.id)) return false;
      if (_fonteAtual.episodio != null) return f.temporada == _fonteAtual.temporada && f.episodio == _fonteAtual.episodio;
      return true;
    }).toList();
    if (alternativas.isNotEmpty) {
      await _iniciarFonte(alternativas.first, limparHistoricoTentativas: false);
      return true;
    }
    CatalogAuditService.instance.reportarProblemaParaScrape(
      titulo: widget.obra.titulo,
      categoria: 'link-sem-peers',
      detalhes: 'Falha em todas as fontes de ${widget.obra.titulo} (${_fonteAtual.etiquetaEpisodio}): $motivoFalha',
    );
    return false;
  }

  Future<void> _abrirMidia(String url, {int? geracao}) async {
    final ger = geracao ?? _geracaoPlayback;
    try {
      String urlFinal = url.trim();
      if (!SupabaseService.ehLinkValido(urlFinal)) {
        const motivo = 'Link inválido no catálogo';
        final trocou = await _tentarProximaFonteOuBackup(motivo, geracao: ger);
        if (!trocou && mounted && ger == _geracaoPlayback) {
          setState(() {
            _carregandoStream = false;
            _erroPlayer = '$motivo\nReportamos automaticamente para correção no catálogo.';
          });
        }
        return;
      }
      final lower = urlFinal.toLowerCase();
      if (lower.startsWith('magnet:?xt=urn:btih:') || lower.endsWith('.torrent')) {
        CdnResolucaoInfo? cdnInfo;
        if (lower.startsWith('magnet:?xt=urn:btih:') && !_forcandoP2pNaSessao) {
          if (mounted) setState(() { _statusCarregamento = 'Conectando à Gcore CDN...'; _progressoCarregamento = null; });
          TorrServerService.garantirAtivo();
          cdnInfo = await CdnStreamService.resolverMagnet(urlFinal);
        }

        if (!mounted || ger != _geracaoPlayback) return;

        if (cdnInfo != null && cdnInfo.url.isNotEmpty) {
          _viaAtual = 'cdn';
          if (mounted) setState(() { _statusCarregamento = 'Iniciando via Gcore CDN (${cdnInfo!.latenciaMs}ms)...'; _progressoCarregamento = 0.95; });
          urlFinal = cdnInfo.url;
        } else {
          _viaAtual = 'p2p';
          final swP2p = Stopwatch()..start();
          final info = await TorrServerService.prepararMagnet(
            urlFinal,
            onStatus: (st) { if (mounted && ger == _geracaoPlayback) setState(() => _statusCarregamento = st); },
            onProgress: (pr) { if (mounted && ger == _geracaoPlayback) setState(() => _progressoCarregamento = pr); },
            cancelado: () => !mounted || ger != _geracaoPlayback,
          );
          swP2p.stop();
          if (!mounted || ger != _geracaoPlayback) return;
          if (info == null) {
            final motivo = TorrServerService.ultimoErro.isNotEmpty ? TorrServerService.ultimoErro : 'Não foi possível carregar o stream no momento.';
            final trocou = await _tentarProximaFonteOuBackup(motivo, geracao: ger);
            if (!trocou && mounted && ger == _geracaoPlayback) {
              setState(() {
                _carregandoStream = false;
                _erroPlayer = '$motivo\nReportamos automaticamente para atualização no catálogo.';
              });
            }
            return;
          }
          if (mounted) {
            setState(() {
              _statusCarregamento = 'P2P pronto (${info.totalSeeds} seeds • ${info.activePeers} peers)';
              _progressoCarregamento = 1.0;
            });
          }
          CdnStreamService.ultimoDiagnostico =
              'Origem: P2P Local (TorrServer) | ${swP2p.elapsedMilliseconds}ms';
          urlFinal = info.playUrl;
        }
      } else {
        _viaAtual = 'direto';
      }

      if (!mounted || ger != _geracaoPlayback) return;
      final headers = Map<String, String>.from(_fonteAtual.headers);
      if (!headers.containsKey('User-Agent') && !urlFinal.startsWith('http://127.0.0.1')) {
        headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
      }
      try {
        final platform = _player.platform;
        if (platform is NativePlayer) {
          await platform.setProperty('network-timeout', '30');
          await platform.setProperty('demuxer-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
          await platform.setProperty('cache', 'yes');
          await platform.setProperty('demuxer-max-bytes', '12582912');
        }
      } catch (_) {}
      if (!mounted || ger != _geracaoPlayback) return;
      await _player.open(Media(urlFinal, httpHeaders: headers), play: true);
    } catch (e) {
      if (mounted && ger == _geracaoPlayback) {
        final trocou = await _tentarProximaFonteOuBackup(e.toString(), geracao: ger);
        if (!trocou && mounted && ger == _geracaoPlayback) {
          setState(() {
            _carregandoStream = false;
            _erroPlayer = e.toString();
          });
        }
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
    if (!mounted) return;
    setState(() => _controlesVisiveis = true);
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _tocando) {
        setState(() => _controlesVisiveis = false);
        _playerRootFocus.requestFocus();
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
    final alvo = _introFim > _posicao.inSeconds
        ? Duration(seconds: _introFim)
        : (_posicao + Duration(seconds: widget.obra.aberturaSegundos));
    _player.seek(alvo);
    _salvarIntroNuvem(_introInicio, alvo.inSeconds, 'usuario_nuvem');
    _mostrarOsd(Icons.fast_forward, 'Abertura pulada');
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
    _geracaoPlayback++;
    _hideTimer?.cancel();
    _osdTimer?.cancel();
    _watchdogTimer?.cancel();
    _autoPlayTimer?.cancel();
    _saveProgressTimer?.cancel();
    for (final sub in _subs) { sub.cancel(); }
    _posNotifier.dispose();
    _durNotifier.dispose();
    _voltarFocus.dispose();
    _centroControlsFocus.dispose();
    _sliderFocus.dispose();
    _barraInferiorFocus.dispose();
    _sliderInternalFocus.dispose();
    _playerRootFocus.dispose();
    _player.dispose();
    TorrServerService.encerrar();
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
                      CinemaFocusBox(
                        autofocus: true,
                        borderRadius: 12,
                        onTap: () {
                          final v = !_legendaAtiva;
                          setState(() => _legendaAtiva = v);
                          setModal(() {});
                          if (!v) _player.setSubtitleTrack(SubtitleTrack.no());
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: _legendaAtiva ? const Color(0xFFF5B82E) : Colors.white12, borderRadius: BorderRadius.circular(12)),
                          child: Text(_legendaAtiva ? 'Ativada' : 'Desativada', style: TextStyle(color: _legendaAtiva ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('Tamanho:', style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 8),
                      CinemaFocusBox(
                        borderRadius: 8,
                        onTap: () { setState(() => _tamanhoLegenda = (_tamanhoLegenda - 2).clamp(18, 44)); setModal(() {}); },
                        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Text('A-', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                      ),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${_tamanhoLegenda.toInt()}', style: const TextStyle(color: Color(0xFFF5B82E), fontWeight: FontWeight.w800))),
                      CinemaFocusBox(
                        borderRadius: 8,
                        onTap: () { setState(() => _tamanhoLegenda = (_tamanhoLegenda + 2).clamp(18, 44)); setModal(() {}); },
                        child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Text('A+', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                      ),
                      const Spacer(),
                      ...[Colors.white, const Color(0xFFF5B82E), Colors.cyanAccent].map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: CinemaFocusBox(
                            borderRadius: 16,
                            onTap: () { setState(() => _corLegenda = c); setModal(() {}); },
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: _corLegenda == c ? Colors.redAccent : Colors.white54, width: 2)),
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
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final subsInternas = _player.state.tracks.subtitle.where((t) => t.id != 'no' && t.id != 'auto').toList();
                    if (subsInternas.isEmpty) return const SizedBox.shrink();
                    return SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          const Center(child: Text('Embutidas: ', style: TextStyle(color: Color(0xFFF5B82E), fontSize: 12, fontWeight: FontWeight.w800))),
                          ...subsInternas.map((st) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: CinemaFocusBox(
                              borderRadius: 14,
                              onTap: () async {
                                await _player.setSubtitleTrack(st);
                                setState(() { _legendaAtiva = true; _legendaSelecionada = st.title ?? st.language ?? 'Interna'; });
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(14)),
                                child: Text('${st.title ?? "Legenda"} (${(st.language ?? st.id).toUpperCase()})', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          )),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
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
                                        return CinemaFocusBox(
                                          borderRadius: 8,
                                          onTap: () async {
                                            if (dl.isNotEmpty) {
                                              await _player.setSubtitleTrack(SubtitleTrack.uri(dl, title: nome, language: idioma));
                                              setState(() { _legendaAtiva = true; _legendaSelecionada = nome; });
                                            }
                                            if (ctx.mounted) Navigator.pop(ctx);
                                          },
                                          child: ListTile(
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
                                        )
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

    final faixasAudio = _player.state.tracks.audio.where((t) => t.id != 'no' && t.id != 'auto').toList();
    final audioAtualId = _player.state.track.audio.id;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141822),
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (faixasAudio.isNotEmpty) ...[
            const Text('Faixas de Áudio do Vídeo (Dublagem / Original)', style: TextStyle(color: Color(0xFFF5B82E), fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...faixasAudio.map((tr) => CinemaFocusBox(
              borderRadius: 8,
              onTap: () async {
                await _player.setAudioTrack(tr);
                if (ctx.mounted) Navigator.pop(ctx);
                _mostrarOsd(Icons.audiotrack, 'Áudio: ${tr.title ?? tr.language ?? tr.id}');
              },
              child: ListTile(
                dense: true,
                leading: Icon(tr.id == audioAtualId ? Icons.check_circle : Icons.audiotrack, color: tr.id == audioAtualId ? const Color(0xFFF5B82E) : Colors.white54),
                title: Text('${tr.title ?? "Faixa"} (${(tr.language ?? tr.id).toUpperCase()})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            )),
            const Divider(color: Colors.white12, height: 24),
          ],
          const Text('Resolução e Fontes', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...fontesMesmoEp.map(
            (f) => CinemaFocusBox(
              autofocus: f.id == _fonteAtual.id,
              borderRadius: 8,
              onTap: () {
                Navigator.pop(ctx);
                _iniciarFonte(f);
              },
              child: ListTile(
                leading: Icon(
                  f.id == _fonteAtual.id ? Icons.check_circle : Icons.play_circle_outline,
                  color: f.id == _fonteAtual.id ? const Color(0xFFF5B82E) : Colors.white54,
                ),
                title: Text(f.badgeResumo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                subtitle: Text(f.formato.toUpperCase(), style: const TextStyle(color: Colors.white54)),
              ),
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
          return CinemaFocusBox(
            autofocus: atual,
            borderRadius: 8,
            onTap: () {
              Navigator.pop(ctx);
              _iniciarFonte(ep);
            },
            child: ListTile(
              leading: Text(
                ep.etiquetaEpisodio.isNotEmpty ? ep.etiquetaEpisodio : 'Ep ${idx + 1}',
                style: TextStyle(color: atual ? const Color(0xFFF5B82E) : Colors.white70, fontWeight: FontWeight.w800),
              ),
              title: Text(ep.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
              trailing: Text(ep.resolucao, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
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
    _osdTimer = Timer(const Duration(milliseconds: 800), () {
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

  void _focarPrimeiroBotao(FocusNode container) {
    final filhos = container.descendants.where((n) => n.canRequestFocus).toList();
    if (filhos.isNotEmpty) {
      filhos.first.requestFocus();
    }
  }

  void _focarPlayPause() {
    final filhos = _centroControlsFocus.descendants.where((n) => n.canRequestFocus).toList();
    if (filhos.length >= 2) {
      filhos[1].requestFocus();
    } else if (filhos.isNotEmpty) {
      filhos.first.requestFocus();
    }
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
    final podePularAbertura = widget.obra.isSerie &&
        _erroPlayer == null &&
        _introFim > _introInicio + 10 &&
        _posicao.inSeconds >= _introInicio &&
        _posicao.inSeconds <= (_introFim - 3);
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
            if (_controlesVisiveis && !_carregandoStream && _erroPlayer == null) {
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
            if (_controlesVisiveis && !_carregandoStream && _erroPlayer == null) {
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
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.82),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF5B82E).withOpacity(0.5)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFFF5B82E)),
                        const SizedBox(height: 14),
                        Text(
                          _statusCarregamento,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        if (_progressoCarregamento != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 180,
                            child: LinearProgressIndicator(
                              value: _progressoCarregamento,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation(Color(0xFFF5B82E)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              if (_osdTexto != null && !_carregandoStream)
                Align(
                  alignment: const Alignment(0, -0.58),
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
              if (_mostrarBotaoInicio && _erroPlayer == null)
                Positioned(
                  left: 28,
                  bottom: 92,
                  child: CinemaFocusBox(
                    borderRadius: 8,
                    onTap: () {
                      _player.seek(Duration.zero);
                      setState(() => _mostrarBotaoInicio = false);
                      _mostrarOsd(Icons.replay, 'Reiniciado do início');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFF5B82E))),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.replay, color: Color(0xFFF5B82E), size: 18),
                          SizedBox(width: 6),
                          Text('Assistir do início', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 28,
                bottom: 92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<Duration>(
                      valueListenable: _posNotifier,
                      builder: (_, pos, __) {
                        final ativo = widget.obra.isSerie &&
                            _erroPlayer == null &&
                            _introFim > _introInicio + 10 &&
                            pos.inSeconds >= _introInicio &&
                            pos.inSeconds <= (_introFim - 3);
                        if (!ativo) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CinemaFocusBox(
                            onTap: _pularAbertura,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              decoration: BoxDecoration(color: const Color(0xFFF5B82E), borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.fast_forward, color: Colors.black),
                                  const SizedBox(width: 6),
                                  Text('Pular Abertura (${(_introFim - pos.inSeconds).clamp(1, 240)}s)', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_contagemAutoPlay > 0 && prox != null && _erroPlayer == null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CinemaFocusBox(
                            borderRadius: 8,
                            onTap: () {
                              _autoPlayTimer?.cancel();
                              _autoPlayTimer = null;
                              setState(() => _contagemAutoPlay = 0);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white30)),
                              child: const Text('Cancelar', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          CinemaFocusBox(
                            borderRadius: 8,
                            onTap: () {
                              _autoPlayTimer?.cancel();
                              _autoPlayTimer = null;
                              setState(() => _contagemAutoPlay = 0);
                              _iniciarFonte(prox);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                              decoration: BoxDecoration(color: const Color(0xFFF5B82E), borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.skip_next, color: Colors.black),
                                  const SizedBox(width: 6),
                                  Text('Próximo (${prox.etiquetaEpisodio}) em ${_contagemAutoPlay}s', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (_controlesVisiveis && !_carregandoStream && _erroPlayer == null)
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
                            Focus(
                              focusNode: _voltarFocus,
                              canRequestFocus: false,
                              skipTraversal: true,
                              onKeyEvent: (_, e) { if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown) { _focarPlayPause(); _reiniciarTimerControles(); return KeyEventResult.handled; } return KeyEventResult.ignored; },
                              child: CinemaFocusBox(
                              borderRadius: 24,
                              onTap: () => Navigator.pop(context),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.arrow_back, color: Colors.white, size: 26),
                              ),
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
                      Focus(
                        focusNode: _centroControlsFocus,
                        canRequestFocus: false,
                        skipTraversal: true,
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent) {
                            if (event.logicalKey == LogicalKeyboardKey.arrowUp) { _focarPrimeiroBotao(_voltarFocus); _reiniciarTimerControles(); return KeyEventResult.handled; }
                            if (event.logicalKey == LogicalKeyboardKey.arrowDown) { _sliderFocus.requestFocus(); _reiniciarTimerControles(); return KeyEventResult.handled; }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Row(
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
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                        child: Column(
                          children: [
                            Focus(
                              focusNode: _sliderFocus,
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) { _focarPrimeiroBotao(_barraInferiorFocus); _reiniciarTimerControles(); return KeyEventResult.handled; }
                                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) { _focarPlayPause(); _reiniciarTimerControles(); return KeyEventResult.handled; }
                                  if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.arrowLeft) { final d = event.logicalKey == LogicalKeyboardKey.arrowRight ? 1 : -1; final now = DateTime.now(); final dbl = _ultDir == d && now.difference(_ultSeek).inMilliseconds < 380; _ultSeek = now; _ultDir = d; _buscarRelativo(dbl ? 30 * d : 15 * d); return KeyEventResult.handled; }
                                } else if (event is KeyRepeatEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.arrowRight) { _buscarRelativo(45); return KeyEventResult.handled; }
                                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) { _buscarRelativo(-45); return KeyEventResult.handled; }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Builder(
                                builder: (fCtx) {
                                  final focado = Focus.of(fCtx).hasFocus;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: focado ? const Color(0xFFF5B82E) : Colors.transparent, width: 2),
                                      color: focado ? const Color(0xFFF5B82E).withOpacity(0.14) : Colors.transparent,
                                    ),
                                    child: ValueListenableBuilder<Duration>(
                                      valueListenable: _posNotifier,
                                      builder: (_, pos, __) {
                                        final dur = _durNotifier.value;
                                        return Row(
                                          children: [
                                            Text(_formatarTempo(pos), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                            Expanded(
                                              child: Slider(
                                                focusNode: _sliderInternalFocus,
                                                value: dur.inMilliseconds > 0 ? pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble() : 0,
                                                max: dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1,
                                                activeColor: const Color(0xFFF5B82E),
                                                inactiveColor: Colors.white24,
                                                onChangeEnd: (v) {
                                                  _player.seek(Duration(milliseconds: v.toInt()));
                                                  _reiniciarTimerControles();
                                                },
                                                onChanged: (v) {
                                                  _posNotifier.value = Duration(milliseconds: v.toInt());
                                                  _reiniciarTimerControles();
                                                },
                                              ),
                                            ),
                                            Text(_formatarTempo(dur), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                          ],
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                            FocusTraversalGroup(
                              policy: ReadingOrderTraversalPolicy(),
                              child: Focus(
                                focusNode: _barraInferiorFocus,
                                canRequestFocus: false,
                                skipTraversal: true,
                                onKeyEvent: (_, event) {
                                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                    _sliderFocus.requestFocus();
                                    _reiniciarTimerControles();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: Row(
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
                              ),
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
