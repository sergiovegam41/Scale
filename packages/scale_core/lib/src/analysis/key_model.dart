import 'dart:math' as math;

import '../theory/chord.dart';
import '../theory/key.dart';

/// Qué tan típico es cada acorde en cada tonalidad.
///
/// Las tablas dan un peso por grado (semitonos desde la tónica) y familia de
/// tríada: en mayor I, IV, V y vi pesan mucho; ii y iii algo; préstamos
/// comunes (bVII, iv, II) poco. Funciona igual con acordes tocados que con
/// símbolos importados, porque no necesita las notas reales.
class KeyModel {
  const KeyModel._();

  // Columnas: [mayor, menor, disminuido, aumentado].
  static const List<List<double>> _major = [
    [1.00, 0.05, 0.02, 0.03], // I
    [0.03, 0.02, 0.02, 0.02], // bII
    [0.15, 0.50, 0.03, 0.02], // ii (II = V/V)
    [0.06, 0.02, 0.02, 0.02], // bIII
    [0.12, 0.35, 0.02, 0.02], // iii (III = V/vi)
    [0.80, 0.12, 0.03, 0.02], // IV (iv prestado)
    [0.02, 0.03, 0.08, 0.02], // #iv°
    [0.85, 0.06, 0.02, 0.03], // V
    [0.10, 0.02, 0.02, 0.02], // bVI
    [0.08, 0.60, 0.02, 0.02], // vi
    [0.20, 0.03, 0.02, 0.02], // bVII
    [0.03, 0.04, 0.15, 0.02], // vii°
  ];

  static const List<List<double>> _minor = [
    [0.08, 1.00, 0.02, 0.02], // i
    [0.04, 0.02, 0.02, 0.02], // bII
    [0.04, 0.10, 0.20, 0.02], // ii°
    [0.50, 0.03, 0.02, 0.05], // bIII
    [0.03, 0.03, 0.02, 0.02], // III
    [0.15, 0.60, 0.02, 0.02], // iv (IV dórico)
    [0.02, 0.02, 0.03, 0.02], // #iv
    [0.60, 0.35, 0.02, 0.02], // V / v
    [0.55, 0.03, 0.02, 0.02], // bVI
    [0.02, 0.02, 0.05, 0.02], // vi°
    [0.55, 0.04, 0.02, 0.02], // bVII
    [0.03, 0.02, 0.10, 0.02], // vii°
  ];

  static const double _floor = 0.02;

  static final Map<Mode, double> _normalizer = {
    for (final mode in Mode.values)
      mode: (mode == Mode.major ? _major : _minor)
          .expand((row) => row)
          .fold<double>(0, (a, w) => a + math.max(w, _floor)),
  };

  /// Peso relativo 0..1 (1 = la tónica de la tonalidad).
  static double weight(Chord chord, MusicKey key) {
    final row = (key.isMajor ? _major : _minor)[key.degreeOf(chord.root)];
    final w = switch (chord.quality.family) {
      TriadFamily.major => row[0],
      TriadFamily.minor => row[1],
      TriadFamily.diminished => row[2],
      TriadFamily.augmented => row[3],
      TriadFamily.suspended || TriadFamily.power => 0.9 * math.max(row[0], row[1]),
    };
    var result = math.max(w, _floor);
    // Un acorde de dominante (G7) apunta más a la tonalidad donde es V.
    if (chord.quality.dominant) {
      final degree = key.degreeOf(chord.root);
      if (degree == 7) {
        result *= 1.2;
      } else if (degree == 0) {
        result *= 0.5;
      }
    }
    // Notas fuera de la escala (Gmaj7 en C) restan.
    final pcs = chord.pitchClasses;
    final inScale = pcs.where(key.fits).length / pcs.length;
    return result * (0.4 + 0.6 * inScale);
  }

  /// Verosimilitud normalizada para comparar tonalidades mayores y menores.
  static double likelihood(Chord chord, MusicKey key) => weight(chord, key) / _normalizer[key.mode]!;

  /// Probabilidad de pasar de [from] a [to] dado que hay un cambio: se
  /// favorecen las modulaciones típicas (subir ½ o 1 tono, a la relativa,
  /// a la dominante/subdominante).
  static final List<List<double>> neighbors = _buildNeighbors();

  static List<List<double>> _buildNeighbors() {
    final m = List.generate(24, (_) => List<double>.filled(24, 0));
    for (final from in MusicKey.all) {
      var total = 0.0;
      for (final to in MusicKey.all) {
        if (to == from) continue;
        final interval = (to.tonic - from.tonic) % 12;
        double w;
        if (to.mode == from.mode && const {1, 2, 10, 11}.contains(interval)) {
          w = 3;
        } else if (to == from.relative) {
          w = 2;
        } else if (to.mode == from.mode && (interval == 5 || interval == 7)) {
          w = 2;
        } else if (to == from.parallel) {
          w = 1.5;
        } else {
          w = 1;
        }
        m[from.index][to.index] = w;
        total += w;
      }
      for (var j = 0; j < 24; j++) {
        m[from.index][j] /= total;
      }
    }
    return m;
  }
}
