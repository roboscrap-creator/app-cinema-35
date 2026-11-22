import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'max_cinema_knowledge_service.dart';
import 'max_memory_service.dart';
import 'pedidos_scrape_service.dart';

class MaxAcaoComando {
  final String tipo;
  final String falaResposta;
  final String? titulo;
  final String? tituloAlternativoCatalogo;
  final String? pessoaCinema;
  final String? streamingPlataforma;
  final String? tipoObra;
  final int? temporada;
  final int? episodio;
  final int? quantidade;
  final String? genero;
  final String? aprendizadoNota;
  final bool aguardarConfirmacaoAbrir;
  final bool aguardarConfirmacaoPedido;

  const MaxAcaoComando({
    required this.tipo,
    required this.falaResposta,
    this.titulo,
    this.tituloAlternativoCatalogo,
    this.pessoaCinema,
    this.streamingPlataforma,
    this.tipoObra,
    this.temporada,
    this.episodio,
    this.quantidade,
    this.genero,
    this.aprendizadoNota,
    this.aguardarConfirmacaoAbrir = false,
    this.aguardarConfirmacaoPedido = false,
  });

  factory MaxAcaoComando.fromJson(Map<String, dynamic> json) {
    return MaxAcaoComando(
      tipo: (json['acao'] ?? 'conversa').toString(),
      falaResposta: (json['fala'] ?? 'Prontinho! Já estou vendo isso para você.').toString(),
      titulo: json['titulo']?.toString(),
      tituloAlternativoCatalogo: json['titulo_alternativo_catalogo']?.toString(),
      pessoaCinema: json['pessoa_cinema']?.toString(),
      streamingPlataforma: json['streaming']?.toString(),
      tipoObra: json['tipo_obra']?.toString(),
      temporada: json['temporada'] is int ? json['temporada'] : int.tryParse(json['temporada']?.toString() ?? ''),
      episodio: json['episodio'] is int ? json['episodio'] : int.tryParse(json['episodio']?.toString() ?? ''),
      quantidade: json['quantidade'] is int ? json['quantidade'] : int.tryParse(json['quantidade']?.toString() ?? ''),
      genero: json['genero']?.toString(),
      aprendizadoNota: json['aprendizado']?.toString(),
      aguardarConfirmacaoAbrir: json['aguardar_confirmacao_abrir'] == true,
      aguardarConfirmacaoPedido: json['aguardar_confirmacao_pedido'] == true,
    );
  }
}

class MaxAssistantService extends ChangeNotifier {
  static final MaxAssistantService instance = MaxAssistantService._();
  MaxAssistantService._();

  static const String _cloudEndpoint = String.fromEnvironment('MAX_CLOUD_URL', defaultValue: '');
  static const String _embeddedGeminiKey1 = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String _embeddedGeminiKey2 = String.fromEnvironment('GEMINI_API_KEY_2', defaultValue: '');

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _inicializado = false;
  bool _ouvindo = false;
  bool _processando = false;
  bool _falando = false;
  String _textoReconhecido = '';
  String _ultimaFalaMax = 'Oi! Eu sou a Max. Peça qualquer filme, série, ator, diretor ou catálogo do CineMax!';
  MaxAcaoComando? _pendenteAbrir;
  MaxAcaoComando? _pendentePedidoScrape;

  void Function(MaxAcaoComando acao)? onExecutarAcao;

  bool get ouvindo => _ouvindo;
  bool get processando => _processando;
  bool get falando => _falando;
  String get textoReconhecido => _textoReconhecido;
  String get ultimaFalaMax => _ultimaFalaMax;

  Future<void> inicializar() async {
    if (_inicializado) return;
    await MaxMemoryService.instance.inicializar();
    await PedidosScrapeService.instance.inicializar();
    try {
      await _tts.setLanguage('pt-BR');
      await _tts.setPitch(1.08);
      await _tts.setSpeechRate(0.52);
      await _tts.setVolume(1.0);
      final vozes = await _tts.getVoices;
      if (vozes is List) {
        for (final v in vozes) {
          if (v is Map) {
            final locale = (v['locale'] ?? '').toString().toLowerCase();
            final name = (v['name'] ?? '').toString().toLowerCase();
            if (locale.contains('pt') &&
                (name.contains('female') || name.contains('fem') || name.contains('ptd') || name.contains('afs'))) {
              await _tts.setVoice({'name': v['name'].toString(), 'locale': v['locale'].toString()});
              break;
            }
          }
        }
      }
      _tts.setStartHandler(() { _falando = true; notifyListeners(); });
      _tts.setCompletionHandler(() {
        _falando = false;
        notifyListeners();
        if (_pendenteAbrir != null || _pendentePedidoScrape != null) {
          Future.delayed(const Duration(milliseconds: 350), iniciarEscuta);
        }
      });
      _tts.setErrorHandler((_) { _falando = false; notifyListeners(); });
    } catch (_) {}
    _inicializado = true;
  }

  Future<void> falar(String texto) async {
    await inicializar();
    _ultimaFalaMax = texto;
    notifyListeners();
    try {
      await _tts.stop();
      await _tts.speak(texto);
    } catch (_) {}
  }

  Future<void> pararTudo() async {
    _pendenteAbrir = null;
    _pendentePedidoScrape = null;
    if (_ouvindo) { await _stt.stop(); _ouvindo = false; }
    await _tts.stop();
    _falando = false;
    _processando = false;
    notifyListeners();
  }

  Future<void> iniciarEscuta() async {
    await inicializar();
    if (_falando) { await _tts.stop(); _falando = false; }

    final disponivel = await _stt.initialize(
      onStatus: (s) { if (s == 'done' || s == 'notListening') { _ouvindo = false; notifyListeners(); } },
      onError: (_) { _ouvindo = false; notifyListeners(); },
    );

    if (!disponivel) {
      await falar('Não consegui acessar o microfone agora. Você pode digitar seu pedido aqui!');
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
      onResult: (result) async {
        _textoReconhecido = result.recognizedWords;
        notifyListeners();
        if (result.finalResult && _textoReconhecido.trim().isNotEmpty) {
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
      final textoLimpo = falaUsuario
          .replaceFirst(RegExp(r'^(oi\s+|olá\s+|ei\s+)?max[,!\s]*', caseSensitive: false), '')
          .trim();

      final confirmouSim = RegExp(
        r'^(sim|pode|pedir|pede|envia|manda|coloca|bota|abre|quero|por favor|com certeza|claro)',
        caseSensitive: false,
      ).hasMatch(textoLimpo);

      if (_pendentePedidoScrape != null) {
        final ped = _pendentePedidoScrape!;
        _pendentePedidoScrape = null;
        if (confirmouSim && (ped.titulo ?? '').isNotEmpty) {
          await PedidosScrapeService.instance.enviarPedido(
            titulo: ped.titulo!,
            tipo: ped.tipoObra ?? 'Filme/Série',
            observacao: 'Pedido feito por voz para a Max',
          );
          final nome = MaxMemoryService.instance.nomeAtual;
          await falar('${nome.isNotEmpty ? "Prontinho, $nome!" : "Prontinho!"} Já mandei ${ped.titulo} para a fila do nosso robô!');
          return;
        }
      }

      if (_pendenteAbrir != null) {
        final abr = _pendenteAbrir!;
        _pendenteAbrir = null;
        if (confirmouSim && (abr.titulo ?? '').isNotEmpty) {
          final nome = MaxMemoryService.instance.nomeAtual;
          final acaoExec = MaxAcaoComando(
            tipo: 'abrir_titulo',
            falaResposta: '${nome.isNotEmpty ? "Com certeza, $nome!" : "Com certeza!"} Abrindo ${abr.titulo} agora. Boa sessão!',
            titulo: abr.titulo,
          );
          await falar(acaoExec.falaResposta);
          onExecutarAcao?.call(acaoExec);
          return;
        }
      }

      final matchPerfil = RegExp(
        r'(?:eu\s+sou\s+(?:o|a)\s+|aqui\s+[eé]\s+(?:o|a)\s+|meu\s+nome\s+[eé]\s+)([A-Za-zÀ-ÿ\s]{2,25})',
        caseSensitive: false,
      ).firstMatch(textoLimpo);
      if (matchPerfil != null) {
        final novoNome = matchPerfil.group(1)!.trim();
        await MaxMemoryService.instance.definirPerfilAtivo(novoNome);
        await falar('Prazer falar com você, $novoNome! Já salvei seu perfil. O que vamos assistir?');
        return;
      }

      String contextoTmdbPessoa = '';
      final matchPessoa = RegExp(
        r'(?:ator|atriz|diretor|diretora|sobre\s+o|sobre\s+a|quem\s+[eé]|filmes\s+d[oe]|s[eé]ries\s+d[oe])\s+([A-Za-zÀ-ÿ\s]{3,35})',
        caseSensitive: false,
      ).firstMatch(textoLimpo);
      if (matchPessoa != null) {
        contextoTmdbPessoa = await MaxCinemaKnowledgeService.instance
            .buscarContextoPessoaTmdb(matchPessoa.group(1)!.trim());
      }

      final acao = await _consultarIAOuFallback(textoLimpo, contextoTmdbPessoa);

      if ((acao.aprendizadoNota ?? '').isNotEmpty) {
        await MaxMemoryService.instance.registrarAprendizado(acao.aprendizadoNota!);
      }
      if (acao.aguardarConfirmacaoPedido && (acao.titulo ?? '').isNotEmpty) _pendentePedidoScrape = acao;
      if (acao.aguardarConfirmacaoAbrir) {
        final alvo = (acao.tituloAlternativoCatalogo ?? '').isNotEmpty
            ? acao.tituloAlternativoCatalogo
            : (acao.titulo ?? acao.pessoaCinema);
        if ((alvo ?? '').isNotEmpty) _pendenteAbrir = MaxAcaoComando(tipo: 'abrir_titulo', falaResposta: '', titulo: alvo);
      }
      if (acao.tipo == 'solicitar_adicao' && (acao.titulo ?? '').isNotEmpty && !acao.aguardarConfirmacaoPedido) {
        await PedidosScrapeService.instance.enviarPedido(titulo: acao.titulo!, tipo: acao.tipoObra ?? 'Filme/Série');
      }
      if ((acao.titulo ?? '').isNotEmpty && (acao.tipo == 'abrir_titulo' || acao.tipo == 'abrir_episodio')) {
        await MaxMemoryService.instance.registrarVisualizacao(
          titulo: acao.titulo!,
          ehSerie: acao.tipo == 'abrir_episodio' || acao.episodio != null,
          temporada: acao.temporada,
          episodio: acao.episodio,
        );
      }

      await falar(acao.falaResposta);
      if (!['conversa', 'sinopse', 'fora_tema', 'solicitar_adicao'].contains(acao.tipo)) {
        onExecutarAcao?.call(acao);
      }
    } finally {
      _processando = false;
      notifyListeners();
    }
  }

  Future<MaxAcaoComando> _consultarIAOuFallback(String pedido, String contextoTmdb) async {
    final contextoPerfis = MaxMemoryService.instance.montarResumoContextoIA();
    final promptSistema = '''
Você é a Max, assistente feminina alegre, cordial e especialista em cinema do CineMax.
Regras:
1. Assuntos fora de cinema/séries/atores/app: brinque com humor dizendo que está tentando te distrair do serviço e volte para o cinema ("acao": "fora_tema").
2. Elenco/Diretores: fale sobre filmografia, Oscars/prêmios, estilo ("Mestre do Suspense", etc.) e cite o que há no CineMax ("acao": "info_pessoa_cinema", "pessoa_cinema": "...").
3. Navegação total: use "abrir_busca", "buscar_termo", "abrir_favoritos", "abrir_todos_filmes", "abrir_todas_series", "abrir_animacoes", "lancamentos_hoje", "top_10_series", "top_10_filmes", "top_imdb", "top_tmdb", "em_alta", "filtrar_streaming" ("streaming": "Netflix"|"Paramount"|"HBO"|"Prime Video"|"Disney"|"Apple TV"|"Globoplay"), "abrir_pedidos", "abrir_titulo", "abrir_episodio".
4. Título fora do catálogo: conte a premissa sem spoilers, recomende um parecido do catálogo ("titulo_alternativo_catalogo") e pergunte se pode pedir ao robô ("aguardar_confirmacao_pedido": true).
5. Sinopse sem spoilers: explique em até 3 frases sem estragar o final e pergunte se quer rodar ("aguardar_confirmacao_abrir": true).
Responda APENAS JSON válido:
{"acao":"...","fala":"...","titulo":null,"titulo_alternativo_catalogo":null,"pessoa_cinema":null,"streaming":null,"tipo_obra":"Filme","temporada":1,"episodio":null,"quantidade":10,"genero":null,"aprendizado":null,"aguardar_confirmacao_abrir":false,"aguardar_confirmacao_pedido":false}

$contextoTmdb
$contextoPerfis
''';

    if (_cloudEndpoint.isNotEmpty) {
      try {
        final resp = await http
            .post(Uri.parse(_cloudEndpoint),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'system': promptSistema, 'message': pedido}))
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final parsed = _extrairJson(resp.body);
          if (parsed != null) return parsed;
        }
      } catch (_) {}
    }

    for (final apiKey in [_embeddedGeminiKey1, _embeddedGeminiKey2]) {
      if (apiKey.isEmpty) continue;
      try {
        final uri = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey');
        final resp = await http
            .post(uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'systemInstruction': {'parts': [{'text': promptSistema}]},
                  'contents': [{'role': 'user', 'parts': [{'text': pedido}]}],
                  'generationConfig': {'temperature': 0.75, 'responseMimeType': 'application/json'}
                }))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final bodyTxt = jsonDecode(resp.body)['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString() ?? '';
          final parsed = _extrairJson(bodyTxt);
          if (parsed != null) return parsed;
        }
      } catch (_) {}
    }

    return _interpretarLocalmente(pedido);
  }

  MaxAcaoComando? _extrairJson(String raw) {
    try {
      final limpo = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final i = limpo.indexOf('{');
      final f = limpo.lastIndexOf('}');
      if (i == -1 || f == -1) return null;
      return MaxAcaoComando.fromJson(jsonDecode(limpo.substring(i, f + 1)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  MaxAcaoComando _interpretarLocalmente(String pedido) {
    final lower = pedido.toLowerCase();
    final nome = MaxMemoryService.instance.nomeAtual;
    final p = nome.isNotEmpty ? 'Claro, $nome! ' : 'Claro! ';

    if (lower.contains('favorito')) return MaxAcaoComando(tipo: 'abrir_favoritos', falaResposta: '${p}Abrindo seus favoritos!');
    if (lower.contains('pedido')) return MaxAcaoComando(tipo: 'abrir_pedidos', falaResposta: '${p}Abrindo a aba de pedidos!');
    if (lower.contains('busca') || lower.contains('pesquis')) {
      final t = pedido.replaceFirst(RegExp(r'^.*?(?:busca|pesquis[ae])\s*(?:por\s+)?', caseSensitive: false), '').trim();
      return t.isEmpty
          ? MaxAcaoComando(tipo: 'abrir_busca', falaResposta: '${p}Abrindo a busca para você!')
          : MaxAcaoComando(tipo: 'buscar_termo', falaResposta: '${p}Buscando por $t!', titulo: t);
    }
    for (final s in {'netflix': 'Netflix', 'paramount': 'Paramount', 'hbo': 'HBO', 'prime': 'Prime Video', 'disney': 'Disney'}.entries) {
      if (lower.contains(s.key)) {
        return MaxAcaoComando(tipo: 'filtrar_streaming', falaResposta: '${p}Mostrando títulos da ${s.value}!', streamingPlataforma: s.value);
      }
    }
    final abrir = RegExp(r'(?:abr[ae]|rod[ae]|coloc[ae]|bot[ae]|assistir)\s+(.+)', caseSensitive: false).firstMatch(pedido);
    if (abrir != null) {
      final tit = abrir.group(1)!.trim();
      return MaxAcaoComando(tipo: 'abrir_titulo', falaResposta: '${p}Abrindo $tit para você!', titulo: tit);
    }
    return const MaxAcaoComando(
      tipo: 'fora_tema',
      falaResposta: 'Haha, engraçadinho! Tá tentando me distrair do serviço, né? Aqui no CineMax eu só falo de cinema e séries! Me pede um filme que eu abro agora!',
    );
  }
}
