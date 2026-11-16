import 'dart:async';
import 'package:flutter/material.dart';
import '../models/midia_model.dart';

class AbaCategoriaPage extends StatefulWidget {
  final String nomeAba;
  final List obras;
  final Function(ObraAgrupada) onAbrirObra;
  const AbaCategoriaPage({super.key, required this.nomeAba, required this.obras, required this.onAbrirObra});
  @override
  State createState() => _AbaCategoriaPageState();
}

class _AbaCategoriaPageState extends State {
  final PageController _pageCtrl = PageController();
  int _bannerAtual = 0;
  Timer? _timer;
  List get _obras => (widget as AbaCategoriaPage).obras;
  List get _banners {
    final l = _obras.where((O) => O.bannerUrl.isNotEmpty || O.capaUrl.isNotEmpty).toList();
    final d = l.where((O) => O.emDestaque).toList();
    return (d.isNotEmpty ? d : l).take(5).toList();
  }
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_banners.length > 1 && _pageCtrl.hasClients) {
        _pageCtrl.animateToPage((_bannerAtual + 1) % _banners.length, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      }
    });
  }
  @override
  void dispose() { _timer?.cancel(); _pageCtrl.dispose(); super.dispose(); }
  Widget _buildBanner() {
    final b = _banners;
    if (b.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 215,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: b.length,
            onPageChanged: (i) => setState(() => _bannerAtual = i),
            itemBuilder: (_, i) {
              final ObraAgrupada o = b[i];
              final img = o.bannerUrl.isNotEmpty ? o.bannerUrl : o.capaUrl;
              return GestureDetector(
                onTap: () => (widget as AbaCategoriaPage).onAbrirObra(o),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1C1E2E))),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 80,
                      bottom: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          if (o.genero.isNotEmpty || o.ano.isNotEmpty)
                            Text('${o.ano} (${(o.categoria)})', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            right: 14,
            bottom: 16,
            child: Row(
              children: List.generate(b.length, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _bannerAtual == i ? 16 : 7,
                height: 7,
                decoration: BoxDecoration(color: _bannerAtual == i ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(4)),
              )),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildFileira(String titulo, List itens) {
    if (itens.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, right: 14, top: 18, bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              const Icon(Icons.chevron_right, color: Colors.white70, size: 22),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: itens.length,
            itemBuilder: (_, i) {
              final ObraAgrupada o = itens[i];
              return GestureDetector(
                onTap: () => (widget as AbaCategoriaPage).onAbrirObra(o),
                child: Container(
                  width: 114,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: const Color(0xFF1C1E2E)),
                  clipBehavior: Clip.antiAlias,
                  child: o.capaUrl.isNotEmpty
                      ? Image.network(o.capaUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(o.titulo, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11))))
                      : Center(child: Text(o.titulo, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = _obras;
    if (l.isEmpty) {
      return Center(child: Text('Nenhum conteúdo em ${(widget as AbaCategoriaPage).nomeAba}', style: const TextStyle(color: Colors.white54)));
    }
    final lancamentos = l.take(15).toList();
    final destaques = l.where((o) => o.emDestaque).toList();
    final populares = l.skip(5).take(20).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _buildBanner(),
        _buildFileira('Lançamentos', lancamentos),
        if (destaques.isNotEmpty) _buildFileira('Em Alta', destaques),
        if (populares.isNotEmpty) _buildFileira('Mais Assistidos', populares),
        _buildFileira('Todos em ' + (widget as AbaCategoriaPage).nomeAba, l.take(30).toList()),
      ],
    );
  }
}
