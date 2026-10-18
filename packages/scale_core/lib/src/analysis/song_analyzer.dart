import '../model/song.dart';
import 'key_regions.dart';
import 'live_analyzer.dart';
import 'part_detector.dart';

/// Construye y reanaliza canciones.
class SongAnalyzer {
  const SongAnalyzer._();

  /// Reconstruye los acordes desde el MIDI crudo con el mismo proceso que
  /// se ve en vivo.
  static List<ChordEvent> chordsFromTake(Take take) {
    final analyzer = LiveAnalyzer();
    for (final e in take.events) {
      analyzer.add(e.transposed(-take.inputTranspose));
    }
    analyzer.flush();
    final end = take.durationMicros;
    return [
      for (final d in analyzer.chords)
        ChordEvent(
          chord: d.chord,
          startMicros: d.startMicros,
          durationMicros: (d.endMicros ?? end) - d.startMicros,
          confidence: d.confidence,
          alternatives: [for (final a in d.recognition.alternatives) a.chord],
        ),
    ];
  }

  static Song fromTake({required String title, required Take take}) {
    final song = Song.create(title: title)
      ..takes.add(take)
      ..chords.addAll(chordsFromTake(take));
    analyze(song);
    return song;
  }

  /// Propone partes (pausas y repeticiones; ver [PartDetector]) si
  /// [sections], y recalcula tonalidad y modulaciones salvo las que fijó el
  /// usuario.
  static void analyze(Song song, {bool sections = true}) {
    if (sections) detectParts(song);

    final chords = [for (final c in song.chords) c.chord];
    final weights = [for (final c in song.chords) LiveAnalyzer.durationWeight(c.durationMicros)];
    if (!song.keyRegionsManual || song.keyRegions.isEmpty) {
      song
        ..keyRegions = KeyAnalyzer.regions(chords, weights: weights)
        ..keyRegionsManual = false;
    }

    if (!song.keyManual) {
      if (song.keyRegions.isEmpty) {
        song
          ..key = null
          ..keyConfidence = null;
      } else {
        // La tonalidad principal es la que ocupa más acordes (la primera si
        // empatan); su seguridad se mide dentro de su región.
        var main = song.keyRegions.first;
        for (final r in song.keyRegions) {
          if (r.length > main.length) main = r;
        }
        song
          ..key = main.key
          ..keyConfidence = main.confidence;
      }
    }
    song.updatedAt = DateTime.now();
  }

  /// Reemplaza las secciones por las partes detectadas. Puede partir acordes
  /// sostenidos entre dos vueltas, así que las modulaciones se recalculan.
  static void detectParts(Song song) {
    final take = song.takes.length == 1 ? song.takes.single : null;
    final silences = take == null ? null : PartDetector.silencesBefore(take, song.chords);
    final detected = PartDetector.detect(song.chords, silenceBefore: silences);
    final split = detected.chords.length != song.chords.length;
    song.chords
      ..clear()
      ..addAll(detected.chords);
    song
      ..sections = detected.sections
      ..arrangement = detected.arrangement;
    if (split) song.keyRegionsManual = false;
  }
}
