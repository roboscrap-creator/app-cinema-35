import 'dart:convert';
import 'package:http/http.dart' as http;
import 'max_memory_service.dart';

class MaxCinemaKnowledgeService {
  static final MaxCinemaKnowledgeService instance = MaxCinemaKnowledgeService._();
  MaxCinemaKnowledgeService._();

  String _tmdbApiKey = '';

  void configurarTmdbKey(String key) {
    if (key.trim().isNotEmpty) _tmdbApiKey = key.trim();
  }

  Future<String> buscarContextoPessoaTmdb(String nomePessoa) async {
    if (_tmdbApiKey.isEmpty || nomePessoa.trim().isEmpty) return '';
    try {
      final searchUri = Uri.parse(
        'https://api.themoviedb.org/3/search/person?api_key=$_tmdbApiKey&language=pt-BR&query=${Uri.encodeComponent(nomePessoa.trim())}',
      );
      final resp = await http.get(searchUri).timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) return '';

      final results = (jsonDecode(resp.body)['results'] as List<dynamic>? ?? []);
      if (results.isEmpty) return '';

      final pessoa = results.first as Map<String, dynamic>;
      final id = pessoa['id'];
      final nome = (pessoa['name'] ?? nomePessoa).toString();
      final departamento = (pessoa['known_for_department'] ?? '').toString();
      final conhecidos = (pessoa['known_for'] as List<dynamic>? ?? [])
          .map((item) => (item['title'] ?? item['name'] ?? '').toString())
          .where((t) => t.isNotEmpty)
          .take(6)
          .toList();

      String bioCurta = '';
      if (id != null) {
        final detResp = await http
            .get(Uri.parse('https://api.themoviedb.org/3/person/$id?api_key=$_tmdbApiKey&language=pt-BR'))
            .timeout(const Duration(seconds: 4));
        if (detResp.statusCode == 200) {
          final bio = (jsonDecode(detResp.body)['biography'] ?? '').toString().trim();
          if (bio.isNotEmpty) bioCurta = bio.length > 320 ? '${bio.substring(0, 320)}...' : bio;
        }
      }

      final resumo = 'TMDB $nome ($departamento): Obras: ${conhecidos.join(", ")}. $bioCurta';
      await MaxMemoryService.instance.registrarAprendizado('$nome: ${conhecidos.take(3).join(", ")}');
      return resumo;
    } catch (_) {
      return '';
    }
  }
}
