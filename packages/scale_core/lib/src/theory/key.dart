import 'chord.dart';
import 'chord_parser.dart';
import 'pitch.dart';

enum Mode { major, minor }

/// Tonalidad: tónica (clase de altura) y modo.
class MusicKey {
  MusicKey(int tonic, this.mode) : tonic = tonic % 12;

  /// 0..11 mayores, 12..23 menores.
  factory MusicKey.fromIndex(int index) => MusicKey(index % 12, index < 12 ? Mode.major : Mode.minor);

  factory MusicKey.fromJson(Map<String, dynamic> json) =>
      MusicKey(json['tonic'] as int, json['mode'] == 'minor' ? Mode.minor : Mode.major);

  /// Lee "G", "Em", "Sol mayor", "Mi menor", "F# minor"…
  static MusicKey? parse(String input) {
    var s = input.trim();
    var minor = false;
    final lower = s.toLowerCase();
    for (final (word, isMinor) in const [
      ('mayor', false),
      ('major', false),
      ('menor', true),
      ('minor', true),
    ]) {
      if (lower.endsWith(word)) {
        s = s.substring(0, s.length - word.length).trim();
        minor = isMinor;
        break;
      }
    }
    final chord = ChordParser.parse(s);
    if (chord == null) return null;
    final family = chord.quality.family;
    if (family != TriadFamily.major && family != TriadFamily.minor) return null;
    return MusicKey(chord.root, minor || family == TriadFamily.minor ? Mode.minor : Mode.major);
  }

  static final List<MusicKey> all = [for (var i = 0; i < 24; i++) MusicKey.fromIndex(i)];

  static const List<int> _majorScale = [0, 2, 4, 5, 7, 9, 11];
  static const List<int> _minorScale = [0, 2, 3, 5, 7, 8, 10];

  // Ortografía convencional de la tónica (menos alteraciones en la armadura).
  static const List<SpelledNote> _majorTonics = [
    SpelledNote(0, 0), SpelledNote(1, -1), SpelledNote(1, 0), SpelledNote(2, -1),
    SpelledNote(2, 0), SpelledNote(3, 0), SpelledNote(3, 1), SpelledNote(4, 0),
    SpelledNote(5, -1), SpelledNote(5, 0), SpelledNote(6, -1), SpelledNote(6, 0),
  ];
  static const List<SpelledNote> _minorTonics = [
    SpelledNote(0, 0), SpelledNote(0, 1), SpelledNote(1, 0), SpelledNote(2, -1),
    SpelledNote(2, 0), SpelledNote(3, 0), SpelledNote(3, 1), SpelledNote(4, 0),
    SpelledNote(4, 1), SpelledNote(5, 0), SpelledNote(6, -1), SpelledNote(6, 0),
  ];

  // Semitonos desde la tónica → cuántas letras avanzar (b2, b3, #4, b6, b7).
  static const List<int> _degreeLetterOffset = [0, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6];

  final int tonic;
  final Mode mode;

  bool get isMajor => mode == Mode.major;
  int get index => (isMajor ? 0 : 12) + tonic;

  /// Relativa: mismas notas (G ≡ Em).
  MusicKey get relative => isMajor ? MusicKey(tonic + 9, Mode.minor) : MusicKey(tonic + 3, Mode.major);
  MusicKey get parallel => MusicKey(tonic, isMajor ? Mode.minor : Mode.major);
  MusicKey transpose(int semitones) => MusicKey(tonic + semitones, mode);

  List<int> get scale => [for (final i in isMajor ? _majorScale : _minorScale) (tonic + i) % 12];

  /// Pertenece a la escala (en menor se acepta también la sensible, armónica).
  bool fits(int pc) {
    final d = degreeOf(pc);
    return (isMajor ? _majorScale : _minorScale).contains(d) || (!isMajor && d == 11);
  }

  int degreeOf(int pc) => (pc - tonic) % 12;

  SpelledNote get tonicSpelling => (isMajor ? _majorTonics : _minorTonics)[tonic];

  /// Escribe [pc] según su función en esta tonalidad: en E mayor el 3 es D#,
  /// en F mayor el 10 es Bb, en D mayor el 0 (bVII) es C.
  SpelledNote spell(int pc) {
    final letter = tonicSpelling.letter + _degreeLetterOffset[degreeOf(pc)];
    final note = SpelledNote.onLetter(letter, pc);
    return note.accidental.abs() > 1 ? SpelledNote.byDefault(pc) : note;
  }

  /// Nombre corto: "G", "Em".
  String name([Notation notation = Notation.american]) =>
      tonicSpelling.name(notation) + (isMajor ? '' : 'm');

  /// Nombre largo: "G mayor", "Mi menor".
  String label([Notation notation = Notation.american]) =>
      '${tonicSpelling.name(notation)} ${isMajor ? 'mayor' : 'menor'}';

  /// Misma tonalidad escrita con la otra enarmonía (F# ≡ Gb), si existe.
  String? enharmonicName([Notation notation = Notation.american]) {
    final other = tonicSpelling.enharmonic;
    return other == null ? null : other.name(notation) + (isMajor ? '' : 'm');
  }

  Map<String, dynamic> toJson() => {'tonic': tonic, 'mode': mode.name};

  @override
  bool operator ==(Object other) => other is MusicKey && other.tonic == tonic && other.mode == mode;

  @override
  int get hashCode => Object.hash(tonic, mode);

  @override
  String toString() => name();
}
