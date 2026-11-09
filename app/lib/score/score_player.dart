import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';

/// Reproduce una partitura por el piano (MIDI de salida) y lleva la posición
/// para el cursor del visor.
///
/// Sin piano conectado avanza igual, en silencio: el cursor sigue moviéndose.
class ScorePlayer extends ChangeNotifier {
  ScorePlayer(this.midi, this.timeline);

  final MidiService midi;
  ScoreTimeline timeline;

  /// Velocidad relativa al tempo escrito (1 = original).
  double get speed => _speed;
  double _speed = 1;
  set speed(double v) {
    final s = v.clamp(0.25, 2.0).toDouble();
    if (s == _speed) return;
    if (playing) {
      // Mantiene la posición actual al cambiar de velocidad.
      _anchorMicros = _scoreMicros;
      _clock
        ..reset()
        ..start();
    }
    _speed = s;
    notifyListeners();
  }

  /// Pentagramas silenciados, como (parte, pentagrama): en piano a dos
  /// pentagramas, (0, 1) es la mano derecha y (0, 2) la izquierda.
  final Set<(int, int)> muted = {};

  bool _muted(PlayedNote n) => muted.contains((n.part, n.staff));

  bool get playing => _timer != null;

  /// Posición en pulsos desplegados.
  int get tick => _tick;
  int _tick = 0;

  /// Ids de las notas que suenan ahora (para resaltarlas). Avisa al cambiar,
  /// sin esperar al aviso general (que va más espaciado).
  final ValueNotifier<List<String>> lit = ValueNotifier(const []);
  int _lastNotifyMs = 0;

  final Stopwatch _clock = Stopwatch();
  double _anchorMicros = 0;
  Timer? _timer;
  int _next = 0;
  final List<PlayedNote> _active = [];
  final Set<int> _sounding = {};

  double get _scoreMicros => _anchorMicros + _clock.elapsedMicroseconds * _speed;

  /// Compás desplegado actual y su número escrito.
  PlayedMeasure get measure => timeline.order[timeline.playedMeasureAt(_tick)];
  String get measureNumber => timeline.score.measures[measure.index].number;

  Duration get position => Duration(microseconds: (timeline.microsAt(_tick) / _speed).round());
  Duration get duration => Duration(microseconds: (timeline.microsAt(timeline.lengthTicks) / _speed).round());

  void toggle() => playing ? pause() : play();

  void play({int? from}) {
    if (from != null) seek(from);
    if (_tick >= timeline.lengthTicks) seek(0);
    _anchorMicros = timeline.microsAt(_tick);
    _lastNotifyMs = 0;
    _clock
      ..reset()
      ..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 4), (_) => _pump());
    _pump();
    notifyListeners();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
    _allOff();
    notifyListeners();
  }

  /// Vuelve al principio.
  void stop() {
    pause();
    seek(0);
  }

  /// Salta a [tick] (desplegado). Si está sonando, sigue desde ahí.
  void seek(int tick) {
    _allOff();
    _tick = tick.clamp(0, timeline.lengthTicks);
    _next = _firstAtOrAfter(_tick);
    _anchorMicros = timeline.microsAt(_tick);
    _clock
      ..reset()
      ..start();
    if (!playing) _clock.stop();
    _setLit(_litAt(_tick));
    notifyListeners();
  }

  int _firstAtOrAfter(int tick) {
    var lo = 0;
    var hi = timeline.notes.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (timeline.notes[mid].start < tick) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Lo que se ve al estar parado en [tick]: las notas que empiezan ahí (o
  /// las siguientes).
  List<String> _litAt(int tick) {
    final i = _firstAtOrAfter(tick);
    if (i >= timeline.notes.length) return const [];
    final start = timeline.notes[i].start;
    return [
      for (var j = i; j < timeline.notes.length && timeline.notes[j].start == start; j++) timeline.notes[j].noteId,
    ];
  }

  void _pump() {
    final tick = timeline.tickAtMicros(_scoreMicros);
    _tick = tick;
    final notes = timeline.notes;
    var changed = false;
    // Primero se apagan las que terminan (una nota repetida debe volver a sonar).
    for (var i = _active.length - 1; i >= 0; i--) {
      final n = _active[i];
      if (n.end <= tick) {
        _off(n);
        _active.removeAt(i);
        changed = true;
      }
    }
    while (_next < notes.length && notes[_next].start <= tick) {
      final n = notes[_next++];
      if (n.end <= tick) continue; // se pasó (por ejemplo, tras una pausa larga)
      _on(n);
      _active.add(n);
      changed = true;
    }
    if (changed) {
      // La más reciente primero: el cursor va a la nota que acaba de empezar.
      _setLit([for (final n in _active.reversed) n.noteId]);
    }
    if (tick >= timeline.lengthTicks && _active.isEmpty) {
      pause();
      _tick = timeline.lengthTicks;
      return;
    }
    // El reloj y el compás en pantalla no necesitan más de ~10 avisos por segundo.
    final ms = _clock.elapsedMilliseconds;
    if (ms - _lastNotifyMs >= 100 || ms < _lastNotifyMs) {
      _lastNotifyMs = ms;
      notifyListeners();
    }
  }

  void _on(PlayedNote n) {
    if (_muted(n) || midi.connected == null) return;
    if (_sounding.contains(n.midi)) midi.send([0x80, n.midi, 0]);
    midi.send([0x90, n.midi, 78]);
    _sounding.add(n.midi);
  }

  void _off(PlayedNote n) {
    if (!_sounding.remove(n.midi)) return;
    // Otra nota igual sigue sonando (dos voces en unísono): no se corta.
    if (_active.any((a) => !identical(a, n) && a.midi == n.midi && !_muted(a))) {
      _sounding.add(n.midi);
      return;
    }
    midi.send([0x80, n.midi, 0]);
  }

  void _allOff() {
    for (final m in _sounding) {
      midi.send([0x80, m, 0]);
    }
    _sounding.clear();
    _active.clear();
  }

  void _setLit(List<String> ids) {
    if (listEquals(ids, lit.value)) return;
    lit.value = ids;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _allOff();
    lit.dispose();
    super.dispose();
  }
}
