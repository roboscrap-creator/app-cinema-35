import 'package:flutter/material.dart';
import 'models/midia_model.dart';
import 'services/supabase_service.dart';
import 'screens/player_screen.dart';
import 'screens/aba_categoria_page.dart';

void main() => runApp(const CinemaApp());

class CinemaApp extends StatelessWidget {
  const CinemaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cinema',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF12131A),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF12131A), elevation: 0),
      ),
      home: const HomeCinemaPage(),
    );
  }
}

class HomeCinemaPage extends StatefulWidget {
  const HomeCinemaPage({super.key});
  @override
  State<HomeCinemaPage> createState() => _HomeCinemaPageState();
}

class _HomeCinemaPageState extends State<HomeCinemaPage> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<ObraAgrupada> _todas = [];
  bool _carregando = true;
  String? _erro;
  static const List<String> _abas = ['Recomendações', 'Filmes', 'Séries', 'Infantil', 'Anime'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _abas.length, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() { _carregando = true; _erro = null; });
    try {
      final lista = await SupabaseService.carregarCatalogoAgrupado();
      setState(() => _todas = lista);
    } catch (e) {
      setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<ObraAgrupada> _filtrarAba(String aba) {
    if (aba == 'Recomendações') return _todas;
    final alow = aba.toLowerCase();
    return _todas.where((o) => o.categoria.toLowerCase().contains(alow) || o.genero.toLowerCase().contains(alow)).toList();
  }

  void _abrirObra(ObraAgrupada obra) {
    if (obra.fontes.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(obra: obra, fonteInicial: obra.fontes.first)));
  }

  void _abrirBusca() {
    showSearch(context: context, delegate: _BuscaObraDelegate(_todas, _abrirObra));
  }

  void _configurarKey() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supabase Anon Key'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Cole sua anon_key')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              await SupabaseService.salvarAnonKey(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _carregar();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Cinema', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        actions: [IconButton(icon: const Icon(Icons.search, size: 24), onPressed: _abrirBusca)],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: const Color(0xFF2196F3),
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
          tabs: _abas.map((a) => Tab(text: a)).toList(),
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('$_erro', style: const TextStyle(color: Colors.redAccent)), const SizedBox(height: 12), ElevatedButton(onPressed: _configurarKey, child: const Text('Configurar Anon Key')), TextButton(onPressed: _carregar, child: const Text('Tentar Novamente'))]))
              : TabBarView(controller: _tabCtrl, children: _abas.map((a) => AbaCategoriaPage(nomeAba: a, obras: _filtrarAba(a), onAbrirObra: _abrirObra)).toList()),
    );
  }
}

class _BuscaObraDelegate extends SearchDelegate {
  final List<ObraAgrupada> obras;
  final Function(ObraAgrupada) onAbrir;
  _BuscaObraDelegate(this.obras, this.onAbrir);
  @override List<Widget> buildActions(BuildContext c) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override Widget? buildLeading(BuildContext c) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(c, null));
  @override Widget buildResults(BuildContext c) => _resultados();
  @override Widget buildSuggestions(BuildContext c) => _resultados();
  Widget _resultados() {
    final q = query.toLowerCase().trim();
    final filtradas = q.isEmpty ? obras.take(20).toList() : obras.where((o) => o.titulo.toLowerCase().contains(q)).toList();
    return ListView.builder(itemCount: filtradas.length, itemBuilder: (c, i) {
      final o = filtradas[i];
      return ListTile(leading: o.capaUrl.isNotEmpty ? Image.network(o.capaUrl, width: 40, height: 58, fit: BoxFit.cover) : const Icon(Icons.movie), title: Text(o.titulo), subtitle: Text(o.categoria), onTap: () { close(c, null); onAbrir(o); });
    });
  }
}
