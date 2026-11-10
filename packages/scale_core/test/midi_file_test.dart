import 'dart:typed_data';

import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

/// Construye un archivo MIDI estándar para las pruebas.
class Smf {
  Smf({this.format = 1, this.ppq = 96});

  final int format;
  final int ppq;
  final List<List<(int, List<int>)>> tracks = [];

  /// Nueva pista: (pulso absoluto, bytes del mensaje sin delta).
  List<(int, List<int>)> track() {
    final t = <(int, List<int>)>[];
    tracks.add(t);
    return t;
  }

  static List<int> varLen(int v) {
    final out = [v & 0x7F];
    v >>= 7;
    while (v > 0) {
      out.insert(0, (v & 0x7F) | 0x80);
      v >>= 7;
    }
    return out;
  }

  static List<int> meta(int type, List<int> data) => [0xFF, type, ...varLen(data.length), ...data];
  static List<int> tempo(double bpm) {
    final us = (60e6 / bpm).round();
    return meta(0x51, [us >> 16 & 0xFF, us >> 8 & 0xFF, us & 0xFF]);
  }

  static List<int> meter(int n, int d) => meta(0x58, [n, d == 8 ? 3 : (d == 2 ? 1 : 2), 24, 8]);
  static List<int> name(String s) => meta(0x03, s.codeUnits);

  /// Notas (inicio y duración en negras) en un canal, con estado continuo
  /// (running status) y note-on de fuerza 0 como final, como hacen muchos.
  static void notes(List<(int, List<int>)> t, int ppq, List<(double, double, int)> notes, {int ch = 0, int vel = 80}) {
    for (final (start, dur, m) in notes) {
      t.add(((start * ppq).round(), [0x90 | ch, m, vel]));
      t.add((((start + dur) * ppq).round(), [0x90 | ch, m, 0]));
    }
  }

  Uint8List bytes() {
    final out = <int>[
      ...'MThd'.codeUnits, 0, 0, 0, 6, 0, format, 0, tracks.length, ppq >> 8, ppq & 0xFF, //
    ];
    for (final t in tracks) {
      final sorted = [...t]..sort((a, b) => a.$1.compareTo(b.$1));
      final data = <int>[];
      var last = 0;
      var running = 0;
      for (final (tick, msg) in sorted) {
        data.addAll(varLen(tick - last));
        last = tick;
        if (msg.first < 0xF0 && msg.first == running) {
          data.addAll(msg.skip(1));
        } else {
          data.addAll(msg);
          running = msg.first < 0xF0 ? msg.first : 0;
        }
      }
      data.addAll([0, 0xFF, 0x2F, 0]);
      out.addAll([
        ...'MTrk'.codeUnits,
        data.length >> 24,
        data.length >> 16 & 0xFF,
        data.length >> 8 & 0xFF,
        data.length & 0xFF,
      ]);
      out.addAll(data);
    }
    return Uint8List.fromList(out);
  }
}

List<String> staffOf(Score s, int staff) => [
  for (final e in s.parts.single.events)
    if (e.staff == staff)
      '${e.isRest ? 'r' : ''}${e.type?.musicXml ?? 'measure'}${'.' * e.dots}'
          '${e.tuplet != null ? '3' : ''}@${e.tick / ticksPerQuarter}'
          '${e.isRest ? '' : ':${e.notes.map((n) => '${n.spelling.name()}${n.octave}${n.tieStart ? '~' : ''}').join(',')}'}',
];

/// Pieza de piano en dos pistas (una por mano), 3/4 a 90.
Smf twoHands() {
  final f = Smf();
  f.track()
    ..add((0, Smf.name('Vals de prueba')))
    ..add((0, Smf.tempo(90)))
    ..add((0, Smf.meter(3, 4)))
    ..add((0, Smf.meta(0x59, [1, 0]))); // Sol mayor
  final rh = f.track()..add((0, Smf.name('Derecha')));
  Smf.notes(rh, 96, [
    (0, 1, 67), (1, 0.5, 69), (1.5, 0.5, 71), (2, 1, 72), //
    (3, 1.5, 74), (4.5, 0.5, 72), (5, 1, 71),
    (6, 0.9, 67), (7, 2, 66),
  ]);
  final lh = f.track()
    ..add((0, Smf.name('Izquierda')))
    ..add((0, [0xC1, 0]));
  Smf.notes(lh, 96, [(0, 3, 43), (3, 3, 50), (6, 3, 38)], ch: 1, vel: 60);
  return f;
}

void main() {
  test('lee pistas, tempo, compás, armadura y estado continuo', () {
    final file = MidiFile.parse(twoHands().bytes());
    expect(file.format, 1);
    expect(file.ticksPerQuarter, 96);
    expect(file.tracks.length, 3);
    expect(file.title, 'Vals de prueba');
    expect(file.initialTempo, closeTo(90, 0.01));
    expect(file.meters.single.$2, const TimeSignature(3, 4));
    expect(file.keys.single.$2, 1);
    expect(file.sources.map((s) => (s.name, s.channel, s.notes)), [('Derecha', 0, 9), ('Izquierda', 1, 3)]);
    expect(file.sources.last.lowest, 38);
  });

  test('una pista por mano: cada una en su pentagrama, figuras exactas', () {
    final s = MidiFileImporter.toScore(MidiFile.parse(twoHands().bytes()), id: 'x', fileName: 'vals.mid')!;
    expect(s.title, 'Vals de prueba');
    expect(s.source!.kind, 'midi');
    expect(s.recording, isNull);
    expect(s.measures.length, 3);
    expect(s.measures.first.time, const TimeSignature(3, 4));
    expect(s.measures.first.tempo, 90);
    expect(s.measures.first.fifths, 1);
    expect(staffOf(s, 1), [
      'quarter@0.0:G4', 'eighth@1.0:A4', 'eighth@1.5:B4', 'quarter@2.0:C5', //
      'quarter.@3.0:D5', 'eighth@4.5:C5', 'quarter@5.0:B4',
      'quarter@6.0:G4', 'half@7.0:F#4',
    ]);
    expect(staffOf(s, 2), ['half.@0.0:G2', 'half.@3.0:D3', 'half.@6.0:D2']);
  });

  test('los silencios del archivo se respetan', () {
    final f = Smf();
    final t = f.track()..add((0, Smf.tempo(120)));
    // Negra, silencio de corchea, corchea; luego negra, silencio de negra, negra.
    Smf.notes(t, 96, [(0, 0.95, 60), (1.5, 0.45, 62), (2, 1, 64), (4, 1, 65), (6, 1, 67), (8, 4, 72)]);
    final s = MidiFileImporter.toScore(MidiFile.parse(f.bytes()), id: 'x')!;
    expect(staffOf(s, 1).take(5), ['quarter@0.0:C4', 'reighth@1.0', 'eighth@1.5:D4', 'quarter@2.0:E4', 'rquarter@3.0']);
  });

  test('formato 0 con dos canales y cambio de tempo', () {
    final f = Smf(format: 0);
    final t = f.track()
      ..add((0, Smf.tempo(100)))
      ..add((8 * 96, Smf.tempo(80)));
    Smf.notes(t, 96, [for (var i = 0; i < 12; i++) (i.toDouble(), 1, 72 + i % 3)]);
    Smf.notes(t, 96, [for (var i = 0; i < 3; i++) (i * 4.0, 4, 48)], ch: 2);
    final file = MidiFile.parse(f.bytes());
    expect(file.sources.map((s) => s.id), ['0:0', '0:2']);
    final s = MidiFileImporter.toScore(file, id: 'x', fileName: 'C:\\x\\mi_cancion.mid')!;
    expect(s.title, 'mi cancion');
    expect([for (final m in s.measures) m.tempo], [100, null, 80]);
    expect(staffOf(s, 2), ['whole@0.0:C3', 'whole@4.0:C3', 'whole@8.0:C3']);
    // Solo la melodía.
    final melody = MidiFileImporter.toScore(file, id: 'y', sources: {'0:0'})!;
    expect(melody.parts.single.events.where((e) => !e.isRest).every((e) => e.notes.single.midi >= 72), isTrue);
  });

  test('la batería no entra por defecto', () {
    final f = Smf();
    final t = f.track();
    Smf.notes(t, 96, [(0, 1, 60), (1, 1, 62)]);
    Smf.notes(t, 96, [(0, 0.5, 36), (1, 0.5, 38)], ch: 9);
    final file = MidiFile.parse(f.bytes());
    expect(file.sources.last.drums, isTrue);
    final s = MidiFileImporter.toScore(file, id: 'x')!;
    expect(s.noteCount, 2);
  });

  test('compases del archivo: anacrusa y cambios de compás', () {
    final f = Smf();
    f.track()
      ..add((0, Smf.meter(1, 4)))
      ..add((96, Smf.meter(4, 4)))
      ..add((96 + 8 * 96, Smf.meter(3, 4)));
    final t = f.track();
    // Anacrusa de una negra, dos compases de 4/4 y uno de 3/4.
    Smf.notes(t, 96, [(0, 1, 67), for (var i = 0; i < 8; i++) (1.0 + i, 1, 72), (9, 3, 76)]);
    final s = MidiFileImporter.toScore(MidiFile.parse(f.bytes()), id: 'x')!;
    expect(
      [for (final m in s.measures) (m.number, m.time.toString(), m.length ~/ ticksPerQuarter, m.implicit)],
      [('0', '4/4', 1, true), ('1', '4/4', 4, false), ('2', '4/4', 4, false), ('3', '3/4', 3, false)],
    );
    expect(staffOf(s, 1).last, 'half.@9.0:E5');
  });

  test('los compases vacíos del principio no se escriben', () {
    final f = Smf();
    final t = f.track()..add((0, Smf.tempo(100)));
    Smf.notes(t, 96, [(8, 4, 60)]);
    final s = MidiFileImporter.toScore(MidiFile.parse(f.bytes()), id: 'x')!;
    expect(s.measures.length, 1);
    expect(staffOf(s, 1), ['whole@0.0:C4']);
    expect(s.measures.first.tempo, 100);
  });

  test('un archivo que no es MIDI', () {
    expect(() => MidiFile.parse(Uint8List.fromList('hola mundo, esto no es'.codeUnits)), throwsFormatException);
  });
}
