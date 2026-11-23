import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import '../models/midia_model.dart';
import 'max_memory_service.dart';
import 'pedidos_scrape_service.dart';
import 'supabase_service.dart';

class MaxAcaoComando {
  final String tipo;
  final String falaResposta;
  final String? titulo;
  final String? tipoObra;
  final bool aguardarConfirmacaoAbrir;
  final bool aguardarConfirmacaoPedido;

  const MaxAcaoComando({
    required this.tipo,
    required this.falaResposta,
    this.titulo,
    this.tipoObra,
    this.aguardarConfirmacaoAbrir = false,
    this.aguardarConfirmacaoPedido = false,
  });

  factory MaxAcaoComando.fromJson(Map<String, dynamic> json) {
    return MaxAcaoComando(
      tipo: (json['acao'] ?? 'conversa').toString(),
      falaResposta: (json['fala'] ?? 'Prontinho!').toString(),
      titulo: json['titulo']?.toString(),
      tipoObra: json['tipo_obra']?.toString(),
      aguardarConfirmacaoAbrir: json['aguardar_confirmacao_abrir'] == true,
      aguardarConfirmacaoPedido: json['aguardar_confirmacao_pedido'] == true,
    );
  }
}

class MaxAssistantService extends ChangeNotifier {
  static final MaxAssistantService instance = MaxAssistantService._();
  MaxAssistantService._();

  static const String _brainUrl =
      '${SupabaseService.baseUrl}/functions/v1/max-brain';

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _inicializado = false;
  bool _ouvindo = false;
  bool _processando = false;
  bool _falando = false;
  String _textoReconhecido = '';
  String _ultimaFalaMax = 'Oi! Toque no microfone e me peça qualquer filme, série ou anime.';
  MaxAcaoComando? _pendenteAbrir;
  MaxAcaoComando? _pendentePedidoCatalogo;

  void Function(MaxAcaoComando acao)? onExecutarAcao;

  bool get ouvindo => _ouvindo;
  bool get processando => _processando;
  bool get falando => _falando;
  String get textoReconhecido => _textoReconhecido;
  String get ultimaFalaMax => _ultimaFalaMax;

  void atualizarCatalogo(List<ObraAgrupada> catalogo) {}

  Future<void> inicializar() async {
    if (_inicializado) return;
    await MaxMemoryService.instance.inicializar();
    await PedidosScrapeService.instance.inicializar();
    try {
      await _tts.setLanguage('pt-BR');
      await _tts.setPitch(1.03);
      await _tts.setSpeechRate(0.50);
      await _tts.setVolume(1.0);
      _tts.setStartHandler(() { _falando = true; notifyListeners(); });
      _tts.setCompletionHandler(() {
        _falando = false;
        notifyListeners();
        if (_pendenteAbrir != null || _pendentePedidoCatalogo != null) {
          Future.delayed(const Duration(milliseconds: 350), iniciarEscuta);
        }
      });
      _tts.setErrorHandler((_) { _falando = false; notifyListeners(); });
    } catch (_) {}
    _inicializado = true;
  }

  Future<void> falar(String texto) async {
    await inicializar();
    final limpo = texto
        .replaceAll(RegExp(r'rob[oô]\s*scrape?', caseSensitive: false), 'catálogo do CineMax')
        .replaceAll(RegExp(r'roboscrap', caseSensitive: false), 'catálogo do CineMax')
        .trim();
    _ultimaFalaMax = limpo;
    notifyListeners();
    try {
      await _tts.stop();
      await _tts.speak(limpo);
    } catch (_) {}
  }

  Future<void> pararTudo() async {
    _pendenteAbrir = null;
    _pendentePedidoCatalogo = null;
    if (_ouvindo) { await _stt.stop(); _ouvindo = false; }
    await _tts.stop();
    _falando = false;
    _processando = false;
    notifyListeners();
  }

  Future<void> iniciarEscuta() async {
    await inicializar();
    if (_falando) { await _tts.stop(); _falando = false; }

    final ok = await _stt.initialize(
      onStatus: (s) { if (s == 'done' || s == 'notListening') { _ouvindo = false; notifyListeners(); } },
      onError: (_) { _ouvindo = false; notifyListeners(); },
    );
    if (!ok) {
      await falar('Não consegui acessar o microfone agora. Você pode digitar aqui embaixo.');
      return;
    }

    _textoReconhecido = '';
    _ouvindo = true;
    notifyListeners();

    await _stt.listen(
      localeId: 'pt_BR',
      listenMode: ListenMode.confirmation,
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(seconds: 15),
      onResult: (res) async {
        _textoReconhecido = res.recognizedWords;
        notifyListeners();
        if (res.finalResult && _textoReconhecido.trim().isNotEmpty) {
          _ouvindo = false;
          notifyListeners();
          await processarComando(_textoReconhecido.trim());
        }
      },
    );
  }

  Future<void> processarComando(String falaUsuario) async {
    await inicializar();
    _processando = true;
    notifyListeners();

    try {
      final textoLimpo = falaUsuario.trim();
      final confirmouSim = RegExp(
        r'^(sim|pode|pedir|pede|envia|manda|coloca|bota|abre|quero|por favor|claro|adiciona)',
        caseSensitive: false,
      ).hasMatch(textoLimpo);

      if (_pendentePedidoCatalogo != null) {
        final ped = _pendentePedidoCatalogo!;
        _pendentePedidoCatalogo = null;
        if (confirmouSim && (ped.titulo ?? '').isNotEmpty) {
          await PedidosScrapeService.instance.enviarPedido(
            titulo: ped.titulo!,
            tipo: ped.tipoObra ?? 'Filme/Série',
            observacao: 'Pedido feito por voz para a Max',
          );
          await falar('Prontinho! Já solicitei a adição de ${ped.titulo} ao catálogo do CineMax.');
          return;
        }
      }

      if (_pendenteAbrir != null) {
        final abr = _pendenteAbrir!;
        _pendenteAbrir = null;
        if (confirmouSim && (abr.titulo ?? '').isNotEmpty) {
          final acaoExec = MaxAcaoComando(
            tipo: 'abrir_titulo',
            falaResposta: 'Abrindo ${abr.titulo} agora. Boa sessão!',
            titulo: abr.titulo,
          );
          await falar(acaoExec.falaResposta);
          onExecutarAcao?.call(acaoExec);
          return;
        }
      }

      final anonKey = await SupabaseService.getAnonKey();
      final resp = await http
          .post(
            Uri.parse(_brainUrl),
            headers: {
              'Authorization': 'Bearer $anonKey',
              'apikey': anonKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'mensagem': textoLimpo,
              'perfil': MaxMemoryService.instance.nomeAtual,
              'kids': MaxMemoryService.instance.modoKidsAtivo,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final acao = MaxAcaoComando.fromJson(data);
        if (acao.aguardarConfirmacaoPedido && (acao.titulo ?? '').isNotEmpty) {
          _pendentePedidoCatalogo = acao;
        }
        if (acao.aguardarConfirmacaoAbrir && (acao.titulo ?? '').isNotEmpty) {
          _pendenteAbrir = acao;
        }
        await falar(acao.falaResposta);
        if (!['conversa', 'solicitar_adicao'].contains(acao.tipo)) {
          onExecutarAcao?.call(acao);
        }
      } else {
        await falar('Não consegui conectar ao meu servidor agora. Tente novamente em instantes.');
      }
    } catch (_) {
      await falar('A conexão oscilou agora. Pode repetir para mim?');
    } finally {
      _processando = false;
      notifyListeners();
    }
  }
}
