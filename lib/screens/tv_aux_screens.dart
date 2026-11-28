import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../services/live_sports_service.dart';
import '../widgets/cinema_widgets.dart';

class TvVitrineCategoriaScreen extends StatefulWidget {
  final String titulo;
  final String tipoBanco;
  final List<ObraAgrupada> obras;
  final ValueChanged<ObraAgrupada> onAbrirObra;

  const TvVitrineCategoriaScreen({
    super.key,
    required this.titulo,
    required this.tipoBanco,
    required this.obras,
    required this.onAbrirObra,
  });

  @override
  State<TvVitrineCategoriaScreen> createState() => _TvVitrineCategoriaScreenState();
}

class _TvVitrineCategoriaScreenState extends State<TvVitrineCategoriaScreen> {
  String _categoriaSelecionada = 'Todos';

  List<MapEntry<String, int>> get _categoriasDinamicas =>
      SupabaseService.instance.extrairCategoriasDinamicas(widget.obras);

  List<ObraAgrupada> _filtrarPorCategoria(String cat) {
    if (cat == 'Todos') return widget.obras;
    final low = cat.toLowerCase();
    return widget.obras.where((o) => '${o.categoria},${o.genero},${o.tags}'.toLowerCase().contains(low)).toList();
  }

  void _abrirExploradorCompleto(String? categoria) {
    final iniciais = (categoria == null || categoria == 'Todos') ? widget.obras : _filtrarPorCategoria(categoria);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TvExploradorCompletoScreen(
          tituloPagina: categoria == null || categoria == 'Todos'
              ? '${widget.titulo} • Catálogo Completo'
              : '${widget.titulo} • $categoria',
          tipoBanco: widget.tipoBanco,
          generoFiltro: (categoria == null || categoria == 'Todos') ? null : categoria,
          obrasIniciais: iniciais,
          onAbrirObra: widget.onAbrirObra,
        ),
      ),
    );
  }

  void _abrirPainelTodasCategorias(List<MapEntry<String, int>> cats) {
    final sortedAz = List<MapEntry<String, int>>.from(cats)..sort((a, b) => a.key.compareTo(b.key));
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF121622),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFF5B82E), width: 1.4),
        ),
        child: Container(
          width: 720,
          height: 480,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Todas as Categorias de ${widget.titulo} (${sortedAz.length})',
                      style: const TextStyle(color: Color(0xFFF5B82E), fontSize: 18, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  CinemaFocusBox(
                    borderRadius: 16,
                    onTap: () => Navigator.pop(ctx),
                    child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.close_rounded, color: Colors.white70)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 3.6,
                  ),
                  itemCount: sortedAz.length,
                  itemBuilder: (_, i) {
                    final item = sortedAz[i];
                    return CinemaFocusBox(
                      borderRadius: 10,
                      onTap: () {
                        Navigator.pop(ctx);
                        _abrirExploradorCompleto(item.key);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: const Color(0xFF1A2030), borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(item.key, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                            Text('${item.value}',
                                style: const TextStyle(color: Color(0xFFF5B82E), fontWeight: FontWeight.w900, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cats = _categoriasDinamicas;
    final topCats = cats.take(14).toList();
    return Column(
      children: [
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Row(
            children: [
              CinemaFocusBox(
                borderRadius: 18,
                onTap: () => _abrirPainelTodasCategorias(cats),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5B82E).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFF5B82E)),
                  ),
                  child: Text('Todas as Categorias (${cats.length})',
                      style: const TextStyle(color: Color(0xFFF5B82E), fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),
              CinemaFocusBox(
                borderRadius: 18,
                onTap: () => _abrirExploradorCompleto('Todos'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(18)),
                  child: Text('Ver Tudo (${widget.obras.length})',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: topCats.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, idx) {
                    final label = idx == 0 ? 'Todos' : topCats[idx - 1].key;
                    final qtd = idx == 0 ? widget.obras.length : topCats[idx - 1].value;
                    final ativo = _categoriaSelecionada == label;
                    return CinemaFocusBox(
                      borderRadius: 18,
                      onTap: () => setState(() => _categoriaSelecionada = label),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: ativo ? const Color(0xFFF5B82E) : Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        alignment: Alignment.center,
                        child: Text('$label ($qtd)',
                            style: TextStyle(color: ativo ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _categoriaSelecionada != 'Todos'
              ? _buildGradeDireta(_filtrarPorCategoria(_categoriaSelecionada))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                  itemCount: cats.length + 1,
                  itemBuilder: (context, idx) {
                    if (idx == 0) {
                      return _buildPrateleira(
                        titulo: 'Mais Recentes & Em Alta (${widget.titulo})',
                        total: widget.obras.length,
                        itens: widget.obras.take(20).toList(),
                        onVerTodos: () => _abrirExploradorCompleto('Todos'),
                      );
                    }
                    final cat = cats[idx - 1];
                    final itensCat = _filtrarPorCategoria(cat.key).take(20).toList();
                    if (itensCat.isEmpty) return const SizedBox.shrink();
                    return _buildPrateleira(
                      titulo: cat.key,
                      total: cat.value,
                      itens: itensCat,
                      onVerTodos: () => _abrirExploradorCompleto(cat.key),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPrateleira({required String titulo, required int total, required List<ObraAgrupada> itens, required VoidCallback onVerTodos}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$titulo ($total)', style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w900)),
              const Spacer(),
              CinemaFocusBox(
                borderRadius: 12,
                onTap: onVerTodos,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  child: Text('Ver todos ›', style: TextStyle(color: Color(0xFFF5B82E), fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 245,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              cacheExtent: 360,
              itemCount: itens.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                if (i == itens.length) {
                  return CinemaFocusBox(
                    borderRadius: 10,
                    onTap: onVerTodos,
                    child: Container(
                      width: 148,
                      height: 216,
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B28),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF5B82E).withOpacity(0.5)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.grid_view_rounded, color: Color(0xFFF5B82E), size: 34),
                          const SizedBox(height: 8),
                          Text('Ver Todos\n($total)', textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                }
                return TvPosterCard(obra: itens[i], onTap: () => widget.onAbrirObra(itens[i]));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeDireta(List<ObraAgrupada> itens) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Row(
            children: [
              Text('$_categoriaSelecionada (${itens.length} títulos)',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
              const Spacer(),
              CinemaFocusBox(
                borderRadius: 12,
                onTap: () => _abrirExploradorCompleto(_categoriaSelecionada),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text('Abrir Explorador Completo (Paginado) ›',
                      style: TextStyle(color: Color(0xFFF5B82E), fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.62,
            ),
            itemCount: itens.length,
            itemBuilder: (_, i) => TvPosterCard(obra: itens[i], onTap: () => widget.onAbrirObra(itens[i])),
          ),
        ),
      ],
    );
  }
}

class TvExploradorCompletoScreen extends StatefulWidget {
  final String tituloPagina;
  final String? tipoBanco;
  final String? generoFiltro;
  final String? filtroTermoHub;
  final List<ObraAgrupada> obrasIniciais;
  final ValueChanged<ObraAgrupada> onAbrirObra;

  const TvExploradorCompletoScreen({
    super.key,
    required this.tituloPagina,
    this.tipoBanco,
    this.generoFiltro,
    this.filtroTermoHub,
    required this.obrasIniciais,
    required this.onAbrirObra,
  });

  @override
  State<TvExploradorCompletoScreen> createState() => _TvExploradorCompletoScreenState();
}

class _TvExploradorCompletoScreenState extends State<TvExploradorCompletoScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  late List<ObraAgrupada> _lista;
  String _ordenacao = 'cronologico';
  String _filtroAudio = 'Todos';
  bool _carregandoMais = false;
  bool _temMais = true;
  int _offsetBanco = 0;

  @override
  void initState() {
    super.initState();
    _lista = List<ObraAgrupada>.from(widget.obrasIniciais);
    _offsetBanco = _lista.length;
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 500) {
      _carregarProximaPagina();
    }
  }

  Future<void> _carregarProximaPagina({bool resetar = false}) async {
    if (_carregandoMais || (!_temMais && !resetar)) return;
    setState(() => _carregandoMais = true);
    if (resetar) {
      _offsetBanco = 0;
      _temMais = true;
    }

    final novos = await SupabaseService.instance.buscarPaginaCatalogo(
      offset: _offsetBanco,
      limit: 60,
      tipo: widget.tipoBanco,
      generoOuTag: widget.generoFiltro ?? widget.filtroTermoHub,
      ordenacao: _ordenacao,
    );

    if (!mounted) return;
    setState(() {
      if (resetar) _lista = [];
      final chaves = _lista.map((e) => e.chaveAgrupamento).toSet();
      for (final n in novos) {
        if (chaves.add(n.chaveAgrupamento)) _lista.add(n);
      }
      _offsetBanco += novos.length;
      if (novos.length < 60) _temMais = false;
      _carregandoMais = false;
    });
  }

  List<ObraAgrupada> get _listaFiltrada {
    var base = _lista;
    if (_filtroAudio == 'Dublado') {
      base = base.where((o) => '${o.titulo} ${o.tags}'.toLowerCase().contains('dub')).toList();
    } else if (_filtroAudio == 'Legendado') {
      base = base.where((o) => '${o.titulo} ${o.tags}'.toLowerCase().contains('leg')).toList();
    }
    if (_ordenacao == 'nota') {
      return List<ObraAgrupada>.from(base)..sort((a, b) => b.notaImdb.compareTo(a.notaImdb));
    } else if (_ordenacao == 'az') {
      return List<ObraAgrupada>.from(base)..sort((a, b) => a.titulo.compareTo(b.titulo));
    }
    return SupabaseService.instance.ordenarCronologicoRelevancia(base);
  }

  @override
  Widget build(BuildContext context) {
    final exibidos = _listaFiltrada;
    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              color: const Color(0xFF0E121B),
              child: Row(
                children: [
                  CinemaFocusBox(
                    autofocus: true,
                    borderRadius: 18,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(
                        children: [
                          Icon(Icons.arrow_back_rounded, color: Color(0xFFF5B82E), size: 20),
                          SizedBox(width: 6),
                          Text('Voltar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('${widget.tituloPagina} (${exibidos.length})',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                  ),
                  _chipFiltro('2026→Antigos', _ordenacao == 'cronologico', () {
                    setState(() => _ordenacao = 'cronologico');
                    _carregarProximaPagina(resetar: true);
                  }),
                  const SizedBox(width: 6),
                  _chipFiltro('Nota IMDb', _ordenacao == 'nota', () {
                    setState(() => _ordenacao = 'nota');
                    _carregarProximaPagina(resetar: true);
                  }),
                  const SizedBox(width: 6),
                  _chipFiltro('A–Z', _ordenacao == 'az', () {
                    setState(() => _ordenacao = 'az');
                    _carregarProximaPagina(resetar: true);
                  }),
                  const SizedBox(width: 12),
                  _chipFiltro('Todos Áudios', _filtroAudio == 'Todos', () => setState(() => _filtroAudio = 'Todos')),
                  const SizedBox(width: 6),
                  _chipFiltro('Dublado', _filtroAudio == 'Dublado', () => setState(() => _filtroAudio = 'Dublado')),
                  const SizedBox(width: 6),
                  _chipFiltro('Legendado', _filtroAudio == 'Legendado', () => setState(() => _filtroAudio = 'Legendado')),
                ],
              ),
            ),
            Expanded(
              child: exibidos.isEmpty
                  ? const Center(child: Text('Nenhum título encontrado neste filtro.', style: TextStyle(color: Colors.white60)))
                  : GridView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(18),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.62,
                      ),
                      itemCount: exibidos.length,
                      itemBuilder: (_, i) => TvPosterCard(obra: exibidos[i], onTap: () => widget.onAbrirObra(exibidos[i])),
                    ),
            ),
            if (_carregandoMais)
              const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(color: Color(0xFFF5B82E))),
          ],
        ),
      ),
    );
  }

  Widget _chipFiltro(String label, bool ativo, VoidCallback onTap) {
    return CinemaFocusBox(
      borderRadius: 16,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: ativo ? const Color(0xFFF5B82E) : Colors.white10,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(color: ativo ? Colors.black : Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class TvCanaisGradeScreen extends StatefulWidget {
  final String titulo;
  final List<ObraAgrupada> canais;
  final List<JogoAoVivoInfo> jogosAoVivo;
  final ValueChanged<ObraAgrupada> onAbrirCanal;

  const TvCanaisGradeScreen({
    super.key,
    required this.titulo,
    required this.canais,
    required this.jogosAoVivo,
    required this.onAbrirCanal,
  });

  @override
  State<TvCanaisGradeScreen> createState() => _TvCanaisGradeScreenState();
}

class _TvCanaisGradeScreenState extends State<TvCanaisGradeScreen> {
  String _cat = 'Todos';

  @override
  Widget build(BuildContext context) {
    final cats = <String>{'Todos'};
    for (final c in widget.canais) {
      if (c.categoria.trim().isNotEmpty) cats.add(c.categoria.trim());
    }
    final catList = cats.toList();
    final filtrados = _cat == 'Todos'
        ? widget.canais
        : widget.canais.where((c) => c.categoria.trim() == _cat).toList();

    return Row(
      children: [
        Container(
          width: 220,
          color: const Color(0xFF0D1018),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: catList.length,
            itemBuilder: (_, i) {
              final c = catList[i];
              final sel = c == _cat;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: CinemaFocusBox(
                  borderRadius: 10,
                  onTap: () => setState(() => _cat = c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFFF5B82E) : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(c, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: sel ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(18),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 2.1,
            ),
            itemCount: filtrados.length,
            itemBuilder: (_, i) {
              final canal = filtrados[i];
              final img = canal.capaUrl.isNotEmpty ? canal.capaUrl : canal.bannerUrl;
              return CinemaFocusBox(
                borderRadius: 12,
                onTap: () => widget.onAbrirCanal(canal),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141926),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      if (img.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: img, width: 54, height: 54, fit: BoxFit.contain,
                            memCacheWidth: 140, fadeInDuration: Duration.zero,
                          ),
                        )
                      else
                        const Icon(Icons.live_tv_rounded, color: Color(0xFFF5B82E), size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(canal.titulo, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                            const SizedBox(height: 4),
                            const Text('AO VIVO', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 10)),
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
      ],
    );
  }
}

class TvBuscaScreen extends StatefulWidget {
  final List<ObraAgrupada> catalogo;
  final ValueChanged<ObraAgrupada> onAbrirObra;

  const TvBuscaScreen({super.key, required this.catalogo, required this.onAbrirObra});

  @override
  State<TvBuscaScreen> createState() => _TvBuscaScreenState();
}

class _TvBuscaScreenState extends State<TvBuscaScreen> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final resultados = q.isEmpty
        ? widget.catalogo.take(24).toList()
        : SupabaseService.instance.ordenarCronologicoRelevancia(
            widget.catalogo.where((o) {
              final blob = '${o.titulo} ${o.categoria} ${o.genero} ${o.tags} ${o.ano}'.toLowerCase();
              return blob.contains(q);
            }).toList(),
          );

    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CinemaFocusBox(
                    borderRadius: 18,
                    onTap: () => Navigator.pop(context),
                    child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.arrow_back_rounded, color: Color(0xFFF5B82E))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Buscar filme, série, faroeste, série turca, ator ou canal...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF161B28),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 0.62,
                ),
                itemCount: resultados.length,
                itemBuilder: (_, i) => TvPosterCard(obra: resultados[i], onTap: () => widget.onAbrirObra(resultados[i])),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
