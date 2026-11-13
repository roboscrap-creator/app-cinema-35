import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../models/catalogo_item.dart';

class VitrineScreen extends StatefulWidget {
  final SupabaseService supabase;
  const VitrineScreen({super.key, required this.supabase});

  @override
  State<VitrineScreen> createState() => _VitrineScreenState();
}

class _VitrineScreenState extends State<VitrineScreen> {
  List<dynamic> _abas = [];
  List<dynamic> _blocos = [];
  List<dynamic> _destaquesHero = [];
  List<CatalogoItem> _itensAprovados = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    setState(() => _carregando = true);
    try {
      final abas = await widget.supabase.listarAbas();
      final blocos = await widget.supabase.listarBlocos();
      final destaques = await widget.supabase.listarDestaquesHero();
      final aprovados = await widget.supabase.listarCatalogo(aprovado: true);
      if (mounted) {
        setState(() {
          _abas = abas;
          _blocos = blocos;
          _destaquesHero = destaques;
          _itensAprovados = aprovados;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _adicionarDestaqueHero() async {
    if (_itensAprovados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aprove ou cadastre pelo menos 1 filme/série antes!')),
      );
      return;
    }

    CatalogoItem selecionado = _itensAprovados.first;
    final ordemCtrl = TextEditingController(text: '${_destaquesHero.length + 1}');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Fixar no Banner Hero'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<CatalogoItem>(
                value: selecionado,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Título Aprovado', border: OutlineInputBorder()),
                items: _itensAprovados
                    .map((item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.titulo, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialog(() => selecionado = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ordemCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Posição no Banner (1, 2, 3...)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final ordem = int.tryParse(ordemCtrl.text) ?? 1;
                await widget.supabase.definirDestaqueHero(selecionado.id, true, ordem: ordem);
                if (ctx.mounted) Navigator.pop(ctx);
                _carregarTudo();
              },
              child: const Text('Salvar Destaque'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _novaAba() async {
    final nomeCtrl = TextEditingController();
    final ordemCtrl = TextEditingController(text: '${_abas.length + 1}');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova Aba no App Cinema'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome da Aba (ex: Lançamentos)')),
            const SizedBox(height: 10),
            TextField(controller: ordemCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ordem (1, 2, 3...)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (nomeCtrl.text.trim().isEmpty) return;
              await widget.supabase.criarAba(nomeCtrl.text.trim(), int.tryParse(ordemCtrl.text) ?? 1);
              if (ctx.mounted) Navigator.pop(ctx);
              _carregarTudo();
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  Future<void> _novoBloco(String idAba) async {
    final nomeCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    String tipoBusca = 'filmes_populares';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Novo Carrossel / Fileira'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Título da Fileira (ex: Ação 4K)')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: tipoBusca,
                decoration: const InputDecoration(labelText: 'Filtro'),
                items: const [
                  DropdownMenuItem(value: 'filmes_populares', child: Text('Todos os Filmes')),
                  DropdownMenuItem(value: 'series_populares', child: Text('Todas as Séries')),
                  DropdownMenuItem(value: 'genero', child: Text('Por Gênero')),
                  DropdownMenuItem(value: 'busca_personalizada', child: Text('Palavra-chave')),
                ],
                onChanged: (v) => setDialog(() => tipoBusca = v ?? 'filmes_populares'),
              ),
              if (tipoBusca == 'genero' || tipoBusca == 'busca_personalizada') ...[
                const SizedBox(height: 10),
                TextField(controller: valorCtrl, decoration: const InputDecoration(labelText: 'Valor (ex: Ação, Terror)')),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nomeCtrl.text.trim().isEmpty) return;
                await widget.supabase.criarBloco(idAba, nomeCtrl.text.trim(), tipoBusca, valorCtrl.text.trim(), 1);
                if (ctx.mounted) Navigator.pop(ctx);
                _carregarTudo();
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
    if (_carregando) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _carregarTudo,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            color: const Color(0xFF1A1812),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.amber.withOpacity(0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          '⭐ Banner Hero (Topo do App Cinema)',
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                        onPressed: _adicionarDestaqueHero,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Destacar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_destaquesHero.isEmpty)
                    const Text('Nenhum destaque fixado (usando os 5 últimos aprovados).', style: TextStyle(color: Colors.white54, fontSize: 12))
                  else
                    ..._destaquesHero.map((d) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.amber,
                            child: Text('#${d['ordem_destaque'] ?? 1}', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(d['titulo'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${d['categoria']} • ${d['resolucao']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              await widget.supabase.definirDestaqueHero(d['id'].toString(), false);
                              _carregarTudo();
                            },
                          ),
                        )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Abas & Fileiras', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(onPressed: _novaAba, icon: const Icon(Icons.tab, size: 18), label: const Text('Nova Aba')),
            ],
          ),
          const SizedBox(height: 10),
          if (_abas.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Sem abas personalizadas (o App Cinema usará Início, Filmes, Séries e TV Ao Vivo automaticamente).'),
              ),
            )
          else
            ..._abas.map((aba) {
              final idAba = aba['id'].toString();
              final blocosDaAba = _blocos.where((b) => b['id_aba'].toString() == idAba).toList();
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  title: Text('${aba['ordem']}. ${aba['nome']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.add_box_outlined, color: Colors.amber), onPressed: () => _novoBloco(idAba)),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () async {
                          await widget.supabase.excluirAba(idAba);
                          _carregarTudo();
                        },
                      ),
                    ],
                  ),
                  children: blocosDaAba
                      .map((b) => ListTile(
                            title: Text(b['nome'] ?? ''),
                            subtitle: Text('Filtro: ${b['tipo_busca']} ${b['valor_busca'] ?? ''}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () async {
                                await widget.supabase.excluirBloco(b['id'].toString());
                                _carregarTudo();
                              },
                            ),
                          ))
                      .toList(),
                ),
              );
            }),
        ],
      ),
    );
  }
}
