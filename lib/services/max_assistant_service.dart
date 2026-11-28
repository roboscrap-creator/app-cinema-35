// [BLINDADO - IA MAX V3.5] NAO ALTERAR ESTE ARQUIVO SEM AUTORIZACAO EXPRESSA DO PROPRIETARIO.
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

  List<ObraAgrupada> _catalogoMemoria = [];

  void atualizarCatalogo(List<ObraAgrupada> catalogo) {
    if (catalogo.isNotEmpty) {
      _catalogoMemoria = List<ObraAgrupada>.from(catalogo);
    }
  }

  String _norm(String t) {
    var r = t.toLowerCase().trim();
    const ac = "áàâãäéèêëíìîïóòôõöúùûüçñ";
    const sa = "aaaaaeeeeiiiiooooouuuucn";
    for (int i = 0; i < ac.length; i++) {
      r = r.replaceAll(ac[i], sa[i]);
    }
    return r.replaceAll(RegExp(r"[^a-z0-9\s]"), " ").replaceAll(RegExp(r"\s+"), " ").trim();
  }

  Future<ObraAgrupada?> _buscarObraNoCatalogoReal(String termoBruto) async {
    final q = _norm(termoBruto);
    if (q.length < 2) return null;

    if (_catalogoMemoria.isEmpty) {
      try {
        _catalogoMemoria = await SupabaseService.carregarCatalogoAgrupado(limite: 800);
      } catch (_) {}
    }

    ObraAgrupada? acharNaLista(List<ObraAgrupada> lista) {
      for (final o in lista) {
        if (_norm(o.titulo) == q) return o;
      }
      for (final o in lista) {
        final nt = _norm(o.titulo);
        if (nt.contains(q) || (q.length >= 4 && q.contains(nt))) return o;
      }
      return null;
    }

    final local = acharNaLista(_catalogoMemoria);
    if (local != null) return local;

    try {
      final atualizado = await SupabaseService.carregarCatalogoAgrupado(forcarRefresh: true, limite: 1000);
      if (atualizado.isNotEmpty) {
        _catalogoMemoria = atualizado;
        return acharNaLista(_catalogoMemoria);
      }
    } catch (_) {}

    return null;
  }

  Map<String, dynamic> _serializarFichaObra(ObraAgrupada o) {
    final ehSerie = o.isSerieFlag == true ||
        o.categoria.toLowerCase().contains('série') ||
        o.categoria.toLowerCase().contains('serie') ||
        o.categoria.toLowerCase().contains('anime') ||
        o.maxTemporada > 0;
    return {
      'titulo': o.titulo,
      if (o.tituloOriginal.trim().isNotEmpty) 'titulo_original': o.tituloOriginal.trim(),
      'categoria': o.categoria,
      'tipo_validado': ehSerie ? 'Série' : 'Filme',
      if (o.ano.trim().isNotEmpty) 'ano': o.ano.trim(),
      if (o.notaImdb > 0) 'nota_imdb': o.notaImdb,
      if (o.genero.trim().isNotEmpty) 'genero': o.genero.trim(),
      if (o.diretor.trim().isNotEmpty) 'diretor': o.diretor.trim(),
      if (o.elenco.trim().isNotEmpty) 'elenco': o.elenco.trim(),
      if (ehSerie && o.maxTemporada > 0) 'temporadas': o.maxTemporada,
      if (ehSerie && o.maxEpisodio > 0) 'episodios_max': o.maxEpisodio,
      if (o.sinopse.trim().isNotEmpty) 'sinopse_oficial_imdb': o.sinopse.trim(),
      if (o.tmdbId != null) 'tmdb_id': o.tmdbId,
    };
  }

  Future<Map<String, dynamic>?> _consultarFichaOficialImdb({
    required String titulo,
    String? tituloOriginal,
    String? anoEsperado,
    bool? esperarSerie,
  }) async {
    final consultas = <String>[
      if ((tituloOriginal ?? '').trim().isNotEmpty) tituloOriginal!.trim(),
      titulo.trim(),
    ];
    final anoLimpo = RegExp(r'(19|20)\d{2}').firstMatch(anoEsperado ?? '')?.group(0);

    for (final qRaw in consultas) {
      final q = qRaw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (q.length < 2) continue;
      try {
        final slug = Uri.encodeComponent(q.toLowerCase());
        final primeiraLetra = RegExp(r'[a-z0-9]').firstMatch(_norm(q))?.group(0) ?? 'a';
        final sugUrl = Uri.parse('https://v3.sg.media-imdb.com/suggestion/$primeiraLetra/$slug.json');
        final rSug = await http.get(sugUrl, headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 6));
        if (rSug.statusCode != 200) continue;
        final bodySug = jsonDecode(utf8.decode(rSug.bodyBytes));
        final lista = (bodySug is Map ? bodySug['d'] : null);
        if (lista is! List || lista.isEmpty) continue;

        Map<String, dynamic>? melhor;
        int melhorScore = -999;

        for (final item in lista) {
          if (item is! Map) continue;
          final id = (item['id'] ?? '').toString();
          if (!id.startsWith('tt')) continue;
          final nomeItem = (item['l'] ?? '').toString();
          final qid = (item['qid'] ?? '').toString().toLowerCase();
          final yItem = (item['y'] ?? '').toString();
          final ehSerieItem = qid.contains('series') || qid.contains('tvmini');

          int score = 0;
          final nItem = _norm(nomeItem);
          final nBusc = _norm(q);
          if (nItem == nBusc) {
            score += 50;
          } else if (nItem.contains(nBusc) || nBusc.contains(nItem)) {
            score += 25;
          } else {
            continue;
          }
          if (anoLimpo != null && yItem.isNotEmpty) {
            if (yItem == anoLimpo) {
              score += 40;
            } else {
              score -= 30;
            }
          }
          if (esperarSerie != null) {
            score += (ehSerieItem == esperarSerie) ? 25 : -25;
          }
          if (score > melhorScore) {
            melhorScore = score;
            melhor = Map<String, dynamic>.from(item);
          }
        }

        if (melhor == null || melhorScore < 20) continue;
        final imdbId = melhor['id'].toString();
        final tituloImdb = (melhor['l'] ?? q).toString();
        final anoImdb = (melhor['y'] ?? '').toString();
        final qidImdb = (melhor['qid'] ?? '').toString().toLowerCase();
        final ehSerieImdb = qidImdb.contains('series') || qidImdb.contains('tvmini');

        String sinopseImdb = '';
        String notaImdb = '';
        String temporadasImdb = '';

        try {
          final pageResp = await http.get(
            Uri.parse('https://www.imdb.com/title/$imdbId/'),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
              'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8',
            },
          ).timeout(const Duration(seconds: 7));
          if (pageResp.statusCode == 200) {
            final html = utf8.decode(pageResp.bodyBytes, allowMalformed: true);
            final mLd = RegExp(
              r'<script[^>]*type=["\x27]application/ld\+json["\x27][^>]*>(.*?)</script>',
              dotAll: true,
              caseSensitive: false,
            ).firstMatch(html);
            if (mLd != null) {
              final ldJson = jsonDecode(mLd.group(1)!.trim());
              if (ldJson is Map) {
                sinopseImdb = (ldJson['description'] ?? '').toString().trim();
                final agg = ldJson['aggregateRating'];
                if (agg is Map && agg['ratingValue'] != null) {
                  notaImdb = agg['ratingValue'].toString();
                }
              }
            }
            if (ehSerieImdb) {
              final mTemp = RegExp(r'(\d+)\s+(?:temporada|season)s?', caseSensitive: false).firstMatch(html);
              if (mTemp != null) {
                temporadasImdb = mTemp.group(1)!;
              }
            }
          }
        } catch (_) {}

        return {
          'fonte': 'IMDb',
          'imdb_id': imdbId,
          'titulo_imdb': tituloImdb,
          if (anoImdb.isNotEmpty) 'ano_imdb': anoImdb,
          'tipo_imdb': ehSerieImdb ? 'Série' : 'Filme',
          if (notaImdb.isNotEmpty) 'nota_imdb': notaImdb,
          if (temporadasImdb.isNotEmpty) 'temporadas_imdb': temporadasImdb,
          if (sinopseImdb.isNotEmpty) 'sinopse_imdb': sinopseImdb,
          'elenco_principal': (melhor['s'] ?? '').toString(),
        };
      } catch (_) {}
    }
    return null;
  }

  String? _extrairTituloPedidoSinopse(String texto) {
    final m = RegExp(
      r"(?:qual\s+(?:[eé]\s+)?a\s+sinopse|sinopse|sobre\s+o\s+que\s+[eé]|fale\s+sobre|me\s+fale\s+de|me\s+fale\s+sobre|resumo|hist[oó]ria)\s+(?:d[eoas]+\s+)?(?:filme|s[eé]rie|anime|desenho)?\s*(.+)?\$",
      caseSensitive: false,
    ).firstMatch(texto.trim());
    if (m == null) return null;
    final resto = (m.group(1) ?? '').replaceAll(RegExp(r'[?.!]+$'), '').trim();
    if (resto.isEmpty || RegExp(r'^(esse|essa|este|esta|ele|ela|isso|aqui|atual)$', caseSensitive: false).hasMatch(resto)) {
      return _obraEmVisualizacao?.titulo ?? '';
    }
    return resto;
  }

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

  bool _iniciandoEscuta = false;
  int _tentativasAudio = 0;

  Future<void> iniciarEscuta({bool isRetry = false}) async {
    if (_iniciandoEscuta) return;
    _iniciandoEscuta = true;
    try {
      await inicializar();
      if (!isRetry) {
        _tentativasAudio = 0;
      }
      if (_falando) {
        await _tts.stop();
        await _descartarAudioPlayer();
        _falando = false;
      }

      if (_ouvindo) {
        try {
          await _stt.stop();
        } catch (_) {}
        _ouvindo = false;
      }
      await Future.delayed(Duration(milliseconds: isRetry ? 900 : 350));

      bool ok = false;
      try {
        ok = await _stt.initialize(
          onStatus: (st) {
            if (st == 'done' || st == 'notListening') {
              if (_ouvindo) {
                _ouvindo = false;
                notifyListeners();
              }
            }
          },
          onError: (err) {
            final msg = err.errorMsg.toLowerCase();
            _ouvindo = false;
            if (msg.contains('no_match') || msg.contains('speech_timeout')) {
              notifyListeners();
              return;
            }
            if ((msg.contains('audio') || msg.contains('busy') || msg.contains('client')) &&
                _tentativasAudio < 2) {
              _tentativasAudio++;
              _ultimaFalaMax = 'Ativando microfone do controle...';
              notifyListeners();
              Future.delayed(const Duration(milliseconds: 900), () {
                iniciarEscuta(isRetry: true);
              });
              return;
            }
            _ultimaFalaMax = 'Use o botão de voz do controle no campo abaixo ou clique no microfone.';
            notifyListeners();
          },
        );
      } catch (_) {
        ok = false;
      }

      if (!ok) {
        _ouvindo = false;
        _ultimaFalaMax = 'Selecione a caixa abaixo e aperte o microfone do controle remoto para falar.';
        notifyListeners();
        return;
      }

      _textoReconhecido = '';
      _ouvindo = true;
      notifyListeners();

      await _stt.listen(
        localeId: 'pt_BR',
        listenMode: ListenMode.confirmation,
        partialResults: true,
        cancelOnError: false,
        pauseFor: const Duration(seconds: 5),
        listenFor: const Duration(seconds: 25),
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
    } finally {
      _iniciandoEscuta = false;
    }
  }

  Future<void> processarComando(String falaUsuario) async {
    /* PATCH_MAX_CATALOGO_IMDB */
    final qLow = falaUsuario.toLowerCase();
    if (qLow.contains('sinopse') || qLow.contains('sobre o que') || qLow.contains('história') || qLow.contains('historia') || qLow.contains('filme') || qLow.contains('série') || qLow.contains('serie')) {
      final limpo = falaUsuario
          .replaceAll(RegExp(r'\b(qual|é|a|o|do|da|de|sinopse|filme|série|serie|me|fala|sobre)\b', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (limpo.length >= 2) {
        final ficha = await _consultarFichaOficialImdb(titulo: tituloSinopse);
        if (ficha != null && (ficha['sinopse'] ?? '').toString().trim().isNotEmpty) {
          final tit = (ficha['titulo'] ?? limpo).toString();
          final sin = ficha['sinopse'].toString().trim();
          final ano = ficha['ano'] != null ? ' (${ficha['ano']})' : '';
      return;
          return;
        }
      }
    }

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

      final mAbrir = RegExp(
        r"^(?:max[,\s]*)?(?:por favor[,\s]*)?(?:abr[ae]|coloc[ae]|bot[ae]|toc[ae]|inici[ae]|reproduz[ae]?|assistir|ver|quero ver|quero assistir|procur[ae]|busc[ae]|encontr[ae]|tem|voc[eê] tem)\s+(?:o\s+|a\s+|os\s+|as\s+)?(?:filme|s[eé]rie|anime|desenho|novela)?\s*(.+)\$",
        caseSensitive: false,
      ).firstMatch(textoLimpo);

      if (mAbrir != null) {
        final termo = (mAbrir.group(1) ?? "").replaceAll(RegExp(r"[?.!]+$"), "").trim();
        if (termo.length >= 2) {
          final achada = await _buscarObraNoCatalogoReal(termo);
          if (achada != null) {
            final acaoDireta = MaxAcaoComando(
              tipo: 'abrir_titulo',
              falaResposta: 'Abrindo ${achada.titulo} agora. Boa sessão!',
              titulo: achada.titulo,
              tipoObra: achada.categoria,
            );
            _historicoDialogo.add({'role': 'assistant', 'content': acaoDireta.falaResposta});
            await falar(acaoDireta.falaResposta);
            onExecutarAcao?.call(acaoDireta);
            return;
          }
        }
      }
      if (_historicoDialogo.length > 20) {
        _historicoDialogo.removeRange(0, _historicoDialogo.length - 20);
      }

      if (_catalogoMemoria.isEmpty) {
        try {
          _catalogoMemoria = await SupabaseService.carregarCatalogoAgrupado(limite: 1000);
        } catch (_) {}
      }

      final tituloSinopse = _extrairTituloPedidoSinopse(textoLimpo);
      ObraAgrupada? obraAlvoSinopse;
      if (tituloSinopse != null) {
        if (_obraEmVisualizacao != null &&
            (tituloSinopse.isEmpty ||
                _norm(_obraEmVisualizacao!.titulo).contains(_norm(tituloSinopse)) ||
                _norm(tituloSinopse).contains(_norm(_obraEmVisualizacao!.titulo)))) {
          obraAlvoSinopse = _obraEmVisualizacao;
        } else if (tituloSinopse.isNotEmpty) {
          obraAlvoSinopse = await _buscarObraNoCatalogoReal(tituloSinopse);
        }
      }

      Map<String, dynamic>? fichaImdbValidada;
      if (obraAlvoSinopse != null) {
        final ehSerieObra = obraAlvoSinopse.isSerieFlag == true ||
            obraAlvoSinopse.categoria.toLowerCase().contains('série') ||
            obraAlvoSinopse.categoria.toLowerCase().contains('serie') ||
            obraAlvoSinopse.maxTemporada > 0;
        fichaImdbValidada = await _consultarFichaOficialImdb(
          titulo: obraAlvoSinopse.titulo,
          tituloOriginal: obraAlvoSinopse.tituloOriginal,
          anoEsperado: obraAlvoSinopse.ano,
          esperarSerie: ehSerieObra,
        );
      } else if (tituloSinopse != null && tituloSinopse.isNotEmpty) {
        fichaImdbValidada = await _consultarFichaOficialImdb(titulo: tituloSinopse);
      } else if (_obraEmVisualizacao != null) {
        fichaImdbValidada = await _consultarFichaOficialImdb(
          titulo: _obraEmVisualizacao!.titulo,
          tituloOriginal: _obraEmVisualizacao!.tituloOriginal,
          anoEsperado: _obraEmVisualizacao!.ano,
        );
      }

      final catalogoEspelho = _catalogoMemoria
          .map((o) => {
                'titulo': o.titulo,
                if (o.tituloOriginal.trim().isNotEmpty) 'titulo_original': o.tituloOriginal.trim(),
                'categoria': o.categoria,
                if (o.ano.trim().isNotEmpty) 'ano': o.ano.trim(),
                if (o.notaImdb > 0) 'nota_imdb': o.notaImdb,
                if (o.maxTemporada > 0) 'temporadas': o.maxTemporada,
                if (o.sinopse.trim().isNotEmpty) 'sinopse': o.sinopse.trim(),
                if (o.tmdbId != null) 'tmdb_id': o.tmdbId,
              })
          .toList();

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
              'modo_livre': true,
              'pesquisa_web_ativa': true,
              'historico': _historicoDialogo,
              'tela_atual': _telaAtual,
              'aba_atual': _abaAtual,
              'fonte_obrigatoria_sinopse': 'IMDb',
              'regra_anti_alucinacao': 'NUNCA invente ou crie sinopse propria. Use EXCLUSIVAMENTE os dados reais de ficha_imdb_validada, obra_consultada ou obra_atual (conferindo titulo exato, ano exato, tipo filme/serie e temporadas do IMDb). Se nao houver sinopse real confirmada no IMDb/catalogo para aquele titulo e ano exatos, diga claramente que nao encontrou a sinopse oficial no IMDb.',
              'catalogo_disponivel': catalogoEspelho,
              if (obraAlvoSinopse != null) 'obra_consultada': _serializarFichaObra(obraAlvoSinopse),
              if (fichaImdbValidada != null) 'ficha_imdb_validada': fichaImdbValidada,
              if (_obraEmVisualizacao != null)
                'obra_atual': _serializarFichaObra(_obraEmVisualizacao!),
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        final acao = MaxAcaoComando.fromJson(data);
        _historicoDialogo.add({'role': 'assistant', 'content': acao.falaResposta});
        if ((acao.aguardarConfirmacaoPedido || acao.tipo == 'solicitar_adicao') && (acao.titulo ?? '').isNotEmpty) {
          final achadaNuvem = await _buscarObraNoCatalogoReal(acao.titulo!);
          if (achadaNuvem != null) {
            final acaoCorrigida = MaxAcaoComando(
              tipo: 'abrir_titulo',
              falaResposta: 'Achei no nosso catálogo! Abrindo ${achadaNuvem.titulo} agora. Boa sessão!',
              titulo: achadaNuvem.titulo,
              tipoObra: achadaNuvem.categoria,
            );
            _historicoDialogo.add({'role': 'assistant', 'content': acaoCorrigida.falaResposta});
            await falar(acaoCorrigida.falaResposta);
            onExecutarAcao?.call(acaoCorrigida);
            return;
          }
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
