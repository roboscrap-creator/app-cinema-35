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
  int _bannerAtual = 0;
  Timer? _timerBanner;
  Map<String, Map<String, dynamic>> _progressoMap = {};

  static const List<String> _ordemFileirasManuais = [
    'Livestream', 'No Cinema', 'Última Temporada e Episódio', 'Lançamentos de Filmes',
    'Nacional', 'Séries Turcas', 'Doramas', 'Netflix', 'Prime Video', 'MAX',
    'Disney+', 'Paramount+', 'Hulu', 'Apple TV', 'Globoplay', 'Pedidos da Semana',
    'Em breve no Cinema', 'Ação', 'Aventura', 'Drama', 'Comédia', 'Terror',
    'Ficção Científica', 'Romance', 'Suspense',
  ];

  @override
  void initState() {
    super.initState();
    _carregarProgresso();
    _timerBanner = Timer.periodic(const Duration(seconds: 5), (_) {
      final total = _obterDestaquesBanner().length;
      if (total > 1 && _bannerCtrl.hasClients) {
        _bannerCtrl.animateToPage((_bannerAtual + 1) % total, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      }
    });
  }

  Future<void> _carregarProgresso() async {
    final p = await SupabaseService.carregarProgressoAssistido();
    if (mounted) setState(() => _progressoMap = p);
  }

  @override
  void dispose() { _timerBanner?.cancel(); _bannerCtrl.dispose(); super.dispose(); }

  List<ObraAgrupada> _obterDestaquesBanner() {
    final marcados = widget.obras.where((o) => o.tags.any((t) => t.toLowerCase() == 'banner principal') || o.emDestaque).toList();
    if (marcados.isNotEmpty) return marcados.take(4).toList();
    return widget.obras.where((o) => o.bannerUrl.isNotEmpty || o.capaUrl.isNotEmpty).take(4).toList();
  }

  List<ObraAgrupada> _filtrarPorTagOuGenero(String nomeSecao) {
    final alvo = nomeSecao.toLowerCase().trim();
    if (alvo.contains('em breve')) return widget.obras.where((o) => o.tags.any((t) => t.toLowerCase().contains('em breve'))).toList();
    if (alvo == 'livestream') return widget.obras.where((o) => o.tags.any((t) => t.toLowerCase() == 'livestream') || o.categoria.toLowerCase().contains('tv')).toList();
    return widget.obras.where((o) => o.tags.any((t) => t.toLowerCase().trim() == alvo) || o.genero.toLowerCase().contains(alvo)).toList();
  }

  void _abrirComProgresso(ObraAgrupada obra) async {
    await SupabaseService.salvarProgressoAssistido(chaveGrupo: obra.chaveGrupo, progresso: 0.35, etiquetaEp: obra.badgePoster);
    widget.onAbrirObra(obra);
    _carregarProgresso();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nomeAba != 'Recomendações') {
      if (widget.obras.isEmpty) return const Center(child: Text('Nenhum conteúdo nesta aba ainda.', style: TextStyle(color: Colors.white54)));
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.56, crossAxisSpacing: 10, mainAxisSpacing: 12),
        itemCount: widget.obras.length,
        itemBuilder: (_, i) => _buildCardPoster(widget.obras[i]),
      );
    }

    final banners = _obterDestaquesBanner();
    final continuarLista = widget.obras.where((o) => _progressoMap.containsKey(o.chaveGrupo)).toList()
      ..sort((a, b) => ((_progressoMap[b.chaveGrupo]?['ts'] ?? 0) as int).compareTo((_progressoMap[a.chaveGrupo]?['ts'] ?? 0) as int));
    final filmesEmAlta = widget.obras.where((o) => o.categoria.toLowerCase().contains('filme')).toList()
      ..sort((a, b) => b.scorePopularidade.compareTo(a.scorePopularidade));
    final seriesMaisAssistidas = widget.obras.where((o) => o.categoria.toLowerCase().contains('série') || o.categoria.toLowerCase().contains('serie')).toList()
      ..sort((a, b) => b.scorePopularidade.compareTo(a.scorePopularidade));
    final animesBombando = widget.obras.where((o) => o.categoria.toLowerCase().contains('anime') || o.genero.toLowerCase().contains('anime') || o.tags.any((t) => t.toLowerCase() == 'anime')).toList()
      ..sort((a, b) => b.scorePopularidade.compareTo(a.scorePopularidade));

    final Set<String> extras = {};
    for (final o in widget.obras) {
      for (final t in o.tags) {
        final l = t.toLowerCase();
        if (l == 'banner principal' || l == 'em breve' || l == 'anime') continue;
        if (!_ordemFileirasManuais.any((p) => p.toLowerCase() == l)) extras.add(t);
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (banners.isNotEmpty) _buildBannerPrincipal(banners),
        if (_filtrarPorTagOuGenero('Livestream').isNotEmpty) _buildFileiraHorizontal(titulo: 'Livestream', itens: _filtrarPorTagOuGenero('Livestream'), isLivestream: true),
        if (continuarLista.isNotEmpty) _buildFileiraHorizontal(titulo: 'Continuar Assistindo', itens: continuarLista, mostrarProgresso: true),
        if (filmesEmAlta.isNotEmpty) _buildFileiraHorizontal(titulo: 'Filmes em Alta', itens: filmesEmAlta),
        if (seriesMaisAssistidas.isNotEmpty) _buildFileiraHorizontal(titulo: 'Séries Mais Assistidas', itens: seriesMaisAssistidas),
        if (animesBombando.isNotEmpty) _buildFileiraHorizontal(titulo: 'Animes Bombando', itens: animesBombando),
        ...[..._ordemFileirasManuais, ...extras].where((s) => s != 'Livestream').map((secao) {
          final itens = _filtrarPorTagOuGenero(secao);
          return itens.isEmpty ? const SizedBox.shrink() : _buildFileiraHorizontal(titulo: secao, itens: itens);
        }),
      ],
    );
  }

  Widget _buildBannerPrincipal(List<ObraAgrupada> banners) {
    return SizedBox(
      height: 215,
      child: Stack(children: [
        PageView.builder(
          controller: _bannerCtrl,
          itemCount: banners.length,
          onPageChanged: (i) => setState(() => _bannerAtual = i),
          itemBuilder: (_, i) {
            final obra = banners[i];
            final img = obra.bannerUrl.isNotEmpty ? obra.bannerUrl : obra.capaUrl;
            return GestureDetector(
              onTap: () => _abrirComProgresso(obra),
              child: Stack(fit: StackFit.expand, children: [
                if (img.isNotEmpty) Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1A1C24))),
                Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87], stops: [0.45, 1.0]))),
                Positioned(left: 16, bottom: 18, right: 85, child: Text(obra.titulo.toUpperCase(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white))),
              ]),
            );
          },
        ),
        Positioned(right: 14, bottom: 16, child: Row(children: List.generate(banners.length, (idx) => Container(margin: const EdgeInsets.symmetric(horizontal: 3), width: idx == _bannerAtual ? 9 : 7, height: idx == _bannerAtual ? 9 : 7, decoration: BoxDecoration(shape: BoxShape.circle, color: idx == _bannerAtual ? Colors.white : Colors.white38))))),
      ]),
    );
  }

  Widget _buildFileiraHorizontal({required String titulo, required List<ObraAgrupada> itens, bool isLivestream = false, bool mostrarProgresso = false}) {
    final top10 = itens.take(10).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
          backgroundColor: const Color(0xFF0B0C10),
          appBar: AppBar(backgroundColor: const Color(0xFF0B0C10), title: Text('$titulo (${itens.length})')),
          body: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.56, crossAxisSpacing: 10, mainAxisSpacing: 12),
            itemCount: itens.length,
            itemBuilder: (_, i) => _buildCardPoster(itens[i]),
          ),
        ))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
          child: Row(children: [
            Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            if (isLivestream) ...[const SizedBox(width: 8), const Icon(Icons.equalizer, color: Color(0xFFF5B82E), size: 18)],
            const Spacer(),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 22),
          ]),
        ),
      ),
      SizedBox(
        height: isLivestream ? 132 : 205,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          scrollDirection: Axis.horizontal,
          itemCount: top10.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => isLivestream ? _buildCardLivestream(top10[i]) : _buildCardPoster(top10[i], mostrarProgresso: mostrarProgresso),
        ),
      ),
    ]);
  }

  Widget _buildCardLivestream(ObraAgrupada obra) {
    final img = obra.bannerUrl.isNotEmpty ? obra.bannerUrl : obra.capaUrl;
    return GestureDetector(
      onTap: () => _abrirComProgresso(obra),
      child: SizedBox(width: 175, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(height: 100, width: 175, child: img.isNotEmpty ? Image.network(img, fit: BoxFit.cover) : Container(color: const Color(0xFF1E202B)))),
        const SizedBox(height: 6),
        Text(obra.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Colors.white)),
      ])),
    );
  }

  Widget _buildCardPoster(ObraAgrupada obra, {bool mostrarProgresso = false}) {
    final progData = _progressoMap[obra.chaveGrupo];
    final double progVal = (progData?['progresso'] is num) ? (progData!['progresso'] as num).toDouble() : 0.0;
    final String badge = (progData?['etiqueta']?.toString().isNotEmpty == true) ? progData!['etiqueta'].toString() : obra.badgePoster;
    return GestureDetector(
      onTap: () => _abrirComProgresso(obra),
      child: SizedBox(width: 112, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(height: 162, width: 112, child: Stack(fit: StackFit.expand, children: [
            if (obra.capaUrl.isNotEmpty) Image.network(obra.capaUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E202B))) else Container(color: const Color(0xFF1E202B)),
            if (badge.isNotEmpty) Positioned(left: 0, right: 0, bottom: mostrarProgresso ? 4 : 0, child: Container(padding: const EdgeInsets.symmetric(vertical: 4), color: Colors.black54, child: Text(badge, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)))),
            if (mostrarProgresso) Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: progVal > 0 ? progVal : 0.35, minHeight: 3, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation<Color>(Colors.white))),
          ])),
        ),
        const SizedBox(height: 5),
        Text(obra.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Colors.white, height: 1.15)),
      ])),
    );
  }
}
