import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';

class MaxPerfilUsuario {
  final String nome;
  final bool infantil;
  final String avatarId;
  final String? ultimaSerie;
  final int ultimaTemporada;
  final int ultimoEpisodio;
  final List<String> historicoRecente;
  final List<String> preferenciasAprendidas;

  const MaxPerfilUsuario({
    required this.nome,
    this.infantil = false,
    this.avatarId = 'geral_pipoca',
    this.ultimaSerie,
    this.ultimaTemporada = 1,
    this.ultimoEpisodio = 1,
    this.historicoRecente = const [],
    this.preferenciasAprendidas = const [],
  });

  MaxPerfilUsuario copyWith({
    String? nome,
    bool? infantil,
    String? avatarId,
    String? ultimaSerie,
    int? ultimaTemporada,
    int? ultimoEpisodio,
    List<String>? historicoRecente,
    List<String>? preferenciasAprendidas,
  }) {
    return MaxPerfilUsuario(
      nome: nome ?? this.nome,
      infantil: infantil ?? this.infantil,
      avatarId: avatarId ?? this.avatarId,
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
        'avatarId': avatarId,
        'ultimaSerie': ultimaSerie,
        'ultimaTemporada': ultimaTemporada,
        'ultimoEpisodio': ultimoEpisodio,
        'historicoRecente': historicoRecente,
        'preferenciasAprendidas': preferenciasAprendidas,
      };

  factory MaxPerfilUsuario.fromJson(Map<String, dynamic> json) {
    return MaxPerfilUsuario(
      nome: (json['nome'] ?? 'Geral').toString(),
      infantil: json['infantil'] == true,
      avatarId: (json['avatarId'] ?? (json['infantil'] == true ? 'desenho_estrela' : 'geral_pipoca')).toString(),
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
  static const String _kApelidosVozKey = 'cinemax_max_apelidos_voz_v1';
  static const String _kCacheRespostasKey = 'cinemax_max_cache_respostas_v1';

  static final MaxMemoryService instance = MaxMemoryService._();
  MaxMemoryService._();

  final Map<String, MaxPerfilUsuario> _perfis = {};
  String _perfilAtivo = '';
  List<String> _catalogoConhecido = [];
  List<String> _fatosAprendidos = [];
  Map<String, String> _apelidosVoz = {};
  Map<String, String> _cacheRespostas = {};
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

    if (!_perfis.containsKey('geral')) {
      _perfis['geral'] = const MaxPerfilUsuario(
        nome: 'Geral',
        infantil: false,
        avatarId: 'geral_pipoca',
      );
    }

    _perfilAtivo = prefs.getString(_kPerfilAtivoKey) ?? 'Geral';
    _fatosAprendidos = prefs.getStringList(_kAprendizadoAppKey) ?? [];

    try {
      final rawApelidos = prefs.getString(_kApelidosVozKey);
      if (rawApelidos != null) _apelidosVoz = Map<String, String>.from(jsonDecode(rawApelidos) as Map);
    } catch (_) {}

    try {
      final rawCache = prefs.getString(_kCacheRespostasKey);
      if (rawCache != null) _cacheRespostas = Map<String, String>.from(jsonDecode(rawCache) as Map);
    } catch (_) {}

    _carregado = true;
    await _carregarPerfisDaNuvem();
    _sincronizarCerebroGlobalSupabase();
  }

  List<MaxPerfilUsuario> get perfis {
    final lista = _perfis.values.toList();
    lista.sort((a, b) {
      if (a.nome.toLowerCase() == 'geral') return -1;
      if (b.nome.toLowerCase() == 'geral') return 1;
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });
    return lista;
  }

  MaxPerfilUsuario? get perfilAtual {
    if (_perfilAtivo.isEmpty) return _perfis['geral'];
    return _perfis[_perfilAtivo.toLowerCase()] ?? _perfis['geral'];
  }

  String get nomeAtual => perfilAtual?.nome ?? 'Geral';
  bool get modoKidsAtivo => perfilAtual?.infantil == true;

  void atualizarConhecimentoCatalogo(List<String> resumosTitulos) {
    _catalogoConhecido = resumosTitulos.take(80).toList();
  }

  Future<void> definirPerfilAtivo(String nome, {bool? infantil, String? avatarId}) async {
    await inicializar();
    final limpo = nome.trim();
    if (limpo.isEmpty) return;
    final chave = limpo.toLowerCase();
    final existente = _perfis[chave];
    _perfis[chave] = (existente ?? MaxPerfilUsuario(nome: limpo)).copyWith(
      nome: limpo,
      infantil: infantil ?? existente?.infantil ?? false,
      avatarId: avatarId ?? existente?.avatarId ?? ((infantil == true) ? 'desenho_estrela' : 'geral_pipoca'),
    );
    _perfilAtivo = limpo;
    await _salvar();
    _enviarPerfilSupabase(_perfis[chave]!);
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

  String? buscarApelidoVoz(String termoFalado) {
    return _apelidosVoz[SupabaseService.normalizarTexto(termoFalado.trim())];
  }

  Future<void> registrarApelidoVoz(String termoFalado, String tituloReal) async {
    await inicializar();
    final norm = SupabaseService.normalizarTexto(termoFalado.trim());
    if (norm.isEmpty || tituloReal.trim().isEmpty) return;
    _apelidosVoz[norm] = tituloReal.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApelidosVozKey, jsonEncode(_apelidosVoz));
    _gravarConhecimentoGlobal('apelido_voz', norm, tituloReal.trim());
  }

  String? buscarCacheResposta(String pergunta) {
    return _cacheRespostas[SupabaseService.normalizarTexto(pergunta.trim())];
  }

  Future<void> salvarCacheResposta(String pergunta, String jsonResposta) async {
    await inicializar();
    final norm = SupabaseService.normalizarTexto(pergunta.trim());
    if (norm.isEmpty) return;
    _cacheRespostas[norm] = jsonResposta;
    if (_cacheRespostas.length > 80) _cacheRespostas.remove(_cacheRespostas.keys.first);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCacheRespostasKey, jsonEncode(_cacheRespostas));
    _gravarConhecimentoGlobal('cache_ia', norm, jsonResposta);
  }

  Future<void> registrarVisualizacao({
    required String titulo,
    bool ehSerie = false,
    int? temporada,
    int? episodio,
    String? preferenciaNota,
  }) async {
    await inicializar();
    final chave = (_perfilAtivo.isEmpty ? 'geral' : _perfilAtivo.toLowerCase());
    final atual = _perfis[chave] ?? MaxPerfilUsuario(nome: _perfilAtivo.isEmpty ? 'Geral' : _perfilAtivo);
    final lista = List<String>.from(atual.historicoRecente)
      ..removeWhere((e) => e.toLowerCase() == titulo.toLowerCase())
      ..insert(0, titulo);
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
    _enviarPerfilSupabase(_perfis[chave]!);
  }

  String montarResumoContextoIA() {
    final buf = StringBuffer();
    if (_perfilAtivo.isNotEmpty) buf.writeln('Usuário falando agora: $_perfilAtivo (Kids: $modoKidsAtivo).');
    for (final p in _perfis.values) {
      buf.write('- Perfil "${p.nome}" (${p.infantil ? "Infantil" : "Geral"}): ');
      if (p.ultimaSerie != null) buf.write('parou em "${p.ultimaSerie}" T${p.ultimaTemporada}:E${p.ultimoEpisodio}; ');
      if (p.historicoRecente.isNotEmpty) buf.write('viu: ${p.historicoRecente.take(5).join(", ")}; ');
      if (p.preferenciasAprendidas.isNotEmpty) buf.write('gostos: ${p.preferenciasAprendidas.take(4).join(", ")}.');
      buf.writeln();
    }
    if (_fatosAprendidos.isNotEmpty) buf.writeln('Aprendizados: ${_fatosAprendidos.take(10).join(" | ")}');
    if (_catalogoConhecido.isNotEmpty) buf.writeln('Catálogo CineMax: ${_catalogoConhecido.join(" ; ")}');
    return buf.toString();
  }


  Future<void> _carregarPerfisDaNuvem() async {
    try {
      final dev = await SupabaseService.getDeviceId();
      final key = await SupabaseService.getAnonKey();
      final uri = Uri.parse('${SupabaseService.baseUrl}/rest/v1/max_perfis_usuario?nome_chave=like.${Uri.encodeComponent(dev)}_*&select=nome_chave,dados&limit=20');
      final resp = await http.get(uri, headers: {'apikey': key, 'Authorization': 'Bearer $key'}).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        for (final row in (jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>)) {
          if (row is Map && row['dados'] is Map) {
            final full = (row['nome_chave'] ?? '').toString().toLowerCase();
            final ch = full.startsWith('${dev}_') ? full.substring(dev.length + 1) : full;
            if (ch.isNotEmpty) {
              _perfis[ch] = MaxPerfilUsuario.fromJson(Map<String, dynamic>.from(row['dados'] as Map));
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _sincronizarCerebroGlobalSupabase() async {
    try {
      final key = await SupabaseService.getAnonKey();
      final uri = Uri.parse('${SupabaseService.baseUrl}/rest/v1/max_cerebro_global?select=tipo,chave,valor&limit=150');
      final resp = await http.get(uri, headers: {'apikey': key, 'Authorization': 'Bearer $key'}).timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        for (final row in (jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>)) {
          if (row is Map) {
            final tipo = (row['tipo'] ?? '').toString();
            final ch = (row['chave'] ?? '').toString();
            final val = (row['valor'] ?? '').toString();
            if (tipo == 'apelido_voz' && ch.isNotEmpty && val.isNotEmpty) _apelidosVoz[ch] = val;
            if (tipo == 'cache_ia' && ch.isNotEmpty && val.isNotEmpty) _cacheRespostas[ch] = val;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _gravarConhecimentoGlobal(String tipo, String chave, String valor) async {
    try {
      final key = await SupabaseService.getAnonKey();
      await http.post(
        Uri.parse('${SupabaseService.baseUrl}/rest/v1/max_cerebro_global'),
        headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode({'tipo': tipo, 'chave': chave, 'valor': valor, 'atualizado_em': DateTime.now().toIso8601String()}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _enviarPerfilSupabase(MaxPerfilUsuario perfil) async {
    try {
      final key = await SupabaseService.getAnonKey();
      await http.post(
        Uri.parse('${SupabaseService.baseUrl}/rest/v1/max_perfis_usuario'),
        headers: {'apikey': key, 'Authorization': 'Bearer $key', 'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates'},
        body: jsonEncode({'nome_chave': '${await SupabaseService.getDeviceId()}_${perfil.nome.toLowerCase()}', 'dados': perfil.toJson(), 'atualizado_em': DateTime.now().toIso8601String()}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _salvar() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    _perfis.forEach((k, v) => map[k] = v.toJson());
    await prefs.setString(_kPerfisKey, jsonEncode(map));
    await prefs.setString(_kPerfilAtivoKey, _perfilAtivo);
  }
}
