import 'chord.dart';
import 'key.dart';
import 'pitch.dart';

/// Forma de una escala: los intervalos desde la tónica.
enum ScaleShape {
  ionian('Mayor (jónico)', [0, 2, 4, 5, 7, 9, 11]),
  dorian('Dórico', [0, 2, 3, 5, 7, 9, 10]),
  phrygian('Frigio', [0, 1, 3, 5, 7, 8, 10]),
  lydian('Lidio', [0, 2, 4, 6, 7, 9, 11]),
  mixolydian('Mixolidio', [0, 2, 4, 5, 7, 9, 10]),
  aeolian('Menor natural (eólico)', [0, 2, 3, 5, 7, 8, 10]),
  locrian('Locrio', [0, 1, 3, 5, 6, 8, 10]),
  harmonicMinor('Menor armónica', [0, 2, 3, 5, 7, 8, 11]),
  pentatonicMajor('Pentatónica mayor', [0, 2, 4, 7, 9]),
  pentatonicMinor('Pentatónica menor', [0, 3, 5, 7, 10]);

  const ScaleShape(this.label, this.intervals);

  final String label;
  final List<int> intervals;

  /// Los siete modos de la escala mayor, en orden de grado.
  static const List<ScaleShape> modes = [ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian];

  bool get isMode => modes.contains(this);
  bool get isPentatonic => this == pentatonicMajor || this == pentatonicMinor;

  /// Si la tónica suena menor (tercera menor).
  bool get isMinor => intervals.contains(3) && !intervals.contains(4);
}

/// Una escala concreta: tónica y forma. Da sus notas, sus grados y los
/// acordes que se forman con ella.
class Scale {
  Scale(int tonic, this.shape) : tonic = tonic % 12;

  final int tonic;
  final ScaleShape shape;

  static const List<int> _major = [0, 2, 4, 5, 7, 9, 11];
  static const List<String> _numerals = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];

  List<int> get notes => [for (final i in shape.intervals) (tonic + i) % 12];

  /// Tonalidad que da la ortografía (en un modo, la mayor de la que sale).
  MusicKey get spellingKey {
    if (shape.isMode) {
      final degree = ScaleShape.modes.indexOf(shape);
      return MusicKey(tonic - _major[degree], Mode.major);
    }
    return MusicKey(tonic, shape.isMinor ? Mode.minor : Mode.major);
  }

  SpelledNote spell(int pc) => spellingKey.spell(pc);

  /// Grado de cada nota respecto de la escala mayor: 1 2 ♭3 4 5 6 ♭7.
  List<String> get degreeLabels => [
        for (final i in shape.intervals) _degreeLabel(i),
      ];

  static String _degreeLabel(int interval) {
    // El grado más cercano de la mayor, con su alteración.
    for (var d = 0; d < 7; d++) {
      if (_major[d] == interval) return '${d + 1}';
    }
    for (var d = 0; d < 7; d++) {
      if (_major[d] - 1 == interval) return '♭${d + 1}';
    }
    for (var d = 0; d < 7; d++) {
      if (_major[d] + 1 == interval) return '♯${d + 1}';
    }
    return '$interval';
  }

  /// Tríada de cada grado (solo en escalas de siete notas).
  List<Chord> get triads {
    final n = notes;
    if (n.length != 7) return const [];
    return [
      for (var i = 0; i < 7; i++) Chord(n[i], _triadQuality((n[(i + 2) % 7] - n[i]) % 12, (n[(i + 4) % 7] - n[i]) % 12)),
    ];
  }

  static ChordQuality _triadQuality(int third, int fifth) => switch ((third, fifth)) {
        (4, 7) => ChordQuality.major,
        (3, 7) => ChordQuality.minor,
        (3, 6) => ChordQuality.diminished,
        (4, 8) => ChordQuality.augmented,
        _ => ChordQuality.major,
      };

  /// Acorde de séptima de cada grado (Cmaj7 Dm7 Em7 Fmaj7 G7 Am7 Bm7b5).
  List<Chord> get sevenths {
    final n = notes;
    if (n.length != 7) return const [];
    return [
      for (var i = 0; i < 7; i++)
        Chord(
          n[i],
          switch (((n[(i + 2) % 7] - n[i]) % 12, (n[(i + 4) % 7] - n[i]) % 12, (n[(i + 6) % 7] - n[i]) % 12)) {
            (4, 7, 11) => ChordQuality.major7,
            (4, 7, 10) => ChordQuality.dominant7,
            (3, 7, 10) => ChordQuality.minor7,
            (3, 7, 11) => ChordQuality.minorMajor7,
            (3, 6, 10) => ChordQuality.halfDiminished,
            (3, 6, 9) => ChordQuality.diminished7,
            _ => ChordQuality.augmented,
          },
        ),
    ];
  }

  /// Cifrado romano de cada séptima: Imaj7 ii7 iii7 IVmaj7 V7 vi7 viiø7.
  List<String> get seventhRomans => [
        for (final (i, chord) in sevenths.indexed)
          switch (chord.quality) {
            ChordQuality.halfDiminished => '${romanOf(i, (chord.root - tonic) % 12, ChordQuality.minor)}ø7',
            ChordQuality.diminished7 => '${romanOf(i, (chord.root - tonic) % 12, ChordQuality.diminished)}7',
            ChordQuality.major7 => '${romanOf(i, (chord.root - tonic) % 12, ChordQuality.major)}maj7',
            ChordQuality.minorMajor7 => '${romanOf(i, (chord.root - tonic) % 12, ChordQuality.minor)}(maj7)',
            ChordQuality.augmented => '${romanOf(i, (chord.root - tonic) % 12, ChordQuality.augmented)}maj7',
            final q => '${romanOf(i, (chord.root - tonic) % 12, q)}7',
          },
      ];

  /// Cifrado romano de cada tríada: I ii iii IV V vi vii° (con ♭ si el grado
  /// está bajado respecto de la mayor: ♭III, ♭VII).
  List<String> get romans => [
        for (final (i, chord) in triads.indexed) romanOf(i, (chord.root - tonic) % 12, chord.quality),
      ];

  static String romanOf(int degree, int interval, ChordQuality quality) {
    final diff = interval - _major[degree];
    final accidental = diff == -1 ? '♭' : diff == 1 ? '♯' : '';
    final family = quality.family;
    final upper = family != TriadFamily.minor && family != TriadFamily.diminished;
    final numeral = upper ? _numerals[degree] : _numerals[degree].toLowerCase();
    final suffix = switch (quality) {
      ChordQuality.diminished => '°',
      ChordQuality.augmented => '+',
      _ => '',
    };
    return '$accidental$numeral$suffix';
  }

  /// Lugar en el círculo de quintas (C = 0, G = 1, D = 2… F = 11).
  static int circlePosition(int pc) => (pc * 7) % 12;

  /// Nota en el lugar [position] del círculo de quintas.
  static int circleNote(int position) => (position * 7) % 12;
}

/// Una progresión escrita en grados ("I V vi IV", "ii7 V7 I", "i ♭VII ♭VI V").
///
/// Los grados se cuentan desde la tónica con la escala mayor como referencia:
/// en menor se escribe i iv V o ♭VI, como en los cancioneros.
class RomanProgression {
  const RomanProgression(this.tokens, this.chords, this.unknown);

  final List<String> tokens;
  final List<Chord> chords;
  final List<String> unknown;

  static final RegExp _token = RegExp(
    r'^([b♭#♯]?)(vii|vi|iv|v|iii|ii|i)(°|o|dim|ø|\+|aug)?(maj7|7|9|6|add9|sus4|sus2|m7b5)?$',
    caseSensitive: false,
  );
  static const List<String> _numerals = ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii'];
  static const List<int> _major = [0, 2, 4, 5, 7, 9, 11];

  static RomanProgression parse(String text, int tonic) {
    final tokens = <String>[], unknown = <String>[];
    final chords = <Chord>[];
    for (final raw in text.split(RegExp(r'[\s,|\-–]+'))) {
      if (raw.isEmpty) continue;
      final chord = chordOf(raw, tonic);
      if (chord == null) {
        unknown.add(raw);
      } else {
        tokens.add(raw);
        chords.add(chord);
      }
    }
    return RomanProgression(tokens, chords, unknown);
  }

  /// Un grado en la tonalidad de [tonic], o null si no se entiende.
  static Chord? chordOf(String token, int tonic) {
    final m = _token.firstMatch(token.trim());
    if (m == null) return null;
    final numeral = m.group(2)!;
    final degree = _numerals.indexOf(numeral.toLowerCase());
    final accidental = switch (m.group(1)) {
      'b' || '♭' => -1,
      '#' || '♯' => 1,
      _ => 0,
    };
    final upper = numeral == numeral.toUpperCase();
    final mark = m.group(3)?.toLowerCase();
    final ext = m.group(4)?.toLowerCase();
    final dim = mark == '°' || mark == 'o' || mark == 'dim';
    final half = mark == 'ø' || ext == 'm7b5';
    final aug = mark == '+' || mark == 'aug';
    final quality = half
        ? ChordQuality.halfDiminished
        : dim
            ? (ext == '7' ? ChordQuality.diminished7 : ChordQuality.diminished)
            : aug
                ? ChordQuality.augmented
                : upper
                    ? switch (ext) {
                        '7' => ChordQuality.dominant7,
                        'maj7' => ChordQuality.major7,
                        '9' => ChordQuality.dominant9,
                        '6' => ChordQuality.sixth,
                        'add9' => ChordQuality.add9,
                        'sus4' => ChordQuality.sus4,
                        'sus2' => ChordQuality.sus2,
                        _ => ChordQuality.major,
                      }
                    : switch (ext) {
                        '7' => ChordQuality.minor7,
                        'maj7' => ChordQuality.minorMajor7,
                        '9' => ChordQuality.minor9,
                        '6' => ChordQuality.minorSixth,
                        'add9' => ChordQuality.minorAdd9,
                        _ => ChordQuality.minor,
                      };
    return Chord(tonic + _major[degree] + accidental, quality);
  }
}
