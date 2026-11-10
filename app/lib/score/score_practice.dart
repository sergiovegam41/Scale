import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';
import 'score_player.dart';

/// Cómo se practica con la partitura.
enum PracticeMode {
  /// Solo escuchar (sin práctica).
  off,

  /// La música avanza a tempo, pero espera en cada nota hasta que se toque.
  wait,

  /// Tocar libremente: la partitura sigue a quien toca (pasa las páginas).
  follow,
}

/// Resultado de una vuelta del bucle o de la pieza entera.
class PracticeSummary {
  const PracticeSummary(this.text, {this.review});

  final String text;

  /// Compás desplegado donde más se falló, para repasarlo.
  final int? review;
}

/// Tocar con la partitura: escucha el teclado y mueve la reproducción.
///
/// En el modo espera hace de [PlaybackGate] del reproductor: la otra mano
/// (si se practica una) suena desde la app y la música se detiene en cada
/// paso hasta que se tocan sus notas. En el modo seguir no suena nada: la
/// posición sale de lo que se toca.
class ScorePractice extends ChangeNotifier implements PlaybackGate {
  ScorePractice(this.player) {
    _sub = player.midi.events.listen(_onInput);
  }

  final ScorePlayer player;
  late final StreamSubscription<MidiInput> _sub;

  PracticeMode get mode => _mode;
  PracticeMode _mode = PracticeMode.off;

  /// Pentagrama que toca quien practica, como (parte, pentagrama), o null
  /// para todos (las dos manos).
  (int, int)? get hand => _hand;
  (int, int)? _hand;

  List<PracticeStep> steps = const [];
  WaitGate? _gate;
  ScoreFollower? _follower;

  WaitGate? get gate => _gate;

  /// Paso en que va el seguimiento libre (-1 antes de empezar).
  int get followPosition => _follower?.position ?? -1;

  /// Notas del paso ya tocadas (en verde).
  final ValueNotifier<List<String>> done = ValueNotifier(const []);

  /// Cuenta de notas equivocadas (para un destello en pantalla).
  final ValueNotifier<int> misses = ValueNotifier(0);

  /// Resumen al terminar una vuelta del bucle o la pieza.
  final ValueNotifier<PracticeSummary?> summary = ValueNotifier(null);

  bool _moving = false;

  void setMode(PracticeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    _rebuild(resetStats: true);
  }

  void setHand((int, int)? hand) {
    if (hand == _hand) return;
    _hand = hand;
    _rebuild(resetStats: true);
  }

  /// La partitura cambió (se volvió a escribir).
  void refresh() => _rebuild(resetStats: true);

  /// Empezar de nuevo: al principio (del bucle), sin aciertos ni fallos.
  void restart() {
    player.stop();
    _gate?.resetStats();
    _follower?.reset(PracticeStep.indexAt(steps, player.tick));
    _show();
    notifyListeners();
  }

  void _rebuild({required bool resetStats}) {
    final hand = _hand;
    steps = _mode == PracticeMode.off
        ? const []
        : PracticeStep.of(player.timeline, include: hand == null ? null : (n) => (n.part, n.staff) == hand);
    player.silent.clear();
    _gate = null;
    _follower = null;
    done.value = const [];
    switch (_mode) {
      case PracticeMode.off:
        player.gate = null;
      case PracticeMode.wait:
        player.pause();
        player.asPlayed = false;
        player.silent.addAll({
          for (final s in steps)
            for (final n in s.notes) (n.part, n.staff),
        });
        _gate = WaitGate(steps)..resetTo(player.tick);
        player.gate = this;
      case PracticeMode.follow:
        player.pause();
        _follower = ScoreFollower(steps)..reset(PracticeStep.indexAt(steps, player.tick));
        player.gate = this;
    }
    _show();
    notifyListeners();
  }

  // PlaybackGate

  @override
  int? get holdTick => _gate?.holdTick;

  @override
  void moved(int tick, {required bool loop}) {
    if (_moving) return;
    final gate = _gate;
    if (gate != null) {
      if (loop && gate.passSteps > 0) {
        summary.value = PracticeSummary(
          'Vuelta terminada: ${gate.passClean} de ${gate.passSteps} a la primera.',
        );
      }
      gate.resetTo(tick);
    }
    _follower?.reset(PracticeStep.indexAt(steps, tick));
    _show();
    notifyListeners();
  }

  void _onInput(MidiInput input) {
    if (input.kind != MidiInputKind.noteOn || input.channel == 9) return;
    final micros = input.time.inMicroseconds;
    switch (_mode) {
      case PracticeMode.off:
        return;
      case PracticeMode.wait:
        final gate = _gate!;
        final before = gate.pending;
        final result = gate.press(input.data1, micros);
        if (result == PressResult.miss) misses.value++;
        if (gate.pending != before) {
          // Se completó el paso (quizá antes de que la música llegara).
          player.catchUp(gate.steps[gate.pending - 1].tick);
          if (gate.finished) _finish(gate);
        }
      case PracticeMode.follow:
        final f = _follower!;
        final before = f.position;
        final pos = f.press(input.data1, micros);
        if (pos >= 0 && pos != before) {
          _moving = true;
          player.seek(steps[pos].tick);
          _moving = false;
        }
    }
    _show();
    notifyListeners();
  }

  void _finish(WaitGate gate) {
    final timeline = player.timeline;
    final byMeasure = <int, int>{};
    gate.missesAt.forEach((tick, n) {
      final m = timeline.playedMeasureAt(tick);
      byMeasure[m] = (byMeasure[m] ?? 0) + n;
    });
    final worst = byMeasure.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    String number(int played) => timeline.score.measures[timeline.order[played].index].number;
    final pct = gate.stepsDone == 0 ? 100 : (100 * gate.cleanSteps / gate.stepsDone).round();
    final review = worst.take(3).map((e) => number(e.key)).toList();
    summary.value = PracticeSummary(
      'Terminaste: $pct % a la primera (${gate.cleanSteps} de ${gate.stepsDone})'
      '${gate.misses == 0 ? ', sin fallos.' : ', ${gate.misses} ${gate.misses == 1 ? 'nota equivocada' : 'notas equivocadas'}.'}'
      '${review.isEmpty ? '' : ' Para repasar: ${review.length == 1 ? 'compás' : 'compases'} ${review.join(', ')}.'}',
      review: worst.isEmpty ? null : worst.first.key,
    );
  }

  /// Lo que se resalta: en espera, lo que falta del paso (azul) y lo ya
  /// tocado (verde); siguiendo, el paso en que se va.
  void _show() {
    switch (_mode) {
      case PracticeMode.off:
        done.value = const [];
      case PracticeMode.wait:
        final gate = _gate!;
        player.lit.value = gate.waitingIds;
        done.value = gate.gotIds;
      case PracticeMode.follow:
        final pos = followPosition;
        if (pos >= 0 && pos < steps.length) player.lit.value = steps[pos].ids;
        done.value = const [];
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    if (identical(player.gate, this)) player.gate = null;
    player.silent.clear();
    done.dispose();
    misses.dispose();
    summary.dispose();
    super.dispose();
  }
}
