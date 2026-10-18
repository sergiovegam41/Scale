import '../model/song.dart';
import '../theory/chord.dart';

enum FollowStatus {
  /// Aún no se tocó el primer acorde.
  waiting,

  /// Se tocó el acorde esperado.
  onTrack,

  /// Se reconoció que el músico saltó a otro punto (repitió una parte).
  jumped,

  /// Lo tocado no coincide con lo esperado ni con otro punto claro.
  offScript,

  /// Se llegó al último acorde.
  finished,
}

/// Sigue a quien toca a lo largo de la canción (modo "tocar en vivo").
///
/// Avanza cuando se toca el acorde siguiente (coincidencia flexible: misma
/// fundamental y familia compatible; G/B, Gadd9 y Gsus4 valen como G). Las
/// vueltas ×N están en la secuencia lineal, así que se recorren solas.
///
/// Si lo tocado no es lo esperado, busca dónde seguir: los dos últimos
/// acordes coinciden con dos seguidos de la canción (el más cercano hacia
/// adelante), o el acorde coincide con el inicio de una sola parte (en
/// worship se repite el coro de improviso). Si no hay nada claro, espera.
class SongFollower {
  SongFollower(Song song)
      : chords = [for (final c in song.chords) c.chord],
        _durations = [for (final c in song.chords) c.durationMicros],
        _starts = {
          for (final o in song.arrangement) o.start,
        }..remove(null);

  /// Fracción de la duración grabada de un acorde tras la cual volver a
  /// atacarlo cuenta como el siguiente, si el siguiente es el mismo acorde
  /// (una parte termina en G y la otra empieza en G).
  static const double sameChordAdvance = 0.6;

  final List<Chord> chords;
  final List<int?> _durations;
  final Set<int> _starts;

  /// Instante (del reloj de quien llama) en que se llegó al acorde actual.
  int? _enteredAt;

  /// Último acorde tocado que coincidió (−1 = todavía ninguno).
  int position = -1;
  FollowStatus status = FollowStatus.waiting;

  /// Lo último que se tocó (aunque no coincidiera).
  Chord? lastPlayed;
  final List<Chord> _recent = [];

  int? get next => position + 1 < chords.length ? position + 1 : null;

  /// Acorde que se espera tocar.
  Chord? get expected => next == null ? null : chords[next!];

  void reset() {
    position = -1;
    status = FollowStatus.waiting;
    lastPlayed = null;
    _enteredAt = null;
    _recent.clear();
  }

  /// Saltar a mano: el acorde [index] pasa a ser el esperado.
  void jumpTo(int index) {
    position = index.clamp(0, chords.length) - 1;
    status = position < 0 ? FollowStatus.waiting : FollowStatus.onTrack;
    _recent.clear();
    _enteredAt = null;
    _jumped = true;
  }

  /// Tras un salto a mano el acorde "actual" no se tocó: manda el esperado.
  bool _jumped = false;

  /// Cada ataque de acorde. [atMicros] (cualquier reloj, siempre el mismo)
  /// permite distinguir un golpe de ritmo de pasar al siguiente acorde
  /// cuando ambos son el mismo.
  FollowStatus onChordPlayed(Chord played, {int? atMicros}) {
    lastPlayed = played;
    if (chords.isEmpty) return status;
    final n = next;
    final toNext = n == null ? 0 : closeness(played, chords[n]);
    final toCurrent = position < 0 ? 0 : closeness(played, chords[position]);
    final matchesNext = toNext > 0;

    // Volver a tocar el acorde actual (ritmo) no cambia nada, salvo que se
    // parezca más al siguiente (D → Dsus4), se acabe de saltar a mano o el
    // siguiente sea el mismo acorde y ya haya pasado su tiempo.
    if (toCurrent > 0 &&
        !(matchesNext && (_jumped || toNext > toCurrent || _currentIsDue(atMicros)))) {
      return status;
    }
    _jumped = false;

    if (n != null && matchesNext) {
      _advanceTo(n, FollowStatus.onTrack, atMicros);
      return status;
    }

    _recent.add(played);
    if (_recent.length > 2) _recent.removeAt(0);

    final resync = _resync(played);
    if (resync != null) {
      _advanceTo(resync, FollowStatus.jumped, atMicros);
    } else {
      status = FollowStatus.offScript;
    }
    return status;
  }

  /// El acorde actual ya duró lo suficiente (según la grabación) como para
  /// que un nuevo ataque sea el siguiente. Sin tiempos (canción escrita), sí.
  bool _currentIsDue(int? atMicros) {
    final duration = position < 0 ? null : _durations[position];
    final entered = _enteredAt;
    if (atMicros == null || duration == null || entered == null) return true;
    return atMicros - entered >= duration * sameChordAdvance;
  }

  /// Qué tanto se parece lo tocado a un acorde de la canción: 3 idéntico,
  /// 2 misma calidad con otro bajo, 1 coincidencia flexible, 0 distinto.
  static int closeness(Chord played, Chord target) {
    if (played == target) return 3;
    if (played.root == target.root && played.quality == target.quality) return 2;
    return played.matchesFlexibly(target) ? 1 : 0;
  }

  void _advanceTo(int index, FollowStatus reason, int? atMicros) {
    position = index;
    _enteredAt = atMicros;
    status = index == chords.length - 1 ? FollowStatus.finished : reason;
    _recent.clear();
  }

  int? _resync(Chord played) {
    final from = position;
    int distance(int p) => (p - from) % chords.length;

    // Dos acordes seguidos que coinciden: el más cercano hacia adelante.
    if (_recent.length == 2) {
      final previous = _recent.first;
      final matches = [
        for (var p = 1; p < chords.length; p++)
          if (played.matchesFlexibly(chords[p]) && previous.matchesFlexibly(chords[p - 1])) p,
      ]..sort((a, b) => distance(a).compareTo(distance(b)));
      if (matches.isNotEmpty) return matches.first;
    }

    // Inicio de una parte, si es una sola la que empieza con ese acorde.
    final starts = [
      for (final s in _starts)
        if (s != next && s < chords.length && played.matchesFlexibly(chords[s])) s,
    ];
    if (starts.length == 1) return starts.single;
    return null;
  }
}
