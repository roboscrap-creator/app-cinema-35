import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/catalogo_item.dart';

class SupabaseService {
  final String supabaseUrl;
  final String serviceKey;

  SupabaseService({required this.supabaseUrl, required this.serviceKey});

  Map<String, String> get _headers => {
        'apikey': serviceKey,
        'Authorization': 'Bearer $serviceKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<List<CatalogoItem>> listarCatalogo({bool? aprovado}) async {
    String filtro = aprovado != null ? '&aprovado=eq.$aprovado' : '';
    final res = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_midia?select=*$filtro&order=criado_em.desc'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      final List dados = jsonDecode(utf8.decode(res.bodyBytes));
      return dados.map((e) => CatalogoItem.fromJson(e)).toList();
    }
    throw Exception('Erro HTTP ${res.statusCode}: ${res.body}');
  }

  Future<void> inserirMidia(Map<String, dynamic> dados) async {
    final res = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_midia'),
      headers: _headers,
      body: jsonEncode(dados),
    );
    if (res.statusCode >= 300) {
      throw Exception('Falha ao salvar: ${res.body}');
    }
  }

  Future<void> atualizarStatus(String id, {bool? aprovado, bool? linkAtivo, String? backupUrl}) async {
    final Map<String, dynamic> body = {};
    if (aprovado != null) body['aprovado'] = aprovado;
    if (linkAtivo != null) body['link_ativo'] = linkAtivo;
    if (backupUrl != null) body['url_stream_backup'] = backupUrl;

    await http.patch(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_midia?id=eq.$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
  }

  Future<void> excluirMidia(String id) async {
    await http.delete(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_midia?id=eq.$id'),
      headers: _headers,
    );
  }

  Future<List>> listarDestaquesHero() async {
    final res = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_midia?em_destaque=eq.true&order=ordem_destaque.asc'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      return List>.from(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    return [];
  }

  Future<void> definirDestaqueHero(String id, bool emDestaque, {int ordem = 1}) async {
    await http.patch(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_midia?id=eq.$id'),
      headers: _headers,
      body: jsonEncode({
        'em_destaque': emDestaque,
        'ordem_destaque': emDestaque ? ordem : 0,
      }),
    );
  }

  Future<List>> listarAbas() async {
    final res = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_abas?order=ordem.asc'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      return List>.from(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    return [];
  }

  Future<void> criarAba(String nome, int ordem) async {
    final id = 'aba_${DateTime.now().millisecondsSinceEpoch}';
    await http.post(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_abas'),
      headers: _headers,
      body: jsonEncode({'id': id, 'nome': nome, 'ordem': ordem, 'esta_ativa': true}),
    );
  }

  Future<void> excluirAba(String id) async {
    await http.delete(Uri.parse('$supabaseUrl/rest/v1/catalogo_abas?id=eq.$id'), headers: _headers);
  }

  Future<List>> listarBlocos() async {
    final res = await http.get(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_blocos?order=ordem.asc'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      return List>.from(jsonDecode(utf8.decode(res.bodyBytes)));
    }
    return [];
  }

  Future<void> criarBloco(String idAba, String nome, String tipoBusca, String valorBusca, int ordem) async {
    final id = 'bloco_${DateTime.now().millisecondsSinceEpoch}';
    await http.post(
      Uri.parse('$supabaseUrl/rest/v1/catalogo_blocos'),
      headers: _headers,
      body: jsonEncode({
        'id': id,
        'id_aba': idAba,
        'nome': nome,
        'tipo_busca': tipoBusca,
        'valor_busca': valorBusca,
        'ordem': ordem,
        'esta_ativo': true,
      }),
    );
  }

  Future<void> excluirBloco(String id) async {
    await http.delete(Uri.parse('$supabaseUrl/rest/v1/catalogo_blocos?id=eq.$id'), headers: _headers);
  }
}
