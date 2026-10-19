import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'storage/app_dir.dart';
import 'package:scale_core/scale_core.dart';

/// Qué se muestra en cada acorde de una canción.
enum ChordDisplay { chords, degrees, both }

/// Orden de la lista de canciones.
enum SongSort {
  recent('Recientes'),
  title('Título A–Z'),
  key('Tonalidad'),
  manual('Mi orden');

  const SongSort(this.label);

  final String label;
}

/// Preferencias compartidas por todas las pantallas; se guardan en el dispositivo.
class AppSettings extends ChangeNotifier {
  /// [_file] solo se pasa en pruebas; por defecto, documentos de la app.
  AppSettings([this._file]);

  File? _file;
  Notation _notation = Notation.american;
  ChordDisplay _display = ChordDisplay.chords;
  bool _pianoSendsTransposed = true;
  int _transposeRange = 12;

  Notation get notation => _notation;
  set notation(Notation value) => _set(() => _notation = value, value != _notation);

  ChordDisplay get display => _display;
  set display(ChordDisplay value) => _set(() => _display = value, value != _display);

  /// El piano manda por MIDI las notas ya movidas por su TRANSPOSE (lo que
  /// suena). Entonces la app resta la capa para ver las figuras originales.
  bool get pianoSendsTransposed => _pianoSendsTransposed;
  set pianoSendsTransposed(bool value) =>
      _set(() => _pianoSendsTransposed = value, value != _pianoSendsTransposed);

  /// Hasta cuántos semitonos (±) permite el transpose del piano.
  int get transposeRange => _transposeRange;
  set transposeRange(int value) => _set(() => _transposeRange = value, value != _transposeRange);

  /// API key de Anthropic para importar con IA. Solo se guarda en este
  /// dispositivo (nunca en el código ni en el repositorio).
  String get anthropicApiKey => _anthropicApiKey;
  set anthropicApiKey(String value) =>
      _set(() => _anthropicApiKey = value.trim(), value.trim() != _anthropicApiKey);
  String _anthropicApiKey = '';

  bool get hasApiKey => _anthropicApiKey.isNotEmpty;

  /// Capa de transpose de la pantalla en vivo (se recuerda entre sesiones).
  int get liveLayer => _liveLayer;
  set liveLayer(int value) => _set(() => _liveLayer = value, value != _liveLayer);
  int _liveLayer = 0;

  /// Cómo se ordena la lista de canciones.
  SongSort get songSort => _songSort;
  set songSort(SongSort value) => _set(() => _songSort = value, value != _songSort);
  SongSort _songSort = SongSort.recent;

  /// Orden a mano (ids de canciones); las que no están van primero.
  List<String> get songOrder => List.unmodifiable(_songOrder);
  set songOrder(List<String> value) =>
      _set(() => _songOrder = List.of(value), !listEquals(value, _songOrder));
  List<String> _songOrder = [];

  /// Canciones que están solo en el archivo (no en la lista para tocar).
  /// Las nuevas entran a la lista.
  Set<String> get archivedSongs => Set.unmodifiable(_archived);
  bool isArchived(String songId) => _archived.contains(songId);
  void setArchived(String songId, bool archived) => _set(
        () => archived ? _archived.add(songId) : _archived.remove(songId),
        archived != _archived.contains(songId),
      );
  Set<String> _archived = {};

  /// Orden del archivo (no tiene orden a mano).
  SongSort get archiveSort => _archiveSort;
  set archiveSort(SongSort value) => _set(() => _archiveSort = value, value != _archiveSort);
  SongSort _archiveSort = SongSort.title;

  ChordFormatter get formatter => ChordFormatter(notation: _notation);

  String noteName(int midiNote) =>
      '${SpelledNote.byDefault(midiNote).name(_notation)}${midiNote ~/ 12 - 1}';

  Future<File> _target() async =>
      _file ??= File('${(await appDataDirectory()).path}/settings.json');

  Future<void> load() async {
    try {
      final file = await _target();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _notation = Notation.values.asNameMap()[json['notation']] ?? _notation;
      _display = ChordDisplay.values.asNameMap()[json['display']] ?? _display;
      _pianoSendsTransposed = json['pianoSendsTransposed'] as bool? ?? _pianoSendsTransposed;
      _transposeRange = json['transposeRange'] as int? ?? _transposeRange;
      _liveLayer = json['liveLayer'] as int? ?? _liveLayer;
      _anthropicApiKey = json['anthropicApiKey'] as String? ?? _anthropicApiKey;
      _songSort = SongSort.values.asNameMap()[json['songSort']] ?? _songSort;
      _songOrder = [for (final id in (json['songOrder'] as List?) ?? const []) id as String];
      _archived = {for (final id in (json['archivedSongs'] as List?) ?? const []) id as String};
      _archiveSort = SongSort.values.asNameMap()[json['archiveSort']] ?? _archiveSort;
      notifyListeners();
    } catch (e) {
      debugPrint('No se pudo leer la configuración: $e');
    }
  }

  void _set(VoidCallback apply, bool changed) {
    if (!changed) return;
    apply();
    notifyListeners();
    _target()
        .then((f) => f.writeAsString(jsonEncode({
              'notation': _notation.name,
              'display': _display.name,
              'pianoSendsTransposed': _pianoSendsTransposed,
              'transposeRange': _transposeRange,
              'liveLayer': _liveLayer,
              'anthropicApiKey': _anthropicApiKey,
              'songSort': _songSort.name,
              'songOrder': _songOrder,
              'archivedSongs': _archived.toList(),
              'archiveSort': _archiveSort.name,
            })))
        .catchError((Object e) {
      debugPrint('No se pudo guardar la configuración: $e');
      return File('');
    });
  }
}
