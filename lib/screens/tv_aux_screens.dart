import 'package:flutter/material.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../widgets/cinema_widgets.dart';

class TvBuscaScreen extends StatefulWidget {
  final List<ObraAgrupada> catalogo;
  final void Function(ObraAgrupada) onAbrirObra;

  const TvBuscaScreen({
    super.key,
    required this.catalogo,
    required this.onAbrirObra,
  });

  @override
  State<TvBuscaScreen> createState() => _TvBuscaScreenState();
}

class _TvBuscaScreenState extends State<TvBuscaScreen> {
  final TextEditingController _ctrl = TextEditingController();
  bool _modoNumeros = false;
  bool _buscando = false;
  List<ObraAgrupada> _resultados = [];
  List<ObraAgrupada> _populares = [];

  static const List<String> _letras = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G',
    'H', 'I', 'J', 'K', 'L', 'M', 'N',
    'O', 'P', 'Q', 'R', 'S', 'T', 'U',
    'V', 'W', 'X', 'Y', 'Z',
  ];

  static const List<String> _numeros = [
    '1', '2', '3', '4', '5', '6', '7',
    '8', '9', '0', '-', ':', '.', '/',
  ];

  @override
  void initState() {
    super.initState();
    _atualizarPopulares();
  }

  void _atualizarPopulares() {
    final ordenados = List<ObraAgrupada>.from(widget.catalogo)
      ..sort((a, b) => b.scorePopularidade.compareTo(a.scorePopularidade));
    final top = ordenados.take(30).toList()..shuffle();
    setState(() => _populares = top.take(10).toList());
  }

  Future<void> _executarBusca() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    final res = await SupabaseService.buscarComElencoEDiretores(q, widget.catalogo);
    if (mounted) {
      setState(() {
        _resultados = res;
        _buscando = false;
      });
    }
  }

  void _digitar(String char) {
    _ctrl.text = '${_ctrl.text}$char';
    _executarBusca();
  }

  void _apagarUltimo() {
    if (_ctrl.text.isNotEmpty) {
      _ctrl.text = _ctrl.text.substring(0, _ctrl.text.length - 1);
      _executarBusca();
    }
  }

  void _limpar() {
    _ctrl.clear();
    setState(() => _resultados = []);
  }

  @override
  Widget build(BuildContext context) {
    final emBusca = _ctrl.text.trim().isNotEmpty;
    final listaExibida = emBusca ? _resultados : _populares;
    final isMobile = MediaQuery.of(context).size.width < 650;

    if (isMobile) {
      return Scaffold(
        backgroundColor: const Color(0xFF0E141B),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Pesquisar', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ctrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) {
                  setState(() {});
                  _executarBusca();
                },
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Pesquise filmes, séries ou diretores...',
                  hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFF5B82E)),
                  suffixIcon: emBusca
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: _limpar,
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    emBusca ? 'Resultados da busca' : 'Buscas populares',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  if (!emBusca)
                    InkWell(
                      onTap: _atualizarPopulares,
                      child: const Icon(Icons.refresh, color: Color(0xFFF5B82E), size: 18),
                    ),
                  const Spacer(),
                  Text(
                    'Total: ${listaExibida.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_buscando)
                const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFFF5B82E))))
              else if (listaExibida.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('Nenhum filme, série ou diretor encontrado.', style: TextStyle(color: Colors.white54, fontSize: 15)),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.60,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: listaExibida.length,
                    itemBuilder: (_, idx) => TvPosterCard(
                      obra: listaExibida[idx],
                      onTap: () => widget.onAbrirObra(listaExibida[idx]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0E141B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Pesquisar', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Row(
        children: [
          Container(
            width: 340,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            color: Colors.black.withOpacity(0.28),
            child: Column(
              children: [
                TextField(
                  controller: _ctrl,
                  onChanged: (_) => _executarBusca(),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Pesquise filmes, séries ou diretores.',
                    hintStyle: const TextStyle(color: Colors.white54, fontSize: 13.5),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _teclaEspecial(
                      label: _modoNumeros ? 'ABC' : '123',
                      onTap: () => setState(() => _modoNumeros = !_modoNumeros),
                    ),
                    _teclaEspecial(icon: Icons.delete_outline, onTap: _limpar),
                    _teclaEspecial(icon: Icons.backspace_outlined, onTap: _apagarUltimo),
                    ElevatedButton(
                      onPressed: _executarBusca,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.22),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: const Text('Buscar', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      ...(_modoNumeros ? _numeros : _letras).map(
                        (ch) => InkWell(
                          onTap: () => _digitar(ch),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              ch,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _digitar(' '),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.space_bar, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pedido registrado! Nossa equipe atualiza o catálogo diariamente.')),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Feedback / Pedir Título'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        emBusca ? 'Resultados da busca' : 'Buscas populares',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 14),
                      if (!emBusca)
                        ActionChip(
                          label: const Text('Atualizar'),
                          backgroundColor: Colors.white12,
                          labelStyle: const TextStyle(color: Colors.white),
                          onPressed: _atualizarPopulares,
                        ),
                      const Spacer(),
                      Text(
                        'Total: ${listaExibida.length}',
                        style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_buscando)
                    const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFFF5B82E))))
                  else if (listaExibida.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('Nenhum filme, série ou diretor encontrado.', style: TextStyle(color: Colors.white54, fontSize: 16)),
                      ),
                    )
                  else
                    Expanded(
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 168,
                          childAspectRatio: 0.62,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: listaExibida.length,
                        itemBuilder: (_, idx) => TvPosterCard(
                          obra: listaExibida[idx],
                          onTap: () => widget.onAbrirObra(listaExibida[idx]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teclaEspecial({String? label, IconData? icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
        child: label != null
            ? Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
            : Icon(icon, color: Colors.white, size: 19),
      ),
    );
  }
}

class TvFiltroScreen extends StatefulWidget {
  final List<ObraAgrupada> catalogo;
  final String tipoInicial;
  final void Function(ObraAgrupada) onAbrirObra;

  const TvFiltroScreen({
    super.key,
    required this.catalogo,
    this.tipoInicial = 'Filmes',
    required this.onAbrirObra,
  });

  @override
  State<TvFiltroScreen> createState() => _TvFiltroScreenState();
}

class _TvFiltroScreenState extends State<TvFiltroScreen> {
  late String _tipo;
  String _genero = 'Todos';
  String _ano = 'Todos';
  String _pais = 'Todos';
  String _audio = 'Todos';

  static const List<String> _tipos = ['Filmes', 'Séries', 'Kids', 'Anime'];
  static const List<String> _generos = [
    'Todos', 'Ação', 'Drama', 'Aventura', 'Crime',
    'Ficção científica', 'Desenho', 'Comédia', 'Romance',
    'Animação', 'Suspense', 'Terror', 'Mistério',
  ];
  static const List<String> _anos = [
    'Todos', '2026', '2025', '2024', '2023', '2022',
    '2021', '2020', '2019', '2018', '2017', 'Anteriores',
  ];
  static const List<String> _paises = [
    'Todos', 'Brasil', 'Portugal', 'Estados Unidos', 'México',
    'Reino Unido', 'Japão', 'Coreia do Sul', 'Espanha', 'Alemanha',
  ];
  static const List<String> _audios = ['Todos', 'Português', 'Espanhol', 'Inglês'];

  @override
  void initState() {
    super.initState();
    _tipo = widget.tipoInicial;
  }

  List<ObraAgrupada> get _filtrados {
    return widget.catalogo.where((o) {
      final cat = o.categoria.toLowerCase();
      final gen = SupabaseService.normalizarTexto(o.genero);
      final tags = o.tags.map((t) => SupabaseService.normalizarTexto(t)).toList();

      if (_tipo == 'Filmes' && (!cat.contains('filme') || cat.contains('série') || cat.contains('serie'))) return false;
      if (_tipo == 'Séries' && !(cat.contains('série') || cat.contains('serie'))) return false;
      if (_tipo == 'Kids' && !(cat.contains('infantil') || cat.contains('kids') || gen.contains('infantil') || gen.contains('animacao') || tags.contains('kids'))) return false;
      if (_tipo == 'Anime' && !(cat.contains('anime') || gen.contains('anime') || tags.contains('anime'))) return false;

      if (_genero != 'Todos') {
        final gBusca = SupabaseService.normalizarTexto(_genero);
        if (!gen.contains(gBusca) && !tags.any((t) => t.contains(gBusca))) return false;
      }

      if (_ano != 'Todos') {
        if (_ano == 'Anteriores') {
          final y = int.tryParse(o.ano.trim()) ?? 9999;
          if (y >= 2017) return false;
        } else if (!o.ano.contains(_ano)) {
          return false;
        }
      }

      if (_pais != 'Todos') {
        final pNorm = SupabaseService.normalizarTexto(o.pais);
        final pBusca = SupabaseService.normalizarTexto(_pais);
        if (pNorm.isNotEmpty && !pNorm.contains(pBusca)) return false;
      }

      if (_audio != 'Todos') {
        final aBusca = SupabaseService.normalizarTexto(_audio);
        final temAudio = o.audiosDisponiveis.any((a) {
          final an = SupabaseService.normalizarTexto(a);
          if (aBusca == 'portugues') return an.contains('portugues') || an.contains('dublado') || an.contains('nacional') || an == 'pt';
          if (aBusca == 'ingles') return an.contains('ingles') || an.contains('legendado') || an == 'en';
          return an.contains(aBusca);
        });
        if (!temAudio) return false;
      }
      return true;
    }).toList();
  }

  Widget _linhaFiltro({required String titulo, required List<String> opcoes, required String selecionado, required void Function(String) onSelect}) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(width: 72, child: Text('$titulo:', style: const TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w700))),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: opcoes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final item = opcoes[i];
                final ativo = item == selecionado;
                return InkWell(
                  onTap: () => onSelect(item),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: ativo ? const Color(0xFFF5B82E) : Colors.transparent, borderRadius: BorderRadius.circular(18)),
                    alignment: Alignment.center,
                    child: Text(item, style: TextStyle(color: ativo ? Colors.black : Colors.white, fontSize: 13.5, fontWeight: ativo ? FontWeight.w800 : FontWeight.w500)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: const Color(0xFF0E141B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Filtro Avançado', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(child: Text('${lista.length} encontrados', style: const TextStyle(color: Color(0xFFF5B82E), fontWeight: FontWeight.w700))),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 16),
        child: Column(
          children: [
            _linhaFiltro(titulo: 'Tipo', opcoes: _tipos, selecionado: _tipo, onSelect: (v) => setState(() => _tipo = v)),
            const SizedBox(height: 6),
            _linhaFiltro(titulo: 'Gênero', opcoes: _generos, selecionado: _genero, onSelect: (v) => setState(() => _genero = v)),
            const SizedBox(height: 6),
            _linhaFiltro(titulo: 'Ano', opcoes: _anos, selecionado: _ano, onSelect: (v) => setState(() => _ano = v)),
            const SizedBox(height: 6),
            _linhaFiltro(titulo: 'País', opcoes: _paises, selecionado: _pais, onSelect: (v) => setState(() => _pais = v)),
            const SizedBox(height: 6),
            _linhaFiltro(titulo: 'Áudio', opcoes: _audios, selecionado: _audio, onSelect: (v) => setState(() => _audio = v)),
            const SizedBox(height: 16),
            Expanded(
              child: lista.isEmpty
                  ? const Center(child: Text('Nenhum título encontrado com essa combinação de filtros.', style: TextStyle(color: Colors.white54, fontSize: 16)))
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 168, childAspectRatio: 0.62, crossAxisSpacing: 14, mainAxisSpacing: 14),
                      itemCount: lista.length,
                      itemBuilder: (_, idx) => TvPosterCard(obra: lista[idx], onTap: () => widget.onAbrirObra(lista[idx])),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class TvHistoricoFavoritosScreen extends StatefulWidget {
  final List<ObraAgrupada> catalogo;
  final void Function(ObraAgrupada) onAbrirObra;

  const TvHistoricoFavoritosScreen({
    super.key,
    required this.catalogo,
    required this.onAbrirObra,
  });

  @override
  State<TvHistoricoFavoritosScreen> createState() => _TvHistoricoFavoritosScreenState();
}

class _TvHistoricoFavoritosScreenState extends State<TvHistoricoFavoritosScreen> {
  int _abaLateral = 0;
  bool _somenteSeries = false;
  bool _modoEdicao = false;
  final Set<String> _selecionados = {};
  Map<String, Map<String, dynamic>> _historicoMap = {};
  Set<String> _favoritosSet = {};

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    final hist = await SupabaseService.carregarProgressoAssistido();
    final favs = await SupabaseService.carregarFavoritos();
    if (mounted) {
      setState(() {
        _historicoMap = hist;
        _favoritosSet = favs;
      });
    }
  }

  List<ObraAgrupada> get _itensAtuais {
    final base = _abaLateral == 0
        ? widget.catalogo.where((o) => _historicoMap.containsKey(o.chaveGrupo)).toList()
        : widget.catalogo.where((o) => _favoritosSet.contains(o.chaveGrupo)).toList();
    return base.where((o) => _somenteSeries ? o.isSerie : !o.isSerie).toList();
  }

  Future<void> _excluirSelecionados() async {
    if (_selecionados.isEmpty) return;
    if (_abaLateral == 0) {
      await SupabaseService.removerDoHistorico(_selecionados.toList());
    } else {
      for (final ch in _selecionados) {
        await SupabaseService.alternarFavorito(ch);
      }
    }
    setState(() {
      _selecionados.clear();
      _modoEdicao = false;
    });
    await _carregarDados();
  }

  Future<void> _limparTudo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B24),
        title: Text(_abaLateral == 0 ? 'Limpar Histórico?' : 'Limpar Favoritos?'),
        content: const Text('Tem certeza que deseja remover todos os itens desta lista?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir tudo'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (_abaLateral == 0) {
        await SupabaseService.limparTodoHistorico();
      } else {
        for (final ch in _favoritosSet.toList()) {
          await SupabaseService.alternarFavorito(ch);
        }
      }
      setState(() {
        _selecionados.clear();
        _modoEdicao = false;
      });
      await _carregarDados();
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseAtual = _abaLateral == 0
        ? widget.catalogo.where((o) => _historicoMap.containsKey(o.chaveGrupo)).toList()
        : widget.catalogo.where((o) => _favoritosSet.contains(o.chaveGrupo)).toList();
    final totalFilmes = baseAtual.where((o) => !o.isSerie).length;
    final totalSeries = baseAtual.where((o) => o.isSerie).length;
    final exibidos = _itensAtuais;

    return Scaffold(
      backgroundColor: const Color(0xFF0E141B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_abaLateral == 0 ? 'Histórico' : 'Meus Favoritos'),
      ),
      body: Row(
        children: [
          Container(
            width: 230,
            padding: const EdgeInsets.symmetric(vertical: 20),
            color: Colors.black.withOpacity(0.24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _itemMenuLateral(
                  titulo: 'Histórico',
                  ativo: _abaLateral == 0,
                  onTap: () => setState(() {
                    _abaLateral = 0;
                    _modoEdicao = false;
                    _selecionados.clear();
                  }),
                ),
                const SizedBox(height: 8),
                _itemMenuLateral(
                  titulo: 'Meus Favoritos',
                  ativo: _abaLateral == 1,
                  onTap: () => setState(() {
                    _abaLateral = 1;
                    _modoEdicao = false;
                    _selecionados.clear();
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _pilulaTipo(label: 'Filmes', ativo: !_somenteSeries, onTap: () => setState(() => _somenteSeries = false)),
                      const SizedBox(width: 12),
                      _pilulaTipo(label: 'Séries', ativo: _somenteSeries, onTap: () => setState(() => _somenteSeries = true)),
                      const SizedBox(width: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Selecionar itens para remover',
                              icon: Icon(Icons.edit_note, color: _modoEdicao ? const Color(0xFFF5B82E) : Colors.white),
                              onPressed: () => setState(() {
                                _modoEdicao = !_modoEdicao;
                                _selecionados.clear();
                              }),
                            ),
                            IconButton(
                              tooltip: 'Excluir tudo',
                              icon: const Icon(Icons.delete_outline, color: Colors.white),
                              onPressed: _limparTudo,
                            ),
                          ],
                        ),
                      ),
                      if (_modoEdicao && _selecionados.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: _excluirSelecionados,
                          icon: const Icon(Icons.delete, size: 18),
                          label: Text('Remover (${_selecionados.length})'),
                        ),
                      ],
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Total de filmes  $totalFilmes', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          Text('Total de séries  $totalSeries', style: const TextStyle(color: Color(0xFFF5B82E), fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: exibidos.isEmpty
                        ? Center(
                            child: Text(
                              _abaLateral == 0 ? 'Nenhum título assistido ainda.' : 'Nenhum título nos seus favoritos ainda.',
                              style: const TextStyle(color: Colors.white54, fontSize: 16),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 168,
                              childAspectRatio: 0.62,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                            ),
                            itemCount: exibidos.length,
                            itemBuilder: (_, idx) {
                              final obra = exibidos[idx];
                              final prog = _historicoMap[obra.chaveGrupo]?['progresso'] as double?;
                              final sel = _selecionados.contains(obra.chaveGrupo);
                              return TvPosterCard(
                                obra: obra,
                                progresso: _abaLateral == 0 ? prog : null,
                                modoEdicao: _modoEdicao,
                                selecionadoEdicao: sel,
                                onTap: () {
                                  if (_modoEdicao) {
                                    setState(() {
                                      if (sel) {
                                        _selecionados.remove(obra.chaveGrupo);
                                      } else {
                                        _selecionados.add(obra.chaveGrupo);
                                      }
                                    });
                                  } else {
                                    widget.onAbrirObra(obra);
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemMenuLateral({required String titulo, required bool ativo, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: ativo ? const LinearGradient(colors: [Color(0xFFF5B82E), Color(0x22F5B82E)]) : null,
        ),
        child: Text(titulo, style: TextStyle(color: ativo ? Colors.black : Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _pilulaTipo({required String label, required bool ativo, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: ativo ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ativo ? const Color(0xFFF5B82E) : Colors.white30),
        ),
        child: Text(label, style: TextStyle(color: ativo ? const Color(0xFFF5B82E) : Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class TvTop100RankingScreen extends StatefulWidget {
  final String fonte;
  final String categoriaInicial;
  final List<ObraAgrupada> catalogo;
  final void Function(ObraAgrupada) onAbrirObra;

  const TvTop100RankingScreen({
    super.key,
    required this.fonte,
    this.categoriaInicial = 'Filmes',
    required this.catalogo,
    required this.onAbrirObra,
  });

  @override
  State<TvTop100RankingScreen> createState() => _TvTop100RankingScreenState();
}

class _TvTop100RankingScreenState extends State<TvTop100RankingScreen> {
  late String _categoria;
  bool _carregando = true;
  List<ObraAgrupada> _lista = [];
  static const List<String> _cats = ['Filmes', 'Séries', 'Kids', 'Anime'];

  @override
  void initState() {
    super.initState();
    _categoria = widget.categoriaInicial;
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final res = await SupabaseService.carregarTop100Ranking(
      fonte: widget.fonte,
      categoria: _categoria,
      catalogoLocal: widget.catalogo,
    );
    if (mounted) {
      setState(() {
        _lista = res;
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tituloBase = widget.fonte == 'imdb' ? 'Top 100 IMDb' : 'Top 100 TMDB';
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('$tituloBase • $_categoria', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: _cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, idx) {
                final c = _cats[idx];
                final ativo = c == _categoria;
                return ChoiceChip(
                  label: Text(c),
                  selected: ativo,
                  selectedColor: const Color(0xFFF5B82E),
                  labelStyle: TextStyle(color: ativo ? Colors.black : Colors.white, fontWeight: FontWeight.w700),
                  onSelected: (_) {
                    setState(() => _categoria = c);
                    _carregar();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFF5B82E)))
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 168,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: _lista.length,
                    itemBuilder: (_, idx) => TvPosterCard(
                      obra: _lista[idx],
                      rankNumero: idx + 1,
                      onTap: () => widget.onAbrirObra(_lista[idx]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class TvSubcategoriaScreen extends StatefulWidget {
  final String titulo;
  final List<ObraAgrupada> itens;
  final List<String> subfiltros;
  final String? filtroInicial;
  final void Function(ObraAgrupada) onAbrirObra;
  final VoidCallback onAbrirBusca;
  final VoidCallback onAbrirFiltro;

  const TvSubcategoriaScreen({
    super.key,
    required this.titulo,
    required this.itens,
    required this.subfiltros,
    this.filtroInicial,
    required this.onAbrirObra,
    required this.onAbrirBusca,
    required this.onAbrirFiltro,
  });

  @override
  State<TvSubcategoriaScreen> createState() => _TvSubcategoriaScreenState();
}

class _TvSubcategoriaScreenState extends State<TvSubcategoriaScreen> {
  bool _menuAberto = true;
  late String _selecionado;

  @override
  void initState() {
    super.initState();
    _selecionado = widget.filtroInicial ?? widget.subfiltros.first;
  }

  List<ObraAgrupada> get _filtrados {
    if (_selecionado == 'Todos' || _selecionado == 'Tudo') return widget.itens;
    final busca = SupabaseService.normalizarTexto(_selecionado);
    return widget.itens.where((o) {
      final g = SupabaseService.normalizarTexto(o.genero);
      final t = o.tags.map((e) => SupabaseService.normalizarTexto(e)).toList();
      final tit = SupabaseService.normalizarTexto(o.titulo);
      return g.contains(busca) || t.any((x) => x.contains(busca)) || tit.contains(busca);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: Row(
          children: [
            IconButton(
              tooltip: _menuAberto ? 'Recolher menu' : 'Expandir menu',
              icon: Icon(_menuAberto ? Icons.menu_open : Icons.menu),
              onPressed: () => setState(() => _menuAberto = !_menuAberto),
            ),
            const SizedBox(width: 6),
            Text('${widget.titulo} • $_selecionado', style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          TopIconeComTooltip(icon: Icons.search, label: 'Buscar', onPressed: widget.onAbrirBusca),
          const SizedBox(width: 10),
          TopIconeComTooltip(icon: Icons.filter_alt_outlined, label: 'Filtro', onPressed: widget.onAbrirFiltro),
          const SizedBox(width: 20),
        ],
      ),
      body: Row(
        children: [
          if (_menuAberto)
            Container(
              width: 210,
              color: const Color(0xFF11141C),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: widget.subfiltros.length,
                itemBuilder: (_, idx) {
                  final f = widget.subfiltros[idx];
                  final ativo = f == _selecionado;
                  return ListTile(
                    selected: ativo,
                    selectedTileColor: const Color(0xFFF5B82E).withOpacity(0.18),
                    title: Text(
                      f,
                      style: TextStyle(color: ativo ? const Color(0xFFF5B82E) : Colors.white70, fontWeight: ativo ? FontWeight.w800 : FontWeight.w500),
                    ),
                    onTap: () => setState(() => _selecionado = f),
                  );
                },
              ),
            ),
          Expanded(
            child: lista.isEmpty
                ? const Center(child: Text('Nenhum título nesta subcategoria.', style: TextStyle(color: Colors.white54)))
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 168,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: lista.length,
                    itemBuilder: (_, idx) => TvPosterCard(obra: lista[idx], onTap: () => widget.onAbrirObra(lista[idx])),
                  ),
          ),
        ],
      ),
    );
  }
}
