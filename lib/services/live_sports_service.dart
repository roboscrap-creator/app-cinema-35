import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/midia_model.dart';

class JogoAoVivoInfo {
  final String id;
  final String campeonato;
  final String timeCasa;
  final String escudoCasa;
  final String placarCasa;
  final String timeFora;
  final String escudoFora;
  final String placarFora;
  final String statusTexto;
  final bool aoVivo;
  final String emissora;
  final int prioridade;

  const JogoAoVivoInfo({
    required this.id,
    required this.campeonato,
    required this.timeCasa,
    required this.escudoCasa,
    required this.placarCasa,
    required this.timeFora,
    required this.escudoFora,
    required this.placarFora,
    required this.statusTexto,
    required this.aoVivo,
    required this.emissora,
    required this.prioridade,
  });

  String get tituloPartida => '$timeCasa x $timeFora';
}

class LiveSportsService {
  LiveSportsService._();
  static final LiveSportsService instance = LiveSportsService._();

  static const List> _ligas = [
    {'slug': 'bra.1', 'nome': 'Brasileirão Série A', 'prio': 100},
    {'slug': 'conmebol.libertadores', 'nome': 'Libertadores', 'prio': 98},
    {'slug': 'bra.copa_do_brasil', 'nome': 'Copa do Brasil', 'prio': 96},
    {'slug': 'uefa.champions', 'nome': 'Champions League', 'prio': 95},
    {'slug': 'conmebol.sudamericana', 'nome': 'Sul-Americana', 'prio': 90},
    {'slug': 'eng.1', 'nome': 'Premier League', 'prio': 88},
    {'slug': 'esp.1', 'nome': 'La Liga', 'prio': 85},
    {'slug': 'ita.1', 'nome': 'Serie A Itália', 'prio': 82},
    {'slug': 'bra.2', 'nome': 'Brasileirão Série B', 'prio': 80},
  ];

  List<JogoAoVivoInfo> _cache = [];
  DateTime? _ultimoFetch;

  Future<List<JogoAoVivoInfo>> buscarJogosPrincipais({bool forcar = false}) async {
    if (!forcar &&
        _cache.isNotEmpty &&
        _ultimoFetch != null &&
        DateTime.now().difference(_ultimoFetch!).inMinutes < 3) {
      return _cache;
    }

    final encontrados = <JogoAoVivoInfo>[];

    await Future.wait(_ligas.map((liga) async {
      final slug = liga['slug'] as String;
      final nomeLiga = liga['nome'] as String;
      final prioBase = liga['prio'] as int;
      try {
        final uri = Uri.parse(
          'https://site.api.espn.com/apis/site/v2/sports/soccer/$slug/scoreboard',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 7));
        if (res.statusCode != 200) return;
        final data = jsonDecode(res.body);
        final events = (data['events'] is List ? data['events'] : []);

        for (final ev in events) {
          if (ev is! Map) continue;
          final competitions = (ev['competitions'] is List ? ev['competitions'] : []);
          if (competitions.isEmpty) continue;
          final comp = competitions.first as Map;
          final competitors = (comp['competitors'] is List ? comp['competitors'] : []);
          if (competitors.length < 2) continue;

          Map? home;
          Map? away;
          for (final c in competitors) {
            if (c is Map) {
              if (c['homeAway'] == 'home') home = c;
              if (c['homeAway'] == 'away') away = c;
            }
          }
          home ??= competitors[0] as Map;
          away ??= competitors[1] as Map;

          final homeTeam = (home['team'] as Map?) ?? {};
          final awayTeam = (away['team'] as Map?) ?? {};

          final timeCasa = (homeTeam['shortDisplayName'] ?? homeTeam['displayName'] ?? 'Time A').toString();
          final timeFora = (awayTeam['shortDisplayName'] ?? awayTeam['displayName'] ?? 'Time B').toString();
          final escudoCasa = (homeTeam['logo'] ?? '').toString();
          final escudoFora = (awayTeam['logo'] ?? '').toString();
          final placarCasa = (home['score'] ?? '0').toString();
          final placarFora = (away['score'] ?? '0').toString();

          final status = (ev['status'] as Map?) ?? {};
          final statusType = (status['type'] as Map?) ?? {};
          final state = (statusType['state'] ?? 'pre').toString().toLowerCase();
          final aoVivo = state == 'in';
          final encerrado = state == 'post';

          String statusTexto = (statusType['shortDetail'] ?? statusType['detail'] ?? '').toString();
          if (aoVivo) {
            final clock = (status['displayClock'] ?? '').toString();
            statusTexto = clock.isNotEmpty ? 'AO VIVO • $clock' : 'AO VIVO';
          } else if (!encerrado) {
            final dateRaw = (ev['date'] ?? '').toString();
            final dt = DateTime.tryParse(dateRaw)?.toLocal();
            if (dt != null) {
              final hh = dt.hour.toString().padLeft(2, '0');
              final mm = dt.minute.toString().padLeft(2, '0');
              statusTexto = 'HOJE • $hh:$mm';
            }
          }

          String emissora = '';
          final broadcasts = (comp['broadcasts'] is List ? comp['broadcasts'] : []);
          if (broadcasts.isNotEmpty && broadcasts.first is Map) {
            final names = ((broadcasts.first as Map)['names'] is List ? (broadcasts.first as Map)['names'] : []);
            if (names.isNotEmpty) emissora = names.first.toString();
          }

          final prioFinal = prioBase + (aoVivo ? 500 : (encerrado ? -200 : 120));

          encontrados.add(JogoAoVivoInfo(
            id: (ev['id'] ?? '$timeCasa-$timeFora').toString(),
            campeonato: nomeLiga,
            timeCasa: timeCasa,
            escudoCasa: escudoCasa,
            placarCasa: placarCasa,
            timeFora: timeFora,
            escudoFora: escudoFora,
            placarFora: placarFora,
            statusTexto: statusTexto.isEmpty ? nomeLiga : statusTexto,
            aoVivo: aoVivo,
            emissora: emissora,
            prioridade: prioFinal,
          ));
        }
      } catch (_) {}
    }));

    encontrados.sort((a, b) => b.prioridade.compareTo(a.prioridade));
    if (encontrados.isNotEmpty) {
      _cache = encontrados.take(8).toList();
      _ultimoFetch = DateTime.now();
    }
    return _cache;
  }

  ObraAgrupada? encontrarCanalParaJogo(
    JogoAoVivoInfo jogo,
    List<ObraAgrupada> canaisSports,
  ) {
    if (canaisSports.isEmpty) return null;

    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâã]'), 'a')
        .replaceAll(RegExp(r'[éèê]'), 'e')
        .replaceAll(RegExp(r'[íìî]'), 'i')
        .replaceAll(RegExp(r'[óòôõ]'), 'o')
        .replaceAll(RegExp(r'[úùû]'), 'u')
        .replaceAll('ç', 'c');

    final casa = norm(jogo.timeCasa);
    final fora = norm(jogo.timeFora);
    final em = norm(jogo.emissora);
    final camp = norm(jogo.campeonato);

    for (final c in canaisSports) {
      final t = norm('${c.titulo} ${c.categoria} ${c.tags}');
      if ((casa.length >= 4 && t.contains(casa)) ||
          (fora.length >= 4 && t.contains(fora))) {
        return c;
      }
    }

    if (em.isNotEmpty) {
      for (final c in canaisSports) {
        final t = norm('${c.titulo} ${c.categoria}');
        if (t.contains(em)) return c;
      }
    }

    final preferencias = <String>[];
    if (camp.contains('brasileir') || camp.contains('copa do brasil')) {
      preferencias.addAll(['premiere', 'sportv', 'globo', 'caze']);
    } else if (camp.contains('libertadores') ||
        camp.contains('premier') ||
        camp.contains('la liga')) {
      preferencias.addAll(['espn', 'disney', 'paramount', 'star']);
    } else if (camp.contains('champions')) {
      preferencias.addAll(['tnt', 'max', 'hbo', 'space']);
    }

    for (final pref in preferencias) {
      for (final c in canaisSports) {
        final t = norm('${c.titulo} ${c.categoria}');
        if (t.contains(pref)) return c;
      }
    }

    return canaisSports.first;
  }
}
