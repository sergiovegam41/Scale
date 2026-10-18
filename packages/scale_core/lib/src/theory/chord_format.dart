import 'chord.dart';
import 'key.dart';
import 'pitch.dart';

/// Convierte acordes a texto de cifrado en la notación elegida.
class ChordFormatter {
  const ChordFormatter({this.notation = Notation.american});

  final Notation notation;

  // Letra del bajo según qué nota del acorde es: 3ª → +2 letras, 5ª → +4…
  static const List<int> _chordToneLetterOffset = [0, 1, 1, 2, 2, 3, 4, 4, 4, 5, 6, 6];

  /// [spell] decide la ortografía de la fundamental (por ejemplo según la
  /// tonalidad); sin él se usa la ortografía por defecto.
  String format(Chord chord, {SpelledNote Function(int pc)? spell}) {
    final root = spell?.call(chord.root) ?? SpelledNote.byDefault(chord.root);
    final out = StringBuffer(root.name(notation))..write(chord.quality.symbol);
    final bass = chord.bass;
    if (bass != null) {
      out
        ..write('/')
        ..write(_spellBass(chord, bass, root, spell).name(notation));
    }
    return out.toString();
  }

  String noteName(int pc, {SpelledNote Function(int pc)? spell}) =>
      (spell?.call(pc) ?? SpelledNote.byDefault(pc)).name(notation);

  static const List<String> _degreeLabels = [
    '1', 'b2', '2', 'b3', '3', '4', '#4', '5', 'b6', '6', 'b7', '7',
  ];

  static const Map<String, String> _superscript = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
    '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹', '/': 'ᐟ',
  };

  /// Sistema numérico (Nashville) relativo a [key]: "1", "6m", "5/7", "b7".
  /// Un sufijo que empieza con número va en superíndice para no pegarse al
  /// grado: D7 en D es "1⁷" (no "17"), D5 es "1⁵".
  String nashville(Chord chord, MusicKey key) {
    final symbol = chord.quality.symbol;
    final suffix = symbol.isNotEmpty && _superscript.containsKey(symbol[0])
        ? _toSuperscript(symbol)
        : symbol;
    final out = StringBuffer(_degreeLabels[key.degreeOf(chord.root)])..write(suffix);
    final bass = chord.bass;
    if (bass != null) {
      out
        ..write('/')
        ..write(_degreeLabels[key.degreeOf(bass)]);
    }
    return out.toString();
  }

  /// Pasa a superíndice los números iniciales ("7sus4" → "⁷sus4", "6/9" → "⁶ᐟ⁹").
  static String _toSuperscript(String s) {
    final out = StringBuffer();
    var leading = true;
    for (final ch in s.split('')) {
      final sup = _superscript[ch];
      if (leading && sup != null) {
        out.write(sup);
      } else {
        leading = false;
        out.write(ch);
      }
    }
    return out.toString();
  }

  SpelledNote _spellBass(
    Chord chord,
    int bass,
    SpelledNote root,
    SpelledNote Function(int pc)? spell,
  ) {
    final semis = (bass - chord.root) % 12;
    if (chord.quality.intervals.contains(semis)) {
      final n = SpelledNote.onLetter(root.letter + _chordToneLetterOffset[semis], bass);
      if (n.accidental.abs() <= 1) return n;
    }
    return spell?.call(bass) ?? SpelledNote.byDefault(bass);
  }
}
