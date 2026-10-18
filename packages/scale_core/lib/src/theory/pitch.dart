/// Notación usada para mostrar nombres de notas.
enum Notation { american, latin }

const List<int> _letterPitch = [0, 2, 4, 5, 7, 9, 11];
const List<String> _americanLetters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
const List<String> _latinLetters = ['Do', 'Re', 'Mi', 'Fa', 'Sol', 'La', 'Si'];

/// Normaliza un entero a clase de altura 0..11 (0 = C/Do).
int pitchClass(int value) => value % 12;

/// Lleva un intervalo en semitonos al rango -6..+5 (el camino más corto).
int signedInterval(int semitones) {
  final s = semitones % 12;
  return s > 5 ? s - 12 : s;
}

String accidentalSymbol(int accidental) {
  if (accidental > 0) return '#' * accidental;
  if (accidental < 0) return 'b' * -accidental;
  return '';
}

/// Una nota escrita: letra (0 = C … 6 = B) más alteración (-2..+2).
///
/// El análisis trabaja con clases de altura; la ortografía (F# o Gb) se decide
/// solo al mostrar, según la tonalidad.
class SpelledNote {
  const SpelledNote(this.letter, this.accidental);

  /// Escribe la clase de altura [pc] usando la letra [letter].
  factory SpelledNote.onLetter(int letter, int pc) {
    final l = letter % 7;
    var diff = (pc - _letterPitch[l]) % 12;
    if (diff > 6) diff -= 12;
    return SpelledNote(l, diff);
  }

  /// Ortografía por defecto cuando no hay tonalidad.
  factory SpelledNote.byDefault(int pc) => _defaultSpellings[pc % 12];

  final int letter;
  final int accidental;

  int get pitchClass => (_letterPitch[letter] + accidental) % 12;

  /// La misma altura escrita con la letra vecina (F# ↔ Gb), si es razonable.
  SpelledNote? get enharmonic {
    if (accidental == 0) return null;
    final other = SpelledNote.onLetter(letter + (accidental > 0 ? 1 : -1), pitchClass);
    return other.accidental.abs() <= 1 ? other : null;
  }

  String name([Notation notation = Notation.american]) {
    final base = notation == Notation.latin ? _latinLetters[letter] : _americanLetters[letter];
    return base + accidentalSymbol(accidental);
  }

  /// Interpretaciones posibles del inicio de [s] como nombre de nota,
  /// en notación latina y americana: (nota, caracteres consumidos).
  static List<(SpelledNote, int)> parsePrefixes(String s) {
    final results = <(SpelledNote, int)>[];
    final lower = s.toLowerCase();
    for (var i = 0; i < 7; i++) {
      final syllable = _latinLetters[i].toLowerCase();
      if (lower.startsWith(syllable)) {
        final (acc, len) = _parseAccidentals(s, syllable.length);
        results.add((SpelledNote(i, acc), syllable.length + len));
      }
    }
    if (s.isNotEmpty) {
      final i = _americanLetters.indexOf(s[0]);
      if (i >= 0) {
        final (acc, len) = _parseAccidentals(s, 1);
        results.add((SpelledNote(i, acc), 1 + len));
      }
    }
    return results;
  }

  static (int, int) _parseAccidentals(String s, int start) {
    var acc = 0;
    var i = start;
    while (i < s.length && i - start < 2) {
      final c = s[i];
      if (c == '#' || c == '♯') {
        if (acc < 0) break;
        acc++;
      } else if (c == 'b' || c == '♭') {
        if (acc > 0) break;
        acc--;
      } else {
        break;
      }
      i++;
    }
    return (acc, i - start);
  }

  @override
  bool operator ==(Object other) =>
      other is SpelledNote && other.letter == letter && other.accidental == accidental;

  @override
  int get hashCode => Object.hash(letter, accidental);

  @override
  String toString() => name();
}

const List<SpelledNote> _defaultSpellings = [
  SpelledNote(0, 0), // C
  SpelledNote(0, 1), // C#
  SpelledNote(1, 0), // D
  SpelledNote(2, -1), // Eb
  SpelledNote(2, 0), // E
  SpelledNote(3, 0), // F
  SpelledNote(3, 1), // F#
  SpelledNote(4, 0), // G
  SpelledNote(5, -1), // Ab
  SpelledNote(5, 0), // A
  SpelledNote(6, -1), // Bb
  SpelledNote(6, 0), // B
];
