import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';

/// Reproduce la toma original tal cual se tocó (MIDI crudo, mismo tiempo) y
/// sabe qué acorde de la partitura suena en cada momento.
class SongPlayer extends ChangeNotifier {
  SongPlayer({required this.song, required this.midi});

  final Song song;
  final MidiService midi;

  /// Enviar las notas al piano conectado (si no, solo se ve).
  bool soundOnPiano = true;

  bool get canPlay => take != null && take!.events.isNotEmpty;
  Take? get take => song.takes.isEmpty ? null : song.takes.first;
  int get durationMicros => take?.durationMicros ?? 0;

  bool playing = false;
  int positionMicros = 0;

  final Stopwatch _clock = Stopwatch();
  int _startPosition = 0;
  int _nextEvent = 0;
  int? _lastChord;
  int _lastNotify = 0;
  Timer? _ticker;
  final Set<int> _sounding = {};

  /// Acorde que suena en la posición actual (null antes del primero).
  int? get chordIndex => chordAt(positionMicros);

  int? chordAt(int micros) {
    int? found;
    for (var i = 0; i < song.chords.length; i++) {
      final start = song.chords[i].startMicros;
      if (start == null) continue;
      if (start <= micros) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }

  void play() {
    if (!canPlay || playing) return;
    if (positionMicros >= durationMicros) positionMicros = 0;
    playing = true;
    _startPosition = positionMicros;
    _nextEvent = take!.events.indexWhere((e) => e.timeMicros >= positionMicros);
    if (_nextEvent < 0) _nextEvent = take!.events.length;
    _clock
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 4), (_) => _tick());
    notifyListeners();
  }

  void pause() {
    if (!playing) return;
    _ticker?.cancel();
    _clock.stop();
    playing = false;
    _silence();
    notifyListeners();
  }

  void toggle() => playing ? pause() : play();

  /// Ir a un instante (p. ej. al tocar un acorde de la partitura).
  void seek(int micros) {
    final wasPlaying = playing;
    pause();
    positionMicros = micros.clamp(0, durationMicros);
    notifyListeners();
    if (wasPlaying) play();
  }

  void restart() => seek(0);

  void _tick() {
    final events = take!.events;
    positionMicros = _startPosition + _clock.elapsedMicroseconds;
    while (_nextEvent < events.length && events[_nextEvent].timeMicros <= positionMicros) {
      _emit(events[_nextEvent]);
      _nextEvent++;
    }
    if (_nextEvent >= events.length) {
      positionMicros = durationMicros;
      pause();
      return;
    }
    // Se avisa a la pantalla al cambiar de acorde y unas 10 veces por segundo.
    final chord = chordIndex;
    if (chord != _lastChord || positionMicros - _lastNotify > 100000) {
      _lastChord = chord;
      _lastNotify = positionMicros;
      notifyListeners();
    }
  }

  void _emit(MidiEvent e) {
    if (e.isNoteOn) {
      _sounding.add(e.data1);
    } else if (e.isNoteOff) {
      _sounding.remove(e.data1);
    }
    if (soundOnPiano && (e.isNote || e.isSustain)) midi.send([e.status, e.data1, e.data2]);
  }

  /// Apaga lo que esté sonando en el piano (al pausar, saltar o salir).
  void _silence() {
    if (!soundOnPiano) {
      _sounding.clear();
      return;
    }
    for (final note in _sounding) {
      midi.send([0x80, note, 0]);
    }
    _sounding.clear();
    midi.send([0xB0, MidiEvent.sustainController, 0]);
    midi.send([0xB0, 123, 0]); // All notes off
  }

  @override
  void dispose() {
    pause();
    _ticker?.cancel();
    super.dispose();
  }
}
