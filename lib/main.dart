import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/midia_model.dart';
import 'services/supabase_service.dart';
import 'services/catalog_audit_service.dart';
import 'widgets/cinema_widgets.dart';
import 'screens/tv_home_screen.dart';
import 'screens/tv_aux_screens.dart';
import 'screens/detalhe_obra_screen.dart';
import 'services/app_updater_service.dart';
import 'services/max_assistant_service.dart';
import 'services/max_memory_service.dart';
import 'widgets/max_assistant_overlay.dart';
import 'widgets/perfis_usuario_screen.dart';

class CinemaOrientation {
  static bool emPlayer = false;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  http.get(Uri.parse('https://roboscrap-backend-l9t8.onrender.com/docs')).catchError((_) => http.Response('', 500));
  runApp(const AppCinema());
}

class AppCinema extends StatelessWidget {
  const AppCinema({super.key});

  @override
  Widget build(BuildContext context) {
    PaintingBinding.instance.imageCache.maximumSize = 50;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 35 * 1024 * 1024;
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      child: MaterialApp(
        title: 'CineMax',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0A0C10),
          primaryColor: const Color(0xFFF5B82E),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFF5B82E),
            secondary: Color(0xFFF5B82E),
            surface: Color(0xFF141822),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
          ),
        ),
        home: const CinemaBootstrapScreen(),
      ),
    );
  }
}

class CinemaBootstrapScreen extends StatefulWidget {
  const CinemaBootstrapScreen({super.key});

  @override
  State<CinemaBootstrapScreen> createState() => _CinemaBootstrapScreenState();
}

class _CinemaBootstrapScreenState extends State<CinemaBootstrapScreen> {
  final ValueNotifier<int> _abaNotifier = ValueNotifier<int>(0);
  List<ObraAgrupada> _catalogo = [];
  bool _carregando = true;
  bool _perfilSelecionado = false;
  bool? _modoTvForcado;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    await MaxMemoryService.instance.inicializar();
    await MaxAssistantService.instance.inicializar();
    final prefs = await SharedPreferences.getInstance();
    final modoSalvo = prefs.getBool('modo_tv_forcado');
    final obras = await SupabaseService.carregarCatalogoAgrupado();
    MaxAssistantService.instance.atualizarCatalogo(obras);
    MaxAssistantService.instance.onExecutarAcao = _executarAcaoMax;
    if (mounted) {
      setState(() {
        _modoTvForcado = modoSalvo;
        _catalogo = obras;
        _carregando = false;
      });
    }
  }

  void _onPerfilConfirmado() {
    if (!mounted) return;
    setState(() => _perfilSelecionado = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) AppUpdaterService.verificarAtualizacao(context, silencioso: true);
    });
  }

  void _irAba(int i, String n) { Navigator.of(context).popUntil((r) => r.isFirst); _abaNotifier.value = i; MaxAssistantService.instance.definirObraEmVisualizacao(null); MaxAssistantService.instance.definirContextoTela(tela: 'home', aba: n); }
  void _executarAcaoMax(MaxAcaoComando acao) {
    if (!mounted) return;
    if (acao.tipo == 'ir_inicio') { _irAba(0, 'Início'); return; }
    if (acao.tipo == 'ir_filmes') { _irAba(1, 'Filmes'); return; }
    if (acao.tipo == 'ir_series') { _irAba(2, 'Séries'); return; }
    if (acao.tipo == 'ir_kids') { _irAba(3, 'Kids'); return; }
    if (acao.tipo == 'ir_anime') { _irAba(4, 'Anime'); return; }
    final listaAtual = _catalogoFiltradoPerfil;
    if (acao.tipo == 'abrir_titulo' && (acao.titulo ?? '').isNotEmpty) {
      final q = SupabaseService.normalizarTexto(acao.titulo!);
      final match = listaAtual.where((o) => SupabaseService.normalizarTexto(o.titulo).contains(q) || SupabaseService.normalizarTexto(o.tituloOriginal).contains(q)).toList();
      if (match.isNotEmpty) { _abrirObra(match.first); return; }
    }
    if (acao.tipo == 'abrir_favoritos') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TvHistoricoFavoritosScreen(catalogo: listaAtual, onAbrirObra: _abrirObra)));
      return;
    }
    if (acao.tipo == 'abrir_pedidos') { PedidosScreenModal.abrir(context); return; }
    if (acao.tipo == 'abrir_busca' || acao.tipo == 'buscar_termo' || acao.tipo == 'filtrar_streaming') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TvBuscaScreen(catalogo: listaAtual, onAbrirObra: _abrirObra)));
    }
  }

  List<ObraAgrupada> get _catalogoFiltradoPerfil {
    if (!MaxMemoryService.instance.modoKidsAtivo) return _catalogo;
    return _catalogo.where((o) {
      final c = SupabaseService.normalizarTexto(o.categoria);
      final g = SupabaseService.normalizarTexto(o.genero);
      final t = o.tags.map((e) => SupabaseService.normalizarTexto(e)).toList();
      final ehAnime = c.contains('anime') || g.contains('anime') || t.contains('anime') ||
          CatalogAuditService.ehAnime(titulo: o.titulo, generos: o.genero.split(','), tags: o.tags, paisOrigem: o.pais, sinopse: o.sinopse);
      if (ehAnime) return false;
      return c.contains('kids') || c.contains('infantil') || g.contains('infantil') || g.contains('animacao') || g.contains('familia') || t.contains('kids');
    }).toList();
  }

  Future<void> _recarregarCatalogo() async {
    setState(() => _carregando = true);
    final obras = await SupabaseService.carregarCatalogoAgrupado(forcarRefresh: true);
    if (mounted) {
      setState(() {
        _catalogo = obras;
        _carregando = false;
      });
    }
  }

  Future<void> _alternarModo(bool paraTv) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('modo_tv_forcado', paraTv);
    setState(() => _modoTvForcado = paraTv);
  }

  void _abrirObra(ObraAgrupada obra) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalheObraScreen(
          obra: obra,
          catalogoCompleto: _catalogo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0C10),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CinemaLogoWidget(height: 64, width: 220),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Color(0xFFF5B82E)),
            ],
          ),
        ),
      );
    }

    if (!_perfilSelecionado) {
      return PerfisSelectionOverlay(obrigatorio: true, onPerfilSelecionado: _onPerfilConfirmado);
    }
    final catalogoAtivo = _catalogoFiltradoPerfil;
    final size = MediaQuery.of(context).size;
    final isTvAuto = size.shortestSide >= 650;
    final usarLayoutTv = _modoTvForcado ?? isTvAuto;

    if (usarLayoutTv) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      return TvHomeScreen(catalogo: catalogoAtivo, onRefresh: _recarregarCatalogo, onAbrirObra: _abrirObra, onAlternarModoMobile: () => _alternarModo(false), abaExternaNotifier: _abaNotifier);
    }
    if (!CinemaOrientation.emPlayer) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    return MobileHomeScreen(catalogo: catalogoAtivo, onRefresh: _recarregarCatalogo, onAbrirObra: _abrirObra, onAlternarModoTv: () => _alternarModo(true), abaExternaNotifier: _abaNotifier);
  }
}

class MobileHomeScreen extends StatefulWidget {
  final List<ObraAgrupada> catalogo;
  final Future<void> Function() onRefresh;
  final void Function(ObraAgrupada) onAbrirObra;
  final VoidCallback onAlternarModoTv;
  final ValueNotifier<int>? abaExternaNotifier;

  const MobileHomeScreen({
    super.key,
    required this.catalogo,
    required this.onRefresh,
    required this.onAbrirObra,
    required this.onAlternarModoTv,
    this.abaExternaNotifier,
  });

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  int _abaIndex = 0;
  Map<String, Map<String, dynamic>> _progressoMap = {};
  static const List<String> _abas = ['Início', 'Filmes', 'Séries', 'Kids', 'Anime'];

  void _onAbaExtM() { final i = widget.abaExternaNotifier?.value; if (i != null && i != _abaIndex && mounted) { setState(() => _abaIndex = i); MaxAssistantService.instance.definirContextoTela(tela: 'home', aba: _abas[i]); } }
  @override
  void initState() {
    super.initState();
    widget.abaExternaNotifier?.addListener(_onAbaExtM);
    MaxAssistantService.instance.definirContextoTela(tela: 'home', aba: _abas[_abaIndex]);
    _carregarProgresso();
  }
  @override
  void dispose() {
    _abaNotifier.dispose(); widget.abaExternaNotifier?.removeListener(_onAbaExtM); super.dispose(); }

  Future<void> _carregarProgresso() async {
    final p = await SupabaseService.carregarProgressoAssistido();
    if (mounted) setState(() => _progressoMap = p);
  }

  List<ObraAgrupada> get _listaAba {
    if (_abaIndex == 0) return widget.catalogo;
    if (_abaIndex == 1) {
      return widget.catalogo.where((o) => o.categoria.toLowerCase().contains('filme') && !o.isSerie).toList();
    }
    if (_abaIndex == 2) {
      return widget.catalogo.where((o) => o.isSerie).toList();
    }
    bool ehAnimeObra(ObraAgrupada o) {
      final c = SupabaseService.normalizarTexto(o.categoria);
      final g = SupabaseService.normalizarTexto(o.genero);
      final t = o.tags.map((e) => SupabaseService.normalizarTexto(e)).toList();
      if (c.contains('anime') || g.contains('anime') || t.contains('anime')) return true;
      return CatalogAuditService.ehAnime(
        titulo: o.titulo,
        generos: o.genero.split(','),
        tags: o.tags,
        paisOrigem: o.pais,
        sinopse: o.sinopse,
      );
    }
    if (_abaIndex == 3) {
      return widget.catalogo.where((o) {
        if (ehAnimeObra(o)) return false;
        final c = SupabaseService.normalizarTexto(o.categoria);
        final g = SupabaseService.normalizarTexto(o.genero);
        return c.contains('kids') || c.contains('infantil') || g.contains('infantil') || g.contains('animacao');
      }).toList();
    }
    return widget.catalogo.where(ehAnimeObra).toList();
  }

  List<ObraAgrupada> _porGenero(List<ObraAgrupada> base, String termo) {
    final q = SupabaseService.normalizarTexto(termo);
    return base.where((o) {
      final g = SupabaseService.normalizarTexto(o.genero);
      final t = o.tags.map((e) => SupabaseService.normalizarTexto(e)).toList();
      return g.contains(q) || t.any((x) => x.contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final base = _listaAba;
    final vm = <String>{}; final baseComCapa = base.where((o) { if (o.capaUrl.isEmpty && o.bannerUrl.isEmpty) return false; final k = SupabaseService.normalizarTexto(o.titulo).replaceAll(RegExp(r'[^a-z0-9]'), ''); return k.isNotEmpty && vm.add(k); }).toList();
    final listaVitrine = baseComCapa.isNotEmpty ? baseComCapa : base;
    final destaques = listaVitrine.where((o) => o.emDestaque).take(6).toList();
    if (destaques.isEmpty && listaVitrine.isNotEmpty) {
      destaques.addAll(listaVitrine.take(5));
    }
    final continuar = widget.catalogo.where((o) => _progressoMap.containsKey(o.chaveGrupo)).toList();
    final top10 = List<ObraAgrupada>.from(listaVitrine)
      ..sort((a, b) => b.scorePopularidade.compareTo(a.scorePopularidade));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      appBar: AppBar(
        titleSpacing: 8,
        title: const CinemaLogoWidget(height: 30, width: 102),
        actions: [
          Center(child: Padding(padding: const EdgeInsets.only(right: 4), child: MaxMicButton(onPressed: () => MaxAssistantModal.abrir(context)))),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvBuscaScreen(catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra))),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Modo TV Box',
            icon: const Icon(Icons.tv_rounded, color: Color(0xFFF5B82E)),
            onPressed: widget.onAlternarModoTv,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF141822),
            onSelected: (v) {
              if (v == 'perfil') {
                PerfisSelectionOverlay.abrir(context, onPerfilSelecionado: () { if (mounted) setState(() {}); });
              } else if (v == 'pedidos') {
                PedidosScreenModal.abrir(context);
              } else if (v == 'filtro') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => TvFiltroScreen(catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra)));
              } else if (v == 'historico') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => TvHistoricoFavoritosScreen(catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra)));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'perfil', child: ListTile(dense: true, leading: Icon(Icons.person, color: Color(0xFFF5B82E)), title: Text('Trocar Perfil'))),
              PopupMenuItem(value: 'pedidos', child: ListTile(dense: true, leading: Icon(Icons.playlist_add_rounded, color: Color(0xFFF5B82E)), title: Text('Pedidos'))),
              PopupMenuItem(value: 'filtro', child: ListTile(dense: true, leading: Icon(Icons.filter_alt_outlined, color: Colors.white), title: Text('Filtro Avançado'))),
              PopupMenuItem(value: 'historico', child: ListTile(dense: true, leading: Icon(Icons.history, color: Colors.white), title: Text('Favoritos e Histórico'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: _abas.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, idx) {
                final ativo = idx == _abaIndex;
                return ChoiceChip(
                  label: Text(_abas[idx]),
                  selected: ativo,
                  selectedColor: const Color(0xFFF5B82E),
                  labelStyle: TextStyle(color: ativo ? Colors.black : Colors.white, fontWeight: FontWeight.w800),
                  onSelected: (_) { setState(() => _abaIndex = idx); MaxAssistantService.instance.definirContextoTela(tela: 'home', aba: _abas[idx]); },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFFF5B82E),
              onRefresh: widget.onRefresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                children: [
                  if (destaques.isNotEmpty)
                    SizedBox(
                      height: 190,
                      child: PageView.builder(
                        itemCount: destaques.length,
                        itemBuilder: (_, idx) {
                          final o = destaques[idx];
                          final img = o.bannerUrl.isNotEmpty ? o.bannerUrl : o.capaUrl;
                          return GestureDetector(
                            onTap: () => widget.onAbrirObra(o),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (img.isNotEmpty)
                                    CachedNetworkImage(imageUrl: img, fit: BoxFit.cover)
                                  else
                                    Container(color: const Color(0xFF161B26)),
                                  Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Colors.transparent, Colors.black87],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 14,
                                    right: 14,
                                    bottom: 12,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(o.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                                        Text('${o.ano} • ${o.genero}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5B82E), foregroundColor: Colors.black),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TvTop100RankingScreen(fonte: 'imdb', catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra),
                            ),
                          ),
                          icon: const Icon(Icons.emoji_events, size: 18),
                          label: const Text('Top 100 IMDb', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF181E2B), foregroundColor: const Color(0xFFF5B82E)),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TvTop100RankingScreen(fonte: 'tmdb', catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra),
                            ),
                          ),
                          icon: const Icon(Icons.star_rate_rounded, size: 18),
                          label: const Text('Top 100 TMDB', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_abaIndex == 0 && continuar.isNotEmpty)
                    _buildShelfMobile('Continuar Assistindo', continuar, mostrarProgresso: true),
                  if (_abaIndex == 0 && top10.isNotEmpty)
                    _buildShelfMobile('Top 10 em Alta', top10.take(10).toList(), numerado: true),
                  _buildShelfMobile('Adicionados Recentemente', listaVitrine.take(20).toList()),
                  _buildShelfMobile('Ação', _porGenero(listaVitrine, 'Ação')),
                  _buildShelfMobile('Suspense e Mistério', _porGenero(listaVitrine, 'Suspense')),
                  _buildShelfMobile('Drama', _porGenero(listaVitrine, 'Drama')),
                  _buildShelfMobile('Comédia', _porGenero(listaVitrine, 'Comédia')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfMobile(
    String titulo,
    List<ObraAgrupada> itens, {
    bool numerado = false,
    bool mostrarProgresso = false,
  }) {
    if (itens.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          SizedBox(
            height: 235,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: itens.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, idx) {
                final obra = itens[idx];
                final prog = mostrarProgresso
                    ? (_progressoMap[obra.chaveGrupo]?['progresso'] as double?)
                    : null;
                return TvPosterCard(
                  obra: obra,
                  width: 132,
                  rankNumero: numerado ? idx + 1 : null,
                  progresso: prog,
                  onTap: () {
                    widget.onAbrirObra(obra);
                    Future.delayed(const Duration(seconds: 2), _carregarProgresso);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
