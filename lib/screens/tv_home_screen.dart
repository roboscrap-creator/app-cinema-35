import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../services/live_sports_service.dart';
import '../services/max_memory_service.dart';
import '../widgets/cinema_widgets.dart';
import '../widgets/max_assistant_overlay.dart';
import '../widgets/perfis_usuario_screen.dart';
import 'detalhe_obra_screen.dart';
import 'player_screen.dart';
import 'tv_aux_screens.dart';

class TvHomeScreen extends StatefulWidget {
  final List<ObraAgrupada> catalogo;
  final VoidCallback onRefresh;
  final VoidCallback onToggleModoMobile;

  const TvHomeScreen({
    super.key,
    required this.catalogo,
    required this.onRefresh,
    required this.onToggleModoMobile,
  });

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  static const List<String> _abas = [
    'Início', 'Filmes', 'Séries', 'Sports', 'TV',
    'Kids', 'Animes', 'Max', 'Procurar', 'Favoritos',
    'Pedidos', 'Histórico',
  ];

  String _abaAtual = 'Início';
  int _bannerIndex = 0;
  Timer? _bannerTimer;
  List<JogoAoVivoInfo> _jogosAoVivo = [];
  bool _carregandoJogos = true;

  @override
  void initState() {
    super.initState();
    _inicializarDadosTv();
    _iniciarCarrossel();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _iniciarCarrossel() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _abaAtual != 'Início') return;
      final filmes = _filmesDestaque;
      if (filmes.length > 1) {
        setState(() => _bannerIndex = (_bannerIndex + 1) % filmes.length);
      }
    });
  }

  Future<void> _inicializarDadosTv() async {
    await SupabaseService.instance.carregarTendenciasTmdb();
    final jogos = await LiveSportsService.instance.buscarJogosPrincipais();
    if (mounted) {
      setState(() {
        _jogosAoVivo = jogos;
        _carregandoJogos = false;
      });
    }
  }

  bool _ehSports(ObraAgrupada o) {
    final t = '${o.tipo} ${o.categoria} ${o.genero} ${o.tags} ${o.titulo}'.toLowerCase();
    return t.contains('sport') || t.contains('esporte') || t.contains('futebol') ||
        t.contains('premiere') || t.contains('espn') || t.contains('sportv') ||
        t.contains('caze') || t.contains('combate') || t.contains('ufc') || t.contains('nba');
  }

  bool _ehTvAoVivo(ObraAgrupada o) {
    if (_ehSports(o)) return false;
    final tipo = o.tipo.toLowerCase();
    final cat = '${o.categoria} ${o.tags}'.toLowerCase();
    return tipo.contains('tv') || tipo.contains('canal') || tipo.contains('live') ||
        cat.contains('tv ao vivo') || cat.contains('canais');
  }

  bool _ehAnime(ObraAgrupada o) =>
      '${o.tipo} ${o.categoria} ${o.genero} ${o.tags}'.toLowerCase().contains('anime');

  bool _ehKids(ObraAgrupada o) {
    final t = '${o.tipo} ${o.categoria} ${o.genero} ${o.tags}'.toLowerCase();
    return t.contains('kids') || t.contains('infantil') ||
        t.contains('animação') || t.contains('animacao') || t.contains('desenho');
  }

  bool _ehSerie(ObraAgrupada o) {
    if (_ehSports(o) || _ehTvAoVivo(o)) return false;
    final t = o.tipo.toLowerCase();
    return t.contains('serie') || t.contains('série') || t.contains('novela') || t.contains('dorama');
  }

  bool _ehFilme(ObraAgrupada o) => !_ehSports(o) && !_ehTvAoVivo(o) && !_ehSerie(o);

  List<ObraAgrupada> get _todosFilmes =>
      SupabaseService.instance.ordenarCronologicoRelevancia(widget.catalogo.where(_ehFilme).toList());

  List<ObraAgrupada> get _todasSeries =>
      SupabaseService.instance.ordenarCronologicoRelevancia(widget.catalogo.where(_ehSerie).toList());

  List<ObraAgrupada> get _canaisSports => widget.catalogo.where(_ehSports).toList();
  List<ObraAgrupada> get _canaisTv => widget.catalogo.where(_ehTvAoVivo).toList();

  List<ObraAgrupada> get _obrasKids =>
      SupabaseService.instance.ordenarCronologicoRelevancia(widget.catalogo.where(_ehKids).toList());

  List<ObraAgrupada> get _obrasAnimes =>
      SupabaseService.instance.ordenarCronologicoRelevancia(widget.catalogo.where(_ehAnime).toList());

  List<ObraAgrupada> get _filmesDestaque =>
      SupabaseService.instance.selecionarDestaquesBanner(candidatos: _todosFilmes, limite: 6);

  List<ObraAgrupada> get _seriesDestaque =>
      SupabaseService.instance.selecionarDestaquesBanner(candidatos: _todasSeries, limite: 5);

  void _abrirObra(ObraAgrupada obra) {
    if (_ehSports(obra) || _ehTvAoVivo(obra)) {
      _reproduzirDireto(obra);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetalheObraScreen(obra: obra)));
  }

  Future<void> _reproduzirDireto(ObraAgrupada obra) async {
    final fontes = await SupabaseService.instance.buscarFontesDaObra(obra);
    if (!mounted) return;
    if (fontes.isEmpty) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetalheObraScreen(obra: obra)));
      return;
    }
    final f = fontes.first;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CinemaPlayerScreen(
          titulo: obra.titulo,
          url: f.streamUrl,
          subtitulo: obra.categoria,
          obra: obra,
          fonteAtual: f,
          fontesDisponiveis: fontes,
        ),
      ),
    );
  }

  void _abrirHubStreaming(String nomeHub, List<String> termos) {
    final lowTermos = termos.map((e) => e.toLowerCase()).toList();
    final filtrados = SupabaseService.instance.ordenarCronologicoRelevancia(
      widget.catalogo.where((o) {
        final blob = '${o.titulo} ${o.categoria} ${o.genero} ${o.tags}'.toLowerCase();
        return lowTermos.any((t) => blob.contains(t));
      }).toList(),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TvExploradorCompletoScreen(
          tituloPagina: nomeHub,
          obrasIniciais: filtrados,
          filtroTermoHub: termos.first,
          onAbrirObra: _abrirObra,
        ),
      ),
    );
  }

  void _selecionarAba(String aba) {
    if (aba == 'Max') {
      MaxAssistantModal.abrir(context);
      return;
    }
    if (aba == 'Procurar') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TvBuscaScreen(catalogo: widget.catalogo, onAbrirObra: _abrirObra)),
      );
      return;
    }
    if (aba == 'Pedidos') {
      PedidosScreenModal.abrir(context);
      return;
    }
    setState(() => _abaAtual = aba);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      body: SafeArea(
        child: Column(
          children: [
            _buildBarraSuperior(),
            Expanded(child: _buildConteudoAba()),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraSuperior() {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0F16),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          const CinemaLogoWidget(height: 34, width: 132),
          const SizedBox(width: 14),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _abas.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, idx) {
                final aba = _abas[idx];
                final ativa = _abaAtual == aba;
                return Center(
                  child: CinemaFocusBox(
                    autofocus: idx == 0,
                    borderRadius: 20,
                    scaleOnFocus: 1.06,
                    onTap: () => _selecionarAba(aba),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: ativa ? const Color(0xFFF5B82E) : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        aba,
                        style: TextStyle(
                          color: ativa ? const Color(0xFF090B10) : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          TopIconeComTooltip(
            icon: Icons.refresh_rounded,
            label: 'Atualizar Catálogo & Jogos',
            onPressed: () {
              widget.onRefresh();
              _inicializarDadosTv();
            },
          ),
          const SizedBox(width: 8),
          TopIconeComTooltip(
            icon: Icons.smartphone_rounded,
            label: 'Mudar para Modo Celular',
            onPressed: widget.onToggleModoMobile,
          ),
          const SizedBox(width: 8),
          PerfilChipTopButton(
            onTap: () => PerfisSelectionOverlay.abrir(
              context,
              onPerfilSelecionado: () {
                if (mounted) setState(() {});
                widget.onRefresh();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudoAba() {
    switch (_abaAtual) {
      case 'Início':
        return _buildInicioBentoTv();
      case 'Filmes':
        return TvVitrineCategoriaScreen(titulo: 'Filmes', tipoBanco: 'Filme', obras: _todosFilmes, onAbrirObra: _abrirObra);
      case 'Séries':
        return TvVitrineCategoriaScreen(titulo: 'Séries', tipoBanco: 'Serie', obras: _todasSeries, onAbrirObra: _abrirObra);
      case 'Kids':
        return TvVitrineCategoriaScreen(titulo: 'Kids & Família', tipoBanco: '', obras: _obrasKids, onAbrirObra: _abrirObra);
      case 'Animes':
        return TvVitrineCategoriaScreen(titulo: 'Animes', tipoBanco: '', obras: _obrasAnimes, onAbrirObra: _abrirObra);
      case 'Sports':
        return TvCanaisGradeScreen(titulo: 'Sports Ao Vivo', canais: _canaisSports, jogosAoVivo: _jogosAoVivo, onAbrirCanal: _reproduzirDireto);
      case 'TV':
        return TvCanaisGradeScreen(titulo: 'Canais de TV Ao Vivo', canais: _canaisTv, jogosAoVivo: const [], onAbrirCanal: _reproduzirDireto);
      case 'Favoritos':
        final favs = <ObraAgrupada>[];
        return TvVitrineCategoriaScreen(titulo: 'Meus Favoritos', tipoBanco: '', obras: favs, onAbrirObra: _abrirObra);
      case 'Histórico':
        final histObras = <ObraAgrupada>[];
        return TvVitrineCategoriaScreen(titulo: 'Continuar Assistindo', tipoBanco: '', obras: histObras, onAbrirObra: _abrirObra);
      default:
        return _buildInicioBentoTv();
    }
  }

  Widget _buildInicioBentoTv() {
    final filmesBanner = _filmesDestaque;
    final seriesFila = _seriesDestaque;
    final filmesRecentes = _todosFilmes.take(18).toList();
    final seriesRecentes = _todasSeries.take(18).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 410,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 62,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 58, child: _buildBannerRotativoFilmes(filmesBanner)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('Séries em Alta (TMDB & IMDb)',
                              style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          CinemaFocusBox(
                            borderRadius: 12,
                            onTap: () => _selecionarAba('Séries'),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              child: Text('Ver todas ›',
                                  style: TextStyle(color: Color(0xFFF5B82E), fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Expanded(flex: 42, child: _buildFileira5Series(seriesFila)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(flex: 38, child: _buildColuna3JogosAoVivo()),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildBarraHubsInferior(),
          const SizedBox(height: 22),
          if (filmesRecentes.isNotEmpty) ...[
            _buildCabecalhoPrateleira(
              titulo: 'Lançamentos de Filmes (2026 • Em Alta)',
              total: _todosFilmes.length,
              onVerTodos: () => _selecionarAba('Filmes'),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 245,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                cacheExtent: 420,
                itemCount: filmesRecentes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => TvPosterCard(obra: filmesRecentes[i], onTap: () => _abrirObra(filmesRecentes[i])),
              ),
            ),
            const SizedBox(height: 20),
          ],
          if (seriesRecentes.isNotEmpty) ...[
            _buildCabecalhoPrateleira(
              titulo: 'Lançamentos de Séries (2026 • Em Alta)',
              total: _todasSeries.length,
              onVerTodos: () => _selecionarAba('Séries'),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 245,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                cacheExtent: 420,
                itemCount: seriesRecentes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => TvPosterCard(obra: seriesRecentes[i], onTap: () => _abrirObra(seriesRecentes[i])),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBannerRotativoFilmes(List<ObraAgrupada> filmes) {
    if (filmes.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: const Color(0xFF141824), borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: const Text('Carregando lançamentos de filmes...', style: TextStyle(color: Colors.white60)),
      );
    }

    final idx = _bannerIndex % filmes.length;
    final filme = filmes[idx];
    final temBackdrop = filme.bannerUrl.isNotEmpty;
    final imgUrl = temBackdrop ? filme.bannerUrl : filme.capaUrl;

    return CinemaFocusBox(
      borderRadius: 14,
      scaleOnFocus: 1.015,
      onTap: () => _abrirObra(filme),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111520),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (temBackdrop)
              Positioned(
                right: 0, top: 0, bottom: 0, width: 460,
                child: CachedNetworkImage(
                  imageUrl: imgUrl,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0.0, -0.25),
                  memCacheWidth: 960,
                  fadeInDuration: Duration.zero,
                ),
              )
            else if (imgUrl.isNotEmpty) ...[
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover, memCacheWidth: 320, fadeInDuration: Duration.zero),
              ),
              Container(color: Colors.black.withOpacity(0.55)),
              Positioned(
                right: 22, top: 14, bottom: 14,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover, memCacheWidth: 420, fadeInDuration: Duration.zero),
                  ),
                ),
              ),
            ],
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: [0.0, 0.44, 0.78, 1.0],
                  colors: [Color(0xFF0C0F17), Color(0xF20C0F17), Color(0x550C0F17), Colors.transparent],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFF5B82E), borderRadius: BorderRadius.circular(6)),
                        child: const Text('TOP LANÇAMENTOS • FILMES',
                            style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
                      ),
                      if (filme.ano.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(filme.ano, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                      if (filme.notaImdb > 0) ...[
                        const SizedBox(width: 8),
                        Text('★ ${filme.notaImdb.toStringAsFixed(1)} IMDb',
                            style: const TextStyle(color: Color(0xFFF5B82E), fontSize: 12, fontWeight: FontWeight.w800)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 340,
                    child: Text(filme.titulo, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900, height: 1.12)),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 330,
                    child: Text(filme.sinopse.isNotEmpty ? filme.sinopse : filme.genero,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(color: const Color(0xFFF5B82E), borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: Colors.black, size: 18),
                            SizedBox(width: 4),
                            Text('Assistir Agora', style: TextStyle(color: Colors.black, fontSize: 12.5, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: List.generate(filmes.length, (i) {
                          final sel = i == idx;
                          return GestureDetector(
                            onTap: () => setState(() => _bannerIndex = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(left: 5),
                              width: sel ? 20 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: sel ? const Color(0xFFF5B82E) : Colors.white38,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileira5Series(List<ObraAgrupada> series) {
    if (series.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: const Color(0xFF141824), borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.center,
        child: const Text('Nenhuma série em destaque no momento', style: TextStyle(color: Colors.white54, fontSize: 12)),
      );
    }
    return Row(
      children: List.generate(series.length, (i) {
        final s = series[i];
        final img = s.bannerUrl.isNotEmpty ? s.bannerUrl : s.capaUrl;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == series.length - 1 ? 0 : 8),
            child: CinemaFocusBox(
              borderRadius: 10,
              scaleOnFocus: 1.05,
              onTap: () => _abrirObra(s),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF151924),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (img.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: img, fit: BoxFit.cover, alignment: const Alignment(0.0, -0.2),
                        memCacheWidth: 360, fadeInDuration: Duration.zero,
                      ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xE6090B10)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 5, left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(4)),
                        child: Text('#${i + 1} SÉRIE',
                            style: const TextStyle(color: Color(0xFFF5B82E), fontSize: 9, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    Positioned(
                      left: 7, right: 7, bottom: 6,
                      child: Text(s.titulo, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, height: 1.15)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildColuna3JogosAoVivo() {
    if (_carregandoJogos && _jogosAoVivo.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: const Color(0xFF121622), borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Color(0xFFF5B82E)),
      );
    }
    final jogo1 = _jogosAoVivo.isNotEmpty ? _jogosAoVivo[0] : null;
    final jogo2 = _jogosAoVivo.length > 1 ? _jogosAoVivo[1] : null;
    final jogo3 = _jogosAoVivo.length > 2 ? _jogosAoVivo[2] : null;

    return Column(
      children: [
        Expanded(flex: 54, child: _buildCardJogoLive(jogo1, destaqueGrande: true)),
        const SizedBox(height: 10),
        Expanded(
          flex: 46,
          child: Row(
            children: [
              Expanded(child: _buildCardJogoLive(jogo2, destaqueGrande: false)),
              const SizedBox(width: 10),
              Expanded(child: _buildCardJogoLive(jogo3, destaqueGrande: false)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardJogoLive(JogoAoVivoInfo? jogo, {required bool destaqueGrande}) {
    final canaisSports = _canaisSports;
    final canalDestino = jogo != null
        ? LiveSportsService.instance.encontrarCanalParaJogo(jogo, canaisSports)
        : (canaisSports.isNotEmpty ? canaisSports.first : null);

    return CinemaFocusBox(
      borderRadius: 14,
      scaleOnFocus: 1.03,
      onTap: () => canalDestino != null ? _reproduzirDireto(canalDestino) : _selecionarAba('Sports'),
      child: Container(
        padding: EdgeInsets.all(destaqueGrande ? 14 : 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: destaqueGrande
                ? const [Color(0xFF1A2A1E), Color(0xFF0E141D)]
                : const [Color(0xFF171E2E), Color(0xFF0D1119)],
          ),
          border: Border.all(
            color: (jogo?.aoVivo == true) ? Colors.redAccent.withOpacity(0.75) : Colors.white.withOpacity(0.14),
            width: 1.3,
          ),
        ),
        child: jogo == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sports_soccer_rounded, color: Color(0xFFF5B82E), size: 30),
                  const SizedBox(height: 6),
                  Text('Sports Ao Vivo', textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: destaqueGrande ? 15 : 12, fontWeight: FontWeight.w800)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: jogo.aoVivo ? const Color(0xFFE53935) : const Color(0xFFF5B82E),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(jogo.aoVivo ? 'LIVE' : 'HOJE',
                            style: TextStyle(color: jogo.aoVivo ? Colors.white : Colors.black, fontSize: 9.5, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(jogo.campeonato, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildEscudoTime(nome: jogo.timeCasa, escudoUrl: jogo.escudoCasa, tamanho: destaqueGrande ? 44 : 28),
                      Column(
                        children: [
                          Text(jogo.aoVivo ? '${jogo.placarCasa} x ${jogo.placarFora}' : 'VS',
                              style: TextStyle(color: Colors.white, fontSize: destaqueGrande ? 20 : 14, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 2),
                          Text(jogo.statusTexto,
                              style: TextStyle(
                                color: jogo.aoVivo ? Colors.greenAccent : const Color(0xFFF5B82E),
                                fontSize: destaqueGrande ? 10.5 : 9,
                                fontWeight: FontWeight.w800,
                              )),
                        ],
                      ),
                      _buildEscudoTime(nome: jogo.timeFora, escudoUrl: jogo.escudoFora, tamanho: destaqueGrande ? 44 : 28),
                    ],
                  ),
                  const Spacer(),
                  if (canalDestino != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.42), borderRadius: BorderRadius.circular(6)),
                      child: Text('▶ ${canalDestino.titulo}', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFFDF73), fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildEscudoTime({required String nome, required String escudoUrl, required double tamanho}) {
    return SizedBox(
      width: tamanho + 34,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (escudoUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: escudoUrl, width: tamanho, height: tamanho, fit: BoxFit.contain,
              memCacheWidth: 120, fadeInDuration: Duration.zero,
              errorWidget: (_, __, ___) => Icon(Icons.shield_rounded, color: Colors.white54, size: tamanho),
            )
          else
            Icon(Icons.shield_rounded, color: Colors.white54, size: tamanho),
          const SizedBox(height: 4),
          Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildBarraHubsInferior() {
    final hubs = [
      {'nome': 'NETFLIX', 'cor': const Color(0xFFE50914), 'onTap': () => _abrirHubStreaming('Catálogo Netflix', ['netflix'])},
      {'nome': 'PRIME VIDEO', 'cor': const Color(0xFF00A8E1), 'onTap': () => _abrirHubStreaming('Catálogo Prime Video', ['prime video', 'amazon', 'prime'])},
      {'nome': 'HBO MAX', 'cor': const Color(0xFF7B2CBF), 'onTap': () => _abrirHubStreaming('Catálogo HBO Max', ['hbo', 'max'])},
      {'nome': 'DISNEY+', 'cor': const Color(0xFF113CCF), 'onTap': () => _abrirHubStreaming('Catálogo Disney+', ['disney', 'pixar', 'marvel', 'star wars'])},
      {'nome': 'ESPN', 'cor': const Color(0xFFD00000), 'onTap': () => _abrirHubStreaming('Canais & Jogos ESPN', ['espn'])},
      {'nome': 'PREMIERE / SPORTV', 'cor': const Color(0xFF1B8A3D), 'onTap': () => _abrirHubStreaming('Premiere & SporTV Ao Vivo', ['premiere', 'sportv', 'globo'])},
      {'nome': 'TELECINE', 'cor': const Color(0xFFB5179E), 'onTap': () => _abrirHubStreaming('Catálogo Telecine', ['telecine'])},
    ];

    return SizedBox(
      height: 54,
      child: Row(
        children: List.generate(hubs.length, (i) {
          final h = hubs[i];
          final cor = h['cor'] as Color;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == hubs.length - 1 ? 0 : 10),
              child: CinemaFocusBox(
                borderRadius: 11,
                scaleOnFocus: 1.05,
                onTap: h['onTap'] as VoidCallback,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [cor.withOpacity(0.88), const Color(0xFF121622)],
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.16)),
                  ),
                  child: Text(h['nome'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCabecalhoPrateleira({required String titulo, required int total, required VoidCallback onVerTodos}) {
    return Row(
      children: [
        Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(width: 8),
        Text('($total)', style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w700)),
        const Spacer(),
        CinemaFocusBox(
          borderRadius: 14,
          onTap: onVerTodos,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text('Ver todos ›', style: TextStyle(color: Color(0xFFF5B82E), fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}
