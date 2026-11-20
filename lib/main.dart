import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'models/midia_model.dart';
import 'services/supabase_service.dart';
import 'screens/detalhe_obra_screen.dart';
import 'screens/aba_categoria_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const CinemaApp());
}

class CinemaApp extends StatelessWidget {
  const CinemaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cinema',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B0C10), elevation: 0),
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
  int _navIndex = 0;
  static const List<String> _abas = ['Recomendações', 'Filmes', 'Séries', 'Infantil', 'Anime'];
  static const Color _corDourado = Color(0xFFF5B82E);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _abas.length, vsync: this);
    _carregar();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _carregar({bool forcar = false}) async {
    setState(() { _carregando = true; _erro = null; });
    try {
      final lista = await SupabaseService.carregarCatalogoAgrupado(forcarRefresh: forcar);
      setState(() => _todas = lista);
    } catch (e) { setState(() => _erro = e.toString()); }
    finally { if (mounted) setState(() => _carregando = false); }
  }

  List<ObraAgrupada> _filtrarAba(String aba) {
    if (aba == 'Recomendações') return _todas;
    return _todas.where((o) {
      final c = o.categoria.toLowerCase(), g = o.genero.toLowerCase();
      final tags = o.tags.map((t) => t.toLowerCase()).toList();
      if (aba == 'Filmes') return c.contains('filme') && !c.contains('série') && !c.contains('serie');
      if (aba == 'Séries') return c.contains('série') || c.contains('serie');
      if (aba == 'Infantil') return c.contains('infantil') || g.contains('infantil') || g.contains('animação') || g.contains('animacao') || tags.contains('infantil');
      if (aba == 'Anime') return c.contains('anime') || g.contains('anime') || tags.contains('anime');
      return true;
    }).toList();
  }

  void _abrirObra(ObraAgrupada obra) {
    if (obra.fontes.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => DetalheObraScreen(obra: obra)));
  }

  void _configurarKey() async {
    final ctrl = TextEditingController();
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Supabase Anon Key'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Cole sua anon_key')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () async { await SupabaseService.salvarAnonKey(ctrl.text); if (ctx.mounted) Navigator.pop(ctx); _carregar(forcar: true); }, child: const Text('Salvar')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Cinema', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.search, size: 25), onPressed: () => showSearch(context: context, delegate: _BuscaObraDelegate(_todas, _abrirObra)))],
        bottom: _navIndex == 0 ? TabBar(
          controller: _tabCtrl, isScrollable: true, tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent, indicatorColor: Colors.transparent,
          labelColor: _corDourado, unselectedLabelColor: Colors.white,
          labelStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
          tabs: _abas.map((a) => Tab(text: a)).toList(),
        ) : null,
      ),
      body: _navIndex == 0
          ? (_carregando ? const Center(child: CircularProgressIndicator(color: _corDourado))
              : _erro != null ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text('$_erro', style: const TextStyle(color: Colors.redAccent)), ElevatedButton(onPressed: _configurarKey, child: const Text('Configurar Key'))]))
              : RefreshIndicator(color: _corDourado, onRefresh: () => _carregar(forcar: true), child: TabBarView(controller: _tabCtrl, children: _abas.map((a) => AbaCategoriaPage(nomeAba: a, obras: _filtrarAba(a), onAbrirObra: _abrirObra)).toList())))
          : ListView(padding: const EdgeInsets.all(16), children: [
              ListTile(leading: const Icon(Icons.refresh, color: _corDourado), title: const Text('Atualizar Catálogo Agora'), onTap: () { setState(() => _navIndex = 0); _carregar(forcar: true); }),
              ListTile(leading: const Icon(Icons.vpn_key, color: _corDourado), title: const Text('Configurar Chave Supabase'), onTap: _configurarKey),
            ]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex, onTap: (i) => setState(() => _navIndex = i),
        backgroundColor: const Color(0xFF0B0C10), type: BottomNavigationBarType.fixed,
        selectedItemColor: _corDourado, unselectedItemColor: Colors.white60,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home_filled), label: 'VOD'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline), label: 'Shorts'),
          BottomNavigationBarItem(icon: Icon(Icons.live_tv_outlined), label: 'Previsão'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
      ),
    );
  }
}

class _BuscaObraDelegate extends SearchDelegate {
  final List<ObraAgrupada> obras; final Function(ObraAgrupada) onAbrir;
  _BuscaObraDelegate(this.obras, this.onAbrir);
  @override List<Widget> buildActions(BuildContext c) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override Widget? buildLeading(BuildContext c) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(c, null));
  @override Widget buildResults(BuildContext c) => _res();
  @override Widget buildSuggestions(BuildContext c) => _res();
  Widget _res() {
    final q = query.toLowerCase().trim();
    final f = q.isEmpty ? obras.take(20).toList() : obras.where((o) => o.titulo.toLowerCase().contains(q)).toList();
    return ListView.builder(itemCount: f.length, itemBuilder: (c, i) => ListTile(leading: f[i].capaUrl.isNotEmpty ? Image.network(f[i].capaUrl, width: 40, height: 58, fit: BoxFit.cover) : const Icon(Icons.movie), title: Text(f[i].titulo), subtitle: Text(f[i].categoria), onTap: () { close(c, null); onAbrir(f[i]); }));
  }
}
