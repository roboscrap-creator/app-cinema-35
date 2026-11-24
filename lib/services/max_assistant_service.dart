import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
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
  final String? audioBase64;
  final bool aguardarConfirmacaoAbrir;
  final bool aguardarConfirmacaoPedido;

  const MaxAcaoComando({
    required this.tipo,
    required this.falaResposta,
    this.titulo,
    this.tipoObra,
    this.audioBase64,
    this.aguardarConfirmacaoAbrir = false,
    this.aguardarConfirmacaoPedido = false,
  });

  factory MaxAcaoComando.fromJson(Map<String, dynamic> json) {
    return MaxAcaoComando(
      tipo: (json['acao'] ?? 'conversa').toString(),
      falaResposta: (json['fala'] ?? 'Prontinho!').toString(),
      titulo: json['titulo']?.toString(),
      tipoObra: json['tipo_obra']?.toString(),
      audioBase64: json['audio_base64']?.toString(),
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
  Player? _audioPlayer;

  bool _inicializado = false;
  bool _ouvindo = false;
  bool _processando = false;
  bool _falando = false;
  String _textoReconhecido = '';
  String _ultimaFalaMax = 'Oi! Toque no microfone e me peça qualquer filme, série ou anime.';
  MaxAcaoComando? _pendenteAbrir;
  MaxAcaoComando? _pendentePedidoCatalogo;
  ObraAgrupada? _obraEmVisualizacao;

  String _telaAtual = 'home';
  String _abaAtual = 'Início';
  void definirContextoTela({String? tela, String? aba}) { if (tela != null) _telaAtual = tela; if (aba != null) _abaAtual = aba; }
  void definirObraEmVisualizacao(ObraAgrupada? obra) { _obraEmVisualizacao = obra; _telaAtual = obra != null ? 'detalhe_obra' : 'home'; }
  final List<Map<String, String>> _historicoDialogo = [];

  void Function(MaxAcaoComando acao)? onExecutarAcao;

  bool get ouvindo => _ouvindo;
  bool get processando => _processando;
  bool get falando => _falando;
  String get textoReconhecido => _textoReconhecido;
  String get ultimaFalaMax => _ultimaFalaMax;

  void atualizarCatalogo(List<ObraAgrupada> catalogo) {}

  void _aoTerminarFala() {
    _falando = false;
    notifyListeners();
    if (_pendenteAbrir != null || _pendentePedidoCatalogo != null) {
      Future.delayed(const Duration(milliseconds: 350), iniciarEscuta);
    }
  }

  Future<void> inicializar() async {
    if (_inicializado) return;
    await MaxMemoryService.instance.inicializar();
    await PedidosScrapeService.instance.inicializar();
    try {
      await _tts.setLanguage('pt-BR');
      try {
        final voices = await _tts.getVoices;
        if (voices is List) {
          Map<String, String>? melhorVoz;
          for (final v in voices) {
            if (v is Map) {
              final locale = (v['locale'] ?? '').toString().toLowerCase();
              final name = (v['name'] ?? '').toString().toLowerCase();
              if (locale.contains('pt-br') || locale.contains('pt_br')) {
                if (name.contains('neural') || name.contains('wavenet') || name.contains('enhanced') || name.contains('pt-br-x-ptd') || name.contains('pt-br-x-afs')) {
                  melhorVoz = {'name': v['name'].toString(), 'locale': v['locale'].toString()};
                  break;
                }
                melhorVoz ??= {'name': v['name'].toString(), 'locale': v['locale'].toString()};
              }
            }
          }
          if (melhorVoz != null) {
            await _tts.setVoice(melhorVoz);
          }
        }
      } catch (_) {}
      await _tts.setPitch(1.05);
      await _tts.setSpeechRate(0.53);
      await _tts.setVolume(1.0);
      _tts.setStartHandler(() { _falando = true; notifyListeners(); });
      _tts.setCompletionHandler(_aoTerminarFala);
      _tts.setErrorHandler((_) { _falando = false; notifyListeners(); });

    } catch (_) {}
    _inicializado = true;
  }

  Future<void> falar(String texto, {String? audioBase64}) async {
    await inicializar();
    final limpo = texto
        .replaceAll(RegExp(r'rob[oô]\s*scrape?', caseSensitive: false), 'catálogo do CineMax')
        .replaceAll(RegExp(r'roboscrap', caseSensitive: false), 'catálogo do CineMax')
        .replaceAll(RegExp(r'[*_#`~]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    _ultimaFalaMax = limpo;
    notifyListeners();

    try {
      await _tts.stop();
      await _descartarAudioPlayer();

      if (audioBase64 != null && audioBase64.isNotEmpty) {
        final bytes = base64Decode(audioBase64);
        final file = File('${Directory.systemTemp.path}/max_voz_neural.mp3');
        await file.writeAsBytes(bytes, flush: true);
        final p = Player();
        _audioPlayer = p;
        p.stream.completed.listen((done) {
          if (done && _falando) {
            _descartarAudioPlayer();
            _aoTerminarFala();
          }
        });
        _falando = true;
        notifyListeners();
        await p.open(Media(file.path), play: true);
        return;
      }

      await _tts.speak(limpo);
    } catch (_) {
      try {
        await _tts.speak(limpo);
      } catch (_) {
        _falando = false;
        notifyListeners();
      }
    }
  }

  Future<void> pararTudo() async {
    _pendenteAbrir = null;
    _pendentePedidoCatalogo = null;
    if (_ouvindo) { await _stt.stop(); _ouvindo = false; }
    await _tts.stop();
    await _descartarAudioPlayer();
    _falando = false;
    _processando = false;
    notifyListeners();
  }

  Future<void> iniciarEscuta() async {
    await inicializar();
    if (_falando) {
      await _tts.stop();
      await _descartarAudioPlayer();
      _falando = false;
    }

    bool ok = false;
    try {
      ok = await _stt.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            _ouvindo = false;
            notifyListeners();
          }
        },
        onError: (err) {
          _ouvindo = false;
          _ultimaFalaMax = 'Não captei áudio (${err.errorMsg}). Toque no microfone de novo ou digite abaixo.';
          notifyListeners();
        },
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      _ouvindo = false;
      _ultimaFalaMax = 'Microfone indisponível neste aparelho. Digite abaixo ou use a tecla de voz do controle.';
      notifyListeners();
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

      _historicoDialogo.add({'role': 'user', 'content': textoLimpo});
      if (_historicoDialogo.length > 8) {
        _historicoDialogo.removeRange(0, _historicoDialogo.length - 8);
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
              'historico': _historicoDialogo, 'tela_atual': _telaAtual, 'aba_atual': _abaAtual,
              if (_obraEmVisualizacao != null)
                'obra_atual': {
                  'titulo': _obraEmVisualizacao!.titulo,
                  'categoria': _obraEmVisualizacao!.categoria,
                  'genero': _obraEmVisualizacao!.genero,
                  'ano': _obraEmVisualizacao!.ano,
                  'diretor': _obraEmVisualizacao!.diretor,
                  'elenco': _obraEmVisualizacao!.elenco,
                  'sinopse': _obraEmVisualizacao!.sinopse,
                  'nota_imdb': _obraEmVisualizacao!.notaImdb,
                },
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final acao = MaxAcaoComando.fromJson(data);
        _historicoDialogo.add({'role': 'assistant', 'content': acao.falaResposta});
        if (acao.aguardarConfirmacaoPedido && (acao.titulo ?? '').isNotEmpty) {
          _pendentePedidoCatalogo = acao;
        }
        if (acao.aguardarConfirmacaoAbrir && (acao.titulo ?? '').isNotEmpty) {
          _pendenteAbrir = acao;
        }
        await falar(acao.falaResposta, audioBase64: acao.audioBase64);
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

  Future<void> _descartarAudioPlayer() async {
    final p = _audioPlayer;
    _audioPlayer = null;
    if (p != null) {
      try {
        await p.stop();
        await p.dispose();
      } catch (_) {}
    }
  }

}
