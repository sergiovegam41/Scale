import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

const fmt = ChordFormatter();

List<Chord> chords(String text) => [for (final s in text.split(' ')) ChordParser.parse(s)!];

/// Canción con partes (inicio, fin, vueltas) sobre la secuencia lineal.
Song songOf(String text, List<(int, int, int)> parts) {
  final song = Song.create(title: 'x')
    ..chords.addAll([
      for (final (i, c) in chords(text).indexed) ChordEvent(chord: c, startMicros: i * 1000000),
    ]);
  for (final (start, end, repeats) in parts) {
    final s = song.newSection(label: song.nextPartLabel());
    song
      ..sections.add(s)
      ..arrangement.add(SectionOccurrence(sectionId: s.id, start: start, end: end, repeats: repeats));
  }
  return song;
}

List<String> names(Song song) => [for (final c in song.chords) fmt.format(c.chord)];
List<(int, int, int)> parts(Song song) => [for (final o in song.arrangement) (o.start, o.end, o.repeats)];

void main() {
  group('edición por vueltas', () {
    test('insertar en una parte ×2 lo agrega en las dos vueltas', () {
      final song = songOf('D A Bm D A Bm G', [(0, 6, 2), (6, 7, 1)]);
      song.insertChord(0, 2, ChordEvent(chord: ChordParser.parse('G')!));
      expect(names(song), ['D', 'A', 'G', 'Bm', 'D', 'A', 'G', 'Bm', 'G']);
      expect(parts(song), [(0, 8, 2), (8, 9, 1)]);
      expect(song.chords[6].startMicros, isNull);
    });

    test('quitar en una parte ×2 mantiene el ×2', () {
      final song = songOf('D A Bm D A Bm', [(0, 6, 2)]);
      song.removeChord(0, 1);
      expect(names(song), ['D', 'Bm', 'D', 'Bm']);
      expect(parts(song), [(0, 4, 2)]);
    });

    test('quitar el único acorde de una parte la elimina', () {
      final song = songOf('E G D', [(0, 1, 1), (1, 3, 1)]);
      song.removeChord(0, 0);
      expect(parts(song), [(0, 2, 1)]);
      expect(song.sections, hasLength(1));
    });

    test('mover un acorde a otra sección', () {
      final song = songOf('G D Em C Am F', [(0, 4, 1), (4, 6, 1)]);
      final c = song.chords[3];
      song.moveChord(0, 3, 1, 0);
      expect(names(song), ['G', 'D', 'Em', 'C', 'Am', 'F']);
      expect(parts(song), [(0, 3, 1), (3, 6, 1)]);
      expect(identical(song.chords[3], c), isTrue, reason: 'conserva su lugar en la toma');
    });

    test('mover dentro de la misma sección', () {
      final song = songOf('G D Em C', [(0, 4, 1)]);
      song.moveChord(0, 0, 0, 3);
      expect(names(song), ['D', 'Em', 'G', 'C']);
      song.moveChord(0, 3, 0, 0);
      expect(names(song), ['C', 'D', 'Em', 'G']);
      song.moveChord(0, 1, 0, 2); // al mismo lugar: nada
      expect(names(song), ['C', 'D', 'Em', 'G']);
    });

    test('mover de una parte ×2 a una ×1 saca el acorde de ambas vueltas', () {
      final song = songOf('D A Bm D A Bm G', [(0, 6, 2), (6, 7, 1)]);
      song.moveChord(0, 2, 1, 1);
      expect(names(song), ['D', 'A', 'D', 'A', 'G', 'Bm']);
      expect(parts(song), [(0, 4, 2), (4, 6, 1)]);
    });

    test('reordenar, duplicar y agregar secciones', () {
      final song = songOf('G D Em C', [(0, 2, 1), (2, 4, 1)]);
      song.sections.first.note = 'suave';
      song.moveOccurrence(0, 1);
      expect(names(song), ['Em', 'C', 'G', 'D']);
      song.duplicateOccurrence(1);
      expect(names(song), ['Em', 'C', 'G', 'D', 'G', 'D']);
      expect(song.arrangement.map((o) => song.section(o.sectionId)!.label), ['Parte 2', 'Parte 1', 'Parte 1']);
      expect(song.section(song.arrangement.last.sectionId)!.note, 'suave');
      expect(song.arrangement[1].sectionId, isNot(song.arrangement[2].sectionId));

      song.addSection(song.newSection(label: 'Coro'), ChordLine.parse('C G').chords, repeats: 2, at: 0);
      expect(names(song).take(4), ['C', 'G', 'C', 'G']);
      expect(parts(song).first, (0, 4, 2));
    });

    test('canción nueva: la primera sección se agrega a una canción vacía', () {
      final song = Song.create(title: 'Nueva', source: SongSource.manual);
      song.addSection(song.newSection(label: 'Verso'), ChordLine.parse("G' D' Em''").chords);
      expect(names(song), ['G', 'D', 'Em']);
      expect(song.chords.map((c) => c.beats), [1, 1, 2]);
      expect(parts(song), [(0, 3, 1)]);
    });

    test('reemplazar la vuelta conserva los acordes que siguen igual', () {
      final song = songOf('D A Bm D A Bm', [(0, 6, 2)]);
      final a1 = song.chords[1], a2 = song.chords[4];
      song.replacePass(0, ChordLine.parse("D A'' G Bm").chords);
      expect(names(song), ['D', 'A', 'G', 'Bm', 'D', 'A', 'G', 'Bm']);
      expect(identical(song.chords[1], a1) && identical(song.chords[5], a2), isTrue);
      expect(song.chords[1].beats, 2);
      expect(song.chords[5].beats, 2);
      expect(song.chords[0].startMicros, 0);
      expect(parts(song), [(0, 8, 2)]);

      song.replacePass(0, ChordLine.parse('D A').chords, repeats: 3);
      expect(names(song), ['D', 'A', 'D', 'A', 'D', 'A']);
      expect(parts(song), [(0, 6, 3)]);
    });

    test('partir en medio de una vuelta parte todas las vueltas', () {
      final song = songOf('D A Bm G D A Bm G', [(0, 8, 2)]);
      song.splitPasses(0, 3, song.newSection(label: 'Puente'));
      expect(parts(song), [(0, 3, 1), (3, 4, 1), (4, 7, 1), (7, 8, 1)]);
      expect(song.arrangement.map((o) => song.section(o.sectionId)!.label), ['Parte 1', 'Puente', 'Parte 1', 'Puente']);
      expect(song.arrangement.map((o) => o.sectionId).toSet(), hasLength(4));
      expect(names(song), ['D', 'A', 'Bm', 'G', 'D', 'A', 'Bm', 'G']);

      final simple = songOf('G D Em C', [(0, 4, 1)]);
      simple.splitPasses(0, 2, simple.newSection(label: 'Coro'));
      expect(parts(simple), [(0, 2, 1), (2, 4, 1)]);
    });

    test('subir las vueltas agrupa si ya eran iguales', () {
      final song = songOf('G D G D Am', [(0, 4, 1), (4, 5, 1)]);
      song.setRepeats(0, 2);
      expect(names(song), ['G', 'D', 'G', 'D', 'Am']);
      expect(parts(song), [(0, 4, 2), (4, 5, 1)]);
      song.ungroup(0);
      expect(parts(song), [(0, 4, 1), (4, 5, 1)]);
    });

    test('las modulaciones fijadas a mano siguen a su acorde', () {
      final song = songOf('G C D G A D E A', [(0, 4, 1), (4, 8, 1)])
        ..keyRegions = [
          KeyRegion(start: 0, end: 4, key: MusicKey(7, Mode.major), confidence: 0.9),
          KeyRegion(start: 4, end: 8, key: MusicKey(9, Mode.major), confidence: 0.9),
        ]
        ..keyRegionsManual = true;
      song.moveChord(0, 0, 0, 4); // la G inicial al final de la parte 1
      song.insertChord(0, 0, ChordEvent(chord: ChordParser.parse('Em')!));
      expect(song.keyRegions.map((r) => (r.start, r.end)), [(0, 5), (5, 9)]);
      song.moveOccurrence(1, 0);
      expect(song.keyRegions.map((r) => (r.start, r.end, r.key.name())), [(0, 4, 'A'), (4, 9, 'G')]);
    });
  });

  group('texto de acordes', () {
    test('lee cifrados, tiempos y vueltas', () {
      final line = ChordLine.parse("D′ A' Bm'' | G, Em7 x2");
      expect(line.chords.map((c) => fmt.format(c.chord)), ['D', 'A', 'Bm', 'G', 'Em7']);
      expect(line.chords.map((c) => c.beats), [1, 1, 2, null, null]);
      expect(line.repeats, 2);
      expect(line.isValid, isTrue);
    });

    test('reconoce vueltas iguales al regrabar', () {
      expect(ChordLine.repeatsOf(chords('D A Bm D A Bm')), (3, 2));
      expect(ChordLine.repeatsOf(chords('G D G D G D G D')), (2, 4));
      expect(ChordLine.repeatsOf(chords('G D Em C')), (4, 1));
      expect(ChordLine.repeatsOf(chords('D A Bm D A')), (5, 1));
    });

    test('marca lo que no reconoce', () {
      final line = ChordLine.parse('G Hola D');
      expect(line.unknown, ['Hola']);
      expect(line.isValid, isFalse);
    });

    test('ida y vuelta en americana y latina', () {
      for (final notation in Notation.values) {
        final f = ChordFormatter(notation: notation);
        final pass = ChordLine.parse("G'' D/F#' Em7 C6/9 Bbmaj7").chords;
        final text = ChordLine.format(pass, formatter: f, repeats: 2);
        final back = ChordLine.parse(text);
        expect(back.chords.map((c) => c.chord), pass.map((c) => c.chord), reason: text);
        expect(back.chords.map((c) => c.beats), pass.map((c) => c.beats));
        expect(back.repeats, 2);
      }
    });
  });

  group('deshacer', () {
    test('deshace y rehace cambios', () {
      final song = songOf('G D Em C', [(0, 2, 1), (2, 4, 1)]);
      final history = SongHistory(song);
      history.record();
      song.removeChord(0, 0);
      history.record();
      song.moveOccurrence(1, 0);
      expect(names(song), ['Em', 'C', 'D']);
      expect(history.undo(), isTrue);
      expect(names(song), ['D', 'Em', 'C']);
      expect(history.undo(), isTrue);
      expect(names(song), ['G', 'D', 'Em', 'C']);
      expect(parts(song), [(0, 2, 1), (2, 4, 1)]);
      expect(history.undo(), isFalse);
      expect(history.redo(), isTrue);
      expect(names(song), ['D', 'Em', 'C']);
      history.record(); // un cambio nuevo borra lo que se podía rehacer
      expect(history.canRedo, isFalse);
    });
  });

  test('acordes de la tonalidad', () {
    expect(MusicKey(7, Mode.major).diatonicChords.map(fmt.format), ['G', 'Am', 'Bm', 'C', 'D', 'Em', 'F#dim']);
    expect(MusicKey(9, Mode.minor).diatonicChords.map(fmt.format), ['Am', 'Bdim', 'C', 'Dm', 'E', 'F', 'G']);
  });
}
