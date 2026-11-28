import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../services/live_sports_service.dart';
import 'detalhe_obra_screen.dart';
import 'cinema_player_screen.dart';
import 'home_screen.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  final List<String> _abas = const [
    'Início', 'Filmes', 'Séries', 'Sports', 'Tv',
    'Kids', 'Animes', 'Max', 'Procurar', 'Favoritos', 'Histórico',
  ];

  final List> _plataformas = const [
    {'nome': 'Netflix', 'cor': Color(0xFFE50914), 'query': 'Netflix'},
    {'nome': 'Prime Video', 'cor': Color(0xFF00A8E1), 'query': 'Prime'},
    {'nome': 'ESPN', 'cor': Color(0xFFD00000), 'query': 'ESPN'},
    {'nome': 'HBO Max', 'cor': Color(0xFF5A2E98), 'query': 'HBO'},
    {'nome': 'Disney+', 'cor': Color(0xFF113CCF), 'query': 'Disney'},
    {'nome': 'Paramount+', 'cor': Color(0xFF0064FF), 'query': 'Paramount'},
  ];

  int _abaIndex = 0;
  int _bannerIndex = 0;
  bool _bannerFocado = false;
  bool _carregando = true;
  String _plataformaSelecionada = '';
  String _termoBusca = '';
  final TextEditingController _buscaController = TextEditingController();

  List<ObraAgrupada> _catalogoCompleto = [];
  List<ObraAgrupada> _favoritos = [];
  List<ObraAgrupada> _historico = [];
  List> _jogosAoVivo = [];
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
    _iniciarTimerBanner();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _buscaController.dispose();
    super.dispose();
  }

  void _iniciarTimerBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _bannerFocado) return;
      final banners = _obterBannersAtuais();
      if (banners.length > 1) {
        setState(() => _bannerIndex = (_bannerIndex + 1) % banners.length);
      }
    });
  }

  Future<void> _carregarTudo() async {
    setState(() => _carregando = true);
    try {
      final catalogo = await SupabaseService.carregarCatalogoAgrupado();
      catalogo.sort((a, b) {
        final anoA = int.tryParse(a.ano ?? '0') ?? 0;
        final anoB = int.tryParse(b.ano ?? '0') ?? 0;
        if (anoB != anoA) return anoB.compareTo(anoA);
        return (b.nota ?? 0).compareTo(a.nota ?? 0);
      });

      List<ObraAgrupada> favs = [];
      List<ObraAgrupada> hist = [];
      List> jogos = [];

      try { favs = await SupabaseService.carregarFavoritos(); } catch (_) {}
      try {
        final progresso = await SupabaseService.carregarProgressoAssistido();
        final chavesHist = progresso.map((e) => e['chave_grupo']?.toString()).toSet();
        hist = catalogo.where((o) => chavesHist.contains(o.chaveGrupo)).toList();
      } catch (_) {}
      try { jogos = await LiveSportsService.buscarJogosAoVivo(); } catch (_) {}

      if (mounted) {
        setState(() {
          _catalogoCompleto = catalogo;
          _favoritos = favs;
          _historico = hist;
          _jogosAoVivo = jogos;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<ObraAgrupada> _filtrarPorCategoria(String cat) {
    final c = cat.toLowerCase();
    return _catalogoCompleto.where((o) {
      final oCat = o.categoria.toLowerCase();
      final gens = o.generos.join(' ').toLowerCase();
      if (c == 'filmes') return oCat.contains('filme') && !gens.contains('animação') && !gens.contains('anime');
      if (c == 'séries') return (oCat.contains('serie') || o.isSerie) && !gens.contains('anime');
      if (c == 'sports') return oCat.contains('sport') || oCat.contains('esporte') || o.titulo.toLowerCase().contains('espn') || o.titulo.toLowerCase().contains('premiere') || o.titulo.toLowerCase().contains('sportv');
      if (c == 'tv') return oCat.contains('tv') || oCat.contains('canal') || oCat.contains('ao vivo');
      if (c == 'kids') return gens.contains('família') || gens.contains('infantil') || gens.contains('kids') || oCat.contains('kids');
      if (c == 'animes') return gens.contains('anime') || oCat.contains('anime');
      return true;
    }).toList();
  }

  List> _obterBannersAtuais() {
    final aba = _abas[_abaIndex];
    final List> lista = [];

    if (aba == 'Início' || aba == 'Filmes') {
      for (final f in _filtrarPorCategoria('Filmes').where((o) => (o.backdropUrl ?? o.posterUrl ?? '').isNotEmpty).take(6)) {
        lista.add({
          'tipo': 'obra',
          'badge': 'FILME EM DESTAQUE • ${f.ano ?? "2026"}',
          'titulo': f.titulo,
          'subtitulo': f.sinopse ?? '',
          'imagem': f.backdropUrl ?? f.posterUrl ?? '',
          'obra': f,
        });
      }
    }
    if (aba == 'Início' || aba == 'Séries') {
      for (final s in _filtrarPorCategoria('Séries').where((o) => (o.backdropUrl ?? o.posterUrl ?? '').isNotEmpty).take(5)) {
        lista.add({
          'tipo': 'obra',
          'badge': 'SÉRIE EM ALTA • ${s.ano ?? "2026"}',
          'titulo': s.titulo,
          'subtitulo': s.sinopse ?? '',
          'imagem': s.backdropUrl ?? s.posterUrl ?? '',
          'obra': s,
        });
      }
    }
    if (aba == 'Início' || aba == 'Sports') {
      for (final j in _jogosAoVivo.take(3)) {
        lista.add({
          'tipo': 'sport',
          'badge': 'AO VIVO • ${j['liga'] ?? 'ESPORTES'}',
          'titulo': '${j['time_casa'] ?? 'Time A'} vs ${j['time_fora'] ?? 'Time B'}',
          'subtitulo': '${j['placar'] ?? 'AO VIVO'} • ${j['canal'] ?? 'Transmissão Direta'}',
          'escudoCasa': j['escudo_casa'] ?? '',
          'escudoFora': j['escudo_fora'] ?? '',
          'imagem': j['banner'] ?? '',
        });
      }
    }
    return lista;
  }

  Future<void> _abrirOuReproduzir(ObraAgrupada obra, {bool direto = false}) async {
    List<FonteMidia> fontes = obra.fontes;
    if (fontes.isEmpty) {
      try { fontes = await SupabaseService.carregarFontesDaObra(obra); } catch (_) {}
    }
    if (!mounted) return;

    final isCanal = obra.categoria.toLowerCase().contains('tv') ||
        obra.categoria.toLowerCase().contains('sport') ||
        obra.categoria.toLowerCase().contains('canal');

    if ((direto || isCanal) && fontes.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CinemaPlayerScreen(
            titulo: obra.titulo,
            url: fontes.first.url,
            obra: obra,
            fontes: fontes,
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetalheObraScreen(obra: obra)),
    ).then((_) => _carregarTudo());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _carregando
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
                  : _buildConteudoAba(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF101018),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          const Text('CineMAX', style: TextStyle(color: Color(0xFFE50914), fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(width: 20),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _abas.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final sel = _abaIndex == idx;
                return Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() {
                      _abaIndex = idx;
                      _bannerIndex = 0;
                      _plataformaSelecionada = '';
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFFE50914) : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _abas[idx],
                        style: TextStyle(color: sel ? Colors.white : Colors.white70, fontWeight: sel ? FontWeight.bold : FontWeight.w500, fontSize: 14),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen())),
            icon: const Icon(Icons.smartphone, size: 16, color: Colors.white),
            label: const Text('Modo Celular', style: TextStyle(color: Colors.white, fontSize: 12)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
          ),
        ],
      ),
    );
  }

  Widget _buildConteudoAba() {
    final aba = _abas[_abaIndex];
    if (aba == 'Procurar') return _buildAbaBusca();
    if (aba == 'Favoritos') return _buildGradeObras('Meus Favoritos', _favoritos);
    if (aba == 'Histórico') return _buildGradeObras('Continuar Assistindo', _historico);
    if (aba == 'Max') {
      final maxObras = _catalogoCompleto.where((o) => o.generos.join(' ').toLowerCase().contains('hbo') || o.titulo.toLowerCase().contains('max')).toList();
      return _buildGradeObras('Catálogo Max / HBO', maxObras.isEmpty ? _catalogoCompleto.take(40).toList() : maxObras);
    }
    if (aba != 'Início') return _buildGradeObras(aba, _filtrarPorCategoria(aba));

    final banners = _obterBannersAtuais();
    final filtradosPlat = _plataformaSelecionada.isEmpty
        ? <ObraAgrupada>[]
        : _catalogoCompleto.where((o) => o.generos.join(' ').toLowerCase().contains(_plataformaSelecionada.toLowerCase()) || o.titulo.toLowerCase().contains(_plataformaSelecionada.toLowerCase())).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (banners.isNotEmpty) _buildBannerRotativo(banners),
        _buildBarraPlataformas(),
        if (_plataformaSelecionada.isNotEmpty) _buildCarrosselHorizontal('Destaques $_plataformaSelecionada', filtradosPlat),
        if (_historico.isNotEmpty) _buildCarrosselHorizontal('Continuar Assistindo', _historico),
        _buildCarrosselHorizontal('Filmes Lançamentos (2026)', _filtrarPorCategoria('Filmes').take(25).toList()),
        _buildCarrosselHorizontal('Séries em Alta', _filtrarPorCategoria('Séries').take(25).toList()),
        _buildCarrosselHorizontal('Esportes ao Vivo', _filtrarPorCategoria('Sports').take(20).toList(), direto: true),
        _buildCarrosselHorizontal('Canais de TV ao Vivo', _filtrarPorCategoria('Tv').take(25).toList(), direto: true),
        _buildCarrosselHorizontal('Animes', _filtrarPorCategoria('Animes').take(20).toList()),
        _buildCarrosselHorizontal('Kids & Família', _filtrarPorCategoria('Kids').take(20).toList()),
      ],
    );
  }

  Widget _buildBannerRotativo(List> banners) {
    final idx = _bannerIndex % banners.length;
    final item = banners[idx];

    return Focus(
      onFocusChange: (f) => setState(() => _bannerFocado = f),
      child: GestureDetector(
        onTap: () {
          if (item['tipo'] == 'obra' && item['obra'] is ObraAgrupada) {
            _abrirOuReproduzir(item['obra'] as ObraAgrupada, direto: true);
          }
        },
        child: Container(
          height: 300,
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _bannerFocado ? const Color(0xFFE50914) : Colors.white12, width: _bannerFocado ? 3 : 1),
            color: const Color(0xFF161622),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if ((item['imagem'] ?? '').toString().isNotEmpty)
                CachedNetworkImage(
                  imageUrl: item['imagem'].toString(),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  fadeInDuration: Duration.zero,
                  errorWidget: (_, __, ___) => Container(color: const Color(0xFF181826)),
                ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xF00A0A0F), Color(0x990A0A0F), Colors.transparent],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(6)),
                      child: Text(item['badge'].toString(), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),
                    if (item['tipo'] == 'sport')
                      Row(
                        children: [
                          if ((item['escudoCasa'] ?? '').toString().isNotEmpty)
                            Image.network(item['escudoCasa'], width: 36, height: 36, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white)),
                          const SizedBox(width: 10),
                          Text(item['titulo'].toString(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          if ((item['escudoFora'] ?? '').toString().isNotEmpty)
                            Image.network(item['escudoFora'], width: 36, height: 36, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.white)),
                        ],
                      )
                    else
                      Text(item['titulo'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 540,
                      child: Text(item['subtitulo'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            if (item['tipo'] == 'obra' && item['obra'] is ObraAgrupada) {
                              _abrirOuReproduzir(item['obra'] as ObraAgrupada, direto: true);
                            }
                          },
                          icon: const Icon(Icons.play_arrow, color: Colors.black),
                          label: const Text('Assistir Agora', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                        ),
                        const Spacer(),
                        Row(
                          children: List.generate(banners.length, (i) => Container(
                            width: i == idx ? 20 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(color: i == idx ? const Color(0xFFE50914) : Colors.white38, borderRadius: BorderRadius.circular(4)),
                          )),
                        ),
                      ],
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

  Widget _buildBarraPlataformas() {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: _plataformas.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final p = _plataformas[index];
          final ativo = _plataformaSelecionada == p['query'];
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _plataformaSelecionada = ativo ? '' : p['query'].toString()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: ativo ? (p['cor'] as Color) : const Color(0xFF181824),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ativo ? Colors.white : Colors.white12),
              ),
              child: Center(child: Text(p['nome'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCarrosselHorizontal(String titulo, List<ObraAgrupada> itens, {bool direto = false}) {
    if (itens.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
          child: Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            scrollDirection: Axis.horizontal,
            cacheExtent: 320,
            itemCount: itens.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, idx) => _buildCardObra(itens[idx], direto: direto),
          ),
        ),
      ],
    );
  }

  Widget _buildGradeObras(String titulo, List<ObraAgrupada> itens) {
    if (itens.isEmpty) {
      return Center(child: Text('Nenhum item encontrado em $titulo.', style: const TextStyle(color: Colors.white54, fontSize: 16)));
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$titulo (${itens.length})', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              cacheExtent: 320,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 0.66,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: itens.length,
              itemBuilder: (context, idx) => _buildCardObra(itens[idx]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardObra(ObraAgrupada obra, {bool direto = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _abrirOuReproduzir(obra, direto: direto),
      child: SizedBox(
        width: 138,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  color: const Color(0xFF1A1A26),
                  width: double.infinity,
                  child: (obra.posterUrl ?? '').isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: obra.posterUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 360,
                          fadeInDuration: Duration.zero,
                          errorWidget: (_, __, ___) => const Icon(Icons.movie, color: Colors.white24, size: 40),
                        )
                      : const Icon(Icons.movie, color: Colors.white24, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(obra.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            if (obra.ano != null) Text(obra.ano!, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildAbaBusca() {
    final resultados = _termoBusca.trim().isEmpty
        ? _catalogoCompleto.take(30).toList()
        : _catalogoCompleto.where((o) => o.titulo.toLowerCase().contains(_termoBusca.trim().toLowerCase())).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            controller: _buscaController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Digite o nome do filme, série, anime ou canal...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF181824),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: (val) => setState(() => _termoBusca = val),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildGradeObras('Resultados', resultados)),
        ],
      ),
    );
  }
}
