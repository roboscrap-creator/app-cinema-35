import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'max_memory_service.dart';

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
      solicitadoPor: (json['solicitadoPor'] ?? 'Usuário CineMax').toString(),
      dataHora: (json['dataHora'] ?? '').toString(),
      enviadoParaScrape: json['enviadoParaScrape'] == true,
    );
  }
}

class PedidosScrapeService extends ChangeNotifier {
  static final PedidosScrapeService instance = PedidosScrapeService._();
  PedidosScrapeService._();

  static const String _kPedidosKey = 'cinemax_pedidos_scrape_v1';
  static const String _scrapeWebhookUrl = String.fromEnvironment('SCRAPE_WEBHOOK_URL', defaultValue: '');
  static const String _githubToken = String.fromEnvironment('GITHUB_PEDIDOS_TOKEN', defaultValue: '');
  static const String _githubRepo = 'roboscrap-creator/app-cinema-35';

  final List<PedidoTituloItem> _pedidos = [];
  bool _carregado = false;

  List<PedidoTituloItem> get pedidos => List.unmodifiable(_pedidos);

  Future<void> inicializar() async {
    if (_carregado) return;
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
    notifyListeners();
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
        : 'Usuário CineMax';
    final agora = DateTime.now();
    final dataFmt =
        '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year} '
        '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';

    bool enviadoRemoto = false;

    if (_scrapeWebhookUrl.isNotEmpty) {
      try {
        final resp = await http
            .post(
              Uri.parse(_scrapeWebhookUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'origem': 'CineMax',
                'titulo': tituloLimpo,
                'tipo': tipo,
                'solicitado_por': quem,
                'observacao': observacao ?? '',
                'data_hora': dataFmt,
              }),
            )
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode >= 200 && resp.statusCode < 300) enviadoRemoto = true;
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
                'title': '[Pedido CineMax] $tituloLimpo ($tipo)',
                'body': 'Título: **$tituloLimpo**\nCategoria: **$tipo**\nSolicitado por: **$quem**\nData: **$dataFmt**\n${observacao ?? ""}',
                'labels': ['pedido-cinemax'],
              }),
            )
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 201 || resp.statusCode == 200) enviadoRemoto = true;
      } catch (_) {}
    }

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
    await _salvar();
    notifyListeners();
    return enviadoRemoto;
  }

  Future<void> _salvar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPedidosKey, jsonEncode(_pedidos.map((e) => e.toJson()).toList()));
  }
}
