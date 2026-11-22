import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../widgets/cinema_widgets.dart';
import 'tv_aux_screens.dart';

class TvHomeScreen extends StatefulWidget {
  final List<ObraAgrupada> catalogo;
  final VoidCallback onRefresh;
  final void Function(ObraAgrupada) onAbrirObra;
  final VoidCallback onAlternarModoMobile;

  const TvHomeScreen({
    super.key,
    required this.catalogo,
    required this.onRefresh,
    required this.onAbrirObra,
    required this.onAlternarModoMobile,
  });

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  int _abaIndex = 0;
  final PageController _bannerFilmesCtrl = PageController();
  final PageController _bannerSeriesCtrl = PageController();
  int _idxBannerFilme = 0;
  int _idxBannerSerie = 0;
  Timer? _autoPlayTimer;
  Map<String, Map<String, dynamic>> _progressoMap = {};

  static const List<String> _abas = ['INÍCIO', 'FILMES', 'SÉRIES', 'KIDS', 'ANIME'];

  @override
  void initState() {
    super.initState();
    _carregarProgresso();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || _abaIndex != 0) return;
      if (_bannerFilmesCtrl.hasClients) {
        final nextF = (_idxBannerFilme + 1) % 4;
        _bannerFilmesCtrl.animateToPage(nextF, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      }
      if (_bannerSeriesCtrl.hasClients) {
        final nextS = (_idxBannerSerie + 1) % 4;
        _bannerSeriesCtrl.animateToPage(nextS, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      }
    });
  }

  Future<void> _carregarProgresso() async {
    final p = await SupabaseService.carregarProgressoAssistido();
    if (mounted) setState(() => _progressoMap = p);
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _bannerFilmesCtrl.dispose();
    _bannerSeriesCtrl.dispose();
    super.dispose();
  }

  List<ObraAgrupada> get _filmes => widget.catalogo
      .where((o) => o.categoria.toLowerCase().contains('filme') && !o.isSerie)
      .toList();

  List<ObraAgrupada> get _series =>
      widget.catalogo.where((o) => o.isSerie).toList();

  List<ObraAgrupada> get _kids => widget.catalogo.where((o) {
        final c = SupabaseService.normalizarTexto(o.categoria);
        final g = SupabaseService.normalizarTexto(o.genero);
        final t = o.tags.map((e) => SupabaseService.normalizarTexto(e)).toList();
        return c.contains('infantil') || c.contains('kids') || g.contains('infantil') || g.contains('animacao') || t.contains('kids');
      }).toList();

  List<ObraAgrupada> get _animes => widget.catalogo.where((o) {
        final c = SupabaseService.normalizarTexto(o.categoria);
        final g = SupabaseService.normalizarTexto(o.genero);
        final t = o.tags.map((e) => SupabaseService.normalizarTexto(e)).toList();
        return c.contains('anime') || g.contains('anime') || t.contains('anime');
      }).toList();

  List<ObraAgrupada> _filtrarTagOuGenero(List<ObraAgrupada> base, String termo) {
    final q = SupabaseService.normalizarTexto(termo);
    return base.where((o) {
      final g = SupabaseService.normalizarTexto(o.genero);
      final c = SupabaseService.normalizarTexto(o.categoria);
      final t = o.tags.map((e) => SupabaseService.normalizarTexto(e)).toList();
      return g.contains(q) || c.contains(q) || t.any((x) => x.contains(q));
    }).toList();
  }

  void _abrirBusca() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvBuscaScreen(catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra),
      ),
    ).then((_) => _carregarProgresso());
  }

  void _abrirFiltro([String tipo = 'Filmes']) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvFiltroScreen(catalogo: widget.catalogo, tipoInicial: tipo, onAbrirObra: widget.onAbrirObra),
      ),
    ).then((_) => _carregarProgresso());
  }

  void _abrirHistoricoFavoritos() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvHistoricoFavoritosScreen(catalogo: widget.catalogo, onAbrirObra: widget.onAbrirObra),
      ),
    ).then((_) => _carregarProgresso());
  }

  void _abrirTop100(String fonte, String categoria) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvTop100RankingScreen(
          fonte: fonte,
          categoriaInicial: categoria,
          catalogo: widget.catalogo,
          onAbrirObra: widget.onAbrirObra,
        ),
      ),
    );
  }

  void _abrirSubpagina(String titulo, List<ObraAgrupada> itens, List<String> subfiltros, [String? inicial]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvSubcategoriaScreen(
          titulo: titulo,
          itens: itens,
          subfiltros: subfiltros,
          filtroInicial: inicial,
          onAbrirObra: widget.onAbrirObra,
          onAbrirBusca: _abrirBusca,
          onAbrirFiltro: () => _abrirFiltro(titulo),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: IndexedStack(
              index: _abaIndex,
              children: [
                _buildAbaInicio(),
                _buildAbaCategoria('Filmes', _filmes),
                _buildAbaCategoria('Séries', _series),
                _buildAbaCategoria('Kids', _kids),
                _buildAbaCategoria('Anime', _animes),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF10131B), Color(0x000A0C10)],
        ),
      ),
      child: Row(
        children: [
          const CinemaLogoWidget(height: 36, width: 124),
          const SizedBox(width: 10),
          CinemaFocusBox(
            onTap: widget.onAlternarModoMobile,
            borderRadius: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A202C),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF5B82E).withOpacity(0.6)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_android, size: 15, color: Color(0xFFF5B82E)),
                  SizedBox(width: 4),
                  Text('Celular', style: TextStyle(color: Color(0xFFF5B82E), fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          ...List.generate(_abas.length, (i) {
            final ativo = _abaIndex == i;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: CinemaFocusBox(
                onTap: () => setState(() => _abaIndex = i),
                borderRadius: 20,
                scaleOnFocus: 1.06,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: ativo ? const Color(0xFFF5B82E).withOpacity(0.18) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: ativo ? const Color(0xFFF5B82E) : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    _abas[i],
                    style: TextStyle(
                      color: ativo ? const Color(0xFFF5B82E) : Colors.white70,
                      fontSize: 15,
                      fontWeight: ativo ? FontWeight.w900 : FontWeight.w600,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          TopIconeComTooltip(icon: Icons.search, label: 'Buscar', onPressed: _abrirBusca),
          const SizedBox(width: 12),
          TopIconeComTooltip(
            icon: Icons.filter_alt_outlined,
            label: 'Filtro',
            onPressed: () => _abrirFiltro(_abaIndex == 2 ? 'Séries' : _abaIndex == 3 ? 'Kids' : _abaIndex == 4 ? 'Anime' : 'Filmes'),
          ),
          const SizedBox(width: 12),
          TopIconeComTooltip(
            icon: Icons.history,
            label: 'Meus Favoritos e Histórico',
            onPressed: _abrirHistoricoFavoritos,
          ),
          const SizedBox(width: 12),
          TopIconeComTooltip(
            icon: Icons.phone_android,
            label: 'Modo Celular',
            onPressed: widget.onAlternarModoMobile,
          ),
        ],
      ),
    );
  }

  Widget _buildAbaInicio() {
    final filmesDestaque = (_filmes.where((o) => o.emDestaque || o.tags.any((t) => t.toLowerCase().contains('banner'))).toList()
          ..sort((a, b) => a.ordemDestaque.compareTo(b.ordemDestaque)))
        .take(4)
        .toList();
    if (filmesDestaque.length < 4) {
      for (final f in _filmes) {
        if (!filmesDestaque.contains(f)) filmesDestaque.add(f);
        if (filmesDestaque.length == 4) break;
      }
    }

    final seriesDestaque = (_series.where((o) => o.emDestaque || o.tags.any((t) => t.toLowerCase().contains('banner'))).toList()
          ..sort((a, b) => a.ordemDestaque.compareTo(b.ordemDestaque)))
        .take(4)
        .toList();
    if (seriesDestaque.length < 4) {
      for (final s in _series) {
        if (!seriesDestaque.contains(s)) seriesDestaque.add(s);
        if (seriesDestaque.length == 4) break;
      }
    }

    final continuar = widget.catalogo.where((o) => _progressoMap.containsKey(o.chaveGrupo)).toList();
    final top10 = List<ObraAgrupada>.from(widget.catalogo)
      ..sort((a, b) => b.scorePopularidade.compareTo(a.scorePopularidade));

    return ListView(
      cacheExtent: 320,
      padding: const EdgeInsets.fromLTRB(26, 8, 26, 36),
      children: [
        // Dois Banners Rotativos Lado a Lado (4 Filmes + 4 Séries)
        SizedBox(
          height: 255,
          child: Row(
            children: [
              Expanded(
                child: _buildCarrosselHero(
                  tituloSecao: 'Filmes em Destaque',
                  itens: filmesDestaque,
                  controller: _bannerFilmesCtrl,
                  paginaAtual: _idxBannerFilme,
                  onPageChanged: (i) => setState(() => _idxBannerFilme = i),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _buildCarrosselHero(
                  tituloSecao: 'Séries em Destaque',
                  itens: seriesDestaque,
                  controller: _bannerSeriesCtrl,
                  paginaAtual: _idxBannerSerie,
                  onPageChanged: (i) => setState(() => _idxBannerSerie = i),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (continuar.isNotEmpty)
          _buildPrateleira(
            titulo: 'Continuar Assistindo',
            itens: continuar,
            mostrarProgresso: true,
          ),
        _buildPrateleira(
          titulo: 'Top 10 em Alta',
          itens: top10.take(10).toList(),
          numerado: true,
        ),
        _buildPrateleira(
          titulo: 'Sports',
          itens: _filtrarTagOuGenero(widget.catalogo, 'Sport'),
        ),
        _buildPrateleira(
          titulo: 'Livestream',
          itens: _filtrarTagOuGenero(widget.catalogo, 'TV'),
        ),
        _buildPrateleira(
          titulo: 'No Cinema',
          itens: _filtrarTagOuGenero(widget.catalogo, 'Cinema'),
        ),
        _buildPrateleira(
          titulo: 'Coleções',
          itens: _filtrarTagOuGenero(widget.catalogo, 'Cole'),
        ),
        _buildPrateleira(
          titulo: 'Ação',
          itens: _filtrarTagOuGenero(widget.catalogo, 'Ação'),
        ),
        _buildPrateleira(
          titulo: 'Mistério',
          itens: _filtrarTagOuGenero(widget.catalogo, 'Mistério'),
        ),
        _buildPrateleira(
          titulo: 'Suspense',
          itens: _filtrarTagOuGenero(widget.catalogo, 'Suspense'),
        ),
        _buildPrateleira(
          titulo: 'Netflix',
          itens: _filtrarTagOuGenero(widget.catalogo, 'Netflix'),
        ),
        _buildPrateleira(
          titulo: 'Disney+',
          itens: _filtrarTagOuGenero(widget.catalogo, 'Disney'),
        ),
        _buildPrateleira(
          titulo: 'Globoplay',
          itens: _filtrarTagOuGenero(widget.catalogo, 'Globoplay'),
        ),
      ],
    );
  }

  Widget _buildCarrosselHero({
    required String tituloSecao,
    required List<ObraAgrupada> itens,
    required PageController controller,
    required int paginaAtual,
    required void Function(int) onPageChanged,
  }) {
    if (itens.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: const Color(0xFF141821), borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: Text(tituloSecao, style: const TextStyle(color: Colors.white54)),
      );
    }
    final idxSeguro = paginaAtual.clamp(0, itens.length - 1);
    final obra = itens[idxSeguro];
    final img = obra.bannerUrl.isNotEmpty ? obra.bannerUrl : obra.capaUrl;

    return CinemaFocusBox(
      onTap: () => widget.onAbrirObra(obra),
      borderRadius: 14,
      scaleOnFocus: 1.025,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (img.isNotEmpty)
              CachedNetworkImage(
                key: ValueKey('${obra.chaveGrupo}_$idxSeguro'),
                imageUrl: img,
                fit: BoxFit.cover,
                memCacheWidth: 720,
                fadeInDuration: Duration.zero,
              )
            else
              Container(color: const Color(0xFF181D27)),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black12, Colors.black87],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 84,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5B82E),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tituloSecao,
                      style: const TextStyle(color: Colors.black, fontSize: 10.5, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    obra.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${obra.ano} • ${obra.genero}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 14,
              bottom: 16,
              child: Row(
                children: List.generate(
                  itens.length,
                  (i) => GestureDetector(
                    onTap: () => onPageChanged(i),
                    child: Container(
                      width: i == idxSeguro ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: i == idxSeguro ? const Color(0xFFF5B82E) : Colors.white38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAbaCategoria(String nomeAba, List<ObraAgrupada> base) {
    final destaques = base.where((o) => o.emDestaque).toList()
      ..sort((a, b) => a.ordemDestaque.compareTo(b.ordemDestaque));
    final trio = <ObraAgrupada>[
      ...destaques.take(3),
      ...base.where((o) => !destaques.contains(o)).take(3),
    ];

    final subfiltros = nomeAba == 'Filmes'
        ? ['Todos', 'Ação', 'Suspense', 'Mistério', 'Drama', 'Comédia', 'Crime', 'Ficção científica', 'Terror']
        : nomeAba == 'Séries'
            ? ['Todos', 'Ação', 'Drama', 'Crime', 'Suspense', 'Mistério', 'Ficção científica', 'Netflix', 'Disney', 'Globoplay']
            : nomeAba == 'Kids'
                ? ['Todos', 'Animação', 'Aventura', 'Comédia', 'Disney']
                : ['Todos', 'Ação', 'Aventura', 'Fantasia', 'Shonen'];

    return ListView(
      cacheExtent: 320,
      padding: const EdgeInsets.fromLTRB(26, 8, 26, 36),
      children: [
        // Mosaico Fixo com Banner Principal + 2 Pôsteres Laterais
        if (trio.isNotEmpty)
          SizedBox(
            height: 250,
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: _cardMosaico(trio[0], grande: true),
                ),
                if (trio.length > 1) ...[
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: _cardMosaico(trio[1])),
                ],
                if (trio.length > 2) ...[
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: _cardMosaico(trio[2])),
                ],
              ],
            ),
          ),
        const SizedBox(height: 18),
        // Barra de Subpáginas + Top 100 IMDb & Top 100 TMDB
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _botaoAcaoCategoria(
                icon: Icons.emoji_events,
                label: 'Top 100 IMDb',
                destaque: true,
                onTap: () => _abrirTop100('imdb', nomeAba),
              ),
              const SizedBox(width: 10),
              _botaoAcaoCategoria(
                icon: Icons.star_rate_rounded,
                label: 'Top 100 TMDB',
                destaque: true,
                onTap: () => _abrirTop100('tmdb', nomeAba),
              ),
              const SizedBox(width: 10),
              _botaoAcaoCategoria(
                icon: Icons.grid_view_rounded,
                label: 'Explorar Subpáginas',
                onTap: () => _abrirSubpagina(nomeAba, base, subfiltros),
              ),
              const SizedBox(width: 10),
              ...subfiltros.skip(1).take(6).map(
                    (g) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _botaoAcaoCategoria(
                        label: g,
                        onTap: () => _abrirSubpagina(nomeAba, base, subfiltros, g),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildPrateleira(titulo: 'Adicionados Recentemente em $nomeAba', itens: base.take(20).toList()),
        _buildPrateleira(titulo: 'Ação e Aventura', itens: _filtrarTagOuGenero(base, 'Ação')),
        _buildPrateleira(titulo: 'Suspense e Mistério', itens: _filtrarTagOuGenero(base, 'Suspense')),
        _buildPrateleira(titulo: 'Drama e Crime', itens: _filtrarTagOuGenero(base, 'Drama')),
      ],
    );
  }

  Widget _cardMosaico(ObraAgrupada obra, {bool grande = false}) {
    final img = grande
        ? (obra.bannerUrl.isNotEmpty ? obra.bannerUrl : obra.capaUrl)
        : (obra.capaUrl.isNotEmpty ? obra.capaUrl : obra.bannerUrl);
    return CinemaFocusBox(
      onTap: () => widget.onAbrirObra(obra),
      borderRadius: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (img.isNotEmpty)
              CachedNetworkImage(imageUrl: img, fit: BoxFit.cover)
            else
              Container(color: const Color(0xFF161A23)),
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
                  Text(
                    obra.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: grande ? 20 : 14.5, fontWeight: FontWeight.w900),
                  ),
                  if (grande)
                    Text(
                      '${obra.ano} • ${obra.genero}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botaoAcaoCategoria({IconData? icon, required String label, bool destaque = false, required VoidCallback onTap}) {
    return CinemaFocusBox(
      onTap: onTap,
      borderRadius: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: destaque ? const Color(0xFFF5B82E) : const Color(0xFF161B26),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: destaque ? const Color(0xFFF5B82E) : Colors.white12),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: destaque ? Colors.black : const Color(0xFFF5B82E)),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                color: destaque ? Colors.black : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrateleira({
    required String titulo,
    required List<ObraAgrupada> itens,
    bool numerado = false,
    bool mostrarProgresso = false,
  }) {
    if (itens.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 248,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: itens.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, idx) {
                final obra = itens[idx];
                final prog = mostrarProgresso
                    ? (_progressoMap[obra.chaveGrupo]?['progresso'] as double?)
                    : null;
                return TvPosterCard(
                  obra: obra,
                  rankNumero: numerado ? idx + 1 : null,
                  progresso: prog,
                  onTap: () => widget.onAbrirObra(obra),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
