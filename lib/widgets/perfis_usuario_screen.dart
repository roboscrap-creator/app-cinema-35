import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/max_assistant_service.dart';
import '../services/max_memory_service.dart';
import 'cinema_widgets.dart';

class AvatarTematico {
  final String id;
  final String nome;
  final String categoria;
  final String emoji;
  final List<Color> cores;
  final String? imageUrl;

  const AvatarTematico({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.emoji,
    required this.cores,
    this.imageUrl,
  });
}

const List<AvatarTematico> kAvataresCineMax = [
  AvatarTematico(id: 'geral_pipoca', nome: 'Pipoca VIP', categoria: 'Geral', emoji: '🍿', cores: [Color(0xFFF5B82E), Color(0xFFC97B0C)]),
  AvatarTematico(id: 'geral_claquete', nome: 'Diretor', categoria: 'Geral', emoji: '🎬', cores: [Color(0xFF3A7BD5), Color(0xFF1F3C88)]),
  AvatarTematico(id: 'filme_heroi', nome: 'Herói', categoria: 'Filmes', emoji: '🦸', cores: [Color(0xFFE53935), Color(0xFF8E0000)]),
  AvatarTematico(id: 'filme_espaco', nome: 'Sci-Fi', categoria: 'Filmes', emoji: '🚀', cores: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
  AvatarTematico(id: 'filme_terror', nome: 'Suspense', categoria: 'Filmes', emoji: '👻', cores: [Color(0xFF434343), Color(0xFF121212)]),
  AvatarTematico(id: 'serie_coroa', nome: 'Trono', categoria: 'Séries', emoji: '👑', cores: [Color(0xFFD4AF37), Color(0xFF7A5C00)]),
  AvatarTematico(id: 'serie_detetive', nome: 'Detetive', categoria: 'Séries', emoji: '🕵️', cores: [Color(0xFF2C3E50), Color(0xFF4CA1AF)]),
  AvatarTematico(id: 'serie_dragao', nome: 'Fantasia', categoria: 'Séries', emoji: '🐉', cores: [Color(0xFF11998E), Color(0xFF0B4F4A)]),
  AvatarTematico(id: 'anime_ninja', nome: 'Ninja', categoria: 'Animes', emoji: '🥷', cores: [Color(0xFFFF512F), Color(0xFFDD2476)]),
  AvatarTematico(id: 'anime_katana', nome: 'Samurai', categoria: 'Animes', emoji: '⚔️', cores: [Color(0xFF8E2DE2), Color(0xFF4A00E0)]),
  AvatarTematico(id: 'anime_chama', nome: 'Shonen', categoria: 'Animes', emoji: '🔥', cores: [Color(0xFFFF8008), Color(0xFFFFC837)]),
  AvatarTematico(id: 'desenho_estrela', nome: 'Estrelinha', categoria: 'Desenhos', emoji: '⭐', cores: [Color(0xFFFFB75E), Color(0xFFED8F03)]),
  AvatarTematico(id: 'desenho_robo', nome: 'Robozinho', categoria: 'Desenhos', emoji: '🤖', cores: [Color(0xFF00B4DB), Color(0xFF0083B0)]),
  AvatarTematico(id: 'desenho_dino', nome: 'Dino Kids', categoria: 'Desenhos', emoji: '🦖', cores: [Color(0xFF56AB2F), Color(0xFFA8E063)]),
  AvatarTematico(id: 'desenho_unicornio', nome: 'Mágico', categoria: 'Desenhos', emoji: '🦄', cores: [Color(0xFFFC5C7D), Color(0xFF6A82FB)]),
  AvatarTematico(id: 'ator_rdj', nome: 'Tony Stark', categoria: 'Filmes', emoji: '🦾', cores: [Color(0xFFB71C1C), Color(0xFFF5B82E)], imageUrl: 'https://image.tmdb.org/t/p/w185/5qHNjhtjMD4YWH3UP0rm4tKwxCL.jpg'),
  AvatarTematico(id: 'ator_keanu', nome: 'John Wick', categoria: 'Filmes', emoji: '🕶️', cores: [Color(0xFF232526), Color(0xFF414345)], imageUrl: 'https://image.tmdb.org/t/p/w185/4D0PpNI0kmP58hgrwGC3wCjxhnm.jpg'),
  AvatarTematico(id: 'ator_bale', nome: 'Batman', categoria: 'Filmes', emoji: '🦇', cores: [Color(0xFF141E30), Color(0xFF243B55)], imageUrl: 'https://image.tmdb.org/t/p/w185/qCpZn2e3dimwbryLnqxZuI88PTi.jpg'),
  AvatarTematico(id: 'ator_depp', nome: 'Jack Sparrow', categoria: 'Filmes', emoji: '🏴‍☠️', cores: [Color(0xFF5D4157), Color(0xFFA8CABA)], imageUrl: 'https://image.tmdb.org/t/p/w185/ilPBHd3r3ahlipN1T4VWSPouMR.jpg'),
  AvatarTematico(id: 'ator_scarlett', nome: 'Viúva Negra', categoria: 'Filmes', emoji: '🕷️', cores: [Color(0xFF8E0E00), Color(0xFF1F1C18)], imageUrl: 'https://image.tmdb.org/t/p/w185/6NsMbJXRlDZuDzatN2akFdGuTvx.jpg'),
  AvatarTematico(id: 'ator_dicaprio', nome: 'DiCaprio', categoria: 'Filmes', emoji: '🎭', cores: [Color(0xFF1E3C72), Color(0xFF2A5298)], imageUrl: 'https://image.tmdb.org/t/p/w185/wo2hJpn04vbtmh0B9utCFdsQhxM.jpg'),
  AvatarTematico(id: 'serie_walter', nome: 'Walter White', categoria: 'Séries', emoji: '🧪', cores: [Color(0xFF134E5E), Color(0xFF71B280)], imageUrl: 'https://image.tmdb.org/t/p/w185/7Jahy5LZX2Fo8fGJltMreAI49hC.jpg'),
  AvatarTematico(id: 'serie_eleven', nome: 'Eleven', categoria: 'Séries', emoji: '⚡', cores: [Color(0xFF4A00E0), Color(0xFF8E2DE2)], imageUrl: 'https://image.tmdb.org/t/p/w185/2685xGmq68G6tmnzbfgSR6ctINZ.jpg'),
  AvatarTematico(id: 'serie_wandinha', nome: 'Wandinha', categoria: 'Séries', emoji: '🖤', cores: [Color(0xFF2C3E50), Color(0xFF000000)], imageUrl: 'https://image.tmdb.org/t/p/w185/q1NRzyZQlYkxLY07GO9NVPkQnu8.jpg'),
  AvatarTematico(id: 'serie_shelby', nome: 'Tommy Shelby', categoria: 'Séries', emoji: '🎩', cores: [Color(0xFF373B44), Color(0xFF4286F4)], imageUrl: 'https://image.tmdb.org/t/p/w185/llkbyWKwpfowZ6C8peBjIV9jj99.jpg'),
  AvatarTematico(id: 'serie_pascal', nome: 'Joel / Mando', categoria: 'Séries', emoji: '🛡️', cores: [Color(0xFF603813), Color(0xFFB29F94)], imageUrl: 'https://image.tmdb.org/t/p/w185/9VYK7oxcqhjd5LAH6ZFJ3XzOlID.jpg'),
  AvatarTematico(id: 'serie_jonsnow', nome: 'Jon Snow', categoria: 'Séries', emoji: '🐺', cores: [Color(0xFF232526), Color(0xFF606C88)], imageUrl: 'https://image.tmdb.org/t/p/w185/htGBMno71iVwih8LiQhWuJGjjmy.jpg'),
  AvatarTematico(id: 'serie_professor', nome: 'Professor', categoria: 'Séries', emoji: '👓', cores: [Color(0xFF8E0E00), Color(0xFF1F1C18)], imageUrl: 'https://image.tmdb.org/t/p/w185/4wXuQxyWcaIQc3gk1xrbXusdXAB.jpg'),
  AvatarTematico(id: 'anime_luffy', nome: 'Luffy', categoria: 'Animes', emoji: '👒', cores: [Color(0xFFE53935), Color(0xFFF5B82E)], imageUrl: 'https://cdn.myanimelist.net/images/characters/9/310307.jpg'),
  AvatarTematico(id: 'anime_zoro', nome: 'Zoro', categoria: 'Animes', emoji: '⚔️', cores: [Color(0xFF1B5E20), Color(0xFF4CAF50)], imageUrl: 'https://cdn.myanimelist.net/images/characters/3/100534.jpg'),
  AvatarTematico(id: 'anime_sanji', nome: 'Sanji', categoria: 'Animes', emoji: '🔥', cores: [Color(0xFF1A237E), Color(0xFFF5B82E)], imageUrl: 'https://cdn.myanimelist.net/images/characters/5/136769.jpg'),
  AvatarTematico(id: 'anime_goku', nome: 'Goku', categoria: 'Animes', emoji: '🐉', cores: [Color(0xFFFF6F00), Color(0xFF1565C0)], imageUrl: 'https://cdn.myanimelist.net/images/characters/9/160679.jpg'),
  AvatarTematico(id: 'anime_vegeta', nome: 'Vegeta', categoria: 'Animes', emoji: '⚡', cores: [Color(0xFF0D47A1), Color(0xFF42A5F5)], imageUrl: 'https://cdn.myanimelist.net/images/characters/14/86185.jpg'),
  AvatarTematico(id: 'anime_naruto', nome: 'Naruto', categoria: 'Animes', emoji: '🍥', cores: [Color(0xFFFF8F00), Color(0xFFFFCA28)], imageUrl: 'https://cdn.myanimelist.net/images/characters/2/284121.jpg'),
  AvatarTematico(id: 'anime_madara', nome: 'Madara', categoria: 'Animes', emoji: '👁️', cores: [Color(0xFF880E4F), Color(0xFF1A1A1A)], imageUrl: 'https://cdn.myanimelist.net/images/characters/12/450359.jpg'),
  AvatarTematico(id: 'anime_gaara', nome: 'Gaara', categoria: 'Animes', emoji: '🏜️', cores: [Color(0xFF6D4C41), Color(0xFFD84315)], imageUrl: 'https://cdn.myanimelist.net/images/characters/10/293375.jpg'),
  AvatarTematico(id: 'anime_hinata', nome: 'Hinata', categoria: 'Animes', emoji: '💜', cores: [Color(0xFF4A148C), Color(0xFF7E57C2)], imageUrl: 'https://cdn.myanimelist.net/images/characters/6/278736.jpg'),
  AvatarTematico(id: 'anime_levi', nome: 'Levi', categoria: 'Animes', emoji: '🗡️', cores: [Color(0xFF263238), Color(0xFF546E7A)], imageUrl: 'https://cdn.myanimelist.net/images/characters/2/241413.jpg'),
  AvatarTematico(id: 'anime_l', nome: 'L', categoria: 'Animes', emoji: '🕵️', cores: [Color(0xFF212121), Color(0xFF616161)], imageUrl: 'https://cdn.myanimelist.net/images/characters/10/249647.jpg'),
  AvatarTematico(id: 'anime_lelouch', nome: 'Lelouch', categoria: 'Animes', emoji: '👑', cores: [Color(0xFF311B92), Color(0xFFD50000)], imageUrl: 'https://cdn.myanimelist.net/images/characters/8/406163.jpg'),
];

AvatarTematico buscarAvatarPorId(String id) {
  for (final a in kAvataresCineMax) {
    if (a.id == id) return a;
  }
  return kAvataresCineMax.first;
}

class AvatarIlustradoWidget extends StatelessWidget {
  final String avatarId;
  final double size;
  final bool infantil;

  const AvatarIlustradoWidget({super.key, required this.avatarId, this.size = 76, this.infantil = false});

  @override
  Widget build(BuildContext context) {
    final av = buscarAvatarPorId(avatarId);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.24),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: av.cores),
            boxShadow: [BoxShadow(color: av.cores.first.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          clipBehavior: Clip.antiAlias,
          child: (av.imageUrl != null && av.imageUrl!.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: av.imageUrl!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  memCacheWidth: 160,
                  fadeInDuration: Duration.zero,
                  placeholder: (_, __) => Center(child: Text(av.emoji, style: TextStyle(fontSize: size * 0.48))),
                  errorWidget: (_, __, ___) => Center(child: Text(av.emoji, style: TextStyle(fontSize: size * 0.48))),
                )
              : Text(av.emoji, style: TextStyle(fontSize: size * 0.48)),
        ),
        if (infantil)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00D2FF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF0A0C10), width: 1.5),
              ),
              child: const Text('KIDS', style: TextStyle(color: Colors.black, fontSize: 8.5, fontWeight: FontWeight.w900)),
            ),
          ),
      ],
    );
  }
}

class PerfilChipTopButton extends StatefulWidget {
  final VoidCallback onTap;
  const PerfilChipTopButton({super.key, required this.onTap});

  @override
  State<PerfilChipTopButton> createState() => _PerfilChipTopButtonState();
}

class _PerfilChipTopButtonState extends State<PerfilChipTopButton> {
  bool _focado = false;

  @override
  Widget build(BuildContext context) {
    final perfil = MaxMemoryService.instance.perfilAtual;
    final nome = perfil?.nome ?? 'Geral';
    final avatarId = perfil?.avatarId ?? 'geral_pipoca';
    final kids = perfil?.infantil == true;

    return CinemaFocusBox(
      onTap: widget.onTap,
      borderRadius: 22,
      scaleOnFocus: 1.06,
      onFocusChanged: (f) { if (mounted) setState(() => _focado = f); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1F2E),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _focado ? Colors.white : const Color(0xFFF5B82E).withOpacity(0.65), width: _focado ? 2.0 : 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarIlustradoWidget(avatarId: avatarId, size: 24, infantil: false),
            const SizedBox(width: 6),
            Text(kids ? '$nome • Kids' : nome, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class PerfisSelectionOverlay extends StatefulWidget {
  final VoidCallback? onPerfilSelecionado;
  final bool obrigatorio;

  const PerfisSelectionOverlay({super.key, this.onPerfilSelecionado, this.obrigatorio = false});

  static Future<void> abrir(BuildContext context, {VoidCallback? onPerfilSelecionado}) async {
    await MaxMemoryService.instance.inicializar();
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.88),
      builder: (_) => PerfisSelectionOverlay(onPerfilSelecionado: onPerfilSelecionado),
    );
  }

  @override
  State<PerfisSelectionOverlay> createState() => _PerfisSelectionOverlayState();
}

class _PerfisSelectionOverlayState extends State<PerfisSelectionOverlay> {
  bool _modoGerenciar = false;

  Future<void> _selecionar(MaxPerfilUsuario perfil) async {
    if (_modoGerenciar) {
      await _abrirFormPerfil(editar: perfil);
      return;
    }
    await MaxMemoryService.instance.definirPerfilAtivo(perfil.nome, infantil: perfil.infantil, avatarId: perfil.avatarId);
    widget.onPerfilSelecionado?.call();
    if (!widget.obrigatorio && mounted) Navigator.of(context).pop();
    if (perfil.nome.toLowerCase() != 'geral') {
      MaxAssistantService.instance.falar('Olá, ${perfil.nome}! O que vamos assistir hoje?');
    }
  }

  Future<void> _abrirFormPerfil({MaxPerfilUsuario? editar}) async {
    final ehEdicao = editar != null;
    final ehGeral = editar?.nome.toLowerCase() == 'geral';
    final nomeCtrl = TextEditingController(text: editar?.nome ?? '');
    bool ehInfantil = editar?.infantil ?? false;
    String categoriaFiltro = 'Todos';
    String avatarSelecionado = editar?.avatarId ?? 'geral_pipoca';
    const categorias = ['Todos', 'Filmes', 'Séries', 'Animes', 'Desenhos', 'Geral'];

    try {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final avataresFiltrados = categoriaFiltro == 'Todos'
              ? kAvataresCineMax
              : kAvataresCineMax.where((a) => a.categoria == categoriaFiltro).toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF141824),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFF5B82E), width: 1.4)),
            title: Text(
              ehEdicao ? 'Editar Perfil' : 'Novo Perfil CineMax',
              style: const TextStyle(color: Color(0xFFF5B82E), fontWeight: FontWeight.w900),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nomeCtrl,
                      enabled: !ehGeral,
                      autofocus: !ehEdicao,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Nome do perfil...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1E2436),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFFF5B82E),
                      title: const Text('Perfil Kids (filtra conteúdo infantil)', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                      value: ehInfantil,
                      onChanged: (v) => setLocal(() {
                        ehInfantil = v;
                        if (v) avatarSelecionado = 'desenho_estrela';
                      }),
                    ),
                    const SizedBox(height: 8),
                    const Text('Escolha uma foto / avatar:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 34,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categorias.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, idx) {
                          final cat = categorias[idx];
                          final ativo = cat == categoriaFiltro;
                          return CinemaFocusBox(
                            borderRadius: 16,
                            onTap: () => setLocal(() => categoriaFiltro = cat),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: ativo ? const Color(0xFFF5B82E) : Colors.white12,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: Text(cat, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ativo ? Colors.black : Colors.white)),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: avataresFiltrados.map((av) {
                        final sel = av.id == avatarSelecionado;
                        return CinemaFocusBox(
                          borderRadius: 16,
                          scaleOnFocus: 1.06,
                          onTap: () => setLocal(() => avatarSelecionado = av.id),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: sel ? const Color(0xFFF5B82E) : Colors.transparent, width: 2.5),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AvatarIlustradoWidget(avatarId: av.id, size: 52),
                                const SizedBox(height: 3),
                                Text(av.nome, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (ehEdicao && !ehGeral)
                CinemaFocusBox(
                  borderRadius: 10,
                  onTap: () async {
                    await MaxMemoryService.instance.excluirPerfil(editar!.nome);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                    widget.onPerfilSelecionado?.call();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        SizedBox(width: 4),
                        Text('Excluir', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              CinemaFocusBox(
                borderRadius: 10,
                onTap: () => Navigator.pop(ctx),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Cancelar', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                ),
              ),
              CinemaFocusBox(
                borderRadius: 10,
                onTap: () async {
                  final nome = nomeCtrl.text.trim();
                  if (nome.isEmpty) return;
                  if (ehEdicao) {
                    await MaxMemoryService.instance.editarPerfil(
                      nomeAntigo: editar!.nome,
                      novoNome: nome,
                      infantil: ehInfantil,
                      avatarId: avatarSelecionado,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                    widget.onPerfilSelecionado?.call();
                  } else {
                    await MaxMemoryService.instance.definirPerfilAtivo(nome, infantil: ehInfantil, avatarId: avatarSelecionado);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                    widget.onPerfilSelecionado?.call();
                    if (!widget.obrigatorio && mounted) Navigator.pop(context);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(color: const Color(0xFFF5B82E), borderRadius: BorderRadius.circular(10)),
                  child: const Text('Salvar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          );
        },
      ),
    );
    } finally {
      nomeCtrl.dispose();
    }
  }

  Widget _buildConteudo() {
    final perfis = MaxMemoryService.instance.perfis;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CinemaLogoWidget(height: 46, width: 170),
            const SizedBox(height: 20),
            Text(
              _modoGerenciar ? 'Toque em um perfil para editar ou excluir' : 'Quem está assistindo?',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 22,
              runSpacing: 22,
              alignment: WrapAlignment.center,
              children: [
                ...perfis.asMap().entries.map((entry) {
                  final p = entry.value;
                  return CinemaFocusBox(
                    autofocus: entry.key == 0,
                    borderRadius: 20,
                    scaleOnFocus: 1.08,
                    onTap: () => _selecionar(p),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AvatarIlustradoWidget(avatarId: p.avatarId, size: 88, infantil: p.infantil),
                              if (_modoGerenciar)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(21),
                                    ),
                                    child: const Icon(Icons.edit_rounded, color: Color(0xFFF5B82E), size: 34),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(p.nome, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  );
                }),
                CinemaFocusBox(
                  borderRadius: 20,
                  scaleOnFocus: 1.08,
                  onTap: () => _abrirFormPerfil(),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: const Color(0xFF181D2B),
                            borderRadius: BorderRadius.circular(21),
                            border: Border.all(color: Colors.white30, width: 1.5),
                          ),
                          child: const Icon(Icons.add_rounded, color: Color(0xFFF5B82E), size: 42),
                        ),
                        const SizedBox(height: 8),
                        const Text('Adicionar Perfil', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            CinemaFocusBox(
              borderRadius: 22,
              scaleOnFocus: 1.05,
              onTap: () => setState(() => _modoGerenciar = !_modoGerenciar),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _modoGerenciar ? const Color(0xFFF5B82E) : Colors.white10,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFF5B82E)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _modoGerenciar ? Icons.check_rounded : Icons.manage_accounts_rounded,
                      color: _modoGerenciar ? Colors.black : const Color(0xFFF5B82E),
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _modoGerenciar ? 'Concluir Edição' : 'Editar / Excluir Perfis',
                      style: TextStyle(
                        color: _modoGerenciar ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.obrigatorio) {
      return Scaffold(backgroundColor: const Color(0xFF0A0C10), body: SafeArea(child: _buildConteudo()));
    }
    return Dialog(
      backgroundColor: const Color(0xFF0E111A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFFF5B82E), width: 1.5)),
      child: _buildConteudo(),
    );
  }
}
