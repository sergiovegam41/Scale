import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../theory/chord.dart';
import '../theory/pitch.dart';
import 'score.dart';

const List<int> _letterPitch = [0, 2, 4, 5, 7, 9, 11];
const String _letters = 'CDEFGAB';

/// Lee partituras MusicXML (.musicxml, .xml y comprimidas .mxl).
///
/// Se queda con lo que Scale usa para mostrar, tocar y seguir: notas,
/// silencios, voces, pentagramas, ligaduras, grupos irregulares, compases,
/// armaduras, tempo, repeticiones y cifrados.
class MusicXmlReader {
  MusicXmlReader._();

  /// Lee el contenido de un archivo; [fileName] solo da el título si la
  /// partitura no tiene.
  static Score readBytes(List<int> bytes, {required String id, String? fileName}) {
    final text = isZip(bytes) ? _unzip(bytes) : _decodeText(bytes);
    return read(text, id: id, fileName: fileName);
  }

  static bool isZip(List<int> bytes) => bytes.length > 3 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  static String _decodeText(List<int> bytes) {
    // UTF-16 con BOM (algunos programas antiguos exportan así).
    if (bytes.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
      final little = bytes[0] == 0xFF;
      final units = <int>[
        for (var i = 2; i + 1 < bytes.length; i += 2) little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
      ];
      return String.fromCharCodes(units);
    }
    var start = 0;
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) start = 3;
    return utf8.decode(bytes.sublist(start), allowMalformed: true);
  }

  static String _unzip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    String? rootPath;
    final container = archive.findFile('META-INF/container.xml');
    if (container != null) {
      final doc = XmlDocument.parse(_decodeText(container.content));
      rootPath = doc.findAllElements('rootfile').firstOrNull?.getAttribute('full-path');
    }
    ArchiveFile? root = rootPath == null ? null : archive.findFile(rootPath);
    root ??= archive.files.where((f) {
      final n = f.name.toLowerCase();
      return f.isFile && !n.startsWith('meta-inf/') && (n.endsWith('.xml') || n.endsWith('.musicxml'));
    }).firstOrNull;
    if (root == null) throw const FormatException('El archivo .mxl no contiene una partitura');
    return _decodeText(root.content);
  }

  static Score read(String text, {required String id, String? fileName}) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(text);
    } on XmlException catch (e) {
      throw FormatException('El archivo no es XML válido: ${e.message}');
    }
    final root = doc.rootElement;
    if (root.name.local == 'score-timewise') {
      throw const FormatException('MusicXML "timewise" todavía no está soportado; expórtalo como "partwise"');
    }
    if (root.name.local != 'score-partwise') throw const FormatException('No es una partitura MusicXML');

    final title = _text(root.getElement('work')?.getElement('work-title')) ??
        _text(root.getElement('movement-title')) ??
        _creditTitle(root) ??
        _stripExtension(fileName) ??
        'Partitura';
    final identification = root.getElement('identification');
    String? creator(String type) => identification
        ?.findElements('creator')
        .where((c) => c.getAttribute('type') == type)
        .map((c) => c.innerText.trim())
        .where((s) => s.isNotEmpty)
        .firstOrNull;

    final names = <String, String>{};
    for (final sp in root.getElement('part-list')?.findElements('score-part') ?? const <XmlElement>[]) {
      names[sp.getAttribute('id') ?? ''] = _text(sp.getElement('part-name')) ?? '';
    }

    final parsed = <_PartParse>[];
    for (final (pi, part) in root.findElements('part').indexed) {
      parsed.add(_PartParse(pi, part, names[part.getAttribute('id')] ?? '')..parse());
    }
    if (parsed.isEmpty) throw const FormatException('La partitura no tiene partes');

    // Los compases son comunes: dura lo que dure la parte más larga.
    final count = parsed.map((p) => p.measures.length).reduce(math.max);
    final measures = <Measure>[];
    var tick = 0;
    for (var i = 0; i < count; i++) {
      final infos = [for (final p in parsed) if (i < p.measures.length) p.measures[i]];
      final first = infos.first;
      var length = infos.map((m) => m.contentLength).reduce(math.max);
      if (length <= 0) length = first.time.measureTicks;
      measures.add(Measure(
        number: first.number,
        tick: tick,
        length: length,
        time: first.time,
        fifths: first.fifths,
        minor: first.minor,
        tempo: infos.map((m) => m.tempo).whereType<double>().firstOrNull,
        repeatStart: infos.any((m) => m.repeatStart),
        repeatEnd: infos.any((m) => m.repeatEnd),
        repeatTimes: first.repeatTimes,
        endings: first.endings,
        implicit: first.implicit,
      ));
      tick += length;
    }

    final parts = <ScorePart>[
      for (final p in parsed)
        ScorePart(
          id: p.element.getAttribute('id') ?? 'P${p.index + 1}',
          name: p.name,
          staves: p.staves,
          clefs: [for (var s = 1; s <= p.staves; s++) p.clefs[s] ?? (s == 1 ? Clef.treble : Clef.bass)],
          events: [
            for (final (mi, e) in p.events)
              if (mi < measures.length) e..tick += measures[mi].tick,
          ]..sort((a, b) => a.tick.compareTo(b.tick)),
          chords: [
            for (final (mi, c) in p.chords)
              if (mi < measures.length) c..tick += measures[mi].tick,
          ],
        ),
    ];

    return Score(
      id: id,
      title: title,
      composer: creator('composer'),
      arranger: creator('arranger'),
      source: ScoreSource(kind: 'musicxml', name: fileName, author: creator('arranger') ?? creator('encoder')),
      measures: measures,
      parts: parts,
    );
  }

  static String? _text(XmlElement? e) {
    final t = e?.innerText.trim();
    return t == null || t.isEmpty ? null : t;
  }

  /// El texto de crédito más grande de la primera página (suele ser el título).
  static String? _creditTitle(XmlElement root) {
    String? best;
    var bestSize = 0.0;
    for (final credit in root.findElements('credit')) {
      final type = _text(credit.getElement('credit-type'));
      for (final words in credit.findElements('credit-words')) {
        final size = double.tryParse(words.getAttribute('font-size') ?? '') ?? 0;
        final t = words.innerText.trim();
        if (t.isEmpty) continue;
        if (type == 'title') return t;
        if (size > bestSize) {
          bestSize = size;
          best = t;
        }
      }
    }
    return best;
  }

  static String? _stripExtension(String? name) {
    if (name == null || name.isEmpty) return null;
    final base = name.split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}

class _MeasureParse {
  _MeasureParse(this.number, this.time, this.fifths, this.minor, this.implicit);

  final String number;
  TimeSignature time;
  int fifths;
  bool minor;
  final bool implicit;
  int contentLength = 0;
  double? tempo;
  bool repeatStart = false;
  bool repeatEnd = false;
  int repeatTimes = 2;
  List<int> endings = const [];
}

class _PartParse {
  _PartParse(this.index, this.element, this.name);

  final int index;
  final XmlElement element;
  final String name;

  final List<_MeasureParse> measures = [];

  /// Eventos con el pulso relativo al inicio de su compás (índice, evento).
  final List<(int, ScoreEvent)> events = [];
  final List<(int, ChordSymbol)> chords = [];
  int staves = 1;
  final Map<int, Clef> clefs = {};

  int _divisions = 1;
  var _time = TimeSignature.common;
  var _fifths = 0;
  var _minor = false;
  List<int>? _ending;
  var _counter = 0;

  int _ticks(String? duration) {
    final d = double.tryParse(duration?.trim() ?? '') ?? 0;
    return (d * ticksPerQuarter / _divisions).round();
  }

  void parse() {
    for (final (mi, m) in element.findElements('measure').indexed) {
      final info = _MeasureParse(
        m.getAttribute('number') ?? '${mi + 1}',
        _time,
        _fifths,
        _minor,
        m.getAttribute('implicit') == 'yes',
      );
      measures.add(info);
      var pos = 0;
      var maxPos = 0;
      ScoreEvent? last;
      if (_ending != null) info.endings = _ending!;

      for (final child in m.childElements) {
        switch (child.name.local) {
          case 'attributes':
            _attributes(child, info, atStart: pos == 0);
          case 'note':
            final e = _note(child, pos, last);
            if (e == null) break;
            if (!identical(e, last)) {
              events.add((mi, e));
              last = e;
              if (!e.grace) pos += e.duration;
            }
          case 'backup':
            pos = math.max(0, pos - _ticks(child.getElement('duration')?.innerText));
            last = null;
          case 'forward':
            pos += _ticks(child.getElement('duration')?.innerText);
            last = null;
          case 'direction':
            final tempo = _directionTempo(child);
            if (tempo != null && (info.tempo == null || pos == 0)) info.tempo = tempo;
          case 'sound':
            final tempo = double.tryParse(child.getAttribute('tempo') ?? '');
            if (tempo != null && tempo > 0) info.tempo ??= tempo;
          case 'harmony':
            final c = _harmony(child, pos);
            if (c != null) chords.add((mi, c));
          case 'barline':
            _barline(child, info);
        }
        maxPos = math.max(maxPos, pos);
      }
      info.contentLength = maxPos;
      // Un compás vacío o una anacrusa sin contenido cuentan como compás entero.
      if (info.contentLength == 0) info.contentLength = info.time.measureTicks;
    }
  }

  void _attributes(XmlElement a, _MeasureParse info, {required bool atStart}) {
    final div = int.tryParse(a.getElement('divisions')?.innerText.trim() ?? '');
    if (div != null && div > 0) _divisions = div;
    final key = a.getElement('key');
    final fifths = int.tryParse(key?.getElement('fifths')?.innerText.trim() ?? '');
    if (fifths != null) {
      _fifths = fifths.clamp(-7, 7);
      _minor = key?.getElement('mode')?.innerText.trim() == 'minor';
      if (atStart) {
        info.fifths = _fifths;
        info.minor = _minor;
      }
    }
    final time = a.getElement('time');
    if (time != null && time.getElement('senza-misura') == null) {
      final beats = (time.getElement('beats')?.innerText ?? '4')
          .split('+')
          .map((s) => int.tryParse(s.trim()) ?? 0)
          .fold(0, (a, b) => a + b);
      final type = int.tryParse(time.getElement('beat-type')?.innerText.trim() ?? '') ?? 4;
      if (beats > 0 && type > 0) {
        _time = TimeSignature(beats, type);
        if (atStart) info.time = _time;
      }
    }
    final st = int.tryParse(a.getElement('staves')?.innerText.trim() ?? '');
    if (st != null && st > 0) staves = st;
    for (final c in a.findElements('clef')) {
      final number = int.tryParse(c.getAttribute('number') ?? '1') ?? 1;
      final sign = c.getElement('sign')?.innerText.trim() ?? 'G';
      final line = int.tryParse(c.getElement('line')?.innerText.trim() ?? '') ?? (sign == 'F' ? 4 : 2);
      final octave = int.tryParse(c.getElement('clef-octave-change')?.innerText.trim() ?? '') ?? 0;
      // Solo la clave inicial de cada pentagrama.
      clefs.putIfAbsent(number, () => Clef(sign, line, octave));
    }
  }

  /// Devuelve el evento nuevo, el anterior si la nota es parte de un acorde,
  /// o null si se ignora.
  ScoreEvent? _note(XmlElement n, int pos, ScoreEvent? last) {
    final grace = n.getElement('grace') != null;
    final isChord = n.getElement('chord') != null;
    final cue = n.getElement('cue') != null;
    final duration = grace ? 0 : _ticks(n.getElement('duration')?.innerText);
    final voice = int.tryParse(n.getElement('voice')?.innerText.trim() ?? '') ?? 1;
    final staff = int.tryParse(n.getElement('staff')?.innerText.trim() ?? '') ?? 1;

    ScoreNote? note;
    final pitch = n.getElement('pitch');
    if (pitch != null && !cue) {
      final step = _letters.indexOf(pitch.getElement('step')?.innerText.trim() ?? 'C');
      final alter = (double.tryParse(pitch.getElement('alter')?.innerText.trim() ?? '') ?? 0).round().clamp(-2, 2);
      final octave = int.tryParse(pitch.getElement('octave')?.innerText.trim() ?? '') ?? 4;
      final letter = step < 0 ? 0 : step;
      final ties = [
        ...n.findElements('tie').map((t) => t.getAttribute('type')),
        ...n.findAllElements('tied').map((t) => t.getAttribute('type')),
      ];
      note = ScoreNote(
        id: n.getAttribute('id') ?? 'n${index}_${_counter++}',
        midi: ((octave + 1) * 12 + _letterPitch[letter] + alter).clamp(0, 127),
        spelling: SpelledNote(letter, alter),
        octave: octave,
        tieStart: ties.contains('start') || ties.contains('continue'),
        tieStop: ties.contains('stop') || ties.contains('continue'),
      );
    }

    if (isChord && last != null) {
      if (note != null) last.notes.add(note);
      return last;
    }

    final type = NoteType.fromMusicXml(n.getElement('type')?.innerText.trim() ?? '');
    final tm = n.getElement('time-modification');
    (int, int)? tuplet;
    if (tm != null) {
      final actual = int.tryParse(tm.getElement('actual-notes')?.innerText.trim() ?? '');
      final normal = int.tryParse(tm.getElement('normal-notes')?.innerText.trim() ?? '');
      if (actual != null && normal != null && actual > 0 && normal > 0) tuplet = (actual, normal);
    }
    final beams = <String>[];
    for (final b in n.findElements('beam')) {
      final level = int.tryParse(b.getAttribute('number') ?? '1') ?? 1;
      if (level < 1 || level > 6) continue;
      while (beams.length < level) {
        beams.add('');
      }
      beams[level - 1] = b.innerText.trim();
    }
    while (beams.isNotEmpty && beams.last.isEmpty) {
      beams.removeLast();
    }
    return ScoreEvent(
      beams: beams,
      id: 'e${index}_${_counter++}',
      tick: pos,
      duration: duration,
      staff: staff,
      voice: voice,
      notes: [?note],
      type: type,
      dots: n.findElements('dot').length,
      tuplet: tuplet,
      grace: grace,
    );
  }

  double? _directionTempo(XmlElement d) {
    final sound = d.getElement('sound')?.getAttribute('tempo');
    final fromSound = double.tryParse(sound ?? '');
    if (fromSound != null && fromSound > 0) return fromSound;
    final metronome = d.findAllElements('metronome').firstOrNull;
    if (metronome == null) return null;
    final perMinute = double.tryParse(metronome.getElement('per-minute')?.innerText.trim() ?? '');
    final unit = NoteType.fromMusicXml(metronome.getElement('beat-unit')?.innerText.trim() ?? '');
    if (perMinute == null || unit == null) return null;
    final dotted = metronome.findElements('beat-unit-dot').length;
    return perMinute * NoteType.dottedTicks(unit, dotted) / ticksPerQuarter;
  }

  ChordSymbol? _harmony(XmlElement h, int pos) {
    final root = h.getElement('root');
    if (root == null) return null;
    final step = _letters.indexOf(root.getElement('root-step')?.innerText.trim() ?? '');
    if (step < 0) return null;
    final alter = (double.tryParse(root.getElement('root-alter')?.innerText.trim() ?? '') ?? 0).round();
    final rootPc = (_letterPitch[step] + alter) % 12;
    final kindEl = h.getElement('kind');
    final kind = kindEl?.innerText.trim() ?? 'major';
    if (kind == 'none') return null;
    final adds = [
      for (final d in h.findElements('degree'))
        if (d.getElement('degree-type')?.innerText.trim() == 'add') int.tryParse(d.getElement('degree-value')?.innerText.trim() ?? ''),
    ];
    final quality = _quality(kind, adds);
    int? bassPc;
    final bass = h.getElement('bass');
    if (bass != null) {
      final b = _letters.indexOf(bass.getElement('bass-step')?.innerText.trim() ?? '');
      if (b >= 0) {
        bassPc = (_letterPitch[b] + (double.tryParse(bass.getElement('bass-alter')?.innerText.trim() ?? '') ?? 0).round()) % 12;
      }
    }
    final offset = _ticks(h.getElement('offset')?.innerText);
    final text = kindEl?.getAttribute('text');
    return ChordSymbol(tick: math.max(0, pos + offset), chord: Chord(rootPc, quality, bass: bassPc), text: text);
  }

  static ChordQuality _quality(String kind, List<int?> adds) {
    final q = switch (kind) {
      'major' => ChordQuality.major,
      'minor' => ChordQuality.minor,
      'augmented' => ChordQuality.augmented,
      'diminished' => ChordQuality.diminished,
      'dominant' || 'augmented-seventh' => ChordQuality.dominant7,
      'major-seventh' => ChordQuality.major7,
      'minor-seventh' => ChordQuality.minor7,
      'diminished-seventh' => ChordQuality.diminished7,
      'half-diminished' => ChordQuality.halfDiminished,
      'major-minor' => ChordQuality.minorMajor7,
      'major-sixth' => ChordQuality.sixth,
      'minor-sixth' => ChordQuality.minorSixth,
      'dominant-ninth' || 'dominant-11th' || 'dominant-13th' => ChordQuality.dominant9,
      'major-ninth' || 'major-11th' || 'major-13th' => ChordQuality.major9,
      'minor-ninth' || 'minor-11th' || 'minor-13th' => ChordQuality.minor9,
      'suspended-second' => ChordQuality.sus2,
      'suspended-fourth' => ChordQuality.sus4,
      'power' => ChordQuality.power,
      _ => kind.startsWith('minor') ? ChordQuality.minor : ChordQuality.major,
    };
    if (adds.contains(9) || adds.contains(2)) {
      if (q == ChordQuality.major) return ChordQuality.add9;
      if (q == ChordQuality.minor) return ChordQuality.minorAdd9;
      if (q == ChordQuality.sixth) return ChordQuality.sixNine;
    }
    return q;
  }

  void _barline(XmlElement b, _MeasureParse info) {
    final repeat = b.getElement('repeat');
    if (repeat != null) {
      final dir = repeat.getAttribute('direction');
      if (dir == 'forward') info.repeatStart = true;
      if (dir == 'backward') {
        info.repeatEnd = true;
        info.repeatTimes = int.tryParse(repeat.getAttribute('times') ?? '') ?? 2;
      }
    }
    final ending = b.getElement('ending');
    if (ending != null) {
      final type = ending.getAttribute('type');
      final numbers = [
        for (final s in (ending.getAttribute('number') ?? '1').split(RegExp(r'[,\s]+')))
          if (int.tryParse(s) case final n?) n,
      ];
      if (type == 'start') {
        _ending = numbers;
        info.endings = numbers;
      } else if (type == 'stop' || type == 'discontinue') {
        if (info.endings.isEmpty) info.endings = numbers;
        _ending = null;
      }
    }
  }
}
