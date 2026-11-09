import 'dart:math' as math;

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
int pulsesPerMeasure(TimeSignature t) =>
    t.beatType == 8 && t.beats % 3 == 0 && t.beats > 3 ? t.beats ~/ 3 : t.beats;

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
      );

  /// Pulsos por minuto del metrónomo (ver [pulseQuarters]).
  final double bpm;
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
  }) =>
      TranscriptionSettings(
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
      };
}

/// La interpretación original de una partitura grabada: la toma en bruto y
/// cómo se escribió.
class ScoreRecording {
  ScoreRecording({required this.take, required this.settings, this.appliedLatencyMicros = 0});

  factory ScoreRecording.fromJson(Map<String, dynamic> j) => ScoreRecording(
        take: Take.fromJson(j['take'] as Map<String, dynamic>),
        settings: TranscriptionSettings.fromJson(j['settings'] as Map<String, dynamic>),
        appliedLatencyMicros: j['appliedLatency'] as int? ?? 0,
      );

  final Take take;
  TranscriptionSettings settings;

  /// Corrección total usada al escribirla (automática + manual).
  int appliedLatencyMicros;

  /// Pulso de la partitura (desplegada = lineal: no hay repeticiones) en el
  /// instante [micros] de la toma, para mover el cursor al reproducirla tal
  /// como se tocó. [pickupTicks]: lo que dura la anacrusa.
  double tickAt(int micros, int pickupTicks) =>
      (micros - settings.startMicros - appliedLatencyMicros) / settings.quarterMicros * ticksPerQuarter + pickupTicks;

  Map<String, dynamic> toJson() => {
        'take': take.toJson(),
        'settings': settings.toJson(),
        if (appliedLatencyMicros != 0) 'appliedLatency': appliedLatencyMicros,
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
  bool triplet = false;
  int staff = 1;
}

class _Group {
  _Group(this.tick, this.triplet);

  final int tick;
  final bool triplet;
  final List<_RawNote> notes = [];
}

/// Convierte una interpretación grabada con metrónomo en partitura de piano
/// (dos pentagramas, una voz por mano).
///
/// Pasos: notas con su inicio y final (el pedal alarga hasta soltarlo),
/// corrección de adelanto, cuantización a la rejilla (tresillos donde
/// encajan), reparto entre manos, duraciones hasta la siguiente nota de la
/// misma mano, ligaduras en las barras, ortografía según la tonalidad,
/// fuerza de cada nota, dinámicas y cifrado.
class PerformanceTranscriber {
  PerformanceTranscriber._(this.take, this.settings);

  /// Escribe [take] como partitura. Devuelve null si no hay notas.
  static Score? transcribe(
    Take take,
    TranscriptionSettings settings, {
    required String id,
    required String title,
  }) =>
      PerformanceTranscriber._(take, settings)._run(id, title);

  final Take take;
  final TranscriptionSettings settings;
  int _ids = 0;

  int get _gridTicks => ticksPerQuarter ~/ settings.grid;
  int get _pulseTicks => (pulseQuarters(settings.time) * ticksPerQuarter).round();
  int get _measureTicks => settings.time.measureTicks;

  Score? _run(String id, String title) {
    final notes = _notes();
    if (notes.isEmpty) return null;
    final latency = (settings.autoLatency ? _estimateLatency(notes) : 0) + settings.latencyMicros;
    final qm = settings.quarterMicros;
    for (final n in notes) {
      n.tick = ((n.on - settings.startMicros - latency) / qm * ticksPerQuarter).round();
      n.endTick = ((n.off - settings.startMicros - latency) / qm * ticksPerQuarter).round();
    }
    _quantize(notes);

    // Anacrusa: lo tocado durante la cuenta, redondeado a pulsos enteros.
    final first = notes.map((n) => n.tick).reduce(math.min);
    final pickup = first < 0 ? ((-first + _pulseTicks - 1) ~/ _pulseTicks) * _pulseTicks : 0;
    for (final n in notes) {
      n.tick += pickup;
      n.endTick += pickup;
    }

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
      measures.add(Measure(number: '0', tick: 0, length: pickup, time: settings.time, fifths: fifths, implicit: true));
      tick = pickup;
    }
    do {
      measures.add(Measure(number: '${number++}', tick: tick, length: _measureTicks, time: settings.time, fifths: fifths));
      tick += _measureTicks;
    } while (tick < lastEnd);
    measures.first.tempo = double.parse(settings.quarterBpm.toStringAsFixed(1));
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
      part.events.addAll(_staffEvents(score, [for (final g in groups) if (g.notes.any((n) => n.staff == staff)) g], staff, key));
    }
    part.events.sort((a, b) => a.tick != b.tick ? a.tick.compareTo(b.tick) : a.staff.compareTo(b.staff));
    if (settings.dynamics) part.directions.addAll(_dynamics(score, notes));
    if (settings.chordSymbols) part.chords.addAll(_chordSymbols(score, latency, pickup));
    score.recording = ScoreRecording(take: take, settings: settings, appliedLatencyMicros: latency);
    return score;
  }

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
    return [for (final n in out) if (n.off - n.on >= 25000) n];
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

  /// Lleva inicios y finales a la rejilla. En cada pulso se prueba también
  /// la de tresillos de corchea y se usa si encaja claramente mejor.
  void _quantize(List<_RawNote> notes) {
    final g = _gridTicks;
    const beat = ticksPerQuarter;
    final tripletGrid = beat ~/ 3;
    final byBeat = <int, List<_RawNote>>{};
    for (final n in notes) {
      (byBeat[(n.tick / beat).floor()] ??= []).add(n);
    }
    final compound = pulseQuarters(settings.time) == 1.5;
    for (final entry in byBeat.entries) {
      final list = entry.value;
      var straight = 0.0;
      var triplet = 0.0;
      var tripletOnly = 0;
      for (final n in list) {
        straight += (n.tick - (n.tick / g).round() * g).abs();
        final t = (n.tick / tripletGrid).round() * tripletGrid;
        triplet += (n.tick - t).abs();
        final inBeat = t - entry.key * beat;
        if (inBeat == tripletGrid || inBeat == 2 * tripletGrid) tripletOnly++;
      }
      final useTriplet = settings.triplets && !compound && tripletOnly >= 2 && triplet < straight * 0.6;
      for (final n in list) {
        final grid = useTriplet ? tripletGrid : g;
        n.triplet = useTriplet;
        n.tick = (n.tick / grid).round() * grid;
      }
    }
    for (final n in notes) {
      n.endTick = math.max(n.tick + (n.triplet ? tripletGrid : g), (n.endTick / g).round() * g);
    }
  }

  List<_Group> _groups(List<_RawNote> notes) {
    final byTick = <int, _Group>{};
    for (final n in notes) {
      (byTick[n.tick] ??= _Group(n.tick, n.triplet)).notes.add(n);
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
  /// que se suelta o hasta el siguiente de la misma mano.
  List<ScoreEvent> _staffEvents(Score score, List<_Group> groups, int staff, MusicKey? key) {
    final out = <ScoreEvent>[];
    final end = score.lengthTicks;
    var pos = 0;
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final notes = [for (final n in g.notes) if (n.staff == staff) n];
      final next = i + 1 < groups.length ? groups[i + 1].tick : end;
      if (g.tick > pos) out.addAll(_rests(score, pos, g.tick, staff));
      var stop = math.min(next, notes.map((n) => n.endTick).reduce(math.max));
      // Un hueco menor que la rejilla es legato, no silencio.
      if (next - stop < _gridTicks) stop = next;
      stop = math.max(stop, g.tick + 1);
      out.addAll(_notesEvents(score, g, notes, g.tick, stop, staff, key));
      pos = stop;
    }
    if (pos < end) out.addAll(_rests(score, pos, end, staff));
    return out;
  }

  List<ScoreEvent> _rests(Score score, int from, int to, int staff) {
    final out = <ScoreEvent>[];
    for (final (s, len, type, dots, tuplet) in _pieces(score, from, to, false)) {
      final m = score.measures[score.measureAt(s)];
      final whole = s == m.tick && len == m.length;
      out.add(ScoreEvent(
        id: 'r${_ids++}',
        tick: s,
        duration: len,
        staff: staff,
        voice: staff == 1 ? 1 : 5,
        notes: [],
        type: whole ? null : type,
        dots: whole ? 0 : dots,
        tuplet: tuplet,
      ));
    }
    return out;
  }

  List<ScoreEvent> _notesEvents(
    Score score,
    _Group group,
    List<_RawNote> notes,
    int from,
    int to,
    int staff,
    MusicKey? key,
  ) {
    final pieces = _pieces(score, from, to, group.triplet);
    final out = <ScoreEvent>[];
    for (final (i, (s, len, type, dots, tuplet)) in pieces.indexed) {
      out.add(ScoreEvent(
        id: 'e${_ids++}',
        tick: s,
        duration: len,
        staff: staff,
        voice: staff == 1 ? 1 : 5,
        type: type,
        dots: dots,
        tuplet: tuplet,
        notes: [
          for (final n in notes)
            () {
              final spelling = key?.spell(n.midi % 12) ?? _defaultSpelling(n.midi % 12);
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
      ));
    }
    return out;
  }

  static SpelledNote _defaultSpelling(int pc) => SpelledNote.byDefault(pc);

  /// Parte [from, to) en figuras escribibles: se corta en las barras y cada
  /// trozo toma la figura más larga que empieza alineada con su propio
  /// valor (así una síncopa se escribe con ligadura sobre el pulso).
  /// En pulsos de tresillo: corcheas o negras de tresillo hasta el pulso.
  List<(int, int, NoteType, int, (int, int)?)> _pieces(Score score, int from, int to, bool triplet) {
    final out = <(int, int, NoteType, int, (int, int)?)>[];
    var s = from;
    while (s < to) {
      final m = score.measures[score.measureAt(s)];
      final measureEnd = m.end;
      final segEnd = math.min(to, measureEnd);
      if (triplet) {
        const unit = ticksPerQuarter ~/ 3;
        final beatEnd = (s ~/ ticksPerQuarter + 1) * ticksPerQuarter;
        if (s % unit == 0 && s % ticksPerQuarter != 0 || segEnd - s < ticksPerQuarter) {
          final stop = math.min(segEnd, beatEnd);
          final len = math.max(unit, ((stop - s) ~/ unit) * unit);
          final type = len >= 2 * unit ? NoteType.quarter : NoteType.eighth;
          final l = type == NoteType.quarter ? 2 * unit : unit;
          out.add((s, l, type, 0, (3, 2)));
          s += l;
          continue;
        }
      }
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
          if (onPulse) {
            // En un pulso cabe cualquier figura que termine en un pulso, las
            // menores que el pulso y la del pulso con puntillo (♩. ♪).
            final dottedPulse = dots == 1 && type.ticks == pulse;
            if ((rel + len) % pulse != 0 && len > pulse && !dottedPulse) continue;
          } else {
            // A contratiempo: alineada con su propio valor y sin cruzar el
            // pulso siguiente (la síncopa se escribe ligada).
            if (rel % math.min(type.ticks, pulse) != 0 || s + len > nextPulse) continue;
          }
          out.add((s, len, type, dots, null));
          s += len;
          placed = true;
          break;
        }
        if (placed) break;
      }
      if (!placed) {
        // Resto que no es figura (por redondeo): se cierra hasta la rejilla.
        final len = math.max(1, math.min(segEnd - s, _gridTicks));
        out.add((s, len, NoteType.ofTicks(len)?.$1 ?? NoteType.sixteenth, 0, null));
        s += len;
      }
    }
    return out;
  }

  /// p, mf, f… según la fuerza media de cada compás; solo se escribe un
  /// cambio que se mantiene al menos dos compases.
  List<ScoreDirection> _dynamics(Score score, List<_RawNote> notes) {
    final perMeasure = List<List<int>>.generate(score.measures.length, (_) => []);
    for (final n in notes) {
      final i = score.measureAt(n.tick);
      perMeasure[i].add(n.velocity);
    }
    // Lo que se oye es lo más fuerte (la melodía), no la media con el
    // acompañamiento: se toma el percentil 80 de cada compás.
    int loud(List<int> v) => (List.of(v)..sort())[((v.length - 1) * 0.8).round()];
    final marks = [for (final v in perMeasure) v.isEmpty ? null : ScoreDirection.markFor(loud(v))];
    final out = <ScoreDirection>[];
    String? current;
    for (var i = 0; i < marks.length; i++) {
      final mark = marks[i];
      if (mark == null || mark == current) continue;
      final next = i + 1 < marks.length ? marks[i + 1] : mark;
      if (current != null && next != null && next != mark) continue;
      final first = notes.where((n) => score.measureAt(n.tick) == i).map((n) => n.tick).reduce(math.min);
      out.add(ScoreDirection(tick: first, kind: DirectionKind.dynamic, value: mark));
      current = mark;
    }
    return out;
  }

  /// Los acordes que Scale detecta en la toma, como cifrado: como mucho
  /// uno por medio compás (por compás en 2/4 y 3/4), el que más suena en
  /// ese tramo, y solo cuando cambia.
  List<ChordSymbol> _chordSymbols(Score score, int latency, int pickup) {
    final qm = settings.quarterMicros;
    final spans = <(int, int, Chord)>[];
    for (final c in SongAnalyzer.chordsFromTake(take)) {
      final start = c.startMicros;
      if (start == null) continue;
      final from = ((start - settings.startMicros - latency) / qm * ticksPerQuarter).round() + pickup;
      final to = from + ((c.durationMicros ?? 0) / qm * ticksPerQuarter).round();
      if (to > from) spans.add((from, to, c.chord));
    }
    final t = settings.time;
    final slot = t.beats == 4 && t.beatType == 4
        ? t.measureTicks ~/ 2
        : (pulseQuarters(t) == 1.5 && t.beats >= 12 ? t.measureTicks ~/ 2 : t.measureTicks);
    final out = <ChordSymbol>[];
    for (final m in score.measures) {
      for (var s = m.tick; s < m.end; s += slot) {
        final e = math.min(m.end, s + slot);
        final weight = <Chord, int>{};
        for (final (from, to, chord) in spans) {
          final overlap = math.min(to, e) - math.max(from, s).toInt();
          if (overlap > 0) weight[chord] = (weight[chord] ?? 0) + overlap;
        }
        if (weight.isEmpty) continue;
        final best = weight.entries.reduce((a, b) => a.value >= b.value ? a : b);
        // Debe sonar al menos la mitad del tramo para escribirse.
        if (best.value * 2 < e - s) continue;
        if (out.isNotEmpty && out.last.chord == best.key) continue;
        out.add(ChordSymbol(tick: s, chord: best.key));
      }
    }
    return out;
  }

}
