import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_cinema/models/midia_model.dart';
import 'package:app_cinema/screens/detalhe_obra_screen.dart';
import 'package:app_cinema/screens/tv_aux_screens.dart';
import 'package:app_cinema/screens/tv_home_screen.dart';

/// Teste de fumaça: garante que as telas principais sobem sem lançar
/// exceção na primeira renderização. Não usa golden files.
void main() {
  final obraExemplo = ObraAgrupada(
    chaveGrupo: 'filme_o_arbitro_1994',
    titulo: 'O Árbitro',
    categoria: 'Filme',
    genero: 'Comédia, Crime, Drama',
    sinopse:
        'Um ladrão azarado faz um casal em crise de refém na véspera de Natal.',
    capaUrl: '',
    bannerUrl: '',
    ano: '1994',
    emDestaque: false,
    ordemDestaque: 999,
    notaImdb: 6.6,
    diretor: 'Ted Demme',
    elenco: 'Denis Leary, Judy Davis, Kevin Spacey',
    tags: const ['1080p', 'Dual Áudio'],
    fontes: const [],
  );

  testWidgets('TvHomeScreen sobe sem erro', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TvHomeScreen(
          catalogo: [obraExemplo],
          onRefresh: () async {},
          onAbrirObra: (_) {},
          onAlternarModoMobile: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('DetalheObraScreen sobe sem erro', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: DetalheObraScreen(
          obra: obraExemplo,
          catalogoCompleto: [obraExemplo],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('TvTop100RankingScreen sobe sem erro', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: TvTop100RankingScreen(
          fonte: 'imdb',
          catalogo: [obraExemplo],
          onAbrirObra: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
