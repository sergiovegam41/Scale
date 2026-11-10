import 'score_timeline.dart';

/// Un momento de la partitura en que hay que tocar algo: las notas (de las
/// manos elegidas) que empiezan juntas.
class PracticeStep {
  PracticeStep(this.tick, this.notes) : pitches = {for (final n in notes) n.midi};

  /// Pulso desplegado.
  final int tick;
  final List<PlayedNote> notes;

  /// Alturas distintas que hay que tocar.
  final Set<int> pitches;

  List<String> get ids => [for (final n in notes) n.noteId];

  /// Ids de las notas del paso con estas alturas.
  List<String> idsOf(Set<int> midis) => [
    for (final n in notes)
      if (midis.contains(n.midi)) n.noteId,
  ];

  /// Los pasos de una partitura, en orden, con solo las notas que [include]
  /// acepta (por ejemplo, las de una mano).
  static List<PracticeStep> of(ScoreTimeline timeline, {bool Function(PlayedNote)? include}) {
    final out = <PracticeStep>[];
    for (final n in timeline.notes) {
      if (include != null && !include(n)) continue;
      final last = out.isEmpty ? null : out.last;
      if (last != null && last.tick == n.start) {
        last.notes.add(n);
        last.pitches.add(n.midi);
      } else {
        out.add(PracticeStep(n.start, [n]));
      }
    }
    return out;
  }

  /// Primer paso en o después de [tick].
  static int indexAt(List<PracticeStep> steps, int tick) {
    var lo = 0;
    var hi = steps.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (steps[mid].tick < tick) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Qué pasó con una tecla en el modo espera.
enum PressResult {
  /// No había nada que esperar (se terminó).
  ignored,

  /// Una nota del acorde que ya se había tocado.
  repeat,

  /// Una nota correcta; faltan otras del mismo acorde.
  hit,

  /// Una nota que no va.
  miss,

  /// Con esta nota se completó el paso: se sigue.
  completed,
}

/// Modo espera: la música no sigue hasta que se tocan las notas del paso.
///
/// Las notas de un acorde no tienen que ir juntas: basta con tocarlas todas
/// (en cualquier orden) desde que el paso quedó pendiente. Una nota del paso
/// siguiente tocada un poco antes de terminar este (al encadenar acordes) se
/// cuenta para el siguiente, no como fallo.
class WaitGate {
  WaitGate(this.steps, {this.earlyMicros = 150000});

  final List<PracticeStep> steps;

  /// Cuánto antes de completar un paso puede llegar una nota del siguiente.
  final int earlyMicros;

  /// Índice del paso que se espera.
  int pending = 0;

  /// Alturas del paso pendiente ya tocadas.
  final Set<int> got = {};

  // Totales de la sesión.
  int hits = 0;
  int misses = 0;
  int stepsDone = 0;

  /// Pasos tocados sin ningún fallo mientras se esperaban.
  int cleanSteps = 0;

  /// Fallos por paso (su pulso desplegado).
  final Map<int, int> missesAt = {};

  // De la vuelta actual (desde el último [resetTo]).
  int passSteps = 0;
  int passClean = 0;

  int _stepMisses = 0;

  /// Fallos recientes: (altura, momento, pulso del paso en que fallaron).
  final List<(int, int, int)> _recent = [];

  PracticeStep? get current => pending < steps.length ? steps[pending] : null;

  /// Pulso en que hay que esperar, o null si ya no queda nada.
  int? get holdTick => current?.tick;

  bool get finished => pending >= steps.length;

  /// Ids de las notas del paso pendiente que faltan y de las ya tocadas.
  List<String> get waitingIds => current?.idsOf(current!.pitches.difference(got)) ?? const [];
  List<String> get gotIds => current?.idsOf(got) ?? const [];

  /// Se espera desde [tick] (al empezar, al saltar o al volver al inicio del
  /// bucle). Empieza una vuelta nueva; los totales siguen.
  void resetTo(int tick) {
    pending = PracticeStep.indexAt(steps, tick);
    got.clear();
    _stepMisses = 0;
    _recent.clear();
    passSteps = 0;
    passClean = 0;
  }

  /// Borra los totales (empezar de nuevo).
  void resetStats() {
    hits = misses = stepsDone = cleanSteps = 0;
    missesAt.clear();
  }

  PressResult press(int midi, int micros) {
    final step = current;
    if (step == null) return PressResult.ignored;
    if (got.contains(midi)) return PressResult.repeat;
    if (step.pitches.contains(midi)) {
      got.add(midi);
      hits++;
      if (got.length < step.pitches.length) return PressResult.hit;
      _complete(micros);
      return PressResult.completed;
    }
    misses++;
    _stepMisses++;
    missesAt[step.tick] = (missesAt[step.tick] ?? 0) + 1;
    _recent.add((midi, micros, step.tick));
    return PressResult.miss;
  }

  void _complete(int micros) {
    final next = pending + 1 < steps.length ? steps[pending + 1] : null;
    // Las que se adelantaron un poco y son del paso siguiente no eran fallos.
    final early = <int>{};
    for (final (m, at, tick) in _recent) {
      if (next == null || micros - at > earlyMicros || !next.pitches.contains(m) || early.contains(m)) continue;
      early.add(m);
      misses--;
      _stepMisses--;
      final c = missesAt[tick]! - 1;
      if (c == 0) {
        missesAt.remove(tick);
      } else {
        missesAt[tick] = c;
      }
    }
    _recent.clear();
    stepsDone++;
    passSteps++;
    if (_stepMisses == 0) {
      cleanSteps++;
      passClean++;
    }
    pending++;
    got.clear();
    _stepMisses = 0;
    if (next == null || early.isEmpty) return;
    got.addAll(early);
    hits += early.length;
    if (got.length == next.pitches.length) _complete(micros);
  }
}

/// Sigue a quien toca libremente, sin esperar ni marcar tempo: dónde va en
/// la partitura según las notas que toca, aunque se equivoque, repita o
/// salte a otra parte.
///
/// Es un modelo oculto de Markov sobre los pasos: con cada nota se pasa
/// (sobre todo) al paso siguiente, o se queda en el mismo si la nota llega
/// casi a la vez que la anterior (un acorde); cada paso explica mejor las
/// notas que contiene. Un salto a cualquier lugar es poco probable, pero
/// unas pocas notas que solo encajan allí bastan para reubicarse.
class ScoreFollower {
  ScoreFollower(this.steps) : _belief = List.filled(steps.length + 1, 0) {
    reset(0);
  }

  final List<PracticeStep> steps;

  /// Probabilidad de cada estado: 0 es "antes de empezar"; i + 1, el paso i.
  final List<double> _belief;

  int? _lastMicros;

  /// Paso en que se va (-1: todavía no se empezó).
  int position = -1;

  /// Dos notas más juntas que esto son del mismo acorde.
  static const int chordMicros = 70000;

  /// Se espera que la próxima nota sea la del paso [index].
  void reset(int index) {
    _belief.fillRange(0, _belief.length, 0);
    final state = index.clamp(0, steps.length);
    _belief[state] = 1;
    position = state - 1;
    _lastMicros = null;
  }

  /// Una nota tocada; devuelve el paso en que se va.
  int press(int midi, int micros) {
    final n = _belief.length;
    if (n <= 1) return position;
    final last = _lastMicros;
    final chord = last != null && micros - last < chordMicros;
    _lastMicros = micros;
    // Avance más probable: quedarse (0), el siguiente (1), saltarse uno…
    final moves = chord ? const [0.75, 0.2, 0.03] : const [0.12, 0.64, 0.12, 0.04];
    const back = 0.02;
    const jump = 0.002;
    final next = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final b = _belief[i];
      if (b < 1e-12) continue;
      for (var k = 0; k < moves.length; k++) {
        final j = i + k;
        if (j < n) next[j] += b * moves[k];
      }
      if (!chord && i > 1) next[i - 1] += b * back;
    }
    final uniform = jump / n;
    var total = 0.0;
    for (var j = 0; j < n; j++) {
      final v = (next[j] * (1 - jump) + uniform) * _emission(j, midi);
      next[j] = v;
      total += v;
    }
    var best = 0;
    for (var j = 0; j < n; j++) {
      _belief[j] = next[j] / total;
      if (_belief[j] > _belief[best]) best = j;
    }
    position = best - 1;
    return position;
  }

  double _emission(int state, int midi) {
    if (state == 0) return 0.01;
    final pitches = steps[state - 1].pitches;
    if (pitches.contains(midi)) return 1;
    // La misma nota en otra octava: casi seguro el mismo lugar.
    for (final p in pitches) {
      if (p % 12 == midi % 12) return 0.2;
    }
    return 0.02;
  }
}
