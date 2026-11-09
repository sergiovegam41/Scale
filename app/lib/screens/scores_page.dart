import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../midi/keyboard_state.dart';
import '../midi/midi_service.dart';
import '../storage/score_repository.dart';
import '../storage/song_repository.dart';
import '../widgets/dialogs.dart';
import 'record_score_page.dart';
import 'score_page.dart';

/// Biblioteca de partituras: importar MusicXML y abrirlas.
class ScoresPage extends StatefulWidget {
  const ScoresPage({
    super.key,
    required this.repo,
    required this.midi,
    required this.keyboard,
    required this.engine,
    required this.songs,
    this.notation = Notation.american,
  });

  final ScoreRepository repo;
  final MidiService midi;
  final KeyboardState keyboard;
  final ChordEngine engine;
  final SongRepository songs;
  final Notation notation;

  @override
  State<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends State<ScoresPage> {
  bool importing = false;

  static const _extensions = ['musicxml', 'mxl', 'xml'];

  void _open(Score score) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScorePage(score: score, midi: widget.midi, repo: widget.repo, notation: widget.notation),
    ));
  }

  void _record() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecordScorePage(
        midi: widget.midi,
        keyboard: widget.keyboard,
        engine: widget.engine,
        scores: widget.repo,
        songs: widget.songs,
        notation: widget.notation,
      ),
    ));
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final List<PlatformFile> files;
    try {
      // En Android las extensiones de MusicXML no siempre tienen tipo MIME
      // registrado: se elige cualquier archivo y se comprueba después.
      final android = defaultTargetPlatform == TargetPlatform.android;
      files = await FilePicker.pickFiles(
        dialogTitle: 'Importar MusicXML',
        type: android ? FileType.any : FileType.custom,
        allowedExtensions: android ? null : _extensions,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir el selector de archivos: $e')));
      return;
    }
    if (files.isEmpty) return;
    setState(() => importing = true);
    final imported = <Score>[];
    final failed = <String>[];
    for (final file in files) {
      final ext = (file.extension ?? '').toLowerCase();
      if (!_extensions.contains(ext)) {
        failed.add('${file.name}: no es MusicXML (.musicxml, .mxl o .xml)');
        continue;
      }
      try {
        final bytes = await file.readAsBytes();
        final score = await compute(_parse, (bytes, file.name, ScoreRepository.newId()));
        await widget.repo.save(score);
        imported.add(score);
      } catch (e) {
        failed.add('${file.name}: ${e is FormatException ? e.message : e}');
      }
    }
    if (!mounted) return;
    setState(() => importing = false);
    if (failed.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(imported.isEmpty ? 'No se pudo importar' : 'Algunos archivos no se importaron'),
          content: Text(failed.join('\n\n')),
          actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Aceptar'))],
        ),
      );
    }
    if (imported.length == 1) _open(imported.single);
  }

  static Score _parse((Uint8List, String, String) args) =>
      MusicXmlReader.readBytes(args.$1, id: args.$3, fileName: args.$2);

  Future<void> _menu(Score score, String action) async {
    switch (action) {
      case 'rename':
        final title = await askText(context, title: 'Nombre de la partitura', initial: score.title);
        if (title == null || title.trim().isEmpty) return;
        score.title = title.trim();
        await widget.repo.save(score);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('¿Borrar la partitura?'),
            content: Text('"${score.title}" se borrará de esta tablet. No se puede deshacer.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Borrar')),
            ],
          ),
        );
        if (ok == true) await widget.repo.delete(score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.repo,
          builder: (context, _) {
            final scores = widget.repo.scores;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('Partituras', style: text.headlineSmall)),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935), foregroundColor: Colors.white),
                        onPressed: _record,
                        icon: const Icon(Icons.fiber_manual_record),
                        label: const Text('Grabar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: importing ? null : _import,
                        icon: importing
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.file_open),
                        label: const Text('Importar MusicXML'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: !widget.repo.loaded
                      ? const Center(child: CircularProgressIndicator())
                      : scores.isEmpty
                          ? _empty(text, scheme)
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              itemCount: scores.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 6),
                              itemBuilder: (context, i) => _tile(scores[i], text, scheme),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _empty(TextTheme text, ColorScheme scheme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.queue_music, size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('Todavía no hay partituras', style: text.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Graba tocando con metrónomo, o importa un archivo MusicXML\n'
                '(.musicxml o .mxl; desde MuseScore: Archivo › Exportar › MusicXML).',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );

  Widget _tile(Score score, TextTheme text, ColorScheme scheme) {
    final details = [
      if (score.composer != null) score.composer!,
      '${score.measures.length} compases',
      '${score.noteCount} notas',
      if (score.parts.length > 1) '${score.parts.length} partes',
      if (score.recording != null) 'grabada',
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(score.recording != null ? Icons.piano : Icons.description_outlined),
        title: Text(score.title, overflow: TextOverflow.ellipsis),
        subtitle: Text(details, overflow: TextOverflow.ellipsis),
        onTap: () => _open(score),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _menu(score, v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Renombrar')),
            PopupMenuItem(value: 'delete', child: Text('Borrar')),
          ],
        ),
      ),
    );
  }
}
