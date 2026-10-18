import 'dart:math' as math;

import '../model/song.dart';
import '../theory/chord.dart';
import '../theory/key.dart';
import 'key_estimator.dart';
import 'key_model.dart';

/// Divide una canción completa en regiones de tonalidad (modulaciones).
///
/// Busca la secuencia de tonalidades más probable (Viterbi) con un costo de
/// cambio alto y luego es conservador: absorbe regiones de menos de
/// [minRegionLength] acordes (un préstamo o un pasaje no es modulación), une
/// regiones relativas (G ↔ Em: mismas notas) y descarta modulaciones cuya
/// tonalidad nueva no alcance [minConfidence] dentro de su región.
class KeyAnalyzer {
  const KeyAnalyzer._();

  static List<KeyRegion> regions(
    List<Chord> chords, {
    List<double>? weights,
    double switchProbability = 0.002,
    int minRegionLength = 8,
    double minConfidence = 0.6,
    double majorPrior = 0.6,
  }) {
    final n = chords.length;
    if (n == 0) return const [];
    // Los pesos solo cuentan en relación con los demás acordes (promedio 1):
    // si no, una canción de acordes cortos tendría menos evidencia frente al
    // costo fijo de modular.
    if (weights != null) {
      final mean = weights.fold<double>(0, (a, w) => a + w) / n;
      if (mean > 0) weights = [for (final w in weights) w / mean];
    }
    final keys = MusicKey.all;
    final logStay = math.log(1 - switchProbability);
    final logMove = [
      for (var j = 0; j < 24; j++)
        [
          for (var k = 0; k < 24; k++)
            k == j ? logStay : math.log(switchProbability * KeyModel.neighbors[j][k]),
        ],
    ];
    double emit(int t, int k) =>
        (weights?[t] ?? 1) * math.log(KeyModel.likelihood(chords[t], keys[k]));

    var delta = [
      for (var k = 0; k < 24; k++)
        math.log(keys[k].isMajor ? majorPrior / 12 : (1 - majorPrior) / 12) + emit(0, k),
    ];
    final back = <List<int>>[];
    for (var t = 1; t < n; t++) {
      final next = List<double>.filled(24, 0);
      final pointers = List<int>.filled(24, 0);
      for (var k = 0; k < 24; k++) {
        var best = double.negativeInfinity;
        var arg = 0;
        for (var j = 0; j < 24; j++) {
          final v = delta[j] + logMove[j][k];
          if (v > best) {
            best = v;
            arg = j;
          }
        }
        next[k] = best + emit(t, k);
        pointers[k] = arg;
      }
      back.add(pointers);
      delta = next;
    }

    final path = List<int>.filled(n, 0);
    var last = 0;
    for (var k = 1; k < 24; k++) {
      if (delta[k] > delta[last]) last = k;
    }
    path[n - 1] = last;
    for (var t = n - 1; t > 0; t--) {
      path[t - 1] = back[t - 1][path[t]];
    }

    final runs = <_Run>[];
    for (var t = 0; t < n; t++) {
      if (runs.isNotEmpty && runs.last.key == path[t]) {
        runs.last.end = t + 1;
      } else {
        runs.add(_Run(t, t + 1, path[t]));
      }
    }
    double confidenceOf(_Run r) => KeyEstimator.fromChords(
          chords.sublist(r.start, r.end),
          weights: weights?.sublist(r.start, r.end),
        ).probabilityOf(keys[r.key]);

    _absorbShortRuns(runs, minRegionLength);
    _mergeRelatives(runs, keys);
    // Una modulación cuya tonalidad nueva es dudosa se une a la anterior.
    var changed = true;
    while (changed && runs.length > 1) {
      changed = false;
      for (var i = 1; i < runs.length; i++) {
        if (confidenceOf(runs[i]) >= minConfidence) continue;
        runs[i - 1].end = runs[i].end;
        runs.removeAt(i);
        _mergeEqual(runs);
        changed = true;
        break;
      }
    }

    return [
      for (final r in runs)
        KeyRegion(start: r.start, end: r.end, key: keys[r.key], confidence: confidenceOf(r)),
    ];
  }

  static void _absorbShortRuns(List<_Run> runs, int minLength) {
    var changed = true;
    while (changed && runs.length > 1) {
      changed = false;
      for (var i = 0; i < runs.length; i++) {
        final r = runs[i];
        if (r.length >= minLength) continue;
        if (i > 0) {
          runs[i - 1].end = r.end;
        } else {
          runs[1].start = r.start;
        }
        runs.removeAt(i);
        changed = true;
        break;
      }
      changed = _mergeEqual(runs) || changed;
    }
  }

  /// G mayor y E menor usan las mismas notas: pasar de una a otra no es
  /// modular. Se quedan con la tonalidad de la parte más larga.
  static void _mergeRelatives(List<_Run> runs, List<MusicKey> keys) {
    for (var i = runs.length - 1; i > 0; i--) {
      final a = runs[i - 1];
      final b = runs[i];
      if (keys[a.key].relative != keys[b.key]) continue;
      if (b.length > a.length) a.key = b.key;
      a.end = b.end;
      runs.removeAt(i);
    }
    _mergeEqual(runs);
  }

  static bool _mergeEqual(List<_Run> runs) {
    var changed = false;
    for (var i = runs.length - 1; i > 0; i--) {
      if (runs[i].key == runs[i - 1].key) {
        runs[i - 1].end = runs[i].end;
        runs.removeAt(i);
        changed = true;
      }
    }
    return changed;
  }
}

class _Run {
  _Run(this.start, this.end, this.key);

  int start;
  int end;
  int key;

  int get length => end - start;
}
