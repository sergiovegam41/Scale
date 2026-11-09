import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';

/// Reproduce una partitura por el piano (MIDI de salida) y lleva la posición
/// para el cursor del visor.
///
/// Dos formas de oírla: como está escrita (a tempo, con la fuerza de cada
/// nota o de sus dinámicas) o, si salió de una grabación, como se tocó (la
/// toma original, con su tempo, sus respiraciones y su fuerza; el cursor la
/// sigue igual).
///
/// Sin piano conectado avanza igual, en silencio: el cursor sigue moviéndose.
class ScorePlayer extends ChangeNotifier {
  ScorePlayer(this.midi, this.timeline);

  final MidiService midi;
  ScoreTimeline timeline;

  ScoreRecording? get recording => timeline.score.recording;
  bool get canPlayAsPlayed => recording != null;

  /// Reproducir la toma original en vez de la partitura escrita.
  bool get asPlayed => _asPlayed && canPlayAsPlayed;
  bool _asPlayed = false;
  set asPlayed(bool v) {
    if (v == _asPlayed) return;
    final wasPlaying = playing;
    final tick = _tick;
    pause();
    _asPlayed = v;
    seek(tick);
    if (wasPlaying) play();
  }

  /// Velocidad relativa al tempo (1 = original).
  double get speed => _speed;
  double _speed = 1;
  set speed(double v) {
    final s = v.clamp(0.25, 2.0).toDouble();
    if (s == _speed) return;
    if (playing) {
      // Mantiene la posición actual al cambiar de velocidad.
      _anchorMicros = _nowMicros;
      _clock
        ..reset()
        ..start();
    }
    _speed = s;
    notifyListeners();
  }

  /// Pentagramas silenciados, como (parte, pentagrama): en piano a dos
  /// pentagramas, (0, 1) es la mano derecha y (0, 2) la izquierda. (Al oír
  /// la toma original suena todo.)
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

  /// Microsegundos (de la partitura a tempo, o de la toma) al darle a play.
  double _anchorMicros = 0;
  Timer? _timer;
  int _next = 0;
  final List<PlayedNote> _active = [];
  final Set<int> _sounding = {};
  bool _pedal = false;

  double get _nowMicros => _anchorMicros + _clock.elapsedMicroseconds * _speed;

  int get _pickup {
    final first = timeline.score.measures.firstOrNull;
    return first != null && first.implicit ? first.length : 0;
  }

  int _tickAt(double micros) => asPlayed
      ? recording!.tickAt(micros.round(), _pickup).floor().clamp(0, timeline.lengthTicks)
      : timeline.tickAtMicros(micros);

  double _microsAt(int tick) {
    if (!asPlayed) return timeline.microsAt(tick);
    final r = recording!;
    final m = (tick - _pickup) / ticksPerQuarter * r.settings.quarterMicros + r.settings.startMicros + r.appliedLatencyMicros;
    return m < 0 ? 0 : m;
  }

  double get _endMicros => asPlayed ? recording!.take.durationMicros.toDouble() : timeline.microsAt(timeline.lengthTicks);

  /// Compás desplegado actual y su número escrito.
  PlayedMeasure get measure => timeline.order[timeline.playedMeasureAt(_tick)];
  String get measureNumber => timeline.score.measures[measure.index].number;

  Duration get position => Duration(microseconds: (_microsAt(_tick) / _speed).round());
  Duration get duration => Duration(microseconds: (_endMicros / _speed).round());

  void toggle() => playing ? pause() : play();

  void play({int? from}) {
    if (from != null) seek(from);
    if (_tick >= timeline.lengthTicks) seek(0);
    _anchorMicros = _microsAt(_tick);
    // La toma desde el principio incluye la cuenta (y la anacrusa).
    if (asPlayed && _tick == 0) _anchorMicros = 0;
    _next = asPlayed ? _rawIndexAt(_anchorMicros) : _firstAtOrAfter(_tick);
    _lastNotifyMs = 0;
    _clock
      ..reset()
      ..start();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 4), (_) => asPlayed ? _pumpRaw() : _pump());
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
    final wasPlaying = playing;
    if (wasPlaying) {
      _timer?.cancel();
      _timer = null;
    }
    _allOff();
    _tick = tick.clamp(0, timeline.lengthTicks);
    _setLit(_litAt(_tick));
    if (wasPlaying) {
      play();
    } else {
      notifyListeners();
    }
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

  int _rawIndexAt(double micros) {
    final events = recording!.take.events;
    final i = events.indexWhere((e) => e.timeMicros >= micros);
    return i < 0 ? events.length : i;
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

  /// Las notas escritas que suenan en [tick], la más reciente primero.
  List<String> _soundingAt(int tick) {
    final out = <PlayedNote>[];
    for (final n in timeline.notes) {
      if (n.start > tick) break;
      if (n.end > tick) out.add(n);
    }
    out.sort((a, b) => b.start.compareTo(a.start));
    return [for (final n in out) n.noteId];
  }

  void _pump() {
    final tick = _tickAt(_nowMicros);
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
    _maybeNotify();
  }

  /// La toma original: cada mensaje tal como llegó (nota, fuerza y pedal).
  void _pumpRaw() {
    final now = _nowMicros;
    final events = recording!.take.events;
    final connected = midi.connected != null;
    var changed = false;
    while (_next < events.length && events[_next].timeMicros <= now) {
      final e = events[_next++];
      if (e.channel == 9) continue; // el metrónomo, si quedó en la toma
      if (e.isNoteOn) {
        if (connected) {
          if (_sounding.contains(e.data1)) midi.send([0x80, e.data1, 0]);
          midi.send([e.status, e.data1, e.data2]);
        }
        _sounding.add(e.data1);
        changed = true;
      } else if (e.isNoteOff) {
        if (_sounding.remove(e.data1) && connected) midi.send([0x80 | e.channel, e.data1, 0]);
      } else if (e.isSustain) {
        _pedal = e.sustainDown;
        if (connected) midi.send([e.status, e.data1, e.data2]);
      }
    }
    final tick = _tickAt(now);
    if (changed || tick != _tick) {
      _tick = tick;
      final ids = _soundingAt(tick);
      if (ids.isNotEmpty || changed) _setLit(ids);
    }
    if (_next >= events.length) {
      pause();
      _tick = timeline.lengthTicks;
      return;
    }
    _maybeNotify();
  }

  void _maybeNotify() {
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
    midi.send([0x90, n.midi, n.velocity.clamp(1, 127)]);
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
    if (midi.connected != null) {
      for (final m in _sounding) {
        midi.send([0x80, m, 0]);
      }
      if (_pedal) midi.send([0xB0, MidiEvent.sustainController, 0]);
    }
    _pedal = false;
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
