import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';

/// Modo "tocar en vivo": pasa cada ataque de acorde que detecta el motor al
/// seguidor de la canción (también volver a tocar el mismo acorde, que hace
/// falta cuando una parte termina y la siguiente empieza con él).
class LiveFollow extends ChangeNotifier {
  LiveFollow({required this.song, required this.engine}) : follower = SongFollower(song) {
    _seenAttacks = engine.attacks;
    engine.addListener(_onEngine);
  }

  final Song song;
  final ChordEngine engine;

  /// Se rehace cuando se edita la canción mientras se prueba.
  SongFollower follower;

  /// Acorde de la canción en el que se va (para ubicarlo tras una edición).
  ChordEvent? get currentEvent {
    final p = follower.position;
    return p >= 0 && p < song.chords.length ? song.chords[p] : null;
  }

  late int _seenAttacks;
  Chord? _lastChord;

  /// En pausa no sigue lo que se toca (por ejemplo, mientras se regraba).
  bool paused = false;

  void _onEngine() {
    final current = engine.current;
    if (paused) {
      _seenAttacks = engine.attacks;
      _lastChord = current?.chord;
      return;
    }
    if (current == null) return;
    // Un ataque nuevo, o el mismo acorde refinado (Gsus → G).
    final attacked = engine.attacks != _seenAttacks;
    if (!attacked && current.chord == _lastChord) return;
    _seenAttacks = engine.attacks;
    _lastChord = current.chord;
    follower.onChordPlayed(current.chord, atMicros: engine.lastAttackMicros);
    notifyListeners();
  }

  void jumpTo(int index) {
    follower.jumpTo(index);
    notifyListeners();
  }

  /// La canción cambió (edición): se vuelve a armar el seguidor y se sigue
  /// desde el mismo acorde [at] si todavía está.
  void rebuild({ChordEvent? at}) {
    follower = SongFollower(song);
    final index = at == null ? -1 : song.chords.indexWhere((e) => identical(e, at));
    if (index >= 0) placeAt(index);
    notifyListeners();
  }

  /// Ubica al seguidor como si se acabara de tocar el acorde [index].
  void placeAt(int index) {
    follower.jumpTo(index + 1);
    notifyListeners();
  }

  void restart() {
    follower.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    engine.removeListener(_onEngine);
    super.dispose();
  }
}
