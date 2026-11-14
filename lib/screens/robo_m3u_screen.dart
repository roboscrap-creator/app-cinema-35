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

  bool _ocupado = false;
  String _statusServidor = 'Toque em Testar Conexão';
  Color _corStatus = Colors.grey;
  String _logExecucao = '';
  List<dynamic> _streamsExtraidosSite = [];
  List<dynamic> _resultadosBusca = [];

  @override
  void initState() {
    super.initState();
    _carregarPrefs();
  }

  Future<void> _carregarPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backendCtrl.text = prefs.getString('robo_backend_url') ?? 'https://roboscrap-backend-l9t8.onrender.com';
      _m3uUrlCtrl.text = prefs.getString('robo_ultima_m3u') ?? '';
      _siteUrlCtrl.text = prefs.getString('robo_ultimo_site') ?? '';
    });
  }

  Future<void> _salvarPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('robo_backend_url', _backendCtrl.text.trim());
    await prefs.setString('robo_ultima_m3u', _m3uUrlCtrl.text.trim());
    await prefs.setString('robo_ultimo_site', _siteUrlCtrl.text.trim());
  }

  String get _baseUrl => _backendCtrl.text.trim().replaceAll(RegExp(r'/$'), '');

  void _abrirPublicacaoInteligente(String urlStream, {String? tituloBruto, String? qualBruta, String? audioBruto}) {
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

    widget.onPublicarLink(
      urlStream: urlStream,
      tituloSugerido: titulo,
      categoriaSugerida: categoria,
      qualidadeSugerida: qual,
      audioSugerido: audio,
    );
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
    await _salvarPrefs();
    setState(() {
      _ocupado = true;
      _streamsExtraidosSite = [];
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
        final lista = (data['streams'] as List?) ?? [];
        setState(() {
          _streamsExtraidosSite = lista;
          _logExecucao = lista.isEmpty
              ? 'Nenhum stream direto (.m3u8/.mp4) encontrado em "${data['titulo_pagina'] ?? site}".'
              : 'Página: ${data['titulo_pagina'] ?? site}\n${lista.length} stream(s) encontrado(s). Toque em "+ Publicar" ao lado do link desejada.';
        });
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
          color: const Color(0xFF171A23),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('1. Varrer Site Específico por URL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amber)),
                const SizedBox(height: 4),
                const Text('Extrai .m3u8 ou .mp4 e preenche a publicação com 1 toque.', style: TextStyle(fontSize: 12, color: Colors.white70)),
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
                  const SizedBox(height: 12),
                  ..._streamsExtraidosSite.map((s) {
                    final u = (s['url_stream'] ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${s['formato']} • ${s['qualidade']} (${s['origem']})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(u, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
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
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                onPressed: () => _abrirPublicacaoInteligente(u, qualBruta: (s['qualidade'] ?? '').toString()),
                                icon: const Icon(Icons.add_circle, size: 18),
                                label: const Text('+ Publicar', style: TextStyle(fontWeight: FontWeight.bold)),
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
