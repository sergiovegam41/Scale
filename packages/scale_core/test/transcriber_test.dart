import 'dart:convert';
import 'dart:math' as math;

import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

/// Una nota tocada: inicio y duración en negras (desde el compás 1), altura
/// y fuerza.
typedef Played = (double beat, double length, int midi, int velocity);

/// Toma sintética a [bpm] con un compás de cuenta (4 negras) antes: cada
/// ataque se desvía al azar hasta [jitterMs] y todos se adelantan [earlyMs].
Take takeOf(
  List<Played> notes, {
  double bpm = 100,
  double jitterMs = 15,
  double earlyMs = 0,
  int seed = 1,
  List<(double, bool)> pedal = const [],
}) {
  final rnd = math.Random(seed);
  final q = 60e6 / bpm;
  final start = (4 * q).round();
  int at(double beat) => (start + beat * q).round();
  final events = <MidiEvent>[];
  for (final (beat, length, midi, velocity) in notes) {
    final jitter = (rnd.nextDouble() * 2 - 1) * jitterMs * 1000 - earlyMs * 1000;
    final on = at(beat) + jitter.round();
    // Se suelta un poquito antes del final (como al tocar legato real).
    final off = at(beat + length) - (q * 0.08).round() + (rnd.nextDouble() * 10000).round();
    events
      ..add(MidiEvent.noteOn(math.max(0, on), midi, velocity: velocity))
      ..add(MidiEvent.noteOff(math.max(1, off), midi));
  }
  for (final (beat, down) in pedal) {
    events.add(MidiEvent.sustain(at(beat), down: down));
  }
  events.sort((a, b) => a.timeMicros.compareTo(b.timeMicros));
  return Take(id: 't', recordedAt: DateTime(2026), events: events);
}

TranscriptionSettings settingsFor({double bpm = 100, TimeSignature time = TimeSignature.common, bool triplets = true}) =>
    TranscriptionSettings(bpm: bpm, time: time, startMicros: (4 * 60e6 / bpm).round(), triplets: triplets);

Score transcribe(Take take, [TranscriptionSettings? s]) =>
    PerformanceTranscriber.transcribe(take, s ?? settingsFor(), id: 'x', title: 'Prueba')!;

/// "Figura@pulso:alturas" de los eventos de un pentagrama, para comparar.
List<String> staffOf(Score s, int staff) => [
      for (final e in s.parts.single.events)
        if (e.staff == staff)
          '${e.isRest ? 'r' : ''}${e.type?.musicXml ?? 'measure'}${'.' * e.dots}'
              '${e.tuplet != null ? '3' : ''}@${e.tick / ticksPerQuarter}'
              '${e.isRest ? '' : ':${e.notes.map((n) => '${n.spelling.name()}${n.octave}${n.tieStart ? '~' : ''}').join(',')}'}',
    ];

void main() {
  test('melodía y bajo: figuras, manos, compases y silencios', () {
    final s = transcribe(takeOf([
      (0, 1, 60, 70), (1, 1, 62, 72), (2, 1, 64, 74), (3, 1, 65, 76), (4, 2, 67, 80), //
      (0, 4, 48, 60), (4, 2, 43, 60),
    ]));
    expect(s.measures.length, 2);
    expect(s.measures.first.tempo, 100);
    expect(staffOf(s, 1), ['quarter@0.0:C4', 'quarter@1.0:D4', 'quarter@2.0:E4', 'quarter@3.0:F4', 'half@4.0:G4', 'rhalf@6.0']);
    expect(staffOf(s, 2), ['whole@0.0:C3', 'half@4.0:G2', 'rhalf@6.0']);
  });

  test('la fuerza de cada nota se conserva y suena al reproducir', () {
    final s = transcribe(takeOf([(0, 1, 60, 33), (1, 1, 64, 101), (2, 2, 67, 64)]));
    final t = ScoreTimeline.of(s);
    expect(t.notes.map((n) => n.velocity), [33, 101, 64]);
  });

  test('adelanto constante respecto al metrónomo se corrige solo', () {
    final notes = <Played>[for (var i = 0; i < 16; i++) (i * 0.5, 0.5, 60 + i % 5, 70)];
    final s = transcribe(takeOf(notes, earlyMs: 55, jitterMs: 20));
    expect(s.recording!.appliedLatencyMicros, inInclusiveRange(-75000, -35000));
    expect(staffOf(s, 1).every((e) => e.startsWith('eighth')), isTrue, reason: staffOf(s, 1).join(' '));
    expect(staffOf(s, 1).first, startsWith('eighth@0.0'));
  });

  test('síncopa: la nota que cruza el pulso se liga', () {
    final s = transcribe(takeOf([(0, 0.5, 60, 70), (0.5, 1, 62, 70), (1.5, 0.5, 64, 70), (2, 2, 65, 70)]));
    expect(staffOf(s, 1), ['eighth@0.0:C4', 'eighth@0.5:D4~', 'eighth@1.0:D4', 'eighth@1.5:E4', 'half@2.0:F4']);
  });

  test('negra con puntillo y corchea', () {
    final s = transcribe(takeOf([(0, 1.5, 60, 70), (1.5, 0.5, 62, 70), (2, 2, 64, 70)]));
    expect(staffOf(s, 1), ['quarter.@0.0:C4', 'eighth@1.5:D4', 'half@2.0:E4']);
  });

  test('nota que cruza la barra se liga al compás siguiente', () {
    final s = transcribe(takeOf([(0, 3, 60, 70), (3, 2, 62, 70), (5, 3, 64, 70)]));
    expect(staffOf(s, 1), ['half.@0.0:C4', 'quarter@3.0:D4~', 'quarter@4.0:D4', 'half.@5.0:E4']);
  });

  test('tresillos de corchea', () {
    final s = transcribe(takeOf([
      (0, 1 / 3, 60, 70), (1 / 3, 1 / 3, 62, 70), (2 / 3, 1 / 3, 64, 70), (1, 1, 65, 70), (2, 2, 67, 70),
    ]));
    final rh = staffOf(s, 1);
    expect(rh.take(3), ['eighth3@0.0:C4', 'eighth3@0.3333333333333333:D4', 'eighth3@0.6666666666666666:E4']);
    expect(rh.skip(3), ['quarter@1.0:F4', 'half@2.0:G4']);
    // Sin tresillos se aproximan a semicorcheas.
    final plain = transcribe(takeOf([(0, 1 / 3, 60, 70), (1 / 3, 1 / 3, 62, 70), (2 / 3, 1 / 3, 64, 70), (1, 3, 65, 70)]),
        settingsFor(triplets: false));
    expect(staffOf(plain, 1).any((e) => e.contains('3@')), isFalse);
  });

  test('anacrusa: lo tocado en la cuenta abre un compás incompleto', () {
    final s = transcribe(takeOf([(-1, 1, 67, 70), (0, 4, 72, 70)]));
    expect(s.measures.first.implicit, isTrue);
    expect(s.measures.first.length, ticksPerQuarter);
    expect(staffOf(s, 1), ['quarter@0.0:G4', 'whole@1.0:C5']);
  });

  test('el pedal alarga las notas hasta la siguiente', () {
    final take = takeOf([(0, 0.25, 48, 70), (2, 0.25, 50, 70)], pedal: [(0, true), (1.9, false)]);
    final s = transcribe(take);
    expect(staffOf(s, 2).first, 'half@0.0:C3');
  });

  test('acordes: notas juntas en un evento y reparto por registro', () {
    final s = transcribe(takeOf([
      (0, 2, 60, 70), (0, 2, 64, 70), (0, 2, 67, 70), (0, 2, 36, 70), (0, 2, 43, 70), //
      (2, 2, 59, 70), (2, 2, 62, 70), (2, 2, 67, 70), (2, 2, 43, 70),
    ]));
    expect(staffOf(s, 1), ['half@0.0:C4,E4,G4', 'half@2.0:B3,D4,G4']);
    expect(staffOf(s, 2), ['half@0.0:C2,G2', 'half@2.0:G2']);
  });

  test('ortografía según la tonalidad estimada', () {
    // Progresión clara en E mayor: el pc 8 debe escribirse G#, no Ab.
    final notes = <Played>[];
    final chords = [[52, 56, 59], [57, 61, 64], [59, 63, 66], [52, 56, 59]];
    for (final (i, c) in chords.indexed) {
      for (final m in c) {
        notes.add((i * 4.0, 4, m + 12, 70));
      }
      notes.add((i * 4.0, 4, c.first - 12, 70));
    }
    final s = transcribe(takeOf(notes));
    expect(s.measures.first.fifths, 4);
    final names = [for (final e in s.parts.single.events) for (final n in e.notes) n.spelling.name()];
    expect(names, contains('G#'));
    expect(names, isNot(contains('Ab')));
  });

  test('6/8: pulso de negra con puntillo', () {
    final s = transcribe(
      takeOf([(0, 0.5, 60, 70), (0.5, 0.5, 62, 70), (1, 0.5, 64, 70), (1.5, 1.5, 65, 70)], bpm: 90),
      settingsFor(bpm: 60, time: const TimeSignature(6, 8)),
    );
    expect(s.measures.first.length, 3 * ticksPerQuarter);
    expect(s.measures.first.tempo, 90);
  });

  test('dinámicas según la fuerza y cifrado de los acordes', () {
    final notes = <Played>[];
    for (var m = 0; m < 6; m++) {
      final v = m < 3 ? 50 : 100;
      for (final p in [60, 64, 67]) {
        notes.add((m * 4.0, 4, p, v));
      }
      notes.add((m * 4.0, 4, 48, v));
    }
    final s = transcribe(takeOf(notes));
    final dyn = s.parts.single.directions;
    expect(dyn.map((d) => d.value), ['p', 'f']);
    expect(dyn.last.tick, 12 * ticksPerQuarter);
    expect(s.parts.single.chords.map((c) => c.chord), [Chord(0, ChordQuality.major)]);
  });

  test('se puede exportar, guardar y reproducir', () {
    final s = transcribe(takeOf([
      (0, 1.5, 60, 70), (1.5, 0.5, 62, 70), (2, 3, 64, 70), (5, 1, 65, 70), (6, 2, 67, 70), (0, 8, 48, 60),
    ]));
    final back = MusicXmlReader.read(MusicXmlWriter.write(s), id: 'x');
    expect(back.noteCount, s.noteCount);
    final json = Score.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(json.recording!.take.events.length, s.recording!.take.events.length);
    expect(json.recording!.settings.bpm, 100);
    // Las ligadas se oyen como una sola nota: tantas como se tocaron.
    expect(ScoreTimeline.of(s).notes.length, 6);
  });

  test('sin notas no hay partitura', () {
    expect(
      PerformanceTranscriber.transcribe(Take(id: 't', recordedAt: DateTime(2026), events: []), settingsFor(),
          id: 'x', title: 'x'),
      isNull,
    );
  });
}
