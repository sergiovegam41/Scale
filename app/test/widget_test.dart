import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scale/midi/keyboard_state.dart';
import 'package:scale/midi/midi_service.dart';

void main() {
  test('el pedal sostiene las notas soltadas', () async {
    final events = StreamController<MidiInput>();
    final state = KeyboardState(events.stream);
    MidiInput msg(MidiInputKind kind, int d1, int d2) =>
        MidiInput(time: Duration.zero, kind: kind, channel: 0, data1: d1, data2: d2);

    events
      ..add(msg(MidiInputKind.controlChange, 64, 127))
      ..add(msg(MidiInputKind.noteOn, 60, 90))
      ..add(msg(MidiInputKind.noteOff, 60, 0));
    await Future<void>.delayed(Duration.zero);
    expect(state.held, isEmpty);
    expect(state.sustained, {60});

    events.add(msg(MidiInputKind.controlChange, 64, 0));
    await Future<void>.delayed(Duration.zero);
    expect(state.sustained, isEmpty);
    expect(state.pedalDown, isFalse);
  });
}
