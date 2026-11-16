import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/midia_model.dart';

class SupabaseService {
  static const String baseUrl = 'https://kuziampmbltqdqkqyrlb.supabase.co';
  static const String defaultAnonKey = 'sb_publishable_ts3-fnYSelSkjp6GIY8jVw_-ZZTkD_5';

  static Future<String> getAnonKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('cinema_anon_key') ?? '';
    return saved.isNotEmpty ? saved : defaultAnonKey;
  }

  static Future<void> salvarAnonKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cinema_anon_key', key.trim());
  }

  static String _limparNomeSerie(String titulo) {
    return titulo
        .replaceAll(RegExp(r'\s*[\|\-\[\(]?\s*(?:S|T)\d{1,2}\s*[\|\-:\s]*E(?:P)?\d{1,3}.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[\|\-\[\(]?\s*EP(?:IS[OÓ]DIO)?\s*\d{1,3}.*$', caseSensitive: false), '')
        .trim();
  }

  static Future<List<ObraAgrupada>> carregarCatalogoAgrupado() async {
    final key = await getAnonKey();
    final headers = {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json'};
    final List<dynamic> dados = [];
    int offset = 0;
    const int pageSize = 1000;
    while (true) {
      final h = {...headers, 'Range': '$offset-${offset + pageSize - 1}'};
      final uri = Uri.parse('$baseUrl/rest/v1/catalogo_midia?select=*&order=ordem_destaque.asc,criado_em.desc');
      final resp = await http.get(uri, headers: h);
      if (resp.statusCode != 200 && resp.statusCode != 206) throw Exception('Erro (${resp.statusCode})');
      final lote = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      dados.addAll(lote);
      if (lote.length < pageSize) break;
      offset += pageSize;
    }

    final Map<String, List> grupos = {};
    for (final item in dados) {
      if (item is! Map<String, dynamic>) continue;
      if ((item['url_stream'] ?? '').toString().trim().isEmpty) continue;
      final tituloRaw = (item['titulo'] ?? 'Sem Título').toString().trim();
      final isEp = RegExp(r'(?:S|T)\d{1,2}\s*[\|\-:\s]*E(?:P)?\d{1,3}', caseSensitive: false).hasMatch(tituloRaw) || item['episodio'] != null;
      final cat = isEp ? 'Série' : (item['categoria'] ?? 'Filme').toString().trim();
      item['categoria'] = cat;
      final serieNome = (item['serie_nome'] ?? '').toString().trim();
      final tituloBase = serieNome.isNotEmpty ? serieNome : (isEp ? _limparNomeSerie(tituloRaw) : tituloRaw);
      if (item['temporada'] == null || item['episodio'] == null) {
        final m = RegExp(r'(?:S|T)(\d{1,2})\s*[\|\-:\s]*E(?:P)?(\d{1,3})', caseSensitive: false).firstMatch(tituloRaw);
        if (m != null) {
          item['temporada'] ??= int.tryParse(m.group(1)!);
          item['episodio'] ??= int.tryParse(m.group(2)!);
        }
      }
      final tmdb = item['tmdb_id'];
      final chave = (tmdb != null && tmdb.toString().isNotEmpty) ? '${cat}_tmdb_$tmdb' : '${cat}_${tituloBase.toLowerCase()}';
      grupos.putIfAbsent(chave, () => []).add(item);
    }

    final List<ObraAgrupada> obras = [];
    grupos.forEach((chave, lista) {
      lista.sort((a, b) => ((b['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0).compareTo((a['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0));
      final p = lista.first;
      final cat = (p['categoria'] ?? 'Filme').toString().trim();
      final tituloRaw = (p['titulo'] ?? 'Sem Título').toString().trim();
      final serieNome = (p['serie_nome'] ?? '').toString().trim();
      final tituloFinal = serieNome.isNotEmpty ? serieNome : (cat == 'Série' ? _limparNomeSerie(tituloRaw) : tituloRaw);
      obras.add(ObraAgrupada(
        chaveGrupo: chave,
        tmdbId: p['tmdb_id'] is int ? p['tmdb_id'] : int.tryParse('${p['tmdb_id'] ?? ''}'),
        titulo: tituloFinal,
        categoria: cat,
        genero: (p['genero'] ?? '').toString(),
        sinopse: (p['sinopse'] ?? '').toString(),
        capaUrl: (p['capa_url'] ?? '').toString(),
        bannerUrl: (p['banner_url'] ?? '').toString(),
        ano: (p['ano'] ?? '').toString(),
        emDestaque: p['em_destaque'] == true,
        ordemDestaque: p['ordem_destaque'] is int ? p['ordem_destaque'] : 999,
        fontes: lista.map<FonteMidia>((e) => FonteMidia.fromJson(e)).toList(),
      ));
    });
    return obras;
  }

  static Future<void> registrarVisualizacao(String id) async {
    try {
      final key = await getAnonKey();
      await http.post(Uri.parse('$baseUrl/rest/v1/rpc/incrementar_visualizacao'), headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json'}, body: jsonEncode({'media_id': id}));
    } catch (_) {}
  }
}
