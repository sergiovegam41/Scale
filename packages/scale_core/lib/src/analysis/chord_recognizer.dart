import 'dart:math' as math;

import '../theory/chord.dart';

class ChordCandidate {
  const ChordCandidate(this.chord, this.score, this.probability);

  final Chord chord;
  final double score;

  /// Probabilidad relativa entre todas las interpretaciones (0..1).
  final double probability;
}

class ChordRecognition {
  ChordRecognition(this.candidates);

  /// Interpretaciones ordenadas de más a menos probable (nunca vacía).
  final List<ChordCandidate> candidates;

  Chord get best => candidates.first.chord;
  double get confidence => candidates.first.probability;
  Iterable<ChordCandidate> get alternatives => candidates.skip(1);
}

/// Bonificación externa por acorde (p. ej. encaje con la tonalidad).
typedef ChordPrior = double Function(Chord chord);

/// Reconoce el acorde de un conjunto de notas comparándolo con plantillas.
///
/// Por cada fundamental presente y cada tipo de acorde se puntúa: notas de la
/// plantilla presentes (+), faltantes (−, poco si es la 5ª), notas sobrantes
/// (−), bajo en la fundamental (+) y complejidad del acorde (−). El bajo decide
/// casos como C6 frente a Am7; [prior] permite desempatar por tonalidad.
class ChordRecognizer {
  const ChordRecognizer({this.temperature = 0.6, this.maxCandidates = 5});

  final double temperature;
  final int maxCandidates;

  static const double _matched = 1.0;
  static const double _missingFifth = 0.35;
  static const double _missing = 1.3;
  static const double _extra = 1.1;
  static const double _foreignBass = 0.6;
  static const double _foreignBassOnly = 0.2;
  static const double _extensionOnlyInBass = 1.2;
  static const double _rootInBass = 0.5;

  static const Map<TriadFamily, Set<int>> _triadTones = {
    TriadFamily.major: {0, 4, 7},
    TriadFamily.minor: {0, 3, 7},
    TriadFamily.diminished: {0, 3, 6},
    TriadFamily.augmented: {0, 4, 8},
    TriadFamily.suspended: {0, 2, 5, 7},
    TriadFamily.power: {0, 7},
  };

  /// [notes] son notas MIDI; la más grave se toma como bajo.
  ChordRecognition? recognize(Iterable<int> notes, {ChordPrior? prior}) {
    if (notes.isEmpty) return null;
    final sorted = notes.toList()..sort();
    final bass = sorted.first % 12;
    final upper = {for (final n in sorted.skip(1)) n % 12};
    return recognizePitchClasses(
      {for (final n in sorted) n % 12},
      bass: bass,
      bassOnly: !upper.contains(bass),
      prior: prior,
    );
  }

  /// [bassOnly]: la nota del bajo no se repite arriba. Si además no es nota
  /// de la tríada, se cifra como bajo con barra (C/B, G/A) y no como
  /// extensión (Cmaj7/B, Gadd9/A).
  ChordRecognition? recognizePitchClasses(
    Set<int> pcs, {
    int? bass,
    bool bassOnly = false,
    ChordPrior? prior,
  }) {
    if (pcs.length < 2) return null;
    final scored = <(Chord, double)>[];
    for (final root in pcs) {
      for (final q in ChordQuality.all) {
        final chord = Chord(root, q, bass: bass);
        var score = _score(root, q, pcs, bass, bassOnly);
        if (prior != null) score += prior(chord);
        scored.add((chord, score));
      }
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final top = scored.first.$2;
    final weights = [for (final (_, s) in scored) math.exp((s - top) / temperature)];
    final total = weights.fold<double>(0, (a, b) => a + b);
    return ChordRecognition([
      for (var i = 0; i < math.min(maxCandidates, scored.length); i++)
        ChordCandidate(scored[i].$1, scored[i].$2, weights[i] / total),
    ]);
  }

  double _score(int root, ChordQuality q, Set<int> pcs, int? bass, bool bassOnly) {
    final template = {for (final i in q.intervals) (root + i) % 12};
    final triad = _triadTones[q.family]!;
    var s = 0.0;
    for (final i in q.intervals) {
      final p = (root + i) % 12;
      if (pcs.contains(p)) {
        s += _matched;
        if (bassOnly && p == bass && !triad.contains(i)) s -= _extensionOnlyInBass;
      } else {
        s -= i == 7 ? _missingFifth : _missing;
      }
    }
    for (final p in pcs) {
      if (!template.contains(p)) {
        s -= p == bass ? (bassOnly ? _foreignBassOnly : _foreignBass) : _extra;
      }
    }
    if (bass == root) s += _rootInBass;
    return s - q.complexity;
  }
}
