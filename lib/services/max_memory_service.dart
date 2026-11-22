import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MaxPerfilUsuario {
  final String nome;
  final bool infantil;
  final String? ultimaSerie;
  final int ultimaTemporada;
  final int ultimoEpisodio;
  final List<String> historicoRecente;
  final List<String> preferenciasAprendidas;

  const MaxPerfilUsuario({
    required this.nome,
    this.infantil = false,
    this.ultimaSerie,
    this.ultimaTemporada = 1,
    this.ultimoEpisodio = 1,
    this.historicoRecente = const [],
    this.preferenciasAprendidas = const [],
  });

  MaxPerfilUsuario copyWith({
    String? nome,
    bool? infantil,
    String? ultimaSerie,
    int? ultimaTemporada,
    int? ultimoEpisodio,
    List<String>? historicoRecente,
    List<String>? preferenciasAprendidas,
  }) {
    return MaxPerfilUsuario(
      nome: nome ?? this.nome,
      infantil: infantil ?? this.infantil,
      ultimaSerie: ultimaSerie ?? this.ultimaSerie,
      ultimaTemporada: ultimaTemporada ?? this.ultimaTemporada,
      ultimoEpisodio: ultimoEpisodio ?? this.ultimoEpisodio,
      historicoRecente: historicoRecente ?? this.historicoRecente,
      preferenciasAprendidas: preferenciasAprendidas ?? this.preferenciasAprendidas,
    );
  }

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'infantil': infantil,
        'ultimaSerie': ultimaSerie,
        'ultimaTemporada': ultimaTemporada,
        'ultimoEpisodio': ultimoEpisodio,
        'historicoRecente': historicoRecente,
        'preferenciasAprendidas': preferenciasAprendidas,
      };

  factory MaxPerfilUsuario.fromJson(Map<String, dynamic> json) {
    return MaxPerfilUsuario(
      nome: (json['nome'] ?? 'Convidado').toString(),
      infantil: json['infantil'] == true,
      ultimaSerie: json['ultimaSerie']?.toString(),
      ultimaTemporada: (json['ultimaTemporada'] is int) ? json['ultimaTemporada'] : 1,
      ultimoEpisodio: (json['ultimoEpisodio'] is int) ? json['ultimoEpisodio'] : 1,
      historicoRecente: (json['historicoRecente'] is List)
          ? List<String>.from(json['historicoRecente'].map((e) => e.toString()))
          : const [],
      preferenciasAprendidas: (json['preferenciasAprendidas'] is List)
          ? List<String>.from(json['preferenciasAprendidas'].map((e) => e.toString()))
          : const [],
    );
  }
}

class MaxMemoryService {
  static const String _kPerfisKey = 'cinemax_max_perfis_v2';
  static const String _kPerfilAtivoKey = 'cinemax_max_perfil_ativo_v2';
  static const String _kAprendizadoAppKey = 'cinemax_max_aprendizado_v2';

  static final MaxMemoryService instance = MaxMemoryService._();
  MaxMemoryService._();

  final Map<String, MaxPerfilUsuario> _perfis = {};
  String _perfilAtivo = '';
  List<String> _catalogoConhecido = [];
  List<String> _fatosAprendidos = [];
  bool _carregado = false;

  Future<void> inicializar() async {
    if (_carregado) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPerfisKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            _perfis[key] = MaxPerfilUsuario.fromJson(value);
          }
        });
      } catch (_) {}
    }
    _perfilAtivo = prefs.getString(_kPerfilAtivoKey) ?? '';
    _fatosAprendidos = prefs.getStringList(_kAprendizadoAppKey) ?? [];
    _carregado = true;
  }

  List<MaxPerfilUsuario> get perfis => _perfis.values.toList();

  MaxPerfilUsuario? get perfilAtual {
    if (_perfilAtivo.isEmpty) return null;
    return _perfis[_perfilAtivo.toLowerCase()];
  }

  String get nomeAtual => perfilAtual?.nome ?? '';

  void atualizarConhecimentoCatalogo(List<String> resumosTitulos) {
    _catalogoConhecido = resumosTitulos.take(80).toList();
  }

  Future<void> registrarAprendizado(String fato) async {
    await inicializar();
    final limpo = fato.trim();
    if (limpo.isEmpty) return;
    _fatosAprendidos.remove(limpo);
    _fatosAprendidos.insert(0, limpo);
    if (_fatosAprendidos.length > 30) _fatosAprendidos = _fatosAprendidos.sublist(0, 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kAprendizadoAppKey, _fatosAprendidos);
  }

  Future<void> definirPerfilAtivo(String nome, {bool? infantil}) async {
    await inicializar();
    final limpo = nome.trim();
    if (limpo.isEmpty) return;
    final chave = limpo.toLowerCase();
    final existente = _perfis[chave];
    _perfis[chave] = (existente ?? MaxPerfilUsuario(nome: limpo)).copyWith(
      nome: limpo,
      infantil: infantil ?? existente?.infantil ?? false,
    );
    _perfilAtivo = limpo;
    await _salvar();
  }

  Future<void> registrarVisualizacao({
    required String titulo,
    bool ehSerie = false,
    int? temporada,
    int? episodio,
    String? preferenciaNota,
  }) async {
    await inicializar();
    final chave = (_perfilAtivo.isEmpty ? 'convidado' : _perfilAtivo.toLowerCase());
    final atual = _perfis[chave] ??
        MaxPerfilUsuario(nome: _perfilAtivo.isEmpty ? 'Convidado' : _perfilAtivo);

    final lista = List<String>.from(atual.historicoRecente);
    lista.removeWhere((e) => e.toLowerCase() == titulo.toLowerCase());
    lista.insert(0, titulo);
    if (lista.length > 15) lista.removeRange(15, lista.length);

    final prefsAprendidas = List<String>.from(atual.preferenciasAprendidas);
    if (preferenciaNota != null && preferenciaNota.trim().isNotEmpty) {
      prefsAprendidas.remove(preferenciaNota.trim());
      prefsAprendidas.insert(0, preferenciaNota.trim());
      if (prefsAprendidas.length > 12) prefsAprendidas.removeRange(12, prefsAprendidas.length);
    }

    _perfis[chave] = atual.copyWith(
      ultimaSerie: ehSerie ? titulo : atual.ultimaSerie,
      ultimaTemporada: ehSerie ? (temporada ?? atual.ultimaTemporada) : atual.ultimaTemporada,
      ultimoEpisodio: ehSerie ? (episodio ?? atual.ultimoEpisodio) : atual.ultimoEpisodio,
      historicoRecente: lista,
      preferenciasAprendidas: prefsAprendidas,
    );
    await _salvar();
  }

  String montarResumoContextoIA() {
    final buf = StringBuffer();
    if (_perfilAtivo.isNotEmpty) buf.writeln('Usuário falando agora: $_perfilAtivo.');
    for (final p in _perfis.values) {
      buf.write('- Perfil "${p.nome}" (${p.infantil ? "Infantil" : "Geral"}): ');
      if (p.ultimaSerie != null) {
        buf.write('parou em "${p.ultimaSerie}" T${p.ultimaTemporada}:E${p.ultimoEpisodio}; ');
      }
      if (p.historicoRecente.isNotEmpty) buf.write('viu: ${p.historicoRecente.take(5).join(", ")}; ');
      if (p.preferenciasAprendidas.isNotEmpty) buf.write('gostos: ${p.preferenciasAprendidas.take(4).join(", ")}.');
      buf.writeln();
    }
    if (_fatosAprendidos.isNotEmpty) buf.writeln('Aprendizados: ${_fatosAprendidos.take(10).join(" | ")}');
    if (_catalogoConhecido.isNotEmpty) buf.writeln('Catálogo CineMax: ${_catalogoConhecido.join(" ; ")}');
    return buf.toString();
  }

  Future<void> _salvar() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    _perfis.forEach((k, v) => map[k] = v.toJson());
    await prefs.setString(_kPerfisKey, jsonEncode(map));
    await prefs.setString(_kPerfilAtivoKey, _perfilAtivo);
  }
}
