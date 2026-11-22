import 'package:flutter/material.dart';
import '../services/max_assistant_service.dart';
import '../services/max_memory_service.dart';

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
    final nome = MaxMemoryService.instance.nomeAtual;
    final inicial = nome.isNotEmpty ? nome[0].toUpperCase() : 'U';

    return Focus(
      onFocusChange: (f) => setState(() => _focado = f),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _focado ? Colors.white : const Color(0xFFF5B82E).withOpacity(0.65),
              width: _focado ? 2.0 : 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: const Color(0xFFF5B82E),
                child: Text(inicial,
                    style: const TextStyle(color: Color(0xFF0B0D12), fontWeight: FontWeight.w900, fontSize: 12)),
              ),
              if (nome.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(nome, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PerfisSelectionOverlay extends StatefulWidget {
  final VoidCallback? onPerfilSelecionado;
  const PerfisSelectionOverlay({super.key, this.onPerfilSelecionado});

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
  Future<void> _selecionar(MaxPerfilUsuario perfil) async {
    await MaxMemoryService.instance.definirPerfilAtivo(perfil.nome, infantil: perfil.infantil);
    widget.onPerfilSelecionado?.call();
    if (mounted) Navigator.of(context).pop();
    MaxAssistantService.instance.falar('Olá, ${perfil.nome}! Perfil carregado. O que vamos assistir?');
  }

  Future<void> _novoPerfil() async {
    final nomeCtrl = TextEditingController();
    bool ehInfantil = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF141824),
          title: const Text('Novo Perfil CineMax', style: TextStyle(color: Color(0xFFF5B82E))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(hintText: 'Nome do usuário...', hintStyle: TextStyle(color: Colors.white38)),
              ),
              SwitchListTile(
                activeColor: const Color(0xFFF5B82E),
                title: const Text('Perfil Infantil (Kids)', style: TextStyle(color: Colors.white)),
                value: ehInfantil,
                onChanged: (v) => setLocal(() => ehInfantil = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF5B82E), foregroundColor: Colors.black),
              onPressed: () async {
                final nome = nomeCtrl.text.trim();
                if (nome.isEmpty) return;
                await MaxMemoryService.instance.definirPerfilAtivo(nome, infantil: ehInfantil);
                if (ctx.mounted) Navigator.pop(ctx);
                widget.onPerfilSelecionado?.call();
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perfis = MaxMemoryService.instance.perfis;
    return Dialog(
      backgroundColor: const Color(0xFF0E111A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFF5B82E), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Quem está assistindo?',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 22),
            Wrap(
              spacing: 18,
              runSpacing: 18,
              alignment: WrapAlignment.center,
              children: [
                ...perfis.map((p) => InkWell(
                      onTap: () => _selecionar(p),
                      child: Column(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5B82E),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(p.nome[0].toUpperCase(),
                                style: const TextStyle(color: Color(0xFF0B0D12), fontSize: 38, fontWeight: FontWeight.w900)),
                          ),
                          const SizedBox(height: 6),
                          Text(p.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )),
                InkWell(
                  onTap: _novoPerfil,
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: const Color(0xFF181D2B),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: const Icon(Icons.add_rounded, color: Color(0xFFF5B82E), size: 40),
                      ),
                      const SizedBox(height: 6),
                      const Text('Adicionar', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
