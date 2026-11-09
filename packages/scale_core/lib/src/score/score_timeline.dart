import 'score.dart';

/// Un compás en el orden en que se toca (con las repeticiones desplegadas).
class PlayedMeasure {
  const PlayedMeasure(this.index, this.playTick, this.pass);

  /// Índice en [Score.measures].
  final int index;

  /// Inicio en la línea de tiempo desplegada.
  final int playTick;

  /// Vuelta de la repetición (1 la primera vez).
  final int pass;
}

/// Una nota en la línea de tiempo desplegada (las ligadas ya unidas).
class PlayedNote {
  PlayedNote({
    required this.start,
    required this.end,
    required this.midi,
    required this.noteId,
    required this.eventId,
    required this.part,
    required this.staff,
    this.velocity = ScoreDynamics.defaultVelocity,
  });

  final int start;
  int end;
  final int midi;
  final String noteId;
  final String eventId;
  final int part;
  final int staff;

  /// Fuerza con que se toca (1..127): la grabada, o la de las dinámicas.
  final int velocity;

  /// Ids de todas las cabezas que forman esta nota (la primera y sus ligadas).
  final List<String> tiedIds = [];
}

/// La partitura como se toca: repeticiones y casillas desplegadas, tempo y
/// la lista de notas con su tiempo real. La usan la reproducción, el cursor
/// y el seguimiento.
class ScoreTimeline {
  ScoreTimeline._(this.score, this.order, this.notes, this._tempo, this.lengthTicks);

  factory ScoreTimeline.of(Score score, {double defaultTempo = 100}) {
    final order = unroll(score.measures);
    final tempo = <_TempoPoint>[];
    var bpm = defaultTempo;
    var micros = 0.0;
    var playTick = 0;
    for (final pm in order) {
      final m = score.measures[pm.index];
      final newBpm = m.tempo;
      if (newBpm != null && newBpm > 0) bpm = newBpm;
      if (tempo.isEmpty || tempo.last.microsPerTick != 60e6 / bpm / ticksPerQuarter) {
        micros = tempo.isEmpty ? 0 : tempo.last.microsAt(pm.playTick);
        tempo.add(_TempoPoint(pm.playTick, micros, 60e6 / bpm / ticksPerQuarter));
      }
      playTick = pm.playTick + m.length;
    }
    if (tempo.isEmpty) tempo.add(_TempoPoint(0, 0, 60e6 / defaultTempo / ticksPerQuarter));

    final notes = <PlayedNote>[];
    for (final (pi, part) in score.parts.indexed) {
      // Notas abiertas que esperan su continuación ligada, por altura.
      final open = <int, PlayedNote>{};
      final byMeasure = _eventsByMeasure(score, part);
      final dynamics = ScoreDynamics(part.directions);
      for (final pm in order) {
        final m = score.measures[pm.index];
        for (final e in byMeasure[pm.index]) {
          if (e.isRest) continue;
          final offset = pm.playTick + e.tick - m.tick;
          final start = e.grace ? (offset - ticksPerQuarter ~/ 8).clamp(0, offset) : offset;
          final end = e.grace ? offset : offset + e.duration;
          for (final n in e.notes) {
            final prev = open[n.midi];
            if (n.tieStop && prev != null && (prev.end - start).abs() <= ticksPerQuarter ~/ 8) {
              prev.end = end;
              prev.tiedIds.add(n.id);
              if (!n.tieStart) open.remove(n.midi);
              continue;
            }
            final played = PlayedNote(
              start: start,
              end: end,
              midi: n.midi,
              noteId: n.id,
              eventId: e.id,
              part: pi,
              staff: e.staff,
              velocity: n.velocity ?? dynamics.velocityAt(e.tick),
            )..tiedIds.add(n.id);
            notes.add(played);
            if (n.tieStart) {
              open[n.midi] = played;
            } else {
              open.remove(n.midi);
            }
          }
        }
      }
    }
    notes.sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.midi.compareTo(b.midi));
    return ScoreTimeline._(score, order, notes, tempo, playTick);
  }

  final Score score;
  final List<PlayedMeasure> order;
  final List<PlayedNote> notes;
  final List<_TempoPoint> _tempo;

  /// Duración total desplegada, en pulsos.
  final int lengthTicks;

  Duration get duration => Duration(microseconds: microsAt(lengthTicks).round());

  /// Microsegundos (a tempo original) en el pulso desplegado [tick].
  double microsAt(int tick) => _tempoAt(tick).microsAt(tick);

  /// Pulso desplegado en el instante [micros] (a tempo original).
  int tickAtMicros(double micros) {
    var point = _tempo.first;
    for (final p in _tempo) {
      if (p.micros > micros) break;
      point = p;
    }
    return point.tick + ((micros - point.micros) / point.microsPerTick + 1e-6).floor();
  }

  /// Negras por minuto vigentes en [tick].
  double bpmAt(int tick) => 60e6 / _tempoAt(tick).microsPerTick / ticksPerQuarter;

  _TempoPoint _tempoAt(int tick) {
    var point = _tempo.first;
    for (final p in _tempo) {
      if (p.tick > tick) break;
      point = p;
    }
    return point;
  }

  /// Compás desplegado que contiene [tick].
  int playedMeasureAt(int tick) {
    var lo = 0;
    var hi = order.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (order[mid].playTick <= tick) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Primer pulso desplegado en que se toca el evento o la nota [id]
  /// (para empezar desde ahí), o null.
  int? firstTickOf(String id) {
    for (final n in notes) {
      if (n.eventId == id || n.tiedIds.contains(id)) return n.start;
    }
    return null;
  }

  /// Despliega repeticiones y casillas de 1ª/2ª vez.
  static List<PlayedMeasure> unroll(List<Measure> measures) {
    final out = <PlayedMeasure>[];
    final jumps = <int, int>{};
    var start = 0;
    var pass = 1;
    var playTick = 0;
    var i = 0;
    var prevHadEndings = false;
    final limit = measures.length * 8;
    while (i < measures.length && out.length < limit) {
      final m = measures[i];
      if (m.repeatStart && i != start) {
        start = i;
        pass = 1;
      }
      if (m.endings.isNotEmpty && !m.endings.contains(pass)) {
        i++;
        continue;
      }
      if (m.endings.isEmpty && prevHadEndings && !m.repeatStart) {
        // Se salió de las casillas: la próxima repetición empieza aquí.
        start = i;
        pass = 1;
      }
      prevHadEndings = m.endings.isNotEmpty;
      out.add(PlayedMeasure(i, playTick, pass));
      playTick += m.length;
      if (m.repeatEnd) {
        final taken = jumps[i] ?? 0;
        if (taken < m.repeatTimes - 1) {
          jumps[i] = taken + 1;
          pass++;
          i = start;
          prevHadEndings = false;
          continue;
        }
        if (m.endings.isEmpty) {
          start = i + 1;
          pass = 1;
        }
      }
      i++;
    }
    return out;
  }

  static List<List<ScoreEvent>> _eventsByMeasure(Score score, ScorePart part) {
    final out = [for (final _ in score.measures) <ScoreEvent>[]];
    for (final e in part.events) {
      out[score.measureAt(e.tick)].add(e);
    }
    return out;
  }
}

class _TempoPoint {
  _TempoPoint(this.tick, this.micros, this.microsPerTick);

  final int tick;
  final double micros;
  final double microsPerTick;

  double microsAt(int t) => micros + (t - tick) * microsPerTick;
}

/// Fuerza de cada nota según las dinámicas escritas de una parte: el nivel
/// de la última marca (p, mf, f…), los acentos (sfz) en su nota y los
/// reguladores, que pasan poco a poco de un nivel al siguiente.
class ScoreDynamics {
  ScoreDynamics(List<ScoreDirection> directions) {
    final sorted = [...directions]..sort((a, b) => a.tick.compareTo(b.tick));
    int? wedgeStart;
    String? wedgeKind;
    for (final d in sorted) {
      if (d.kind == DirectionKind.dynamic) {
        final v = ScoreDirection.velocities[d.value];
        if (v == null) continue;
        if (ScoreDirection.accents.contains(d.value)) {
          _accents[d.tick] = v;
        } else {
          _levels.add((d.tick, v));
        }
      } else if (d.value == 'stop') {
        if (wedgeStart != null && d.tick > wedgeStart) _wedges.add((wedgeStart, d.tick, wedgeKind == 'crescendo'));
        wedgeStart = null;
      } else {
        wedgeStart = d.tick;
        wedgeKind = d.value;
      }
    }
  }

  /// Sin dinámicas escritas: mezzoforte.
  static const int defaultVelocity = 80;

  final List<(int, int)> _levels = [];
  final Map<int, int> _accents = {};
  final List<(int, int, bool)> _wedges = [];

  int _levelAt(int tick) {
    var v = defaultVelocity;
    for (final (t, level) in _levels) {
      if (t > tick) break;
      v = level;
    }
    return v;
  }

  int velocityAt(int tick) {
    final accent = _accents[tick];
    if (accent != null) return accent;
    for (final (start, stop, crescendo) in _wedges) {
      if (tick < start || tick >= stop) continue;
      final from = _levelAt(start);
      // Destino: la marca que llega al terminar el regulador, o un escalón.
      int? to;
      for (final (t, level) in _levels) {
        if (t > stop + ticksPerQuarter * 4) break;
        if (t >= stop) {
          to = level;
          break;
        }
      }
      to ??= (from + (crescendo ? 24 : -24)).clamp(16, 120);
      final f = (tick - start) / (stop - start);
      return (from + (to - from) * f).round().clamp(1, 127);
    }
    return _levelAt(tick);
  }
}
