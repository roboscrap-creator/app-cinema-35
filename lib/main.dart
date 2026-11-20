import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/midia_model.dart';
import 'services/supabase_service.dart';
import 'widgets/cinema_widgets.dart';
import 'screens/tv_home_screen.dart';
import 'screens/tv_aux_screens.dart';
import 'screens/detalhe_obra_screen.dart';

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
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      child: MaterialApp(
        title: 'Cinema',
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
  List<ObraAgrupada> _catalogo = [];
  bool _carregando = true;
  bool? _modoTvForcado;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();
    final modoSalvo = prefs.getBool('modo_tv_forcado');
    final obras = await SupabaseService.carregarCatalogoAgrupado();
    if (mounted) {
      setState(() {
        _modoTvForcado = modoSalvo;
        _catalogo = obras;
        _carregando = false;
      });
    }
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

    final size = MediaQuery.of(context).size;
    final isTvAuto = size.shortestSide >= 650;
    final usarLayoutTv = _modoTvForcado ?? isTvAuto;

    if (usarLayoutTv) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      return TvHomeScreen(
        catalogo: _catalogo,
        onRefresh: _recarregarCatalogo,
        onAbrirObra: _abrirObra,
        onAlternarModoMobile: () => _alternarModo(false),
      );
    }

    if (!CinemaOrientation.emPlayer) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    return MobileHomeScreen(
      catalogo: _catalogo,
      onRefresh: _recarregarCatalogo,
      onAbrirObra: _abrirObra,
      onAlternarModoTv: () => _alternarModo(true),
    );
  }
}

class MobileHomeScreen extends StatefulWidget {
  final List<ObraAgrupada> catalogo;
  final Future<void> Function() onRefresh;
  final void Function(ObraAgrupada) onAbrirObra;
  final VoidCallback onAlternarModoTv;

  const MobileHomeScreen({
    super.key,
    required this.catalogo,
    required this.onRefresh,
    required this.onAbrirObra,
    required this.onAlternarModoTv,
  });

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  int _abaIndex = 0;
  static const List<String> _abas = ['Início', 'Filmes', 'Séries', 'Kids', 'Anime'];

  List<ObraAgrupada> get _listaAba {
    if (_abaIndex == 0) return widget.catalogo;
    if (_abaIndex == 1) {
      return widget.catalogo.where((o) => o.categoria.toLowerCase().contains('filme') && !o.isSerie).toList();
    }
    if (_abaIndex == 2) {
      return widget.catalogo.where((o) => o.isSerie).toList();
    }
    if (_abaIndex == 3) {
      return widget.catalogo.where((o) {
        final c = SupabaseService.normalizarTexto(o.categoria);
        final g = SupabaseService.normalizarTexto(o.genero);
        return c.contains('kids') || c.contains('infantil') || g.contains('animacao');
      }).toList();
    }
    return widget.catalogo.where((o) {
      final c = SupabaseService.normalizarTexto(o.categoria);
      final g = SupabaseService.normalizarTexto(o.genero);
      return c.contains('anime') || g.contains('anime');
    }).toList();
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
    final destaques = base.where((o) => o.emDestaque).take(6).toList();
    if (destaques.isEmpty && base.isNotEmpty) {
      destaques.addAll(base.take(5));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      appBar: AppBar(
        title: const CinemaLogoWidget(height: 34, width: 120),
        actions: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TvBuscaScreen(catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Filtro Avançado',
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TvFiltroScreen(catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Meus Favoritos e Histórico',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TvHistoricoFavoritosScreen(catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Modo TV Box',
            icon: const Icon(Icons.tv, color: Color(0xFFF5B82E)),
            onPressed: widget.onAlternarModoTv,
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
                  onSelected: (_) => setState(() => _abaIndex = idx),
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
                  _buildShelfMobile('Adicionados Recentemente', base.take(20).toList()),
                  _buildShelfMobile('Ação', _porGenero(base, 'Ação')),
                  _buildShelfMobile('Suspense e Mistério', _porGenero(base, 'Suspense')),
                  _buildShelfMobile('Drama', _porGenero(base, 'Drama')),
                  _buildShelfMobile('Comédia', _porGenero(base, 'Comédia')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfMobile(String titulo, List<ObraAgrupada> itens) {
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
              itemBuilder: (_, idx) => TvPosterCard(
                obra: itens[idx],
                width: 132,
                onTap: () => widget.onAbrirObra(itens[idx]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
