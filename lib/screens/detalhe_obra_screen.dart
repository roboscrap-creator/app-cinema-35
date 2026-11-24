import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/midia_model.dart';
import '../services/supabase_service.dart';
import '../services/cdn_stream_service.dart';
import '../services/max_assistant_service.dart';
import '../widgets/cinema_widgets.dart';
import '../widgets/max_assistant_overlay.dart';
import 'player_screen.dart';

class DetalheObraScreen extends StatefulWidget {
  final ObraAgrupada obra;
  final List<ObraAgrupada> catalogoCompleto;

  const DetalheObraScreen({
    super.key,
    required this.obra,
    this.catalogoCompleto = const [],
  });

  @override
  State<DetalheObraScreen> createState() => _DetalheObraScreenState();
}

class _DetalheObraScreenState extends State<DetalheObraScreen> {
  late ObraAgrupada _obraAtual;
  bool _favorito = false;
  double _progressoSalvo = 0.0;
  int _temporadaSelecionada = 1;
  String _audioSelecionado = '';
  String _resolucaoSelecionada = '';

  @override
  void initState() {
    super.initState();
    _obraAtual = widget.obra;
    MaxAssistantService.instance.definirObraEmVisualizacao(_obraAtual);
    if (_obraAtual.temporadasDisponiveis.isNotEmpty) {
      _temporadaSelecionada = _obraAtual.temporadasDisponiveis.first;
    }
    if (_obraAtual.audiosDisponiveis.isNotEmpty) {
      _audioSelecionado = _obraAtual.audiosDisponiveis.first;
    }
    if (_obraAtual.resolucoesDisponiveis.isNotEmpty) {
      _resolucaoSelecionada = _obraAtual.resolucoesDisponiveis.first;
    }
    _carregarDetalhesExtras();
    CdnStreamService.preAquecerMagnet(_escolherMelhorFonte()?.urlStream);
  }

  @override
  void dispose() {
    MaxAssistantService.instance.definirObraEmVisualizacao(null);
    super.dispose();
  }

  Future<void> _carregarDetalhesExtras() async {
    if (_obraAtual.fontes.isEmpty && _obraAtual.totalFontes > 0) {
      final fontesNuvem = await SupabaseService.carregarFontesDaObra(_obraAtual);
      if (mounted && fontesNuvem.isNotEmpty) {
        setState(() {
          _obraAtual = _obraAtual.copyWith(fontes: fontesNuvem);
          if (_obraAtual.temporadasDisponiveis.isNotEmpty) _temporadaSelecionada = _obraAtual.temporadasDisponiveis.first;
          if (_obraAtual.audiosDisponiveis.isNotEmpty) _audioSelecionado = _obraAtual.audiosDisponiveis.first;
          if (_obraAtual.resolucoesDisponiveis.isNotEmpty) _resolucaoSelecionada = _obraAtual.resolucoesDisponiveis.first;
        });
        CdnStreamService.preAquecerMagnet(_escolherMelhorFonte()?.urlStream);
      }
    }
    final favs = await SupabaseService.carregarFavoritos();
    final progMap = await SupabaseService.carregarProgressoAssistido();
    final progVal = (progMap[_obraAtual.chaveGrupo]?['progresso'] as num?)?.toDouble() ?? 0.0;
    if (mounted) {
      setState(() { _favorito = favs.contains(_obraAtual.chaveGrupo); _progressoSalvo = progVal; });
    }
    final enriquecido = await SupabaseService.enriquecerComTmdb(_obraAtual);
    if (mounted) {
      setState(() => _obraAtual = enriquecido);
      MaxAssistantService.instance.definirObraEmVisualizacao(_obraAtual);
      CdnStreamService.preAquecerMagnet(_escolherMelhorFonte()?.urlStream);
    }
  }

  Future<void> _alternarFavorito() async {
    final novo = await SupabaseService.alternarFavorito(_obraAtual.chaveGrupo);
    if (mounted) {
      setState(() => _favorito = novo);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(novo ? 'Adicionado aos Meus Favoritos!' : 'Removido dos Favoritos.'),
        ),
      );
    }
  }

  FonteMidia? _escolherMelhorFonte([int? epNumero]) {
    if (_obraAtual.fontes.isEmpty) return null;
    var candidatas = _obraAtual.fontes;
    if (_obraAtual.isSerie) {
      candidatas = candidatas.where((f) => (f.temporada ?? 1) == _temporadaSelecionada).toList();
      if (epNumero != null) {
        candidatas = candidatas.where((f) => f.episodio == epNumero).toList();
      }
    }
    if (candidatas.isEmpty) candidatas = _obraAtual.fontes;

    final matchExato = candidatas.where((f) =>
        (_audioSelecionado.isEmpty || f.tipoAudio.toLowerCase().contains(_audioSelecionado.toLowerCase())) &&
        (_resolucaoSelecionada.isEmpty || f.resolucao.toLowerCase().contains(_resolucaoSelecionada.toLowerCase())));
    if (matchExato.isNotEmpty) return matchExato.first;

    final matchAudio = candidatas.where((f) =>
        _audioSelecionado.isEmpty || f.tipoAudio.toLowerCase().contains(_audioSelecionado.toLowerCase()));
    if (matchAudio.isNotEmpty) return matchAudio.first;

    return candidatas.first;
  }

  Future<void> _reproduzir([FonteMidia? fonteEspecifica]) async {
    if (fonteEspecifica == null && _obraAtual.fontes.isEmpty && _obraAtual.totalFontes > 0) {
      final fontesNuvem = await SupabaseService.carregarFontesDaObra(_obraAtual);
      if (mounted && fontesNuvem.isNotEmpty) {
        setState(() => _obraAtual = _obraAtual.copyWith(fontes: fontesNuvem));
      }
    }
    final alvo = fonteEspecifica ?? _escolherMelhorFonte();
    if (alvo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este título do Top 100 ainda está em breve no catálogo.')),
      );
      return;
    }
    final eps = _obraAtual.isSerie ? _obraAtual.episodiosDaTemporada(_temporadaSelecionada) : <FonteMidia>[];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CinemaPlayerScreen(
          obra: _obraAtual,
          fonteInicial: alvo,
          listaEpisodios: eps,
          progressoInicial: fonteEspecifica == null ? _progressoSalvo : 0.0,
        ),
      ),
    ).then((_) => _carregarDetalhesExtras());
  }

  List<ObraAgrupada> get _relacionados {
    if (widget.catalogoCompleto.isEmpty) return [];
    final genPrincipal = _obraAtual.genero.split(',').first.trim().toLowerCase();
    return widget.catalogoCompleto
        .where((o) =>
            o.chaveGrupo != _obraAtual.chaveGrupo &&
            (genPrincipal.isEmpty || o.genero.toLowerCase().contains(genPrincipal)))
        .take(12)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 760;
    final bgImg = _obraAtual.bannerUrl.isNotEmpty ? _obraAtual.bannerUrl : _obraAtual.capaUrl;
    final epsTemporada = _obraAtual.isSerie
        ? _obraAtual.episodiosDaTemporada(_temporadaSelecionada)
        : <FonteMidia>[];

    // Agrupa episódios únicos por número de episódio
    final Map<int, FonteMidia> epsUnicos = {};
    for (final f in epsTemporada) {
      final numEp = f.episodio ?? (epsUnicos.length + 1);
      epsUnicos.putIfAbsent(numEp, () => f);
    }
    final listaEps = epsUnicos.values.toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (bgImg.isNotEmpty)
            CachedNetworkImage(
              imageUrl: bgImg,
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.76),
              colorBlendMode: BlendMode.darken,
            ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xF00A0C10), Color(0xAA0A0C10), Color(0xDD0A0C10)],
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(26, 12, 26, 36),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _obraAtual.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MaxMicButton(onPressed: () => MaxAssistantModal.abrir(context)),
                  ],
                ),
                const SizedBox(height: 16),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: _buildInfoPrincipal()),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: _buildPreviewCard(bgImg)),
                    ],
                  )
                else ...[
                  _buildPreviewCard(bgImg),
                  const SizedBox(height: 18),
                  _buildInfoPrincipal(),
                ],
                if (_obraAtual.isSerie && _obraAtual.disponivelParaAssistir) ...[
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Text('Temporadas:', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FocusTraversalGroup(
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: _obraAtual.temporadasDisponiveis.map((t) {
                              final ativo = t == _temporadaSelecionada;
                              return CinemaFocusBox(
                                borderRadius: 18,
                                onTap: () => setState(() => _temporadaSelecionada = t),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: ativo ? const Color(0xFFF5B82E) : const Color(0xFF1A202E),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    'Temp. $t',
                                    style: TextStyle(color: ativo ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FocusTraversalGroup(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: List.generate(listaEps.length, (idx) {
                        final ep = listaEps[idx];
                        final label = ep.etiquetaEpisodio.isNotEmpty ? ep.etiquetaEpisodio : 'Episódio ${idx + 1}';
                        return CinemaFocusBox(
                          borderRadius: 8,
                          scaleOnFocus: 1.05,
                          onTap: () => _reproduzir(_escolherMelhorFonte(ep.episodio) ?? ep),
                          child: Container(
                            width: 156,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF171C26),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
                if (_relacionados.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const Text('Você também pode gostar', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 248,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _relacionados.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (_, idx) => TvPosterCard(
                        obra: _relacionados[idx],
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetalheObraScreen(
                                obra: _relacionados[idx],
                                catalogoCompleto: widget.catalogoCompleto,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(String img) {
    return CinemaFocusBox(
      onTap: () => _reproduzir(),
      borderRadius: 14,
      scaleOnFocus: 1.035,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (img.isNotEmpty)
                CachedNetworkImage(imageUrl: img, fit: BoxFit.cover)
              else
                Container(color: const Color(0xFF161A23)),
              Container(color: Colors.black38),
              Center(
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFF5B82E),
                  child: Icon(
                    _obraAtual.disponivelParaAssistir ? Icons.play_arrow_rounded : Icons.schedule,
                    color: Colors.black,
                    size: 36,
                  ),
                ),
              ),
              Positioned(
                bottom: 10,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    _obraAtual.disponivelParaAssistir ? 'Clique para reproduzir' : 'Em breve no catálogo',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPrincipal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_obraAtual.notaImdb > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFF5B82E), borderRadius: BorderRadius.circular(5)),
                child: Text('IMDb ${_obraAtual.notaImdb.toStringAsFixed(1)}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
              ),
            if (_obraAtual.ano.isNotEmpty)
              Text(_obraAtual.ano, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            if (_obraAtual.pais.isNotEmpty)
              Text('• ${_obraAtual.pais}', style: const TextStyle(color: Colors.white70)),
            if (_obraAtual.genero.isNotEmpty)
              Text('• ${_obraAtual.genero}', style: const TextStyle(color: Color(0xFFF5B82E))),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _obraAtual.sinopse.isNotEmpty ? _obraAtual.sinopse : 'Sinopse indisponível.',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        if (_obraAtual.diretor.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Direção: ${_obraAtual.diretor}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
        if (_obraAtual.elenco.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Elenco: ${_obraAtual.elenco}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        if (_obraAtual.disponivelParaAssistir) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._obraAtual.audiosDisponiveis.map(
                (a) => ChoiceChip(
                  label: Text(a),
                  selected: _audioSelecionado == a,
                  selectedColor: const Color(0xFFF5B82E),
                  labelStyle: TextStyle(color: _audioSelecionado == a ? Colors.black : Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  onSelected: (_) => setState(() => _audioSelecionado = a),
                ),
              ),
              ..._obraAtual.resolucoesDisponiveis.map(
                (r) => ChoiceChip(
                  label: Text(r),
                  selected: _resolucaoSelecionada == r,
                  selectedColor: Colors.white24,
                  labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  onSelected: (_) => setState(() => _resolucaoSelecionada = r),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            CinemaFocusBox(
              autofocus: true,
              borderRadius: 24,
              scaleOnFocus: 1.06,
              onTap: () => _reproduzir(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                decoration: BoxDecoration(
                  color: _obraAtual.disponivelParaAssistir ? const Color(0xFFF5B82E) : Colors.white24,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_obraAtual.disponivelParaAssistir ? Icons.play_arrow : Icons.schedule, color: _obraAtual.disponivelParaAssistir ? Colors.black : Colors.white70),
                    const SizedBox(width: 8),
                    Text(_obraAtual.disponivelParaAssistir ? 'ASSISTIR AGORA' : 'EM BREVE', style: TextStyle(color: _obraAtual.disponivelParaAssistir ? Colors.black : Colors.white70, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            CinemaFocusBox(
              borderRadius: 24,
              scaleOnFocus: 1.06,
              onTap: _alternarFavorito,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _favorito ? const Color(0xFFF5B82E) : Colors.white30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_favorito ? Icons.favorite : Icons.favorite_border, color: _favorito ? const Color(0xFFF5B82E) : Colors.white),
                    const SizedBox(width: 8),
                    Text(_favorito ? 'Favoritado' : 'Favoritar', style: TextStyle(color: _favorito ? const Color(0xFFF5B82E) : Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
