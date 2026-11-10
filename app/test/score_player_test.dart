import 'package:flutter_test/flutter_test.dart';
import 'package:scale/midi/midi_service.dart';
import 'package:scale/score/score_player.dart';
import 'package:scale_core/scale_core.dart';

/// Tres compases de 4/4 con una negra por pulso, a 240 (un compás por segundo).
Score threeBars() {
  final events = <ScoreEvent>[
    for (var i = 0; i < 12; i++)
      ScoreEvent(
        id: 'e$i',
        tick: i * ticksPerQuarter,
        duration: ticksPerQuarter,
        staff: 1,
        voice: 1,
        notes: [ScoreNote(id: 'n$i', midi: 60 + i, spelling: SpelledNote.byDefault(i), octave: 4)],
        type: NoteType.quarter,
      ),
  ];
  return Score(
    id: 's',
    title: 'Prueba',
    measures: [
      for (var m = 0; m < 3; m++)
        Measure(
          number: '${m + 1}',
          tick: m * 4 * ticksPerQuarter,
          length: 4 * ticksPerQuarter,
          time: TimeSignature.common,
          fifths: 0,
          tempo: m == 0 ? 240 : null,
        ),
    ],
    parts: [ScorePart(id: 'P1', name: 'Piano', events: events)],
  );
}

void main() {
  test('el bucle A–B vuelve al principio y no sale de él', () async {
    final player = ScorePlayer(MidiService(), ScoreTimeline.of(threeBars()));
    const bar = 4 * ticksPerQuarter;
    player
      ..speed = 2
      ..setLoop(bar, 2 * bar);
    expect(player.tick, bar);
    player.play();
    final seen = <int>[];
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      seen.add(player.tick);
    }
    player.pause();
    // 1,2 s a doble velocidad: más de dos vueltas al compás 2.
    expect(seen.every((t) => t >= bar && t < 2 * bar), isTrue, reason: '$seen');
    expect(seen.any((t) => t < bar + bar ~/ 4), isTrue);
    expect(player.playing, isFalse);
    player.clearLoop();
    expect(player.looping, isFalse);
    player.stop();
    expect(player.tick, 0);
    player.dispose();
  });

  test('con bucle, ir al principio va al inicio del bucle', () {
    final player = ScorePlayer(MidiService(), ScoreTimeline.of(threeBars()));
    player.setLoop(4 * ticksPerQuarter, 12 * ticksPerQuarter);
    player.seek(10 * ticksPerQuarter);
    player.stop();
    expect(player.tick, 4 * ticksPerQuarter);
    player.dispose();
  });
}
