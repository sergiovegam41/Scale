import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'app_dir.dart';
import 'package:scale_core/scale_core.dart';

/// Canciones guardadas localmente, un archivo JSON por canción.
class SongRepository extends ChangeNotifier {
  /// [_directory] solo se pasa en pruebas; por defecto, documentos de la app.
  SongRepository([this._directory]);

  Directory? _directory;
  final List<Song> _songs = [];
  bool loaded = false;

  /// Archivos que no se pudieron leer (se dejan intactos en disco).
  final List<String> unreadable = [];

  /// Más recientes primero.
  List<Song> get songs => List.unmodifiable(_songs);

  Future<Directory> _dir() async {
    final dir = _directory ??= Directory('${(await appDataDirectory()).path}/songs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> load() async {
    final dir = await _dir();
    _songs.clear();
    unreadable.clear();
    final upgraded = <Song>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final song = Song.fromJson(jsonDecode(await entity.readAsString()) as Map<String, dynamic>);
        if (_upgrade(song)) upgraded.add(song);
        _songs.add(song);
      } catch (e) {
        unreadable.add(entity.path);
        debugPrint('No se pudo leer ${entity.path}: $e');
      }
    }
    _sort();
    loaded = true;
    notifyListeners();
    for (final song in upgraded) {
      await save(song);
    }
  }

  static final RegExp _letterLabel = RegExp(r'^[A-Z]$');

  /// Canciones guardadas antes de los nombres musicales: si todas sus
  /// secciones siguen con la letra automática (A, B…, fácil de confundir con
  /// una tonalidad), se vuelven a detectar con nombres; las modulaciones no
  /// ajustadas a mano se recalculan con el criterio actual.
  static bool _upgrade(Song song) {
    final oldLabels = song.sections.isNotEmpty &&
        song.sections.every((s) => s.kind == SectionKind.other && _letterLabel.hasMatch(s.label));
    final before = song.keyRegions.length;
    if (!oldLabels && (song.keyRegionsManual || before <= 1)) return false;
    SongAnalyzer.analyze(song, sections: oldLabels);
    return oldLabels || song.keyRegions.length != before;
  }

  Song? byId(String id) {
    for (final s in _songs) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> save(Song song) async {
    song.updatedAt = DateTime.now();
    final dir = await _dir();
    // Se escribe a un temporal y se renombra para no dejar archivos a medias.
    final tmp = File('${dir.path}/${song.id}.json.tmp');
    await tmp.writeAsString(jsonEncode(song.toJson()), flush: true);
    await tmp.rename('${dir.path}/${song.id}.json');
    _songs.removeWhere((s) => s.id == song.id);
    _songs.add(song);
    _sort();
    notifyListeners();
  }

  Future<void> delete(Song song) async {
    final file = File('${(await _dir()).path}/${song.id}.json');
    if (await file.exists()) await file.delete();
    _songs.removeWhere((s) => s.id == song.id);
    notifyListeners();
  }

  void _sort() => _songs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}
