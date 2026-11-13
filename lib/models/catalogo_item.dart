class CatalogoItem {
  final String id;
  final int? tmdbId;
  final String titulo;
  final String categoria;
  final String genero;
  final String sinopse;
  final String capaUrl;
  final String bannerUrl;
  final int? ano;
  final double? notaImdb;
  final String urlStream;
  final String urlStreamBackup;
  final String resolucao;
  final String tipoAudio;
  final bool aprovado;
  final bool linkAtivo;
  final bool emDestaque;
  final int ordemDestaque;

  CatalogoItem({
    required this.id,
    this.tmdbId,
    required this.titulo,
    this.categoria = 'Filme',
    this.genero = 'Geral',
    this.sinopse = '',
    this.capaUrl = '',
    this.bannerUrl = '',
    this.ano,
    this.notaImdb,
    required this.urlStream,
    this.urlStreamBackup = '',
    this.resolucao = '1080p',
    this.tipoAudio = 'Dublado',
    this.aprovado = false,
    this.linkAtivo = true,
    this.emDestaque = false,
    this.ordemDestaque = 0,
  });

  factory CatalogoItem.fromJson(Map<String, dynamic> j) => CatalogoItem(
        id: j['id']?.toString() ?? '',
        tmdbId: j['tmdb_id'],
        titulo: j['titulo'] ?? 'Sem título',
        categoria: j['categoria'] ?? 'Filme',
        genero: j['genero'] ?? 'Geral',
        sinopse: j['sinopse'] ?? '',
        capaUrl: j['capa_url'] ?? '',
        bannerUrl: j['banner_url'] ?? '',
        ano: j['ano'],
        notaImdb: (j['nota_imdb'] as num?)?.toDouble(),
        urlStream: j['url_stream'] ?? '',
        urlStreamBackup: j['url_stream_backup'] ?? '',
        resolucao: j['resolucao'] ?? '1080p',
        tipoAudio: j['tipo_audio'] ?? 'Dublado',
        aprovado: j['aprovado'] ?? false,
        linkAtivo: j['link_ativo'] ?? true,
        emDestaque: j['em_destaque'] ?? false,
        ordemDestaque: (j['ordem_destaque'] as num?)?.toInt() ?? 0,
      );
}
