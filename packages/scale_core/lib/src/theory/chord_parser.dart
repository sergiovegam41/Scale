import 'chord.dart';
import 'pitch.dart';

/// Lee cifrados escritos a mano, de cancioneros o devueltos por la IA:
/// "D/F#", "Em7", "Bbsus4", "G2", "Sol7", "Rem", "Do7M", "F#m7(b5)"…
class ChordParser {
  const ChordParser._();

  static final Map<String, ChordQuality> _aliases = {
    '': ChordQuality.major,
    'M': ChordQuality.major,
    'maj': ChordQuality.major,
    'Maj': ChordQuality.major,
    'm': ChordQuality.minor,
    'mi': ChordQuality.minor,
    'min': ChordQuality.minor,
    '-': ChordQuality.minor,
    'dim': ChordQuality.diminished,
    'o': ChordQuality.diminished,
    'aug': ChordQuality.augmented,
    '+': ChordQuality.augmented,
    'sus2': ChordQuality.sus2,
    '2': ChordQuality.sus2,
    'sus4': ChordQuality.sus4,
    'sus': ChordQuality.sus4,
    '4': ChordQuality.sus4,
    '5': ChordQuality.power,
    '6': ChordQuality.sixth,
    'add6': ChordQuality.sixth,
    'm6': ChordQuality.minorSixth,
    'min6': ChordQuality.minorSixth,
    '-6': ChordQuality.minorSixth,
    '7': ChordQuality.dominant7,
    'maj7': ChordQuality.major7,
    'Maj7': ChordQuality.major7,
    'M7': ChordQuality.major7,
    'ma7': ChordQuality.major7,
    'j7': ChordQuality.major7,
    '7M': ChordQuality.major7,
    'm7': ChordQuality.minor7,
    'min7': ChordQuality.minor7,
    '-7': ChordQuality.minor7,
    'mmaj7': ChordQuality.minorMajor7,
    'mMaj7': ChordQuality.minorMajor7,
    'mM7': ChordQuality.minorMajor7,
    'm7M': ChordQuality.minorMajor7,
    'minmaj7': ChordQuality.minorMajor7,
    'm7b5': ChordQuality.halfDiminished,
    'min7b5': ChordQuality.halfDiminished,
    '-7b5': ChordQuality.halfDiminished,
    'm7-5': ChordQuality.halfDiminished,
    'dim7': ChordQuality.diminished7,
    'o7': ChordQuality.diminished7,
    '7sus4': ChordQuality.dominant7sus4,
    '7sus': ChordQuality.dominant7sus4,
    'add9': ChordQuality.add9,
    'add2': ChordQuality.add9,
    'madd9': ChordQuality.minorAdd9,
    'madd2': ChordQuality.minorAdd9,
    'm2': ChordQuality.minorAdd9,
    '9': ChordQuality.dominant9,
    'maj9': ChordQuality.major9,
    'M9': ChordQuality.major9,
    'm9': ChordQuality.minor9,
    'min9': ChordQuality.minor9,
    '-9': ChordQuality.minor9,
    '69': ChordQuality.sixNine,
    '6/9': ChordQuality.sixNine,
    '6add9': ChordQuality.sixNine,
    'add4': ChordQuality.add4,
    'add11': ChordQuality.add4,
  };

  // Alias largos sin distinguir mayúsculas ("MAJ7", "Sus4"). Los cortos
  // ('M' frente a 'm') sí distinguen.
  static final Map<String, ChordQuality> _aliasesLower = {
    for (final e in _aliases.entries)
      if (e.key.length >= 3) e.key.toLowerCase(): e.value,
  };

  /// Devuelve null si el texto no es un acorde reconocible.
  static Chord? parse(String input) {
    final s = _normalize(input);
    if (s.isEmpty) return null;
    // Se prueban todas las lecturas de la fundamental: "Fadd9" no es "Fa"+"dd9".
    for (final (root, length) in SpelledNote.parsePrefixes(s)) {
      final chord = _parseRest(root.pitchClass, s.substring(length));
      if (chord != null) return chord;
    }
    return null;
  }

  static Chord? _parseRest(int root, String rest) {
    final whole = _quality(rest);
    if (whole != null) return Chord(root, whole);
    final slash = rest.lastIndexOf('/');
    if (slash < 0) return null;
    final quality = _quality(rest.substring(0, slash));
    if (quality == null) return null;
    final bassText = rest.substring(slash + 1);
    for (final (bass, length) in SpelledNote.parsePrefixes(bassText)) {
      if (length == bassText.length) return Chord(root, quality, bass: bass.pitchClass);
    }
    return null;
  }

  static ChordQuality? _quality(String suffix) {
    final s = suffix.replaceAll('(', '').replaceAll(')', '');
    return _aliases[s] ?? _aliasesLower[s.toLowerCase()];
  }

  static String _normalize(String input) => input
      .trim()
      .replaceAll(' ', '')
      .replaceAll('♯', '#')
      .replaceAll('♭', 'b')
      .replaceAll('Δ', 'maj')
      .replaceAll('ø7', 'm7b5')
      .replaceAll('ø', 'm7b5')
      .replaceAll('°', 'dim')
      .replaceAll('º', 'dim')
      .replaceAll('–', '-')
      .replaceAll('−', '-');
}
