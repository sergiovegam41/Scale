import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

const fmt = ChordFormatter();

String? name(List<int> notes) {
  final rec = const ChordRecognizer().recognize(notes);
  return rec == null ? null : fmt.format(rec.best);
}

void main() {
  group('reconocimiento', () {
    test('tríadas y séptimas', () {
      expect(name([48, 52, 55]), 'C');
      expect(name([45, 48, 52]), 'Am');
      expect(name([43, 47, 50, 53]), 'G7');
      expect(name([40, 43, 47, 50]), 'Em7');
      expect(name([47, 50, 53, 57]), 'Bm7b5');
      expect(name([48, 52, 55, 59]), 'Cmaj7');
    });

    test('el bajo decide C6 frente a Am7', () {
      expect(name([45, 48, 52, 55]), 'Am7');
      expect(name([48, 52, 55, 57]), 'C6');
    });

    test('acordes típicos de worship', () {
      expect(name([50, 55, 57]), 'Dsus4');
      expect(name([50, 52, 57]), 'Dsus2');
      expect(name([43, 45, 47, 50]), 'Gadd9');
      expect(name([42, 50, 54, 57]), 'D/F#');
      expect(name([47, 55, 59, 62]), 'G/B');
      expect(name([48, 55]), 'C5');
    });

    test('nota solo en el bajo que no es de la tríada → bajo con barra', () {
      expect(name([47, 60, 64, 67]), 'C/B');
      expect(name([45, 55, 59, 62]), 'G/A');
      expect(name([41, 55, 59, 62]), 'G/F');
      // Si la 7ª también suena arriba, es parte del acorde.
      expect(name([47, 60, 64, 67, 71]), 'Cmaj7/B');
    });

    test('una sola nota no es acorde', () {
      expect(name([60]), isNull);
      expect(name([48, 60]), isNull);
    });

    test('las alternativas incluyen la lectura enarmónica de las mismas notas', () {
      final rec = const ChordRecognizer().recognize([52, 55, 59, 62])!;
      expect(fmt.format(rec.best), 'Em7');
      expect(rec.alternatives.map((c) => fmt.format(c.chord)), contains('G6/E'));
      expect(rec.confidence, inExclusiveRange(0, 1));
    });
  });

  group('parser', () {
    Chord p(String s) => ChordParser.parse(s)!;

    test('notación americana', () {
      expect(p('D/F#'), Chord(2, ChordQuality.major, bass: 6));
      expect(p('Bbsus4'), Chord(10, ChordQuality.sus4));
      expect(p('G2'), Chord(7, ChordQuality.sus2));
      expect(p('F#m7(b5)'), Chord(6, ChordQuality.halfDiminished));
      expect(p('Fadd9'), Chord(5, ChordQuality.add9));
      expect(p('C6/9'), Chord(0, ChordQuality.sixNine));
      expect(p('Ebmaj7'), Chord(3, ChordQuality.major7));
      expect(p('CΔ7'), Chord(0, ChordQuality.major7));
    });

    test('notación latina', () {
      expect(p('Sol7'), Chord(7, ChordQuality.dominant7));
      expect(p('Rem'), Chord(2, ChordQuality.minor));
      expect(p('Do7M'), Chord(0, ChordQuality.major7));
      expect(p('Mi/Sol#'), Chord(4, ChordQuality.major, bass: 8));
      expect(p('Sib'), Chord(10, ChordQuality.major));
      expect(p('Fa#m'), Chord(6, ChordQuality.minor));
    });

    test('texto que no es acorde', () {
      expect(ChordParser.parse('Verso'), isNull);
      expect(ChordParser.parse(''), isNull);
      expect(ChordParser.parse('Cxyz'), isNull);
    });

    test('ida y vuelta formato → parser', () {
      for (final q in ChordQuality.all) {
        for (final root in [0, 3, 6, 10]) {
          final chord = Chord(root, q, bass: (root + 4) % 12);
          for (final n in Notation.values) {
            final text = ChordFormatter(notation: n).format(chord);
            expect(ChordParser.parse(text), chord, reason: text);
          }
        }
      }
    });
  });

  group('formato', () {
    test('notación latina y ortografía del bajo', () {
      final chord = Chord(2, ChordQuality.major, bass: 6);
      expect(const ChordFormatter(notation: Notation.latin).format(chord), 'Re/Fa#');
      expect(fmt.format(Chord(11, ChordQuality.major, bass: 3)), 'B/D#');
      expect(fmt.format(Chord(8, ChordQuality.major, bass: 0)), 'Ab/C');
    });
  });

  test('transportar y coincidencia flexible', () {
    final g = Chord(7, ChordQuality.major);
    expect(Chord(2, ChordQuality.major).transpose(5), g);
    expect(g.matchesFlexibly(Chord(7, ChordQuality.add9)), isTrue);
    expect(g.matchesFlexibly(Chord(7, ChordQuality.major, bass: 11)), isTrue);
    expect(g.matchesFlexibly(Chord(7, ChordQuality.sus4)), isTrue);
    expect(g.matchesFlexibly(Chord(7, ChordQuality.minor)), isFalse);
    expect(g.matchesFlexibly(Chord(9, ChordQuality.major)), isFalse);
  });

  test('json del acorde', () {
    final chord = Chord(2, ChordQuality.minor7, bass: 0);
    expect(Chord.fromJson(chord.toJson()), chord);
  });
}
