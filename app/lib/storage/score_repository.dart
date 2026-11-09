import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import 'app_dir.dart';

/// Partituras guardadas localmente, un archivo JSON por partitura.
class ScoreRepository extends ChangeNotifier {
  /// [_directory] solo se pasa en pruebas; por defecto, datos de la app.
  ScoreRepository([this._directory]);

  Directory? _directory;
  final List<Score> _scores = [];
  bool loaded = false;

  /// Archivos que no se pudieron leer (se dejan intactos en disco).
  final List<String> unreadable = [];

  /// Más recientes primero.
  List<Score> get scores => List.unmodifiable(_scores);

  Future<Directory> _dir() async {
    final dir = _directory ??= Directory('${(await appDataDirectory()).path}/scores');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> load() async {
    final dir = await _dir();
    _scores.clear();
    unreadable.clear();
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final text = await entity.readAsString();
        _scores.add(await compute(_decode, text));
      } catch (e) {
        unreadable.add(entity.path);
        debugPrint('No se pudo leer ${entity.path}: $e');
      }
    }
    _sort();
    loaded = true;
    notifyListeners();
  }

  static Score _decode(String text) => Score.fromJson(jsonDecode(text) as Map<String, dynamic>);

  Score? byId(String id) {
    for (final s in _scores) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> save(Score score) async {
    score.updatedAt = DateTime.now();
    final dir = await _dir();
    // Se escribe a un temporal y se renombra para no dejar archivos a medias.
    final tmp = File('${dir.path}/${score.id}.json.tmp');
    await tmp.writeAsString(jsonEncode(score.toJson()), flush: true);
    await tmp.rename('${dir.path}/${score.id}.json');
    _scores.removeWhere((s) => s.id == score.id);
    _scores.add(score);
    _sort();
    notifyListeners();
  }

  Future<void> delete(Score score) async {
    final file = File('${(await _dir()).path}/${score.id}.json');
    if (await file.exists()) await file.delete();
    _scores.removeWhere((s) => s.id == score.id);
    notifyListeners();
  }

  void _sort() => _scores.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// Id nuevo para una partitura.
  static String newId() => 'sc${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
