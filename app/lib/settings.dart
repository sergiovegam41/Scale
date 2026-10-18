import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scale_core/scale_core.dart';

/// Qué se muestra en cada acorde de una canción.
enum ChordDisplay { chords, degrees, both }

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

  /// Capa de transpose de la pantalla en vivo (se recuerda entre sesiones).
  int get liveLayer => _liveLayer;
  set liveLayer(int value) => _set(() => _liveLayer = value, value != _liveLayer);
  int _liveLayer = 0;

  ChordFormatter get formatter => ChordFormatter(notation: _notation);

  String noteName(int midiNote) =>
      '${SpelledNote.byDefault(midiNote).name(_notation)}${midiNote ~/ 12 - 1}';

  Future<File> _target() async =>
      _file ??= File('${(await getApplicationDocumentsDirectory()).path}/settings.json');

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
            })))
        .catchError((Object e) {
      debugPrint('No se pudo guardar la configuración: $e');
      return File('');
    });
  }
}
