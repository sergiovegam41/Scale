import 'package:flutter_test/flutter_test.dart';
import 'package:scale/midi/midi_service.dart';
import 'package:scale/score/score_player.dart';
import 'package:scale/score/score_practice.dart';
import 'package:scale_core/scale_core.dart';

/// Dos compases de 4/4 a 240: derecha Do Re Mi Fa | Sol La Si Do, izquierda
/// redondas Do | Sol.
Score twoHands() {
  final right = [60, 62, 64, 65, 67, 69, 71, 72];
  final events = <ScoreEvent>[
    for (final (i, m) in right.indexed)
      ScoreEvent(
        id: 'r$i',
        tick: i * ticksPerQuarter,
        duration: ticksPerQuarter,
        staff: 1,
        voice: 1,
        notes: [ScoreNote(id: 'nr$i', midi: m, spelling: SpelledNote.byDefault(m % 12), octave: 4)],
        type: NoteType.quarter,
      ),
    for (final (i, m) in [48, 43].indexed)
      ScoreEvent(
        id: 'l$i',
        tick: i * 4 * ticksPerQuarter,
        duration: 4 * ticksPerQuarter,
        staff: 2,
        voice: 5,
        notes: [ScoreNote(id: 'nl$i', midi: m, spelling: SpelledNote.byDefault(m % 12), octave: 2)],
        type: NoteType.whole,
      ),
  ];
  return Score(
    id: 's',
    title: 'Prueba',
    measures: [
      for (var m = 0; m < 2; m++)
        Measure(
          number: '${m + 1}',
          tick: m * 4 * ticksPerQuarter,
          length: 4 * ticksPerQuarter,
          time: TimeSignature.common,
          fifths: 0,
          tempo: m == 0 ? 240 : null,
        ),
    ],
    parts: [ScorePart(id: 'P1', name: 'Piano', staves: 2, events: events)],
  );
}

const _q = ticksPerQuarter;

void main() {
  late MidiService midi;
  late ScorePlayer player;
  late ScorePractice practice;
  var clock = 0;

  void key(int note) {
    clock += 400000;
    midi.debugInject(
      MidiInput(time: Duration(microseconds: clock), kind: MidiInputKind.noteOn, channel: 0, data1: note, data2: 80),
    );
  }

  Future<void> settle([int ms = 300]) => Future<void>.delayed(Duration(milliseconds: ms));

  setUp(() {
    midi = MidiService();
    player = ScorePlayer(midi, ScoreTimeline.of(twoHands()));
    practice = ScorePractice(player);
  });

  tearDown(() {
    practice.dispose();
    player.dispose();
  });

  test('esperar: la música se detiene en cada nota de la mano que se practica', () async {
    practice
      ..setMode(PracticeMode.wait)
      ..setHand((0, 1));
    expect(player.silent, {(0, 1)});
    expect(player.lit.value, ['nr0']);
    expect(player.playing, isFalse);

    // Tocar la primera nota la pone en marcha; se detiene en la segunda.
    key(60);
    await settle();
    expect(player.playing, isTrue);
    expect(player.waiting, isTrue);
    expect(player.tick, _q);
    expect(player.lit.value, ['nr1']);

    // Una equivocada no avanza.
    key(70);
    await settle(100);
    expect(practice.misses.value, 1);
    expect(player.tick, _q);

    key(62);
    await settle();
    expect(player.tick, 2 * _q);
    expect(practice.gate!.hits, 2);
  });

  test('esperar: si se toca antes de que la música llegue, la alcanza', () async {
    practice
      ..setMode(PracticeMode.wait)
      ..setHand((0, 1));
    player.speed = 0.25; // una negra por segundo
    key(60);
    await settle(50);
    key(62);
    key(64);
    await settle(50);
    expect(player.tick, greaterThanOrEqualTo(2 * _q));
    expect(practice.gate!.pending, 3);
  });

  test('esperar: al terminar da un resumen con dónde se falló', () async {
    practice.setMode(PracticeMode.wait);
    // Las dos manos: el primer paso es Do grave y Do central juntos.
    key(48);
    key(60);
    for (final m in [62, 64, 65]) {
      key(m);
    }
    key(66); // fallo en el compás 2
    for (final m in [43, 67, 69, 71, 72]) {
      key(m);
    }
    await settle(50);
    final s = practice.summary.value!;
    expect(s.text, contains('Terminaste'));
    expect(s.text, contains('compás 2'));
    expect(s.review, 1);
  });

  test('seguirme: la partitura va donde se toca, sin sonar', () async {
    practice.setMode(PracticeMode.follow);
    expect(player.gate, same(practice));
    key(48);
    await settle(10);
    for (final m in [62, 64, 65, 67]) {
      key(m);
      await settle(10);
    }
    expect(player.playing, isFalse);
    expect(player.tick, 4 * _q);
    expect(player.measureNumber, '2');
    expect(player.lit.value, ['nl1', 'nr4']);
  });

  test('salir de la práctica deja todo como estaba', () {
    practice
      ..setMode(PracticeMode.wait)
      ..setHand((0, 2))
      ..setMode(PracticeMode.off);
    expect(player.gate, isNull);
    expect(player.silent, isEmpty);
  });
}
