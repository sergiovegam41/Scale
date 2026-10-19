import 'dart:math' as math;
import 'dart:typed_data';

/// Espectro de un trozo de audio en escala de notas, para el espectrograma.
///
/// Cada fila es una fracción de semitono entre [minMidi] y [maxMidi] (de
/// abajo hacia arriba): así el espectrograma se alinea con las notas cantadas.
class NoteSpectrum {
  NoteSpectrum({
    required this.sampleRate,
    this.size = 2048,
    this.minMidi = 36,
    this.maxMidi = 96,
    this.rowsPerSemitone = 4,
  })  : assert(size & (size - 1) == 0, 'el tamaño debe ser potencia de 2'),
        _window = Float64List.fromList([
          for (var i = 0; i < size; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / (size - 1)),
        ]),
        _re = Float64List(size),
        _im = Float64List(size);

  final int sampleRate;

  /// Muestras por análisis (2048 a 16 kHz = 128 ms: alcanza para voces graves).
  final int size;
  final int minMidi;
  final int maxMidi;
  final int rowsPerSemitone;

  final Float64List _window;
  final Float64List _re;
  final Float64List _im;

  int get rows => (maxMidi - minMidi) * rowsPerSemitone;

  /// Nota (con decimales) en el centro de la fila [row] (0 = la más grave).
  double midiOfRow(int row) => minMidi + (row + 0.5) / rowsPerSemitone;

  static double frequencyOf(double midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

  /// Intensidad en dB de cada fila para las últimas [size] muestras.
  Float64List analyze(List<double> samples) {
    final offset = samples.length - size;
    for (var i = 0; i < size; i++) {
      final s = offset + i >= 0 ? samples[offset + i] : 0.0;
      _re[i] = s * _window[i];
      _im[i] = 0;
    }
    _fft(_re, _im);
    final half = size ~/ 2;
    final magnitude = Float64List(half + 1);
    for (var k = 0; k <= half; k++) {
      magnitude[k] = math.sqrt(_re[k] * _re[k] + _im[k] * _im[k]);
    }
    final binHz = sampleRate / size;
    double at(double bin) {
      final b = bin.clamp(0, half - 1.0001);
      final i = b.floor();
      final f = b - i;
      return magnitude[i] * (1 - f) + magnitude[i + 1] * f;
    }

    final out = Float64List(rows);
    for (var r = 0; r < rows; r++) {
      final center = midiOfRow(r);
      final lo = frequencyOf(center - 0.5 / rowsPerSemitone) / binHz;
      final hi = frequencyOf(center + 0.5 / rowsPerSemitone) / binHz;
      // En los agudos una fila abarca varios bins: el máximo; en los graves, interpolado.
      var m = at(frequencyOf(center) / binHz);
      for (var k = lo.ceil(); k <= hi.floor() && k <= half; k++) {
        if (magnitude[k] > m) m = magnitude[k];
      }
      out[r] = 20 * math.log(m + 1e-9) / math.ln10;
    }
    return out;
  }

  /// FFT radix-2 en el lugar.
  static void _fft(Float64List re, Float64List im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final angle = -2 * math.pi / len;
      final wr = math.cos(angle), wi = math.sin(angle);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0, ci = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final a = i + k, b = a + len ~/ 2;
          final xr = re[b] * cr - im[b] * ci;
          final xi = re[b] * ci + im[b] * cr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
          final nr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = nr;
        }
      }
    }
  }
}
