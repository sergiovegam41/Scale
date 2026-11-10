import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

/// Piano a dos pentagramas en 4/4: (inicio en negras, pentagrama, alturas).
Score piano(List<(double, int, List<int>)> events, {int bars = 4}) {
  var id = 0;
  return Score(
    id: 's',
    title: 'Prueba',
    measures: [
      for (var m = 0; m < bars; m++)
        Measure(
          number: '${m + 1}',
          tick: m * 4 * ticksPerQuarter,
          length: 4 * ticksPerQuarter,
          time: TimeSignature.common,
          fifths: 0,
          tempo: m == 0 ? 120 : null,
        ),
    ],
    parts: [
      ScorePart(
        id: 'P1',
        name: 'Piano',
        staves: 2,
        events: [
          for (final (q, staff, midis) in events)
            ScoreEvent(
              id: 'e${id++}',
              tick: (q * ticksPerQuarter).round(),
              duration: ticksPerQuarter,
              staff: staff,
              voice: staff == 1 ? 1 : 5,
              notes: [
                for (final m in midis)
                  ScoreNote(id: 'n${id}_$m', midi: m, spelling: SpelledNote.byDefault(m % 12), octave: m ~/ 12 - 1),
              ],
              type: NoteType.quarter,
            ),
        ],
      ),
    ],
  );
}

const _q = ticksPerQuarter;

void main() {
  group('pasos', () {
    test('agrupa las notas que empiezan juntas, de las dos manos o de una', () {
      final t = ScoreTimeline.of(piano([(0, 1, [72]), (0, 2, [48, 55]), (1, 1, [74]), (2, 2, [50])]));
      final both = PracticeStep.of(t);
      expect([for (final s in both) '${s.tick}:${(s.pitches.toList()..sort()).join(',')}'], [
        '0:48,55,72',
        '$_q:74',
        '${2 * _q}:50',
      ]);
      final right = PracticeStep.of(t, include: (n) => n.staff == 1);
      expect([for (final s in right) s.tick], [0, _q]);
      expect(PracticeStep.indexAt(both, 1), 1);
      expect(PracticeStep.indexAt(both, 3 * _q), 3);
    });
  });

  group('modo espera', () {
    late WaitGate gate;
    setUp(() {
      gate = WaitGate(
        PracticeStep.of(ScoreTimeline.of(piano([(0, 1, [60, 64, 67]), (1, 1, [62]), (2, 1, [64]), (3, 1, [65])]))),
      );
    });

    test('espera el acorde completo, en cualquier orden', () {
      expect(gate.holdTick, 0);
      expect(gate.press(67, 0), PressResult.hit);
      expect(gate.press(67, 10000), PressResult.repeat);
      expect(gate.press(60, 20000), PressResult.hit);
      expect(gate.waitingIds.length, 1);
      expect(gate.press(64, 300000), PressResult.completed);
      expect(gate.holdTick, _q);
      expect(gate.cleanSteps, 1);
      expect(gate.hits, 3);
    });

    test('una nota equivocada no avanza y queda contada en su paso', () {
      gate.press(60, 0);
      gate.press(64, 0);
      gate.press(67, 0);
      expect(gate.press(61, 1000000), PressResult.miss);
      expect(gate.holdTick, _q);
      expect(gate.press(62, 1200000), PressResult.completed);
      expect(gate.misses, 1);
      expect(gate.missesAt, {_q: 1});
      expect(gate.cleanSteps, 1);
      expect(gate.stepsDone, 2);
    });

    test('una nota del paso siguiente que se adelanta un poco no es fallo', () {
      gate.press(60, 0);
      gate.press(64, 0);
      // Re (paso 2) un poco antes de completar el acorde con Sol.
      expect(gate.press(62, 50000), PressResult.miss);
      expect(gate.press(67, 100000), PressResult.completed);
      // El Re ya contó: se espera el Mi del paso 3.
      expect(gate.holdTick, 2 * _q);
      expect(gate.misses, 0);
      expect(gate.cleanSteps, 2);
      expect(gate.missesAt, isEmpty);
    });

    test('pero si llega mucho antes sí es fallo', () {
      gate.press(60, 0);
      gate.press(64, 0);
      gate.press(62, 0);
      gate.press(67, 900000);
      expect(gate.holdTick, _q);
      expect(gate.misses, 1);
      expect(gate.cleanSteps, 0);
    });

    test('al volver al inicio del bucle empieza otra vuelta', () {
      for (final m in [60, 64, 67, 62, 64]) {
        gate.press(m, 0);
      }
      expect(gate.passSteps, 3);
      gate.resetTo(_q);
      expect(gate.holdTick, _q);
      expect(gate.passSteps, 0);
      expect(gate.stepsDone, 3);
      gate.press(62, 0);
      gate.press(64, 0);
      gate.press(65, 0);
      expect(gate.finished, isTrue);
      expect(gate.press(70, 0), PressResult.ignored);
    });
  });

  group('seguir sin esperar', () {
    // Una escala que sube y baja dos veces (pasajes que se repiten) y un final distinto.
    final melody = [60, 62, 64, 65, 67, 65, 64, 62, 60, 62, 64, 65, 67, 65, 64, 62, 72, 71, 69, 67, 76, 74, 72, 71];
    final score = piano([
      for (final (i, m) in melody.indexed) (i * 0.5, 1, [m]),
    ], bars: 3);
    final steps = PracticeStep.of(ScoreTimeline.of(score));

    test('va nota a nota', () {
      final f = ScoreFollower(steps);
      for (var i = 0; i < 12; i++) {
        expect(f.press(melody[i], i * 300000), i, reason: 'nota $i');
      }
    });

    test('un acorde no avanza de más', () {
      final chords = ScoreFollower(
        PracticeStep.of(ScoreTimeline.of(piano([(0, 1, [60, 64, 67]), (1, 1, [62, 65, 69]), (2, 1, [64, 67, 71])]))),
      );
      chords.press(64, 0);
      chords.press(60, 20000);
      expect(chords.press(67, 40000), 0);
      chords.press(62, 500000);
      chords.press(65, 520000);
      expect(chords.press(69, 530000), 1);
    });

    test('una nota equivocada no lo pierde', () {
      final f = ScoreFollower(steps);
      var t = 0;
      for (var i = 0; i < 5; i++) {
        f.press(melody[i], t += 300000);
      }
      f.press(61, t += 300000); // en lugar del Fa
      for (var i = 6; i < 10; i++) {
        expect(f.press(melody[i], t += 300000), i);
      }
    });

    test('saltarse una nota tampoco', () {
      final f = ScoreFollower(steps);
      var t = 0;
      for (final i in [0, 1, 2, 4, 5, 6, 7]) {
        f.press(melody[i], t += 300000);
      }
      expect(f.position, 7);
    });

    test('si salta a otra parte, se reubica en pocas notas', () {
      final f = ScoreFollower(steps);
      var t = 0;
      for (var i = 0; i < 4; i++) {
        f.press(melody[i], t += 300000);
      }
      // Salta al final.
      var pos = -1;
      for (var i = 20; i < 24; i++) {
        pos = f.press(melody[i], t += 300000);
      }
      expect(pos, 23);
    });

    test('empezar desde un lugar', () {
      final f = ScoreFollower(steps)..reset(16);
      expect(f.position, 15);
      expect(f.press(72, 0), 16);
      expect(f.press(71, 300000), 17);
    });
  });
}
