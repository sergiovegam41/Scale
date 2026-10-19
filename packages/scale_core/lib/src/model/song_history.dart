import 'song.dart';

/// Deshacer y rehacer cambios de edición de una canción.
///
/// Antes de cada cambio se llama a [record]; se guarda una foto de lo
/// editable (las tomas MIDI no cambian al editar y no se copian).
class SongHistory {
  SongHistory(this.song, {this.limit = 60});

  final Song song;
  final int limit;
  final List<Map<String, dynamic>> _undo = [];
  final List<Map<String, dynamic>> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void record() {
    _undo.add(song.editState());
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    _redo.add(song.editState());
    song.restoreEditState(_undo.removeLast());
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(song.editState());
    song.restoreEditState(_redo.removeLast());
    return true;
  }
}
