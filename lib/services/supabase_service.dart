import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/midia_model.dart';

class SupabaseService {
  static const String baseUrl = 'https://kuziampmbltqdqkqyrlb.supabase.co';
  static const String defaultAnonKey = 'sb_publishable_ts3-fnYSelSkjp6GIY8jVw_-ZZTkD_5';
  static List<ObraAgrupada>? _memoriaRapida;

  static Future<String> getAnonKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('cinema_anon_key') ?? '';
    return saved.isNotEmpty ? saved : defaultAnonKey;
  }

  static Future<void> salvarAnonKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cinema_anon_key', key.trim());
  }

  static Future<void> salvarProgressoAssistido({required String chaveGrupo, required double progresso, String? etiquetaEp}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cinema_continuar_assistindo') ?? '{}';
    final Map<String, dynamic> mapa = jsonDecode(raw);
    mapa[chaveGrupo] = {'progresso': progresso.clamp(0.05, 0.98), 'etiqueta': etiquetaEp ?? '', 'ts': DateTime.now().millisecondsSinceEpoch};
    await prefs.setString('cinema_continuar_assistindo', jsonEncode(mapa));
  }

  static Future>> carregarProgressoAssistido() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cinema_continuar_assistindo') ?? '{}';
    final Map<String, dynamic> decoded = jsonDecode(raw);
    final Map<String, Map<String, dynamic>> out = {};
    decoded.forEach((k, v) { if (v is Map) out[k] = Map<String, dynamic>.from(v); });
    return out;
  }

  static String? _extrairLogoM3u(String texto) {
    final m = RegExp(r'tvg-logo\s*=\s*"([^"]+)"', caseSensitive: false).firstMatch(texto);
    return (m != null && m.group(1)!.startsWith('http')) ? m.group(1)!.trim() : null;
  }

  static String _limparExtinf(String texto) {
    var s = texto.trim();
    if (s.toUpperCase().startsWith('#EXTINF')) {
      final cut = s.lastIndexOf('"') > s.lastIndexOf(',') ? s.lastIndexOf('"') : s.lastIndexOf(',');
      if (cut != -1 && cut + 1 < s.length) s = s.substring(cut + 1).trim();
    }
    return s;
  }

  static Map<String, int>? _extrairTempEp(String titulo) {
    for (final rx in [
      RegExp(r'(?:S|T)\s*(\d{1,2})\s*[\|\-:\.\s]*E(?:P)?\s*(\d{1,3})', caseSensitive: false),
      RegExp(r'(\d{1,2})\s*[xX]\s*(\d{1,3})'),
      RegExp(r'TEMPORADA\s*(\d{1,2}).*?EP(?:IS[OÓ]DIO)?\s*(\d{1,3})', caseSensitive: false),
    ]) {
      final m = rx.firstMatch(titulo);
      if (m != null) return {'t': int.parse(m.group(1)!), 'e': int.parse(m.group(2)!)};
    }
    final epOnly = RegExp(r'(?:^|[\s\|\-\[\(])EP(?:IS[OÓ]DIO)?\s*0*(\d{1,3})(?:$|[\s\|\-\]\)])', caseSensitive: false).firstMatch(titulo);
    if (epOnly != null) return {'t': 1, 'e': int.parse(epOnly.group(1)!)};
    return null;
  }

  static String _limparNomeObra(String titulo) {
    var s = _limparExtinf(titulo)
        .replaceAll(RegExp(r'[\|\-\[\(]?\s*(?:S|T)\s*\d{1,2}\s*[\|\-:\.\s]*E(?:P)?\s*\d{1,3}.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\|\-\[\(]?\s*\d{1,2}\s*[xX]\s*\d{1,3}.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\|\-\[\(]?\s*TEMPORADA\s*\d{1,2}.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\|\-\[\(]?\s*EP(?:IS[OÓ]DIO)?\s*\d{1,3}.*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[\(\[]?(?:dublado|legendado|dual|nacional|hd|fhd|4k|1080p|720p)[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\|\-:\s]+$'), '').trim();
    return s.isEmpty ? _limparExtinf(titulo) : s;
  }

  static String _normalizarChave(String texto) => _limparNomeObra(texto).toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a').replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i').replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u').replaceAll('ç', 'c').replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _normalizarUrlImagem(String url) {
    var u = url.trim();
    if (u.startsWith('http://image.tmdb.org') || u.startsWith('http://i.imgur.com')) u = u.replaceFirst('http://', 'https://');
    return u;
  }

  static bool _urlEstaAtiva(String url) {
    final u = url.toLowerCase();
    for (final m in ['staniptv', 'ntcdn.us', 'vstreaming.net', 'popfilmeshd.net', 'themediafire.club', 'cdnv12.ec.cx', 'cdnv18.ec.cx', '0.0.0.0', 'lh3.googleusercontent.com', 'dailymotion.com/sec(']) {
      if (u.contains(m)) return false;
    }
    return true;
  }

  static List<ObraAgrupada> _agruparDados(List<dynamic> dados) {
    final Map<String, List<Map<String, dynamic>>> grupos = {};
    final Set<String> idsVistos = {};
    for (final item in dados) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = (map['id'] ?? '').toString();
      if (id.isNotEmpty && !idsVistos.add(id)) continue;
      final url = (map['url_stream'] ?? '').toString().trim();
      if (url.isEmpty || !_urlEstaAtiva(url)) continue;

      final tituloBruto = (map['titulo'] ?? 'Sem Título').toString().trim();
      var capa = _normalizarUrlImagem((map['capa_url'] ?? '').toString());
      if (capa.isEmpty) { final logo = _extrairLogoM3u(tituloBruto); if (logo != null) capa = _normalizarUrlImagem(logo); }
      map['capa_url'] = capa;
      map['banner_url'] = _normalizarUrlImagem((map['banner_url'] ?? '').toString());
      final tituloLimpo = _limparExtinf(tituloBruto);
      map['titulo'] = tituloLimpo;

      final te = _extrairTempEp(tituloLimpo);
      final catOrig = (map['categoria'] ?? 'Filme').toString().trim();
      final isSerie = te != null || map['episodio'] != null || catOrig.toLowerCase().contains('série') || catOrig.toLowerCase().contains('serie');
      if (te != null) { map['temporada'] = te['t']; map['episodio'] = te['e']; }
      if (isSerie && !catOrig.toLowerCase().contains('anime') && !catOrig.toLowerCase().contains('infantil')) map['categoria'] = 'Série';

      final serieNome = (map['serie_nome'] ?? '').toString().trim();
      final norm = _normalizarChave(serieNome.isNotEmpty ? _limparNomeObra(serieNome) : _limparNomeObra(tituloLimpo));
      grupos.putIfAbsent(isSerie ? 'serie_$norm' : 'filme_$norm', () => []).add(map);
    }

    final List<ObraAgrupada> obras = [];
    grupos.forEach((chave, lista) {
      lista.sort((a, b) => ((b['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0).compareTo((a['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0));
      final p = lista.first;
      final isSerie = chave.startsWith('serie_');
      final catOrig = (p['categoria'] ?? 'Filme').toString().trim();
      final cat = isSerie && !catOrig.toLowerCase().contains('anime') && !catOrig.toLowerCase().contains('infantil') ? 'Série' : catOrig;
      final serieNome = (p['serie_nome'] ?? '').toString().trim();
      final tituloFinal = serieNome.isNotEmpty ? _limparNomeObra(serieNome) : _limparNomeObra((p['titulo'] ?? '').toString());

      final Set<String> tagsSet = {};
      int viewsTotal = 0; double maiorNota = 0.0; bool algumDestaque = false; int menorOrdem = 999;
      for (final row in lista) {
        if (row['tags'] is List) { for (final t in (row['tags'] as List)) { if (t != null && t.toString().trim().isNotEmpty) tagsSet.add(t.toString().trim()); } }
        if (row['em_destaque'] == true) { algumDestaque = true; tagsSet.add('Banner Principal'); }
        final ord = row['ordem_destaque'] is int ? row['ordem_destaque'] as int : 999;
        if (ord < menorOrdem) menorOrdem = ord;
        viewsTotal += (row['visualizacoes'] is num) ? (row['visualizacoes'] as num).toInt() : 0;
        final nt = (row['nota_imdb'] is num) ? (row['nota_imdb'] as num).toDouble() : 0.0;
        if (nt > maiorNota) maiorNota = nt;
      }

      obras.add(ObraAgrupada(
        chaveGrupo: chave, tmdbId: p['tmdb_id'] is int ? p['tmdb_id'] : int.tryParse('${p['tmdb_id'] ?? ''}'),
        titulo: tituloFinal, categoria: cat, genero: (p['genero'] ?? '').toString(),
        sinopse: (p['sinopse'] ?? '').toString(), capaUrl: (p['capa_url'] ?? '').toString(),
        bannerUrl: (p['banner_url'] ?? '').toString(), ano: (p['ano'] ?? '').toString(),
        emDestaque: algumDestaque, ordemDestaque: menorOrdem, tags: tagsSet.toList(),
        notaImdb: maiorNota, visualizacoes: viewsTotal,
        fontes: lista.map<FonteMidia>((e) => FonteMidia.fromJson(e)).toList(),
      ));
    });
    obras.sort((a, b) => (a.capaUrl.isNotEmpty ? 0 : 1).compareTo(b.capaUrl.isNotEmpty ? 0 : 1));
    return obras;
  }

  static Future<List<dynamic>> _fetchLote(String key, String filtroQuery, int limite) async {
    const cols = 'id,tmdb_id,titulo,serie_nome,categoria,genero,sinopse,capa_url,banner_url,ano,temporada,episodio,url_stream,url_stream_backup,headers_customizados,formato,tipo_audio,resolucao,em_destaque,ordem_destaque,tags,nota_imdb,visualizacoes';
    const filtroAtivos = '&url_stream=not.ilike.*STANIPTV*&url_stream=not.ilike.*ntcdn.us*&url_stream=not.ilike.*vstreaming.net*&url_stream=not.ilike.*popfilmeshd.net*&url_stream=not.ilike.*themediafire.club*&url_stream=not.ilike.*cdnv12.ec.cx*&url_stream=not.ilike.*cdnv18.ec.cx*&url_stream=not.ilike.*0.0.0.0*&url_stream=not.ilike.*lh3.googleusercontent.com*&url_stream=not.ilike.*dailymotion.com/sec(*';
    final uri = Uri.parse('$baseUrl/rest/v1/catalogo_midia?select=$cols$filtroAtivos$filtroQuery&order=ordem_destaque.asc,criado_em.desc');
    final resp = await http.get(uri, headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Range': '0-${limite - 1}'}).timeout(const Duration(seconds: 12));
    return (resp.statusCode == 200 || resp.statusCode == 206) ? jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic> : [];
  }

  static Future<List<ObraAgrupada>> carregarCatalogoAgrupado({bool forcarRefresh = false}) async {
    if (!forcarRefresh && _memoriaRapida != null && _memoriaRapida!.isNotEmpty) return _memoriaRapida!;
    final key = await getAnonKey();
    final res = await Future.wait([
      _fetchLote(key, '&categoria=ilike.*Filme*', 1200),
      _fetchLote(key, '&categoria=ilike.*S*rie*', 2000),
      _fetchLote(key, '&or=(categoria.ilike.*Anime*,genero.ilike.*Anime*)', 800),
      _fetchLote(key, '&or=(categoria.ilike.*Infantil*,genero.ilike.*Infantil*,genero.ilike.*Anima*)', 800),
      _fetchLote(key, '&categoria=ilike.*TV*', 400),
    ]);
    final combinado = [...res[0], ...res[1], ...res[2], ...res[3], ...res[4]];
    if (combinado.isEmpty) combinado.addAll(await _fetchLote(key, '', 2000));
    _memoriaRapida = _agruparDados(combinado);
    return _memoriaRapida!;
  }

  static Future<void> registrarVisualizacao(String id) async {
    try {
      final key = await getAnonKey();
      await http.post(Uri.parse('$baseUrl/rest/v1/rpc/incrementar_visualizacao'), headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json'}, body: jsonEncode({'media_id': id}));
    } catch (_) {}
  }
}
