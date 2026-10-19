import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale/analysis/chord_engine.dart';
import 'package:scale/midi/midi_service.dart';
import 'package:scale/screens/song_editor.dart';
import 'package:scale/screens/song_list_page.dart';
import 'package:scale/settings.dart';
import 'package:scale/storage/song_repository.dart';
import 'package:scale_core/scale_core.dart';

const fmt = ChordFormatter();

Song songOf(String text, List<(int, int)> parts) {
  final song = Song.create(title: 'Prueba')
    ..chords.addAll([for (final s in text.split(' ')) ChordEvent(chord: ChordParser.parse(s)!)]);
  for (final (start, end) in parts) {
    final s = song.newSection(label: song.nextPartLabel());
    song
      ..sections.add(s)
      ..arrangement.add(SectionOccurrence(sectionId: s.id, start: start, end: end));
  }
  SongAnalyzer.analyze(song, sections: false);
  return song;
}

List<String> names(Song song) => [for (final c in song.chords) fmt.format(c.chord)];

void main() {
  late Directory dir;
  late SongRepository repo;
  late AppSettings settings;
  late MidiService midi;
  late ChordEngine engine;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scale_editor');
    repo = SongRepository(Directory('${dir.path}/songs'));
    settings = AppSettings(File('${dir.path}/settings.json'));
    midi = MidiService();
    engine = ChordEngine(midi, settings);
  });

  tearDown(() async {
    engine.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, Song song) async {
    tester.view.physicalSize = const Size(2304, 1440);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: SongEditor(
        song: song,
        repo: repo,
        settings: settings,
        midi: midi,
        engine: engine,
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// La celda de un acorde de la partitura (no los de la paleta).
  Finder cell(String name, {int at = 0}) => find.descendant(
        of: find.byType(ListView).first,
        matching: find.text(name),
      ).at(at);

  testWidgets('arrastrar un acorde de lado lo mueve a otra sección y se puede deshacer', (tester) async {
    final song = songOf('G D Em C Am F', [(0, 4), (4, 6)]);
    await tester.runAsync(() async => pump(tester, song));
    expect(find.text('Parte 1'), findsOneWidget);
    expect(find.text('Parte 2'), findsOneWidget);

    final from = tester.getCenter(cell('C'));
    final target = tester.getRect(cell('Am'));
    final gesture = await tester.startGesture(from);
    // De lado: el arrastre empieza sin esperar.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(Offset(target.left + 4, target.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(names(song), ['G', 'D', 'Em', 'C', 'Am', 'F']);
    expect([for (final o in song.arrangement) (o.start, o.end)], [(0, 3), (3, 6)]);

    await tester.tap(find.byTooltip('Deshacer (Ctrl+Z)'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect([for (final o in song.arrangement) (o.start, o.end)], [(0, 4), (4, 6)]);
  });

  testWidgets('arrastrar dentro de la misma sección cambia el orden', (tester) async {
    final song = songOf('G D Em C', [(0, 4)]);
    await tester.runAsync(() async => pump(tester, song));

    final from = tester.getCenter(cell('G'));
    final target = tester.getRect(cell('Em'));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(Offset(target.right - 4, target.center.dy)); // a la derecha de Em
    await tester.pump();
    await gesture.up();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(names(song), ['D', 'Em', 'G', 'C']);
  });

  testWidgets('editar una sección como texto', (tester) async {
    final song = songOf('G D Em C', [(0, 4)]);
    await tester.runAsync(() async => pump(tester, song));

    await tester.tap(find.text('Parte 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Acordes'), "G D'' Em C x2");
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(names(song), ['G', 'D', 'Em', 'C', 'G', 'D', 'Em', 'C']);
    expect(song.arrangement.single.repeats, 2);
    expect(song.chords[1].beats, 2);
  });

  test('la lista para tocar deja afuera las del archivo y sigue el orden', () async {
    final a = Song.create(title: 'A'), b = Song.create(title: 'B'), c = Song.create(title: 'C');
    for (final song in [a, b, c]) {
      await repo.save(song);
    }
    settings
      ..songOrder = [c.id, a.id, b.id]
      ..songSort = SongSort.manual
      ..setArchived(a.id, true);
    expect(SongListPage.liveList(repo, settings).map((s) => s.title), ['C', 'B']);
    settings.setArchived(a.id, false);
    expect(SongListPage.liveList(repo, settings).map((s) => s.title), ['C', 'A', 'B']);

    final back = AppSettings(File('${dir.path}/settings.json'));
    settings.setArchived(b.id, true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await back.load();
    expect(back.isArchived(b.id), isTrue);
    expect(back.songOrder, [c.id, a.id, b.id]);
  });

  test('orden de canciones: a mano, por título y tonalidad', () {
    Song s(String title, String key) => Song.create(title: title)..key = MusicKey.parse(key);
    final a = s('Óceanos', 'D'), b = s('Al que está sentado', 'G'), c = s('Cuán grande es Él', 'C');
    final songs = [a, b, c];
    expect(SongListPage.sorted(songs, SongSort.title, const []).map((x) => x.title),
        ['Al que está sentado', 'Cuán grande es Él', 'Óceanos']);
    expect(SongListPage.sorted(songs, SongSort.key, const []).map((x) => x.key!.name()), ['C', 'D', 'G']);
    expect(SongListPage.sorted(songs, SongSort.manual, [c.id, a.id]).map((x) => x.title).first, b.title,
        reason: 'las que no tienen lugar van primero');
    expect(SongListPage.sorted(songs, SongSort.manual, [b.id, c.id, a.id]).map((x) => x.title),
        ['Al que está sentado', 'Cuán grande es Él', 'Óceanos']);
  });
}
