import 'package:flutter/material.dart';
import '../models/midia_model.dart';
import 'player_screen.dart';

class DetalheObraScreen extends StatefulWidget {
  final ObraAgrupada obra;
  const DetalheObraScreen({super.key, required this.obra});

  @override
  State<DetalheObraScreen> createState() => _DetalheObraScreenState();
}

class _DetalheObraScreenState extends State<DetalheObraScreen> {
  late int _tempAtual;

  @override
  void initState() {
    super.initState();
    final temps = widget.obra.temporadasDisponiveis;
    _tempAtual = temps.isNotEmpty ? temps.first : 1;
  }

  void _play(FonteMidia fonte) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(obra: widget.obra, fonteInicial: fonte)));
  }

  List<FonteMidia> _episodiosUnicos(List<FonteMidia> brutos) {
    final Map<int, FonteMidia> porNumero = {};
    for (final f in brutos) {
      final epNum = f.episodio ?? (porNumero.length + 1);
      porNumero.putIfAbsent(epNum, () => f);
    }
    final keys = porNumero.keys.toList()..sort();
    return keys.map((k) => porNumero[k]!).toList();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.obra;
    final isSerie = o.chaveGrupo.startsWith('serie_') ||
        o.categoria.toLowerCase().contains('série') ||
        o.categoria.toLowerCase().contains('serie') ||
        o.fontes.any((f) => f.episodio != null);
    final temps = o.temporadasDisponiveis;
    final epsBrutos = isSerie ? o.episodiosDaTemporada(_tempAtual) : o.fontes;
    final eps = isSerie ? _episodiosUnicos(epsBrutos) : epsBrutos;
    final img = o.bannerUrl.isNotEmpty ? o.bannerUrl : o.capaUrl;

    return Scaffold(
      appBar: AppBar(title: Text(o.titulo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (img.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(img, height: 210, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          const SizedBox(height: 14),
          Text(o.titulo, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text([o.categoria, o.ano, o.genero].where((e) => e.isNotEmpty).join(' • '), style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (o.sinopse.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(o.sinopse, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          if (eps.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: () => _play(eps.first),
              icon: const Icon(Icons.play_arrow),
              label: Text(isSerie ? 'Assistir T$_tempAtual • EP${eps.first.episodio ?? 1}' : 'Assistir Agora'),
            ),
          if (isSerie && temps.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Temporadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: temps.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final t = temps[i];
                  return ChoiceChip(
                    label: Text('Temporada $t'),
                    selected: _tempAtual == t,
                    onSelected: (_) => setState(() => _tempAtual = t),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            isSerie ? 'Temporada $_tempAtual • ${eps.length} Episódios' : 'Opções de Reprodução (${eps.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...eps.map((f) => Card(
                color: const Color(0xFF1A1C26),
                child: ListTile(
                  leading: const Icon(Icons.play_circle_fill, color: Color(0xFF2196F3), size: 32),
                  title: Text(isSerie ? 'Episódio ${f.episodio ?? 1} - ${f.titulo}' : f.titulo),
                  subtitle: Text(f.badgeResumo),
                  onTap: () => _play(f),
                ),
              )),
        ],
      ),
    );
  }
}
