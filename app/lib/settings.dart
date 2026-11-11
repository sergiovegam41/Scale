import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'ai/ai_client.dart' show AiProvider;
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

  /// Servicio de IA para importar (Claude o Groq).
  AiProvider get aiProvider => _aiProvider;
  set aiProvider(AiProvider value) => _set(() => _aiProvider = value, value != _aiProvider);
  AiProvider _aiProvider = AiProvider.claude;

  /// API key de Groq (también solo en este dispositivo).
  String get groqApiKey => _groqApiKey;
  set groqApiKey(String value) => _set(() => _groqApiKey = value.trim(), value.trim() != _groqApiKey);
  String _groqApiKey = '';

  /// Modelos de Groq; vacío = el predeterminado de la app. Groq cambia sus
  /// modelos seguido, así se puede cambiar sin actualizar la app.
  String get groqTextModel => _groqTextModel;
  set groqTextModel(String value) =>
      _set(() => _groqTextModel = value.trim(), value.trim() != _groqTextModel);
  String _groqTextModel = '';

  String get groqVisionModel => _groqVisionModel;
  set groqVisionModel(String value) =>
      _set(() => _groqVisionModel = value.trim(), value.trim() != _groqVisionModel);
  String _groqVisionModel = '';

  String apiKeyFor(AiProvider provider) => switch (provider) {
        AiProvider.claude => _anthropicApiKey,
        AiProvider.groq => _groqApiKey,
      };

  void setApiKey(AiProvider provider, String value) => switch (provider) {
        AiProvider.claude => anthropicApiKey = value,
        AiProvider.groq => groqApiKey = value,
      };

  /// Hay API key para el servicio elegido.
  bool get hasApiKey => apiKeyFor(_aiProvider).isNotEmpty;

  /// Sitios de búsqueda usados hace poco (ids o dominios, el último primero).
  List<String> get recentSites => List.unmodifiable(_recentSites);
  void useSite(String id) {
    final next = [id, ..._recentSites.where((s) => s != id)].take(12).toList();
    _set(() => _recentSites = next, !listEquals(next, _recentSites));
  }
  List<String> _recentSites = [];

  /// Sitios agregados por el usuario: nombre y dominio (se busca en Google
  /// con `site:`).
  List<({String name, String host})> get customSites => List.unmodifiable(_customSites);
  void addCustomSite(String name, String host) {
    final h = host.trim().toLowerCase();
    if (h.isEmpty) return;
    _set(
      () => _customSites = [..._customSites.where((s) => s.host != h), (name: name.trim().isEmpty ? h : name.trim(), host: h)],
      true,
    );
  }
  void removeCustomSite(String host) =>
      _set(() => _customSites = [..._customSites.where((s) => s.host != host)], _customSites.any((s) => s.host == host));
  List<({String name, String host})> _customSites = [];

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
      _aiProvider = AiProvider.values.asNameMap()[json['aiProvider']] ?? _aiProvider;
      _groqApiKey = json['groqApiKey'] as String? ?? _groqApiKey;
      _groqTextModel = json['groqTextModel'] as String? ?? _groqTextModel;
      _groqVisionModel = json['groqVisionModel'] as String? ?? _groqVisionModel;
      _songSort = SongSort.values.asNameMap()[json['songSort']] ?? _songSort;
      _recentSites = [for (final id in (json['recentSites'] as List?) ?? const []) id as String];
      _customSites = [
        for (final m in (json['customSites'] as List?) ?? const [])
          if (m is Map) (name: '${m['name'] ?? m['host']}', host: '${m['host']}'),
      ];
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
              'aiProvider': _aiProvider.name,
              'groqApiKey': _groqApiKey,
              'groqTextModel': _groqTextModel,
              'groqVisionModel': _groqVisionModel,
              'songSort': _songSort.name,
              'recentSites': _recentSites,
              'customSites': [for (final c in _customSites) {'name': c.name, 'host': c.host}],
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
