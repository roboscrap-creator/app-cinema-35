import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SerieIncompletaInfo {
  final String titulo;
  final int tmdbId;
  final int temporada;
  final int totalEsperadoTmdb;
  final int totalNoCatalogo;
  final List<int> episodiosFaltando;

  const SerieIncompletaInfo({
    required this.titulo,
    required this.tmdbId,
    required this.temporada,
    required this.totalEsperadoTmdb,
    required this.totalNoCatalogo,
    required this.episodiosFaltando,
  });

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'tmdbId': tmdbId,
        'temporada': temporada,
        'totalEsperadoTmdb': totalEsperadoTmdb,
        'totalNoCatalogo': totalNoCatalogo,
        'episodiosFaltando': episodiosFaltando,
      };
}

class CatalogAuditService extends ChangeNotifier {
  static final CatalogAuditService instance = CatalogAuditService._();
  CatalogAuditService._();

  static const String _scrapeWebhookUrl = String.fromEnvironment('SCRAPE_WEBHOOK_URL', defaultValue: '');
  static const String _githubToken = String.fromEnvironment('GITHUB_PEDIDOS_TOKEN', defaultValue: '');
  static const String _githubRepo = 'roboscrap-creator/app-cinema-35';
  static const String _kSeriesIncompletasKey = 'cinemax_series_incompletas_v1';

  final List<SerieIncompletaInfo> _seriesIncompletas = [];
  final Set<String> _alertasJaEnviados = {};

  List<SerieIncompletaInfo> get seriesIncompletas => List.unmodifiable(_seriesIncompletas);

  static bool ehAnime({
    required String titulo,
    List<String> generos = const [],
    List<String> tags = const [],
    String? paisOrigem,
    String? idiomaOriginal,
    String? sinopse,
  }) {
    final gLower = generos.map((e) => e.toLowerCase().trim()).toList();
    final tagsLower = tags.map((e) => e.toLowerCase().trim()).toList();
    final tLower = titulo.toLowerCase();
    final sLower = (sinopse ?? '').toLowerCase();
    final pais = (paisOrigem ?? '').toUpperCase();
    final lang = (idiomaOriginal ?? '').toLowerCase();

    if (gLower.any((g) => g.contains('anime')) || tagsLower.any((t) => t.contains('anime'))) return true;
    if (RegExp(r'[\u3040-\u30ff\u4e00-\u9faf]').hasMatch(titulo)) return true;

    final ehAnimacao = gLower.any((g) =>
        g.contains('animação') || g.contains('animacao') || g.contains('animation'));
    final origemJapao = pais.contains('JP') || pais.contains('JAP') || lang == 'ja' || lang == 'jp';
    if (ehAnimacao && origemJapao) return true;

    final ehFamiliaKids = gLower.any((g) =>
            g.contains('família') || g.contains('familia') || g.contains('family') || g.contains('infantil') || g.contains('kids')) ||
        tagsLower.any((t) => t.contains('kids') || t.contains('infantil'));

    if (ehAnimacao && !ehFamiliaKids) return true;

    const termosAnime = [
      'ms. servant', 'ms servant', 'sensei', 'senpai', 'sama', 'chan', 'kun',
      'isekai', 'shonen', 'shoujo', 'mecha', 'jujutsu', 'naruto', 'one piece',
      'dragon ball', 'attack on titan', 'shingeki', 'demon slayer', 'kimetsu',
      'bleach', 'death note', 'fullmetal', 'hunter x hunter', 'chainsaw man',
      'tokyo ghoul', 'my hero academia', 'boku no hero', 'solo leveling',
      'boruto', 'saint seiya', 'cavaleiros do zodíaco', 'yu yu hakusho',
      'evangelion', 'cowboy bebop', 'spy x family', 'vinland saga', 'blue lock',
      'haikyuu', 'gundam', 'mobile suit', 'bass x machina', 'bastard', 'berserk',
      'one punch', 'mob psycho', 'jojo', 'fairy tail', 'black clover',
      'sword art', 'overlord', 're:zero', 'konosuba', 'dandadan', 'kaiju',
      'frieren', 'mashle', 'dr. stone', 'akira', 'ghost in the shell',
      'inuyasha', 'ranma', 'sailor moon', 'pokemon', 'pokémon', 'digimon',
      'yu-gi-oh', 'beyblade', 'bakugan', 'monogatari', 'fate/', 'steins;gate',
      'code geass', 'gintama', 'jigokuraku', 'tokyo revengers', 'baki', 'kengan'
    ];
    return termosAnime.any((p) => tLower.contains(p) || sLower.contains(p));
  }

  Future<String?> auditarReproducao({
    required String titulo,
    required bool ehFilmeCatalogo,
    String? subtituloEpisodio,
    Duration? duracaoRealVideo,
    int? duracaoEsperadaMinutos,
  }) async {
    final sub = (subtituloEpisodio ?? '').toUpperCase();

    if (ehFilmeCatalogo && RegExp(r'S\d+\s*-\s*E\d+').hasMatch(sub)) {
      final motivo = 'Filme "$titulo" classificado com numeração de série ($sub).';
      await reportarProblemaParaScrape(titulo: titulo, categoria: 'erro-classificacao', detalhes: motivo);
      return motivo;
    }

    if (duracaoRealVideo != null &&
        duracaoRealVideo.inMinutes > 2 &&
        duracaoEsperadaMinutos != null &&
        duracaoEsperadaMinutos > 40) {
      final diff = (duracaoRealVideo.inMinutes - duracaoEsperadaMinutos).abs();
      if (diff > 35) {
        final motivo =
            'Vídeo possivelmente trocado em "$titulo": esperado ~${duracaoEsperadaMinutos}min, vídeo tem ${duracaoRealVideo.inMinutes}min.';
        await reportarProblemaParaScrape(titulo: titulo, categoria: 'video-trocado', detalhes: motivo);
        return motivo;
      }
    }
    return null;
  }

  Future<void> auditarSerieContraTmdb({
    required String titulo,
    required int tmdbId,
    required String tmdbApiKey,
    required int temporada,
    required List<int> episodiosDisponiveisNoApp,
  }) async {
    if (tmdbApiKey.isEmpty || tmdbId <= 0) return;
    try {
      final uri = Uri.parse(
        'https://api.themoviedb.org/3/tv/$tmdbId/season/$temporada?api_key=$tmdbApiKey&language=pt-BR',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return;

      final epsTmdb = (jsonDecode(resp.body)['episodes'] as List<dynamic>? ?? []);
      final hoje = DateTime.now();

      final lancados = <int>[];
      for (final ep in epsTmdb) {
        final numEp = ep['episode_number'];
        final airDateStr = (ep['air_date'] ?? '').toString();
        if (numEp is int) {
          final airDate = DateTime.tryParse(airDateStr);
          if (airDate == null || !airDate.isAfter(hoje)) lancados.add(numEp);
        }
      }

      final faltando = lancados.where((n) => !episodiosDisponiveisNoApp.contains(n)).toList()..sort();
      _seriesIncompletas.removeWhere((s) => s.tmdbId == tmdbId && s.temporada == temporada);

      if (faltando.isNotEmpty) {
        final info = SerieIncompletaInfo(
          titulo: titulo,
          tmdbId: tmdbId,
          temporada: temporada,
          totalEsperadoTmdb: lancados.length,
          totalNoCatalogo: episodiosDisponiveisNoApp.length,
          episodiosFaltando: faltando,
        );
        _seriesIncompletas.insert(0, info);
        notifyListeners();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _kSeriesIncompletasKey,
          jsonEncode(_seriesIncompletas.map((e) => e.toJson()).toList()),
        );

        await reportarProblemaParaScrape(
          titulo: '$titulo (T$temporada)',
          categoria: 'serie-incompleta',
          detalhes:
              'Série "$titulo" T$temporada incompleta: ${episodiosDisponiveisNoApp.length}/${lancados.length} eps. '
              'Faltando: ${faltando.map((e) => "E${e.toString().padLeft(2, '0')}").join(", ")}.',
        );
      }
    } catch (_) {}
  }

  Future<bool> reportarProblemaParaScrape({
    required String titulo,
    required String categoria,
    required String detalhes,
  }) async {
    final chaveUnica = '$categoria:${titulo.toLowerCase()}';
    if (_alertasJaEnviados.contains(chaveUnica)) return true;
    _alertasJaEnviados.add(chaveUnica);

    bool ok = false;
    if (_scrapeWebhookUrl.isNotEmpty) {
      try {
        final resp = await http
            .post(
              Uri.parse(_scrapeWebhookUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'origem': 'CineMax-Auditor',
                'categoria': categoria,
                'titulo': titulo,
                'detalhes': detalhes,
                'timestamp': DateTime.now().toIso8601String(),
              }),
            )
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode >= 200 && resp.statusCode < 300) ok = true;
      } catch (_) {}
    }

    if (_githubToken.isNotEmpty) {
      try {
        final resp = await http
            .post(
              Uri.parse('https://api.github.com/repos/$_githubRepo/issues'),
              headers: {
                'Authorization': 'Bearer $_githubToken',
                'Accept': 'application/vnd.github+json',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'title': '[$categoria] $titulo',
                'body': 'Categoria: `$categoria`\nTítulo: **$titulo**\nDiagnóstico: $detalhes',
                'labels': ['auditoria-cinemax', categoria],
              }),
            )
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 201 || resp.statusCode == 200) ok = true;
      } catch (_) {}
    }
    return ok;
  }
}
