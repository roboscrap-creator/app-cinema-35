import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import '../models/midia_model.dart';
import 'max_cinema_knowledge_service.dart';
import 'max_memory_service.dart';
import 'pedidos_scrape_service.dart';
import 'supabase_service.dart';

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

  List<ObraAgrupada> _catalogoAtual = [];
  bool _inicializado = false;
  bool _ouvindo = false;
  bool _processando = false;
  bool _falando = false;
  String _textoReconhecido = '';
  String _ultimaFalaMax = 'Oi! Eu sou a Max. Pode pedir qualquer filme, série, anime ou ator do CineMax!';
  MaxAcaoComando? _pendenteAbrir;
  MaxAcaoComando? _pendentePedidoCatalogo;

  void Function(MaxAcaoComando acao)? onExecutarAcao;

  bool get ouvindo => _ouvindo;
  bool get processando => _processando;
  bool get falando => _falando;
  String get textoReconhecido => _textoReconhecido;
  String get ultimaFalaMax => _ultimaFalaMax;

  void atualizarCatalogo(List<ObraAgrupada> catalogo) {
    _catalogoAtual = catalogo;
    MaxMemoryService.instance.atualizarConhecimentoCatalogo(
      catalogo.take(80).map((o) => '${o.titulo} (${o.categoria})').toList(),
    );
  }

  Future<void> inicializar() async {
    if (_inicializado) return;
    await MaxMemoryService.instance.inicializar();
    await PedidosScrapeService.instance.inicializar();
    MaxCinemaKnowledgeService.instance.configurarTmdbKey(SupabaseService.tmdbApiKey);
    try {
      await _tts.setLanguage('pt-BR');
      await _tts.setPitch(1.04);
      await _tts.setSpeechRate(0.49);
      await _tts.setVolume(1.0);
      final vozes = await _tts.getVoices;
      if (vozes is List) {
        Map? melhorVoz;
        for (final v in vozes) {
          if (v is Map) {
            final locale = (v['locale'] ?? '').toString().toLowerCase();
            final name = (v['name'] ?? '').toString().toLowerCase();
            if (locale.contains('pt') && locale.contains('br')) {
              if (name.contains('ptd') || name.contains('afs') || name.contains('female') || name.contains('network')) {
                melhorVoz = v;
                if (name.contains('ptd') || name.contains('afs')) break;
              }
            }
          }
        }
        if (melhorVoz != null) {
          await _tts.setVoice({'name': melhorVoz['name'].toString(), 'locale': melhorVoz['locale'].toString()});
        }
      }
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
        .replaceAll(RegExp(r'roboscrap', caseSensitive: false), 'catálogo do CineMax');
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

  ObraAgrupada? _buscarNoCatalogoLivre(String termo) {
    if (_catalogoAtual.isEmpty || termo.trim().length < 2) return null;
    final apelido = MaxMemoryService.instance.buscarApelidoVoz(termo);
    final qNorm = SupabaseService.normalizarTexto((apelido ?? termo).trim());
    if (qNorm.isEmpty) return null;

    for (final o in _catalogoAtual) {
      if (SupabaseService.normalizarTexto(o.titulo) == qNorm ||
          SupabaseService.normalizarTexto(o.tituloOriginal) == qNorm) return o;
    }
    for (final o in _catalogoAtual) {
      final t = SupabaseService.normalizarTexto(o.titulo);
      final orig = SupabaseService.normalizarTexto(o.tituloOriginal);
      if (t.contains(qNorm) || orig.contains(qNorm) || (qNorm.length >= 4 && qNorm.contains(t) && t.length >= 4)) {
        return o;
      }
    }
    return null;
  }

  Future?> _confirmarTituloTmdb(String termo) async {
    try {
      final uri = Uri.parse(
        'https://api.themoviedb.org/3/search/multi?api_key=${SupabaseService.tmdbApiKey}&language=pt-BR&query=${Uri.encodeQueryComponent(termo.trim())}',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final results = (jsonDecode(utf8.decode(resp.bodyBytes))['results'] as List?) ?? [];
        for (final item in results) {
          if (item is Map) {
            final mt = (item['media_type'] ?? '').toString();
            if (mt == 'movie' || mt == 'tv') {
              final tit = (item['title'] ?? item['name'] ?? '').toString().trim();
              if (tit.isNotEmpty) return {'titulo': tit, 'tipo': mt == 'tv' ? 'Série' : 'Filme'};
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> processarComando(String falaUsuario) async {
    await inicializar();
    _processando = true;
    notifyListeners();

    try {
      final textoLimpo = falaUsuario
          .replaceFirst(RegExp(r'^(oi\s+|ol[aá]\s+|ei\s+)?max[,!\s]*', caseSensitive: false), '')
          .trim();

      final nome = MaxMemoryService.instance.nomeAtual;
      final vocativo = (nome.isNotEmpty && nome.toLowerCase() != 'geral') ? ', $nome' : '';

      final confirmouSim = RegExp(
        r'^(sim|pode|pedir|pede|envia|manda|coloca|bota|abre|quero|por favor|com certeza|claro|adiciona)',
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
          await falar('Prontinho$vocativo! Já solicitei a adição de ${ped.titulo} ao catálogo do CineMax.');
          return;
        }
      }

      if (_pendenteAbrir != null) {
        final abr = _pendenteAbrir!;
        _pendenteAbrir = null;
        if (confirmouSim && (abr.titulo ?? '').isNotEmpty) {
          final acaoExec = MaxAcaoComando(
            tipo: 'abrir_titulo',
            falaResposta: 'Com certeza$vocativo! Abrindo ${abr.titulo} agora. Boa sessão!',
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
        await falar('Prazer falar com você, $novoNome! Já ativei seu perfil. O que vamos assistir?');
        return;
      }

      final termoLimpoTitulo = textoLimpo
          .replaceFirst(RegExp(r'^(?:abr[ae]|rod[ae]|coloc[ae]|bot[ae]|assistir|ver|tem|procura|busca)\s+(?:o\s+filme\s+|a\s+s[eé]rie\s+|o\s+anime\s+)?', caseSensitive: false), '')
          .trim();

      final obraCatalogo = _buscarNoCatalogoLivre(termoLimpoTitulo);
      if (obraCatalogo != null) {
        await MaxMemoryService.instance.registrarApelidoVoz(termoLimpoTitulo, obraCatalogo.titulo);
        final pediuAbrirDireto = RegExp(r'^(?:abr[ae]|rod[ae]|coloc[ae]|bot[ae]|assistir|ver)\s+', caseSensitive: false).hasMatch(textoLimpo);
        if (pediuAbrirDireto) {
          final acaoExec = MaxAcaoComando(
            tipo: 'abrir_titulo',
            falaResposta: 'Abrindo ${obraCatalogo.titulo} agora$vocativo! Boa sessão!',
            titulo: obraCatalogo.titulo,
          );
          await falar(acaoExec.falaResposta);
          onExecutarAcao?.call(acaoExec);
          return;
        } else {
          _pendenteAbrir = MaxAcaoComando(tipo: 'abrir_titulo', falaResposta: '', titulo: obraCatalogo.titulo);
          await falar('Encontrei ${obraCatalogo.titulo} na seção ${obraCatalogo.categoria} do CineMax! Quer que eu abra agora?');
          return;
        }
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
      if (acao.aguardarConfirmacaoPedido && (acao.titulo ?? '').isNotEmpty) _pendentePedidoCatalogo = acao;
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
    final cached = MaxMemoryService.instance.buscarCacheResposta(pedido);
    if (cached != null) {
      final parsedCache = _extrairJson(cached);
      if (parsedCache != null) return parsedCache;
    }

    final contextoPerfis = MaxMemoryService.instance.montarResumoContextoIA();
    final promptSistema = '''
Você é a Max, assistente de voz simpática, natural e especialista em cinema do aplicativo CineMax.
Regras:
1. Fale de forma natural, amigável e objetiva em português do Brasil. Nunca seja robótica nem defensiva.
2. NUNCA mencione as palavras "roboscrap", "robo" ou "scrape". Quando um título não estiver no catálogo, ofereça solicitar a adição ao catálogo do CineMax.
3. Elenco/Diretores: fale sobre filmografia e cite o que há no CineMax ("acao": "info_pessoa_cinema", "pessoa_cinema": "...").
4. Navegação: use "abrir_busca", "buscar_termo", "abrir_favoritos", "abrir_todos_filmes", "abrir_todas_series", "abrir_animacoes", "abrir_pedidos", "abrir_titulo", "abrir_episodio", "filtrar_streaming".
5. Título fora do catálogo: confirme o título e pergunte se deseja adicionar ao catálogo do CineMax ("aguardar_confirmacao_pedido": true).
Responda APENAS JSON válido:
{"acao":"...","fala":"...","titulo":null,"titulo_alternativo_catalogo":null,"pessoa_cinema":null,"streaming":null,"tipo_obra":"Filme","temporada":1,"episodio":null,"quantidade":10,"genero":null,"aprendizado":null,"aguardar_confirmacao_abrir":false,"aguardar_confirmacao_pedido":false}

$contextoTmdb
$contextoPerfis
''';

    if (_cloudEndpoint.isNotEmpty) {
      try {
        final resp = await http.post(Uri.parse(_cloudEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'system': promptSistema, 'message': pedido})).timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          final parsed = _extrairJson(resp.body);
          if (parsed != null) return parsed;
        }
      } catch (_) {}
    }

    for (final apiKey in [_embeddedGeminiKey1, _embeddedGeminiKey2]) {
      if (apiKey.isEmpty) continue;
      try {
        final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey');
        final resp = await http.post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'systemInstruction': {'parts': [{'text': promptSistema}]},
              'contents': [{'role': 'user', 'parts': [{'text': pedido}]}],
              'generationConfig': {'temperature': 0.65, 'responseMimeType': 'application/json'}
            })).timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final bodyTxt = jsonDecode(resp.body)['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString() ?? '';
          final parsed = _extrairJson(bodyTxt);
          if (parsed != null) {
            await MaxMemoryService.instance.salvarCacheResposta(pedido, bodyTxt);
            return parsed;
          }
        }
      } catch (_) {}
    }

    return await _interpretarLocalmente(pedido);
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

  Future<MaxAcaoComando> _interpretarLocalmente(String pedido) async {
    final lower = pedido.toLowerCase();
    final nome = MaxMemoryService.instance.nomeAtual;
    final p = (nome.isNotEmpty && nome.toLowerCase() != 'geral') ? 'Claro, $nome! ' : 'Claro! ';

    if (lower.contains('favorito') || lower.contains('histórico') || lower.contains('historico')) {
      return MaxAcaoComando(tipo: 'abrir_favoritos', falaResposta: '${p}Abrindo seus favoritos e histórico!');
    }
    if (lower.contains('pedido')) {
      return MaxAcaoComando(tipo: 'abrir_pedidos', falaResposta: '${p}Abrindo a lista de pedidos do CineMax!');
    }
    if (lower.contains('filmes')) {
      return MaxAcaoComando(tipo: 'abrir_todos_filmes', falaResposta: '${p}Mostrando a seção de filmes!');
    }
    if (lower.contains('séries') || lower.contains('series')) {
      return MaxAcaoComando(tipo: 'abrir_todas_series', falaResposta: '${p}Mostrando a seção de séries!');
    }
    if (lower.contains('anime') || lower.contains('desenho') || lower.contains('kids')) {
      return MaxAcaoComando(tipo: 'abrir_animacoes', falaResposta: '${p}Mostrando animes e animações!');
    }
    if (lower.contains('busca') || lower.contains('pesquis')) {
      final t = pedido.replaceFirst(RegExp(r'^.*?(?:busca|pesquis[ae])\s*(?:por\s+)?', caseSensitive: false), '').trim();
      return t.isEmpty
          ? MaxAcaoComando(tipo: 'abrir_busca', falaResposta: '${p}Abrindo a busca para você!')
          : MaxAcaoComando(tipo: 'buscar_termo', falaResposta: '${p}Buscando por $t!', titulo: t);
    }

    final termoLimpo = pedido
        .replaceFirst(RegExp(r'^(?:abr[ae]|rod[ae]|coloc[ae]|bot[ae]|assistir|ver|tem|quero\s+ver)\s+', caseSensitive: false), '')
        .trim();
    if (termoLimpo.length >= 2) {
      final tmdb = await _confirmarTituloTmdb(termoLimpo);
      if (tmdb != null) {
        final tit = tmdb['titulo']!;
        final tipo = tmdb['tipo']!;
        return MaxAcaoComando(
          tipo: 'solicitar_adicao',
          falaResposta: 'Não encontrei $tit no catálogo do CineMax ainda. Quer que eu peça para adicionar ao catálogo do CineMax?',
          titulo: tit,
          tipoObra: tipo,
          aguardarConfirmacaoPedido: true,
        );
      }
    }

    return MaxAcaoComando(
      tipo: 'conversa',
      falaResposta: '${p}Pode me dizer o nome de qualquer filme, série ou anime que eu procuro no CineMax para você!',
    );
  }
}
