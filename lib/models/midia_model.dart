class FonteMidia {
  final String id;
  final String titulo;
  final String categoria;
  final String urlStream;
  String get url => urlStream;
  final String urlStreamBackup;
  final String formato;
  final String resolucao;
  final String tipoAudio;
  final List<String> idiomasAudio;
  final Map<String, String> headers;
  final int? temporada;
  final int? episodio;

  FonteMidia({
    required this.id,
    required this.titulo,
    required this.categoria,
    required this.urlStream,
    required this.urlStreamBackup,
    required this.formato,
    required this.resolucao,
    required this.tipoAudio,
    required this.idiomasAudio,
    required this.headers,
    this.temporada,
    this.episodio,
  });

  String get badgeResumo =>
      '${resolucao.isNotEmpty ? resolucao : 'HD'} • ${tipoAudio.isNotEmpty ? tipoAudio : 'Dublado'}';

  String get etiquetaEpisodio =>
      (temporada != null && episodio != null) ? 'S$temporada - E$episodio' : '';

  factory FonteMidia.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers_customizados'];
    final Map<String, String> parsedHeaders = {};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k != null && v != null) parsedHeaders[k.toString()] = v.toString();
      });
    }
    final rawIdiomas = json['idiomas_audio'];
    return FonteMidia(
      id: (json['id'] ?? '').toString(),
      titulo: (json['titulo'] ?? 'Sem Título').toString(),
      categoria: (json['categoria'] ?? 'Filme').toString(),
      urlStream: (json['url_stream'] ?? '').toString(),
      urlStreamBackup: (json['url_stream_backup'] ?? '').toString(),
      formato: (json['formato'] ?? 'mp4').toString(),
      resolucao: (json['resolucao'] ?? '1080p').toString(),
      tipoAudio: (json['tipo_audio'] ?? 'Dublado').toString(),
      idiomasAudio: rawIdiomas is List
          ? rawIdiomas.map((e) => e.toString()).toList()
          : ['Português'],
      headers: parsedHeaders,
      temporada: json['temporada'] is int
          ? json['temporada']
          : int.tryParse('${json['temporada'] ?? ''}'),
      episodio: json['episodio'] is int
          ? json['episodio']
          : int.tryParse('${json['episodio'] ?? ''}'),
    );
  }
}

typedef FonteStream = FonteMidia;

class ObraAgrupada {
  final String chaveGrupo;
  final int? tmdbId;
  final String titulo;
  final String tituloOriginal;
  final String categoria;
  final String genero;
  final String sinopse;
  final String capaUrl;
  final String bannerUrl;
  final int ano;
  final String pais;
  final String diretor;
  final String elenco;
  final int aberturaSegundos;
  final bool emDestaque;
  final int ordemDestaque;
  final List<String> tags;
  final double notaImdb;
  final int visualizacoes;
  final List<FonteMidia> fontes;
  final int totalFontes;
  final int maxTemporada;
  final int maxEpisodio;
  final bool isSerieFlag;
  final String? imdbIdReal;

  ObraAgrupada({
    this.chaveGrupo = '',
    this.tmdbId,
    required this.titulo,
    this.tituloOriginal = '',
    this.categoria = 'Filme',
    this.genero = '',
    this.sinopse = '',
    this.capaUrl = '',
    this.bannerUrl = '',
    this.ano = 0,
    this.pais = '',
    this.diretor = '',
    this.elenco = '',
    this.aberturaSegundos = 0,
    this.emDestaque = false,
    this.ordemDestaque = 999,
    this.tags = const [],
    this.notaImdb = 0.0,
    this.visualizacoes = 0,
    this.fontes = const [],
    this.totalFontes = 0,
    this.maxTemporada = 1,
    this.maxEpisodio = 0,
    this.isSerieFlag = false,
    this.imdbIdReal,
  });

  // Getters de compatibilidade entre Modo Celular, Modo TV e Serviços
  String get nome => titulo;
  String get tipo => categoria;
  String get capa => capaUrl;
  String get banner => bannerUrl;
  String get nota => notaImdb.toStringAsFixed(1);
  String get imdbId => imdbIdReal ?? '';
  String? get posterUrl => capaUrl;
  String? get backdropUrl => bannerUrl.trim().isNotEmpty ? bannerUrl : capaUrl;

  List<String> get generos => genero
      .split(RegExp(r'[,/|]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  bool get isSerie =>
      isSerieFlag ||
      categoria.toLowerCase().contains('série') ||
      categoria.toLowerCase().contains('serie') ||
      categoria.toLowerCase().contains('anime');

  double get scorePopularidade => (visualizacoes * 2.0) + (notaImdb * 10.0);

  String get badgePoster {
    if (!isSerie) return '';
    if (fontes.isEmpty) {
      if (maxTemporada > 1) return 'Temp.$maxTemporada';
      if (maxEpisodio > 0) return 'S$maxTemporada-E$maxEpisodio';
      return 'Temp.$maxTemporada';
    }
    final temps = temporadasDisponiveis;
    if (temps.length > 1) return 'Temp.${temps.last}';
    final eps = episodiosDaTemporada(temps.first);
    if (eps.isNotEmpty && eps.last.episodio != null) {
      return 'S${temps.first}-E${eps.last.episodio}';
    }
    return 'Temp.${temps.first}';
  }

  List<String> get audiosDisponiveis {
    final set = <String>{};
    for (final f in fontes) {
      if (f.tipoAudio.isNotEmpty) set.add(f.tipoAudio);
      for (final idm in f.idiomasAudio) {
        if (idm.trim().isNotEmpty) set.add(idm.trim());
      }
    }
    return set.isEmpty ? ['Português'] : set.toList();
  }

  List<String> get resolucoesDisponiveis {
    final set = <String>{};
    for (final f in fontes) {
      if (f.resolucao.isNotEmpty) set.add(f.resolucao);
    }
    return set.isEmpty ? ['1080p'] : set.toList();
  }

  List<int> get temporadasDisponiveis {
    final set = <int>{};
    for (final f in fontes) {
      set.add(f.temporada ?? 1);
    }
    if (set.isEmpty) return [1];
    return set.toList()..sort();
  }

  List<FonteMidia> episodiosDaTemporada(int temp) {
    final list = fontes.where((f) => (f.temporada ?? 1) == temp).toList();
    list.sort((a, b) => (a.episodio ?? 0).compareTo(b.episodio ?? 0));
    return list;
  }

  ObraAgrupada copyWith({
    String? tituloOriginal,
    String? pais,
    String? diretor,
    String? elenco,
    String? sinopse,
    String? genero,
    double? notaImdb,
    List<FonteMidia>? fontes,
  }) {
    return ObraAgrupada(
      chaveGrupo: chaveGrupo,
      tmdbId: tmdbId,
      titulo: titulo,
      tituloOriginal: tituloOriginal ?? this.tituloOriginal,
      categoria: categoria,
      genero: (genero != null && genero.isNotEmpty) ? genero : this.genero,
      sinopse: (sinopse != null && sinopse.isNotEmpty) ? sinopse : this.sinopse,
      capaUrl: capaUrl,
      bannerUrl: bannerUrl,
      ano: ano,
      pais: (pais != null && pais.isNotEmpty) ? pais : this.pais,
      diretor: (diretor != null && diretor.isNotEmpty) ? diretor : this.diretor,
      elenco: (elenco != null && elenco.isNotEmpty) ? elenco : this.elenco,
      aberturaSegundos: aberturaSegundos,
      emDestaque: emDestaque,
      ordemDestaque: ordemDestaque,
      tags: tags,
      notaImdb: (notaImdb != null && notaImdb > 0) ? notaImdb : this.notaImdb,
      visualizacoes: visualizacoes,
      fontes: fontes ?? this.fontes,
      totalFontes:
          (fontes != null && fontes.isNotEmpty) ? fontes.length : totalFontes,
      maxTemporada: maxTemporada,
      maxEpisodio: maxEpisodio,
      isSerieFlag: isSerieFlag,
      imdbIdReal: imdbIdReal,
    );
  }

  factory ObraAgrupada.fromMap(Map<String, dynamic> map) {
    final titulo = (map['titulo'] ?? map['nome'] ?? '').toString();
    final categoria = (map['categoria'] ?? map['tipo'] ?? 'Filme').toString();
    final genero = (map['genero'] ??
            (map['generos'] is List ? (map['generos'] as List).join(', ') : ''))
        .toString();
    final capa =
        (map['capa_url'] ?? map['capaUrl'] ?? map['posterUrl'] ?? '').toString();
    final banner =
        (map['banner_url'] ?? map['bannerUrl'] ?? map['backdropUrl'] ?? '')
            .toString();
    final nota =
        double.tryParse((map['nota_imdb'] ?? map['nota'] ?? '0').toString()) ??
            0.0;
    final ano = int.tryParse((map['ano'] ?? '0').toString()) ?? 0;
    final sinopse = (map['sinopse'] ?? '').toString();
    final imdb = (map['imdb_id'] ?? map['imdbId'] ?? '').toString();
    final tmdb =
        int.tryParse((map['tmdb_id'] ?? map['tmdbId'] ?? '').toString());
    final urlDireta = (map['url_stream'] ?? map['url'] ?? '').toString();
    final fontes = <FonteMidia>[];
    if (urlDireta.isNotEmpty) {
      fontes.add(FonteMidia(
        id: (map['id'] ?? '').toString(),
        titulo: titulo,
        categoria: categoria,
        urlStream: urlDireta,
        urlStreamBackup: '',
        formato: 'mp4',
        resolucao: '1080p',
        tipoAudio: 'Dublado',
        idiomasAudio: const ['Português'],
        headers: const {},
      ));
    }
    return ObraAgrupada(
      chaveGrupo: (map['chave_grupo'] ?? titulo.toLowerCase()).toString(),
      tmdbId: tmdb,
      titulo: titulo,
      tituloOriginal: (map['titulo_original'] ?? titulo).toString(),
      categoria: categoria,
      genero: genero,
      sinopse: sinopse,
      capaUrl: capa,
      bannerUrl: banner,
      ano: ano,
      notaImdb: nota,
      fontes: fontes,
      totalFontes: fontes.length,
      isSerieFlag: categoria.toLowerCase().contains('série') ||
          categoria.toLowerCase().contains('serie') ||
          categoria.toLowerCase().contains('anime'),
      imdbIdReal: imdb.isNotEmpty ? imdb : null,
    );
  }
}
