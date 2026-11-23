import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'max_memory_service.dart';
import 'supabase_service.dart';

class PedidoTituloItem {
  final String titulo;
  final String tipo;
  final String solicitadoPor;
  final String dataHora;
  final bool enviadoParaScrape;

  const PedidoTituloItem({
    required this.titulo,
    required this.tipo,
    required this.solicitadoPor,
    required this.dataHora,
    required this.enviadoParaScrape,
  });

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'tipo': tipo,
        'solicitadoPor': solicitadoPor,
        'dataHora': dataHora,
        'enviadoParaScrape': enviadoParaScrape,
      };

  factory PedidoTituloItem.fromJson(Map<String, dynamic> json) {
    return PedidoTituloItem(
      titulo: (json['titulo'] ?? '').toString(),
      tipo: (json['tipo'] ?? 'Filme/Série').toString(),
      solicitadoPor: (json['solicitadoPor'] ?? json['solicitado_por'] ?? 'Usuário CineMax').toString(),
      dataHora: (json['dataHora'] ?? json['criado_em'] ?? '').toString(),
      enviadoParaScrape: json['enviadoParaScrape'] == true || json['status'] != null,
    );
  }
}

class PedidosScrapeService extends ChangeNotifier {
  static final PedidosScrapeService instance = PedidosScrapeService._();
  PedidosScrapeService._();

  static const String _kPedidosKey = 'cinemax_pedidos_scrape_v1';
  final List<PedidoTituloItem> _pedidos = [];
  bool _carregado = false;

  List<PedidoTituloItem> get pedidos => List.unmodifiable(_pedidos);

  Future<void> inicializar() async {
    if (!_carregado) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPedidosKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final lista = jsonDecode(raw) as List<dynamic>;
          _pedidos.clear();
          for (final item in lista) {
            if (item is Map<String, dynamic>) _pedidos.add(PedidoTituloItem.fromJson(item));
          }
        } catch (_) {}
      }
      _carregado = true;
    }
    await _sincronizarDaNuvem();
    notifyListeners();
  }

  Future<void> _sincronizarDaNuvem() async {
    try {
      final key = await SupabaseService.getAnonKey();
      final uri = Uri.parse('${SupabaseService.baseUrl}/rest/v1/pedidos_catalogo?select=titulo,tipo,solicitado_por,status,criado_em&order=criado_em.desc&limit=50');
      final resp = await http.get(uri, headers: {'apikey': key, 'Authorization': 'Bearer $key'}).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final rows = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
        if (rows.isNotEmpty) {
          _pedidos.clear();
          for (final r in rows) {
            if (r is Map<String, dynamic>) {
              final dt = (r['criado_em'] ?? '').toString();
              final dataCurta = dt.length >= 16 ? dt.substring(0, 16).replaceFirst('T', ' ') : dt;
              _pedidos.add(PedidoTituloItem(
                titulo: (r['titulo'] ?? '').toString(),
                tipo: (r['tipo'] ?? 'Filme').toString(),
                solicitadoPor: (r['solicitado_por'] ?? 'Geral').toString(),
                dataHora: dataCurta,
                enviadoParaScrape: true,
              ));
            }
          }
          // 100% nuvem na Supabase
        }
      }
    } catch (_) {}
  }

  Future<bool> enviarPedido({
    required String titulo,
    String tipo = 'Filme/Série',
    String? observacao,
  }) async {
    await inicializar();
    final tituloLimpo = titulo.trim();
    if (tituloLimpo.isEmpty) return false;

    final quem = MaxMemoryService.instance.nomeAtual.isNotEmpty
        ? MaxMemoryService.instance.nomeAtual
        : 'Geral';
    final agora = DateTime.now();
    final dataFmt =
        '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} '
        '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';

    bool enviadoRemoto = false;
    try {
      final key = await SupabaseService.getAnonKey();
      final resp = await http.post(
        Uri.parse('${SupabaseService.baseUrl}/rest/v1/pedidos_catalogo'),
        headers: {
          'apikey': key,
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'titulo': tituloLimpo,
          'tipo': tipo,
          'solicitado_por': quem,
          'observacao': observacao ?? '',
          'status': 'pendente',
        }),
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode >= 200 && resp.statusCode < 300) enviadoRemoto = true;
    } catch (_) {}

    _pedidos.removeWhere((p) => p.titulo.toLowerCase() == tituloLimpo.toLowerCase());
    _pedidos.insert(
      0,
      PedidoTituloItem(
        titulo: tituloLimpo,
        tipo: tipo,
        solicitadoPor: quem,
        dataHora: dataFmt,
        enviadoParaScrape: enviadoRemoto,
      ),
    );
    // 100% nuvem na Supabase
    notifyListeners();
    return enviadoRemoto;
  }

  Future<void> _salvar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPedidosKey, jsonEncode(_pedidos.map((e) => e.toJson()).toList()));
  }
}
