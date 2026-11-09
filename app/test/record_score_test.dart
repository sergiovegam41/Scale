import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale/analysis/chord_engine.dart';
import 'package:scale/midi/keyboard_state.dart';
import 'package:scale/midi/midi_service.dart';
import 'package:scale/screens/record_score_page.dart';
import 'package:scale/settings.dart';
import 'package:scale/storage/score_repository.dart';
import 'package:scale/storage/song_repository.dart';

void main() {
  late Directory dir;
  late MidiService midi;
  late ChordEngine engine;
  late KeyboardState keyboard;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scale_record');
    midi = MidiService();
    engine = ChordEngine(midi, AppSettings(File('${dir.path}/settings.json')));
    keyboard = KeyboardState(midi.events);
  });

  tearDown(() async {
    engine.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: RecordScorePage(
        midi: midi,
        keyboard: keyboard,
        engine: engine,
        scores: ScoreRepository(Directory('${dir.path}/scores')),
        songs: SongRepository(Directory('${dir.path}/songs')),
      ),
    ));
  }

  for (final (name, size) in [('tablet', const Size(2304, 1440)), ('teléfono', const Size(1080, 2340))]) {
    testWidgets('configurar, grabar y ver lo tocado ($name)', (tester) async {
      await pump(tester, size);
      expect(find.text('Compás'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      await tester.tap(find.text('3/4'));
      await tester.pump();
      await tester.ensureVisible(find.text('Empezar'));
      await tester.tap(find.text('Empezar'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Terminar y escribir'), findsOneWidget);
      // Tres pulsos en 3/4.
      expect(find.text('Lo que toques aparece aquí'), findsOneWidget);
      midi.debugInject(MidiInput(
        time: midi.now,
        kind: MidiInputKind.noteOn,
        channel: 0,
        data1: 64,
        data2: 90,
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Lo que toques aparece aquí'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Descartar'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Empezar'), findsOneWidget);
    });
  }
}
