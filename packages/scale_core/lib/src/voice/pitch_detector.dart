import 'dart:math' as math;

/// Frecuencia fundamental estimada de un trozo de audio.
class PitchEstimate {
  const PitchEstimate(this.frequency, this.clarity);

  final double frequency;

  /// 0..1: qué tan periódica (clara) es la señal.
  final double clarity;

  /// Altura en semitonos MIDI (69 = A4 = 440 Hz), con decimales.
  double get midi => 69 + 12 * math.log(frequency / 440) / math.ln2;
}

/// Detector de altura YIN (de Cheveigné y Kawahara, 2002) para voz cantada.
///
/// Para cada retardo τ mide qué tanto se parece la señal a sí misma
/// desplazada (función de diferencia normalizada) y toma el primer mínimo
/// claro: ese τ es el período. Funciona bien con una sola voz; con piano
/// fuerte de fondo confunde (hay varias alturas a la vez).
class PitchDetector {
  PitchDetector({
    required this.sampleRate,
    this.minFrequency = 70,
    this.maxFrequency = 1100,
    this.threshold = 0.15,
    this.minRms = 0.01,
  });

  final int sampleRate;

  /// Voz más grave esperada (≈ C#2) y más aguda (≈ C#6).
  final double minFrequency;
  final double maxFrequency;

  /// Umbral YIN: menor = más exigente con la periodicidad.
  final double threshold;

  /// Por debajo de este nivel se considera silencio.
  final double minRms;

  /// Muestras en −1..1. Devuelve null si es silencio o no hay altura clara.
  PitchEstimate? detect(List<double> frame) {
    var energy = 0.0;
    for (final s in frame) {
      energy += s * s;
    }
    if (math.sqrt(energy / frame.length) < minRms) return null;

    final maxLag = math.min(frame.length ~/ 2, (sampleRate / minFrequency).ceil());
    final minLag = math.max(2, (sampleRate / maxFrequency).floor());
    final window = frame.length - maxLag;
    if (window <= 0 || minLag >= maxLag) return null;

    // Función de diferencia y su versión normalizada acumulada.
    final cmnd = List<double>.filled(maxLag + 1, 1);
    var running = 0.0;
    for (var tau = 1; tau <= maxLag; tau++) {
      var d = 0.0;
      for (var j = 0; j < window; j++) {
        final delta = frame[j] - frame[j + tau];
        d += delta * delta;
      }
      running += d;
      cmnd[tau] = running == 0 ? 1 : d * tau / running;
    }

    // Primer valle bajo el umbral (evita errores de octava hacia abajo).
    int? best;
    for (var tau = minLag; tau < maxLag; tau++) {
      if (cmnd[tau] < threshold) {
        while (tau + 1 < maxLag && cmnd[tau + 1] < cmnd[tau]) {
          tau++;
        }
        best = tau;
        break;
      }
    }
    if (best == null) return null;

    // Interpolación parabólica para afinar entre muestras.
    var period = best.toDouble();
    if (best > 1 && best < maxLag) {
      final a = cmnd[best - 1];
      final b = cmnd[best];
      final c = cmnd[best + 1];
      final denominator = a - 2 * b + c;
      if (denominator.abs() > 1e-12) period += 0.5 * (a - c) / denominator;
    }
    return PitchEstimate(sampleRate / period, (1 - cmnd[best]).clamp(0, 1).toDouble());
  }
}
