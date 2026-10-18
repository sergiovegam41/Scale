import '../midi/midi_event.dart';
import '../theory/key.dart';
import 'key_estimator.dart';
import 'key_model.dart';
import 'live_chord_detector.dart';

/// Acordes y tonalidad en vivo: el mismo proceso sirve para la pantalla y
/// para reconstruir una canción desde su toma MIDI, con idéntico resultado.
class LiveAnalyzer {
  LiveAnalyzer({this.maxHistory});

  /// Desde esta seguridad los acordes se escriben según la tonalidad.
  static const double spellingThreshold = 0.45;

  /// Desde esta seguridad la tonalidad se da por confirmada: marca
  /// modulaciones y ayuda al reconocedor en casos dudosos.
  static const double confirmThreshold = 0.6;

  /// Acordes que se conservan (null = todos, como al grabar).
  final int? maxHistory;

  final LiveChordDetector detector = LiveChordDetector();

  KeyEstimate key = KeyEstimator().estimate;

  /// Tonalidad confirmada anterior, si la actual surgió de una modulación.
  MusicKey? previousKey;
  MusicKey? _confirmedKey;

  List<DetectedChord> get chords => detector.chords;
  int? get pendingCloseMicros => detector.pendingCloseMicros;
  bool get sounding => detector.heldNotes.isNotEmpty;
  int get attacks => detector.attacks;
  int? get lastAttackMicros => detector.lastAttackMicros;

  MusicKey? get displayKey => !key.isEmpty && key.confidence >= spellingThreshold ? key.key : null;

  bool add(MidiEvent event) => _changed(detector.add(event));
  bool advanceTo(int timeMicros) => _changed(detector.advanceTo(timeMicros));
  bool flush() => _changed(detector.flush());

  void reset() {
    detector
      ..reset()
      ..prior = null;
    key = KeyEstimator().estimate;
    previousKey = null;
    _confirmedKey = null;
  }

  /// Peso de cada acorde para la tonalidad: los largos pesan más.
  static double durationWeight(int? durationMicros) =>
      durationMicros == null ? 1.0 : (durationMicros / 1.5e6).clamp(0.5, 1.5).toDouble();

  bool _changed(bool changed) {
    if (!changed) return false;
    final limit = maxHistory;
    if (limit != null && chords.length > limit) chords.removeRange(0, chords.length - limit);
    _updateKey();
    return true;
  }

  void _updateKey() {
    key = KeyEstimator.fromChords(
      chords.map((c) => c.chord),
      weights: [
        for (final c in chords)
          durationWeight(c.endMicros == null ? null : c.endMicros! - c.startMicros),
      ],
    );
    if (!key.isEmpty && key.confidence >= confirmThreshold) {
      final confirmed = _confirmedKey;
      if (confirmed != null && confirmed != key.key) previousKey = confirmed;
      _confirmedKey = key.key;
    }
    final k = key.key;
    final confidence = key.confidence;
    detector.prior = confidence >= confirmThreshold
        ? (chord) => 0.25 * confidence * KeyModel.weight(chord, k)
        : null;
  }
}
