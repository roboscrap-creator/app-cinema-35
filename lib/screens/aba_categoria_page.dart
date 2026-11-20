import 'dart:async';
import 'package:flutter/material.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';

class AbaCategoriaPage extends StatefulWidget {
  final String nomeAba;
  final List<ObraAgrupada> obras;
  final Function(ObraAgrupada) onAbrirObra;
  const AbaCategoriaPage({super.key, required this.nomeAba, required this.obras, required this.onAbrirObra});
  @override
  State<AbaCategoriaPage> createState() => _AbaCategoriaPageState();
}

class _AbaCategoriaPageState extends State<AbaCategoriaPage> {
  final PageController _bannerCtrl = PageController();
  Timer? _timer;
  int _bannerIdx = 0;
  Map<String, Map<String, dynamic>> _progresso = {};

  @override
  void initState() {
    super.initState();
    _carregarProgresso();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_bannerCtrl.hasClients) {
        final next = (_bannerIdx + 1) % 4;
        _bannerCtrl.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      }
    });
  }

  Future<void> _carregarProgresso() async {
    final p = await SupabaseService.carregarProgressoAssistido();
    if (mounted) setState(() => _progresso = p);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerCtrl.dispose();
    super.dispose();
  }

  bool _temTag(ObraAgrupada o, List<String> chaves) {
    final tgs = o.tags.map((e) => e.toLowerCase()).toList();
    return chaves.any((c) => tgs.any((t) => t.contains(c.toLowerCase())));
  }

  bool _temGenero(ObraAgrupada o, String g) {
    return o.genero.toLowerCase().contains(g.toLowerCase()) || _temTag(o, [g]);
  }

  List<ObraAgrupada> _filtrarPorAba() {
    final cat = widget.nomeAba.toLowerCase();
    return widget.obras.where((o) {
      final c = o.categoria.toLowerCase();
      final g = o.genero.toLowerCase();
      if (cat.contains('recomenda')) return true;
      if (cat.contains('filme')) return c.contains('filme') && !c.contains('tv');
      if (cat.contains('série') || cat.contains('serie')) return c.contains('série') || c.contains('serie');
      if (cat.contains('infantil')) return c.contains('infantil') || g.contains('infantil') || g.contains('anima');
      if (cat.contains('anime')) return c.contains('anime') || g.contains('anime');
      return true;
    }).toList();
  }

  void _abrir(ObraAgrupada o) {
    widget.onAbrirObra(o);
  }

  void _verTodos(String titulo, List<ObraAgrupada> lista) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(titulo, style: const TextStyle(color: Colors.white))),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.62, crossAxisSpacing: 10, mainAxisSpacing: 12),
        itemCount: lista.length,
        itemBuilder: (_, i) {
          final o = lista[i];
          return GestureDetector(
            onTap: () { Navigator.pop(context); _abrir(o); },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: o.capaUrl.isNotEmpty ? Image.network(o.capaUrl, fit: BoxFit.cover, width: double.infinity) : Container(color: Colors.grey[900]))),
              const SizedBox(height: 4),
              Text(o.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          );
        },
      ),
    )));
  }

  String _etiquetaSerie(ObraAgrupada o) {
    final c = o.categoria.toLowerCase();
    if (!c.contains('série') && !c.contains('serie') && !c.contains('anime') && o.fontes.length <= 1) return '';
    int maxT = 0, maxE = 0;
    for (final f in o.fontes) {
      final t = f.temporada ?? 0;
      final e = f.episodio ?? 0;
      if (t > maxT) { maxT = t; maxE = e; }
      else if (t == maxT && e > maxE) { maxE = e; }
    }
    if (maxT > 0 && maxE > 0) return 'S$maxT - E$maxE';
    if (maxT > 0) return 'Temp.$maxT';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final lista = widget.obras;
    if (lista.isEmpty) {
      return Center(child: Text('Nenhum item em ${widget.nomeAba}', style: const TextStyle(color: Colors.white54)));
    }
    final cat = widget.nomeAba.toLowerCase();
    final isFilmes = cat.contains('filme');
    final isSeries = cat.contains('série') || cat.contains('serie');
    final isInfantil = cat.contains('infantil');
    final isAnime = cat.contains('anime');
    final isRecomenda = cat.contains('recomenda');

    final banners = lista.where((o) => o.emDestaque || _temTag(o, ['banner', 'destaque'])).toList();
    if (banners.length < 4) {
      for (final o in lista) {
        if (!banners.contains(o) && (o.bannerUrl.isNotEmpty || o.capaUrl.isNotEmpty)) banners.add(o);
        if (banners.length == 4) break;
      }
    }
    final top4 = banners.take(4).toList();

    return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (top4.isNotEmpty) _buildBanner(top4),
          if (isRecomenda) ..._buildSecoesRecomendacoes(lista),
          if (isFilmes) ..._buildSecoesFilmes(lista),
          if (isSeries) ..._buildSecoesSeries(lista),
          if (!isRecomenda && !isFilmes && !isSeries) _buildFileira('Catálogo ${widget.nomeAba}', lista),
        ],
    );
  }

  List<Widget> _buildSecoesRecomendacoes(List<ObraAgrupada> lista) {
    final live = widget.obras.where((o) => o.categoria.toLowerCase().contains('tv') || _temTag(o, ['live', 'tv'])).toList();
    final cont = widget.obras.where((o) => _progresso.containsKey(o.chaveGrupo)).toList();
    final topFilmes = [...lista.where((o) => o.categoria.toLowerCase().contains('filme'))]..sort((a, b) => b.visualizacoes.compareTo(a.visualizacoes));
    final topSeries = [...lista.where((o) => o.categoria.toLowerCase().contains('série') || o.categoria.toLowerCase().contains('serie'))]..sort((a, b) => b.visualizacoes.compareTo(a.visualizacoes));
    return [
      if (live.isNotEmpty) _buildFileira('Livestream', live, horizontal: true, iconeLive: true),
      if (cont.isNotEmpty) _buildFileira('Continuar Assistindo', cont, mostrarProgresso: true),
      if (topFilmes.isNotEmpty) _buildFileira('Top Filmes', topFilmes, ranking: true),
      if (topSeries.isNotEmpty) _buildFileira('Top Séries', topSeries, ranking: true),
      _buildFileira('Adicionados Recentemente', lista),
    ];
  }

  List<Widget> _buildSecoesFilmes(List<ObraAgrupada> filmes) {
    final noCinema = filmes.where((o) => _temTag(o, ['no cinema', 'cinema'])).toList();
    final lancamentos = [...filmes]..sort((a, b) => b.ano.compareTo(a.ano));
    final dublados = filmes.where((o) => o.fontes.any((f) => f.tipoAudio.toLowerCase().contains('dub') || f.tipoAudio.toLowerCase().contains('dual'))).toList();
    final netflix = filmes.where((o) => _temTag(o, ['netflix'])).toList();
    final especiais = filmes.where((o) => _temTag(o, ['especiais', 'especial'])).toList();
    final disney = filmes.where((o) => _temTag(o, ['disney'])).toList();
    final nacional = filmes.where((o) => _temTag(o, ['nacional']) || _temGenero(o, 'nacional')).toList();
    final curta = filmes.where((o) => _temTag(o, ['curta']) || _temGenero(o, 'curta')).toList();
    final emBreve = filmes.where((o) => _temTag(o, ['em breve', 'trailer']) || o.titulo.toLowerCase().contains('(trailer)')).toList();

    final generos = [
      'Ação', 'Aventura', 'Romance', 'Mistério', 'Crime', 'Comédia', 'Drama',
      'Família', 'Fantasia', 'Ficção Científica', 'Terror', 'Suspense', 'Musical',
      'Guerra', 'Faroeste', 'Documentário', 'História'
    ];

    return [
      if (noCinema.isNotEmpty) _buildFileira('No Cinema', noCinema),
      if (lancamentos.isNotEmpty) _buildFileira('Lançamentos', lancamentos),
      if (dublados.isNotEmpty) _buildFileira('Dublado', dublados),
      if (netflix.isNotEmpty) _buildFileira('Netflix Filmes', netflix),
      if (especiais.isNotEmpty) _buildFileira('Especiais', especiais, horizontal: true),
      if (disney.isNotEmpty) _buildFileira('Disney+ Filmes', disney),
      if (nacional.isNotEmpty) _buildFileira('Nacional', nacional),
      for (final g in generos)
        if (filmes.any((o) => _temGenero(o, g)))
          _buildFileira(g, filmes.where((o) => _temGenero(o, g)).toList()),
      if (curta.isNotEmpty) _buildFileira('Curta', curta, horizontal: true),
      if (emBreve.isNotEmpty) _buildFileira('Em breve', emBreve),
      _buildFileira('Todos', filmes),
    ];
  }

  List<Widget> _buildSecoesSeries(List<ObraAgrupada> series) {
    final melhores = [...series]..sort((a, b) => b.notaImdb.compareTo(a.notaImdb));
    final doramas = series.where((o) => _temGenero(o, 'dorama') || _temTag(o, ['dorama', 'corean'])).toList();
    final turcas = series.where((o) => _temTag(o, ['turca', 'novelas turcas'])).toList();
    final novelas = series.where((o) => _temGenero(o, 'novela') || _temTag(o, ['novela'])).toList();
    final plataformas = [
      ['Netflix', 'netflix'],
      ['Disney+', 'disney'],
      ['MAX', 'max'],
      ['Apple TV+', 'apple'],
      ['Paramount +', 'paramount'],
      ['Prime Video', 'prime'],
      ['Globo', 'globo'],
      ['Hulu', 'hulu'],
    ];
    final nacionais = series.where((o) => _temTag(o, ['nacional', 'nacionais'])).toList();
    final renovadas = series.where((o) => _temTag(o, ['renovada'])).toList();
    final biblicas = series.where((o) => _temTag(o, ['bíblica', 'biblica'])).toList();
    final latinas = series.where((o) => _temTag(o, ['latino'])).toList();
    final britanicas = series.where((o) => _temTag(o, ['britânica', 'britanica'])).toList();
    final generos = [
      'Drama Médico', 'Drama', 'Família', 'Fantasia', 'Procedimento Policial',
      'Aventura', 'Comédia', 'Ação', 'Suspense', 'Terror', 'Romance', 'Infantil', 'Esporte'
    ];

    return [
      _buildFileira('Última Temporada e Episódio', series),
      if (melhores.isNotEmpty) _buildFileira('Melhores Séries', melhores),
      if (doramas.isNotEmpty) _buildFileira('Doramas', doramas),
      if (turcas.isNotEmpty) _buildFileira('Novelas Turcas', turcas),
      if (novelas.isNotEmpty) _buildFileira('Novelas', novelas),
      for (final p in plataformas)
        if (series.any((o) => _temTag(o, [p[1]])))
          _buildFileira(p[0], series.where((o) => _temTag(o, [p[1]])).toList()),
      if (nacionais.isNotEmpty) _buildFileira('Séries Nacionais', nacionais),
      if (renovadas.isNotEmpty) _buildFileira('Séries Renovadas', renovadas),
      if (biblicas.isNotEmpty) _buildFileira('Telenovelas Bíblicas', biblicas),
      for (final g in generos)
        if (series.any((o) => _temGenero(o, g)))
          _buildFileira(g, series.where((o) => _temGenero(o, g)).toList()),
      if (latinas.isNotEmpty) _buildFileira('Séries Latino-americanas', latinas),
      if (britanicas.isNotEmpty) _buildFileira('Séries Britânicas', britanicas),
      _buildFileira('Todas', series),
    ];
  }


  bool _combina(ObraAgrupada o, List<String> termos) {
    final tit = o.titulo.toLowerCase();
    return _temTag(o, termos) || termos.any((k) => tit.contains(k.toLowerCase()));
  }

  List<Widget> _buildSecoesInfantil(List<ObraAgrupada> inf) {
    final guiaPais = inf.where((o) => _temGenero(o, 'família') || _temTag(o, ['guia dos pais'])).toList();
    final cantar = inf.where((o) => _temGenero(o, 'musical') || _temTag(o, ['cantar', 'dançar', 'musical'])).toList();
    final seriesDesenho = inf.where((o) => o.categoria.toLowerCase().contains('série') || o.categoria.toLowerCase().contains('serie') || o.fontes.length > 1).toList();
    final liveAction = inf.where((o) => _temTag(o, ['live-action', 'live action', 'remake'])).toList();
    final animal = inf.where((o) => _temTag(o, ['animal', 'animais'])).toList();
    final filmesAnim = inf.where((o) => o.categoria.toLowerCase().contains('filme') && o.fontes.length == 1).toList();

    final franquias = [
      ['Pixar', ['pixar']],
      ['Kung Fu Panda', ['kung fu panda']],
      ['Monstros', ['monstros', 'monsters']],
      ['SpongeBob', ['spongebob', 'bob esponja', 'kamp coral']],
      ['Disney 100', ['disney 100', 'disney']],
      ['Garfield', ['garfield']],
      ['Patrulha Canina', ['patrulha canina', 'paw patrol']],
      ['Minions', ['minions', 'meu malvado favorito']],
      ['Snoopy', ['snoopy', 'peanuts']],
      ['Mickey', ['mickey']],
      ['Madagascar', ['madagascar', 'pinguins']],
      ['DreamWorks', ['dreamworks']],
      ['Elsa', ['frozen', 'elsa']],
      ['Bebê', ['bebê', 'bebe', 'baby']],
      ['Barbie', ['barbie']],
      ['Pony', ['pony', 'my little pony']],
      ['Peppa Pig', ['peppa']],
    ];

    return [
      _buildFileira('Todos', inf),
      if (guiaPais.isNotEmpty) _buildFileira('Com a Família (Guia dos Pais)', guiaPais),
      if (cantar.isNotEmpty) _buildFileira('Vamos Cantar e Dançar \ud83c\udfb6', cantar),
      if (seriesDesenho.isNotEmpty) _buildFileira('Séries de Desenhos', seriesDesenho),
      if (liveAction.isNotEmpty) _buildFileira('Live-action e Remakes', liveAction),
      if (animal.isNotEmpty) _buildFileira('Animal Engraçado', animal),
      if (guiaPais.isNotEmpty) _buildFileira('Diversão em Família', guiaPais),
      if (filmesAnim.isNotEmpty) _buildFileira('Filmes de Animação', filmesAnim),
      for (final f in franquias)
        if (inf.any((o) => _combina(o, f[1] as List<String>)))
          _buildFileira(f[0] as String, inf.where((o) => _combina(o, f[1] as List<String>)).toList()),
    ];
  }

  List<Widget> _buildSecoesAnime(List<ObraAgrupada> animes) {
    final filmesAnime = animes.where((o) => o.categoria.toLowerCase().contains('filme') || (o.fontes.length == 1 && (o.fontes.first.temporada ?? 0) == 0)).toList();

    final franquias = [
      ['One piece', ['one piece']],
      ['Naruto', ['naruto', 'boruto']],
      ['Dragon Ball', ['dragon ball']],
      ['Ataque dos Titãs', ['ataque dos titãs', 'attack on titan']],
      ['My Hero Academia', ['my hero academia', 'boku no hero']],
      ['Pokémon', ['pokémon', 'pokemon', 'digimon']],
      ['JoJo’s Bizarre Adventure', ['jojo']],
      ['Bleach', ['bleach']],
      ['Fairy Tail', ['fairy tail']],
      ['Ghibli', ['ghibli', 'mononoke', 'arrietty', 'kokuriko']],
    ];

    return [
      _buildFileira('Todos', animes),
      if (filmesAnime.isNotEmpty) _buildFileira('Filmes de Anime', filmesAnime),
      for (final f in franquias)
        if (animes.any((o) => _combina(o, f[1] as List<String>)))
          _buildFileira(f[0] as String, animes.where((o) => _combina(o, f[1] as List<String>)).toList()),
    ];
  }

  Widget _buildBanner(List<ObraAgrupada> items) {
    return SizedBox(
      height: 230,
      child: Stack(
        children: [
          PageView.builder(
            controller: _bannerCtrl,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _bannerIdx = i),
            itemBuilder: (_, i) {
              final o = items[i];
              final img = o.bannerUrl.isNotEmpty ? o.bannerUrl : o.capaUrl;
              return GestureDetector(
                onTap: () => _abrir(o),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (img.isNotEmpty) Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey[900])),
                    Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]))),
                    Positioned(
                      left: 16, right: 80, bottom: 18,
                      child: Text(o.titulo.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            right: 16, bottom: 20,
            child: Row(
              children: List.generate(items.length, (i) => Container(
                margin: const EdgeInsets.only(left: 5),
                width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _bannerIdx == i ? Colors.white : Colors.white38),
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileira(String titulo, List<ObraAgrupada> lista, {bool horizontal = false, bool iconeLive = false, bool mostrarProgresso = false, bool ranking = false}) {
    final amostra = lista.take(10).toList();
    final cardW = horizontal ? 165.0 : 112.0;
    final cardH = horizontal ? 96.0 : 162.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 8, 10),
          child: Row(
            children: [
              Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              if (iconeLive) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.equalizer, color: Color(0xFFFFB800), size: 18)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white70),
                onPressed: () => _verTodos(titulo, lista),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        SizedBox(
          height: cardH + 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: amostra.length,
            itemBuilder: (_, i) {
              final o = amostra[i];
              final prog = _progresso[o.chaveGrupo];
              final badgeEp = _etiquetaSerie(o);
              return GestureDetector(
                onTap: () => _abrir(o),
                child: Container(
                  width: cardW,
                  margin: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            Container(
                              width: cardW, height: cardH, color: const Color(0xFF1A1A1A),
                              child: o.capaUrl.isNotEmpty
                                  ? Image.network(o.capaUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie, color: Colors.white24))
                                  : const Icon(Icons.movie, color: Colors.white24),
                            ),
                            if (ranking)
                              Positioned(top: 4, left: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFFFB800), borderRadius: BorderRadius.circular(4)), child: Text('#${i + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)))),
                            if (!mostrarProgresso && !horizontal && badgeEp.isNotEmpty)
                              Positioned(
                                left: 0, right: 0, bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])),
                                  child: Text(badgeEp, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            if (mostrarProgresso && prog != null)
                              Positioned(
                                left: 0, right: 0, bottom: 0,
                                child: Column(
                                  children: [
                                    if ((prog['etiqueta'] ?? '').toString().isNotEmpty)
                                      Container(color: Colors.black54, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), child: Text(prog['etiqueta'], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                                    LinearProgressIndicator(value: (prog['progresso'] as num?)?.toDouble() ?? 0.2, minHeight: 3, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB800))),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(o.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.2)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
