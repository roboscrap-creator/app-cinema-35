import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/midia_model.dart';
import 'app_logger.dart';
import 'cdn_stream_service.dart';
import 'supabase_service.dart';

class LegendaOnlineItem {
  final String id;
  final String idioma;
  final String nome;
  final String url;

  const LegendaOnlineItem({
    required this.id,
    required this.idioma,
    required this.nome,
    required this.url,
  });
}

class SubtitleService {
  static String _labelIdioma(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('pob') || l.contains('pb') || l.contains('brazil')) {
      return 'Português (BR)';
    }
    if (l.contains('por') || l.contains('pt')) return 'Português';
    if (l.contains('eng') || l.contains('en')) return 'Inglês';
    if (l.contains('spa') || l.contains('es')) return 'Espanhol';
    return raw.toUpperCase();
  }

  static Future<String> _descobrirImdbId(ObraAgrupada obra, FonteMidia fonte) async {
    if (obra.tmdbId != null && obra.tmdbId! > 0) {
      try {
        final mediaType = obra.isSerie ? 'tv' : 'movie';
        final r = await http.get(
          Uri.parse('${CdnStreamService.backendBaseUrl}/tmdb/details/$mediaType/${obra.tmdbId}'),
          headers: CdnStreamService.authHeaders(),
        ).timeout(const Duration(seconds: 6));
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body) as Map<String, dynamic>;
          final ext = (data['external_ids'] as Map?)?['imdb_id']?.toString() ?? '';
          if (ext.startsWith('tt')) return ext;
        }
      } catch (e) {
        AppLogger.erro('SubtitleService.tmdbImdb', e);
      }
    }

    try {
      final q = Uri.encodeComponent(
        (obra.tituloOriginal.isNotEmpty ? obra.tituloOriginal : obra.titulo).trim(),
      );
      final r = await http.get(
        Uri.parse('https://v3.sg.media-imdb.com/suggestion/x/$q.json'),
      ).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final d = (jsonDecode(r.body)['d'] as List<dynamic>?) ?? [];
        for (final item in d) {
          if (item is Map && (item['id'] ?? '').toString().startsWith('tt')) {
            return item['id'].toString();
          }
        }
      }
    } catch (e) {
      AppLogger.erro('SubtitleService.imdbSuggest', e);
    }
    return '';
  }

  static Future<List<LegendaOnlineItem>> buscarMultiBancos({
    required ObraAgrupada obra,
    required FonteMidia fonte,
    String tituloBusca = '',
  }) async {
    final encontrados = <LegendaOnlineItem>[];
    final urlsVistas = <String>{};
    final termo = tituloBusca.trim().isNotEmpty ? tituloBusca.trim() : obra.titulo;
    final temp = fonte.temporada ?? 0;
    final ep = fonte.episodio ?? 0;

    void adicionar(String id, String idioma, String nome, String url) {
      if (url.isEmpty || urlsVistas.contains(url)) return;
      urlsVistas.add(url);
      encontrados.add(LegendaOnlineItem(id: id, idioma: idioma, nome: nome, url: url));
    }

    // 1. Backend Render protegido
    try {
      final uri = Uri.parse('${CdnStreamService.backendBaseUrl}/legendas/buscar').replace(
        queryParameters: {
          'titulo': termo,
          'tmdb_id': '${obra.tmdbId ?? ''}',
          'tipo': obra.isSerie ? 'tv' : 'movie',
          'temporada': '$temp',
          'episodio': '$ep',
        },
      );
      final resp = await http
          .get(uri, headers: CdnStreamService.authHeaders())
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final lista = (data['legendas'] as List<dynamic>? ?? []);
        for (int i = 0; i < lista.length; i++) {
          final l = lista[i] as Map<String, dynamic>;
          adicionar(
            'srv_$i',
            (l['idioma'] ?? 'Português').toString(),
            (l['nome'] ?? 'Legenda ${i + 1}').toString(),
            (l['url'] ?? '').toString(),
          );
        }
      }
    } catch (e) {
      AppLogger.erro('SubtitleService.backend', e);
    }

    // 2. Fallback direto OpenSubtitles v3 via IMDb ID
    if (encontrados.isEmpty) {
      final imdbId = await _descobrirImdbId(obra, fonte);
      if (imdbId.startsWith('tt')) {
        final endpoint = (obra.isSerie && temp > 0 && ep > 0)
            ? 'https://opensubtitles-v3.strem.io/subtitles/series/$imdbId:$temp:$ep.json'
            : 'https://opensubtitles-v3.strem.io/subtitles/movie/$imdbId.json';
        try {
          final r = await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 7));
          if (r.statusCode == 200) {
            final subs = (jsonDecode(r.body)['subtitles'] as List<dynamic>? ?? []);
            for (int i = 0; i < subs.length; i++) {
              final s = subs[i] as Map<String, dynamic>;
              final lang = (s['lang'] ?? '').toString();
              if (RegExp(r'por|pob|pb|pt|eng|spa', caseSensitive: false).hasMatch(lang)) {
                final idioma = _labelIdioma(lang);
                adicionar(
                  'os3_$i',
                  idioma,
                  '$idioma • OpenSubtitles #${i + 1}',
                  (s['url'] ?? '').toString(),
                );
              }
            }
          }
        } catch (e) {
          AppLogger.erro('SubtitleService.os3', e);
        }
      }
    }

    // Ordena priorizando Português
    encontrados.sort((a, b) {
      final aPt = a.idioma.toLowerCase().contains('portugu') ? 0 : 1;
      final bPt = b.idioma.toLowerCase().contains('portugu') ? 0 : 1;
      return aPt.compareTo(bPt);
    });

    return encontrados;
  }

  static String montarUrlProxyVtt(String rawUrl) {
    if (rawUrl.contains('/legendas/baixar')) return rawUrl;
    return '${CdnStreamService.backendBaseUrl}/legendas/baixar?url=${Uri.encodeComponent(rawUrl)}';
  }
}
