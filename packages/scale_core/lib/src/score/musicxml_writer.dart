import 'dart:math' as math;

import 'package:xml/xml.dart';

import 'score.dart';

const String _letters = 'CDEFGAB';

/// Escribe una partitura de Scale como MusicXML 4.0 (partwise).
///
/// Sirve para exportar y para el visor: cada `<note>` lleva el id de Scale,
/// así el visor puede resaltar las notas por id.
class MusicXmlWriter {
  MusicXmlWriter._();

  static String write(Score score) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element('score-partwise', attributes: {'version': '4.0'}, nest: () {
      b.element('work', nest: () => b.element('work-title', nest: score.title));
      b.element('identification', nest: () {
        if (score.composer != null) b.element('creator', attributes: {'type': 'composer'}, nest: score.composer);
        if (score.arranger != null) b.element('creator', attributes: {'type': 'arranger'}, nest: score.arranger);
        b.element('encoding', nest: () => b.element('software', nest: 'Scale'));
      });
      b.element('part-list', nest: () {
        for (final p in score.parts) {
          b.element('score-part', attributes: {'id': p.id}, nest: () {
            b.element('part-name', nest: p.name);
          });
        }
      });
      for (final p in score.parts) {
        _PartWriter(b, score, p).write();
      }
    });
    return b.buildDocument().toXmlString();
  }
}

class _PartWriter {
  _PartWriter(this.b, this.score, this.part);

  final XmlBuilder b;
  final Score score;
  final ScorePart part;

  void write() {
    final byMeasure = [for (final _ in score.measures) <ScoreEvent>[]];
    for (final e in part.events) {
      byMeasure[score.measureAt(e.tick)].add(e);
    }
    final chordsBy = [for (final _ in score.measures) <ChordSymbol>[]];
    for (final c in part.chords) {
      chordsBy[score.measureAt(c.tick)].add(c);
    }
    b.element('part', attributes: {'id': part.id}, nest: () {
      for (final (mi, m) in score.measures.indexed) {
        final prev = mi == 0 ? null : score.measures[mi - 1];
        b.element('measure', attributes: {'number': m.number, if (m.implicit) 'implicit': 'yes'}, nest: () {
          _attributes(m, prev, first: mi == 0);
          _leftBarline(m, prev);
          if (m.tempo != null && part == score.parts.first) _tempo(m.tempo!);
          for (final c in chordsBy[mi]) {
            _harmony(c, m);
          }
          _events(m, byMeasure[mi]);
          _rightBarline(m, mi + 1 < score.measures.length ? score.measures[mi + 1] : null);
        });
      }
    });
  }

  void _attributes(Measure m, Measure? prev, {required bool first}) {
    final keyChanged = first || prev!.fifths != m.fifths || prev.minor != m.minor;
    final timeChanged = first || prev!.time != m.time;
    if (!keyChanged && !timeChanged) return;
    b.element('attributes', nest: () {
      if (first) b.element('divisions', nest: '$ticksPerQuarter');
      if (keyChanged) {
        b.element('key', nest: () {
          b.element('fifths', nest: '${m.fifths}');
          b.element('mode', nest: m.minor ? 'minor' : 'major');
        });
      }
      if (timeChanged) {
        b.element('time', nest: () {
          b.element('beats', nest: '${m.time.beats}');
          b.element('beat-type', nest: '${m.time.beatType}');
        });
      }
      if (first) {
        if (part.staves > 1) b.element('staves', nest: '${part.staves}');
        for (var s = 0; s < part.staves; s++) {
          final clef = s < part.clefs.length ? part.clefs[s] : (s == 0 ? Clef.treble : Clef.bass);
          b.element('clef', attributes: {if (part.staves > 1) 'number': '${s + 1}'}, nest: () {
            b.element('sign', nest: clef.sign);
            b.element('line', nest: '${clef.line}');
            if (clef.octaveChange != 0) b.element('clef-octave-change', nest: '${clef.octaveChange}');
          });
        }
      }
    });
  }

  void _leftBarline(Measure m, Measure? prev) {
    final endingStart = m.endings.isNotEmpty && (prev == null || !_sameList(prev.endings, m.endings));
    if (!m.repeatStart && !endingStart) return;
    b.element('barline', attributes: {'location': 'left'}, nest: () {
      if (m.repeatStart) b.element('bar-style', nest: 'heavy-light');
      if (endingStart) b.element('ending', attributes: {'number': m.endings.join(', '), 'type': 'start'});
      if (m.repeatStart) b.element('repeat', attributes: {'direction': 'forward'});
    });
  }

  void _rightBarline(Measure m, Measure? next) {
    final endingStop = m.endings.isNotEmpty && (next == null || !_sameList(next.endings, m.endings));
    if (!m.repeatEnd && !endingStop) return;
    b.element('barline', attributes: {'location': 'right'}, nest: () {
      if (m.repeatEnd) b.element('bar-style', nest: 'light-heavy');
      if (endingStop) {
        b.element('ending', attributes: {'number': m.endings.join(', '), 'type': m.repeatEnd ? 'stop' : 'discontinue'});
      }
      if (m.repeatEnd) {
        b.element('repeat', attributes: {'direction': 'backward', if (m.repeatTimes != 2) 'times': '${m.repeatTimes}'});
      }
    });
  }

  void _tempo(double bpm) {
    final value = bpm == bpm.roundToDouble() ? '${bpm.round()}' : bpm.toStringAsFixed(1);
    b.element('direction', attributes: {'placement': 'above'}, nest: () {
      b.element('direction-type', nest: () {
        b.element('metronome', nest: () {
          b.element('beat-unit', nest: 'quarter');
          b.element('per-minute', nest: value);
        });
      });
      b.element('sound', attributes: {'tempo': value});
    });
  }

  static const _kinds = {
    'maj': 'major',
    'm': 'minor',
    'dim': 'diminished',
    'aug': 'augmented',
    'sus2': 'suspended-second',
    'sus4': 'suspended-fourth',
    '5': 'power',
    '6': 'major-sixth',
    'm6': 'minor-sixth',
    '7': 'dominant',
    'maj7': 'major-seventh',
    'm7': 'minor-seventh',
    'mMaj7': 'major-minor',
    'm7b5': 'half-diminished',
    'dim7': 'diminished-seventh',
    '9': 'dominant-ninth',
    'maj9': 'major-ninth',
    'm9': 'minor-ninth',
  };

  void _harmony(ChordSymbol c, Measure m) {
    final chord = c.chord;
    final spell = _defaultSpelling(chord.root, m.fifths);
    b.element('harmony', nest: () {
      b.element('root', nest: () {
        b.element('root-step', nest: _letters[spell.$1]);
        if (spell.$2 != 0) b.element('root-alter', nest: '${spell.$2}');
      });
      final id = chord.quality.id;
      final kind = _kinds[id] ?? (chord.quality.family.name == 'minor' ? 'minor' : 'major');
      b.element('kind', attributes: {'text': chord.quality.symbol}, nest: kind);
      final bass = chord.bass;
      if (bass != null) {
        final bs = _defaultSpelling(bass, m.fifths);
        b.element('bass', nest: () {
          b.element('bass-step', nest: _letters[bs.$1]);
          if (bs.$2 != 0) b.element('bass-alter', nest: '${bs.$2}');
        });
      }
      if (id == 'add9' || id == 'madd9' || id == '69') {
        b.element('degree', nest: () {
          b.element('degree-value', nest: '9');
          b.element('degree-alter', nest: '0');
          b.element('degree-type', nest: 'add');
        });
      }
      final offset = c.tick - m.tick;
      if (offset > 0) b.element('offset', nest: '$offset');
    });
  }

  /// Letra y alteración de [pc]: sostenidos en armaduras con sostenidos.
  static (int, int) _defaultSpelling(int pc, int fifths) {
    const sharps = [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (3, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1), (6, 0)];
    const flats = [(0, 0), (1, -1), (1, 0), (2, -1), (2, 0), (3, 0), (4, -1), (4, 0), (5, -1), (5, 0), (6, -1), (6, 0)];
    return (fifths >= 0 ? sharps : flats)[pc % 12];
  }

  /// Escribe las voces una tras otra, volviendo al inicio del compás con
  /// `<backup>` y rellenando huecos con `<forward>`.
  void _events(Measure m, List<ScoreEvent> events) {
    final streams = <(int, int), List<ScoreEvent>>{};
    for (final e in events) {
      (streams[(e.staff, e.voice)] ??= []).add(e);
    }
    final keys = streams.keys.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    // Alteraciones vigentes en el compás por pentagrama: (letra, octava) → alteración.
    final shown = <int, Map<(int, int), int>>{};
    for (final key in keys) {
      final list = streams[key]!..sort((a, b) => a.tick.compareTo(b.tick));
      var pos = m.tick;
      final tuplet = _TupletState();
      final beams = list.any((e) => e.beams.isNotEmpty) ? null : _autoBeams(list, m);
      for (final e in list) {
        if (e.tick > pos && !e.grace) {
          b.element('forward', nest: () {
            b.element('duration', nest: '${e.tick - pos}');
            b.element('voice', nest: '${key.$2}');
            if (part.staves > 1) b.element('staff', nest: '${key.$1}');
          });
          pos = e.tick;
        }
        _event(e, m, shown.putIfAbsent(e.staff, () => {}), tuplet, beams?[e] ?? e.beams);
        if (!e.grace) pos = e.tick + e.duration;
      }
      if (key != keys.last && pos > m.tick) {
        b.element('backup', nest: () => b.element('duration', nest: '${pos - m.tick}'));
      }
    }
  }

  void _event(ScoreEvent e, Measure m, Map<(int, int), int> shown, _TupletState tuplet, List<String> beams) {
    final written = e.type != null ? (e.type!, e.dots) : _writtenType(e);
    final tupletMark = tuplet.mark(e, written.$1);
    final notes = e.notes.isEmpty ? <ScoreNote?>[null] : e.notes;
    for (final (i, n) in notes.indexed) {
      b.element('note', attributes: {'id': n?.id ?? e.id}, nest: () {
        if (e.grace) b.element('grace');
        if (i > 0) b.element('chord');
        if (n == null) {
          b.element('rest', attributes: {if (_isWholeMeasureRest(e, m)) 'measure': 'yes'});
        } else {
          b.element('pitch', nest: () {
            b.element('step', nest: _letters[n.spelling.letter]);
            if (n.spelling.accidental != 0) b.element('alter', nest: '${n.spelling.accidental}');
            b.element('octave', nest: '${n.octave}');
          });
        }
        if (!e.grace) b.element('duration', nest: '${e.duration}');
        if (n != null && n.tieStop) b.element('tie', attributes: {'type': 'stop'});
        if (n != null && n.tieStart) b.element('tie', attributes: {'type': 'start'});
        b.element('voice', nest: '${e.voice}');
        if (!(n == null && _isWholeMeasureRest(e, m))) b.element('type', nest: written.$1.musicXml);
        for (var d = 0; d < written.$2; d++) {
          b.element('dot');
        }
        if (n != null) {
          final acc = _accidental(n, m, shown);
          if (acc != null) b.element('accidental', nest: acc);
        }
        final t = e.tuplet;
        if (t != null) {
          b.element('time-modification', nest: () {
            b.element('actual-notes', nest: '${t.$1}');
            b.element('normal-notes', nest: '${t.$2}');
          });
        }
        if (part.staves > 1) b.element('staff', nest: '${e.staff}');
        if (i == 0) {
          for (final (level, value) in beams.indexed) {
            if (value.isNotEmpty) b.element('beam', attributes: {'number': '${level + 1}'}, nest: value);
          }
        }
        final hasNotations = (n != null && (n.tieStart || n.tieStop)) || (i == 0 && tupletMark != null);
        if (hasNotations) {
          b.element('notations', nest: () {
            if (n != null && n.tieStop) b.element('tied', attributes: {'type': 'stop'});
            if (n != null && n.tieStart) b.element('tied', attributes: {'type': 'start'});
            if (i == 0 && tupletMark != null) b.element('tuplet', attributes: {'type': tupletMark});
          });
        }
      });
    }
  }

  /// Agrupa con barras las corcheas y figuras menores de una voz que no traen
  /// barras escritas: dentro de cada pulso (negra; en 6/8, 9/8 y 12/8, negra
  /// con puntillo). El segundo nivel une semicorcheas seguidas.
  static Map<ScoreEvent, List<String>> _autoBeams(List<ScoreEvent> events, Measure m) {
    final compound = m.time.beatType == 8 && m.time.beats % 3 == 0 && m.time.beats > 3;
    final beat = switch (m.time.beatType) {
      _ when compound => ticksPerQuarter * 3 ~/ 2,
      8 => math.max(m.length, ticksPerQuarter ~/ 2), // 3/8, 5/8…: el compás entero
      2 => ticksPerQuarter * 2,
      _ => ticksPerQuarter,
    };
    final out = <ScoreEvent, List<String>>{};
    final groups = <List<(ScoreEvent, NoteType)>>[];
    var current = <(ScoreEvent, NoteType)>[];
    int? currentBeat;
    for (final e in events) {
      final type = e.type ?? _writtenType(e).$1;
      final beamable = !e.isRest && !e.grace && type.quarters <= 0.5;
      final beatIndex = (e.tick - m.tick) ~/ beat;
      if (!beamable || beatIndex != currentBeat) {
        if (current.length >= 2) groups.add(current);
        current = [];
        currentBeat = beamable ? beatIndex : null;
      }
      if (beamable) current.add((e, type));
    }
    if (current.length >= 2) groups.add(current);
    for (final g in groups) {
      for (final (i, (e, _)) in g.indexed) {
        out[e] = [i == 0 ? 'begin' : (i == g.length - 1 ? 'end' : 'continue')];
      }
      // Segundo nivel: semicorcheas (o menores) seguidas.
      for (var i = 0; i < g.length; i++) {
        if (g[i].$2.quarters > 0.25) continue;
        var j = i;
        while (j + 1 < g.length && g[j + 1].$2.quarters <= 0.25) {
          j++;
        }
        if (j > i) {
          for (var k = i; k <= j; k++) {
            out[g[k].$1]!.add(k == i ? 'begin' : (k == j ? 'end' : 'continue'));
          }
        } else {
          out[g[i].$1]!.add(i == 0 ? 'forward hook' : 'backward hook');
        }
        i = j;
      }
    }
    return out;
  }

  /// Silencio de compás entero (se dibuja como redonda centrada en cualquier compás).
  static bool _isWholeMeasureRest(ScoreEvent e, Measure m) =>
      e.isRest && e.tick == m.tick && e.duration == m.length && (e.type == null || e.type == NoteType.whole);

  /// Figura que corresponde a la duración (para eventos sin figura guardada).
  static (NoteType, int) _writtenType(ScoreEvent e) {
    var ticks = e.duration;
    final t = e.tuplet;
    if (t != null) ticks = (ticks * t.$1 / t.$2).round();
    final exact = NoteType.ofTicks(ticks);
    if (exact != null) return exact;
    for (final type in NoteType.values) {
      if (type.ticks <= ticks) return (type, 0);
    }
    return (NoteType.oneTwentyEighth, 0);
  }

  /// Alteración a escribir según la armadura y lo ya escrito en el compás.
  static String? _accidental(ScoreNote n, Measure m, Map<(int, int), int> shown) {
    final slot = (n.spelling.letter, n.octave);
    final current = shown[slot] ?? _keyAccidental(n.spelling.letter, m.fifths);
    final want = n.spelling.accidental;
    shown[slot] = want;
    if (n.tieStop || current == want) return null;
    return switch (want) {
      -2 => 'flat-flat',
      -1 => 'flat',
      1 => 'sharp',
      2 => 'double-sharp',
      _ => 'natural',
    };
  }

  static int _keyAccidental(int letter, int fifths) {
    const sharpOrder = [3, 0, 4, 1, 5, 2, 6];
    const flatOrder = [6, 2, 5, 1, 4, 0, 3];
    if (fifths > 0) return sharpOrder.take(fifths).contains(letter) ? 1 : 0;
    if (fifths < 0) return flatOrder.take(-fifths).contains(letter) ? -1 : 0;
    return 0;
  }

  static bool _sameList(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Agrupa eventos consecutivos de un grupo irregular para marcar su
/// principio y su final (el corchete con el 3).
class _TupletState {
  (int, int)? _ratio;
  int _remaining = 0;

  /// 'start', 'stop', 'start' y 'stop' juntos no se dan; null si no marca nada.
  String? mark(ScoreEvent e, NoteType type) {
    final t = e.tuplet;
    if (t == null) {
      _ratio = null;
      return null;
    }
    String? out;
    if (_ratio != t || _remaining <= 0) {
      _ratio = t;
      _remaining = t.$2 * type.ticks;
      out = 'start';
    }
    _remaining -= e.duration;
    if (_remaining <= 0) {
      _ratio = null;
      return out == 'start' ? null : 'stop';
    }
    return out;
  }
}
