import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scale/analysis/chord_engine.dart';
import 'package:scale/midi/midi_service.dart';
import 'package:scale/midi/take_capture.dart';
import 'package:scale/settings.dart';

void main() {
  late Directory dir;
  late MidiService midi;
  late ChordEngine engine;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('scale_capture');
    midi = MidiService();
    engine = ChordEngine(midi, AppSettings(File('${dir.path}/settings.json')));
  });

  tearDown(() async {
    engine.dispose();
    await dir.delete(recursive: true);
  });

  MidiInput note(int ms, int key, int velocity, {bool on = true}) => MidiInput(
        time: Duration(milliseconds: ms),
        kind: on ? MidiInputKind.noteOn : MidiInputKind.noteOff,
        channel: 0,
        data1: key,
        data2: velocity,
      );

  test('guarda las notas con su fuerza y tiempos relativos', () async {
    final capture = TakeCapture(engine);
    midi.debugInject(note(1000, 60, 33));
    midi.debugInject(note(1250, 64, 101));
    midi.debugInject(note(1600, 60, 0, on: false));
    await Future<void>.delayed(Duration.zero);
    final take = capture.take('Coro')!;
    expect(take.partial, isTrue);
    expect(take.label, 'Coro');
    expect([for (final e in take.events) (e.timeMicros, e.data1, e.data2)], [
      (0, 60, 33),
      (250000, 64, 101),
      (600000, 60, 0),
    ]);
    capture.dispose();
  });

  test('inactiva no guarda; empezar de nuevo descarta', () async {
    final capture = TakeCapture(engine, active: false);
    midi.debugInject(note(0, 60, 80));
    await Future<void>.delayed(Duration.zero);
    expect(capture.take('x'), isNull);
    capture.active = true;
    midi.debugInject(note(10, 62, 80));
    await Future<void>.delayed(Duration.zero);
    capture.restart();
    expect(capture.take('x'), isNull);
    capture.dispose();
  });
}
