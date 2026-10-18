/// Familia de la tríada base; es lo que compara el modo "tocar" (flexible).
enum TriadFamily {
  major,
  minor,
  diminished,
  augmented,
  suspended,
  power;

  bool get _loose => this == suspended || this == power;
  bool get _plain => this == major || this == minor;

  /// Coincidencia flexible: sus y quintas valen como mayor o menor.
  bool compatibleWith(TriadFamily other) {
    if (this == other) return true;
    if (_loose) return other._plain || other._loose;
    if (other._loose) return _plain;
    return false;
  }
}

/// Tipo de acorde: intervalos desde la fundamental y su sufijo de cifrado.
class ChordQuality {
  const ChordQuality._(
    this.id,
    this.symbol,
    this.intervals,
    this.family,
    this.complexity, {
    this.dominant = false,
  });

  /// Identificador estable para persistir (no cambia aunque cambie el sufijo).
  final String id;

  /// Sufijo de cifrado: '', 'm', '7', 'sus4'…
  final String symbol;

  /// Semitonos desde la fundamental, empezando por 0.
  final List<int> intervals;
  final TriadFamily family;

  /// Penalización a priori: ante la duda se prefiere el acorde más simple.
  final double complexity;

  /// Tiene la séptima menor sobre tríada mayor (función de dominante).
  final bool dominant;

  static const major = ChordQuality._('maj', '', [0, 4, 7], TriadFamily.major, 0);
  static const minor = ChordQuality._('m', 'm', [0, 3, 7], TriadFamily.minor, 0);
  static const diminished = ChordQuality._('dim', 'dim', [0, 3, 6], TriadFamily.diminished, 0.3);
  static const augmented = ChordQuality._('aug', 'aug', [0, 4, 8], TriadFamily.augmented, 0.4);
  static const sus2 = ChordQuality._('sus2', 'sus2', [0, 2, 7], TriadFamily.suspended, 0.15);
  static const sus4 = ChordQuality._('sus4', 'sus4', [0, 5, 7], TriadFamily.suspended, 0.1);
  static const power = ChordQuality._('5', '5', [0, 7], TriadFamily.power, 0.3);
  static const sixth = ChordQuality._('6', '6', [0, 4, 7, 9], TriadFamily.major, 0.25);
  static const minorSixth = ChordQuality._('m6', 'm6', [0, 3, 7, 9], TriadFamily.minor, 0.3);
  static const dominant7 =
      ChordQuality._('7', '7', [0, 4, 7, 10], TriadFamily.major, 0.1, dominant: true);
  static const major7 = ChordQuality._('maj7', 'maj7', [0, 4, 7, 11], TriadFamily.major, 0.15);
  static const minor7 = ChordQuality._('m7', 'm7', [0, 3, 7, 10], TriadFamily.minor, 0.1);
  static const minorMajor7 =
      ChordQuality._('mMaj7', 'm(maj7)', [0, 3, 7, 11], TriadFamily.minor, 0.5);
  static const halfDiminished =
      ChordQuality._('m7b5', 'm7b5', [0, 3, 6, 10], TriadFamily.diminished, 0.3);
  static const diminished7 =
      ChordQuality._('dim7', 'dim7', [0, 3, 6, 9], TriadFamily.diminished, 0.4);
  static const dominant7sus4 =
      ChordQuality._('7sus4', '7sus4', [0, 5, 7, 10], TriadFamily.suspended, 0.2, dominant: true);
  static const add9 = ChordQuality._('add9', 'add9', [0, 2, 4, 7], TriadFamily.major, 0.15);
  static const minorAdd9 =
      ChordQuality._('madd9', 'm(add9)', [0, 2, 3, 7], TriadFamily.minor, 0.2);
  static const dominant9 =
      ChordQuality._('9', '9', [0, 2, 4, 7, 10], TriadFamily.major, 0.25, dominant: true);
  static const major9 = ChordQuality._('maj9', 'maj9', [0, 2, 4, 7, 11], TriadFamily.major, 0.3);
  static const minor9 = ChordQuality._('m9', 'm9', [0, 2, 3, 7, 10], TriadFamily.minor, 0.25);
  static const sixNine = ChordQuality._('69', '6/9', [0, 2, 4, 7, 9], TriadFamily.major, 0.35);
  static const add4 = ChordQuality._('add4', 'add4', [0, 4, 5, 7], TriadFamily.major, 0.35);

  static const List<ChordQuality> all = [
    major, minor, diminished, augmented, sus2, sus4, power, sixth, minorSixth,
    dominant7, major7, minor7, minorMajor7, halfDiminished, diminished7,
    dominant7sus4, add9, minorAdd9, dominant9, major9, minor9, sixNine, add4,
  ];

  static final Map<String, ChordQuality> _byId = {for (final q in all) q.id: q};

  static ChordQuality? byId(String id) => _byId[id];

  @override
  String toString() => id;
}

/// Un acorde independiente de la ortografía: fundamental y bajo como clases
/// de altura (0..11). El nombre (F# o Gb, Re o D) se decide al mostrarlo.
class Chord {
  Chord(int root, this.quality, {int? bass})
      : root = root % 12,
        bass = (bass == null || bass % 12 == root % 12) ? null : bass % 12;

  factory Chord.fromJson(Map<String, dynamic> json) => Chord(
        json['root'] as int,
        ChordQuality.byId(json['quality'] as String) ?? ChordQuality.major,
        bass: json['bass'] as int?,
      );

  final int root;
  final ChordQuality quality;

  /// Bajo distinto de la fundamental (C/E), o null si está en fundamental.
  final int? bass;

  bool get isSlash => bass != null;

  Set<int> get pitchClasses {
    final b = bass;
    return {
      for (final i in quality.intervals) (root + i) % 12,
      if (b != null) b,
    };
  }

  Chord transpose(int semitones) {
    final b = bass;
    return Chord(root + semitones, quality, bass: b == null ? null : b + semitones);
  }

  /// Coincidencia flexible: misma fundamental y familia compatible
  /// (Gadd9, G/B y G7 valen como G).
  bool matchesFlexibly(Chord other) =>
      root == other.root && quality.family.compatibleWith(other.quality.family);

  Map<String, dynamic> toJson() => {
        'root': root,
        'quality': quality.id,
        if (bass != null) 'bass': bass,
      };

  @override
  bool operator ==(Object other) =>
      other is Chord && other.root == root && other.quality == quality && other.bass == bass;

  @override
  int get hashCode => Object.hash(root, quality, bass);

  @override
  String toString() => '${root}_${quality.id}${bass == null ? '' : '/$bass'}';
}
