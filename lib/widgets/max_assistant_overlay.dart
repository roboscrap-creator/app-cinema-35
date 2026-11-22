import 'package:flutter/material.dart';
import '../services/max_assistant_service.dart';
import '../services/max_memory_service.dart';
import '../services/pedidos_scrape_service.dart';

class MaxMicButton extends StatefulWidget {
  final VoidCallback onPressed;
  const MaxMicButton({super.key, required this.onPressed});

  @override
  State<MaxMicButton> createState() => _MaxMicButtonState();
}

class _MaxMicButtonState extends State<MaxMicButton> {
  bool _focado = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MaxAssistantService.instance,
      builder: (context, _) {
        final max = MaxAssistantService.instance;
        final ativo = max.ouvindo || max.falando || max.processando;
        return Focus(
          onFocusChange: (f) => setState(() => _focado = f),
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: ativo || _focado
                      ? const [Color(0xFFFFDF73), Color(0xFFF5B82E)]
                      : const [Color(0xFF232838), Color(0xFF151822)],
                ),
                border: Border.all(
                  color: _focado ? Colors.white : const Color(0xFFF5B82E),
                  width: _focado ? 2.2 : 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    max.ouvindo ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                    size: 18,
                    color: ativo || _focado ? const Color(0xFF0B0D12) : const Color(0xFFF5B82E),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    max.ouvindo ? 'Ouvindo...' : 'Max',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ativo || _focado ? const Color(0xFF0B0D12) : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PedidosScreenModal extends StatefulWidget {
  const PedidosScreenModal({super.key});

  static Future<void> abrir(BuildContext context) async {
    await PedidosScrapeService.instance.inicializar();
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const PedidosScreenModal(),
    );
  }

  @override
  State<PedidosScreenModal> createState() => _PedidosScreenModalState();
}

class _PedidosScreenModalState extends State<PedidosScreenModal> {
  final TextEditingController _tituloCtrl = TextEditingController();
  String _tipoSelecionado = 'Filme';
  bool _enviando = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final titulo = _tituloCtrl.text.trim();
    if (titulo.isEmpty) return;
    setState(() => _enviando = true);
    final remotoOk = await PedidosScrapeService.instance.enviarPedido(titulo: titulo, tipo: _tipoSelecionado);
    _tituloCtrl.clear();
    if (mounted) {
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1D2230),
          content: Text(
            remotoOk ? 'Pedido "$titulo" enviado direto para o Robô Scrape!' : 'Pedido "$titulo" salvo na lista!',
            style: const TextStyle(color: Color(0xFFFFDF73), fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PedidosScrapeService.instance,
      builder: (context, _) {
        final lista = PedidosScrapeService.instance.pedidos;
        return Container(
          height: MediaQuery.of(context).size.height * 0.78,
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF10131C),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF5B82E), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.playlist_add_check_circle_rounded, color: Color(0xFFF5B82E), size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Pedidos de Filmes & Séries',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tituloCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Nome do filme, série ou anime...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1A1F2E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _enviar(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: _tipoSelecionado,
                    dropdownColor: const Color(0xFF1A1F2E),
                    style: const TextStyle(color: Color(0xFFF5B82E), fontWeight: FontWeight.w700),
                    items: const [
                      DropdownMenuItem(value: 'Filme', child: Text('Filme')),
                      DropdownMenuItem(value: 'Série', child: Text('Série')),
                      DropdownMenuItem(value: 'Anime', child: Text('Anime')),
                    ],
                    onChanged: (v) { if (v != null) setState(() => _tipoSelecionado = v); },
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _enviando ? null : _enviar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5B82E),
                      foregroundColor: const Color(0xFF0B0D12),
                    ),
                    child: const Text('Pedir', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: lista.isEmpty
                    ? const Center(child: Text('Nenhum pedido feito ainda.', style: TextStyle(color: Colors.white54)))
                    : ListView.separated(
                        itemCount: lista.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final item = lista[idx];
                          return ListTile(
                            tileColor: const Color(0xFF171B26),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            leading: const Icon(Icons.movie_filter_rounded, color: Color(0xFFF5B82E)),
                            title: Text(item.titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            subtitle: Text('${item.tipo} • ${item.solicitadoPor} (${item.dataHora})',
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            trailing: Text(
                              item.enviadoParaScrape ? 'No Robô' : 'Salvo',
                              style: TextStyle(
                                color: item.enviadoParaScrape ? Colors.greenAccent : Colors.amberAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MaxAssistantModal extends StatefulWidget {
  const MaxAssistantModal({super.key});

  static Future<void> abrir(BuildContext context) async {
    MaxAssistantService.instance.iniciarEscuta();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const MaxAssistantModal(),
    );
  }

  @override
  State<MaxAssistantModal> createState() => _MaxAssistantModalState();
}

class _MaxAssistantModalState extends State<MaxAssistantModal> {
  final TextEditingController _textoCtrl = TextEditingController();

  @override
  void dispose() {
    _textoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MaxAssistantService.instance,
      builder: (context, _) {
        final max = MaxAssistantService.instance;
        final nomeUsuario = MaxMemoryService.instance.nomeAtual;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF121621),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF5B82E), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFF5B82E),
                      child: Icon(Icons.auto_awesome_rounded, color: Color(0xFF0B0D12)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        nomeUsuario.isNotEmpty ? 'Max • Olá, $nomeUsuario!' : 'Max • Assistente CineMax',
                        style: const TextStyle(color: Color(0xFFF5B82E), fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        PedidosScreenModal.abrir(context);
                      },
                      child: const Text('Pedidos', style: TextStyle(color: Color(0xFFF5B82E))),
                    ),
                    IconButton(
                      autofocus: true,
                      onPressed: () => max.ouvindo ? max.pararTudo() : max.iniciarEscuta(),
                      icon: Icon(
                        max.ouvindo ? Icons.stop_circle_rounded : Icons.mic_rounded,
                        color: const Color(0xFFF5B82E),
                        size: 30,
                      ),
                    ),
                  ],
                ),
                if (max.textoReconhecido.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('"${max.textoReconhecido}"',
                      style: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 12),
                Text(max.ultimaFalaMax, style: const TextStyle(color: Color(0xFFFFF4D2), fontSize: 15, height: 1.35)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textoCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Ou escreva para a Max...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFF1A1F2E),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (v) {
                          if (v.trim().isNotEmpty) {
                            _textoCtrl.clear();
                            max.processarComando(v.trim());
                          }
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        final v = _textoCtrl.text.trim();
                        if (v.isNotEmpty) {
                          _textoCtrl.clear();
                          max.processarComando(v);
                        }
                      },
                      icon: const Icon(Icons.send_rounded, color: Color(0xFFF5B82E)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
