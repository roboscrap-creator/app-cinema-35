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

  static String? _extrairLogoM3u(String texto) {
    final m = RegExp(r'tvg-logo\s*=\s*"([^"]+)"', caseSensitive: false).firstMatch(texto);
    if (m != null && m.group(1)!.startsWith('http')) {
      return m.group(1)!.trim();
    }
    return null;
  }

  static String _limparExtinf(String texto) {
    var s = texto.trim();
    if (s.toUpperCase().startsWith('#EXTINF')) {
      final lastQuote = s.lastIndexOf('"');
      final comma = s.lastIndexOf(',');
      final cut = lastQuote > comma ? lastQuote : comma;
      if (cut != -1 && cut + 1 < s.length) {
        s = s.substring(cut + 1).trim();
      }
    }
    return s;
  }

  static Map<String, int>? _extrairTempEp(String titulo) {
    final patterns = [
      RegExp(r'(?:S|T)\s*(\d{1,2})\s*[\|\-:\.\s]*E(?:P)?\s*(\d{1,3})', caseSensitive: false),
      RegExp(r'(\d{1,2})\s*[xX]\s*(\d{1,3})'),
      RegExp(r'TEMPORADA\s*(\d{1,2}).*?EP(?:IS[OÓ]DIO)?\s*(\d{1,3})', caseSensitive: false),
    ];
    for (final rx in patterns) {
      final m = rx.firstMatch(titulo);
      if (m != null) {
        final t = int.tryParse(m.group(1)!);
        final e = int.tryParse(m.group(2)!);
        if (t != null && e != null) return {'t': t, 'e': e};
      }
    }
    final epOnly = RegExp(r'(?:^|[\s\|\-\[\(])EP(?:IS[OÓ]DIO)?\s*0*(\d{1,3})(?:$|[\s\|\-\]\)])', caseSensitive: false).firstMatch(titulo);
    if (epOnly != null) {
      final e = int.tryParse(epOnly.group(1)!);
      if (e != null) return {'t': 1, 'e': e};
    }
    return null;
  }

  static String _limparNomeObra(String titulo) {
    var s = _limparExtinf(titulo)
        .replaceAll(RegExp(r'[\|\-\[\(]?\s*(?:S|T)\s*\d{1,2}\s*[\|\-:\.\s]*E(?:P)?\s*\d{1,3}.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\|\-\[\(]?\s*\d{1,2}\s*[xX]\s*\d{1,3}.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\|\-\[\(]?\s*TEMPORADA\s*\d{1,2}.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\|\-\[\(]?\s*EP(?:IS[OÓ]DIO)?\s*\d{1,3}.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[\(\[](?:dublado|legendado|dual|nacional|hd|fhd|4k|1080p|720p)[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\|\-:\s]+$'), '')
        .trim();
    return s.isEmpty ? _limparExtinf(titulo) : s;
  }

  static String _normalizarChave(String texto) {
    return _limparNomeObra(texto)
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _normalizarUrlImagem(String url) {
    var u = url.trim();
    if (u.startsWith('http://image.tmdb.org') || u.startsWith('http://i.imgur.com') || u.startsWith('http://imgur.com')) {
      u = u.replaceFirst('http://', 'https://');
    }
    return u;
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
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      if ((map['url_stream'] ?? '').toString().trim().isEmpty) continue;

      final tituloBruto = (map['titulo'] ?? 'Sem Título').toString().trim();
      var capa = _normalizarUrlImagem((map['capa_url'] ?? '').toString());
      if (capa.isEmpty) {
        final logoM3u = _extrairLogoM3u(tituloBruto);
        if (logoM3u != null) capa = _normalizarUrlImagem(logoM3u);
      }
      map['capa_url'] = capa;
      map['banner_url'] = _normalizarUrlImagem((map['banner_url'] ?? '').toString());

      final tituloLimpo = _limparExtinf(tituloBruto);
      map['titulo'] = tituloLimpo;

      final te = _extrairTempEp(tituloLimpo);
      final catOrig = (map['categoria'] ?? 'Filme').toString().trim();
      final isSerie = te != null ||
          map['episodio'] != null ||
          catOrig.toLowerCase().contains('série') ||
          catOrig.toLowerCase().contains('serie');

      if (te != null) {
        map['temporada'] = te['t'];
        map['episodio'] = te['e'];
      }
      if (isSerie && !catOrig.toLowerCase().contains('anime') && !catOrig.toLowerCase().contains('infantil')) {
        map['categoria'] = 'Série';
      }

      final serieNome = (map['serie_nome'] ?? '').toString().trim();
      final nomeBase = serieNome.isNotEmpty ? _limparNomeObra(serieNome) : _limparNomeObra(tituloLimpo);
      final norm = _normalizarChave(nomeBase);
      final chave = isSerie ? 'serie_$norm' : 'filme_$norm';
      grupos.putIfAbsent(chave, () => []).add(map);
    }

    final List<ObraAgrupada> obras = [];
    grupos.forEach((chave, lista) {
      final typed = lista.cast();
      typed.sort((a, b) => ((b['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0)
          .compareTo((a['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0));
      final p = Map<String, dynamic>.from(typed.first);
      final isSerie = chave.startsWith('serie_');
      final catOrig = (p['categoria'] ?? 'Filme').toString().trim();
      final cat = isSerie && !catOrig.toLowerCase().contains('anime') && !catOrig.toLowerCase().contains('infantil')
          ? 'Série'
          : catOrig;
      final serieNome = (p['serie_nome'] ?? '').toString().trim();
      final tituloLimpo = (p['titulo'] ?? 'Sem Título').toString().trim();
      final tituloFinal = serieNome.isNotEmpty ? _limparNomeObra(serieNome) : _limparNomeObra(tituloLimpo);

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
        fontes: typed.map<FonteMidia>((e) => FonteMidia.fromJson(Map<String, dynamic>.from(e))).toList(),
      ));
    });

    obras.sort((a, b) {
      final hasA = a.capaUrl.isNotEmpty ? 0 : 1;
      final hasB = b.capaUrl.isNotEmpty ? 0 : 1;
      if (hasA != hasB) return hasA.compareTo(hasB);
      return a.ordemDestaque.compareTo(b.ordemDestaque);
    });
    return obras;
  }

  static Future<void> registrarVisualizacao(String id) async {
    try {
      final key = await getAnonKey();
      await http.post(
        Uri.parse('$baseUrl/rest/v1/rpc/incrementar_visualizacao'),
        headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json'},
        body: jsonEncode({'media_id': id}),
      );
    } catch (_) {}
  }
}
