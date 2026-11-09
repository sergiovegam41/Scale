import '../theory/chord.dart';
import '../theory/key.dart';
import '../theory/pitch.dart';

/// Pentagrama de una nota: clave de sol (mano derecha) o de fa (izquierda).
enum StaffClef { treble, bass }

const List<int> _letterPitch = [0, 2, 4, 5, 7, 9, 11];

/// Número diatónico (octava * 7 + letra) de la línea inferior de cada clave:
/// Mi4 en sol, Sol2 en fa.
const int _trebleBottom = 4 * 7 + 2;
const int _bassBottom = 2 * 7 + 4;

/// Armadura de una tonalidad: qué alteración lleva cada letra.
class KeySignature {
  const KeySignature._(this.fifths);

  /// Armadura con [fifths] sostenidos (positivo) o bemoles (negativo).
  factory KeySignature.fifths(int fifths) => KeySignature._(fifths.clamp(-7, 7));

  /// Armadura de [key] (en menor, la de su relativa mayor).
  factory KeySignature.of(MusicKey? key) {
    if (key == null) return none;
    var fifths = 0;
    for (final pc in key.scale) {
      fifths += key.spell(pc).accidental;
    }
    return KeySignature.fifths(fifths);
  }

  static const none = KeySignature._(0);

  /// Orden de las letras en la armadura: Fa Do Sol Re La Mi Si / Si Mi La Re Sol Do Fa.
  static const List<int> sharpOrder = [3, 0, 4, 1, 5, 2, 6];
  static const List<int> flatOrder = [6, 2, 5, 1, 4, 0, 3];

  /// Positivo: sostenidos; negativo: bemoles.
  final int fifths;

  /// Letras alteradas, en el orden en que se escriben.
  List<int> get letters => fifths >= 0 ? sharpOrder.take(fifths).toList() : flatOrder.take(-fifths).toList();

  /// Alteración que la armadura da a [letter] (0 = C … 6 = B).
  int accidentalFor(int letter) => letters.contains(letter) ? (fifths > 0 ? 1 : -1) : 0;

  /// Posición (0 = línea inferior, 8 = superior) de cada alteración de la
  /// armadura en [clef], en el orden en que se dibujan.
  List<int> steps(StaffClef clef) {
    // Posiciones en clave de sol; la de fa va dos posiciones más abajo.
    const sharpSteps = [8, 5, 9, 6, 3, 7, 4];
    const flatSteps = [4, 7, 3, 6, 2, 5, 1];
    final shift = clef == StaffClef.treble ? 0 : -2;
    final src = fifths >= 0 ? sharpSteps : flatSteps;
    return [for (var i = 0; i < fifths.abs(); i++) src[i] + shift];
  }

  @override
  bool operator ==(Object other) => other is KeySignature && other.fifths == fifths;

  @override
  int get hashCode => fifths.hashCode;
}

/// Una nota del acorde ya escrita y colocada en el pentagrama doble.
class StaffNote {
  const StaffNote({
    required this.midi,
    required this.spelling,
    required this.octave,
    required this.clef,
    required this.step,
    required this.accidental,
    required this.shifted,
    required this.accidentalColumn,
  });

  final int midi;
  final SpelledNote spelling;

  /// Octava de la letra escrita (Do4 = do central; Si#3 suena como Do4).
  final int octave;
  final StaffClef clef;

  /// Posición en su pentagrama: 0 = línea inferior, 8 = superior; los pares
  /// son líneas. Negativo o mayor que 8: líneas adicionales.
  final int step;

  /// Alteración a dibujar: null si la armadura ya la da; 0 es becuadro.
  final int? accidental;

  /// Cabeza desplazada al otro lado (intervalo de segunda con la de abajo).
  final bool shifted;

  /// Columna de la alteración, contando desde las cabezas (0 = la más cercana).
  final int accidentalColumn;

  /// Nombre con octava: "F#4", "Sol3".
  String label([Notation notation = Notation.american]) => '${spelling.name(notation)}$octave';

  @override
  String toString() =>
      'StaffNote(${label()} $clef step $step${accidental == null ? '' : ' acc $accidental'}'
      '${shifted ? ' shifted' : ''})';
}

/// Un acorde escrito en pentagrama doble: ortografía según el acorde y la
/// tonalidad, reparto entre las dos claves, segundas y alteraciones apiladas.
class ChordStaff {
  ChordStaff._(this.notes, this.signature);

  /// Escribe las notas MIDI [midiNotes]. [chord] decide la ortografía de las
  /// notas del acorde (la 3ª de E es G#, no Ab) y [key] la de las demás y la
  /// armadura.
  factory ChordStaff.layout(Iterable<int> midiNotes, {Chord? chord, MusicKey? key}) {
    final signature = KeySignature.of(key);
    final sorted = midiNotes.toSet().toList()..sort();
    if (sorted.isEmpty) return ChordStaff._(const [], signature);

    var spelled = [for (final m in sorted) (m, spellInChord(m % 12, chord: chord, key: key))];
    spelled = _avoidSameLetter(spelled);

    final split = _splitPoint(sorted);
    final placed = <StaffNote>[];
    for (final clef in StaffClef.values) {
      final own = [
        for (final (m, s) in spelled)
          if ((clef == StaffClef.treble) == (m >= split)) (m, s),
      ];
      placed.addAll(_place(own, clef, signature));
    }
    return ChordStaff._(placed, signature);
  }

  /// Notas de abajo arriba, primero las de clave de sol y luego las de fa.
  final List<StaffNote> notes;
  final KeySignature signature;

  List<StaffNote> on(StaffClef clef) => [
    for (final n in notes)
      if (n.clef == clef) n,
  ];

  /// Cuántas columnas de alteraciones usa el pentagrama más ancho.
  int get accidentalColumns {
    var max = 0;
    for (final n in notes) {
      if (n.accidental != null && n.accidentalColumn + 1 > max) max = n.accidentalColumn + 1;
    }
    return max;
  }

  /// Ortografía de la clase de altura [pc] dentro de [chord]: las notas del
  /// acorde se escriben por intervalo desde la fundamental (Fa#, La#, Do# en
  /// F#), las demás según [key].
  static SpelledNote spellInChord(int pc, {Chord? chord, MusicKey? key}) {
    SpelledNote byKey(int p) => key?.spell(p) ?? SpelledNote.byDefault(p);
    if (chord == null) return byKey(pc);
    final root = byKey(chord.root);
    final semis = (pc - chord.root) % 12;
    final offset = _letterOffset(semis, chord.quality);
    if (offset == null) return byKey(pc);
    final note = SpelledNote.onLetter(root.letter + offset, pc);
    return note.accidental.abs() <= 2 ? note : byKey(pc);
  }

  /// Cuántas letras sube cada intervalo del acorde: la 3ª dos, la 5ª cuatro…
  static int? _letterOffset(int semis, ChordQuality quality) {
    final has = quality.intervals.contains;
    return switch (semis) {
      0 => 0,
      1 => 1, // b9
      2 => 1, // 2 / 9
      3 => 2, // 3ª menor
      4 => 2, // 3ª mayor
      5 => 3, // 4ª / 11
      6 => has(6) && !has(7) ? 4 : 3, // b5 en disminuidos, #11 en lo demás
      7 => 4,
      8 => has(8) && !has(7) ? 4 : 5, // #5 en aumentados, b6 / b13 en lo demás
      9 => quality == ChordQuality.diminished7 ? 6 : 5, // bb7 en dim7, 6 / 13
      10 => 6,
      11 => 6,
      _ => null,
    };
  }

  /// Dos notas con la misma letra en la misma octava (Sol y Sol#) no caben
  /// en la misma línea: la de arriba pasa a la letra siguiente (Lab).
  static List<(int, SpelledNote)> _avoidSameLetter(List<(int, SpelledNote)> notes) {
    final out = <(int, SpelledNote)>[];
    for (final (m, s) in notes) {
      var spelling = s;
      if (out.isNotEmpty) {
        final (pm, ps) = out.last;
        if (_diatonic(pm, ps) >= _diatonic(m, spelling)) {
          final up = SpelledNote.onLetter(spelling.letter + 1, m % 12);
          if (up.accidental.abs() <= 1) spelling = up;
        }
      }
      out.add((m, spelling));
    }
    return out;
  }

  /// Octava de la letra escrita: Si#3 suena como Do4 pero se escribe en la 3.
  static int octaveOf(int midi, SpelledNote s) => ((midi - s.accidental - _letterPitch[s.letter]) ~/ 12) - 1;

  static int _diatonic(int midi, SpelledNote s) => octaveOf(midi, s) * 7 + s.letter;

  /// Nota MIDI desde la que se escribe en clave de sol.
  ///
  /// Si hay un salto claro (una quinta justa o más) cerca del do central, ahí se
  /// separan las manos. Un acorde cerrado va entero a un solo pentagrama si
  /// cabe con pocas líneas adicionales; si no, se parte en el do central.
  static int _splitPoint(List<int> sorted) {
    var bestScore = double.negativeInfinity;
    var bestAt = -1;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i] - sorted[i - 1];
      // Las de abajo deben caber en clave de fa (hasta Mi4) y las de arriba
      // en clave de sol (desde Sol3). Entre saltos parecidos gana el más
      // cercano al do central.
      if (gap < 7 || sorted[i - 1] > 64 || sorted[i] < 55) continue;
      final score = gap - ((sorted[i] + sorted[i - 1]) / 2 - 60).abs() / 2;
      if (score > bestScore) {
        bestScore = score;
        bestAt = i;
      }
    }
    if (bestAt > 0) return sorted[bestAt];
    final low = sorted.first;
    final high = sorted.last;
    if (low >= 55) return low; // todo en clave de sol (hasta Sol3, dos líneas)
    if (high <= 64) return high + 1; // todo en clave de fa (hasta Mi4, dos líneas)
    return 60;
  }

  static List<StaffNote> _place(List<(int, SpelledNote)> notes, StaffClef clef, KeySignature sig) {
    final bottom = clef == StaffClef.treble ? _trebleBottom : _bassBottom;
    final steps = [for (final (m, s) in notes) _diatonic(m, s) - bottom];

    // Segundas: la de arriba va al otro lado, salvo que la de abajo ya lo esté.
    final shifted = List.filled(notes.length, false);
    for (var i = 1; i < notes.length; i++) {
      if (steps[i] - steps[i - 1] == 1 && !shifted[i - 1]) shifted[i] = true;
    }

    // Alteraciones: las que la armadura no da.
    final accidentals = <int?>[
      for (final (_, s) in notes) s.accidental == sig.accidentalFor(s.letter) ? null : s.accidental,
    ];

    // Columnas: se colocan de fuera hacia dentro (arriba, abajo, la segunda
    // de arriba…) en la columna más cercana que no choque (menos de una sexta).
    final columns = List.filled(notes.length, 0);
    final withAcc = [
      for (var i = 0; i < notes.length; i++)
        if (accidentals[i] != null) i,
    ];
    final order = <int>[];
    var lo = 0;
    var hi = withAcc.length - 1;
    while (lo <= hi) {
      order.add(withAcc[hi--]);
      if (lo <= hi) order.add(withAcc[lo++]);
    }
    final placed = <int>[];
    for (final i in order) {
      var col = 0;
      while (placed.any((j) => columns[j] == col && (steps[j] - steps[i]).abs() < 6)) {
        col++;
      }
      columns[i] = col;
      placed.add(i);
    }

    return [
      for (var i = 0; i < notes.length; i++)
        StaffNote(
          midi: notes[i].$1,
          spelling: notes[i].$2,
          octave: octaveOf(notes[i].$1, notes[i].$2),
          clef: clef,
          step: steps[i],
          accidental: accidentals[i],
          shifted: shifted[i],
          accidentalColumn: columns[i],
        ),
    ];
  }
}
