import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'models/midia_model.dart';
import 'services/supabase_service.dart';
import 'screens/player_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppCinema());
}

class AppCinema extends StatelessWidget {
  const AppCinema({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Cinema 3.5',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        primaryColor: const Color(0xFFE50914),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          secondary: Colors.amberAccent,
          surface: Color(0xFF14161D),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B0C10), elevation: 0),
      ),
      home: const HomeCinemaScreen(),
    );
  }
}

class HomeCinemaScreen extends StatefulWidget {
  const HomeCinemaScreen({super.key});

  @override
  State<HomeCinemaScreen> createState() => _HomeCinemaScreenState();
}

class _HomeCinemaScreenState extends State<HomeCinemaScreen> {
  List<ObraAgrupada> _catalogo = [];
  bool _carregando = true;
  String? _erro;
  int _abaAtual = 0;
  String _busca = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await SupabaseService.carregarCatalogoAgrupado();
      if (!mounted) return;
      setState(() {
        _catalogo = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  List<ObraAgrupada> get _filtrados {
    return _catalogo.where((o) {
      if (_abaAtual == 1 && o.categoria != 'Filme') return false;
      if (_abaAtual == 2 && o.categoria != 'Série') return false;
      if (_abaAtual == 3 && o.categoria != 'TV ao Vivo') return false;
      if (_busca.trim().isNotEmpty) {
        final q = _busca.toLowerCase();
        return o.titulo.toLowerCase().contains(q) || o.genero.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  void _abrirDetalhes(ObraAgrupada obra) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DetalhesObraScreen(obra: obra)));
  }

  @override
  Widget build(BuildContext context) {
    final destaques = _catalogo.where((o) => o.emDestaque).toList();
    final hero = destaques.isNotEmpty ? destaques.first : (_catalogo.isNotEmpty ? _catalogo.first : null);
    final filmes = _catalogo.where((o) => o.categoria == 'Filme').toList();
    final series = _catalogo.where((o) => o.categoria == 'Série').toList();
    final canais = _catalogo.where((o) => o.categoria == 'TV ao Vivo').toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(6)),
              child: const Text('3.5', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            const Text('Cimema', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _busca = v),
              decoration: InputDecoration(
                hintText: 'Buscar filmes, séries, canais ou gêneros...',
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _busca.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _busca = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF161922),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
                : _erro != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_erro!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _carregar, child: const Text('Recarregar')),
                          ],
                        ),
                      )
                    : _busca.isNotEmpty || _abaAtual != 0
                        ? _buildGrade(_filtrados)
                        : RefreshIndicator(
                            onRefresh: _carregar,
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 24),
                              children: [
                                if (hero != null) _buildBannerHero(hero),
                                if (destaques.isNotEmpty) _buildCarrossel('Em Destaque na Vitrine', destaques),
                                if (filmes.isNotEmpty) _buildCarrossel('Filmes Recentes (${filmes.length})', filmes),
                                if (series.isNotEmpty) _buildCarrossel('Séries (${series.length})', series),
                                if (canais.isNotEmpty) _buildCarrossel('TV ao Vivo (${canais.length})', canais),
                              ],
                            ),
                          ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF11131A),
        selectedIndex: _abaAtual,
        indicatorColor: const Color(0xFFE50914).withOpacity(0.25),
        onDestinationSelected: (idx) => setState(() => _abaAtual = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.movie_outlined), selectedIcon: Icon(Icons.movie), label: 'Filmes'),
          NavigationDestination(icon: Icon(Icons.tv_outlined), selectedIcon: Icon(Icons.tv), label: 'Séries'),
          NavigationDestination(icon: Icon(Icons.live_tv_outlined), selectedIcon: Icon(Icons.live_tv), label: 'TV ao Vivo'),
        ],
      ),
    );
  }

  Widget _buildBannerHero(ObraAgrupada obra) {
    final img = obra.bannerUrl.isNotEmpty ? obra.bannerUrl : obra.capaUrl;
    return GestureDetector(
      onTap: () => _abrirDetalhes(obra),
      child: Container(
        height: 230,
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: const Color(0xFF1A1D26)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (img.isNotEmpty)
              CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 64, color: Colors.white24),
              ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87, Colors.black],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(4)),
                        child: Text(obra.categoria.toUpperCase(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Text('${obra.audiosDisponiveis.join(" / ")} • ${obra.resolucoesDisponiveis.first}',
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(obra.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => PlayerScreen(obra: obra, fonteInicial: obra.fontes.first)),
                          );
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Assistir Agora', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        onPressed: () => _abrirDetalhes(obra),
                        icon: const Icon(Icons.tune, size: 18),
                        label: Text(obra.fontes.length > 1 ? '${obra.fontes.length} opções' : 'Detalhes'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarrossel(String titulo, List<ObraAgrupada> itens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Text(titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 215,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: itens.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, idx) => SizedBox(width: 124, child: _buildCardObra(itens[idx])),
          ),
        ),
      ],
    );
  }

  Widget _buildGrade(List<ObraAgrupada> itens) {
    if (itens.isEmpty) return const Center(child: Text('Nenhum título encontrado.'));
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.56,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: itens.length,
      itemBuilder: (_, idx) => _buildCardObra(itens[idx]),
    );
  }

  Widget _buildCardObra(ObraAgrupada obra) {
    return GestureDetector(
      onTap: () => _abrirDetalhes(obra),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: obra.capaUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: obra.capaUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: const Color(0xFF1A1D26)),
                          errorWidget: (_, __, ___) =>
                              Container(color: const Color(0xFF1A1D26), child: const Icon(Icons.movie, color: Colors.white24)),
                        )
                      : Container(color: const Color(0xFF1A1D26), child: const Icon(Icons.movie, color: Colors.white24)),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                    child: Text(obra.resolucoesDisponiveis.first,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                  ),
                ),
                if (obra.audiosDisponiveis.length > 1)
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(4)),
                      child: const Text('DUAL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Text(obra.titulo,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text(obra.audiosDisponiveis.join(' • '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ],
      ),
    );
  }
}

class DetalhesObraScreen extends StatefulWidget {
  final ObraAgrupada obra;
  const DetalhesObraScreen({super.key, required this.obra});

  @override
  State<DetalhesObraScreen> createState() => _DetalhesObraScreenState();
}

class _DetalhesObraScreenState extends State<DetalhesObraScreen> {
  int _temporadaSelecionada = 1;

  @override
  void initState() {
    super.initState();
    if (widget.obra.temporadasDisponiveis.isNotEmpty) {
      _temporadaSelecionada = widget.obra.temporadasDisponiveis.first;
    }
  }

  void _reproduzir(FonteMidia fonte) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(obra: widget.obra, fonteInicial: fonte)));
  }

  @override
  Widget build(BuildContext context) {
    final obra = widget.obra;
    final banner = obra.bannerUrl.isNotEmpty ? obra.bannerUrl : obra.capaUrl;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(obra.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (banner.isNotEmpty) CachedNetworkImage(imageUrl: banner, fit: BoxFit.cover),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black26, Color(0xFF0B0C10)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Chip(label: Text(obra.categoria), backgroundColor: const Color(0xFFE50914)),
                    const SizedBox(width: 8),
                    if (obra.ano.isNotEmpty) Chip(label: Text(obra.ano), backgroundColor: const Color(0xFF1A1D26)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(obra.genero,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(obra.sinopse, style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 14)),
                const SizedBox(height: 20),
                if (obra.categoria != 'Série') ...[
                  const Text('Escolha o Áudio e a Qualidade para Assistir:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ...obra.fontes.map(
                    (f) => Card(
                      color: const Color(0xFF161922),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE50914),
                          child: Icon(Icons.play_arrow, color: Colors.white),
                        ),
                        title: Text('${f.tipoAudio} • ${f.resolucao}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Stream ${f.formato.toUpperCase()} • Idiomas: ${f.idiomasAudio.join(", ")}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _reproduzir(f),
                      ),
                    ),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Episódios', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      DropdownButton<int>(
                        value: _temporadaSelecionada,
                        dropdownColor: const Color(0xFF161922),
                        items: obra.temporadasDisponiveis
                            .map((t) => DropdownMenuItem(value: t, child: Text('Temporada $t')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _temporadaSelecionada = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...obra.episodiosDaTemporada(_temporadaSelecionada).map(
                        (ep) => Card(
                          color: const Color(0xFF161922),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF232836),
                              child: Text('${ep.episodio ?? 1}',
                                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(
                              ep.etiquetaEpisodio.isNotEmpty ? '${ep.etiquetaEpisodio} - ${ep.titulo}' : ep.titulo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(ep.badgeResumo, style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                            trailing: const Icon(Icons.play_circle_fill, color: Color(0xFFE50914), size: 30),
                            onTap: () => _reproduzir(ep),
                          ),
                        ),
                      ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
