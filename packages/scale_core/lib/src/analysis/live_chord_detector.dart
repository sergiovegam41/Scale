import '../midi/midi_event.dart';
import '../theory/chord.dart';
import 'chord_recognizer.dart';
import 'chord_segmenter.dart';

/// Un acorde de la secuencia detectada.
class DetectedChord {
  DetectedChord({
    required this.startMicros,
    required this.recognition,
    required this.notes,
  });

  final int startMicros;
  int? endMicros;
  ChordRecognition recognition;
  Set<int> notes;

  Chord get chord => recognition.best;
  double get confidence => recognition.confidence;
}

/// Une segmentación y reconocimiento en una secuencia de acordes en vivo.
///
/// Reglas de la secuencia:
/// - volver a tocar el mismo acorde no crea uno nuevo;
/// - añadir notas justo después del ataque manteniendo el acorde (mismo bajo
///   y fundamental) lo completa (G → Gadd9) en vez de crear otro;
/// - una nota suelta de adorno, más tarde, sobre el bajo sostenido no lo cambia;
/// - un acorde que dura menos de [minChordMicros] se toma como de paso y lo
///   reemplaza el siguiente.
class LiveChordDetector {
  LiveChordDetector({
    ChordSegmenter? segmenter,
    this.recognizer = const ChordRecognizer(),
    this.minChordMicros = 150000,
    this.refineWindowMicros = 400000,
    this.prior,
  }) : segmenter = segmenter ?? ChordSegmenter();

  final ChordSegmenter segmenter;
  final ChordRecognizer recognizer;
  final int minChordMicros;

  /// Notas que llegan dentro de este tiempo desde el ataque (acorde arpegiado
  /// rápido) completan el acorde; las que llegan después son adornos.
  final int refineWindowMicros;

  /// Bonificación externa (la tonalidad, en la siguiente fase).
  ChordPrior? prior;

  final List<DetectedChord> chords = [];

  /// Último reconocimiento, aunque se haya fusionado con el acorde anterior.
  ChordRecognition? lastRecognition;

  /// Ataques de acorde (también volver a tocar el mismo, que en la secuencia
  /// no se duplica). Los adornos de una sola nota no cuentan. Sirve para
  /// seguir una canción donde dos partes se tocan con el mismo acorde.
  int attacks = 0;

  /// Instante del último ataque.
  int? lastAttackMicros;

  Set<int> get heldNotes => segmenter.heldNotes;
  int? get pendingCloseMicros => segmenter.pendingCloseMicros;

  /// Devuelve true si cambió la secuencia o el último reconocimiento.
  bool add(MidiEvent event) => _process(segmenter.add(event));

  bool advanceTo(int timeMicros) => _process(segmenter.advanceTo(timeMicros));

  bool flush() {
    final group = segmenter.flush();
    return group != null && _process([group]);
  }

  void reset() {
    segmenter.reset();
    chords.clear();
    lastRecognition = null;
    attacks = 0;
    lastAttackMicros = null;
  }

  bool _process(List<NoteGroup> groups) {
    var changed = false;
    for (final g in groups) {
      final rec = recognizer.recognize(g.notes, prior: prior);
      if (rec == null || !_isChord(g, rec)) continue;
      lastRecognition = rec;
      _append(g, rec);
      if (!(g.onsets == 1 && g.bassHeld)) {
        attacks++;
        lastAttackMicros = g.startMicros;
      }
      changed = true;
    }
    return changed;
  }

  /// Por debajo de C4 una nota funciona como bajo.
  static const int bassRegisterTop = 60;

  // Dos notas distintas son un intervalo (melodía, adorno), no un acorde;
  // salvo la quinta (acorde de potencia) y un bajo grave con su 3ª encima:
  // D2 D3 F#4 es un D con la 5ª omitida.
  static bool _isChord(NoteGroup group, ChordRecognition rec) {
    final pcs = group.pitchClasses;
    if (pcs.length >= 3 || rec.best.quality == ChordQuality.power) return true;
    if (pcs.length != 2 || group.bassNote >= bassRegisterTop) return false;
    final bass = group.bassNote % 12;
    final other = pcs.firstWhere((p) => p != bass);
    final interval = (other - bass) % 12;
    return interval == 3 || interval == 4;
  }

  void _append(NoteGroup group, ChordRecognition rec) {
    final chord = rec.best;
    if (chords.isNotEmpty) {
      final last = chords.last;
      if (last.chord == chord) return;
      final rolled = group.startMicros - last.startMicros < refineWindowMicros;
      if (rolled &&
          group.extendsPrevious &&
          last.chord.root == chord.root &&
          last.chord.bass == chord.bass) {
        last
          ..recognition = rec
          ..notes = group.notes;
        // Refinar puede dejarlo igual al anterior (Eb, Eb5 → Eb): se unen.
        if (chords.length >= 2 && chords[chords.length - 2].chord == chord) {
          chords.removeLast();
          chords.last.endMicros = null;
        }
        return;
      }
      // Adorno: una sola nota nueva sobre el bajo sostenido que deja la misma
      // fundamental y bajo (D2 D3 + G4 → F#4 → G4) no cambia el acorde.
      if (group.onsets == 1 &&
          group.bassHeld &&
          last.chord.root == chord.root &&
          last.chord.bass == chord.bass) {
        return;
      }
      if (group.startMicros - last.startMicros < minChordMicros) {
        chords.removeLast();
        if (chords.isNotEmpty && chords.last.chord == chord) {
          chords.last.endMicros = null;
          return;
        }
      }
    }
    if (chords.isNotEmpty) chords.last.endMicros = group.startMicros;
    chords.add(DetectedChord(startMicros: group.startMicros, recognition: rec, notes: group.notes));
  }
}
