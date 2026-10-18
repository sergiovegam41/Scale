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
  final SongFollower follower;

  late int _seenAttacks;
  Chord? _lastChord;

  void _onEngine() {
    final current = engine.current;
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
