import 'dart:math' as math;

import '../theory/chord.dart';
import '../theory/key.dart';
import 'key_model.dart';

class KeyCandidate {
  const KeyCandidate(this.key, this.probability);

  final MusicKey key;
  final double probability;
}

/// Resultado del estimador: las 24 tonalidades ordenadas por probabilidad.
class KeyEstimate {
  KeyEstimate(List<double> probabilities, this.observations)
      : ranked = [
          for (var i = 0; i < 24; i++) KeyCandidate(MusicKey.fromIndex(i), probabilities[i]),
        ]..sort((a, b) => b.probability.compareTo(a.probability));

  final List<KeyCandidate> ranked;

  /// Acordes observados hasta ahora.
  final int observations;

  bool get isEmpty => observations == 0;
  MusicKey get key => ranked.first.key;
  double get confidence => ranked.first.probability;

  double probabilityOf(MusicKey key) => ranked.firstWhere((c) => c.key == key).probability;

  Iterable<KeyCandidate> get alternatives => ranked.skip(1);
}

/// Estimación incremental de la tonalidad (filtro bayesiano sobre las 24).
///
/// Cada acorde multiplica la probabilidad de cada tonalidad por qué tan típico
/// es ahí; entre acorde y acorde una pequeña probabilidad de cambio permite
/// seguir modulaciones. Cuantos más acordes coherentes, más seguro.
class KeyEstimator {
  KeyEstimator({this.switchProbability = 0.03, this.majorPrior = 0.6}) {
    reset();
  }

  final double switchProbability;

  /// Probabilidad inicial repartida entre las 12 mayores (worship: mayoría mayor).
  final double majorPrior;

  late List<double> _p;
  int _observations = 0;

  void reset() {
    _p = [
      for (final k in MusicKey.all) k.isMajor ? majorPrior / 12 : (1 - majorPrior) / 12,
    ];
    _observations = 0;
  }

  /// [weight] escala la evidencia (p. ej. por duración del acorde).
  void observe(Chord chord, {double weight = 1}) {
    if (_observations > 0) _transition();
    for (var i = 0; i < 24; i++) {
      _p[i] *= math.pow(KeyModel.likelihood(chord, MusicKey.all[i]), weight);
    }
    _normalize();
    _observations++;
  }

  KeyEstimate get estimate => KeyEstimate(List.of(_p), _observations);

  /// Estima desde cero a partir de una secuencia completa.
  static KeyEstimate fromChords(Iterable<Chord> chords, {List<double>? weights}) {
    final estimator = KeyEstimator();
    var i = 0;
    for (final c in chords) {
      estimator.observe(c, weight: weights?[i] ?? 1);
      i++;
    }
    return estimator.estimate;
  }

  void _transition() {
    final n = KeyModel.neighbors;
    final next = List<double>.filled(24, 0);
    for (var j = 0; j < 24; j++) {
      final pj = _p[j];
      next[j] += (1 - switchProbability) * pj;
      final row = n[j];
      for (var k = 0; k < 24; k++) {
        next[k] += switchProbability * pj * row[k];
      }
    }
    _p = next;
  }

  void _normalize() {
    final total = _p.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      reset();
      return;
    }
    for (var i = 0; i < 24; i++) {
      _p[i] /= total;
    }
  }
}
