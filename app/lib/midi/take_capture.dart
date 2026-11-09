import 'dart:async';

import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import 'midi_service.dart';

/// Guarda en bruto lo que se toca (notas con su fuerza, pedal y tiempos
/// exactos) mientras [active] está encendido, para conservar la toma de una
/// sección grabada en el editor aunque de ella solo se usen los acordes.
class TakeCapture {
  TakeCapture(this.engine, {this.active = true}) {
    _sub = engine.midi.events.listen(_onInput);
  }

  final ChordEngine engine;

  /// Solo se guarda lo que llega con la captura activa.
  bool active;

  late final StreamSubscription<MidiInput> _sub;
  final List<MidiEvent> _events = [];
  int? _startMicros;
  DateTime? _startedAt;

  bool get hasNotes => _events.any((e) => e.isNoteOn);

  /// Descarta lo capturado (empezar de nuevo).
  void restart() {
    _events.clear();
    _startMicros = null;
    _startedAt = null;
  }

  void _onInput(MidiInput input) {
    if (!active) return;
    final e = input.toMidiEvent();
    final start = _startMicros ??= e.timeMicros;
    _startedAt ??= DateTime.now();
    _events.add(MidiEvent(e.timeMicros - start, e.status, e.data1, e.data2));
  }

  /// La toma parcial con lo capturado, o null si no se tocó ninguna nota.
  Take? take(String label) {
    if (!hasNotes) return null;
    return Take(
      id: Song.newId(),
      recordedAt: _startedAt ?? DateTime.now(),
      events: List.of(_events),
      inputTranspose: engine.inputTranspose,
      partial: true,
      label: label,
    );
  }

  void dispose() => _sub.cancel();
}
