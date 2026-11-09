import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';

/// Metrónomo con cuenta previa. Suena en el piano por el canal de percusión
/// (cajas chinas de General MIDI: aguda en el primer pulso) y siempre se ve
/// en pantalla.
///
/// Los pulsos se programan sobre el mismo reloj con el que se marcan las
/// notas que llegan del piano, así la grabación sabe exactamente dónde cayó
/// cada pulso.
class Metronome extends ChangeNotifier {
  Metronome(this.midi);

  final MidiService midi;

  /// Sonar en el piano (si está conectado).
  bool sound = true;

  double bpm = 80;
  TimeSignature time = TimeSignature.common;

  /// Compases de cuenta antes de empezar a grabar.
  int countInMeasures = 1;

  bool get running => _timer != null;

  /// Instante (reloj del MIDI) del primer pulso de la cuenta.
  int startMicros = 0;

  /// Pulso actual desde el inicio de la cuenta (0 = primer pulso de la cuenta).
  int pulse = -1;

  Timer? _timer;
  int _nextPulse = 0;

  int get pulsesPerBar => pulsesPerMeasure(time);
  int get countInPulses => countInMeasures * pulsesPerBar;
  double get pulseMicros => 60e6 / bpm;

  /// Instante del primer compás grabado (tras la cuenta).
  int get downbeatMicros => startMicros + (countInPulses * pulseMicros).round();

  /// En la cuenta: cuántos pulsos faltan (3, 2, 1…); 0 ya grabando.
  int get countdown => pulse < 0 ? countInPulses : (pulse < countInPulses ? countInPulses - pulse : 0);

  /// Compás (1 = el primero grabado) y pulso dentro de él (0..).
  int get bar => pulse < countInPulses ? 0 : (pulse - countInPulses) ~/ pulsesPerBar + 1;
  int get beatInBar => pulse < 0 ? 0 : pulse % pulsesPerBar;

  void start() {
    stop();
    // Medio pulso de margen para programar el primero con exactitud.
    startMicros = midi.now.inMicroseconds + (pulseMicros / 2).round();
    _nextPulse = 0;
    pulse = -1;
    _timer = Timer.periodic(const Duration(milliseconds: 2), (_) => _tick());
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void _tick() {
    final now = midi.now.inMicroseconds;
    final due = startMicros + (_nextPulse * pulseMicros).round();
    if (now < due) return;
    pulse = _nextPulse++;
    if (sound && midi.connected != null) {
      final accent = pulse % pulsesPerBar == 0;
      final note = accent ? 76 : 77; // caja china aguda / grave
      midi.send([0x99, note, accent ? 110 : 80]);
      midi.send([0x89, note, 0]);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
