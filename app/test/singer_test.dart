import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scale/voice/singer_engine.dart';
import 'package:scale_core/scale_core.dart';

/// Voz sintética (fundamental y armónicos, con vibrato) como PCM de 16 bits.
Uint8List sing(List<(int, double)> melody, {int rate = SingerEngine.sampleRate}) {
  final samples = <double>[];
  var phase = 0.0;
  for (final (midi, seconds) in melody) {
    final f0 = 440 * math.pow(2, (midi - 69) / 12);
    for (var i = 0; i < seconds * rate; i++) {
      final t = samples.length / rate;
      final f = f0 * math.pow(2, 25 / 1200 * math.sin(2 * math.pi * 5.5 * t));
      phase += 2 * math.pi * f / rate;
      samples.add(0.4 * math.sin(phase) + 0.2 * math.sin(2 * phase) + 0.1 * math.sin(3 * phase));
    }
    samples.addAll(List.filled((0.05 * rate).round(), 0.0)); // respiración
  }
  final bytes = ByteData(samples.length * 2);
  for (final (i, s) in samples.indexed) {
    bytes.setInt16(i * 2, (s * 32767).round().clamp(-32768, 32767), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Una melodía en G mayor.
const melody = [
  (67, 0.5), (69, 0.4), (71, 0.6), (72, 0.4), (74, 0.8), (71, 0.4), (67, 0.6),
  (66, 0.4), (67, 0.8), (74, 0.5), (76, 0.4), (74, 0.4), (71, 0.6), (69, 0.4), (67, 1.0),
];

void main() {
  test('el cantante: altura, espectrograma y tonalidad a partir del audio', () {
    final engine = SingerEngine();
    final audio = sing(melody);
    // Llega en trozos, como del micrófono.
    for (var i = 0; i < audio.length; i += 1280) {
      engine.feed(Uint8List.sublistView(audio, i, math.min(audio.length, i + 1280)));
    }
    expect(engine.trace, hasLength(SingerEngine.historyLength));
    expect(engine.spectrogram, hasLength(SingerEngine.historyLength));
    expect(engine.spectrogram.first, hasLength(engine.spectrum.rows));

    // La última nota (G4) se ve en la altura y como lo más fuerte del espectro.
    final last = engine.trace.reversed.firstWhere((p) => p.midi != null).midi!;
    expect(last, closeTo(67, 0.5));
    final column = engine.spectrogram[engine.spectrogram.length - 5];
    var loudest = 0;
    for (var r = 0; r < column.length; r++) {
      if (column[r] > column[loudest]) loudest = r;
    }
    expect(engine.spectrum.midiOfRow(loudest), closeTo(67, 1));

    expect(engine.key.key, MusicKey(7, Mode.major));
    engine.reset();
    expect(engine.trace, isEmpty);
    expect(engine.spectrogram, isEmpty);
  });
}
