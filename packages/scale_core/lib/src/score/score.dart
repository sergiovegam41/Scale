import '../theory/chord.dart';
import '../theory/pitch.dart';
import 'transcriber.dart';

/// Pulsos por negra en todo el modelo de partitura.
const int ticksPerQuarter = 480;

/// Figura escrita (redonda, blanca, negra…).
enum NoteType {
  maxima('maxima', 32),
  long('long', 16),
  breve('breve', 8),
  whole('whole', 4),
  half('half', 2),
  quarter('quarter', 1),
  eighth('eighth', 1 / 2),
  sixteenth('16th', 1 / 4),
  thirtySecond('32nd', 1 / 8),
  sixtyFourth('64th', 1 / 16),
  oneTwentyEighth('128th', 1 / 32);

  const NoteType(this.musicXml, this.quarters);

  /// Nombre en MusicXML (`<type>`).
  final String musicXml;

  /// Duración en negras, sin puntillo.
  final double quarters;

  int get ticks => (quarters * ticksPerQuarter).round();

  static NoteType? fromMusicXml(String s) {
    for (final t in values) {
      if (t.musicXml == s) return t;
    }
    return null;
  }

  /// Figura y puntillos que mejor escriben [ticks] (o null si no hay una
  /// figura simple exacta y hace falta ligar).
  static (NoteType, int)? ofTicks(int ticks) {
    for (final t in values) {
      for (var dots = 0; dots <= 2; dots++) {
        if (dottedTicks(t, dots) == ticks) return (t, dots);
      }
    }
    return null;
  }

  static int dottedTicks(NoteType t, int dots) {
    var total = 0.0;
    var part = t.quarters;
    for (var i = 0; i <= dots; i++) {
      total += part;
      part /= 2;
    }
    return (total * ticksPerQuarter).round();
  }
}

/// Clave de un pentagrama.
class Clef {
  const Clef(this.sign, this.line, [this.octaveChange = 0]);

  factory Clef.fromJson(Map<String, dynamic> j) =>
      Clef(j['sign'] as String, j['line'] as int, (j['octave'] as int?) ?? 0);

  static const treble = Clef('G', 2);
  static const bass = Clef('F', 4);

  /// 'G', 'F', 'C', 'percussion'…
  final String sign;
  final int line;
  final int octaveChange;

  Map<String, dynamic> toJson() => {'sign': sign, 'line': line, if (octaveChange != 0) 'octave': octaveChange};

  @override
  bool operator ==(Object other) =>
      other is Clef && other.sign == sign && other.line == line && other.octaveChange == octaveChange;

  @override
  int get hashCode => Object.hash(sign, line, octaveChange);
}

/// Compás (4/4, 6/8…).
class TimeSignature {
  const TimeSignature(this.beats, this.beatType);

  factory TimeSignature.fromJson(List<dynamic> j) => TimeSignature(j[0] as int, j[1] as int);

  static const common = TimeSignature(4, 4);

  final int beats;
  final int beatType;

  int get measureTicks => beats * ticksPerQuarter * 4 ~/ beatType;

  List<int> toJson() => [beats, beatType];

  @override
  String toString() => '$beats/$beatType';

  @override
  bool operator ==(Object other) => other is TimeSignature && other.beats == beats && other.beatType == beatType;

  @override
  int get hashCode => Object.hash(beats, beatType);
}

/// Datos de un compás comunes a todas las partes: dónde empieza, cuánto
/// dura, compás, armadura, tempo y repeticiones.
class Measure {
  Measure({
    required this.number,
    required this.tick,
    required this.length,
    required this.time,
    required this.fifths,
    this.minor = false,
    this.tempo,
    this.repeatStart = false,
    this.repeatEnd = false,
    this.repeatTimes = 2,
    this.endings = const [],
    this.implicit = false,
  });

  factory Measure.fromJson(Map<String, dynamic> j) => Measure(
    number: j['n'] as String,
    tick: j['t'] as int,
    length: j['len'] as int,
    time: TimeSignature.fromJson(j['time'] as List<dynamic>),
    fifths: j['fifths'] as int,
    minor: j['minor'] as bool? ?? false,
    tempo: (j['tempo'] as num?)?.toDouble(),
    repeatStart: j['repStart'] as bool? ?? false,
    repeatEnd: j['repEnd'] as bool? ?? false,
    repeatTimes: j['repTimes'] as int? ?? 2,
    endings: [for (final e in (j['endings'] as List<dynamic>? ?? const [])) e as int],
    implicit: j['implicit'] as bool? ?? false,
  );

  /// Número como se escribe (puede ser "12a" o "X1").
  final String number;

  /// Inicio en pulsos desde el principio de la partitura (sin repetir).
  int tick;

  /// Duración real (una anacrusa es más corta que el compás).
  int length;
  TimeSignature time;

  /// Armadura: sostenidos positivos, bemoles negativos.
  int fifths;
  bool minor;

  /// Negras por minuto que empiezan en este compás (null: sigue el anterior).
  double? tempo;
  bool repeatStart;
  bool repeatEnd;

  /// Veces que se toca lo encerrado en la repetición (normalmente 2).
  int repeatTimes;

  /// Casillas de primera/segunda vez a las que pertenece este compás.
  List<int> endings;

  /// Anacrusa u otro compás que no cuenta en la numeración.
  bool implicit;

  int get end => tick + length;

  Map<String, dynamic> toJson() => {
    'n': number,
    't': tick,
    'len': length,
    'time': time.toJson(),
    'fifths': fifths,
    if (minor) 'minor': true,
    if (tempo != null) 'tempo': tempo,
    if (repeatStart) 'repStart': true,
    if (repeatEnd) 'repEnd': true,
    if (repeatEnd && repeatTimes != 2) 'repTimes': repeatTimes,
    if (endings.isNotEmpty) 'endings': endings,
    if (implicit) 'implicit': true,
  };
}

/// Una nota escrita: altura que suena, ortografía y ligaduras de prolongación.
class ScoreNote {
  ScoreNote({
    required this.id,
    required this.midi,
    required this.spelling,
    required this.octave,
    this.tieStart = false,
    this.tieStop = false,
    this.velocity,
  });

  factory ScoreNote.fromJson(Map<String, dynamic> j) => ScoreNote(
    id: j['id'] as String,
    midi: j['m'] as int,
    spelling: SpelledNote(j['l'] as int, j['a'] as int? ?? 0),
    octave: j['o'] as int,
    tieStart: j['ts'] as bool? ?? false,
    tieStop: j['te'] as bool? ?? false,
    velocity: j['v'] as int?,
  );

  /// Estable: no cambia al guardar ni al editar otras notas.
  final String id;
  int midi;
  SpelledNote spelling;

  /// Octava de la letra escrita (Do4 = do central).
  int octave;

  /// Ligada a la siguiente nota igual (se prolonga, no se vuelve a tocar).
  bool tieStart;

  /// Viene ligada de la anterior.
  bool tieStop;

  /// Fuerza con que se tocó (1..127), si se conoce: la de una grabación o la
  /// indicada nota a nota en el archivo. Si es null, sale de las dinámicas
  /// escritas (p, mf, f…).
  int? velocity;

  Map<String, dynamic> toJson() => {
    'id': id,
    'm': midi,
    'l': spelling.letter,
    if (spelling.accidental != 0) 'a': spelling.accidental,
    'o': octave,
    if (tieStart) 'ts': true,
    if (tieStop) 'te': true,
    if (velocity != null) 'v': velocity,
  };
}

/// Un evento en una voz: nota, acorde (varias notas a la vez) o silencio.
class ScoreEvent {
  ScoreEvent({
    required this.id,
    required this.tick,
    required this.duration,
    required this.staff,
    required this.voice,
    required this.notes,
    this.type,
    this.dots = 0,
    this.tuplet,
    this.tupletSpan,
    this.grace = false,
    this.beams = const [],
  });

  factory ScoreEvent.fromJson(Map<String, dynamic> j) => ScoreEvent(
    id: j['id'] as String,
    tick: j['t'] as int,
    duration: j['d'] as int,
    staff: j['s'] as int? ?? 1,
    voice: j['v'] as int? ?? 1,
    notes: [for (final n in (j['n'] as List<dynamic>? ?? const [])) ScoreNote.fromJson(n as Map<String, dynamic>)],
    type: j['ty'] == null ? null : NoteType.fromMusicXml(j['ty'] as String),
    dots: j['dots'] as int? ?? 0,
    tuplet: j['tup'] == null ? null : (((j['tup'] as List)[0] as int), ((j['tup'] as List)[1] as int)),
    tupletSpan: j['tsp'] as int?,
    grace: j['g'] as bool? ?? false,
    beams: [for (final b in (j['b'] as List<dynamic>? ?? const [])) b as String],
  );

  final String id;

  /// Inicio en pulsos desde el principio de la partitura.
  int tick;

  /// Duración que suena, en pulsos (0 en las notas de adorno).
  int duration;

  /// Pentagrama dentro de la parte: 1 = arriba (mano derecha en piano).
  int staff;
  int voice;

  /// Vacío: silencio.
  List<ScoreNote> notes;

  /// Figura escrita; null si hay que deducirla de la duración.
  NoteType? type;
  int dots;

  /// Grupo irregular: (notas reales, notas normales), p. ej. (3, 2) en un tresillo.
  (int, int)? tuplet;

  /// Lo que dura (en pulsos reales) el grupo irregular que empieza en este
  /// evento, si no es el habitual (p. ej. un tresillo de una negra que
  /// empieza con negra de tresillo). Null: se deduce de la figura.
  int? tupletSpan;
  bool grace;

  /// Barras de corchea por nivel, como en MusicXML: 'begin', 'continue',
  /// 'end', 'forward hook', 'backward hook'. Vacío: se agrupan solas al
  /// escribir.
  List<String> beams;

  bool get isRest => notes.isEmpty;
  int get end => tick + duration;

  Map<String, dynamic> toJson() => {
    'id': id,
    't': tick,
    'd': duration,
    if (staff != 1) 's': staff,
    if (voice != 1) 'v': voice,
    if (notes.isNotEmpty) 'n': [for (final n in notes) n.toJson()],
    if (type != null) 'ty': type!.musicXml,
    if (dots != 0) 'dots': dots,
    if (tuplet != null) 'tup': [tuplet!.$1, tuplet!.$2],
    if (tupletSpan != null) 'tsp': tupletSpan,
    if (grace) 'g': true,
    if (beams.isNotEmpty) 'b': beams,
  };
}

/// Indicación de dinámica escrita: una marca (p, mf, f…) o un regulador
/// (crescendo / diminuendo y su final).
class ScoreDirection {
  ScoreDirection({required this.tick, required this.kind, required this.value, this.staff = 1});

  factory ScoreDirection.fromJson(Map<String, dynamic> j) => ScoreDirection(
    tick: j['t'] as int,
    kind: j['k'] == 'wedge' ? DirectionKind.wedge : DirectionKind.dynamic,
    value: j['val'] as String,
    staff: j['s'] as int? ?? 1,
  );

  int tick;
  final DirectionKind kind;

  /// Marca ('pp', 'mf', 'sfz'…) o, en un regulador, 'crescendo',
  /// 'diminuendo' o 'stop'.
  final String value;
  int staff;

  /// Fuerza MIDI típica de cada marca (la misma escala que MuseScore).
  static const Map<String, int> velocities = {
    'pppp': 10,
    'ppp': 16,
    'pp': 33,
    'p': 49,
    'mp': 64,
    'mf': 80,
    'f': 96,
    'ff': 112,
    'fff': 126,
    'ffff': 127,
    'sf': 112,
    'sfz': 112,
    'sffz': 126,
    'fz': 112,
    'rf': 112,
    'rfz': 112,
    'fp': 96,
    'sfp': 112,
  };

  /// Marcas que solo acentúan una nota, no cambian el nivel general.
  static const Set<String> accents = {'sf', 'sfz', 'sffz', 'fz', 'rf', 'rfz', 'fp', 'sfp'};

  /// Marca más cercana a una fuerza MIDI (para escribir las dinámicas de una
  /// grabación).
  static String markFor(int velocity) {
    const levels = ['ppp', 'pp', 'p', 'mp', 'mf', 'f', 'ff', 'fff'];
    var best = 'mf';
    var bestDiff = 999;
    for (final l in levels) {
      final d = (velocities[l]! - velocity).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = l;
      }
    }
    return best;
  }

  Map<String, dynamic> toJson() => {'t': tick, 'k': kind.name, 'val': value, if (staff != 1) 's': staff};
}

enum DirectionKind { dynamic, wedge }

/// Un cifrado escrito sobre el pentagrama.
class ChordSymbol {
  ChordSymbol({required this.tick, required this.chord, this.text});

  factory ChordSymbol.fromJson(Map<String, dynamic> j) => ChordSymbol(
    tick: j['t'] as int,
    chord: Chord.fromJson(j['c'] as Map<String, dynamic>),
    text: j['txt'] as String?,
  );

  int tick;
  Chord chord;

  /// Texto original si no coincide con el formato de Scale.
  String? text;

  Map<String, dynamic> toJson() => {'t': tick, 'c': chord.toJson(), if (text != null) 'txt': text};
}

/// Un instrumento o mano: uno o varios pentagramas con sus eventos.
class ScorePart {
  ScorePart({
    required this.id,
    required this.name,
    this.staves = 1,
    List<Clef>? clefs,
    List<ScoreEvent>? events,
    List<ChordSymbol>? chords,
    List<ScoreDirection>? directions,
    this.program,
  }) : clefs = clefs ?? [for (var i = 0; i < staves; i++) i == 0 ? Clef.treble : Clef.bass],
       events = events ?? [],
       chords = chords ?? [],
       directions = directions ?? [];

  factory ScorePart.fromJson(Map<String, dynamic> j) => ScorePart(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    staves: j['staves'] as int? ?? 1,
    clefs: [for (final c in (j['clefs'] as List<dynamic>? ?? const [])) Clef.fromJson(c as Map<String, dynamic>)],
    events: [
      for (final e in (j['events'] as List<dynamic>? ?? const [])) ScoreEvent.fromJson(e as Map<String, dynamic>),
    ],
    chords: [
      for (final c in (j['chords'] as List<dynamic>? ?? const [])) ChordSymbol.fromJson(c as Map<String, dynamic>),
    ],
    directions: [
      for (final d in (j['dirs'] as List<dynamic>? ?? const [])) ScoreDirection.fromJson(d as Map<String, dynamic>),
    ],
    program: j['program'] as int?,
  );

  final String id;
  String name;
  int staves;

  /// Clave inicial de cada pentagrama.
  List<Clef> clefs;

  /// Ordenados por inicio.
  List<ScoreEvent> events;
  List<ChordSymbol> chords;

  /// Dinámicas escritas, ordenadas por inicio.
  List<ScoreDirection> directions;

  /// Instrumento General MIDI (0 = piano).
  int? program;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'staves': staves,
    'clefs': [for (final c in clefs) c.toJson()],
    'events': [for (final e in events) e.toJson()],
    if (chords.isNotEmpty) 'chords': [for (final c in chords) c.toJson()],
    if (directions.isNotEmpty) 'dirs': [for (final d in directions) d.toJson()],
    if (program != null) 'program': program,
  };
}

/// De dónde vino una partitura: archivo, web, grabación…
class ScoreSource {
  ScoreSource({required this.kind, this.name, this.url, this.author, DateTime? importedAt})
    : importedAt = importedAt ?? DateTime.now();

  factory ScoreSource.fromJson(Map<String, dynamic> j) => ScoreSource(
    kind: j['kind'] as String,
    name: j['name'] as String?,
    url: j['url'] as String?,
    author: j['author'] as String?,
    importedAt: DateTime.tryParse(j['at'] as String? ?? ''),
  );

  /// 'musicxml', 'midi', 'recording', 'photo'…
  final String kind;

  /// Nombre del archivo original.
  final String? name;
  final String? url;

  /// Arreglista o quien hizo el archivo.
  final String? author;
  final DateTime importedAt;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    if (name != null) 'name': name,
    if (url != null) 'url': url,
    if (author != null) 'author': author,
    'at': importedAt.toIso8601String(),
  };
}

/// Partitura guardada en Scale.
///
/// Es la fuente de verdad: MusicXML y MIDI solo se usan para importar y
/// exportar. Cada nota tiene un id estable para resaltarla, seguirla y
/// corregirla.
class Score {
  Score({
    required this.id,
    required this.title,
    this.composer,
    this.arranger,
    this.source,
    List<Measure>? measures,
    List<ScorePart>? parts,
    this.recording,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : measures = measures ?? [],
       parts = parts ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  static const String format = 'scale.score';
  static const int version = 1;

  factory Score.fromJson(Map<String, dynamic> j) {
    if (j['format'] != format) throw const FormatException('No es una partitura de Scale');
    return Score(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      composer: j['composer'] as String?,
      arranger: j['arranger'] as String?,
      source: j['source'] == null ? null : ScoreSource.fromJson(j['source'] as Map<String, dynamic>),
      measures: [for (final m in j['measures'] as List<dynamic>) Measure.fromJson(m as Map<String, dynamic>)],
      parts: [for (final p in j['parts'] as List<dynamic>) ScorePart.fromJson(p as Map<String, dynamic>)],
      recording: j['recording'] == null ? null : ScoreRecording.fromJson(j['recording'] as Map<String, dynamic>),
      createdAt: DateTime.tryParse(j['created'] as String? ?? ''),
      updatedAt: DateTime.tryParse(j['updated'] as String? ?? ''),
    );
  }

  final String id;
  String title;
  String? composer;
  String? arranger;
  ScoreSource? source;
  List<Measure> measures;
  List<ScorePart> parts;

  /// Si salió de una grabación: la interpretación original, para oírla tal
  /// como se tocó o volver a escribirla con otros ajustes.
  ScoreRecording? recording;
  DateTime createdAt;
  DateTime updatedAt;

  int get lengthTicks => measures.isEmpty ? 0 : measures.last.end;

  /// Compás que contiene [tick].
  int measureAt(int tick) {
    var lo = 0;
    var hi = measures.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (measures[mid].tick <= tick) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Cuántas notas (no silencios) tiene.
  int get noteCount => parts.fold(0, (n, p) => n + p.events.fold(0, (m, e) => m + e.notes.length));

  Map<String, dynamic> toJson() => {
    'format': format,
    'version': version,
    'id': id,
    'title': title,
    if (composer != null) 'composer': composer,
    if (arranger != null) 'arranger': arranger,
    if (source != null) 'source': source!.toJson(),
    'created': createdAt.toIso8601String(),
    'updated': updatedAt.toIso8601String(),
    'measures': [for (final m in measures) m.toJson()],
    'parts': [for (final p in parts) p.toJson()],
    if (recording != null) 'recording': recording!.toJson(),
  };
}
