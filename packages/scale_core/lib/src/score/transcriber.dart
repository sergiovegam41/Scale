import 'dart:math' as math;
import 'dart:typed_data';

import '../analysis/chord_recognizer.dart';
import '../analysis/key_estimator.dart';
import '../analysis/live_analyzer.dart';
import '../analysis/song_analyzer.dart';
import '../model/song.dart';
import '../notation/chord_staff.dart';
import '../theory/chord.dart';
import '../theory/key.dart';
import '../theory/pitch.dart';
import 'score.dart';

/// Pulso del compás: la negra en x/4, la blanca en x/2, la negra con
/// puntillo en 6/8, 9/8 y 12/8, la corchea en 3/8 y 5/8.
double pulseQuarters(TimeSignature t) {
  if (t.beatType == 8 && t.beats % 3 == 0 && t.beats > 3) return 1.5;
  return 4 / t.beatType;
}

/// Pulsos por compás (6/8 → 2, 3/4 → 3).
int pulsesPerMeasure(TimeSignature t) => t.beatType == 8 && t.beats % 3 == 0 && t.beats > 3 ? t.beats ~/ 3 : t.beats;

/// De dónde sale el pulso al escribir una toma.
enum TempoMode {
  /// Del metrónomo si se le siguió; si no, del tempo de quien toca.
  auto,

  /// Siempre del metrónomo.
  metronome,

  /// Siempre del tempo de quien toca (aunque acelere o frene).
  player,
}

/// Cómo se convierte una toma en partitura. Se guarda con la partitura para
/// poder volver a escribirla con otros ajustes sin volver a tocar.
class TranscriptionSettings {
  const TranscriptionSettings({
    required this.bpm,
    required this.time,
    required this.startMicros,
    this.grid = 4,
    this.triplets = true,
    this.autoLatency = true,
    this.latencyMicros = 0,
    this.keyIndex,
    this.chordSymbols = true,
    this.dynamics = true,
    this.tempoMode = TempoMode.auto,
    this.meter,
  });

  factory TranscriptionSettings.fromJson(Map<String, dynamic> j) => TranscriptionSettings(
    bpm: (j['bpm'] as num).toDouble(),
    time: TimeSignature.fromJson(j['time'] as List<dynamic>),
    startMicros: j['start'] as int,
    grid: j['grid'] as int? ?? 4,
    triplets: j['triplets'] as bool? ?? true,
    autoLatency: j['autoLatency'] as bool? ?? true,
    latencyMicros: j['latency'] as int? ?? 0,
    keyIndex: j['key'] as int?,
    chordSymbols: j['chords'] as bool? ?? true,
    dynamics: j['dyn'] as bool? ?? true,
    tempoMode: TempoMode.values.asNameMap()[j['tempoMode']] ?? TempoMode.auto,
    meter: j['meter'] == null ? null : TimeSignature.fromJson(j['meter'] as List<dynamic>),
  );

  /// Pulsos por minuto del metrónomo (ver [pulseQuarters]).
  final double bpm;

  /// Compás del metrónomo.
  final TimeSignature time;

  /// Instante de la toma en que empezó el primer compás (tras la cuenta).
  final int startMicros;

  /// Divisiones de la negra: 2 = corcheas, 4 = semicorcheas.
  final int grid;

  /// Detectar tresillos de corchea cuando encajan claramente mejor.
  final bool triplets;

  /// Corregir el adelanto o retraso habitual de quien toca respecto al
  /// metrónomo (se mide en la propia toma).
  final bool autoLatency;

  /// Corrección manual, sumada a la automática.
  final int latencyMicros;

  /// Tonalidad fijada (índice de [MusicKey.fromIndex]); null: se estima.
  final int? keyIndex;

  /// Escribir los acordes detectados como cifrado.
  final bool chordSymbols;

  /// Escribir p, mf, f… según la fuerza con que se tocó.
  final bool dynamics;

  final TempoMode tempoMode;

  /// Compás con que se escribe; null: se deduce de lo tocado (prefiriendo
  /// el del metrónomo).
  final TimeSignature? meter;

  double get quarterBpm => bpm * pulseQuarters(time);
  double get quarterMicros => 60e6 / quarterBpm;

  TranscriptionSettings copyWith({
    double? bpm,
    int? grid,
    bool? triplets,
    bool? autoLatency,
    int? latencyMicros,
    int? keyIndex,
    bool clearKey = false,
    bool? chordSymbols,
    bool? dynamics,
    TempoMode? tempoMode,
    TimeSignature? meter,
    bool clearMeter = false,
  }) => TranscriptionSettings(
    bpm: bpm ?? this.bpm,
    time: time,
    startMicros: startMicros,
    grid: grid ?? this.grid,
    triplets: triplets ?? this.triplets,
    autoLatency: autoLatency ?? this.autoLatency,
    latencyMicros: latencyMicros ?? this.latencyMicros,
    keyIndex: clearKey ? null : (keyIndex ?? this.keyIndex),
    chordSymbols: chordSymbols ?? this.chordSymbols,
    dynamics: dynamics ?? this.dynamics,
    tempoMode: tempoMode ?? this.tempoMode,
    meter: clearMeter ? null : (meter ?? this.meter),
  );

  Map<String, dynamic> toJson() => {
    'bpm': bpm,
    'time': time.toJson(),
    'start': startMicros,
    'grid': grid,
    'triplets': triplets,
    'autoLatency': autoLatency,
    if (latencyMicros != 0) 'latency': latencyMicros,
    if (keyIndex != null) 'key': keyIndex,
    'chords': chordSymbols,
    'dyn': dynamics,
    if (tempoMode != TempoMode.auto) 'tempoMode': tempoMode.name,
    if (meter != null) 'meter': meter!.toJson(),
  };
}

/// La interpretación original de una partitura grabada: la toma en bruto y
/// cómo se escribió.
class ScoreRecording {
  ScoreRecording({
    required this.take,
    required this.settings,
    this.appliedLatencyMicros = 0,
    this.beats = const [],
    this.beatTicks = ticksPerQuarter,
    this.followedMetronome = true,
  });

  factory ScoreRecording.fromJson(Map<String, dynamic> j) => ScoreRecording(
    take: Take.fromJson(j['take'] as Map<String, dynamic>),
    settings: TranscriptionSettings.fromJson(j['settings'] as Map<String, dynamic>),
    appliedLatencyMicros: j['appliedLatency'] as int? ?? 0,
    beats: [for (final b in (j['beats'] as List<dynamic>? ?? const [])) b as int],
    beatTicks: j['beatTicks'] as int? ?? ticksPerQuarter,
    followedMetronome: j['followed'] as bool? ?? true,
  );

  final Take take;
  TranscriptionSettings settings;

  /// Corrección total usada al escribirla (automática + manual).
  int appliedLatencyMicros;

  /// Instante de la toma de cada pulso escrito: el pulso i está en el
  /// tick i × [beatTicks] de la partitura. Vacío en partituras antiguas.
  List<int> beats;
  int beatTicks;

  /// Si se escribió sobre el pulso del metrónomo (o sobre el de quien tocó).
  bool followedMetronome;

  /// Tempo medio de quien tocó, en negras por minuto.
  double? get playedQuarterBpm {
    if (beats.length < 2) return null;
    final per = [for (var i = 0; i + 1 < beats.length; i++) beats[i + 1] - beats[i]]..sort();
    return 60e6 / per[per.length ~/ 2] * beatTicks / ticksPerQuarter;
  }

  /// Pulso de la partitura (desplegada = lineal: no hay repeticiones) en el
  /// instante [micros] de la toma, para mover el cursor al reproducirla tal
  /// como se tocó. [pickupTicks]: lo que dura la anacrusa (solo en
  /// partituras antiguas, sin [beats]).
  double tickAt(int micros, int pickupTicks) {
    if (beats.length < 2) {
      return (micros - settings.startMicros - appliedLatencyMicros) / settings.quarterMicros * ticksPerQuarter +
          pickupTicks;
    }
    var lo = 0;
    var hi = beats.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (beats[mid] <= micros) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + (micros - beats[lo]) / (beats[lo + 1] - beats[lo])) * beatTicks;
  }

  /// Lo contrario de [tickAt]: el instante de la toma de un pulso escrito.
  double microsAt(int tick, int pickupTicks) {
    if (beats.length < 2) {
      return (tick - pickupTicks) / ticksPerQuarter * settings.quarterMicros +
          settings.startMicros +
          appliedLatencyMicros;
    }
    final pos = tick / beatTicks;
    final i = pos.floor().clamp(0, beats.length - 2);
    return beats[i] + (pos - i) * (beats[i + 1] - beats[i]);
  }

  Map<String, dynamic> toJson() => {
    'take': take.toJson(),
    'settings': settings.toJson(),
    if (appliedLatencyMicros != 0) 'appliedLatency': appliedLatencyMicros,
    if (beats.isNotEmpty) 'beats': beats,
    if (beatTicks != ticksPerQuarter) 'beatTicks': beatTicks,
    if (!followedMetronome) 'followed': false,
  };
}

class _RawNote {
  _RawNote(this.on, this.off, this.midi, this.velocity);

  final int on;
  int off;
  final int midi;
  final int velocity;

  int tick = 0;
  int endTick = 0;
  int staff = 1;
}

/// Un ataque: las notas que empiezan juntas (un acorde) y su peso para
/// encontrar el pulso.
class _Onset {
  _Onset(this.time);

  double time;
  final List<_RawNote> notes = [];
  double salience = 1;
  int tick = 0;
}

class _Group {
  _Group(this.tick);

  final int tick;
  final List<_RawNote> notes = [];
}

/// Los pulsos de una toma: el instante de cada uno (de antes del primer
/// ataque a después del último). Fuera de la lista se prolongan al mismo
/// ritmo.
class _Beats {
  _Beats(this.t);

  /// Pulsos regulares desde [origin] cada [period], cubriendo [from, to].
  /// Devuelve también la posición de [origin] en la lista.
  static (_Beats, int) regular(double origin, double period, double from, double to) {
    final k0 = ((from - origin) / period).floor() - 1;
    final k1 = ((to - origin) / period).ceil() + 1;
    return (_Beats([for (var k = k0; k <= k1; k++) origin + k * period]), -k0);
  }

  final List<double> t;

  double period(int j) {
    final i = j.clamp(0, t.length - 2);
    return t[i + 1] - t[i];
  }

  /// Posición (pulso y fracción) del instante [x].
  double pos(double x) {
    if (x <= t.first) return (x - t.first) / (t[1] - t[0]);
    if (x >= t.last) return t.length - 1 + (x - t.last) / (t.last - t[t.length - 2]);
    var lo = 0;
    var hi = t.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (t[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo + (x - t[lo]) / (t[lo + 1] - t[lo]);
  }

  double medianPeriod(int from, int to) {
    final p = [for (var j = math.max(0, from); j < math.min(to, t.length - 1); j++) t[j + 1] - t[j]]..sort();
    return p.isEmpty ? period(from) : p[p.length ~/ 2];
  }
}

/// Cómo quedó cada ataque en la rejilla: pulso, posición dentro de él y
/// en cuántas partes se dividió ese pulso.
class _Quant {
  _Quant(this.at, this.subs, this.error, this.cost);

  final List<(int, int, int)> at;
  final Map<int, int> subs;

  /// Desvío total de los ataques respecto a la rejilla (normalizado).
  final double error;

  /// Desvío más lo complicado de las figuras.
  final double cost;
}

/// Convierte una interpretación grabada en partitura de piano (dos
/// pentagramas, una voz por mano).
///
/// Pasos: notas con su inicio y final (el pedal alarga hasta soltarlo);
/// el pulso: el del metrónomo si se le siguió o, si no, el de quien toca
/// (que puede acelerar o frenar); en cada pulso, la división más sencilla
/// que explica lo tocado (negras, corcheas, semicorcheas o tresillos);
/// compás y primera parte fuerte; reparto entre manos; duraciones hasta la
/// siguiente nota de la misma mano (un hueco corto es legato, no silencio);
/// ligaduras; ortografía según la tonalidad; fuerza de cada nota, dinámicas
/// y cifrado.
class PerformanceTranscriber {
  PerformanceTranscriber._(this.take, this.settings);

  /// Escribe [take] como partitura. Devuelve null si no hay notas.
  static Score? transcribe(Take take, TranscriptionSettings settings, {required String id, required String title}) =>
      PerformanceTranscriber._(take, settings)._run(id, title);

  final Take take;
  final TranscriptionSettings settings;
  int _ids = 0;

  /// El compás del pulso que se sigue: el fijado o el del metrónomo (los
  /// compases que se prueban comparten pulso con él).
  TimeSignature get _baseTime => settings.meter ?? settings.time;
  double get _pulseQ => pulseQuarters(_baseTime);
  int get _pt => (_pulseQ * ticksPerQuarter).round();

  /// Pulsos escritos en tresillo (índice de pulso desde el principio).
  Set<int> _tripletBeats = {};

  Score? _run(String id, String title) {
    final notes = _notes();
    if (notes.isEmpty) return null;
    final onsets = _onsets(notes);
    final firstOn = notes.first.on.toDouble();
    final lastOff = math.max(notes.map((n) => n.off).reduce(math.max), take.durationMicros).toDouble();

    // El pulso del metrónomo (corrigiendo el adelanto habitual).
    final metroPeriod = settings.quarterMicros * _pulseQ;
    final latency = (settings.autoLatency ? _estimateLatency(notes) : 0) + settings.latencyMicros;
    final (metro, metroDown) = _Beats.regular(
      (settings.startMicros + latency).toDouble(),
      metroPeriod,
      math.min(firstOn, 0),
      lastOff + metroPeriod,
    );
    var beats = metro;
    var q = _quantize(onsets, metro);
    var followed = true;

    // ¿Se siguió el metrónomo? Si no, el pulso de quien toca.
    if (settings.tempoMode != TempoMode.metronome && onsets.length >= 8) {
      final tracked = _track(onsets, metroPeriod, firstOn, lastOff);
      if (tracked != null) {
        final tq = _quantize(onsets, tracked);
        final ratio = tracked.medianPeriod(0, tracked.t.length) / metroPeriod;
        // Siguiendo el metrónomo, el desvío medio es pequeño (≈0,1); sin
        // seguirlo pasa de 0,5 y el pulso propio lo explica mucho mejor.
        final poorFit = q.error / onsets.length > 0.35 && tq.error < q.error * 0.75;
        final otherTempo = (ratio - 1).abs() > 0.06 && tq.cost < q.cost;
        if (settings.tempoMode == TempoMode.player || poorFit || otherTempo) {
          beats = tracked;
          q = tq;
          followed = false;
        }
      }
    }

    // Cada ataque en su sitio de la rejilla (en pulsos de la lista).
    final pt = _pt;
    for (final (i, o) in onsets.indexed) {
      final (j, k, sub) = q.at[i];
      o.tick = j * pt + k * (pt ~/ sub);
      for (final n in o.notes) {
        n.tick = o.tick;
        n.endTick = math.max(o.tick + pt ~/ sub, _endTick(n.off.toDouble(), beats, q.subs));
      }
    }
    final triplets = {
      for (final e in q.subs.entries)
        if (e.value == 3 && _pulseQ == 1) e.key,
    };

    // Compás y primera parte fuerte.
    final jFirst = _floorDiv(onsets.first.tick, pt);
    final (time, phase) = _meter(onsets, jFirst, followed ? metroDown : null);
    final b = pulsesPerMeasure(time);
    final metroPhase = followed && b == pulsesPerMeasure(settings.time) && phase == metroDown % b;
    int origin;
    var pickupBeats = 0;
    if (metroPhase && jFirst >= metroDown) {
      // Se empezó en el compás 1 o después: compases enteros (con silencio
      // al principio si se entró tarde).
      origin = jFirst - (jFirst - phase) % b;
    } else {
      origin = jFirst;
      pickupBeats = (phase - jFirst) % b;
    }
    for (final n in notes) {
      n.tick -= origin * pt;
      n.endTick -= origin * pt;
    }
    _tripletBeats = {for (final j in triplets) j - origin};
    final pickup = pickupBeats * pt;

    final groups = _groups(notes);
    _assignHands(groups);

    final key = settings.keyIndex != null ? MusicKey.fromIndex(settings.keyIndex!) : _estimateKey();
    final fifths = key == null ? 0 : KeySignature.of(key).fifths;

    // Compases: la anacrusa (si la hay) y compases enteros hasta la última nota.
    final lastEnd = _streamEnds(groups);
    final measures = <Measure>[];
    var tick = 0;
    var number = 1;
    if (pickup > 0) {
      measures.add(Measure(number: '0', tick: 0, length: pickup, time: time, fifths: fifths, implicit: true));
      tick = pickup;
    }
    do {
      measures.add(Measure(number: '${number++}', tick: tick, length: time.measureTicks, time: time, fifths: fifths));
      tick += time.measureTicks;
    } while (tick < lastEnd);
    final lastBeat = _floorDiv(onsets.last.tick, pt);
    final quarterBpm = followed
        ? settings.quarterBpm
        : () {
            final played = 60e6 / beats.medianPeriod(origin, lastBeat + 1) * _pulseQ;
            // Casi el del metrónomo: se escribe el del metrónomo.
            return (played / settings.quarterBpm - 1).abs() < 0.04 ? settings.quarterBpm : played.roundToDouble();
          }();
    measures.first.tempo = double.parse(quarterBpm.toStringAsFixed(1));
    if (key != null) {
      for (final m in measures) {
        m.minor = !key.isMajor;
      }
    }

    final score = Score(
      id: id,
      title: title,
      source: ScoreSource(kind: 'recording'),
      measures: measures,
      parts: [ScorePart(id: 'P1', name: 'Piano', staves: 2, program: 0)],
    );
    final part = score.parts.single;
    for (final staff in [1, 2]) {
      part.events.addAll(
        _staffEvents(
          score,
          [
            for (final g in groups)
              if (g.notes.any((n) => n.staff == staff)) g,
          ],
          staff,
          key,
        ),
      );
    }
    part.events.sort((a, b) => a.tick != b.tick ? a.tick.compareTo(b.tick) : a.staff.compareTo(b.staff));
    if (settings.dynamics) part.directions.addAll(_dynamics(score, notes));
    if (settings.chordSymbols) part.chords.addAll(_chordSymbols(score, notes, key));
    score.recording = ScoreRecording(
      take: take,
      settings: settings,
      appliedLatencyMicros: followed ? latency : 0,
      beats: [for (var j = math.max(0, origin); j < beats.t.length; j++) beats.t[j].round()],
      beatTicks: pt,
      followedMetronome: followed,
    );
    return score;
  }

  static int _floorDiv(int a, int b) => (a / b).floor();

  /// Notas de la toma con inicio y final; el pedal de resonancia alarga las
  /// que se sueltan con él pisado. Se ignora el canal de percusión (el
  /// metrónomo) y los roces de menos de 25 ms.
  List<_RawNote> _notes() {
    final out = <_RawNote>[];
    final open = <int, _RawNote>{};
    final pedalHeld = <_RawNote>[];
    var pedal = false;
    final shift = -take.inputTranspose;
    for (final e in take.events) {
      if (e.channel == 9) continue;
      if (e.isSustain) {
        pedal = e.sustainDown;
        if (!pedal) {
          for (final n in pedalHeld) {
            n.off = e.timeMicros;
          }
          pedalHeld.clear();
        }
        continue;
      }
      if (!e.isNote) continue;
      final midi = (e.data1 + shift).clamp(0, 127);
      if (e.isNoteOn) {
        final prev = open.remove(midi);
        if (prev != null) {
          prev.off = e.timeMicros;
          pedalHeld.remove(prev);
        }
        final n = _RawNote(e.timeMicros, take.durationMicros, midi, e.data2);
        open[midi] = n;
        out.add(n);
      } else if (e.isNoteOff) {
        final n = open.remove(midi);
        if (n == null) continue;
        n.off = e.timeMicros;
        if (pedal) pedalHeld.add(n);
      }
    }
    // Una nota vuelta a tocar con el pedal pisado corta la anterior.
    out.sort((a, b) => a.on.compareTo(b.on));
    for (var i = 0; i < out.length; i++) {
      for (var j = i + 1; j < out.length && out[j].on < out[i].off; j++) {
        if (out[j].midi == out[i].midi) {
          out[i].off = out[j].on;
          break;
        }
      }
    }
    // Roces: una tecla vecina tocada sin querer junto a otra (muy corta,
    // más suave y casi a la vez) no es una nota.
    bool smudge(_RawNote n) {
      if (n.off - n.on > 110000) return false;
      for (final m in out) {
        if (identical(m, n) || (m.on - n.on).abs() > 50000) continue;
        final d = (m.midi - n.midi).abs();
        if (d >= 1 && d <= 2 && m.velocity >= n.velocity && m.off - m.on > n.off - n.on) return true;
      }
      return false;
    }

    return [
      for (final n in out)
        if (n.off - n.on >= 25000 && !smudge(n)) n,
    ];
  }

  /// Junta las notas que empiezan a la vez (menos de 35 ms) en un ataque.
  List<_Onset> _onsets(List<_RawNote> notes) {
    final out = <_Onset>[];
    for (final n in notes) {
      if (out.isEmpty || !_sameAttack(out.last, n)) out.add(_Onset(n.on.toDouble()));
      out.last.notes.add(n);
    }
    for (final o in out) {
      // Un acorde arpegiado cuenta en el medio de su arpegio.
      final ons = [for (final n in o.notes) n.on]..sort();
      o.time = ons[ons.length ~/ 2].toDouble();
      final loud = o.notes.map((n) => n.velocity).reduce(math.max);
      final low = o.notes.map((n) => n.midi).reduce(math.min);
      o.salience = 0.6 + 0.4 * math.min(1, loud / 100) + 0.25 * math.min(3, o.notes.length - 1) + (low < 55 ? 0.5 : 0);
    }
    return out;
  }

  /// Si [n] es parte del mismo ataque que [o]: casi a la vez (35 ms) o un
  /// acorde arpegiado (notas seguidas a menos de 120 ms, todas aún pulsadas
  /// cuando entra la nueva).
  static bool _sameAttack(_Onset o, _RawNote n) {
    final first = o.notes.first.on;
    if (n.on - first <= 35000) return true;
    final last = o.notes.last.on;
    if (n.on - last > 120000 || n.on - first > 250000) return false;
    if (n.off - n.on < 150000) return false;
    for (final m in o.notes) {
      if (m.midi == n.midi || m.off < n.on + 100000) return false;
    }
    return true;
  }

  /// Adelanto (negativo) o retraso típico respecto al metrónomo: la mediana
  /// de cuánto se separan los ataques de la corchea más cercana, contando
  /// solo los que caen cerca de una.
  int _estimateLatency(List<_RawNote> notes) {
    final qm = settings.quarterMicros;
    final half = qm / 2;
    final deviations = <double>[];
    var lastOn = -1 << 40;
    for (final n in notes) {
      if (n.on - lastOn < 40000) continue; // un ataque por acorde
      lastOn = n.on;
      final rel = n.on - settings.startMicros;
      final d = rel - (rel / half).round() * half;
      if (d.abs() < qm / 8) deviations.add(d);
    }
    if (deviations.length < 8) return 0;
    deviations.sort();
    return deviations[deviations.length ~/ 2].round().clamp(-60000, 60000);
  }

  /// En cuántas partes puede dividirse un pulso y lo que "cuesta" leerlo:
  /// negras y corcheas son lo normal; semicorcheas y tresillos solo si lo
  /// tocado lo pide claramente.
  List<(int, double)> get _subdivisions {
    final semis = settings.grid >= 4;
    return switch (_pulseQ) {
      1 => [(1, 0), (2, 1.5), if (semis) (4, 3), if (settings.triplets) (3, 4.5), if (semis) (8, 6)],
      1.5 => [(1, 0), (3, 1.5), if (semis) (6, 3)],
      2 => [(1, 0), (2, 0), (4, 1.5), if (semis) (8, 3)],
      0.5 => [(1, 0), if (semis) (2, 3)],
      _ => [(1, 0), (2, 1.5)],
    };
  }

  /// División de un pulso sin ataques (para los finales de nota).
  int get _defaultSub => switch (_pulseQ) {
    1.5 => 3,
    0.5 => 1,
    _ => 2,
  };

  /// Cada ataque a la división más sencilla de su pulso que lo explica.
  _Quant _quantize(List<_Onset> onsets, _Beats beats) {
    final byBeat = <int, List<(int, double)>>{};
    for (final (i, o) in onsets.indexed) {
      final p = beats.pos(o.time);
      final j = p.floor();
      (byBeat[j] ??= []).add((i, p - j));
    }
    final at = List<(int, int, int)>.filled(onsets.length, (0, 0, 1));
    final subs = <int, int>{};
    var error = 0.0;
    var cost = 0.0;
    for (final MapEntry(key: j, value: list) in byBeat.entries) {
      final period = beats.period(j);
      final sigma = 0.045 * period + 15000;
      var best = double.infinity;
      var bestErr = 0.0;
      var bestSub = 1;
      for (final (sub, complexity) in _subdivisions) {
        var err = 0.0;
        var c = complexity;
        final used = <int>{};
        for (final (_, f) in list) {
          final k = (f * sub).round();
          final d = (f - k / sub) * period / sigma;
          err += d * d;
          if (!used.add(k)) c += 6; // dos ataques distintos en el mismo sitio
        }
        if (err + c < best) {
          best = err + c;
          bestErr = err;
          bestSub = sub;
        }
      }
      subs[j] = bestSub;
      error += bestErr;
      cost += best;
      for (final (i, f) in list) {
        at[i] = (j, (f * bestSub).round(), bestSub);
      }
    }
    return _Quant(at, subs, error, cost);
  }

  /// Final de una nota en la rejilla del pulso donde cae.
  int _endTick(double micros, _Beats beats, Map<int, int> subs) {
    final p = beats.pos(micros);
    final j = p.floor();
    var sub = subs[j] ?? _defaultSub;
    if (sub == 1) sub = _defaultSub;
    return j * _pt + ((p - j) * sub).round() * (_pt ~/ sub);
  }

  /// El pulso de quien toca: primero el tempo (los intervalos entre
  /// ataques que mejor encajan en pulsos y sus divisiones, prefiriendo el
  /// del metrónomo), luego cada pulso siguiendo sus aceleraciones y
  /// frenadas (programación dinámica sobre los ataques, como en el
  /// seguimiento de pulso de Ellis).
  _Beats? _track(List<_Onset> onsets, double priorPeriod, double first, double last) {
    // 1. Tempo: el de toda la toma y, por tramos, cómo va cambiando.
    final period = _bestPeriod(onsets, 0, onsets.length, priorPeriod, 0.5, 60e6 / 260, 60e6 / 30);
    if (period == 0) return null;

    // 2. Pulsos. Fuerza de cada instante (cada 10 ms): los ataques, más
    // pesados si son acordes, graves o largos.
    const frame = 10000.0;
    final t0 = onsets.first.time - 1.5 * period;
    final n = ((onsets.last.time + 0.5 * period - t0) / frame).ceil() + 1;
    final env = Float64List(n);
    for (final (i, o) in onsets.indexed) {
      final ioi = i + 1 < onsets.length ? onsets[i + 1].time - o.time : period;
      final w = o.salience * (1 + 0.6 * math.min(1.5, ioi / period));
      final c = (o.time - t0) / frame;
      for (var f = (c - 8).floor(); f <= (c + 8).ceil(); f++) {
        if (f < 0 || f >= n) continue;
        final d = (f - c) * frame / 25000;
        env[f] += w * math.exp(-d * d / 2);
      }
    }
    final local = _localPeriods(onsets, period);
    const alpha = 60.0;
    final score = Float64List(n);
    final prev = Int32List(n)..fillRange(0, n, -1);
    var li = 0;
    for (var f = 0; f < n; f++) {
      // Pulso esperado aquí (interpolando entre tramos).
      final t = t0 + f * frame;
      while (li + 1 < local.length && local[li + 1].$1 <= t) {
        li++;
      }
      final (ta, pa) = local[li];
      final pHere = li + 1 < local.length && t > ta
          ? pa + (local[li + 1].$2 - pa) * (t - ta) / (local[li + 1].$1 - ta)
          : pa;
      final pf = pHere / frame;
      final lo = (0.7 * pf).floor();
      final hi = (1.4 * pf).ceil();
      var bestPrev = 0.0;
      var arg = -1;
      for (var lag = lo; lag <= hi; lag++) {
        final g = f - lag;
        if (g < 0) break;
        final l = math.log(lag / pf);
        final v = score[g] - alpha * l * l;
        if (v > bestPrev) {
          bestPrev = v;
          arg = g;
        }
      }
      score[f] = env[f] + bestPrev;
      prev[f] = arg;
    }
    var end = -1;
    final from = ((onsets.last.time - 0.6 * period - t0) / frame).floor().clamp(0, n - 1);
    for (var f = from; f < n; f++) {
      if (end < 0 || score[f] > score[end]) end = f;
    }
    final frames = <int>[];
    for (var f = end; f >= 0; f = prev[f]) {
      frames.add(f);
    }
    if (frames.length < 3) return null;
    final times = [for (final f in frames.reversed) t0 + f * frame];

    // Cada pulso, exactamente sobre el ataque que tenga muy cerca.
    var k = 0;
    for (var i = 0; i < times.length; i++) {
      while (k < onsets.length && onsets[k].time < times[i] - 0.08 * period) {
        k++;
      }
      var nearest = -1;
      for (var m = k; m < onsets.length && onsets[m].time <= times[i] + 0.08 * period; m++) {
        if (nearest < 0 || (onsets[m].time - times[i]).abs() < (onsets[nearest].time - times[i]).abs()) nearest = m;
      }
      if (nearest >= 0) times[i] = onsets[nearest].time;
    }
    // Se prolongan hacia atrás y hacia delante al ritmo de los extremos.
    double edge(Iterable<double> d) {
      final l = d.toList()..sort();
      return l[l.length ~/ 2];
    }

    final head = edge([for (var i = 0; i < math.min(4, times.length - 1); i++) times[i + 1] - times[i]]);
    while (times.first > first - 0.5 * head) {
      times.insert(0, times.first - head);
    }
    final tail = edge([for (var i = math.max(0, times.length - 5); i < times.length - 1; i++) times[i + 1] - times[i]]);
    while (times.last < last + tail) {
      times.add(times.last + tail);
    }
    return _Beats(times);
  }

  /// El pulso (en µs) entre [minP] y [maxP] con el que mejor encajan los
  /// intervalos entre los ataques [i0, i1), prefiriendo los cercanos a
  /// [prior] (con una tolerancia de [sigmaOctaves] octavas).
  double _bestPeriod(List<_Onset> onsets, int i0, int i1, double prior, double sigmaOctaves, double minP, double maxP) {
    var period = prior;
    var best = -1.0;
    for (var p = minP; p <= maxP; p *= 1.005) {
      final l = math.log(p / prior) / math.ln2;
      final weight = math.exp(-l * l / (2 * sigmaOctaves * sigmaOctaves));
      if (weight < 0.01) continue;
      var num = 0.0;
      var den = 0.0;
      for (var i = i0; i < i1; i++) {
        for (var j = i + 1; j < math.min(i1, i + 5); j++) {
          final d = onsets[j].time - onsets[i].time;
          if (d > 3e6) break;
          final x = d / p;
          if (x < 0.15) continue;
          final w = onsets[i].salience * onsets[j].salience;
          num += w * _fit(x);
          den += w;
        }
      }
      if (den == 0) continue;
      final s = num / den * weight;
      if (s > best) {
        best = s;
        period = p;
      }
    }
    return period;
  }

  /// El pulso por tramos (cada 1,5 s, mirando 4 s a cada lado), para
  /// seguir a quien acelera o frena. Lista de (instante, pulso).
  List<(double, double)> _localPeriods(List<_Onset> onsets, double period) {
    final first = onsets.first.time;
    final last = onsets.last.time;
    final out = <(double, double)>[];
    for (var t = first; ; t += 1.5e6) {
      final i0 = onsets.indexWhere((o) => o.time >= t - 4e6);
      var i1 = onsets.indexWhere((o) => o.time > t + 4e6);
      if (i1 < 0) i1 = onsets.length;
      final p = i1 - i0 >= 6 ? _bestPeriod(onsets, i0, i1, period, 0.25, period * 0.7, period * 1.45) : period;
      out.add((t, p));
      if (t >= last) break;
    }
    // Sin saltos sueltos: mediana de cada tres.
    return [
      for (var i = 0; i < out.length; i++)
        (out[i].$1, ([out[math.max(0, i - 1)].$2, out[i].$2, out[math.min(out.length - 1, i + 1)].$2]..sort())[1]),
    ];
  }

  /// Qué tan bien cae un intervalo de [x] pulsos en pulsos enteros o en
  /// sus divisiones sencillas.
  static double _fit(double x) {
    final f = x - x.floorToDouble();
    var best = 0.0;
    for (final (c, v) in const [
      (0.0, 1.0),
      (1.0, 1.0),
      (0.5, 0.7),
      (0.25, 0.35),
      (0.75, 0.35),
      (1 / 3, 0.4),
      (2 / 3, 0.4),
    ]) {
      final d = (f - c) / 0.06;
      best = math.max(best, v * math.exp(-d * d / 2));
    }
    return best;
  }

  /// Compás (entre el del metrónomo y los parecidos, salvo que esté
  /// fijado) y en qué pulso caen las partes fuertes: donde empiezan las
  /// notas largas, los acordes y los bajos.
  (TimeSignature, int) _meter(List<_Onset> onsets, int jFirst, int? metroDown) {
    final pt = _pt;
    final fixed = settings.meter;
    final base = settings.time;
    final simple = pulseQuarters(base) != 1.5 && {2, 3, 4}.contains(base.beats);
    final candidates = fixed != null
        ? [fixed]
        : [
            base,
            if (simple)
              for (final b in const [3, 4])
                if (b != base.beats) TimeSignature(b, base.beatType),
          ];
    final few = onsets.length < 8;
    if (few) {
      final t = candidates.first;
      final b = pulsesPerMeasure(t);
      return (t, metroDown != null ? metroDown % b : jFirst % b);
    }
    // Peso de cada pulso: los ataques que caen justo en él, más pesados si
    // la nota es larga.
    // Bajo: la nota más grave de su entorno (un pulso antes y después), no
    // cualquier nota de un arpegio de la mano izquierda.
    final lows = [for (final o in onsets) o.notes.map((n) => n.midi).reduce(math.min)];
    bool isBass(int i) {
      if (lows[i] >= 60) return false;
      for (var k = i - 1; k >= 0 && onsets[i].tick - onsets[k].tick <= pt; k--) {
        if (lows[k] < lows[i]) return false;
      }
      for (var k = i + 1; k < onsets.length && onsets[k].tick - onsets[i].tick <= pt; k++) {
        if (lows[k] < lows[i]) return false;
      }
      return true;
    }

    final bassAt = [for (var i = 0; i < onsets.length; i++) isBass(i)];
    final weight = <int, double>{};
    for (final (i, o) in onsets.indexed) {
      if (o.tick % pt != 0) continue;
      // Un bajo cuenta hasta el siguiente bajo (aunque la otra mano toque
      // entre medias): en "bajo – acorde" el bajo marca la parte fuerte.
      final bass = bassAt[i];
      var next = o.notes.map((n) => n.endTick).reduce(math.max);
      for (var k = i + 1; k < onsets.length; k++) {
        if (!bass || bassAt[k]) {
          next = onsets[k].tick;
          break;
        }
      }
      final w = o.salience * (1 + 0.8 * math.min(2, (next - o.tick) / pt)) * (bass ? 1.2 : 1);
      final j = o.tick ~/ pt;
      weight[j] = (weight[j] ?? 0) + w;
    }
    final jLast = _floorDiv(onsets.last.tick, pt);
    double strength(int b, int p) {
      var sum = 0.0;
      var hs = 0.0;
      var all = 0.0;
      var count = 0;
      for (var j = jFirst; j <= jLast; j++) {
        final w = weight[j] ?? 0;
        final pos = (j - p) % b;
        final h = pos == 0 ? 1.0 : (b == 4 && pos == 2 ? 0.4 : 0.0);
        sum += h * w;
        hs += h;
        all += w;
        count++;
      }
      final mean = all / count;
      if (hs == 0 || mean == 0) return 0;
      return (sum / hs - mean) / mean;
    }

    TimeSignature? bestTime;
    var bestScore = -double.infinity;
    for (final t in candidates) {
      final b = pulsesPerMeasure(t);
      var s = -double.infinity;
      for (var p = 0; p < b; p++) {
        s = math.max(s, strength(b, p));
      }
      if (t == base) s += 0.1;
      if (s > bestScore) {
        bestScore = s;
        bestTime = t;
      }
    }
    final t = bestTime!;
    final b = pulsesPerMeasure(t);
    var phase = 0;
    var phaseScore = -double.infinity;
    for (var p = 0; p < b; p++) {
      final pickup = (p - jFirst) % b;
      var s = strength(b, p) + (pickup == 0 ? 0.2 : (pickup == 1 ? 0.08 : 0));
      if (metroDown != null && b == pulsesPerMeasure(base) && p == metroDown % b) s += 0.3;
      if (s > phaseScore) {
        phaseScore = s;
        phase = p;
      }
    }
    return (t, phase);
  }

  List<_Group> _groups(List<_RawNote> notes) {
    final byTick = <int, _Group>{};
    for (final n in notes) {
      (byTick[n.tick] ??= _Group(n.tick)).notes.add(n);
    }
    final groups = byTick.values.toList()..sort((a, b) => a.tick.compareTo(b.tick));
    for (final g in groups) {
      g.notes.sort((a, b) => a.midi.compareTo(b.midi));
    }
    return groups;
  }

  /// Reparte cada acorde entre las manos: el corte que deja cada nota más
  /// cerca del registro por donde viene su mano, sin abrir una mano más de
  /// una décima.
  void _assignHands(List<_Group> groups) {
    var rh = 67.0;
    var lh = 48.0;
    for (final g in groups) {
      final p = [for (final n in g.notes) n.midi];
      var bestK = 0;
      var bestCost = double.infinity;
      for (var k = 0; k <= p.length; k++) {
        var cost = 0.0;
        for (var i = 0; i < p.length; i++) {
          cost += i < k ? (p[i] - lh).abs() : (p[i] - rh).abs();
        }
        if (k > 1 && p[k - 1] - p[0] > 16) cost += 100;
        if (k < p.length - 1 && p.last - p[k] > 16) cost += 100;
        // Preferencia suave por el do central como frontera.
        for (var i = 0; i < p.length; i++) {
          if (i < k && p[i] >= 67) cost += 6;
          if (i >= k && p[i] <= 52) cost += 6;
        }
        if (cost < bestCost) {
          bestCost = cost;
          bestK = k;
        }
      }
      for (var i = 0; i < g.notes.length; i++) {
        g.notes[i].staff = i < bestK ? 2 : 1;
      }
      final left = p.take(bestK);
      final right = p.skip(bestK);
      if (left.isNotEmpty) lh = lh * 0.6 + left.reduce((a, b) => a + b) / left.length * 0.4;
      if (right.isNotEmpty) rh = rh * 0.6 + right.reduce((a, b) => a + b) / right.length * 0.4;
      if (rh - lh < 7) {
        final mid = (rh + lh) / 2;
        rh = mid + 3.5;
        lh = mid - 3.5;
      }
    }
  }

  int _streamEnds(List<_Group> groups) {
    var end = 0;
    for (final g in groups) {
      for (final n in g.notes) {
        end = math.max(end, n.endTick);
      }
    }
    return end;
  }

  MusicKey? _estimateKey() {
    final chords = SongAnalyzer.chordsFromTake(take);
    if (chords.isEmpty) return null;
    final estimate = KeyEstimator.fromChords(
      [for (final c in chords) c.chord],
      weights: [for (final c in chords) LiveAnalyzer.durationWeight(c.durationMicros ?? 0)],
    );
    return estimate.isEmpty ? null : estimate.key;
  }

  /// Una mano como secuencia de acordes y silencios: cada acorde dura hasta
  /// el siguiente de la misma mano, salvo que se soltara mucho antes (al
  /// menos un pulso): entonces termina en el pulso y sigue un silencio.
  List<ScoreEvent> _staffEvents(Score score, List<_Group> groups, int staff, MusicKey? key) {
    final out = <ScoreEvent>[];
    final end = score.lengthTicks;
    final pt = _pt;
    var pos = 0;
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final notes = [
        for (final n in g.notes)
          if (n.staff == staff) n,
      ];
      final next = i + 1 < groups.length ? groups[i + 1].tick : end;
      if (g.tick > pos) out.addAll(_rests(score, pos, g.tick, staff));
      var stop = math.min(next, notes.map((n) => n.endTick).reduce(math.max));
      if (next - stop < pt) {
        stop = next;
      } else {
        stop = math.min(next, ((stop + pt - 1) ~/ pt) * pt);
      }
      stop = math.max(stop, g.tick + 1);
      out.addAll(_notesEvents(score, notes, g.tick, stop, staff, key));
      pos = stop;
    }
    if (pos < end) out.addAll(_rests(score, pos, end, staff));
    return out;
  }

  List<ScoreEvent> _rests(Score score, int from, int to, int staff) {
    final out = <ScoreEvent>[];
    for (final p in _pieces(score, from, to)) {
      final m = score.measures[score.measureAt(p.tick)];
      final whole = p.tick == m.tick && p.length == m.length;
      out.add(
        ScoreEvent(
          id: 'r${_ids++}',
          tick: p.tick,
          duration: p.length,
          staff: staff,
          voice: staff == 1 ? 1 : 5,
          notes: [],
          type: whole ? null : p.type,
          dots: whole ? 0 : p.dots,
          tuplet: p.tuplet,
          tupletSpan: p.tupletSpan,
        ),
      );
    }
    return out;
  }

  List<ScoreEvent> _notesEvents(Score score, List<_RawNote> notes, int from, int to, int staff, MusicKey? key) {
    final pieces = _pieces(score, from, to);
    final out = <ScoreEvent>[];
    for (final (i, p) in pieces.indexed) {
      out.add(
        ScoreEvent(
          id: 'e${_ids++}',
          tick: p.tick,
          duration: p.length,
          staff: staff,
          voice: staff == 1 ? 1 : 5,
          type: p.type,
          dots: p.dots,
          tuplet: p.tuplet,
          tupletSpan: p.tupletSpan,
          notes: [
            for (final n in notes)
              () {
                final spelling = key?.spell(n.midi % 12) ?? SpelledNote.byDefault(n.midi % 12);
                return ScoreNote(
                  id: 'n${_ids++}',
                  midi: n.midi,
                  spelling: spelling,
                  octave: ChordStaff.octaveOf(n.midi, spelling),
                  tieStop: i > 0,
                  tieStart: i < pieces.length - 1,
                  velocity: n.velocity,
                );
              }(),
          ],
        ),
      );
    }
    return out;
  }

  /// Parte [from, to) en figuras escribibles: se corta en las barras y cada
  /// trozo toma la figura más larga que empieza alineada con su propio
  /// valor (así una síncopa se escribe con ligadura sobre el pulso).
  /// Dentro de un pulso en tresillo: corcheas o negras de tresillo.
  List<_Piece> _pieces(Score score, int from, int to) {
    final out = <_Piece>[];
    final pt = _pt;
    var s = from;
    while (s < to) {
      final m = score.measures[score.measureAt(s)];
      var segEnd = math.min(to, m.end);
      final beat = _floorDiv(s, pt);
      final beatStart = beat * pt;
      if (_tripletBeats.contains(beat) && !(s == beatStart && segEnd >= beatStart + pt)) {
        const unit = ticksPerQuarter ~/ 3;
        final stop = math.min(segEnd, beatStart + pt);
        final units = ((stop - s) / unit).round().clamp(1, 2);
        out.add(
          _Piece(
            s,
            units * unit,
            units == 2 ? NoteType.quarter : NoteType.eighth,
            0,
            (3, 2),
            // El grupo (que empieza con el pulso) dura el pulso.
            s == beatStart ? pt : null,
          ),
        );
        s += units * unit;
        continue;
      }
      // Si termina dentro de un pulso en tresillo, ese pulso va aparte.
      final endBeat = _floorDiv(segEnd, pt);
      if (segEnd % pt != 0 && _tripletBeats.contains(endBeat) && endBeat * pt > s) segEnd = endBeat * pt;
      final rel = s - m.tick;
      final pulse = (pulseQuarters(m.time) * ticksPerQuarter).round();
      final onPulse = rel % pulse == 0;
      final nextPulse = m.tick + (rel ~/ pulse + 1) * pulse;
      var placed = false;
      for (final type in NoteType.values) {
        if (type.quarters > 4) continue;
        for (final dots in const [1, 0]) {
          final len = NoteType.dottedTicks(type, dots);
          if (len > segEnd - s) continue;
          // Un puntillo que acaba fuera de la rejilla de semicorcheas lleva a
          // cadenas ilegibles (♬. ⁀ 𝅘𝅥𝅯. ⁀ …).
          if (dots == 1 && (rel + len) % (ticksPerQuarter ~/ 4) != 0) continue;
          if (onPulse) {
            // En un pulso cabe cualquier figura que termine en un pulso, las
            // menores que el pulso y la del pulso con puntillo (♩. ♪).
            final dottedPulse = dots == 1 && type.ticks == pulse;
            if ((rel + len) % pulse != 0 && len > pulse && !dottedPulse) continue;
          } else {
            // A contratiempo: alineada con su propio valor y sin cruzar el
            // pulso siguiente (la síncopa se escribe ligada).
            // Excepción: la negra a contratiempo que acaba justo ahí
            // (♪ ♩ ♪), si no cruza la mitad de un 4/4.
            final syncopa =
                dots == 0 &&
                type.ticks == pulse &&
                pulse == ticksPerQuarter &&
                rel % pulse == pulse ~/ 2 &&
                s + len == segEnd &&
                !(m.time.beats == 4 && m.time.beatType == 4 && nextPulse - m.tick == m.length ~/ 2);
            if (!syncopa && (rel % math.min(type.ticks, pulse) != 0 || s + len > nextPulse)) continue;
          }
          out.add(_Piece(s, len, type, dots, null, null));
          s += len;
          placed = true;
          break;
        }
        if (placed) break;
      }
      if (!placed) {
        // Resto que no es figura (por redondeo): se cierra hasta la rejilla.
        final len = math.max(1, math.min(segEnd - s, ticksPerQuarter ~/ 4));
        out.add(_Piece(s, len, NoteType.ofTicks(len)?.$1 ?? NoteType.sixteenth, 0, null, null));
        s += len;
      }
    }
    return out;
  }

  /// p, mf, f… según la fuerza de cada compás; solo se escribe un cambio
  /// que se mantiene al menos dos compases.
  List<ScoreDirection> _dynamics(Score score, List<_RawNote> notes) {
    final perMeasure = List<List<int>>.generate(score.measures.length, (_) => []);
    // La anacrusa cuenta con el primer compás (dos notas no son un matiz).
    final pickup = score.measures.first.implicit && score.measures.length > 1 ? 1 : 0;
    for (final n in notes) {
      final i = math.max(pickup, score.measureAt(n.tick));
      perMeasure[i].add(n.velocity);
    }
    // Lo que se oye es lo más fuerte (la melodía), no la media con el
    // acompañamiento: se toma el percentil 80 de cada compás, y la mediana
    // con los compases vecinos para no marcar cada vaivén.
    int? loud(List<int> v) => v.isEmpty ? null : (List.of(v)..sort())[((v.length - 1) * 0.8).round()];
    final levels = [for (final v in perMeasure) loud(v)];
    final smooth = [
      for (var i = 0; i < levels.length; i++)
        if (levels[i] == null)
          null
        else
          () {
            final around = [
              for (var j = math.max(0, i - 1); j <= math.min(levels.length - 1, i + 1); j++)
                if (levels[j] != null) levels[j]!,
            ]..sort();
            return around.length == 2 ? levels[i]! : around[around.length ~/ 2];
          }(),
    ];
    final out = <ScoreDirection>[];
    String? current;
    // Cambia solo si se aleja bien del matiz actual (no por estar en la
    // frontera entre p y mp) y se mantiene en el compás siguiente.
    bool differs(int? v) => v != null && (current == null || (v - ScoreDirection.velocities[current]!).abs() >= 12);
    for (var i = 0; i < smooth.length; i++) {
      final v = smooth[i];
      if (!differs(v)) continue;
      final mark = ScoreDirection.markFor(v!);
      if (mark == current) continue;
      final next = i + 1 < smooth.length ? smooth[i + 1] : v;
      if (current != null && next != null && !differs(next)) continue;
      final first = notes
          .where((n) => math.max(pickup, score.measureAt(n.tick)) == i)
          .map((n) => n.tick)
          .reduce(math.min);
      out.add(ScoreDirection(tick: first, kind: DirectionKind.dynamic, value: mark));
      current = mark;
    }
    return out;
  }

  /// El cifrado: en cada tramo (medio compás en 4/4; un compás en 2/4,
  /// 3/4 y 6/8) las notas que más suenan, contando cada bajo hasta el
  /// siguiente bajo (en "bajo – acorde" el bajo se suelta enseguida pero se
  /// sigue oyendo) y juntando los arpegios. Solo donde hay acompañamiento
  /// (mano izquierda o bajo); se escribe cuando cambia.
  List<ChordSymbol> _chordSymbols(Score score, List<_RawNote> notes, MusicKey? key) {
    final sorted = [...notes]..sort((a, b) => a.tick.compareTo(b.tick));
    final pt = _pt;
    // Bajos: la nota más grave de su entorno (un pulso a cada lado).
    final bassEnd = <_RawNote, int>{};
    final basses = [
      for (final n in sorted)
        if (n.midi < 55 && !sorted.any((m) => (m.tick - n.tick).abs() <= pt && m.midi < n.midi)) n,
    ];
    for (var k = 0; k < basses.length; k++) {
      final n = basses[k];
      final next = k + 1 < basses.length ? basses[k + 1].tick : n.endTick;
      bassEnd[n] = math.max(n.endTick, math.min(next, n.tick + 4 * pt));
    }
    const recognizer = ChordRecognizer();
    final out = <ChordSymbol>[];
    for (final m in score.measures) {
      final t = m.time;
      final slot = t.beats == 4 && t.beatType == 4
          ? t.measureTicks ~/ 2
          : (pulseQuarters(t) == 1.5 && t.beats >= 12 ? t.measureTicks ~/ 2 : t.measureTicks);
      for (var s = m.tick; s < m.end; s += slot) {
        final e = math.min(m.end, s + slot);
        final weight = <int, int>{};
        var accompanied = false;
        int? lowest;
        for (final n in sorted) {
          if (n.tick >= e) break;
          final end = bassEnd[n] ?? n.endTick;
          final overlap = (math.min(end, e) - math.max(n.tick, s)).toInt();
          if (overlap <= 0) continue;
          weight[n.midi % 12] = (weight[n.midi % 12] ?? 0) + overlap;
          if (n.staff == 2 || bassEnd.containsKey(n)) accompanied = true;
          if (lowest == null || n.midi < lowest) lowest = n.midi;
        }
        if (!accompanied || weight.length < 2) continue;
        // Las de paso (poco tiempo sonando) no cuentan.
        final top = weight.values.reduce(math.max);
        final pcs = {
          for (final w in weight.entries)
            if (w.value >= top * 0.3) w.key,
        };
        final found = recognizer.recognizePitchClasses(pcs, bass: lowest! % 12);
        if (found == null || found.candidates.isEmpty) continue;
        var chord = _simple(found.candidates.first.chord);
        if (chord.quality == ChordQuality.power) {
          // Sin tercera clara: la que haya sonado aunque sea poco o, si no,
          // la de la tonalidad.
          final major = weight[(chord.root + 4) % 12] ?? 0;
          final minor = weight[(chord.root + 3) % 12] ?? 0;
          final q = major != minor
              ? (major > minor ? ChordQuality.major : ChordQuality.minor)
              : _diatonic(chord.root, key);
          if (q != null) chord = Chord(chord.root, q, bass: chord.bass);
        }
        if (out.isNotEmpty && out.last.chord == chord) continue;
        out.add(ChordSymbol(tick: s, chord: chord));
      }
    }
    return out;
  }
}

/// Mayor o menor según la tonalidad (I, IV, V mayores; ii, iii, vi menores
/// en mayor; i, iv menores y III, V, VI, VII mayores en menor).
ChordQuality? _diatonic(int root, MusicKey? key) {
  if (key == null) return null;
  final d = (root - key.tonic) % 12;
  if (key.isMajor) {
    if (const {0, 5, 7}.contains(d)) return ChordQuality.major;
    if (const {2, 4, 9}.contains(d)) return ChordQuality.minor;
  } else {
    if (const {0, 5}.contains(d)) return ChordQuality.minor;
    if (const {3, 7, 8, 10}.contains(d)) return ChordQuality.major;
  }
  return null;
}

/// El cifrado de una partitura, sin adornos: las notas de la melodía hacen
/// que se detecten add9, 6 o 9 que no son parte de la armonía. Se queda la
/// tríada (o la séptima) y el bajo solo si es una inversión.
Chord _simple(Chord c) {
  final q = switch (c.quality) {
    ChordQuality.add9 || ChordQuality.sixth || ChordQuality.sixNine || ChordQuality.add4 => ChordQuality.major,
    ChordQuality.minorAdd9 || ChordQuality.minorSixth || ChordQuality.minorMajor7 => ChordQuality.minor,
    ChordQuality.dominant9 => ChordQuality.dominant7,
    ChordQuality.major9 => ChordQuality.major7,
    ChordQuality.minor9 => ChordQuality.minor7,
    final other => other,
  };
  final b = c.bass;
  final inversion = b != null && q.intervals.take(3).map((i) => (c.root + i) % 12).contains(b);
  return Chord(c.root, q, bass: inversion ? b : null);
}

/// Un trozo escribible de una nota o un silencio.
class _Piece {
  _Piece(this.tick, this.length, this.type, this.dots, this.tuplet, this.tupletSpan);

  final int tick;
  final int length;
  final NoteType type;
  final int dots;
  final (int, int)? tuplet;
  final int? tupletSpan;
}
