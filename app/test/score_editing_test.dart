import 'package:flutter_test/flutter_test.dart';
import 'package:scale/midi/midi_service.dart';
import 'package:scale/score/score_editing.dart';
import 'package:scale_core/scale_core.dart';

import 'score_practice_test.dart' show twoHands;

void main() {
  late MidiService midi;
  late Score original;
  late ScoreEditing editing;
  var clock = 0;

  void send(MidiInputKind kind, int note) {
    clock += 50000;
    midi.debugInject(
      MidiInput(
        time: Duration(microseconds: clock),
        kind: kind,
        channel: 0,
        data1: note,
        data2: 80,
      ),
    );
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() {
    midi = MidiService();
    original = twoHands();
    editing = ScoreEditing(midi, original);
  });

  tearDown(() => editing.dispose());

  test('se corrige sobre una copia', () {
    editing.select('nr0', play: false);
    editing.apply(() => editing.editor.transpose('nr0', 1));
    expect(editing.score.parts.first.events.first.notes.first.midi, 61);
    expect(original.parts.first.events.first.notes.first.midi, 60);
    expect(editing.editor.dirty, isTrue);
  });

  test('una tecla cambia la nota elegida y pasa a la siguiente', () async {
    editing.select('nr1', play: false);
    send(MidiInputKind.noteOn, 63);
    send(MidiInputKind.noteOff, 63);
    await settle();
    expect(editing.editor.locate('nr1')!.note!.midi, 63);
    expect(editing.selected, 'nr2');
  });

  test('un acorde se aplica al soltar todas las teclas', () async {
    editing.select('nr3', play: false);
    send(MidiInputKind.noteOn, 65);
    send(MidiInputKind.noteOn, 69);
    send(MidiInputKind.noteOff, 65);
    await settle();
    // Todavía hay una tecla abajo: no se aplica.
    expect(editing.editor.canUndo, isFalse);
    send(MidiInputKind.noteOff, 69);
    await settle();
    expect([for (final n in editing.editor.locate('nr3')!.event.notes) n.midi], [65, 69]);
  });

  test('sin nota elegida avisa', () async {
    String? said;
    editing.onError = (m) => said = m;
    send(MidiInputKind.noteOn, 60);
    send(MidiInputKind.noteOff, 60);
    await settle();
    expect(said, contains('Primero'));
  });

  test('deshacer conserva lo elegido si sigue existiendo', () {
    editing.select('nr2', play: false);
    editing.apply(() => editing.editor.delete('nr2'), play: false);
    expect(editing.selected, 'r2');
    editing.undo();
    expect(editing.selected, 'r2');
    expect(editing.location!.note!.midi, 64);
    editing.redo();
    editing.select('nr3', play: false);
    editing.apply(() => editing.editor.addNote('nr3', 69), play: false);
    final added = editing.selected!;
    editing.undo();
    expect(editing.editor.locate(added), isNull);
    expect(editing.selected, isNull);
  });
}
