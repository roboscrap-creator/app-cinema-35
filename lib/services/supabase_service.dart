import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/midia_model.dart';

class SupabaseService {
  static const String baseUrl = 'https://kuziampmbltqdqkqyrlb.supabase.co';
  static const String anonKey = '';

  static Map<String, String> get _headers => {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
      };

  static Future<List<ObraAgrupada>> carregarCatalogoAgrupado() async {
    final uri = Uri.parse(
      '$baseUrl/rest/v1/catalogo_midia?select=*&aprovado=eq.true&link_ativo=eq.true&order=ordem_destaque.asc,criado_em.desc&limit=1000',
    );
    final resp = await http.get(uri, headers: _headers);
    if (resp.statusCode != 200) throw Exception('Erro (${resp.statusCode})');

    final List<dynamic> dados = jsonDecode(utf8.decode(resp.bodyBytes));
    final Map<String, List<Map<String, dynamic>>> grupos = {};

    for (final item in dados) {
      if (item is! Map<String, dynamic>) continue;
      if ((item['url_stream'] ?? '').toString().trim().isEmpty) continue;
      final cat = (item['categoria'] ?? 'Filme').toString().trim();
      final tmdb = item['tmdb_id'];
      final tituloBase = ((cat == 'Série' && (item['serie_nome'] ?? '').toString().trim().isNotEmpty)
              ? item['serie_nome']
              : item['titulo'] ?? 'Sem Título')
          .toString()
          .trim();
      final chave = (tmdb != null && tmdb.toString().isNotEmpty)
          ? '${cat}_tmdb_$tmdb'
          : '${cat}_${tituloBase.toLowerCase()}';
      grupos.putIfAbsent(chave, () => []).add(item);
    }

    final List<ObraAgrupada> obras = [];
    grupos.forEach((chave, lista) {
      lista.sort((a, b) => ((b['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0)
          .compareTo((a['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0));
      final p = lista.first;
      final cat = (p['categoria'] ?? 'Filme').toString();
      final titulo = ((cat == 'Série' && (p['serie_nome'] ?? '').toString().trim().isNotEmpty)
              ? p['serie_nome']
              : p['titulo'] ?? 'Sem Título')
          .toString()
          .trim();
      final fontes = lista.map((e) => FonteMidia.fromJson(e)).toList();
      fontes.sort((a, b) {
        int peso(String r) {
          final up = r.toUpperCase();
          if (up.contains('4K') || up.contains('2160')) return 4;
          if (up.contains('1080')) return 3;
          if (up.contains('720')) return 2;
          return 1;
        }
        final c = peso(b.resolucao).compareTo(peso(a.resolucao));
        return c != 0 ? c : a.tipoAudio.compareTo(b.tipoAudio);
      });

      obras.add(ObraAgrupada(
        chaveGrupo: chave,
        tmdbId: p['tmdb_id'] is int ? p['tmdb_id'] : int.tryParse('${p['tmdb_id'] ?? ''}'),
        titulo: titulo,
        categoria: cat,
        genero: (p['genero'] ?? 'Variados').toString(),
        sinopse: (p['sinopse'] ?? 'Sinopse não disponível.').toString(),
        capaUrl: (p['capa_url'] ?? '').toString(),
        bannerUrl: (p['banner_url'] ?? '').toString(),
        ano: (p['ano'] ?? '').toString(),
        emDestaque: p['em_destaque'] == true,
        ordemDestaque: p['ordem_destaque'] is int ? p['ordem_destaque'] : 999,
        fontes: fontes,
      ));
    });
    return obras;
  }

  static Future<void> registrarVisualizacao(String id) async {
    if (id.isEmpty) return;
    try {
      await http.post(
        Uri.parse('$baseUrl/rest/v1/rpc/incrementar_visualizacao'),
        headers: _headers,
        body: jsonEncode({'midia_id': id}),
      );
    } catch (_) {}
  }
}
