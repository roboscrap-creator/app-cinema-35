import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models/catalogo_item.dart';
import 'services/supabase_service.dart';
import 'screens/vitrine_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RoboScrapApp());
}

class RoboScrapApp extends StatelessWidget {
  const RoboScrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboScrap 3.5',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E1015),
        colorScheme: const ColorScheme.dark(primary: Colors.amber, secondary: Colors.tealAccent),
      ),
      home: const HomeAdmin(),
    );
  }
}

class HomeAdmin extends StatefulWidget {
  const HomeAdmin({super.key});

  @override
  State<HomeAdmin> createState() => _HomeAdminState();
}

class _HomeAdminState extends State<HomeAdmin> {
  int _abaAtual = 0;
  String _supabaseUrl = 'https://kuziampmbltqdqkqyrlb.supabase.co';
  String _serviceKey = '';
  String _tmdbKey = '';
  List<CatalogoItem> _catalogo = [];
  bool _carregando = false;

  SupabaseService get _sb => SupabaseService(supabaseUrl: _supabaseUrl, serviceKey: _serviceKey);

  @override
  void initState() {
    super.initState();
    _carregarConfig();
  }

  Future<void> _carregarConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _supabaseUrl = prefs.getString('admin_sb_url') ?? 'https://kuziampmbltqdqkqyrlb.supabase.co';
      _serviceKey = prefs.getString('admin_sb_key') ?? '';
      _tmdbKey = prefs.getString('admin_tmdb_key') ?? '';
    });
    if (_serviceKey.isNotEmpty) {
      _atualizarCatalogo(); } catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red)); } }
    } else {
      setState(() => _abaAtual = 3);
    }
  }

  Future<void> _atualizarCatalogo() async {
    if (_serviceKey.isEmpty) return;
    setState(() => _carregando = true);
    try {
      final itens = await _sb.listarCatalogo();
      if (mounted) setState(() => _catalogo = itens);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _dialogAdicionarMidia() async {
    final tituloCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final backupCtrl = TextEditingController();
    final capaCtrl = TextEditingController();
    final bannerCtrl = TextEditingController();
    final sinopseCtrl = TextEditingController();
    final generoCtrl = TextEditingController(text: 'Ação, Aventura');
    final anoCtrl = TextEditingController(text: '2026');
    String categoria = 'Filme';
    String resolucao = '1080p';
    String audio = 'Dublado';
    bool buscandoTmdb = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Publicar Filme / Série / Canal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tituloCtrl,
                        decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
                      ),
                    ),
                    if (_tmdbKey.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Buscar Capa e Sinopse no TMDB',
                        icon: buscandoTmdb
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.auto_awesome, color: Colors.amber),
                        onPressed: () async {
                          if (tituloCtrl.text.trim().isEmpty) return;
                          setDialog(() => buscandoTmdb = true);
                          try {
                            final q = Uri.encodeComponent(tituloCtrl.text.trim());
                            final r = await http.get(Uri.parse('https://api.themoviedb.org/3/search/multi?api_key=$_tmdbKey&language=pt-BR&query=$q'));
                            if (r.statusCode == 200) {
                              final results = (jsonDecode(r.body)['results'] as List?) ?? [];
                              if (results.isNotEmpty) {
                                final m = results.first;
                                setDialog(() {
                                  tituloCtrl.text = m['title'] ?? m['name'] ?? tituloCtrl.text;
                                  sinopseCtrl.text = m['overview'] ?? '';
                                  if (m['poster_path'] != null) capaCtrl.text = 'https://image.tmdb.org/t/p/w500${m['poster_path']}';
                                  if (m['backdrop_path'] != null) bannerCtrl.text = 'https://image.tmdb.org/t/p/original${m['backdrop_path']}';
                                  final data = (m['release_date'] ?? m['first_air_date'] ?? '').toString();
                                  if (data.length >= 4) anoCtrl.text = data.substring(0, 4);
                                });
                              }
                            }
                          } catch (_) {}
                          setDialog(() => buscandoTmdb = false);
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: categoria,
                  decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Filme', child: Text('Filme')),
                    DropdownMenuItem(value: 'Série', child: Text('Série')),
                    DropdownMenuItem(value: 'TV Ao Vivo', child: Text('TV Ao Vivo')),
                  ],
                  onChanged: (v) => setDialog(() => categoria = v ?? 'Filme'),
                ),
                const SizedBox(height: 10),
                TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'Link Stream Principal (.m3u8 / .mp4)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: backupCtrl, decoration: const InputDecoration(labelText: 'Link Stream Backup (Opcional)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: resolucao,
                        decoration: const InputDecoration(labelText: 'Qualidade', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: '4K', child: Text('4K')),
                          DropdownMenuItem(value: '1080p', child: Text('1080p')),
                          DropdownMenuItem(value: '720p', child: Text('720p')),
                        ],
                        onChanged: (v) => setDialog(() => resolucao = v ?? '1080p'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: audio,
                        decoration: const InputDecoration(labelText: 'Áudio', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'Dublado', child: Text('Dublado')),
                          DropdownMenuItem(value: 'Dual Áudio', child: Text('Dual Áudio')),
                          DropdownMenuItem(value: 'Legendado', child: Text('Legendado')),
                        ],
                        onChanged: (v) => setDialog(() => audio = v ?? 'Dublado'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: capaCtrl, decoration: const InputDecoration(labelText: 'URL da Capa (Pôster)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: bannerCtrl, decoration: const InputDecoration(labelText: 'URL do Banner (Horizontal)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: generoCtrl, decoration: const InputDecoration(labelText: 'Gêneros', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: sinopseCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Sinopse', border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              onPressed: () async {
                if (tituloCtrl.text.trim().isEmpty || urlCtrl.text.trim().isEmpty) return;
                try { await _sb.inserirMidia({
                  'titulo': tituloCtrl.text.trim(),
                  'categoria': categoria,
                  'url_stream': urlCtrl.text.trim(),
                  'url_stream_backup': backupCtrl.text.trim(),
                  'capa_url': capaCtrl.text.trim(),
                  'banner_url': bannerCtrl.text.trim(),
                  'genero': generoCtrl.text.trim(),
                  'sinopse': sinopseCtrl.text.trim(),
                  'ano': int.tryParse(anoCtrl.text) ?? 2026,
                  'resolucao': resolucao,
                  'tipo_audio': audio,
                  'aprovado': true,
                  'link_ativo': true,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _atualizarCatalogo(); } catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red)); } }
              },
              child: const Text('Publicar Agora'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = _catalogo.where((e) => !e.aprovado).toList();
    final aprovados = _catalogo.where((e) => e.aprovado).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('RoboScrap 3.5 • Painel Admin'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _atualizarCatalogo),
        ],
      ),
      floatingActionButton: _abaAtual == 0 && _serviceKey.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              onPressed: _dialogAdicionarMidia,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar Mídia', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : IndexedStack(
              index: _abaAtual,
              children: [
                _listaItens(aprovados, vazio: 'Nenhum título publicado ainda. Toque em "+ Adicionar Mídia".'),
                _listaItens(pendentes, vazio: 'Nenhum item pendente na fila de curadoria.', isCuradoria: true),
                VitrineScreen(supabase: _sb),
                _telaConfig(),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _abaAtual,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.amber,
        onTap: (i) => setState(() => _abaAtual = i),
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.movie), label: 'Publicados (${aprovados.length})'),
          BottomNavigationBarItem(icon: const Icon(Icons.fact_check), label: 'Curadoria (${pendentes.length})'),
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_customize), label: 'Vitrine & Hero'),
          const BottomNavigationBarItem(icon: Icon(Icons.vpn_key), label: 'Chaves'),
        ],
      ),
    );
  }

  Widget _listaItens(List<CatalogoItem> lista, {required String vazio, bool isCuradoria = false}) {
    if (lista.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(vazio, textAlign: TextAlign.center)));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: lista.length,
      itemBuilder: (context, i) {
        final item = lista[i];
        return Card(
          child: ListTile(
            leading: item.capaUrl.isNotEmpty
                ? Image.network(item.capaUrl, width: 42, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie))
                : const Icon(Icons.movie),
            title: Text(item.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${item.categoria} • ${item.resolucao} • ${item.tipoAudio}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCuradoria)
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                    onPressed: () async {
                      await _sb.atualizarStatus(item.id, aprovado: true, linkAtivo: true);
                      _atualizarCatalogo(); } catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red)); } }
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await _sb.excluirMidia(item.id);
                    _atualizarCatalogo(); } catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red)); } }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _telaConfig() {
    final urlCtrl = TextEditingController(text: _supabaseUrl);
    final keyCtrl = TextEditingController(text: _serviceKey);
    final tmdbCtrl = TextEditingController(text: _tmdbKey);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Credenciais Administrativas (Supabase & TMDB)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'Supabase URL', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(
          controller: keyCtrl,
          decoration: const InputDecoration(labelText: 'Supabase Secret / service_role Key', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: tmdbCtrl,
          decoration: const InputDecoration(labelText: 'TMDB API Key (para puxar capas e sinopses)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('admin_sb_url', urlCtrl.text.trim());
            await prefs.setString('admin_sb_key', keyCtrl.text.trim());
            await prefs.setString('admin_tmdb_key', tmdbCtrl.text.trim());
            await _carregarConfig();
            if (mounted) {
              setState(() => _abaAtual = 0);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chaves salvas!'), backgroundColor: Colors.green));
            }
          },
          icon: const Icon(Icons.save),
          label: const Text('Salvar e Conectar', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
