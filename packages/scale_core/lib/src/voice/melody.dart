import 'dart:math' as math;

import '../analysis/key_estimator.dart';
import '../theory/key.dart';
import 'pitch_detector.dart';

/// Una nota cantada (redondeada al semitono).
class SungNote {
  SungNote(this.midi, this.startMicros, this.durationMicros);

  final int midi;
  final int startMicros;
  int durationMicros;

  int get pitchClass => midi % 12;
}

/// Convierte la altura cuadro a cuadro en notas estables.
///
/// Los cuadros seguidos que no se alejan más de [toleranceSemitones] de la
/// mediana forman una nota (el vibrato y la afinación imperfecta no la
/// cortan); una nota más corta que [minNoteMicros] es un paso o un error y se
/// descarta.
class MelodyTracker {
  MelodyTracker({this.minNoteMicros = 100000, this.toleranceSemitones = 0.7});

  final int minNoteMicros;
  final double toleranceSemitones;

  final List<SungNote> notes = [];

  /// Altura del último cuadro con voz (para mostrar como afinador).
  double? currentMidi;

  final List<double> _segment = [];
  int _segmentStart = 0;
  int _segmentEnd = 0;

  /// [timeMicros]: inicio del cuadro; [frameMicros]: cuánto avanza cada cuadro.
  /// Devuelve true si se agregó una nota.
  bool addFrame(int timeMicros, PitchEstimate? pitch, int frameMicros) {
    if (pitch == null) {
      currentMidi = null;
      return _close();
    }
    final midi = pitch.midi;
    currentMidi = midi;
    var added = false;
    if (_segment.isNotEmpty && (midi - _median()).abs() > toleranceSemitones) {
      added = _close();
    }
    if (_segment.isEmpty) _segmentStart = timeMicros;
    _segment.add(midi);
    _segmentEnd = timeMicros + frameMicros;
    return added;
  }

  /// Cierra la nota en curso (al dejar de escuchar).
  bool flush() => _close();

  void reset() {
    notes.clear();
    _segment.clear();
    currentMidi = null;
  }

  bool _close() {
    if (_segment.isEmpty) return false;
    final duration = _segmentEnd - _segmentStart;
    final midi = _median().round();
    _segment.clear();
    if (duration < minNoteMicros) return false;
    // La misma nota tras una brevísima interrupción se une a la anterior.
    if (notes.isNotEmpty) {
      final last = notes.last;
      if (last.midi == midi && _segmentStart - (last.startMicros + last.durationMicros) < minNoteMicros) {
        last.durationMicros = _segmentEnd - last.startMicros;
        return true;
      }
    }
    notes.add(SungNote(midi, _segmentStart, duration));
    return true;
  }

  double _median() {
    final sorted = [..._segment]..sort();
    return sorted[sorted.length ~/ 2];
  }
}

/// Tonalidad de una melodía cantada.
///
/// Cada nota es evidencia: qué tan típica es su clase de altura en cada una de
/// las 24 tonalidades según los perfiles de Temperley (corpus Kostka-Payne),
/// más definidos para melodías que los de Krumhansl-Kessler, cuyo perfil menor
/// es tan plano que con pocas notas favorece siempre a la mayor. Las notas
/// largas pesan más. Es el mismo enfoque bayesiano que con acordes: cuanto
/// más canta, más seguro.
class MelodyKeyEstimator {
  const MelodyKeyEstimator._();

  static const List<double> _major = [
    0.748, 0.060, 0.488, 0.082, 0.670, 0.460, 0.096, 0.715, 0.104, 0.366, 0.057, 0.400,
  ];
  static const List<double> _minor = [
    0.712, 0.084, 0.474, 0.618, 0.049, 0.460, 0.105, 0.747, 0.404, 0.067, 0.133, 0.330,
  ];

  static final List<double> _majorLog = _logNormalized(_major);
  static final List<double> _minorLog = _logNormalized(_minor);

  static List<double> _logNormalized(List<double> profile) {
    final total = profile.fold<double>(0, (a, b) => a + b);
    return [for (final p in profile) math.log(p / total)];
  }

  /// Duración de nota que cuenta como una observación completa.
  static const int _unitMicros = 400000;

  /// Cuánto pesa cada observación (bajo = más prudente con pocas notas; los
  /// perfiles de Temperley son marcados, así que se modera).
  static const double _evidenceScale = 0.35;

  static KeyEstimate estimate(List<SungNote> notes, {double majorPrior = 0.55}) {
    final log = [
      for (final k in MusicKey.all) math.log(k.isMajor ? majorPrior / 12 : (1 - majorPrior) / 12),
    ];
    for (final note in notes) {
      final weight = _evidenceScale * (note.durationMicros / _unitMicros).clamp(0.3, 3.0);
      for (var i = 0; i < 24; i++) {
        final key = MusicKey.all[i];
        final profile = key.isMajor ? _majorLog : _minorLog;
        log[i] += weight * profile[key.degreeOf(note.pitchClass)];
      }
    }
    final top = log.reduce(math.max);
    final weights = [for (final l in log) math.exp(l - top)];
    final total = weights.fold<double>(0, (a, b) => a + b);
    return KeyEstimate([for (final w in weights) w / total], notes.length);
  }

  /// Nota más grave y más aguda cantadas (para saber su rango).
  static (int, int)? range(List<SungNote> notes) {
    if (notes.isEmpty) return null;
    var low = notes.first.midi;
    var high = low;
    for (final n in notes) {
      low = math.min(low, n.midi);
      high = math.max(high, n.midi);
    }
    return (low, high);
  }
}
