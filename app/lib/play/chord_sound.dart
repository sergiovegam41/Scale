import 'dart:async';

import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';

/// Hace sonar un acorde en el piano por el cable MIDI (para escucharlo al
/// tocarlo en las herramientas).
class ChordSound {
  ChordSound(this.midi);

  final MidiService midi;
  final List<Timer> _timers = [];
  final Set<int> _sounding = {};

  /// Devuelve false si el piano no está conectado.
  bool play(Chord chord) {
    if (midi.connected == null) return false;
    stop();
    // Bajo en la segunda octava y el acorde cerrado en la del medio.
    final bass = 40 + ((chord.bass ?? chord.root) - 4) % 12;
    final top = 55 + (chord.root - 7) % 12;
    final notes = [bass, for (final i in chord.quality.intervals) top + i];
    for (final (i, n) in notes.indexed) {
      _timers.add(Timer(Duration(milliseconds: i * 18), () {
        midi.send([0x90, n, i == 0 ? 80 : 70]);
        _sounding.add(n);
      }));
    }
    _timers.add(Timer(const Duration(milliseconds: 1600), stop));
    return true;
  }

  void stop() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final n in _sounding) {
      midi.send([0x80, n, 0]);
    }
    _sounding.clear();
  }

  void dispose() => stop();
}
