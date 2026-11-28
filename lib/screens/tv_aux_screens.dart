import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';

class TvFiltroScreen extends StatefulWidget {
  final String tituloPagina;
  final List<ObraAgrupada> catalogoCompleto;
  final String? filtroTipo;
  final String? filtroPlataforma;
  final String? filtroGeneroInicial;
  final bool isKids;
  final Function(ObraAgrupada) onAbrirObra;
  final Function(String) onNavegarAba;
  final VoidCallback onAlternarModoMobile;

  const TvFiltroScreen({
    super.key,
    required this.tituloPagina,
    required this.catalogoCompleto,
    this.filtroTipo,
    this.filtroPlataforma,
    this.filtroGeneroInicial,
    this.isKids = false,
    required this.onAbrirObra,
    required this.onNavegarAba,
    required this.onAlternarModoMobile,
  });

  @override
  State<TvFiltroScreen> createState() => _TvFiltroScreenState();
}

class _TvFiltroScreenState extends State<TvFiltroScreen> {
  String _generoSelecionado = 'Todos';
  String _ordenacao = 'lancamentos';
  int _limiteExibido = 60;
  final ScrollController _scrollController = ScrollController();

  static const List<String> _abasTopo = [
    'Início', 'Filmes', 'Séries', 'Sports', 'TV', 'Kids', 'Animes', 'Max', 'Procurar', 'Favoritos'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.filtroGeneroInicial != null && widget.filtroGeneroInicial!.isNotEmpty) {
      _generoSelecionado = widget.filtroGeneroInicial!;
    }
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
        setState(() => _limiteExibido += 60);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<String> _extrairGenerosDisponiveis(List<ObraAgrupada> base) {
    final contagem = <String, int>{};
    for (final o in base) {
      for (final g in o.generos) {
        if (g.length > 2) contagem[g] = (contagem[g] ?? 0) + 1;
      }
    }
    final ordenados = contagem.keys.toList()..sort((a, b) => (contagem[b] ?? 0).compareTo(contagem[a] ?? 0));
    return ['Todos', ...ordenados];
  }

  List<ObraAgrupada> _filtrarBase() {
    var lista = widget.catalogoCompleto.where((o) {
      if (widget.isKids) {
        final g = o.genero.toLowerCase();
        final t = o.tipo.toLowerCase();
        return g.contains('infantil') || g.contains('kids') || g.contains('anima') || g.contains('família') || t.contains('kids');
      }
      if (widget.filtroTipo != null && widget.filtroTipo!.isNotEmpty) {
        final f = widget.filtroTipo!.toLowerCase();
        final t = o.tipo.toLowerCase();
        final g = o.genero.toLowerCase();
        if (f == 'anime') return t.contains('anime') || g.contains('anime');
        if (f == 'série' || f == 'serie') return (t.contains('série') || t.contains('serie')) && !t.contains('anime');
        if (f == 'filme') return t.contains('filme');
      }
      if (widget.filtroPlataforma != null && widget.filtroPlataforma!.isNotEmpty) {
        final p = widget.filtroPlataforma!.toLowerCase();
        final tudo = '${o.titulo}${o.genero} ${o.sinopse}${o.tipo}'.toLowerCase();
        if (p == 'netflix') return tudo.contains('netflix');
        if (p == 'prime video') return tudo.contains('prime') || tudo.contains('amazon');
        if (p == 'hbo max') return tudo.contains('hbo') || tudo.contains('max');
        if (p == 'disney+') return tudo.contains('disney') || tudo.contains('pixar') || tudo.contains('marvel') || tudo.contains('star wars');
        if (p == 'telecine') return tudo.contains('telecine');
        return tudo.contains(p);
      }
      return true;
    }).toList();

    if (_generoSelecionado != 'Todos') {
      final gSel = _generoSelecionado.toLowerCase();
      lista = lista.where((o) => o.genero.toLowerCase().contains(gSel)).toList();
    }

    lista.sort((a, b) {
      if (_ordenacao == 'nota') {
        final cmpNota = b.notaImdb.compareTo(a.notaImdb);
        return cmpNota != 0 ? cmpNota : b.ano.compareTo(a.ano);
      } else if (_ordenacao == 'az') {
        return a.titulo.compareTo(b.titulo);
      } else {
        final aAlta = SupabaseService.estaEmAltaTmdbImdb(a) ? 1 : 0;
        final bAlta = SupabaseService.estaEmAltaTmdbImdb(b) ? 1 : 0;
        if (a.ano >= 2025 && b.ano >= 2025 && aAlta != bAlta) return bAlta.compareTo(aAlta);
        final cmpAno = b.ano.compareTo(a.ano);
        if (cmpAno != 0) return cmpAno;
        if (aAlta != bAlta) return bAlta.compareTo(aAlta);
        return b.notaImdb.compareTo(a.notaImdb);
      }
    });
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final baseTipo = _filtrarBase();
    final generos = _extrairGenerosDisponiveis(widget.catalogoCompleto);
    final exibidos = baseTipo.take(_limiteExibido).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 6),
              child: Row(
                children: [
                  Text('${widget.tituloPagina} (${baseTipo.length})', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  _buildSortChip('2026 → Antigos', 'lancamentos'),
                  const SizedBox(width: 8),
                  _buildSortChip('Melhor IMDb', 'nota'),
                  const SizedBox(width: 8),
                  _buildSortChip('A–Z', 'az'),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                scrollDirection: Axis.horizontal,
                itemCount: generos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final gen = generos[index];
                  final ativo = gen == _generoSelecionado;
                  return ChoiceChip(
                    label: Text(gen),
                    selected: ativo,
                    selectedColor: const Color(0xFFE50914),
                    backgroundColor: const Color(0xFF161B26),
                    labelStyle: TextStyle(color: ativo ? Colors.white : Colors.white70, fontWeight: ativo ? FontWeight.bold : FontWeight.normal),
                    onSelected: (_) => setState(() {
                      _generoSelecionado = gen;
                      _limiteExibido = 60;
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: exibidos.isEmpty
                  ? const Center(child: Text('Nenhum título encontrado neste filtro.', style: TextStyle(color: Colors.white60, fontSize: 16)))
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, childAspectRatio: 0.66, crossAxisSpacing: 14, mainAxisSpacing: 14),
                      itemCount: exibidos.length,
                      itemBuilder: (context, index) {
                        final obra = exibidos[index];
                        return InkWell(
                          onTap: () => widget.onAbrirObra(obra),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(color: const Color(0xFF141923), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (obra.capaUrl.isNotEmpty)
                                  CachedNetworkImage(imageUrl: obra.capaUrl, fit: BoxFit.cover, memCacheWidth: 360, fadeInDuration: Duration.zero, errorWidget: (_, __, ___) => const Icon(Icons.movie, color: Colors.white30, size: 40)),
                                Positioned(
                                  left: 0, right: 0, bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black, Colors.transparent])),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(obra.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                        Text('${obra.ano > 0 ? obra.ano : ''} • ★ ${obra.notaImdb.toStringAsFixed(1)}', style: const TextStyle(color: Colors.amber, fontSize: 10)),
                                      ],
                                    ),
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
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, String value) {
    final ativo = _ordenacao == value;
    return InkWell(
      onTap: () => setState(() => _ordenacao = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: ativo ? const Color(0xFFE50914) : const Color(0xFF161B26), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: const Color(0xFF0D111A),
      child: Row(
        children: [
          const Text('CineMAX', style: TextStyle(color: Color(0xFFE50914), fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(width: 18),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _abasTopo.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final aba = _abasTopo[i];
                final ativa = aba.toLowerCase() == widget.tituloPagina.toLowerCase();
                return TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onNavegarAba(aba);
                  },
                  style: TextButton.styleFrom(backgroundColor: ativa ? const Color(0xFFE50914) : Colors.transparent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  child: Text(aba, style: TextStyle(fontWeight: ativa ? FontWeight.bold : FontWeight.w500)),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onAlternarModoMobile();
            },
            icon: const Icon(Icons.smartphone, size: 16, color: Colors.white),
            label: const Text('Modo Celular', style: TextStyle(color: Colors.white, fontSize: 12)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24)),
          ),
        ],
      ),
    );
  }
}

class TvHistoricoFavoritosScreen extends StatelessWidget {
  final List<ObraAgrupada> catalogoCompleto;
  final Function(ObraAgrupada) onAbrirObra;
  final VoidCallback onAlternarModoMobile;

  const TvHistoricoFavoritosScreen({super.key, required this.catalogoCompleto, required this.onAbrirObra, required this.onAlternarModoMobile});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Set<String>>(
      future: SupabaseService.carregarFavoritos(),
      builder: (context, snap) {
        final favs = snap.data ?? <String>{};
        final lista = catalogoCompleto.where((o) => favs.contains(o.titulo)).toList();
        return TvFiltroScreen(tituloPagina: 'Favoritos', catalogoCompleto: lista, onAbrirObra: onAbrirObra, onNavegarAba: (_) {}, onAlternarModoMobile: onAlternarModoMobile);
      },
    );
  }
}

class TvTop100RankingScreen extends StatelessWidget {
  final String titulo;
  final List<ObraAgrupada> itens;
  final Function(ObraAgrupada) onAbrirObra;
  final VoidCallback onAlternarModoMobile;

  const TvTop100RankingScreen({super.key, required this.titulo, required this.itens, required this.onAbrirObra, required this.onAlternarModoMobile});

  @override
  Widget build(BuildContext context) {
    return TvFiltroScreen(tituloPagina: titulo, catalogoCompleto: itens, onAbrirObra: onAbrirObra, onNavegarAba: (_) {}, onAlternarModoMobile: onAlternarModoMobile);
  }
}
