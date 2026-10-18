import 'dart:async';

import 'package:flutter/foundation.dart';

import 'midi_service.dart';

/// Estado visible del teclado: teclas presionadas, sostenidas por pedal
/// y un registro de los últimos mensajes.
class KeyboardState extends ChangeNotifier {
  KeyboardState(Stream<MidiInput> events) {
    _sub = events.listen(_onInput);
  }

  static const int sustainController = 64;
  static const int maxLog = 40;

  late final StreamSubscription<MidiInput> _sub;

  /// Nota → velocidad, para teclas físicamente presionadas.
  final Map<int, int> held = {};

  /// Notas soltadas que siguen sonando por el pedal.
  final Set<int> sustained = {};

  bool pedalDown = false;
  int? lastVelocity;
  int messageCount = 0;
  final List<MidiInput> log = [];

  void _onInput(MidiInput input) {
    messageCount++;
    log.insert(0, input);
    if (log.length > maxLog) log.removeLast();

    switch (input.kind) {
      case MidiInputKind.noteOn:
        held[input.data1] = input.data2;
        sustained.remove(input.data1);
        lastVelocity = input.data2;
      case MidiInputKind.noteOff:
        if (held.remove(input.data1) != null && pedalDown) {
          sustained.add(input.data1);
        }
      case MidiInputKind.controlChange:
        if (input.data1 == sustainController) {
          pedalDown = input.data2 >= 64;
          if (!pedalDown) sustained.clear();
        }
    }
    notifyListeners();
  }

  void clear() {
    held.clear();
    sustained.clear();
    log.clear();
    messageCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
