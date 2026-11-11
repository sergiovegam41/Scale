import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../storage/score_repository.dart';

/// Qué es un archivo descargado o elegido, mirando su contenido (y si no
/// alcanza, su nombre).
enum ScoreFileKind {
  midi,
  musicXml,
  pdf,
  html,
  unknown;

  bool get importable => this == midi || this == musicXml;

  static ScoreFileKind of(List<int> bytes, {String name = '', String mimeType = ''}) {
    bool starts(String magic) =>
        bytes.length >= magic.length && String.fromCharCodes(bytes.take(magic.length)) == magic;
    if (starts('MThd')) return midi;
    if (starts('%PDF')) return pdf;
    final lower = name.toLowerCase();
    if (starts('PK')) {
      // Un .mxl es un zip; otros zips no sirven.
      return lower.endsWith('.mxl') || mimeType.contains('musicxml') || _zipHasMusicXml(bytes) ? musicXml : unknown;
    }
    final head = utf8.decode(bytes.take(4096).toList(), allowMalformed: true).toLowerCase();
    if (head.contains('<score-partwise') || head.contains('<score-timewise')) return musicXml;
    if (head.contains('<html') || head.contains('<!doctype html') || mimeType.contains('html')) return html;
    return unknown;
  }

  static bool _zipHasMusicXml(List<int> bytes) {
    // Los .mxl traen META-INF/container.xml; basta buscar el nombre.
    final text = latin1.decode(bytes.take(65536).toList(), allowInvalid: true);
    return text.contains('META-INF/container.xml');
  }
}

/// Convertir un archivo MIDI o MusicXML en partitura (sin guardarla).
class ScoreImport {
  ScoreImport._();

  /// Devuelve null si el usuario canceló al elegir las pistas del MIDI.
  /// Lanza [FormatException] si el archivo no sirve.
  static Future<Score?> fromBytes(
    BuildContext context,
    Uint8List bytes,
    String name, {
    ScoreFileKind? kind,
  }) async {
    final k = kind ?? ScoreFileKind.of(bytes, name: name);
    final id = ScoreRepository.newId();
    switch (k) {
      case ScoreFileKind.midi:
        final sources = await _pickSources(context, MidiFile.parse(bytes), name);
        if (sources == null) return null;
        final score = await compute(_parseMidi, (bytes, name, id, sources));
        if (score == null) throw const FormatException('no tiene notas (o no elegiste ninguna pista)');
        return score;
      case ScoreFileKind.musicXml:
        return compute(_parse, (bytes, name, id));
      case ScoreFileKind.pdf:
        throw const FormatException(
          'es un PDF. Todavía no se pueden importar partituras en PDF; busca la versión MIDI o MusicXML.',
        );
      case ScoreFileKind.html:
      case ScoreFileKind.unknown:
        throw const FormatException('no es MusicXML (.musicxml, .mxl) ni MIDI (.mid)');
    }
  }

  static Score _parse((Uint8List, String, String) args) =>
      MusicXmlReader.readBytes(args.$1, id: args.$3, fileName: args.$2);

  static Score? _parseMidi((Uint8List, String, String, Set<String>) args) =>
      MidiFileImporter.toScore(MidiFile.parse(args.$1), id: args.$3, fileName: args.$2, sources: args.$4);

  /// Qué pistas del MIDI entran en la partitura. Con una o dos (sin contar
  /// la batería) entran todas sin preguntar.
  static Future<Set<String>?> _pickSources(BuildContext context, MidiFile file, String name) async {
    final playable = [
      for (final s in file.sources)
        if (!s.drums) s,
    ];
    if (playable.length <= 2) return {for (final s in playable) s.id};
    if (!context.mounted) return null;
    return showDialog<Set<String>>(
      context: context,
      builder: (_) => SourcesDialog(fileName: name, sources: file.sources),
    );
  }
}

/// Elegir las pistas de un MIDI con varios instrumentos.
class SourcesDialog extends StatefulWidget {
  const SourcesDialog({super.key, required this.fileName, required this.sources});

  final String fileName;
  final List<MidiSource> sources;

  @override
  State<SourcesDialog> createState() => _SourcesDialogState();
}

class _SourcesDialogState extends State<SourcesDialog> {
  late final Set<String> chosen = {
    for (final s in widget.sources)
      if (!s.drums) s.id,
  };

  static String _note(int midi) {
    const names = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
    return '${names[midi % 12]}${midi ~/ 12 - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pianos = [
      for (final s in widget.sources)
        if (!s.drums && (s.program == null || s.program! < 8)) s.id,
    ];
    final playable = widget.sources.where((s) => !s.drums).length;
    return AlertDialog(
      title: const Text('¿Qué pistas entran?'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${widget.fileName}" tiene varios instrumentos. Lo que elijas se junta en una '
              'partitura de piano (dos pentagramas). Para que quede limpia, deja la melodía y el '
              'acompañamiento, o solo las pistas de piano.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (pianos.isNotEmpty && pianos.length < playable)
              TextButton.icon(
                onPressed: () => setState(
                  () => chosen
                    ..clear()
                    ..addAll(pianos),
                ),
                icon: const Icon(Icons.piano),
                label: const Text('Solo las de piano'),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in widget.sources)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: chosen.contains(s.id),
                      onChanged: (v) => setState(() => v == true ? chosen.add(s.id) : chosen.remove(s.id)),
                      title: Text(s.name ?? 'Pista ${s.track + 1}'),
                      subtitle: Text(
                        '${s.instrument} · ${s.notes} notas'
                        '${s.drums ? '' : ' · ${_note(s.lowest)} a ${_note(s.highest)}'}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: chosen.isEmpty ? null : () => Navigator.of(context).pop(Set.of(chosen)),
          child: const Text('Importar'),
        ),
      ],
    );
  }
}
