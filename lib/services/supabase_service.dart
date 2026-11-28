import 'cdn_stream_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/midia_model.dart';

class SupabaseService {
  static const String baseUrl = 'https://kuziampmbltqdqkqyrlb.supabase.co';
  static const String defaultAnonKey =
      'sb_publishable_ts3-fnYSelSkjp6GIY8jVw_-ZZTkD_5';
  static const String tmdbApiKey = String.fromEnvironment('TMDB_API_KEY', defaultValue: '');

  static List<ObraAgrupada>? _memoriaRapida;
  static final Map<String, Map<String, dynamic>> _cacheCreditosTmdb = {};

  static Future<String> getAnonKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('cinema_anon_key') ?? '';
    return saved.isNotEmpty ? saved : defaultAnonKey;
  }

  static Future<void> salvarAnonKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cinema_anon_key', key.trim());
  }

  // =========================================================================
  // PROGRESSO / CONTINUAR ASSISTINDO & HISTÓRICO COMPLETO
  // =========================================================================
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('cinemax_device_id_v1') ?? '';
    if (id.isEmpty) {
      id = 'dev_${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString('cinemax_device_id_v1', id);
    }
    return id;
  }

  static Future<String> _perfilAtualChave() async {
    final prefs = await SharedPreferences.getInstance();
    final dev = await getDeviceId();
    final p = (prefs.getString('cinemax_max_perfil_ativo_v2') ?? 'geral').trim().toLowerCase();
    return '${dev}_${p.isEmpty ? 'geral' : p}';
  }

  static Future<void> salvarProgressoAssistido({
    required String chaveGrupo,
    required double progresso,
    String? etiquetaEp,
    int? posicaoSegundos,
    int? duracaoSegundos,
    String? fonteId,
  }) async {
    final pct = progresso.clamp(0.01, 0.99);
    try {
      final prefs = await SharedPreferences.getInstance();
      final perfil = await _perfilAtualChave();
      final raw = prefs.getString('cinemax_progresso_local_$perfil');
      final Map<String, dynamic> mapa = raw != null && raw.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(raw))
          : {};
      mapa[chaveGrupo] = {
        'progresso': pct,
        'etiqueta': etiquetaEp ?? '',
        'posicao_seg': posicaoSegundos ?? 0,
        'duracao_seg': duracaoSegundos ?? 0,
        'fonte_id': fonteId ?? '',
        'atualizado_em': DateTime.now().toIso8601String(),
      };
      await prefs.setString('cinemax_progresso_local_$perfil', jsonEncode(mapa));
    } catch (_) {}
    try {
      final perfil = await _perfilAtualChave();
      final key = await getAnonKey();
      await http.post(
        Uri.parse('$baseUrl/rest/v1/user_progresso'),
        headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode({
          'perfil': perfil,
          'chave_grupo': chaveGrupo,
          'progresso': pct,
          'etiqueta': etiquetaEp ?? '',
          'atualizado_em': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<Map<String, Map<String, dynamic>>> carregarProgressoAssistido() async {
    final Map<String, Map<String, dynamic>> out = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final perfil = await _perfilAtualChave();
      final raw = prefs.getString('cinemax_progresso_local_$perfil');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is Map) {
              out[k.toString()] = {
                'progresso': (v['progresso'] as num?)?.toDouble() ?? 0.0,
                'etiqueta': (v['etiqueta'] ?? '').toString(),
                'posicao_seg': (v['posicao_seg'] as num?)?.toInt() ?? 0,
                'duracao_seg': (v['duracao_seg'] as num?)?.toInt() ?? 0,
                'fonte_id': (v['fonte_id'] ?? '').toString(),
              };
            }
          });
        }
      }
    } catch (_) {}
    try {
      final perfil = await _perfilAtualChave();
      final key = await getAnonKey();
      final uri = Uri.parse('$baseUrl/rest/v1/user_progresso?perfil=eq.${Uri.encodeComponent(perfil)}&select=chave_grupo,progresso,etiqueta');
      final resp = await http.get(uri, headers: {'apikey': key, 'Authorization': 'Bearer $key'}).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        for (final r in (jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>)) {
          if (r is Map && (r['chave_grupo'] ?? '').toString().isNotEmpty) {
            final cg = r['chave_grupo'].toString();
            final local = out[cg] ?? {};
            final progNuvem = (r['progresso'] as num?)?.toDouble() ?? 0.0;
            final progLocal = (local['progresso'] as num?)?.toDouble() ?? 0.0;
            out[cg] = {
              'progresso': progLocal > 0 ? progLocal : progNuvem,
              'etiqueta': (local['etiqueta'] ?? '').toString().isNotEmpty
                  ? local['etiqueta']
                  : (r['etiqueta'] ?? '').toString(),
              'posicao_seg': local['posicao_seg'] ?? 0,
              'duracao_seg': local['duracao_seg'] ?? 0,
              'fonte_id': local['fonte_id'] ?? '',
            };
          }
        }
      }
    } catch (_) {}
    return out;
  }

  static Future<void> removerDoHistorico(List<String> chaves) async {
    try {
      final perfil = await _perfilAtualChave();
      final key = await getAnonKey();
      for (final c in chaves) {
        await http.delete(
          Uri.parse('$baseUrl/rest/v1/user_progresso?perfil=eq.${Uri.encodeComponent(perfil)}&chave_grupo=eq.${Uri.encodeComponent(c)}'),
          headers: {'apikey': key, 'Authorization': 'Bearer $key'},
        ).timeout(const Duration(seconds: 4));
      }
    } catch (_) {}
  }

  static Future<void> limparTodoHistorico() async {
    try {
      final perfil = await _perfilAtualChave();
      final key = await getAnonKey();
      await http.delete(
        Uri.parse('$baseUrl/rest/v1/user_progresso?perfil=eq.${Uri.encodeComponent(perfil)}'),
        headers: {'apikey': key, 'Authorization': 'Bearer $key'},
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<Set<String>> carregarFavoritos() async {
    final set = <String>{};
    try {
      final perfil = await _perfilAtualChave();
      final key = await getAnonKey();
      final uri = Uri.parse('$baseUrl/rest/v1/user_favoritos?perfil=eq.${Uri.encodeComponent(perfil)}&select=chave_grupo');
      final resp = await http.get(uri, headers: {'apikey': key, 'Authorization': 'Bearer $key'}).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        for (final r in (jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>)) {
          if (r is Map && (r['chave_grupo'] ?? '').toString().isNotEmpty) {
            set.add(r['chave_grupo'].toString());
          }
        }
      }
    } catch (_) {}
    return set;
  }

  static Future<bool> alternarFavorito(String chaveGrupo) async {
    final atuais = await carregarFavoritos();
    final adicionado = !atuais.contains(chaveGrupo);
    try {
      final perfil = await _perfilAtualChave();
      final key = await getAnonKey();
      if (adicionado) {
        await http.post(
          Uri.parse('$baseUrl/rest/v1/user_favoritos'),
          headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates'},
          body: jsonEncode({'perfil': perfil, 'chave_grupo': chaveGrupo}),
        ).timeout(const Duration(seconds: 5));
      } else {
        await http.delete(
          Uri.parse('$baseUrl/rest/v1/user_favoritos?perfil=eq.${Uri.encodeComponent(perfil)}&chave_grupo=eq.${Uri.encodeComponent(chaveGrupo)}'),
          headers: {'apikey': key, 'Authorization': 'Bearer $key'},
        ).timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    return adicionado;
  }

  // =========================================================================
  // NORMALIZAÇÃO E AGRUPAMENTO DO CATÁLOGO SUPABASE
  // =========================================================================
  static String? _extrairLogoM3u(String texto) {
    final m = RegExp(r'tvg-logo\s*=\s*"([^"]+)"', caseSensitive: false)
        .firstMatch(texto);
    return (m != null && m.group(1)!.startsWith('http'))
        ? m.group(1)!.trim()
        : null;
  }

  static String _limparExtinf(String texto) {
    var s = texto.trim();
    if (s.toUpperCase().startsWith('#EXTINF')) {
      final cut = s.lastIndexOf('"') > s.lastIndexOf(',')
          ? s.lastIndexOf('"')
          : s.lastIndexOf(',');
      if (cut != -1 && cut + 1 < s.length) s = s.substring(cut + 1).trim();
    }
    return s;
  }

  static Map<String, int>? _extrairTempEp(String titulo) {
    for (final rx in [
      RegExp(r'(?:S|T)\s*(\d{1,2})\s*[\|\-:\.\s]*E(?:P)?\s*(\d{1,3})',
          caseSensitive: false),
      RegExp(r'(\d{1,2})\s*[xX]\s*(\d{1,3})'),
      RegExp(r'TEMPORADA\s*(\d{1,2}).*?EP(?:IS[OÓ]DIO)?\s*(\d{1,3})',
          caseSensitive: false),
    ]) {
      final m = rx.firstMatch(titulo);
      if (m != null) {
        return {'t': int.parse(m.group(1)!), 'e': int.parse(m.group(2)!)};
      }
    }
    final epOnly = RegExp(
            r'(?:^|[\s\|\-\[\(])EP(?:IS[OÓ]DIO)?\s*0*(\d{1,3})(?:$|[\s\|\-\]\)])',
            caseSensitive: false)
        .firstMatch(titulo);
    if (epOnly != null) return {'t': 1, 'e': int.parse(epOnly.group(1)!)};
    return null;
  }

  static String _separarCamelCase(String texto) {
    if (texto.contains(' ')) return texto;
    return texto.replaceAllMapped(RegExp(r'([a-záàâãéêíóôõúç])([A-ZÁÀÂÃÉÊÍÓÔÕÚÇ])'), (m) => '${m.group(1)} ${m.group(2)}');
  }

  static String _limparNomeObra(String titulo) {
    var s = _limparExtinf(titulo)
        .replaceAll(
            RegExp(
                r'[\|\-\[\(]?\s*(?:S|T)\s*\d{1,2}\s*[\|\-:\.\s]*E(?:P)?\s*\d{1,3}.*$',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'[\|\-\[\(]?\s*\d{1,2}\s*[xX]\s*\d{1,3}.*$',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'[\|\-\[\(]?\s*TEMPORADA\s*\d{1,2}.*$',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'[\|\-\[\(]?\s*EP(?:IS[OÓ]DIO)?\s*\d{1,3}.*$',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\s*[\(\[]?(?:dublado|legendado|dual|nacional|hd|fhd|4k|1080p|720p)[\)\]]',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'[\|\-:\s]+$'), '')
        .trim();
    final base = s.isEmpty ? _limparExtinf(titulo) : s;
    return _separarCamelCase(base);
  }

  static String normalizarTexto(String texto) => texto
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôõö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll('ç', 'c');

  static String _normalizarChave(String texto) =>
      normalizarTexto(_limparNomeObra(texto)).replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _normalizarUrlImagem(String url) {
    var u = url.trim().replaceAll('/t/p/original/', '/t/p/w780/');
    if (u.startsWith('http://image.tmdb.org') ||
        u.startsWith('http://i.imgur.com')) {
      u = u.replaceFirst('http://', 'https://');
    }
    return u;
  }

  static bool ehLinkValido(String url) {
    final u = url.trim();
    if (u.isEmpty) return false;
    final low = u.toLowerCase();
    if (low.startsWith('magnet:?xt=urn:btih:')) {
      return RegExp(r'^magnet:\?xt=urn:btih:(?:[a-f0-9]{40}|[a-z2-7]{32})(?:&|$)', caseSensitive: false).hasMatch(u);
    }
    if (low.startsWith('https://') || low.startsWith('http://')) {
      final uri = Uri.tryParse(u);
      return uri != null && uri.host.isNotEmpty;
    }
    return false;
  }

  static bool _urlEstaAtiva(String url) {
    if (!ehLinkValido(url)) return false;
    final u = url.toLowerCase();
    for (final m in [
      'staniptv',
      'ntcdn.us',
      'vstreaming.net',
      'popfilmeshd.net',
      'themediafire.club',
      'cdnv12.ec.cx',
      'cdnv18.ec.cx',
      '0.0.0.0',
      'lh3.googleusercontent.com',
      'dailymotion.com/sec('
    ]) {
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
      if (capa.isEmpty) {
        final logo = _extrairLogoM3u(tituloBruto);
        if (logo != null) capa = _normalizarUrlImagem(logo);
      }
      map['capa_url'] = capa;
      map['banner_url'] =
          _normalizarUrlImagem((map['banner_url'] ?? '').toString());
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
      if (isSerie &&
          !catOrig.toLowerCase().contains('anime') &&
          !catOrig.toLowerCase().contains('infantil') &&
          !catOrig.toLowerCase().contains('kids')) {
        map['categoria'] = 'Série';
      }

      final serieNome = (map['serie_nome'] ?? '').toString().trim();
      final norm = _normalizarChave(
          serieNome.isNotEmpty ? _limparNomeObra(serieNome) : _limparNomeObra(tituloLimpo));
      grupos.putIfAbsent(isSerie ? 'serie_$norm' : 'filme_$norm', () => []).add(map);
    }

    final List<ObraAgrupada> obras = [];
    grupos.forEach((chave, lista) {
      lista.sort((a, b) => ((b['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0)
          .compareTo((a['capa_url'] ?? '').toString().isNotEmpty ? 1 : 0));
      final p = lista.first;
      final isSerie = chave.startsWith('serie_');
      final catOrig = (p['categoria'] ?? 'Filme').toString().trim();
      final cat = isSerie &&
              !catOrig.toLowerCase().contains('anime') &&
              !catOrig.toLowerCase().contains('infantil') &&
              !catOrig.toLowerCase().contains('kids')
          ? 'Série'
          : catOrig;
      final serieNome = (p['serie_nome'] ?? '').toString().trim();
      final tituloFinal = serieNome.isNotEmpty
          ? _limparNomeObra(serieNome)
          : _limparNomeObra((p['titulo'] ?? '').toString());

      final Set<String> tagsSet = {};
      int viewsTotal = 0;
      double maiorNota = 0.0;
      bool algumDestaque = false;
      int menorOrdem = 999;

      for (final row in lista) {
        if (row['tags'] is List) {
          for (final t in (row['tags'] as List)) {
            if (t != null && t.toString().trim().isNotEmpty) {
              tagsSet.add(t.toString().trim());
            }
          }
        }
        if (row['em_destaque'] == true) {
          algumDestaque = true;
          tagsSet.add('Banner Principal');
        }
        final ord =
            row['ordem_destaque'] is int ? row['ordem_destaque'] as int : 999;
        if (ord < menorOrdem) menorOrdem = ord;
        viewsTotal +=
            (row['visualizacoes'] is num) ? (row['visualizacoes'] as num).toInt() : 0;
        final nt =
            (row['nota_imdb'] is num) ? (row['nota_imdb'] as num).toDouble() : 0.0;
        if (nt > maiorNota) maiorNota = nt;
      }

      obras.add(ObraAgrupada(
        chaveGrupo: chave,
        tmdbId: p['tmdb_id'] is int
            ? p['tmdb_id']
            : int.tryParse('${p['tmdb_id'] ?? ''}'),
        titulo: tituloFinal,
        tituloOriginal: (p['titulo_original'] ?? '').toString(),
        categoria: cat,
        genero: (p['genero'] ?? '').toString(),
        sinopse: (p['sinopse'] ?? '').toString(),
        capaUrl: (p['capa_url'] ?? '').toString(),
        bannerUrl: (p['banner_url'] ?? '').toString(),
        ano: (p['ano'] ?? '').toString(),
        pais: (p['pais'] ?? '').toString(),
        diretor: (p['diretor'] ?? '').toString(),
        elenco: (p['elenco'] ?? '').toString(),
        aberturaSegundos: p['abertura_segundos'] is int
            ? p['abertura_segundos']
            : int.tryParse('${p['abertura_segundos'] ?? 85}') ?? 85,
        emDestaque: algumDestaque,
        ordemDestaque: menorOrdem,
        tags: tagsSet.toList(),
        notaImdb: maiorNota,
        visualizacoes: viewsTotal,
        fontes: lista.map<FonteMidia>((e) => FonteMidia.fromJson(e)).toList(),
      ));
    });

    obras.sort((a, b) =>
        (a.capaUrl.isNotEmpty ? 0 : 1).compareTo(b.capaUrl.isNotEmpty ? 0 : 1));
    return obras;
  }

  static Future<List<dynamic>> _fetchLote(
      String key, String filtroQuery, int limite) async {
    const cols =
        'id,tmdb_id,titulo,serie_nome,categoria,genero,sinopse,capa_url,banner_url,ano,temporada,episodio,url_stream,url_stream_backup,headers_customizados,formato,tipo_audio,resolucao,em_destaque,ordem_destaque,tags,nota_imdb,visualizacoes';
    const filtroAtivos =
        '&url_stream=not.ilike.*STANIPTV*&url_stream=not.ilike.*ntcdn.us*&url_stream=not.ilike.*vstreaming.net*&url_stream=not.ilike.*popfilmeshd.net*&url_stream=not.ilike.*themediafire.club*&url_stream=not.ilike.*cdnv12.ec.cx*&url_stream=not.ilike.*cdnv18.ec.cx*&url_stream=not.ilike.*0.0.0.0*&url_stream=not.ilike.*lh3.googleusercontent.com*&url_stream=not.ilike.*dailymotion.com/sec(';
    final uri = Uri.parse(
        '$baseUrl/rest/v1/catalogo_midia?select=$cols$filtroAtivos$filtroQuery&order=ordem_destaque.asc,criado_em.desc');
    final resp = await http.get(uri, headers: {
      'apikey': key,
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      'Range': '0-${limite - 1}',
    }).timeout(const Duration(seconds: 12));
    return (resp.statusCode == 200 || resp.statusCode == 206)
        ? jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>
        : [];
  }

  static ObraAgrupada _obraFromViewRow(Map<String, dynamic> r) {
    final tagsRaw = r['tags'];
    final tagsList = tagsRaw is List
        ? tagsRaw.where((e) => e != null).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    return ObraAgrupada(
      chaveGrupo: (r['chave_grupo'] ?? '').toString(),
      tmdbId: r['tmdb_id'] is int ? r['tmdb_id'] : int.tryParse('${r['tmdb_id'] ?? ''}'),
      titulo: (r['titulo'] ?? 'Sem Título').toString(),
      categoria: (r['categoria'] ?? 'Filme').toString(),
      genero: (r['genero'] ?? '').toString(),
      sinopse: (r['sinopse'] ?? '').toString(),
      capaUrl: _normalizarUrlImagem((r['capa_url'] ?? '').toString()),
      bannerUrl: _normalizarUrlImagem((r['banner_url'] ?? '').toString()),
      ano: (r['ano'] ?? '').toString(),
      emDestaque: r['em_destaque'] == true,
      ordemDestaque: (r['ordem_destaque'] is num) ? (r['ordem_destaque'] as num).toInt() : 999,
      tags: tagsList,
      notaImdb: (r['nota_imdb'] is num) ? (r['nota_imdb'] as num).toDouble() : 0.0,
      visualizacoes: (r['visualizacoes'] is num) ? (r['visualizacoes'] as num).toInt() : 0,
      fontes: const [],
      totalFontes: (r['total_fontes'] is num) ? (r['total_fontes'] as num).toInt() : 1,
      maxTemporada: (r['max_temporada'] is num) ? (r['max_temporada'] as num).toInt() : 1,
      maxEpisodio: (r['max_episodio'] is num) ? (r['max_episodio'] as num).toInt() : 0,
      isSerieFlag: r['is_serie'] == true,
    );
  }

  static String _normChaveObra(String t) {
    var r = t.toLowerCase().trim();
    const ac = "áàâãäéèêëíìîïóòôõöúùûüçñ";
    const sa = "aaaaaeeeeiiiiooooouuuucn";
    for (int i = 0; i < ac.length; i++) {
      r = r.replaceAll(ac[i], sa[i]);
    }
    return r.replaceAll(RegExp(r"[^a-z0-9]"), "");
  }

  static List<ObraAgrupada> _fundirObrasEquivalentes(List<ObraAgrupada> lista) {
    if (lista.length < 2) return lista;
    final mapChave = <String, int>{};
    final resultado = <ObraAgrupada>[];

    for (final item in lista) {
      final chaves = <String>{};
      if (item.tmdbId != null && item.tmdbId! > 0) chaves.add('tmdb_${item.tmdbId}');
      final nTit = _normChaveObra(item.titulo);
      final nOrig = _normChaveObra(item.tituloOriginal);
      if (nTit.length >= 3) chaves.add('t_$nTit');
      if (nOrig.length >= 3) chaves.add('t_$nOrig');

      int? idxExistente;
      for (final c in chaves) {
        if (mapChave.containsKey(c)) {
          idxExistente = mapChave[c];
          break;
        }
      }

      if (idxExistente == null) {
        final novoIdx = resultado.length;
        resultado.add(item);
        for (final c in chaves) {
          mapChave[c] = novoIdx;
        }
      } else {
        final base = resultado[idxExistente];
        // Mantem como principal a obra que tem metadados completos (capa/sinopse/notaImdb/tmdbId)
        final baseScore = (base.sinopse.isNotEmpty ? 4 : 0) +
            (base.notaImdb > 0 ? 3 : 0) +
            (base.tmdbId != null && base.tmdbId! > 0 ? 3 : 0) +
            (base.capaUrl.isNotEmpty ? 2 : 0);
        final itemScore = (item.sinopse.isNotEmpty ? 4 : 0) +
            (item.notaImdb > 0 ? 3 : 0) +
            (item.tmdbId != null && item.tmdbId! > 0 ? 3 : 0) +
            (item.capaUrl.isNotEmpty ? 2 : 0);

        final princ = itemScore > baseScore ? item : base;
        final sec = itemScore > baseScore ? base : item;

        final fontesCombinadas = <FonteMidia>[...princ.fontes];
        final urlsVistas = fontesCombinadas.map((f) => f.urlStream).toSet();
        for (final f in sec.fontes) {
          if (!urlsVistas.contains(f.urlStream)) {
            urlsVistas.add(f.urlStream);
            fontesCombinadas.add(f);
          }
        }

        final tempMax = princ.maxTemporada >= sec.maxTemporada ? princ.maxTemporada : sec.maxTemporada;
        final epMax = princ.maxEpisodio >= sec.maxEpisodio ? princ.maxEpisodio : sec.maxEpisodio;
        final origFinal = princ.tituloOriginal.trim().isNotEmpty
            ? princ.tituloOriginal
            : (sec.tituloOriginal.trim().isNotEmpty ? sec.tituloOriginal : sec.titulo);

        resultado[idxExistente] = ObraAgrupada(
          chaveGrupo: princ.chaveGrupo,
          tmdbId: princ.tmdbId ?? sec.tmdbId,
          titulo: princ.titulo,
          tituloOriginal: origFinal,
          categoria: princ.categoria == 'Geral' && sec.categoria != 'Geral' ? sec.categoria : princ.categoria,
          genero: princ.genero.isNotEmpty ? princ.genero : sec.genero,
          sinopse: princ.sinopse.isNotEmpty ? princ.sinopse : sec.sinopse,
          capaUrl: princ.capaUrl.isNotEmpty ? princ.capaUrl : sec.capaUrl,
          bannerUrl: princ.bannerUrl.isNotEmpty ? princ.bannerUrl : sec.bannerUrl,
          ano: princ.ano.isNotEmpty ? princ.ano : sec.ano,
          pais: princ.pais.isNotEmpty ? princ.pais : sec.pais,
          diretor: princ.diretor.isNotEmpty ? princ.diretor : sec.diretor,
          elenco: princ.elenco.isNotEmpty ? princ.elenco : sec.elenco,
          aberturaSegundos: princ.aberturaSegundos > 0 ? princ.aberturaSegundos : sec.aberturaSegundos,
          emDestaque: princ.emDestaque || sec.emDestaque,
          ordemDestaque: princ.ordemDestaque,
          tags: {...princ.tags, ...sec.tags}.toList(),
          notaImdb: princ.notaImdb > 0 ? princ.notaImdb : sec.notaImdb,
          visualizacoes: princ.visualizacoes + sec.visualizacoes,
          fontes: fontesCombinadas,
          totalFontes: princ.totalFontes + sec.totalFontes,
          maxTemporada: tempMax,
          maxEpisodio: epMax,
          isSerieFlag: princ.isSerieFlag ?? sec.isSerieFlag,
        );
        for (final c in chaves) {
          mapChave[c] = idxExistente;
        }
      }
    }
    return resultado;
  }

  static Future<List<ObraAgrupada>> carregarCatalogoAgrupado({bool forcarRefresh = false, int limite = 500}) async {
    if (!forcarRefresh && _memoriaRapida != null && _memoriaRapida!.isNotEmpty) {
      return _memoriaRapida!;
    }
    final key = await getAnonKey();
    try {
      final uri = Uri.parse(
        '$baseUrl/rest/v1/catalogo_agrupado_view?select=*&order=em_destaque.desc,ordem_destaque.asc,criado_em.desc&limit=$limite',
      );
      final resp = await http.get(uri, headers: {
        'apikey': key,
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 || resp.statusCode == 206) {
        final rows = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
        if (rows.isNotEmpty) {
          final bruta = rows.whereType().map((e) => _obraFromViewRow(Map<String, dynamic>.from(e))).toList();
          final lista = _fundirObrasEquivalentes(bruta);
          _memoriaRapida = lista;
          return lista;
        }
      }
    } catch (_) {}

    final fallback = await _fetchLote(key, '', 400);
    final agrupado = _agruparDados(fallback);
    if (agrupado.isNotEmpty) _memoriaRapida = agrupado;
    return agrupado;
  }

  static Future<List<FonteMidia>> carregarFontesDaObra(ObraAgrupada obra) async {
    if (obra.fontes.isNotEmpty) return obra.fontes;
    final key = await getAnonKey();
    const cols = 'id,titulo,categoria,url_stream,url_stream_backup,formato,resolucao,tipo_audio,idiomas_audio,headers_customizados,temporada,episodio';
    const filtroAtivos =
        '&url_stream=not.ilike.*STANIPTV*&url_stream=not.ilike.*ntcdn.us*&url_stream=not.ilike.*vstreaming.net*&url_stream=not.ilike.*popfilmeshd.net*&url_stream=not.ilike.*themediafire.club*&url_stream=not.ilike.*cdnv12.ec.cx*&url_stream=not.ilike.*cdnv18.ec.cx*&url_stream=not.ilike.*0.0.0.0*&url_stream=not.ilike.*lh3.googleusercontent.com*&url_stream=not.ilike.*dailymotion.com/sec(';

    final termosOr = <String>[];
    if (obra.tmdbId != null && obra.tmdbId! > 0) {
      termosOr.add('tmdb_id.eq.${obra.tmdbId}');
    }
    final encTit = Uri.encodeComponent(obra.titulo.trim());
    if (encTit.isNotEmpty) {
      termosOr.add('serie_nome.ilike.*$encTit*');
      termosOr.add('titulo.ilike.*$encTit*');
    }
    final orig = obra.tituloOriginal.trim();
    if (orig.isNotEmpty && orig.toLowerCase() != obra.titulo.trim().toLowerCase()) {
      final encOrig = Uri.encodeComponent(orig);
      termosOr.add('serie_nome.ilike.*$encOrig*');
      termosOr.add('titulo.ilike.*$encOrig*');
    }
    final filtro = '&or=(${termosOr.join(",")})';

    try {
      final uri = Uri.parse('$baseUrl/rest/v1/catalogo_midia?select=$cols$filtroAtivos$filtro&order=temporada.asc.nullslast,episodio.asc.nullslast&limit=250');
      final resp = await http.get(uri, headers: {
        'apikey': key,
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200 || resp.statusCode == 206) {
        final rows = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
        final fontes = <FonteMidia>[];
        for (final item in rows) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final titLimpo = _limparExtinf((map['titulo'] ?? '').toString());
          map['titulo'] = titLimpo;
          final te = _extrairTempEp(titLimpo);
          if (te != null) {
            map['temporada'] ??= te['t'];
            map['episodio'] ??= te['e'];
          }
          final uStream = (map['url_stream'] ?? '').toString().trim();
          if (_urlEstaAtiva(uStream)) {
            final uBackup = (map['url_stream_backup'] ?? '').toString().trim();
            if (uBackup.isNotEmpty && !_urlEstaAtiva(uBackup)) {
              map['url_stream_backup'] = '';
            }
            fontes.add(FonteMidia.fromJson(map));
          }
        }
        return fontes;
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> registrarVisualizacao(String id) async {
    try {
      final key = await getAnonKey();
      await http.post(
        Uri.parse('$baseUrl/rest/v1/rpc/incrementar_visualizacao'),
        headers: {
          'apikey': key,
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'media_id': id}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // =========================================================================
  // TMDB: METADADOS COMPLETOS (DIRETOR, ELENCO, PAÍS, TÍTULO ORIGINAL)
  // =========================================================================
  static Future<ObraAgrupada> enriquecerComTmdb(ObraAgrupada obra) async {
    if (obra.diretor.isNotEmpty &&
        obra.elenco.isNotEmpty &&
        obra.pais.isNotEmpty) {
      return obra;
    }
    if (_cacheCreditosTmdb.containsKey(obra.chaveGrupo)) {
      final c = _cacheCreditosTmdb[obra.chaveGrupo]!;
      return obra.copyWith(
        tituloOriginal: c['tituloOriginal'],
        pais: c['pais'],
        diretor: c['diretor'],
        elenco: c['elenco'],
        sinopse: c['sinopse'],
        notaImdb: c['nota'],
      );
    }

    try {
      final tipo = obra.isSerie ? 'tv' : 'movie';
      int? idTmdb = obra.tmdbId;

      if (idTmdb == null) {
        final searchUri = Uri.parse(
            'https://api.themoviedb.org/3/search/$tipo?api_key=$tmdbApiKey&language=pt-BR&query=${Uri.encodeQueryComponent(obra.titulo)}');
        final sResp =
            await http.get(searchUri).timeout(const Duration(seconds: 6));
        if (sResp.statusCode == 200) {
          final results =
              (jsonDecode(utf8.decode(sResp.bodyBytes))['results'] as List?) ??
                  [];
          if (results.isNotEmpty) {
            idTmdb = results.first['id'] as int?;
          }
        }
      }

      if (idTmdb != null) {
        final detUri = Uri.parse(
            'https://api.themoviedb.org/3/$tipo/$idTmdb?api_key=$tmdbApiKey&language=pt-BR&append_to_response=credits');
        final dResp =
            await http.get(detUri).timeout(const Duration(seconds: 6));
        if (dResp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(dResp.bodyBytes));
          final orig =
              (data['original_title'] ?? data['original_name'] ?? '').toString();
          final countries = (data['production_countries'] as List?) ?? [];
          final paisNome = countries.isNotEmpty
              ? (countries.first['name'] ?? '').toString()
              : '';
          final credits = data['credits'] as Map<String, dynamic>? ?? {};
          final cast = (credits['cast'] as List?) ?? [];
          final crew = (credits['crew'] as List?) ?? [];

          final diretores = crew
              .where((c) => (c['job'] ?? '') == 'Director')
              .map((c) => (c['name'] ?? '').toString())
              .where((n) => n.isNotEmpty)
              .take(2)
              .join(', ');
          final criadores = ((data['created_by'] as List?) ?? [])
              .map((c) => (c['name'] ?? '').toString())
              .where((n) => n.isNotEmpty)
              .take(2)
              .join(', ');
          final elencoStr = cast
              .map((c) => (c['name'] ?? '').toString())
              .where((n) => n.isNotEmpty)
              .take(5)
              .join(', ');
          final sinopseTmdb = (data['overview'] ?? '').toString();
          final vote = (data['vote_average'] is num)
              ? (data['vote_average'] as num).toDouble()
              : 0.0;

          final info = {
            'tituloOriginal': orig,
            'pais': paisNome,
            'diretor': diretores.isNotEmpty ? diretores : criadores,
            'elenco': elencoStr,
            'sinopse': sinopseTmdb,
            'nota': double.parse(vote.toStringAsFixed(1)),
          };
          if (_cacheCreditosTmdb.length > 120) { _cacheCreditosTmdb.remove(_cacheCreditosTmdb.keys.first); }
      _cacheCreditosTmdb[obra.chaveGrupo] = info;
          return obra.copyWith(
            tituloOriginal: orig,
            pais: paisNome,
            diretor: info['diretor'] as String,
            elenco: elencoStr,
            sinopse: sinopseTmdb,
            notaImdb: info['nota'] as double,
          );
        }
      }
    } catch (_) {}
    return obra;
  }

  // =========================================================================
  // BUSCA UNIFICADA (TÍTULOS + ELENCO + DIRETORES VIA TMDB)
  // =========================================================================
  static Future<List<ObraAgrupada>> buscarComElencoEDiretores(
      String query, List<ObraAgrupada> catalogo) async {
    final qNorm = normalizarTexto(query.trim());
    if (qNorm.isEmpty) return [];

    final Map<String, ObraAgrupada> resultados = {};
    try {
      final key = await getAnonKey();
      final enc = Uri.encodeComponent(query.trim());
      final uri = Uri.parse('$baseUrl/rest/v1/catalogo_agrupado_view?select=*&or=(titulo.ilike.*$enc*,genero.ilike.*$enc*)&limit=60');
      final resp = await http.get(uri, headers: {'apikey': key, 'Authorization': 'Bearer $key'}).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        for (final r in (jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>)) {
          if (r is Map) {
            final o = _obraFromViewRow(Map<String, dynamic>.from(r));
            resultados[o.chaveGrupo] = o;
          }
        }
      }
    } catch (_) {}

    for (final o in catalogo) {
      final tit = normalizarTexto(o.titulo);
      final orig = normalizarTexto(o.tituloOriginal);
      final dir = normalizarTexto(o.diretor);
      final el = normalizarTexto(o.elenco);
      final gen = normalizarTexto(o.genero);
      if (tit.contains(qNorm) ||
          orig.contains(qNorm) ||
          dir.contains(qNorm) ||
          el.contains(qNorm) ||
          gen.contains(qNorm)) {
        resultados[o.chaveGrupo] = o;
      }
    }

    // Busca pessoa (ator/diretor) no TMDB para cruzar com o catálogo
    if (qNorm.length >= 3) {
      try {
        final pUri = Uri.parse(
            'https://api.themoviedb.org/3/search/person?api_key=$tmdbApiKey&language=pt-BR&query=${Uri.encodeQueryComponent(query.trim())}');
        final resp = await http.get(pUri).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final pessoas =
              (jsonDecode(utf8.decode(resp.bodyBytes))['results'] as List?) ??
                  [];
          final Set<int> idsRelacionados = {};
          final Set<String> titulosRelacionados = {};

          for (final p in pessoas.take(2)) {
            final known = (p['known_for'] as List?) ?? [];
            for (final k in known) {
              if (k['id'] is int) idsRelacionados.add(k['id']);
              final t1 = normalizarTexto((k['title'] ?? '').toString());
              final t2 = normalizarTexto((k['name'] ?? '').toString());
              if (t1.isNotEmpty) titulosRelacionados.add(t1);
              if (t2.isNotEmpty) titulosRelacionados.add(t2);
            }
            if (p['id'] is int) {
              final credUri = Uri.parse(
                  'https://api.themoviedb.org/3/person/${p['id']}/combined_credits?api_key=$tmdbApiKey&language=pt-BR');
              final cResp =
                  await http.get(credUri).timeout(const Duration(seconds: 5));
              if (cResp.statusCode == 200) {
                final cData = jsonDecode(utf8.decode(cResp.bodyBytes));
                for (final item in [
                  ...((cData['cast'] as List?) ?? []),
                  ...((cData['crew'] as List?) ?? []),
                ]) {
                  if (item['id'] is int) idsRelacionados.add(item['id']);
                  final t1 = normalizarTexto((item['title'] ?? '').toString());
                  final t2 = normalizarTexto((item['name'] ?? '').toString());
                  if (t1.isNotEmpty) titulosRelacionados.add(t1);
                  if (t2.isNotEmpty) titulosRelacionados.add(t2);
                }
              }
            }
          }

          for (final o in catalogo) {
            if ((o.tmdbId != null && idsRelacionados.contains(o.tmdbId)) ||
                titulosRelacionados.contains(normalizarTexto(o.titulo))) {
              resultados[o.chaveGrupo] = o;
            }
          }
        }
      } catch (_) {}
    }

    return resultados.values.toList();
  }

  // =========================================================================
  // TOP 100 IMDb & TMDB POR CATEGORIA (INCLUI TÍTULOS FORA DO CATÁLOGO)
  // =========================================================================
  static Future<List<ObraAgrupada>> carregarTop100Ranking({
    required String fonte, // 'imdb' ou 'tmdb'
    required String categoria, // 'Filmes', 'Séries', 'Kids', 'Anime'
    required List<ObraAgrupada> catalogoLocal,
  }) async {
    final isTv = categoria == 'Séries' || categoria == 'Anime';
    final endpoint = isTv ? 'tv' : 'movie';
    final sort = fonte == 'imdb'
        ? 'vote_average.desc&vote_count.gte=${isTv ? 400 : 1200}'
        : 'popularity.desc';

    String extraGenre = '';
    if (categoria == 'Kids') extraGenre = '&with_genres=10751,16';
    if (categoria == 'Anime') {
      extraGenre = '&with_genres=16&with_original_language=ja';
    }

    final Map<String, ObraAgrupada> mapaLocalPorTitulo = {};
    final Map<int, ObraAgrupada> mapaLocalPorId = {};
    for (final o in catalogoLocal) {
      mapaLocalPorTitulo[normalizarTexto(o.titulo)] = o;
      if (o.tmdbId != null) mapaLocalPorId[o.tmdbId!] = o;
    }

    final List<ObraAgrupada> ranking = [];
    try {
      // 5 páginas x 20 itens = Top 100
      final futures = List.generate(5, (idx) {
        final page = idx + 1;
        final uri = Uri.parse(
            'https://api.themoviedb.org/3/discover/$endpoint?api_key=$tmdbApiKey&language=pt-BR&sort_by=$sort$extraGenre&page=$page');
        return http.get(uri).timeout(const Duration(seconds: 8));
      });

      final responses = await Future.wait(futures);
      for (final resp in responses) {
        if (resp.statusCode != 200) continue;
        final results =
            (jsonDecode(utf8.decode(resp.bodyBytes))['results'] as List?) ?? [];
        for (final item in results) {
          if (ranking.length >= 100) break;
          final int? id = item['id'] is int ? item['id'] : null;
          final titulo =
              (item['title'] ?? item['name'] ?? 'Sem Título').toString();
          final normTit = normalizarTexto(titulo);

          // Se já existir no seu catálogo do Supabase, vincula com os streams reais
          if (id != null && mapaLocalPorId.containsKey(id)) {
            ranking.add(mapaLocalPorId[id]!);
            continue;
          }
          if (mapaLocalPorTitulo.containsKey(normTit)) {
            ranking.add(mapaLocalPorTitulo[normTit]!);
            continue;
          }

          final poster = (item['poster_path'] ?? '').toString();
          final backdrop = (item['backdrop_path'] ?? '').toString();
          final dataLanc =
              (item['release_date'] ?? item['first_air_date'] ?? '').toString();
          final ano = dataLanc.length >= 4 ? dataLanc.substring(0, 4) : '';
          final nota = (item['vote_average'] is num)
              ? double.parse((item['vote_average'] as num).toStringAsFixed(1))
              : 0.0;

          ranking.add(ObraAgrupada(
            chaveGrupo: 'rank_${fonte}_${categoria}_${id ?? ranking.length}',
            tmdbId: id,
            titulo: titulo,
            tituloOriginal:
                (item['original_title'] ?? item['original_name'] ?? '')
                    .toString(),
            categoria: categoria,
            genero: categoria,
            sinopse: (item['overview'] ?? '').toString(),
            capaUrl: poster.isNotEmpty
                ? 'https://image.tmdb.org/t/p/w500$poster'
                : '',
            bannerUrl: backdrop.isNotEmpty
                ? 'https://image.tmdb.org/t/p/w780$backdrop'
                : '',
            ano: ano,
            emDestaque: false,
            ordemDestaque: ranking.length + 1,
            notaImdb: nota,
            fontes: const [], // Ainda não adicionado no catálogo (exibe badge "Em breve")
          ));
        }
      }
    } catch (_) {}

    return ranking;
  }

}
