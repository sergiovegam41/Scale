import 'key.dart';

/// Cuántos semitonos mover para pasar de una tonalidad a otra.
///
/// Siempre hay dos caminos (subir o bajar): de D a F son +3 o −9. Se
/// recomienda el más corto que quepa en el rango del transpose del piano.
class TransposeAdvice {
  const TransposeAdvice._(this.up, this.down, this.recommended, this.range);

  /// [range]: hasta cuántos semitonos permite el transpose del piano (±).
  factory TransposeAdvice.between(MusicKey from, MusicKey to, {int range = 12}) {
    final up = (to.tonic - from.tonic) % 12;
    final down = up == 0 ? 0 : up - 12;
    final fitting = [up, down].where((s) => s.abs() <= range).toList();
    final pool = fitting.isEmpty ? [up, down] : fitting;
    // A igual distancia (6 semitonos) se prefiere bajar.
    pool.sort((a, b) => a.abs() != b.abs() ? a.abs().compareTo(b.abs()) : a.compareTo(b));
    return TransposeAdvice._(up, down, pool.first, range);
  }

  /// Subiendo: 0..11.
  final int up;

  /// Bajando: −11..0.
  final int down;

  final int recommended;
  final int range;

  bool fits(int semitones) => semitones.abs() <= range;

  /// Las dos opciones (una sola si no hay que mover nada).
  List<int> get options => up == 0 ? [0] : [up, down];

  static String label(int semitones) => semitones > 0 ? '+$semitones' : '$semitones';
}
