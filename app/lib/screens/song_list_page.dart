import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../settings.dart';
import '../storage/song_repository.dart';
import '../widgets/dialogs.dart';
import '../widgets/repeat_badge.dart';

/// Biblioteca de canciones anotadas.
class SongListPage extends StatelessWidget {
  const SongListPage({
    super.key,
    required this.repo,
    required this.settings,
    required this.onOpen,
  });

  final SongRepository repo;
  final AppSettings settings;
  final ValueChanged<Song> onOpen;

  static String date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([repo, settings]),
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final songs = repo.songs;
        return Scaffold(
          appBar: AppBar(title: Text('Canciones (${songs.length})')),
          body: !repo.loaded
              ? const Center(child: CircularProgressIndicator())
              : songs.isEmpty
                  ? Center(
                      child: Text(
                        'Aún no hay canciones.\nGraba tu primera desde "En vivo".',
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 380,
                        mainAxisExtent: 150,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: songs.length,
                      itemBuilder: (context, i) => _SongCard(
                        song: songs[i],
                        notation: settings.notation,
                        onTap: () => onOpen(songs[i]),
                        onDelete: () async {
                          final ok = await confirm(
                            context,
                            title: 'Eliminar canción',
                            message: '¿Eliminar "${songs[i].title}"? No se puede deshacer.',
                          );
                          if (ok) await repo.delete(songs[i]);
                        },
                      ),
                    ),
        );
      },
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.song,
    required this.notation,
    required this.onTap,
    required this.onDelete,
  });

  final Song song;
  final Notation notation;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final order = <InlineSpan>[
      for (final (i, o) in song.arrangement.indexed) ...[
        if (i > 0) const TextSpan(text: ' · '),
        TextSpan(text: song.section(o.sectionId)?.label ?? '?'),
        if (o.repeats > 1)
          TextSpan(
            text: ' ×${o.repeats}',
            style: const TextStyle(color: repeatColor, fontWeight: FontWeight.w700),
          ),
      ],
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title, style: text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      song.key?.label(notation) ?? 'Tonalidad sin determinar',
                      style: text.titleMedium?.copyWith(color: scheme.primary),
                    ),
                    const Spacer(),
                    Text.rich(
                      TextSpan(children: order),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                    Text(
                      '${song.chords.length} acordes · ${SongListPage.date(song.updatedAt)}',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Eliminar',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
