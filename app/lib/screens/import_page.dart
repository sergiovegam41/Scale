import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scale_core/scale_core.dart';

import '../ai/import_session.dart';
import '../settings.dart';
import '../storage/song_repository.dart';
import '../widgets/chord_cell.dart';
import '../widgets/dialogs.dart';
import '../widgets/repeat_badge.dart';

/// Importar una canción desde capturas, fotos o texto, refinándola en un chat
/// con la IA. Al guardar, devuelve la canción con `Navigator.pop`.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.repo, required this.settings});

  final SongRepository repo;
  final AppSettings settings;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final ImportSession session = ImportSession(widget.settings.anthropicApiKey);
  final TextEditingController input = TextEditingController();
  final ScrollController chatScroll = ScrollController();
  final ImagePicker picker = ImagePicker();
  final List<ImportImage> pending = [];

  AppSettings get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    session.addListener(_scrollChatToEnd);
  }

  @override
  void dispose() {
    session.dispose();
    input.dispose();
    chatScroll.dispose();
    super.dispose();
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chatScroll.hasClients) {
        chatScroll.animateTo(
          chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  static String _mediaType(XFile file) {
    final type = file.mimeType;
    if (type != null && type.startsWith('image/')) return type;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  // Se reducen al tomarlas: ~1600 px bastan para leer un cifrado y aligeran el envío.
  Future<void> _pick(ImageSource source) async {
    final files = source == ImageSource.gallery
        ? await picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85)
        : [?await picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85)];
    for (final f in files) {
      pending.add(ImportImage(await f.readAsBytes(), _mediaType(f)));
    }
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final text = input.text;
    final images = List.of(pending);
    if (text.trim().isEmpty && images.isEmpty) return;
    input.clear();
    setState(pending.clear);
    await session.send(text, images);
    // Si falló, se devuelve lo escrito para reintentar.
    final failed = session.lastFailed;
    if (failed != null && mounted) {
      setState(() {
        input.text = failed.text;
        pending.addAll(failed.images);
      });
    }
  }

  Future<void> _save() async {
    final song = session.result?.song;
    if (song == null) return;
    final title = await askText(context, title: 'Guardar canción', initial: song.title);
    if (title == null) return;
    if (title.isNotEmpty) song.title = title;
    await widget.repo.save(song);
    if (mounted) Navigator.of(context).pop(song);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session, settings]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Importar canción'),
          actions: [
            FilledButton.icon(
              onPressed: session.hasSong && !session.busy ? _save : null,
              icon: const Icon(Icons.save_alt),
              label: const Text('Guardar canción'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _preview()),
            const VerticalDivider(width: 1),
            SizedBox(width: 440, child: _chat()),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final result = session.result;
    if (result == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 48, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Trae una canción', style: text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Adjunta una captura de un cancionero, una foto de la hoja o pizarra, '
                'o pega el texto del cifrado en el chat. Aquí verás la canción y la '
                'podrás ir corrigiendo conversando.',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final song = result.song;
    final key = song.key;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(song.title, style: text.headlineSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 16,
          children: [
            if (key != null)
              Text(
                '${key.label(settings.notation)} · ${song.chords.length} acordes',
                style: text.titleMedium?.copyWith(color: scheme.primary),
              ),
            if (song.lyrics != null)
              Text('· con letra (guardada aparte)', style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        if (result.keyMismatch)
          _warning(
            'La fuente dice ${result.statedKey!.label(settings.notation)}, pero los acordes '
            'apuntan a ${key!.label(settings.notation)}. Puedes cambiarla luego en la canción.',
          ),
        if (result.unknownSymbols.isNotEmpty)
          _warning('No entendí estos cifrados y no los agregué: ${result.unknownSymbols.join(', ')}'),
        for (final o in song.arrangement) _section(song, o),
      ],
    );
  }

  Widget _warning(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        border: Border.all(color: Colors.amberAccent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amberAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  Widget _section(Song song, SectionOccurrence o) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final section = song.section(o.sectionId);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(section?.label ?? '', style: text.titleLarge?.copyWith(color: scheme.primary)),
              if (o.repeats > 1) ...[const SizedBox(width: 10), RepeatBadge(o.repeats, fontSize: 18)],
            ],
          ),
          if (section?.note case final note? when note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('📝 $note', style: text.bodyLarge?.copyWith(color: scheme.tertiary)),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = o.start; i < o.start + o.passLength; i++)
                ChordCell(
                  chord: song.chords[i].chord,
                  musicKey: song.keyAt(i),
                  settings: settings,
                  beats: song.chords[i].beats,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chat() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: chatScroll,
            padding: const EdgeInsets.all(12),
            children: [
              if (session.entries.isEmpty)
                Text(
                  'Ejemplos de lo que puedes decir después:\n'
                  '• "El coro se repite dos veces"\n'
                  '• "Ese Bm es un D/F#"\n'
                  '• "Junta el verso 1 y 2" · "Ignora la letra"\n'
                  '• "En el puente: hacer adorno"',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              for (final e in session.entries) _bubble(e),
              if (session.busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text('Leyendo la canción…', style: text.bodyMedium),
                    ],
                  ),
                ),
              if (session.error != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(session.error!, style: TextStyle(color: scheme.onErrorContainer)),
                ),
            ],
          ),
        ),
        if (pending.isNotEmpty)
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (i, image) in pending.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(image.bytes, width: 68, height: 68, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => pending.removeAt(i)),
                            icon: const Icon(Icons.cancel, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // En escritorio no hay cámara: solo se eligen archivos.
              if (Platform.isAndroid || Platform.isIOS)
                IconButton(
                  tooltip: 'Tomar foto',
                  onPressed: session.busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
              IconButton(
                tooltip: Platform.isAndroid || Platform.isIOS ? 'Elegir de la galería' : 'Elegir imágenes',
                onPressed: session.busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 6,
                  enabled: !session.busy,
                  decoration: const InputDecoration(
                    hintText: 'Pega el cifrado o escribe una corrección…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Enviar',
                onPressed: session.busy ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bubble(ChatEntry e) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: e.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: e.fromUser ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.images.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final image in e.images)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(image.bytes, width: 96, height: 96, fit: BoxFit.cover),
                    ),
                ],
              ),
            if (e.text.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: e.images.isEmpty ? 0 : 6),
                child: Text(
                  e.text,
                  style: TextStyle(color: e.fromUser ? scheme.onPrimaryContainer : scheme.onSurface),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
