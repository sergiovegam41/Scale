import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

const ms = 1000;
const fmt = ChordFormatter();

/// Toca un bloque de notas en [at] (con 10 ms entre dedos) y lo suelta en [until].
List<MidiEvent> block(List<int> notes, int at, int until) => [
      for (var i = 0; i < notes.length; i++) MidiEvent.noteOn((at + i * 10) * ms, notes[i]),
      for (final n in notes) MidiEvent.noteOff(until * ms, n),
    ];

List<String> play(List<MidiEvent> events) {
  final detector = LiveChordDetector();
  final sorted = [...events]..sort((a, b) => a.timeMicros.compareTo(b.timeMicros));
  for (final e in sorted) {
    detector.add(e);
  }
  detector.flush();
  return [for (final c in detector.chords) fmt.format(c.chord)];
}

void main() {
  test('una progresión en bloques', () {
    expect(
      play([
        ...block([48, 52, 55], 0, 900),
        ...block([43, 47, 50], 1000, 1900),
        ...block([45, 48, 52], 2000, 2900),
        ...block([41, 45, 48], 3000, 3900),
      ]),
      ['C', 'G', 'Am', 'F'],
    );
  });

  test('dos notas no entran a la secuencia, salvo la quinta', () {
    expect(
      play([
        ...block([48, 52, 55], 0, 900),
        ...block([74, 83], 1000, 1900),
        ...block([43, 50], 2000, 2900),
      ]),
      ['C', 'G5'],
    );
  });

  test('bajo grave en octavas + su 3ª es acorde (5ª omitida)', () {
    expect(play(block([38, 50, 66], 0, 900)), ['D']);
    expect(play(block([40, 52, 67], 0, 900)), ['Em']);
    // Pero un bajo grave con una 4ª no lo es.
    expect(play(block([38, 50, 67], 0, 900)), isEmpty);
  });

  test('un adorno sobre el bajo sostenido no cambia el acorde', () {
    // Toma real: C, luego D2 D3 F#4 con un adorno G4/F#4 arriba, luego Bm7.
    expect(
      play([
        ...block([36, 48, 60, 64, 67], 0, 3000),
        MidiEvent.noteOn(3280 * ms, 66),
        MidiEvent.noteOn(3290 * ms, 38),
        MidiEvent.noteOn(3310 * ms, 50),
        MidiEvent.noteOn(3700 * ms, 67),
        MidiEvent.noteOff(3740 * ms, 66),
        MidiEvent.noteOn(3940 * ms, 66),
        MidiEvent.noteOff(3970 * ms, 67),
        MidiEvent.noteOn(4390 * ms, 67),
        MidiEvent.noteOff(4450 * ms, 66),
        MidiEvent.noteOn(4840 * ms, 66),
        MidiEvent.noteOff(4910 * ms, 67),
        MidiEvent.noteOff(6340 * ms, 66),
        MidiEvent.noteOff(6440 * ms, 38),
        MidiEvent.noteOff(6470 * ms, 50),
        ...block([47, 57, 62], 6650, 11200),
      ]),
      ['C', 'D', 'Bm7'],
    );
  });

  test('cuenta cada ataque, también al repetir el mismo acorde, pero no los adornos', () {
    final detector = LiveChordDetector();
    for (final e in [
      ...block([43, 55, 59, 62], 0, 900),
      ...block([43, 55, 59, 62], 1000, 1900),
    ]..sort((a, b) => a.timeMicros.compareTo(b.timeMicros))) {
      detector.add(e);
    }
    detector.flush();
    expect(detector.chords, hasLength(1));
    expect(detector.attacks, 2);
    expect(detector.lastAttackMicros, 1000 * ms);

    // Un adorno de una nota sobre el bajo sostenido no es un ataque.
    detector
      ..add(MidiEvent.noteOn(2000 * ms, 43))
      ..add(MidiEvent.noteOn(2000 * ms, 59))
      ..add(MidiEvent.noteOn(2000 * ms, 62))
      ..add(MidiEvent.noteOn(2600 * ms, 64))
      ..flush();
    expect(detector.attacks, 3);
  });

  test('las notas casi simultáneas forman un solo acorde', () {
    final seg = ChordSegmenter();
    final groups = <NoteGroup>[];
    for (final e in block([48, 52, 55], 0, 500)) {
      groups.addAll(seg.add(e));
    }
    expect(groups, hasLength(1));
    expect(groups.single.pitchClasses, {0, 4, 7});
  });

  test('repetir el mismo acorde no lo duplica', () {
    expect(
      play([
        ...block([48, 52, 55], 0, 400),
        ...block([48, 52, 55], 500, 900),
        ...block([43, 47, 50], 1000, 1500),
      ]),
      ['C', 'G'],
    );
  });

  test('la 9ª que llega justo después del ataque completa el acorde', () {
    expect(
      play([
        ...block([48, 52, 55], 0, 1500),
        MidiEvent.noteOn(250 * ms, 62),
        MidiEvent.noteOff(1500 * ms, 62),
      ]),
      ['Cadd9'],
    );
  });

  test('una nota que llega después sobre el acorde sostenido es adorno', () {
    expect(
      play([
        ...block([48, 52, 55], 0, 1500),
        MidiEvent.noteOn(900 * ms, 62),
        MidiEvent.noteOff(1200 * ms, 62),
      ]),
      ['C'],
    );
  });

  test('refinar al mismo acorde que el anterior no lo duplica', () {
    // C, luego C5 (sin la 3ª) y al sumar la 3ª vuelve a ser C.
    expect(
      play([
        ...block([48, 52, 55], 0, 900),
        MidiEvent.noteOn(1000 * ms, 48),
        MidiEvent.noteOn(1000 * ms, 55),
        MidiEvent.noteOn(1250 * ms, 64),
        MidiEvent.noteOff(1900 * ms, 48),
        MidiEvent.noteOff(1900 * ms, 55),
        MidiEvent.noteOff(1900 * ms, 64),
      ]),
      ['C'],
    );
  });

  test('un acorde de paso muy corto lo reemplaza el siguiente', () {
    expect(
      play([
        ...block([48, 52, 55], 0, 900),
        ...block([50, 53, 57], 1000, 1080),
        ...block([43, 47, 50], 1100, 1900),
      ]),
      ['C', 'G'],
    );
  });

  test('bajo que camina mantiene la mano derecha: nuevos acordes', () {
    // Derecha sostiene C E G; el bajo baja C → B → A.
    expect(
      play([
        MidiEvent.noteOn(0, 64),
        MidiEvent.noteOn(0, 67),
        MidiEvent.noteOn(0, 72),
        MidiEvent.noteOn(0, 48),
        MidiEvent.noteOff(900 * ms, 48),
        MidiEvent.noteOn(1000 * ms, 47),
        MidiEvent.noteOff(1900 * ms, 47),
        MidiEvent.noteOff(1900 * ms, 67),
        MidiEvent.noteOn(2000 * ms, 45),
        MidiEvent.noteOn(2000 * ms, 69),
        MidiEvent.noteOff(2900 * ms, 45),
        MidiEvent.noteOff(2900 * ms, 64),
        MidiEvent.noteOff(2900 * ms, 69),
        MidiEvent.noteOff(2900 * ms, 72),
      ]),
      ['C', 'C/B', 'Am'],
    );
  });

  test('con pedal, un arpegio suma sus notas', () {
    expect(
      play([
        MidiEvent.sustain(0, down: true),
        MidiEvent.noteOn(0, 43),
        MidiEvent.noteOff(200 * ms, 43),
        MidiEvent.noteOn(300 * ms, 47),
        MidiEvent.noteOff(500 * ms, 47),
        MidiEvent.noteOn(600 * ms, 50),
        MidiEvent.noteOff(800 * ms, 50),
        MidiEvent.sustain(900 * ms, down: false),
      ]).last,
      'G',
    );
  });

  test('evento MIDI: json y transposición', () {
    final e = MidiEvent.noteOn(1234, 60, velocity: 80);
    expect(MidiEvent.fromJson(e.toJson()).toJson(), e.toJson());
    expect(e.transposed(3).data1, 63);
    expect(MidiEvent.sustain(0, down: true).transposed(3).data1, 64);
  });
}
