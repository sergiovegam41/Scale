import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../settings.dart';
import '../storage/song_repository.dart';
import '../widgets/dialogs.dart';
import '../widgets/repeat_badge.dart';
import '../widgets/settings_sheet.dart';
import 'import_page.dart';

/// Biblioteca de canciones: la lista para tocar (en su orden, se reorganiza a
/// mano) y el archivo con todas, también las que no se van a tocar.
class SongListPage extends StatefulWidget {
  const SongListPage({
    super.key,
    required this.repo,
    required this.settings,
    required this.onOpen,
    required this.onCreate,
  });

  final SongRepository repo;
  final AppSettings settings;
  final ValueChanged<Song> onOpen;

  /// Canción nueva escrita a mano: se abre directo para editarla.
  final ValueChanged<Song> onCreate;

  static String date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Para ordenar y buscar sin que importen mayúsculas ni tildes.
  static String fold(String s) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    final out = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      out.write(i < 0 ? ch : to[i]);
    }
    return out.toString().trim();
  }

  static List<Song> sorted(List<Song> songs, SongSort sort, List<String> order) {
    final list = List.of(songs); // el repositorio ya las da más recientes primero
    int byTitle(Song a, Song b) => fold(a.title).compareTo(fold(b.title));
    int byRecent(Song a, Song b) => b.updatedAt.compareTo(a.updatedAt);
    switch (sort) {
      case SongSort.recent:
        list.sort(byRecent);
      case SongSort.title:
        list.sort((a, b) => byTitle(a, b) != 0 ? byTitle(a, b) : byRecent(a, b));
      case SongSort.key:
        int k(Song s) => s.key == null ? 99 : s.key!.tonic * 2 + (s.key!.isMajor ? 0 : 1);
        list.sort((a, b) => k(a) != k(b) ? k(a).compareTo(k(b)) : byTitle(a, b));
      case SongSort.manual:
        // Las que todavía no tienen lugar (nuevas) van primero.
        final pos = {for (final (i, id) in order.indexed) id: i};
        int p(Song s) => pos[s.id] ?? -1;
        list.sort((a, b) => p(a) != p(b) ? p(a).compareTo(p(b)) : byRecent(a, b));
    }
    return list;
  }

  /// Las canciones para tocar (todas menos las del archivo), en su orden.
  static List<Song> liveList(SongRepository repo, AppSettings settings) => sorted(
        [for (final s in repo.songs) if (!settings.isArchived(s.id)) s],
        settings.songSort,
        settings.songOrder,
      );

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  bool reorganizing = false;

  /// Ver el archivo (todas las canciones) en vez de la lista para tocar.
  bool archive = false;
  String query = '';
  final TextEditingController _search = TextEditingController();

  SongRepository get repo => widget.repo;
  AppSettings get settings => widget.settings;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (!settings.hasApiKey) {
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Falta la API key'),
          content: const Text(
            'Para importar con IA escribe tu API key de Anthropic en ⚙ Configuración. '
            'Se guarda solo en esta tablet.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abrir ⚙')),
          ],
        ),
      );
      if (open == true && mounted) await showSettings(context, settings);
      if (!settings.hasApiKey || !mounted) return;
    }
    final song = await Navigator.of(context).push<Song>(
      MaterialPageRoute(builder: (_) => ImportPage(repo: repo, settings: settings)),
    );
    if (song != null) widget.onOpen(song);
  }

  Future<void> _create() async {
    final title = await askText(context, title: 'Canción nueva', initial: '', confirm: 'Crear');
    if (title == null || title.isEmpty) return;
    final song = Song.create(title: title, source: SongSource.manual);
    await repo.save(song);
    widget.onCreate(song);
  }

  void _toggleReorganize() {
    setState(() {
      reorganizing = !reorganizing;
      if (reorganizing) {
        _search.clear();
        query = '';
      }
    });
  }

  /// Arrastrar en "Reorganizar" pasa a "Mi orden" partiendo de lo que se ve.
  void _reorder(List<Song> shown, int from, int to) {
    final ids = [for (final s in shown) s.id];
    ids.insert(to, ids.removeAt(from));
    settings
      ..songOrder = ids
      ..songSort = SongSort.manual;
  }

  /// Pasar una canción al archivo o de vuelta a la lista para tocar.
  void _setArchived(Song song, bool archived) {
    settings.setArchived(song.id, archived);
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(archived ? '"${song.title}" pasó al archivo' : '"${song.title}" está en la lista para tocar'),
      action: SnackBarAction(label: 'Deshacer', onPressed: () => settings.setArchived(song.id, !archived)),
    ));
  }

  Future<void> _delete(Song song) async {
    final ok = await confirm(
      context,
      title: 'Eliminar canción',
      message: '¿Eliminar "${song.title}" para siempre? Si solo no la vas a tocar, pásala al archivo.',
    );
    if (ok) await repo.delete(song);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([repo, settings]),
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final live = SongListPage.liveList(repo, settings);
        final all = archive
            ? SongListPage.sorted(
                repo.songs,
                settings.archiveSort == SongSort.manual ? SongSort.title : settings.archiveSort,
                const [],
              )
            : live;
        final q = SongListPage.fold(query);
        final songs = q.isEmpty ? all : all.where((s) => SongListPage.fold(s.title).contains(q)).toList();
        final sort = archive ? settings.archiveSort : settings.songSort;
        return Scaffold(
          appBar: AppBar(
            title: reorganizing
                ? Text('Para tocar (${live.length})')
                : SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.queue_music),
                        label: Text('Para tocar (${live.length})'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: Text('Archivo (${repo.songs.length})'),
                      ),
                    ],
                    selected: {archive},
                    onSelectionChanged: (s) => setState(() => archive = s.first),
                  ),
            actions: reorganizing
                ? [
                    Text(
                      'Arrastra para cambiar el orden',
                      style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: _toggleReorganize,
                      icon: const Icon(Icons.check),
                      label: const Text('Listo'),
                    ),
                    const SizedBox(width: 8),
                  ]
                : [
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => query = v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Buscar',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(() {
                                    _search.clear();
                                    query = '';
                                  }),
                                ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<SongSort>(
                      tooltip: 'Ordenar',
                      initialValue: sort,
                      onSelected: (s) => archive ? settings.archiveSort = s : settings.songSort = s,
                      itemBuilder: (_) => [
                        for (final s in SongSort.values)
                          if (!archive || s != SongSort.manual)
                            CheckedPopupMenuItem(value: s, checked: s == sort, child: Text(s.label)),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.sort),
                            const SizedBox(width: 6),
                            Text(sort.label),
                          ],
                        ),
                      ),
                    ),
                    if (!archive)
                      TextButton.icon(
                        onPressed: live.length < 2 ? null : _toggleReorganize,
                        icon: const Icon(Icons.swap_vert),
                        label: const Text('Reorganizar'),
                      ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.add),
                      label: const Text('Nueva'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Importar'),
                    ),
                    const SizedBox(width: 4),
                    SettingsButton(settings: settings),
                    const SizedBox(width: 8),
                  ],
          ),
          body: !repo.loaded
              ? const Center(child: CircularProgressIndicator())
              : all.isEmpty
                  ? Center(
                      child: Text(
                        archive || repo.songs.isEmpty
                            ? 'Aún no hay canciones.\nGraba tu primera desde "En vivo", escríbela con "Nueva" '
                                'o tráela con "Importar".'
                            : 'No hay canciones para tocar.\nAgrégalas desde el Archivo.',
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : reorganizing
                      ? _reorderList(live)
                      : songs.isEmpty
                          ? Center(child: Text('Ninguna canción coincide con "$query"', style: text.titleMedium))
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 380,
                                mainAxisExtent: 150,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: songs.length,
                              itemBuilder: (context, i) {
                                final song = songs[i];
                                final inList = !settings.isArchived(song.id);
                                return _SongCard(
                                  song: song,
                                  notation: settings.notation,
                                  inList: inList,
                                  showListBadge: archive,
                                  onTap: () => widget.onOpen(song),
                                  onToggleList: () => _setArchived(song, inList),
                                  onDelete: () => _delete(song),
                                );
                              },
                            ),
        );
      },
    );
  }

  Widget _reorderList(List<Song> songs) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      buildDefaultDragHandles: false,
      itemCount: songs.length,
      onReorderItem: (from, to) => _reorder(songs, from, to),
      itemBuilder: (context, i) {
        final s = songs[i];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(s.id),
          index: i,
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: SizedBox(
                width: 32,
                child: Text('${i + 1}', style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              title: Text(s.title, style: text.titleLarge),
              subtitle: _KeyLine(song: s, notation: settings.notation),
              trailing: ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle, size: 32),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tonalidad original y, si quedó guardado un transporte, en qué suena.
class _KeyLine extends StatelessWidget {
  const _KeyLine({required this.song, required this.notation, this.style});

  final Song song;
  final Notation notation;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final key = song.key;
    if (key == null) return Text('Tonalidad sin determinar', style: style);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: key.label(notation)),
          if (song.transpose != 0)
            TextSpan(
              text: '  →  ${song.soundingKey!.label(notation)} (${TransposeAdvice.label(song.transpose)})',
              style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.w600),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.song,
    required this.notation,
    required this.inList,
    required this.showListBadge,
    required this.onTap,
    required this.onToggleList,
    required this.onDelete,
  });

  final Song song;
  final Notation notation;

  /// Está en la lista para tocar.
  final bool inList;

  /// En el archivo: marcar las que están en la lista.
  final bool showListBadge;
  final VoidCallback onTap;
  final VoidCallback onToggleList;
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
                    _KeyLine(song: song, notation: notation, style: text.titleMedium?.copyWith(color: scheme.primary)),
                    const Spacer(),
                    Text.rich(
                      TextSpan(children: order),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium,
                    ),
                    Row(
                      children: [
                        if (showListBadge && inList) ...[
                          Icon(Icons.queue_music, size: 16, color: scheme.tertiary),
                          const SizedBox(width: 4),
                          Text('Para tocar · ', style: text.bodySmall?.copyWith(color: scheme.tertiary)),
                        ],
                        Expanded(
                          child: Text(
                            song.chords.isEmpty
                                ? 'Sin acordes todavía · ${SongListPage.date(song.updatedAt)}'
                                : '${song.chords.length} acordes · ${SongListPage.date(song.updatedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'delete' ? onDelete() : onToggleList(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'list',
                    child: ListTile(
                      leading: Icon(inList ? Icons.inventory_2_outlined : Icons.queue_music),
                      title: Text(inList ? 'Pasar al archivo' : 'Agregar a "Para tocar"'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: scheme.error),
                      title: Text('Eliminar', style: TextStyle(color: scheme.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
