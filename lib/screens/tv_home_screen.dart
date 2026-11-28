import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/midia_model.dart';
import '../services/live_sports_service.dart';
import '../services/supabase_service.dart';
import 'player_screen.dart';
import 'tv_aux_screens.dart';

class TvHomeScreen extends StatefulWidget {
  final List<ObraAgrupada> catalogo;
  final Future<void> Function() onRefresh;
  final Function(ObraAgrupada) onAbrirObra;
  final VoidCallback onAlternarModoMobile;
  final ValueNotifier<String?>? abaExternaNotifier;

  const TvHomeScreen({
    super.key,
    required this.catalogo,
    required this.onRefresh,
    required this.onAbrirObra,
    required this.onAlternarModoMobile,
    this.abaExternaNotifier,
  });

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  static const List<String> _abasSuperiores = [
    'Início', 'Filmes', 'Séries', 'Sports', 'TV', 'Kids', 'Animes', 'Max', 'Procurar', 'Favoritos',
  ];

  final PageController _bannerPageController = PageController();
  Timer? _autoSlideTimer;
  int _bannerAtual = 0;
  String _abaSelecionada = 'Início';
  List<JogoAoVivo> _jogosAoVivo = [];
  bool _carregandoJogos = true;

  @override
  void initState() {
    super.initState();
    _carregarJogosEsporte();
    _iniciarCarrosselAutomatico();
    widget.abaExternaNotifier?.addListener(_onAbaExterna);
  }

  void _onAbaExterna() {
    final destino = widget.abaExternaNotifier?.value;
    if (destino != null && destino.isNotEmpty) _navegarParaAba(destino);
  }

  void _iniciarCarrosselAutomatico() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      final filmes = _obter6FilmesDestaque();
      if (!mounted || filmes.isEmpty || !_bannerPageController.hasClients) return;
      final proximo = (_bannerAtual + 1) % filmes.length;
      _bannerPageController.animateToPage(proximo, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  Future<void> _carregarJogosEsporte() async {
    try {
      final jogos = await LiveSportsService.instance.buscarJogosPrincipais();
      if (mounted) setState(() { _jogosAoVivo = jogos; _carregandoJogos = false; });
    } catch (_) {
      if (mounted) setState(() => _carregandoJogos = false);
    }
  }

  @override
  void dispose() {
    widget.abaExternaNotifier?.removeListener(_onAbaExterna);
    _autoSlideTimer?.cancel();
    _bannerPageController.dispose();
    super.dispose();
  }

  List<ObraAgrupada> _obter6FilmesDestaque() {
    final filmes = widget.catalogo.where((o) {
      final t = o.tipo.toLowerCase();
      return t.contains('filme') && !t.contains('tv');
    }).toList();

    filmes.sort((a, b) {
      final aAlta = SupabaseService.estaEmAltaTmdbImdb(a) ? 1 : 0;
      final bAlta = SupabaseService.estaEmAltaTmdbImdb(b) ? 1 : 0;
      final aTemBanner = (a.bannerUrl != null && a.bannerUrl!.isNotEmpty) ? 1 : 0;
      final bTemBanner = (b.bannerUrl != null && b.bannerUrl!.isNotEmpty) ? 1 : 0;
      if (aAlta != bAlta) return bAlta.compareTo(aAlta);
      final cmpAno = b.ano.compareTo(a.ano);
      if (cmpAno != 0) return cmpAno;
      if (aTemBanner != bTemBanner) return bTemBanner.compareTo(aTemBanner);
      return b.notaImdb.compareTo(a.notaImdb);
    });
    return filmes.take(6).toList();
  }

  List<ObraAgrupada> _obter5SeriesDestaque() {
    final series = widget.catalogo.where((o) {
      final t = o.tipo.toLowerCase();
      return (t.contains('série') || t.contains('serie')) && !t.contains('anime');
    }).toList();

    series.sort((a, b) {
      final aAlta = SupabaseService.estaEmAltaTmdbImdb(a) ? 1 : 0;
      final bAlta = SupabaseService.estaEmAltaTmdbImdb(b) ? 1 : 0;
      if (aAlta != bAlta) return bAlta.compareTo(aAlta);
      final cmpAno = b.ano.compareTo(a.ano);
      if (cmpAno != 0) return cmpAno;
      return b.notaImdb.compareTo(a.notaImdb);
    });
    return series.take(5).toList();
  }

  List<ObraAgrupada> _obterCanaisPorTermos(List<String> termos) {
    return widget.catalogo.where((o) {
      final tudo = '${o.titulo} ${o.genero} ${o.tipo}'.toLowerCase();
      return termos.any((t) => tudo.contains(t.toLowerCase()));
    }).toList();
  }

  void _abrirCanalEsportivoParaJogo(JogoAoVivo jogo) {
    final canaisSports = _obterCanaisPorTermos([jogo.canalTransmissao, 'espn', 'premiere', 'sportv', 'caze', 'sports', 'esporte']);
    if (canaisSports.isNotEmpty && canaisSports.first.fontes.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CinemaPlayerScreen(obra: canaisSports.first, fonteInicial: canaisSports.first.fontes.first)));
    } else {
      _navegarParaAba('Sports');
    }
  }

  void _navegarParaAba(String aba) {
    setState(() => _abaSelecionada = aba);
    final lower = aba.toLowerCase();
    if (lower == 'início' || lower == 'inicio') return;

    if (lower == 'favoritos') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvHistoricoFavoritosScreen(catalogoCompleto: widget.catalogo, onAbrirObra: widget.onAbrirObra, onAlternarModoMobile: widget.onAlternarModoMobile)));
      return;
    }

    if (lower == 'sports' || lower == 'tv') {
      final canais = lower == 'sports'
          ? _obterCanaisPorTermos(['sport', 'espn', 'premiere', 'combate', 'dazn', 'caze', 'futebol'])
          : _obterCanaisPorTermos(['tv', 'ao vivo', 'aberta', 'globo', 'sbt', 'record', 'band', 'telecine', 'hbo']);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvFiltroScreen(tituloPagina: aba, catalogoCompleto: canais.isNotEmpty ? canais : widget.catalogo, onAbrirObra: widget.onAbrirObra, onNavegarAba: _navegarParaAba, onAlternarModoMobile: widget.onAlternarModoMobile)));
      return;
    }

    if (lower == 'procurar') {
      _abrirBuscaRapidaTv();
      return;
    }

    String? filtroTipo;
    bool isKids = false;
    if (lower == 'filmes') filtroTipo = 'Filme';
    if (lower == 'séries' || lower == 'series') filtroTipo = 'Série';
    if (lower == 'animes') filtroTipo = 'Anime';
    if (lower == 'kids') isKids = true;

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvFiltroScreen(tituloPagina: aba, catalogoCompleto: widget.catalogo, filtroTipo: filtroTipo, isKids: isKids, onAbrirObra: widget.onAbrirObra, onNavegarAba: _navegarParaAba, onAlternarModoMobile: widget.onAlternarModoMobile)));
  }

  void _abrirPlataforma(String nomePlataforma, {bool isCanalAoVivo = false}) {
    if (isCanalAoVivo) {
      final termos = nomePlataforma.toLowerCase().contains('espn') ? ['espn'] : ['premiere', 'sportv'];
      final canais = _obterCanaisPorTermos(termos);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvFiltroScreen(tituloPagina: nomePlataforma, catalogoCompleto: canais, onAbrirObra: widget.onAbrirObra, onNavegarAba: _navegarParaAba, onAlternarModoMobile: widget.onAlternarModoMobile)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvFiltroScreen(tituloPagina: nomePlataforma, catalogoCompleto: widget.catalogo, filtroPlataforma: nomePlataforma, onAbrirObra: widget.onAbrirObra, onNavegarAba: _navegarParaAba, onAlternarModoMobile: widget.onAlternarModoMobile)));
  }

  void _abrirBuscaRapidaTv() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141923),
        title: const Text('Procurar no CineMAX', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Digite o nome do filme, série, anime ou canal...', hintStyle: TextStyle(color: Colors.white38)),
          onSubmitted: (termo) {
            Navigator.pop(ctx);
            final filtrados = widget.catalogo.where((o) => o.titulo.toLowerCase().contains(termo.trim().toLowerCase())).toList();
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvFiltroScreen(tituloPagina: 'Busca: $termo', catalogoCompleto: filtrados, onAbrirObra: widget.onAbrirObra, onNavegarAba: _navegarParaAba, onAlternarModoMobile: widget.onAlternarModoMobile)));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filmes6 = _obter6FilmesDestaque();
    final series5 = _obter5SeriesDestaque();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: SafeArea(
        child: Column(
          children: [
            _buildBarraSuperior(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 365,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 62,
                            child: Column(
                              children: [
                                Expanded(flex: 66, child: _buildCarrossel6Filmes(filmes6)),
                                const SizedBox(height: 10),
                                Expanded(flex: 34, child: _buildLinha5Series(series5)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(flex: 38, child: _buildColuna3JogosAoVivo()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildBarraPlataformasInferior(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraSuperior() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(color: Color(0xFF0D111A), border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        children: [
          const Text('CineMAX', style: TextStyle(color: Color(0xFFE50914), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
          const SizedBox(width: 16),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _abasSuperiores.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final aba = _abasSuperiores[index];
                final selecionada = aba == _abaSelecionada;
                return TextButton(
                  onPressed: () => _navegarParaAba(aba),
                  style: TextButton.styleFrom(backgroundColor: selecionada ? const Color(0xFFE50914) : Colors.transparent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  child: Text(aba, style: TextStyle(fontSize: 13.5, fontWeight: selecionada ? FontWeight.bold : FontWeight.w500)),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: widget.onAlternarModoMobile,
            icon: const Icon(Icons.smartphone, size: 16, color: Colors.white),
            label: const Text('Modo Celular', style: TextStyle(color: Colors.white, fontSize: 12)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          ),
        ],
      ),
    );
  }

  Widget _buildCarrossel6Filmes(List<ObraAgrupada> filmes) {
    if (filmes.isEmpty) {
      return Container(decoration: BoxDecoration(color: const Color(0xFF141923), borderRadius: BorderRadius.circular(14)), child: const Center(child: Text('Carregando lançamentos em alta...', style: TextStyle(color: Colors.white60))));
    }
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF121722), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PageView.builder(
            controller: _bannerPageController,
            onPageChanged: (i) => setState(() => _bannerAtual = i),
            itemCount: filmes.length,
            itemBuilder: (context, index) {
              final filme = filmes[index];
              final temBannerHorizontal = filme.bannerUrl != null && filme.bannerUrl!.trim().isNotEmpty;
              final imgUrl = temBannerHorizontal ? filme.bannerUrl! : filme.capaUrl;
              return InkWell(
                onTap: () => widget.onAbrirObra(filme),
                child: Row(
                  children: [
                    Expanded(
                      flex: 42,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        color: const Color(0xFF111621),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(6)),
                              child: Text('EM ALTA • ${filme.ano > 0 ? filme.ano : "2026"}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 8),
                            Text(filme.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text('★ ${filme.notaImdb.toStringAsFixed(1)} IMDb  •  ${filme.genero}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(filme.sinopse.isNotEmpty ? filme.sinopse : 'Lançamento disponível no catálogo CineMAX.', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: () => widget.onAbrirObra(filme),
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('Assistir Agora'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 58,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (imgUrl.isNotEmpty)
                            CachedNetworkImage(imageUrl: imgUrl, fit: temBannerHorizontal ? BoxFit.cover : BoxFit.contain, alignment: const Alignment(0.0, -0.2), memCacheWidth: 900, fadeInDuration: Duration.zero),
                          Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF111621), Colors.transparent], stops: [0.0, 0.22]))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            right: 14, bottom: 10,
            child: Row(
              children: List.generate(filmes.length, (i) {
                final ativo = i == _bannerAtual;
                return AnimatedContainer(duration: const Duration(milliseconds: 250), margin: const EdgeInsets.symmetric(horizontal: 3), width: ativo ? 18 : 7, height: 7, decoration: BoxDecoration(color: ativo ? const Color(0xFFE50914) : Colors.white38, borderRadius: BorderRadius.circular(4)));
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinha5Series(List<ObraAgrupada> series) {
    return Row(
      children: List.generate(5, (index) {
        if (index >= series.length) {
          return Expanded(child: Container(margin: EdgeInsets.only(right: index < 4 ? 8 : 0), decoration: BoxDecoration(color: const Color(0xFF141923), borderRadius: BorderRadius.circular(10))));
        }
        final serie = series[index];
        final thumb = (serie.bannerUrl != null && serie.bannerUrl!.isNotEmpty) ? serie.bannerUrl! : serie.capaUrl;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < 4 ? 8 : 0),
            child: InkWell(
              onTap: () => widget.onAbrirObra(serie),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(color: const Color(0xFF141923), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb.isNotEmpty) CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, alignment: const Alignment(0.0, -0.2), memCacheWidth: 360, fadeInDuration: Duration.zero),
                    Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]))),
                    Positioned(
                      left: 6, right: 6, bottom: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(serie.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          Text('Série • ${serie.ano > 0 ? serie.ano : "2026"}', style: const TextStyle(color: Colors.white70, fontSize: 9.5)),
                        ],
                      ),
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
    if (_carregandoJogos) {
      return Container(decoration: BoxDecoration(color: const Color(0xFF141923), borderRadius: BorderRadius.circular(14)), child: const Center(child: CircularProgressIndicator(color: Color(0xFFE50914))));
    }
    final jogo1 = _jogosAoVivo.isNotEmpty ? _jogosAoVivo[0] : null;
    final jogo2 = _jogosAoVivo.length > 1 ? _jogosAoVivo[1] : null;
    final jogo3 = _jogosAoVivo.length > 2 ? _jogosAoVivo[2] : null;

    return Column(
      children: [
        Expanded(flex: 52, child: _buildCardJogoAoVivo(jogo1, grande: true)),
        const SizedBox(height: 10),
        Expanded(
          flex: 48,
          child: Row(
            children: [
              Expanded(child: _buildCardJogoAoVivo(jogo2, grande: false)),
              const SizedBox(width: 10),
              Expanded(child: _buildCardJogoAoVivo(jogo3, grande: false)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardJogoAoVivo(JogoAoVivo? jogo, {required bool grande}) {
    return InkWell(
      onTap: () => jogo != null ? _abrirCanalEsportivoParaJogo(jogo) : _navegarParaAba('Sports'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1B2436), Color(0xFF101520)]), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
        child: jogo == null
            ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.sports_soccer, color: Colors.white54, size: 28), SizedBox(height: 6), Text('Canais Sports Ao Vivo', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold))]))
            : Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: jogo.aoVivo ? const Color(0xFFE50914) : Colors.blueGrey.shade800, borderRadius: BorderRadius.circular(5)),
                        child: Text(jogo.aoVivo ? '● LIVE' : jogo.statusTexto, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      Flexible(child: Text(jogo.liga, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 10))),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildEscudoTime(jogo.timeCasa, jogo.escudoCasa, grande ? 38 : 26),
                      Text(jogo.aoVivo ? '${jogo.placarCasa} x ${jogo.placarFora}' : 'VS', style: TextStyle(color: Colors.white, fontSize: grande ? 20 : 14, fontWeight: FontWeight.w900)),
                      _buildEscudoTime(jogo.timeFora, jogo.escudoFora, grande ? 38 : 26),
                    ],
                  ),
                  Text('Assistir em ${jogo.canalTransmissao}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.amberAccent, fontSize: 10.5, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  Widget _buildEscudoTime(String nome, String logoUrl, double size) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logoUrl.isNotEmpty) CachedNetworkImage(imageUrl: logoUrl, width: size, height: size, fit: BoxFit.contain, errorWidget: (_, __, ___) => Icon(Icons.shield, color: Colors.white54, size: size)) else Icon(Icons.shield, color: Colors.white54, size: size),
          const SizedBox(height: 4),
          Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildBarraPlataformasInferior() {
    final plataformas = [
      {'nome': 'Netflix', 'cor': const Color(0xFFE50914), 'aoVivo': false},
      {'nome': 'Prime Video', 'cor': const Color(0xFF00A8E1), 'aoVivo': false},
      {'nome': 'HBO Max', 'cor': const Color(0xFF7B2CBF), 'aoVivo': false},
      {'nome': 'Disney+', 'cor': const Color(0xFF113CCF), 'aoVivo': false},
      {'nome': 'ESPN', 'cor': const Color(0xFFD00000), 'aoVivo': true},
      {'nome': 'Premiere / SporTV', 'cor': const Color(0xFF1B8A3D), 'aoVivo': true},
      {'nome': 'Telecine', 'cor': const Color(0xFFFF6D00), 'aoVivo': false},
    ];
    return SizedBox(
      height: 58,
      child: Row(
        children: List.generate(plataformas.length, (i) {
          final p = plataformas[i];
          final nome = p['nome'] as String;
          final cor = p['cor'] as Color;
          final aoVivo = p['aoVivo'] as bool;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < plataformas.length - 1 ? 10 : 0),
              child: InkWell(
                onTap: () => _abrirPlataforma(nome, isCanalAoVivo: aoVivo),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFF141923), borderRadius: BorderRadius.circular(12), border: Border.all(color: cor.withOpacity(0.55), width: 1.4)),
                  child: Center(child: Text(nome, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4))),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
