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

/// Toma sintética sin metrónomo: [time] da el instante (en µs) de cada
/// pulso tocado, para simular a alguien que acelera o frena.
Take takeAt(List<Played> notes, double Function(double beat) time, {double jitterMs = 15, int seed = 3}) {
  final rnd = math.Random(seed);
  final events = <MidiEvent>[];
  for (final (beat, length, midi, velocity) in notes) {
    final on = time(beat) + (rnd.nextDouble() * 2 - 1) * jitterMs * 1000;
    final end = time(beat + length);
    final off = end - (end - on) * 0.12;
    events
      ..add(MidiEvent.noteOn(on.round(), midi, velocity: velocity))
      ..add(MidiEvent.noteOff(off.round(), midi));
  }
  events.sort((a, b) => a.timeMicros.compareTo(b.timeMicros));
  return Take(id: 't', recordedAt: DateTime(2026), events: events);
}

/// Cumpleaños feliz (3/4, anacrusa de un pulso) en pulsos desde el primer
/// pulso del compás 1.
const List<Played> birthday = [
  (-1, 0.75, 60, 60), (-0.25, 0.25, 60, 55), (0, 1, 62, 70), (1, 1, 60, 65), (2, 1, 65, 70), (3, 2, 64, 70), //
  (5, 0.75, 60, 60), (5.75, 0.25, 60, 55), (6, 1, 62, 70), (7, 1, 60, 65), (8, 1, 67, 70), (9, 2, 65, 70), //
  (11, 0.75, 60, 60), (11.75, 0.25, 60, 55), (12, 1, 72, 75), (13, 1, 69, 70), (14, 1, 65, 70), (15, 1, 64, 65),
  (16, 2, 62, 65), (17.9, 0.1, 62, 0), //
];

TranscriptionSettings settingsFor({
  double bpm = 100,
  TimeSignature time = TimeSignature.common,
  bool triplets = true,
}) => TranscriptionSettings(bpm: bpm, time: time, startMicros: (4 * 60e6 / bpm).round(), triplets: triplets);

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
    final s = transcribe(
      takeOf([
        (0, 1, 60, 70), (1, 1, 62, 72), (2, 1, 64, 74), (3, 1, 65, 76), (4, 2, 67, 80), //
        (0, 4, 48, 60), (4, 2, 43, 60),
      ]),
    );
    expect(s.measures.length, 2);
    expect(s.measures.first.tempo, 100);
    expect(staffOf(s, 1), [
      'quarter@0.0:C4',
      'quarter@1.0:D4',
      'quarter@2.0:E4',
      'quarter@3.0:F4',
      'half@4.0:G4',
      'rhalf@6.0',
    ]);
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
    // ♪ ♩ ♪: la negra a contratiempo se escribe sin ligar…
    expect(staffOf(s, 1), ['eighth@0.0:C4', 'quarter@0.5:D4', 'eighth@1.5:E4', 'half@2.0:F4']);
    // …salvo que cruce la mitad del 4/4.
    final mid = transcribe(takeOf([(0, 1.5, 60, 70), (1.5, 1, 62, 70), (2.5, 1.5, 64, 70)]));
    expect(staffOf(mid, 1), ['quarter.@0.0:C4', 'eighth@1.5:D4~', 'eighth@2.0:D4', 'eighth@2.5:E4~', 'quarter@3.0:E4']);
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
    final s = transcribe(
      takeOf([(0, 1 / 3, 60, 70), (1 / 3, 1 / 3, 62, 70), (2 / 3, 1 / 3, 64, 70), (1, 1, 65, 70), (2, 2, 67, 70)]),
    );
    final rh = staffOf(s, 1);
    expect(rh.take(3), ['eighth3@0.0:C4', 'eighth3@0.3333333333333333:D4', 'eighth3@0.6666666666666666:E4']);
    expect(rh.skip(3), ['quarter@1.0:F4', 'half@2.0:G4']);
    // Sin tresillos se aproximan a semicorcheas.
    final plain = transcribe(
      takeOf([(0, 1 / 3, 60, 70), (1 / 3, 1 / 3, 62, 70), (2 / 3, 1 / 3, 64, 70), (1, 3, 65, 70)]),
      settingsFor(triplets: false),
    );
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
    final s = transcribe(
      takeOf([
        (0, 2, 60, 70), (0, 2, 64, 70), (0, 2, 67, 70), (0, 2, 36, 70), (0, 2, 43, 70), //
        (2, 2, 59, 70), (2, 2, 62, 70), (2, 2, 67, 70), (2, 2, 43, 70),
      ]),
    );
    expect(staffOf(s, 1), ['half@0.0:C4,E4,G4', 'half@2.0:B3,D4,G4']);
    expect(staffOf(s, 2), ['half@0.0:C2,G2', 'half@2.0:G2']);
  });

  test('ortografía según la tonalidad estimada', () {
    // Progresión clara en E mayor: el pc 8 debe escribirse G#, no Ab.
    final notes = <Played>[];
    final chords = [
      [52, 56, 59],
      [57, 61, 64],
      [59, 63, 66],
      [52, 56, 59],
    ];
    for (final (i, c) in chords.indexed) {
      for (final m in c) {
        notes.add((i * 4.0, 4, m + 12, 70));
      }
      notes.add((i * 4.0, 4, c.first - 12, 70));
    }
    final s = transcribe(takeOf(notes));
    expect(s.measures.first.fifths, 4);
    final names = [
      for (final e in s.parts.single.events)
        for (final n in e.notes) n.spelling.name(),
    ];
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
    final s = transcribe(
      takeOf([(0, 1.5, 60, 70), (1.5, 0.5, 62, 70), (2, 3, 64, 70), (5, 1, 65, 70), (6, 2, 67, 70), (0, 8, 48, 60)]),
    );
    final back = MusicXmlReader.read(MusicXmlWriter.write(s), id: 'x');
    expect(back.noteCount, s.noteCount);
    final json = Score.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(json.recording!.take.events.length, s.recording!.take.events.length);
    expect(json.recording!.settings.bpm, 100);
    // Las ligadas se oyen como una sola nota: tantas como se tocaron.
    expect(ScoreTimeline.of(s).notes.length, 6);
  });

  test('sin seguir el metrónomo: se escribe al tempo y compás de quien toca', () {
    // Metrónomo a 80 en 4/4, pero se tocó a 100 y la canción es en 3/4.
    final notes = [
      for (final n in birthday)
        if (n.$4 > 0) n,
    ];
    final take = takeAt(notes, (b) => 3e6 + (b + 1) * 600000);
    final s = transcribe(take, settingsFor(bpm: 80));
    expect(s.recording!.followedMetronome, isFalse);
    expect(s.measures.first.time, const TimeSignature(3, 4));
    expect(s.measures.first.tempo, 100);
    expect(s.measures.first.implicit, isTrue);
    expect(s.measures.first.length, ticksPerQuarter);
    final rh = staffOf(s, 1);
    expect(rh.take(8), [
      'eighth.@0.0:C4', '16th@0.75:C4', 'quarter@1.0:D4', 'quarter@2.0:C4', 'quarter@3.0:F4', 'half@4.0:E4', //
      'eighth.@6.0:C4', '16th@6.75:C4',
    ]);
    expect(rh.where((e) => e.startsWith('r')), isEmpty, reason: rh.join(' '));
    // El cursor de "como la toqué" sigue los pulsos de quien tocó.
    final rec = s.recording!;
    expect(rec.microsAt(ticksPerQuarter, 0), closeTo(3.6e6, 20000));
    expect(rec.tickAt(rec.microsAt(5 * ticksPerQuarter, 0).round(), 0), closeTo(5 * ticksPerQuarter, 1));
    // Con el compás fijado se respeta.
    final fixed = transcribe(take, settingsFor(bpm: 80).copyWith(meter: TimeSignature.common));
    expect(fixed.measures.first.time, TimeSignature.common);
  });

  test('quien acelera poco a poco: los pulsos lo siguen', () {
    // Estrellita (4/4), de 90 a 115 por minuto.
    const tune = [60, 60, 67, 67, 69, 69, 67, 0, 65, 65, 64, 64, 62, 62, 60, 0, 67, 67, 65, 65, 64, 64, 62, 0];
    final notes = <Played>[
      for (final (i, m) in tune.indexed)
        if (m != 0) (i.toDouble(), i + 1 < tune.length && tune[i + 1] == 0 ? 2.0 : 1.0, m, 70),
    ];
    double time(double b) {
      // El pulso pasa de 667 ms a 522 ms de forma continua.
      const p0 = 60e6 / 90;
      const p1 = 60e6 / 115;
      final k = (p1 - p0) / 24;
      return 2e6 + p0 * b + k * b * b / 2;
    }

    final s = transcribe(takeAt(notes, time), settingsFor(bpm: 90));
    expect(s.recording!.followedMetronome, isFalse);
    expect(s.measures.first.time, TimeSignature.common);
    expect(s.measures.first.implicit, isFalse);
    final rh = staffOf(s, 1);
    expect(rh.every((e) => e.startsWith('quarter') || e.startsWith('half')), isTrue, reason: rh.join(' '));
    expect(rh.where((e) => e.startsWith('half')).map((e) => e.split('@')[1].split(':')[0]), ['6.0', '14.0', '22.0']);
  });

  test('siguiendo el metrónomo se escribe sobre su pulso', () {
    final notes = [
      for (final n in birthday)
        if (n.$4 > 0) (n.$1 + 1, n.$2, n.$3, n.$4),
    ];
    final s = transcribe(takeOf(notes, bpm: 90, jitterMs: 20), settingsFor(bpm: 90, time: const TimeSignature(3, 4)));
    expect(s.recording!.followedMetronome, isTrue);
    expect(s.measures.first.tempo, 90);
    expect(s.measures.first.time, const TimeSignature(3, 4));
  });

  test('acorde arpegiado: un solo acorde en su pulso', () {
    final events = <MidiEvent>[];
    const q = 600000;
    for (var bar = 0; bar < 3; bar++) {
      final t = 2400000 + bar * 4 * q;
      for (final (i, m) in [48, 55, 60, 64, 67].indexed) {
        events
          ..add(MidiEvent.noteOn(t - 120000 + i * 60000, m, velocity: 60))
          ..add(MidiEvent.noteOff(t + 3 * q, m));
      }
    }
    events.sort((a, b) => a.timeMicros.compareTo(b.timeMicros));
    final s = transcribe(
      Take(id: 't', recordedAt: DateTime(2026), events: events),
      TranscriptionSettings(bpm: 100, time: TimeSignature.common, startMicros: 2400000),
    );
    expect(staffOf(s, 1).first, 'half.@0.0:C4,E4,G4');
    expect(staffOf(s, 2).first, 'half.@0.0:C3,G3');
  });

  test('un roce con la tecla vecina no es una nota', () {
    final take = takeOf([(0, 1, 60, 70), (1, 1, 62, 70), (2, 2, 64, 70)]);
    final extra = MidiEvent.noteOn(take.events[2].timeMicros + 20000, 63, velocity: 30);
    final off = MidiEvent.noteOff(extra.timeMicros + 70000, 63);
    final events = [...take.events, extra, off]..sort((a, b) => a.timeMicros.compareTo(b.timeMicros));
    final s = transcribe(Take(id: 't', recordedAt: DateTime(2026), events: events));
    expect([for (final e in s.parts.single.events) for (final n in e.notes) n.midi], [60, 62, 64]);
  });

  test('una escala rápida se escribe en fusas, sin mezclar notas', () {
    final notes = <Played>[
      for (var i = 0; i < 8; i++) (1 + i / 8, 1 / 8, 60 + [0, 2, 4, 5, 7, 9, 11, 12][i], 60),
      (2, 2, 74, 70),
    ];
    final s = transcribe(takeOf(notes, jitterMs: 8));
    final rh = staffOf(s, 1).where((e) => !e.startsWith('r')).toList();
    expect(rh.every((e) => !e.contains(',')), isTrue, reason: rh.join(' '));
    expect(rh.length, 9);
  });

  test('bajo y acorde (sin metrónomo): el bajo cae en la parte fuerte', () {
    final notes = <Played>[
      for (var bar = 0; bar < 6; bar++) ...[
        (bar * 4.0, 0.15, bar.isEven ? 43 : 38, 70),
        for (final m in bar.isEven ? [59, 62, 66] : [57, 62, 66]) (bar * 4.0 + 1, 2, m, 55),
      ],
    ];
    final s = transcribe(takeAt(notes, (b) => 2e6 + b * 730000), settingsFor(bpm: 100));
    expect(s.recording!.followedMetronome, isFalse);
    expect(s.measures.first.implicit, isFalse);
    expect(staffOf(s, 2).first, startsWith('quarter@0.0:'));
  });

  test('el cifrado se queda con lo esencial', () {
    final notes = <Played>[];
    // D con la novena en la melodía (Dadd9) y G con la sexta.
    for (final (i, chord) in [
      [50, 57, 62, 66, 76],
      [43, 55, 59, 62, 64],
    ].indexed) {
      for (final m in chord) {
        notes.add((i * 4.0, 4, m, 70));
      }
    }
    final s = transcribe(takeOf(notes));
    expect(s.parts.single.chords.map((c) => c.chord), [Chord(2, ChordQuality.major), Chord(7, ChordQuality.major)]);
  });

  test('sin notas no hay partitura', () {
    expect(
      PerformanceTranscriber.transcribe(
        Take(id: 't', recordedAt: DateTime(2026), events: []),
        settingsFor(),
        id: 'x',
        title: 'x',
      ),
      isNull,
    );
  });
}
