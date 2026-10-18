import 'dart:math' as math;

import '../midi/midi_event.dart';

/// Grupo de notas que suenan juntas tras un ataque: la entrada del reconocedor.
class NoteGroup {
  NoteGroup({
    required this.startMicros,
    required this.notes,
    required this.extendsPrevious,
    this.onsets = 0,
    this.bassHeld = false,
  });

  final int startMicros;

  /// Notas MIDI (con octava).
  final Set<int> notes;

  /// Se mantuvieron todas las notas del grupo anterior y solo se añadieron
  /// otras (p. ej. sumar la 9ª a un acorde sostenido).
  final bool extendsPrevious;

  /// Notas atacadas en este grupo (el resto venían sostenidas).
  final int onsets;

  /// El bajo ya estaba presionado antes de este ataque.
  final bool bassHeld;

  Set<int> get pitchClasses => {for (final n in notes) n % 12};

  int get bassNote => notes.reduce(math.min);
}

/// Agrupa el flujo de note on/off en acordes.
///
/// Las notas que empiezan dentro de [clusterWindowMicros] forman un mismo
/// ataque. Al cerrarse, el acorde son las teclas presionadas más las del
/// ataque. Si el ataque tiene menos de 3 clases de altura (arpegio con
/// pedal), se suman las notas recientes sostenidas por el pedal.
///
/// Es determinista: el tiempo solo avanza con los eventos o con [advanceTo].
class ChordSegmenter {
  ChordSegmenter({
    this.clusterWindowMicros = 70000,
    this.arpeggioWindowMicros = 1500000,
  });

  final int clusterWindowMicros;
  final int arpeggioWindowMicros;

  final Set<int> _held = {};
  final Map<int, int> _pedalNotes = {};
  final Set<int> _cluster = {};
  bool _pedalDown = false;
  int? _clusterStart;
  int _lastOnset = 0;
  Set<int> _previous = const {};

  /// Teclas presionadas justo antes de que empezara el ataque en curso.
  Set<int> _heldBeforeCluster = const {};

  /// Teclas físicamente presionadas en este momento.
  Set<int> get heldNotes => Set.unmodifiable(_held);

  bool get pedalDown => _pedalDown;

  /// Instante en que se cerrará el ataque en curso, si hay uno.
  int? get pendingCloseMicros =>
      _clusterStart == null ? null : _lastOnset + clusterWindowMicros;

  List<NoteGroup> add(MidiEvent event) {
    final out = advanceTo(event.timeMicros);
    if (event.isNoteOn) {
      if (_clusterStart == null) {
        _clusterStart = event.timeMicros;
        _heldBeforeCluster = {..._held};
      }
      _cluster.add(event.data1);
      _held.add(event.data1);
      _lastOnset = event.timeMicros;
      if (_pedalDown) _pedalNotes[event.data1] = event.timeMicros;
    } else if (event.isNoteOff) {
      _held.remove(event.data1);
    } else if (event.isSustain) {
      if (event.sustainDown && !_pedalDown) {
        _pedalDown = true;
        _pedalNotes
          ..clear()
          ..addAll({for (final n in _held) n: event.timeMicros});
      } else if (!event.sustainDown) {
        _pedalDown = false;
        _pedalNotes.clear();
      }
    }
    return out;
  }

  List<NoteGroup> advanceTo(int timeMicros) {
    final close = pendingCloseMicros;
    if (close != null && timeMicros >= close) return [_close()];
    return const [];
  }

  /// Cierra el ataque en curso sin esperar (fin de la toma).
  NoteGroup? flush() => _clusterStart == null ? null : _close();

  void reset() {
    _held.clear();
    _pedalNotes.clear();
    _cluster.clear();
    _pedalDown = false;
    _clusterStart = null;
    _previous = const {};
  }

  NoteGroup _close() {
    final start = _clusterStart!;
    final notes = <int>{..._held, ..._cluster};
    if (_pedalDown && {for (final n in notes) n % 12}.length < 3) {
      for (final e in _pedalNotes.entries) {
        if (e.value >= start - arpeggioWindowMicros) notes.add(e.key);
      }
    }
    final extendsPrevious = _previous.isNotEmpty &&
        _held.containsAll(_previous) &&
        !_previous.containsAll(notes);
    final group = NoteGroup(
      startMicros: start,
      notes: notes,
      extendsPrevious: extendsPrevious,
      onsets: _cluster.length,
      bassHeld: _heldBeforeCluster.contains(notes.reduce(math.min)),
    );
    _previous = notes;
    _cluster.clear();
    _clusterStart = null;
    _heldBeforeCluster = const {};
    return group;
  }
}
