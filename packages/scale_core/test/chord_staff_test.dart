import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

void main() {
  Chord chord(String s) => ChordParser.parse(s)!;
  MusicKey key(String s) => MusicKey.parse(s)!;
  List<String> labels(ChordStaff staff) => [for (final n in staff.notes) n.label()];

  group('KeySignature', () {
    test('armaduras de mayores y menores', () {
      expect(KeySignature.of(key('C')).fifths, 0);
      expect(KeySignature.of(key('G')).fifths, 1);
      expect(KeySignature.of(key('E')).fifths, 4);
      expect(KeySignature.of(key('F')).fifths, -1);
      expect(KeySignature.of(key('Eb')).fifths, -3);
      expect(KeySignature.of(key('Em')).fifths, 1);
      expect(KeySignature.of(key('Dm')).fifths, -1);
      expect(KeySignature.of(key('F#m')).fifths, 3);
      expect(KeySignature.of(null).fifths, 0);
    });

    test('alteración por letra y posiciones', () {
      final d = KeySignature.fifths(2); // Fa#, Do#
      expect(d.accidentalFor(3), 1);
      expect(d.accidentalFor(0), 1);
      expect(d.accidentalFor(4), 0);
      expect(d.steps(StaffClef.treble), [8, 5]);
      expect(d.steps(StaffClef.bass), [6, 3]);
      expect(KeySignature.fifths(-2).steps(StaffClef.treble), [4, 7]);
    });
  });

  group('ortografía en el acorde', () {
    test('la tercera de E es G#, no Ab', () {
      final s = ChordStaff.layout([64, 68, 71], chord: chord('E'), key: key('A'));
      expect(labels(s), ['E4', 'G#4', 'B4']);
    });

    test('F# mayor en F#: A# y C#', () {
      final s = ChordStaff.layout([66, 70, 73], chord: chord('F#'), key: key('F#'));
      expect(labels(s), ['F#4', 'A#4', 'C#5']);
      // En F# mayor la armadura ya da todo: ninguna alteración visible.
      expect(s.notes.every((n) => n.accidental == null), isTrue);
    });

    test('Gb en Db: bemoles', () {
      final s = ChordStaff.layout([66, 70, 73], chord: chord('Gb'), key: key('Db'));
      expect(labels(s), ['Gb4', 'Bb4', 'Db5']);
    });

    test('dim7 usa doble bemol en la séptima', () {
      final s = ChordStaff.layout([60, 63, 66, 69], chord: chord('Cdim7'), key: key('C'));
      expect(labels(s), ['C4', 'Eb4', 'Gb4', 'Bbb4']);
    });

    test('aumentado: quinta aumentada', () {
      final s = ChordStaff.layout([60, 64, 68], chord: chord('Caug'));
      expect(labels(s), ['C4', 'E4', 'G#4']);
    });

    test('sin acorde ni tonalidad, ortografía por defecto', () {
      final s = ChordStaff.layout([61, 63]);
      expect(labels(s), ['C#4', 'Eb4']);
    });

    test('Si#3 se escribe en la octava 3', () {
      expect(ChordStaff.octaveOf(60, const SpelledNote(6, 1)), 3);
      expect(ChordStaff.octaveOf(59, const SpelledNote(0, -1)), 4);
    });
  });

  group('reparto entre claves', () {
    test('bajo separado de la mano derecha', () {
      final s = ChordStaff.layout([43, 67, 71, 74], chord: chord('G'), key: key('G'));
      expect(s.on(StaffClef.bass).map((n) => n.label()), ['G2']);
      expect(s.on(StaffClef.treble).map((n) => n.label()), ['G4', 'B4', 'D5']);
    });

    test('acorde cerrado alrededor del do central va en un solo pentagrama', () {
      final s = ChordStaff.layout([55, 59, 62], chord: chord('G'));
      expect(s.on(StaffClef.treble).length, 3);
      final low = ChordStaff.layout([48, 52, 55], chord: chord('C'));
      expect(low.on(StaffClef.bass).length, 3);
    });

    test('con dos saltos iguales se separa en el más cercano al do central', () {
      final s = ChordStaff.layout([43, 55, 67, 71, 74], chord: chord('G'));
      expect(s.on(StaffClef.bass).map((n) => n.label()), ['G2', 'G3']);
    });

    test('C D G cerrado no se separa', () {
      final s = ChordStaff.layout([60, 62, 67], chord: chord('Csus2'));
      expect(s.on(StaffClef.treble).length, 3);
    });

    test('acorde abierto sin salto claro se parte en el do central', () {
      final s = ChordStaff.layout([52, 55, 57, 60, 64, 67]);
      expect(s.on(StaffClef.bass).every((n) => n.midi < 60), isTrue);
      expect(s.on(StaffClef.treble).every((n) => n.midi >= 60), isTrue);
    });

    test('posiciones: do central es -2 en sol y 10 en fa', () {
      final t = ChordStaff.layout([60, 64, 67], chord: chord('C'));
      expect(t.notes.first.step, -2);
      expect(t.notes.first.clef, StaffClef.treble);
      final b = ChordStaff.layout([43, 60]);
      expect(b.on(StaffClef.bass).first.step, 0); // G2, línea inferior
      expect(b.on(StaffClef.bass).length, 1);
    });
  });

  group('segundas y alteraciones', () {
    test('en una segunda la nota de arriba va al otro lado', () {
      final s = ChordStaff.layout([60, 62, 67], chord: chord('Csus2'));
      final t = s.on(StaffClef.treble);
      expect(t.map((n) => n.shifted), [false, true, false]);
    });

    test('cluster de tres segundas alterna los lados', () {
      final s = ChordStaff.layout([60, 62, 64]);
      expect(s.on(StaffClef.treble).map((n) => n.shifted), [false, true, false]);
    });

    test('alteraciones fuera de la armadura, becuadro incluido', () {
      // C7 en F: Bb lo da la armadura; en G, Bb necesita bemol y F natural becuadro.
      final inF = ChordStaff.layout([60, 64, 67, 70], chord: chord('C7'), key: key('F'));
      expect(inF.notes.every((n) => n.accidental == null), isTrue);
      final inG = ChordStaff.layout([65, 69, 72], chord: chord('F'), key: key('G'));
      expect(inG.notes.first.accidental, 0);
    });

    test('alteraciones cercanas van en columnas distintas', () {
      final s = ChordStaff.layout([61, 65, 68], chord: chord('C#'));
      final acc = s.notes.where((n) => n.accidental != null).toList();
      expect(acc.length, 3);
      expect(acc.map((n) => n.accidentalColumn).toSet().length, greaterThan(1));
      expect(s.accidentalColumns, greaterThanOrEqualTo(2));
    });

    test('alteraciones a una octava comparten columna', () {
      final s = ChordStaff.layout([61, 73]);
      expect(s.notes.map((n) => n.accidentalColumn), [0, 0]);
    });

    test('dos notas de la misma letra no comparten línea', () {
      final s = ChordStaff.layout([67, 68]);
      expect(s.notes[0].step, isNot(s.notes[1].step));
    });
  });
}
