import 'dart:math' as math;
import 'dart:typed_data';

import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

const rate = 16000;
const frame = 1024;
const hop = 512;

double hz(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// Voz sintética: fundamental + armónicos (más parecida a una voz que un seno
/// puro), con vibrato opcional. La fase se acumula para que el vibrato module
/// la frecuencia de verdad.
List<double> voice(double frequency, int samples, {double vibratoCents = 0, int offset = 0}) {
  final out = <double>[];
  var phase = 0.0;
  for (var i = 0; i < samples; i++) {
    final t = (i + offset) / rate;
    final f = frequency * math.pow(2, vibratoCents / 1200 * math.sin(2 * math.pi * 5.5 * t));
    phase += 2 * math.pi * f / rate;
    out.add(0.5 * math.sin(phase) + 0.25 * math.sin(2 * phase) + 0.12 * math.sin(3 * phase));
  }
  return out;
}

/// Pasa una melodía (midi, segundos) por detector + seguidor como la app.
List<SungNote> sing(List<(int, double)> melody, {double vibratoCents = 0}) {
  final audio = <double>[];
  for (final (midi, seconds) in melody) {
    audio.addAll(voice(hz(midi), (seconds * rate).round(), vibratoCents: vibratoCents, offset: audio.length));
    audio.addAll(List.filled((0.06 * rate).round(), 0.0)); // respiración
  }
  final detector = PitchDetector(sampleRate: rate);
  final tracker = MelodyTracker();
  const frameMicros = hop * 1000000 ~/ rate;
  for (var start = 0; start + frame <= audio.length; start += hop) {
    tracker.addFrame(start * 1000000 ~/ rate, detector.detect(audio.sublist(start, start + frame)), frameMicros);
  }
  tracker.flush();
  return tracker.notes;
}

void main() {
  group('detector de altura', () {
    final detector = PitchDetector(sampleRate: rate);

    test('reconoce notas de voz grave a aguda', () {
      for (final midi in [43, 50, 57, 64, 69, 76]) {
        final p = detector.detect(voice(hz(midi), frame))!;
        expect(p.midi, closeTo(midi, 0.15), reason: 'midi $midi');
        expect(p.clarity, greaterThan(0.8));
      }
    });

    test('silencio y ruido no tienen altura', () {
      expect(detector.detect(List.filled(frame, 0.0)), isNull);
      final random = math.Random(7);
      expect(detector.detect([for (var i = 0; i < frame; i++) random.nextDouble() * 2 - 1]), isNull);
    });
  });

  group('melodía', () {
    test('convierte el canto en notas, con vibrato y respiraciones', () {
      final notes = sing([(67, 0.5), (69, 0.4), (71, 0.6), (67, 0.8)], vibratoCents: 35);
      expect(notes.map((n) => n.midi), [67, 69, 71, 67]);
      expect(notes.first.durationMicros, closeTo(500000, 80000));
    });

    test('una nota demasiado corta no cuenta', () {
      final notes = sing([(67, 0.5), (72, 0.05), (67, 0.5)]);
      expect(notes.map((n) => n.midi), [67, 67]);
    });
  });

  group('tonalidad de la melodía', () {
    test('una melodía en G mayor', () {
      // "Cuán grande es Él"-like: G A B C D B G, D C B A G.
      final notes = sing([
        (67, 0.6), (69, 0.4), (71, 0.6), (72, 0.4), (74, 0.8), (71, 0.4), (67, 0.8),
        (74, 0.4), (72, 0.4), (71, 0.4), (69, 0.4), (67, 1.0),
      ]);
      final estimate = MelodyKeyEstimator.estimate(notes);
      expect(estimate.key, MusicKey(7, Mode.major));
      expect(MelodyKeyEstimator.range(notes), (67, 74));
    });

    test('la misma melodía cantada más arriba cambia de tonalidad', () {
      final melody = [(67, 0.6), (69, 0.4), (71, 0.6), (72, 0.4), (74, 0.8), (71, 0.4), (67, 0.8)];
      final notes = sing([for (final (m, s) in melody) (m + 3, s)]);
      expect(MelodyKeyEstimator.estimate(notes).key, MusicKey(10, Mode.major));
    });

    test('una melodía en menor', () {
      // A menor: A C E D C B A, E G# A.
      final notes = sing([
        (69, 0.6), (72, 0.4), (76, 0.6), (74, 0.4), (72, 0.4), (71, 0.4), (69, 0.9),
        (64, 0.4), (68, 0.4), (69, 1.0),
      ]);
      expect(MelodyKeyEstimator.estimate(notes).key, MusicKey(9, Mode.minor));
    });

    test('más notas → más seguridad', () {
      final short = MelodyKeyEstimator.estimate(sing([(67, 0.4), (71, 0.4)]));
      final long = MelodyKeyEstimator.estimate(sing([
        (67, 0.6), (69, 0.4), (71, 0.6), (72, 0.4), (74, 0.8), (71, 0.4), (67, 0.8),
        (74, 0.4), (72, 0.4), (71, 0.4), (69, 0.4), (67, 1.0),
      ]));
      expect(long.confidence, greaterThan(short.confidence));
    });
  });

  group('espectro', () {
    int loudest(Float64List column) {
      var best = 0;
      for (var r = 1; r < column.length; r++) {
        if (column[r] > column[best]) best = r;
      }
      return best;
    }

    test('la fundamental cae en la fila de su nota', () {
      final spectrum = NoteSpectrum(sampleRate: rate);
      for (final midi in [48, 57, 69, 76]) {
        final column = spectrum.analyze([for (var i = 0; i < 2048; i++) math.sin(2 * math.pi * hz(midi) * i / rate)]);
        expect(spectrum.midiOfRow(loudest(column)), closeTo(midi, 0.5), reason: 'midi $midi');
      }
    });

    test('se ven también los armónicos de la voz', () {
      final spectrum = NoteSpectrum(sampleRate: rate);
      final column = spectrum.analyze(voice(hz(57), 2048));
      double at(double midi) => column[((midi - spectrum.minMidi) * spectrum.rowsPerSemitone).floor()];
      final silence = spectrum.analyze(List.filled(2048, 0.0));
      expect(at(57), greaterThan(silence[0] + 60));
      expect(at(69), greaterThan(at(63) + 10), reason: 'la octava (2º armónico) resalta');
    });
  });
}
