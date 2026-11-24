import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_cinema/models/midia_model.dart';
import 'package:app_cinema/screens/detalhe_obra_screen.dart';
import 'package:app_cinema/screens/tv_aux_screens.dart';
import 'package:app_cinema/screens/tv_home_screen.dart';

void main() {
  final obraExemplo = ObraAgrupada(
    chaveGrupo: 'filme_o_arbitro_1994',
    titulo: 'O Árbitro',
    categoria: 'Filme',
    genero: 'Comédia, Crime, Drama',
    ano: '1994',
    notaImdb: 6.6,
    sinopse: 'Um ladrão azarado faz um casal em crise de refém na véspera de Natal.',
    direcao: 'Ted Demme',
    elenco: 'Denis Leary, Judy Davis, Kevin Spacey',
    capaUrl: '',
    fundoUrl: '',
    tags: const ['1080p', 'Dual Áudio'],
    fontes: const [],
  );

  Future<void> capturarTela(
    WidgetTester tester,
    Size resolucao,
    String nomeArquivo,
    Widget tela,
  ) async {
    tester.view.physicalSize = resolucao;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: tela,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$nomeArquivo'));
  }

  testWidgets('Auditoria Visual - Celular e TV Box', (tester) async {
    await capturarTela(
      tester,
      const Size(1080, 2400),
      '01_home_celular.png',
      TvHomeScreen(catalogo: [obraExemplo], onAbrirObra: (_) {}),
    );

    await capturarTela(
      tester,
      const Size(1920, 1080),
      '02_home_tvbox.png',
      TvHomeScreen(catalogo: [obraExemplo], onAbrirObra: (_) {}),
    );

    await capturarTela(
      tester,
      const Size(1080, 2400),
      '03_detalhes_celular.png',
      DetalheObraScreen(obra: obraExemplo, catalogoCompleto: [obraExemplo]),
    );

    await capturarTela(
      tester,
      const Size(1080, 2400),
      '04_historico_favoritos_celular.png',
      TvTop100RankingScreen(catalogo: [obraExemplo], onAbrirObra: (_) {}),
    );
  });
}
