import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

const fmt = ChordFormatter();

void main() {
  group('escalas', () {
    test('mayor: notas, grados y acordes', () {
      final s = Scale(0, ScaleShape.ionian);
      expect(s.notes.map((pc) => s.spell(pc).name()), ['C', 'D', 'E', 'F', 'G', 'A', 'B']);
      expect(s.degreeLabels, ['1', '2', '3', '4', '5', '6', '7']);
      expect(s.triads.map(fmt.format), ['C', 'Dm', 'Em', 'F', 'G', 'Am', 'Bdim']);
      expect(s.romans, ['I', 'ii', 'iii', 'IV', 'V', 'vi', 'vii°']);
    });

    test('modos: misma forma, otra tónica', () {
      final dorian = Scale(2, ScaleShape.dorian);
      expect(dorian.notes.map((pc) => dorian.spell(pc).name()), ['D', 'E', 'F', 'G', 'A', 'B', 'C']);
      expect(dorian.degreeLabels, ['1', '2', '♭3', '4', '5', '6', '♭7']);
      expect(dorian.romans, ['i', 'ii', '♭III', 'IV', 'v', 'vi°', '♭VII']);
      final mixo = Scale(7, ScaleShape.mixolydian);
      expect(mixo.triads.map(fmt.format), ['G', 'Am', 'Bdim', 'C', 'Dm', 'Em', 'F']);
      expect(mixo.romans.last, '♭VII');
    });

    test('menor natural y armónica', () {
      final natural = Scale(9, ScaleShape.aeolian);
      expect(natural.romans, ['i', 'ii°', '♭III', 'iv', 'v', '♭VI', '♭VII']);
      final harmonic = Scale(9, ScaleShape.harmonicMinor);
      expect(harmonic.notes.map((pc) => harmonic.spell(pc).name()), ['A', 'B', 'C', 'D', 'E', 'F', 'G#']);
      expect(harmonic.triads.map((c) => fmt.format(c, spell: harmonic.spell)), ['Am', 'Bdim', 'Caug', 'Dm', 'E', 'F', 'G#dim']);
      expect(harmonic.romans, ['i', 'ii°', '♭III+', 'iv', 'V', '♭VI', 'vii°']);
    });

    test('pentatónicas: cinco notas seguidas en el círculo', () {
      final penta = Scale(0, ScaleShape.pentatonicMajor);
      expect(penta.notes.map(Scale.circlePosition).toSet(), {0, 1, 2, 3, 4});
      expect(penta.triads, isEmpty);
      expect(Scale(9, ScaleShape.pentatonicMinor).notes.toSet(), penta.notes.toSet());
    });

    test('séptimas de la mayor y de la menor armónica', () {
      final c = Scale(0, ScaleShape.ionian);
      expect(c.sevenths.map(fmt.format), ['Cmaj7', 'Dm7', 'Em7', 'Fmaj7', 'G7', 'Am7', 'Bm7b5']);
      expect(c.seventhRomans, ['Imaj7', 'ii7', 'iii7', 'IVmaj7', 'V7', 'vi7', 'viiø7']);
      final a = Scale(9, ScaleShape.harmonicMinor);
      expect(a.seventhRomans[4], 'V7');
      expect(a.seventhRomans[6], 'vii°7');
    });

    test('círculo de quintas', () {
      expect([for (var p = 0; p < 12; p++) Scale.circleNote(p)], [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]);
      expect(Scale.circlePosition(5), 11);
    });
  });

  group('progresión por grados', () {
    test('I V vi IV en G', () {
      final p = RomanProgression.parse('I V vi IV', 7);
      expect(p.chords.map(fmt.format), ['G', 'D', 'Em', 'C']);
      expect(p.unknown, isEmpty);
    });

    test('menor, préstamos y séptimas', () {
      expect(RomanProgression.parse('i iv V i', 9).chords.map(fmt.format), ['Am', 'Dm', 'E', 'Am']);
      expect(RomanProgression.parse('I bVII IV I', 2).chords.map(fmt.format), ['D', 'C', 'G', 'D']);
      expect(RomanProgression.parse('ii7 V7 Imaj7 vii°', 0).chords.map(fmt.format), ['Dm7', 'G7', 'Cmaj7', 'Bdim']);
      expect(RomanProgression.parse('♭VI ♭VII i', 9).chords.map(fmt.format), ['F', 'G', 'Am']);
    });

    test('marca lo que no entiende', () {
      final p = RomanProgression.parse('I hola V', 0);
      expect(p.unknown, ['hola']);
      expect(p.chords, hasLength(2));
    });
  });
}
