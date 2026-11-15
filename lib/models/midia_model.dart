class FonteMidia {
  final String id;
  final String titulo;
  final String categoria;
  final String urlStream;
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

  String get badgeResumo {
    final res = resolucao.isNotEmpty ? resolucao : 'HD';
    final aud = tipoAudio.isNotEmpty ? tipoAudio : 'Dublado';
    return '$res • $aud';
  }

  String get etiquetaEpisodio {
    if (temporada != null && episodio != null) {
      return 'T${temporada.toString().padLeft(2, '0')}:E${episodio.toString().padLeft(2, '0')}';
    }
    return '';
  }

  factory FonteMidia.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers_customizados'];
    final Map<String, String> parsedHeaders = {};
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k != null && v != null) parsedHeaders[k.toString()] = v.toString();
      });
    }
    final rawIdiomas = json['idiomas_audio'];
    final List<String> idiomas = rawIdiomas is List ? rawIdiomas.map((e) => e.toString()).toList() : ['PT'];

    return FonteMidia(
      id: (json['id'] ?? '').toString(),
      titulo: (json['titulo'] ?? 'Sem Título').toString(),
      categoria: (json['categoria'] ?? 'Filme').toString(),
      urlStream: (json['url_stream'] ?? '').toString(),
      urlStreamBackup: (json['url_stream_backup'] ?? '').toString(),
      formato: (json['formato'] ?? 'mp4').toString(),
      resolucao: (json['resolucao'] ?? '1080p').toString(),
      tipoAudio: (json['tipo_audio'] ?? 'Dublado').toString(),
      idiomasAudio: idiomas,
      headers: parsedHeaders,
      temporada: json['temporada'] is int ? json['temporada'] : int.tryParse('${json['temporada'] ?? ''}'),
      episodio: json['episodio'] is int ? json['episodio'] : int.tryParse('${json['episodio'] ?? ''}'),
    );
  }
}

class ObraAgrupada {
  final String chaveGrupo;
  final int? tmdbId;
  final String titulo;
  final String categoria;
  final String genero;
  final String sinopse;
  final String capaUrl;
  final String bannerUrl;
  final String ano;
  final bool emDestaque;
  final int ordemDestaque;
  final List<FonteMidia> fontes;

  ObraAgrupada({
    required this.chaveGrupo,
    this.tmdbId,
    required this.titulo,
    required this.categoria,
    required this.genero,
    required this.sinopse,
    required this.capaUrl,
    required this.bannerUrl,
    required this.ano,
    required this.emDestaque,
    required this.ordemDestaque,
    required this.fontes,
  });

  List<String> get audiosDisponiveis {
    final set = <String>{};
    for (final f in fontes) {
      if (f.tipoAudio.isNotEmpty) set.add(f.tipoAudio);
    }
    return set.isEmpty ? ['Dublado'] : set.toList();
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
    return set.toList()..sort();
  }

  List<FonteMidia> episodiosDaTemporada(int temp) {
    final list = fontes.where((f) => (f.temporada ?? 1) == temp).toList();
    list.sort((a, b) => (a.episodio ?? 0).compareTo(b.episodio ?? 0));
    return list;
  }
}
