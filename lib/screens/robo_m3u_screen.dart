import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RoboM3uScreen extends StatefulWidget {
  final VoidCallback onAtualizarCatalogo;
  final void Function({
    required String urlStream,
    String? tituloSugerido,
    String? categoriaSugerida,
    String? qualidadeSugerida,
    String? audioSugerido,
  }) onPublicarLink;

  const RoboM3uScreen({
    super.key,
    required this.onAtualizarCatalogo,
    required this.onPublicarLink,
  });

  @override
  State<RoboM3uScreen> createState() => _RoboM3uScreenState();
}

class _RoboM3uScreenState extends State<RoboM3uScreen> {
  final _backendCtrl = TextEditingController(text: 'https://roboscrap-backend-l9t8.onrender.com');
  final _m3uUrlCtrl = TextEditingController();
  final _limiteCtrl = TextEditingController(text: '25');
  final _siteUrlCtrl = TextEditingController();
  final _buscaCtrl = TextEditingController();
  final _loteUrlCtrl = TextEditingController();
  final _loteQtdCtrl = TextEditingController(text: '100');
  final _loteFiltroCtrl = TextEditingController();
  bool _autoAprovarTmdb = true;

  bool _ocupado = false;
  String _statusServidor = 'Toque em Testar Conexão';
  Color _corStatus = Colors.grey;
  String _logExecucao = '';
  List<Map<String, dynamic>> _streamsExtraidosSite = [];
  List<dynamic> _resultadosBusca = [];
  Set<String> _selecionados = {};
  Set<String> _publicadosSessao = {};

  @override
  void initState() {
    super.initState();
    _carregarPrefs();
  }

  Future<void> _carregarPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final salvosJson = prefs.getString('robo_streams_salvos') ?? '[]';
    final pubsJson = prefs.getString('robo_publicados_salvos') ?? '[]';
    List<Map<String, dynamic>> listaSalva = [];
    try {
      final decoded = jsonDecode(salvosJson) as List;
      listaSalva = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}

    Set<String> pubsSalvos = {};
    try {
      pubsSalvos = (jsonDecode(pubsJson) as List).map((e) => e.toString()).toSet();
    } catch (_) {}

    setState(() {
      _backendCtrl.text = prefs.getString('robo_backend_url') ?? 'https://roboscrap-backend-l9t8.onrender.com';
      _m3uUrlCtrl.text = prefs.getString('robo_ultima_m3u') ?? '';
      _siteUrlCtrl.text = prefs.getString('robo_ultimo_site') ?? '';
      _streamsExtraidosSite = listaSalva;
      _publicadosSessao = pubsSalvos;
      _selecionados = listaSalva
          .map((e) => (e['url_stream'] ?? '').toString())
          .where((u) => u.isNotEmpty && !pubsSalvos.contains(u))
          .toSet();
    });
  }

  Future<void> _salvarPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('robo_backend_url', _backendCtrl.text.trim());
    await prefs.setString('robo_ultima_m3u', _m3uUrlCtrl.text.trim());
    await prefs.setString('robo_ultimo_site', _siteUrlCtrl.text.trim());
    await prefs.setString('robo_streams_salvos', jsonEncode(_streamsExtraidosSite));
    await prefs.setString('robo_publicados_salvos', jsonEncode(_publicadosSessao.toList()));
  }

  Future<void> _limparListaSalva() async {
    setState(() {
      _streamsExtraidosSite = [];
      _selecionados.clear();
      _publicadosSessao.clear();
      _logExecucao = 'Lista limpa manualmente.';
    });
    await _salvarPrefs();
  }

  String get _baseUrl => _backendCtrl.text.trim().replaceAll(RegExp(r'/$'), '');

  Map<String, String> _analisarUrl(String urlStream, {String? tituloBruto, String? qualBruta, String? audioBruto}) {
    final lower = urlStream.toLowerCase();
    final isSerie = RegExp(r'(s\d{1,2}e\d{1,2}|/\d{1,2}(leg|dub)/|temporada|season|episodio)').hasMatch(lower);
    final categoria = isSerie ? 'Série' : 'Filme';

    String qual = qualBruta ?? '1080p';
    if (qual == 'HD' || qual.isEmpty) {
      if (lower.contains('2160') || lower.contains('4k')) {
        qual = '4K';
      } else if (lower.contains('1080')) {
        qual = '1080p';
      } else if (lower.contains('720')) {
        qual = '720p';
      } else {
        qual = '1080p';
      }
    }

    String audio = audioBruto ?? 'Dublado';
    if (audio.isEmpty) {
      audio = (lower.contains('leg') && !lower.contains('dub')) ? 'Legendado' : 'Dublado';
    }

    String titulo = (tituloBruto ?? '').trim();
    if (titulo.isEmpty) {
      try {
        final uri = Uri.parse(urlStream);
        final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) {
          String alvo = segs.last;
          if (isSerie && segs.length >= 3) {
            alvo = segs[segs.length - 3];
          }
          alvo = alvo.replaceAll(RegExp(r'\.(mp4|m3u8|mkv|avi)$', caseSensitive: false), '');
          alvo = alvo.replaceAll(RegExp(r'[-_](dub|leg|dual|720p|1080p|4k|alto|baixo|hd|fhd).*$', caseSensitive: false), '');
          alvo = alvo.replaceAll(RegExp(r'[-_.]'), ' ').trim();
          if (alvo.isNotEmpty) {
            titulo = alvo[0].toUpperCase() + alvo.substring(1);
          }
        }
      } catch (_) {}
    }

    return {
      'titulo': titulo.isEmpty ? 'Sem Título' : titulo,
      'categoria': categoria,
      'qualidade': qual,
      'audio': audio,
    };
  }

  Future<void> _abrirPublicacaoInteligente(String urlStream, {String? tituloBruto, String? qualBruta, String? audioBruto}) async {
    final info = _analisarUrl(urlStream, tituloBruto: tituloBruto, qualBruta: qualBruta, audioBruto: audioBruto);
    setState(() {
      _publicadosSessao.add(urlStream);
      _selecionados.remove(urlStream);
    });
    await _salvarPrefs();

    widget.onPublicarLink(
      urlStream: urlStream,
      tituloSugerido: info['titulo'],
      categoriaSugerida: info['categoria'],
      qualidadeSugerida: info['qualidade'],
      audioSugerido: info['audio'],
    );
  }

  Future<void> _enviarSelecionadosEmFila() async {
    if (_selecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marque pelo menos 1 link na lista.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final sbUrl = prefs.getString('admin_sb_url') ?? 'https://kuziampmbltqdqkqyrlb.supabase.co';
    final sbKey = prefs.getString('admin_sb_key') ?? '';
    final tmdbKey = prefs.getString('admin_tmdb_key') ?? '';

    if (sbKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configure a Supabase Key na aba Chaves primeiro.'), backgroundColor: Colors.red),
      );
      return;
    }

    final urlsParaEnviar = _selecionados.toList();
    setState(() {
      _ocupado = true;
      _logExecucao = 'Enviando ${urlsParaEnviar.length} itens em fila (buscando capas TMDB + gravando na Curadoria)...';
    });

    int enviados = 0;
    for (final u in urlsParaEnviar) {
      final info = _analisarUrl(u);
      String tituloFinal = info['titulo']!;
      String capaUrl = '';
      String bannerUrl = '';
      String sinopse = '';
      String ano = '2026';

      if (tmdbKey.isNotEmpty && tituloFinal != 'Sem Título') {
        try {
          final q = Uri.encodeComponent(tituloFinal);
          final rTmdb = await http
              .get(Uri.parse('https://api.themoviedb.org/3/search/multi?api_key=$tmdbKey&language=pt-BR&query=$q'))
              .timeout(const Duration(seconds: 8));
          if (rTmdb.statusCode == 200) {
            final results = (jsonDecode(rTmdb.body)['results'] as List?) ?? [];
            if (results.isNotEmpty) {
              final m = results.first;
              tituloFinal = (m['title'] ?? m['name'] ?? tituloFinal).toString();
              sinopse = (m['overview'] ?? '').toString();
              if (m['poster_path'] != null) capaUrl = 'https://image.tmdb.org/t/p/w500${m['poster_path']}';
              if (m['backdrop_path'] != null) bannerUrl = 'https://image.tmdb.org/t/p/original${m['backdrop_path']}';
              final data = (m['release_date'] ?? m['first_air_date'] ?? '').toString();
              if (data.length >= 4) ano = data.substring(0, 4);
            }
          }
        } catch (_) {}
      }

      try {
        final rSb = await http.post(
          Uri.parse('$sbUrl/rest/v1/catalogo_midia'),
          headers: {
            'apikey': sbKey,
            'Authorization': 'Bearer $sbKey',
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
          },
          body: jsonEncode({
            'titulo': tituloFinal,
            'categoria': info['categoria'],
            'url_stream': u,
            'qualidade': info['qualidade'],
            'audio': info['audio'],
            'capa_url': capaUrl,
            'banner_url': bannerUrl,
            'sinopse': sinopse,
            'genero': 'Ação, Aventura',
            'ano': int.tryParse(ano) ?? 2026,
            'aprovado': false,
            'link_ativo': true,
          }),
        );
        if (rSb.statusCode == 200 || rSb.statusCode == 201) {
          enviados++;
          _publicadosSessao.add(u);
          _selecionados.remove(u);
        }
      } catch (_) {}
    }

    await _salvarPrefs();
    widget.onAtualizarCatalogo();
    if (mounted) {
      setState(() {
        _ocupado = false;
        _logExecucao = 'Fila concluída! $enviados de ${urlsParaEnviar.length} itens enviados para a aba "Curadoria".\nA lista continua salva aqui até você tocar em Limpar.';
      });
    }
  }

  Future<void> _iniciarLoteInteligente() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("ultimo_link_lote", _loteUrlCtrl.text.trim());
    final fonte = _loteUrlCtrl.text.trim();
    if (fonte.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cole o link do Gist ou lista M3U no campo acima.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final sbUrl = prefs.getString('admin_sb_url') ?? 'https://kuziampmbltqdqkqyrlb.supabase.co';
    final sbKey = prefs.getString('admin_sb_key') ?? '';
    final tmdbKey = prefs.getString('admin_tmdb_key') ?? '';

    if (sbKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configure a Supabase Key na aba Chaves primeiro.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _ocupado = true;
      _logExecucao = 'Enviando lote inteligente para o servidor Render...';
    });

    try {
      final limite = int.tryParse(_loteQtdCtrl.text.trim()) ?? 100;
      final res = await http
          .post(
            Uri.parse('$_baseUrl/importar-lote-inteligente'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'fonte_url': fonte,
              'limite': limite,
              'filtro': _loteFiltroCtrl.text.trim(),
              'auto_aprovar': _autoAprovarTmdb,
              'supabase_url': sbUrl,
              'supabase_key': sbKey,
              'tmdb_key': tmdbKey,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      setState(() => _logExecucao = (data['mensagem'] ?? res.body).toString());
    } catch (e) {
      setState(() => _logExecucao = 'Erro ao iniciar lote: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _checarStatusLote() async {
    setState(() => _logExecucao = "Consultando progresso no Render...");
    try {
      final res = await http.get(Uri.parse("$_baseUrl/status-lote")).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final msg = (data["mensagem"] ?? "").toString();
        setState(() {
          _logExecucao = msg.isEmpty ? "Servidor ocioso (nenhum lote ativo)." : msg;
        });
      } else {
        setState(() => _logExecucao = "Erro HTTP ${res.statusCode} ao consultar progresso.");
      }
    } catch (e) {
      setState(() => _logExecucao = "Erro ao consultar status: $e");
    }
  }

  Future<void> _testarPing() async {
    await _salvarPrefs();
    setState(() {
      _ocupado = true;
      _statusServidor = 'Conectando ao Render...';
      _corStatus = Colors.amber;
    });
    try {
      final res = await http.get(Uri.parse('$_baseUrl/ping')).timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        setState(() {
          _statusServidor = 'Servidor Online (200 OK)';
          _corStatus = Colors.greenAccent;
        });
      } else {
        setState(() {
          _statusServidor = 'Erro HTTP ${res.statusCode}';
          _corStatus = Colors.redAccent;
        });
      }
    } catch (e) {
      setState(() {
        _statusServidor = 'Falha na conexão: $e';
        _corStatus = Colors.redAccent;
      });
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _importarListaM3u() async {
    final m3u = _m3uUrlCtrl.text.trim();
    if (m3u.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cole o link de uma lista .m3u ou .m3u8 primeiro.'), backgroundColor: Colors.orange),
      );
      return;
    }
    await _salvarPrefs();
    setState(() {
      _ocupado = true;
      _logExecucao = 'Baixando lista M3U, consultando TMDB e enviando para Curadoria...\nAguarde alguns segundos.';
    });

    try {
      final limite = int.tryParse(_limiteCtrl.text.trim()) ?? 25;
      final res = await http
          .post(
            Uri.parse('$_baseUrl/importar-m3u'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'m3u_url': m3u, 'limite': limite}),
          )
          .timeout(const Duration(seconds: 90));

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200) {
        setState(() {
          _logExecucao =
              'Importação M3U concluída!\n'
              '• Total na lista: ${data['total_na_lista'] ?? '-'}\n'
              '• Processados: ${data['processados'] ?? '-'}\n'
              '• Inseridos na Curadoria: ${data['inseridos'] ?? '-'}\n'
              'Abra a aba "Curadoria" para aprovar.';
        });
        widget.onAtualizarCatalogo();
      } else {
        setState(() => _logExecucao = 'Erro (${res.statusCode}): ${data['detail'] ?? res.body}');
      }
    } catch (e) {
      setState(() => _logExecucao = 'Erro ao importar lista: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _extrairDeSite() async {
    final site = _siteUrlCtrl.text.trim();
    if (site.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cole o endereço do site para varrer.'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() {
      _ocupado = true;
      _logExecucao = 'Varrendo HTML e iframes de $site em busca de .m3u8 / .mp4...';
    });

    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/extrair-site'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'site_url': site}),
          )
          .timeout(const Duration(seconds: 40));

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200) {
        final rawList = (data['streams'] as List?) ?? [];
        final novaLista = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        setState(() {
          _streamsExtraidosSite = novaLista;
          _publicadosSessao.clear();
          _selecionados = novaLista.map((e) => (e['url_stream'] ?? '').toString()).where((u) => u.isNotEmpty).toSet();
          _logExecucao = novaLista.isEmpty
              ? 'Nenhum stream direto (.m3u8/.mp4) encontrado em "${data['titulo_pagina'] ?? site}".'
              : 'Página: ${data['titulo_pagina'] ?? site}\n${novaLista.length} stream(s) salvos na fila abaixo até você limpar.';
        });
        await _salvarPrefs();
      } else {
        setState(() => _logExecucao = 'Erro (${res.statusCode}): ${data['detail'] ?? res.body}');
      }
    } catch (e) {
      setState(() => _logExecucao = 'Erro ao varrer site: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _buscarLinkNoRobo() async {
    final termo = _buscaCtrl.text.trim();
    if (termo.isEmpty) return;
    await _salvarPrefs();
    setState(() {
      _ocupado = true;
      _resultadosBusca = [];
      _logExecucao = 'Buscando "$termo" no índice do robô e testando links...';
    });

    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/buscar-link'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'titulo': termo}),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200) {
        final lista = (data['resultados'] as List?) ?? [];
        setState(() {
          _resultadosBusca = lista;
          _logExecucao = lista.isEmpty
              ? 'Nenhum link ativo encontrado para "$termo". Importe uma lista M3U primeiro.'
              : '${lista.length} stream(s) validado(s) encontrado(s):';
        });
      } else {
        setState(() => _logExecucao = 'Erro (${res.statusCode}): ${data['detail'] ?? res.body}');
      }
    } catch (e) {
      setState(() => _logExecucao = 'Erro na busca: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _verificarLinksCatalogo() async {
    await _salvarPrefs();
    setState(() {
      _ocupado = true;
      _logExecucao = 'Testando todos os links do catálogo no Supabase...';
    });

    try {
      final res = await http.post(Uri.parse('$_baseUrl/verificar-links')).timeout(const Duration(seconds: 90));
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200) {
        setState(() {
          _logExecucao =
              'Varredura concluída!\n'
              '• Links offline desativados: ${data['links_desativados'] ?? data['inativos'] ?? 0}';
        });
        widget.onAtualizarCatalogo();
      } else {
        setState(() => _logExecucao = 'Erro (${res.statusCode}): ${data['detail'] ?? res.body}');
      }
    } catch (e) {
      setState(() => _logExecucao = 'Erro na varredura: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _copiarTexto(String texto) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link stream copiado!'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF171A23),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Servidor Robô (FastAPI / Render)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                TextField(
                  controller: _backendCtrl,
                  decoration: const InputDecoration(labelText: 'URL do Backend Render', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.circle, size: 12, color: _corStatus),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_statusServidor, style: TextStyle(color: _corStatus, fontSize: 13))),
                    ElevatedButton.icon(
                      onPressed: _ocupado ? null : _testarPing,
                      icon: const Icon(Icons.bolt, size: 18),
                      label: const Text('Testar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF1A222D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.tealAccent, width: 1.2)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Importação Inteligente em Lote (Estilo Streamer)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.tealAccent)),
                const SizedBox(height: 4),
                const Text(
                  'Pula o que já está no banco, faz cache do TMDB por série e publica direto os que tiverem capa/sinopse (jogando só os duvidosos para Curadoria).',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _loteUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Link do Gist, Site ou Lista .m3u',
                    hintText: 'https://gist.github.com/...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 115,
                      child: TextField(
                        controller: _loteQtdCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Qtd (0=Tudo)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _loteFiltroCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Filtro opcional (ex: 2026, arrow)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: Colors.tealAccent,
                  title: const Text('Publicar direto se achar no TMDB', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Desmarque se quiser revisar todos na Curadoria antes', style: TextStyle(fontSize: 11)),
                  value: _autoAprovarTmdb,
                  onChanged: (v) => setState(() => _autoAprovarTmdb = v),
                ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: _ocupado ? null : _iniciarLoteInteligente,
                        icon: const Icon(Icons.rocket_launch),
                        label: const Text('Iniciar Lote', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12)),
                      onPressed: _checarStatusLote,
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Progresso'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF171A23),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('1. Varrer Site Específico & Fila de Publicação', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amber)),
                const SizedBox(height: 4),
                const Text('A lista fica salva na fila mesmo após publicar até você limpar.', style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 10),
                TextField(
                  controller: _siteUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Endereço da página/player',
                    hintText: 'https://exemplo.com/filme-x',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: _ocupado ? null : _extrairDeSite,
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Extrair Links do Site', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_streamsExtraidosSite.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Fila: ${_streamsExtraidosSite.length} itens (${_selecionados.length} marcados)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.tealAccent),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _ocupado ? null : _limparListaSalva,
                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 18),
                        label: const Text('Limpar Lista', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 11)),
                      onPressed: _ocupado || _selecionados.isEmpty ? null : _enviarSelecionadosEmFila,
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text('Enviar ${_selecionados.length} Marcados p/ Curadoria (TMDB)', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._streamsExtraidosSite.map((s) {
                    final u = (s['url_stream'] ?? '').toString();
                    final marcado = _selecionados.contains(u);
                    final jaPublicado = _publicadosSessao.contains(u);
                    final info = _analisarUrl(u, qualBruta: (s['qualidade'] ?? '').toString());
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: jaPublicado ? Colors.green.withOpacity(0.12) : Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: jaPublicado ? Colors.greenAccent : Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: marcado,
                                activeColor: Colors.amber,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selecionados.add(u);
                                    } else {
                                      _selecionados.remove(u);
                                    }
                                  });
                                },
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${info['titulo']} • ${info['categoria']} (${info['qualidade']})',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13.5),
                                    ),
                                    if (jaPublicado)
                                      const Text('✓ Já enviado / publicado', style: TextStyle(color: Colors.greenAccent, fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Text(u, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _copiarTexto(u),
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copiar'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: jaPublicado ? Colors.green : Colors.amber,
                                  foregroundColor: jaPublicado ? Colors.white : Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () => _abrirPublicacaoInteligente(u, qualBruta: (s['qualidade'] ?? '').toString()),
                                icon: Icon(jaPublicado ? Icons.check_circle : Icons.add_circle, size: 18),
                                label: Text(jaPublicado ? 'Publicar Novamente' : '+ Publicar', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF171A23),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('2. Importação Automática de Lista M3U', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amber)),
                const SizedBox(height: 4),
                const Text('Extrai títulos, puxa capas no TMDB e envia para Curadoria.', style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 10),
                TextField(
                  controller: _m3uUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Link da Lista (.m3u ou .m3u8)',
                    hintText: 'https://exemplo.com/lista.m3u',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 105,
                      child: TextField(
                        controller: _limiteCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Qtd. Lote', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 13)),
                        onPressed: _ocupado ? null : _importarListaM3u,
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('Importar M3U', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF171A23),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('3. Buscar Stream por Nome no Índice', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.tealAccent)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _buscaCtrl,
                        decoration: const InputDecoration(labelText: 'Nome do filme ou série', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _ocupado ? null : _buscarLinkNoRobo,
                      child: const Icon(Icons.search),
                    ),
                  ],
                ),
                if (_resultadosBusca.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ..._resultadosBusca.map((r) {
                    final u = (r['url_stream'] ?? '').toString();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r['titulo'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${r['qualidade'] ?? ''} • ${r['audio'] ?? ''}\n$u', maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10)),
                        onPressed: () => _abrirPublicacaoInteligente(
                          u,
                          tituloBruto: (r['titulo'] ?? '').toString(),
                          qualBruta: (r['qualidade'] ?? '').toString(),
                          audioBruto: (r['audio'] ?? '').toString(),
                        ),
                        child: const Text('+ Publicar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _ocupado ? null : _verificarLinksCatalogo,
          icon: const Icon(Icons.health_and_safety, color: Colors.tealAccent),
          label: const Text('Varredura Automática: Desativar Links Offline'),
        ),
        if (_ocupado) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator(color: Colors.amber)),
        ],
        if (_logExecucao.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
            child: Text(_logExecucao, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: Colors.white)),
          ),
        ],
      ],
    );
  }
}
