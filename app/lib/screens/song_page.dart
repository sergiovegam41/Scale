import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../midi/midi_service.dart';
import '../settings.dart';
import '../storage/song_repository.dart';
import 'play_page.dart';
import 'song_editor.dart';
import '../widgets/chord_cell.dart';
import '../widgets/dialogs.dart';
import '../widgets/repeat_badge.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/song_key_panel.dart';

enum SongView { sections, linear }

/// Abrir una canción (para ir a la siguiente de la lista al tocar).
typedef SongOpener = void Function(Song song, {bool edit, PlayMode? play});

/// Una canción: la secuencia de acordes como partitura y la tonalidad en la esquina.
class SongPage extends StatefulWidget {
  const SongPage({
    super.key,
    required this.song,
    required this.repo,
    required this.settings,
    required this.midi,
    required this.engine,
    this.startEditing = false,
    this.startPlaying,
    this.onOpenSong,
  });

  /// Abrir directo tocando, en este modo (al pasar a la siguiente canción).
  final PlayMode? startPlaying;
  final SongOpener? onOpenSong;

  /// Abrir directo en el editor (canción nueva).
  final bool startEditing;

  final Song song;
  final SongRepository repo;
  final AppSettings settings;
  final MidiService midi;
  final ChordEngine engine;

  @override
  State<SongPage> createState() => _SongPageState();
}

class _SongPageState extends State<SongPage> {
  SongView view = SongView.sections;

  /// Editor (arrastrar acordes, secciones como texto, probar con el piano).
  late bool editing = widget.startEditing;

  /// Al entrar al editor desde "Tocar → Editar", empezar probando desde el
  /// acorde en el que se iba.
  bool _editTesting = false;
  int? _editFrom;

  /// Con capa de transpose: ver lo que suena o las figuras originales. Se
  /// guarda con la canción.
  bool get sounding => !song.showOriginal;

  Song get song => widget.song;
  AppSettings get settings => widget.settings;

  /// Semitonos que se aplican al mostrar (0 si se ven las originales).
  int get _shown => sounding ? song.transpose : 0;

  Future<void> _transpose() async {
    final key = song.key;
    if (key == null) return;
    final semitones = await pickTranspose(
      context,
      original: key,
      current: song.transpose,
      range: settings.transposeRange,
      notation: settings.notation,
    );
    if (semitones == null) return;
    song
      ..transpose = semitones
      ..showOriginal = false;
    await _save();
  }

  Future<void> _save() async {
    await widget.repo.save(song);
    if (mounted) setState(() {});
  }

  Future<void> _rename() async {
    final title = await askText(context, title: 'Título de la canción', initial: song.title);
    if (title == null || title.isEmpty) return;
    song.title = title;
    await _save();
  }

  Future<void> _renameSection(SectionDef section) async {
    final result = await askSection(context, section);
    if (result == null) return;
    section
      ..label = result.$1
      ..kind = result.$2
      ..note = result.$3.isEmpty ? null : result.$3;
    await _save();
  }

  Future<void> _removeModulation(int region) async {
    final r = song.keyRegions[region];
    final ok = await confirm(
      context,
      title: 'Quitar modulación',
      message: '¿Toda la canción sigue en ${song.keyRegions[region - 1].key.label(settings.notation)} '
          'y no cambia a ${r.key.label(settings.notation)} en el acorde ${r.start + 1}?',
      action: 'Quitar',
    );
    if (!ok) return;
    song.removeModulation(region);
    SongAnalyzer.analyze(song, sections: false);
    await _save();
  }

  Future<void> _redetectModulations() async {
    song.keyRegionsManual = false;
    SongAnalyzer.analyze(song, sections: false);
    await _save();
  }

  Future<void> _redetectParts() async {
    final ok = await confirm(
      context,
      title: 'Volver a detectar partes',
      message: 'Se reemplazarán las secciones actuales (nombres y vueltas) por partes '
          'detectadas por pausas y repeticiones.',
      action: 'Detectar',
    );
    if (!ok) return;
    SongAnalyzer.analyze(song);
    await _save();
  }

  Future<void> _changeKey() async {
    final result = await pickKey(context, current: song.keyManual ? song.key : null, notation: settings.notation);
    if (result == null) return;
    final (key,) = result;
    if (key == null) {
      song.keyManual = false;
      SongAnalyzer.analyze(song, sections: false);
    } else {
      song
        ..key = key
        ..keyManual = true;
    }
    await _save();
  }

  /// En la vista por secciones, un cambio se aplica a todas las vueltas y
  /// apariciones de esa sección que tenían el mismo acorde en esa posición.
  Future<void> _editChord(int index, {SectionOccurrence? occurrence}) async {
    final event = song.chords[index];
    final edit = await editChord(
      context,
      event: event,
      musicKey: song.keyAt(index),
      settings: settings,
      piano: widget.engine,
    );
    if (edit == null) return;

    final targets = <int>{index};
    if (occurrence != null && view == SongView.sections) {
      final offset = (index - occurrence.start) % occurrence.passLength;
      for (final o in song.arrangement.where((o) => o.sectionId == occurrence.sectionId)) {
        for (var i = o.start + offset; i < o.end; i += o.passLength) {
          if (song.chords[i].chord == event.chord) targets.add(i);
        }
      }
    }

    switch (edit) {
      case ReplaceChord(:final chord):
        for (final i in targets) {
          final e = song.chords[i];
          if (e.chord == chord) continue;
          e
            ..alternatives = [e.chord, ...e.alternatives.where((a) => a != chord)]
            ..chord = chord
            ..edited = true;
        }
      case SetBeats(:final beats):
        for (final i in targets) {
          song.chords[i].beats = beats;
        }
      case DeleteChord():
        for (final i in targets.toList()..sort((a, b) => b.compareTo(a))) {
          song.removeChordAt(i);
        }
      case InsertNear() || SplitHere() || FollowFromHere():
        return; // solo en el editor
    }
    SongAnalyzer.analyze(song, sections: false);
    await _save();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Eliminar canción',
      message: '¿Eliminar "${song.title}"? No se puede deshacer.',
    );
    if (!ok) return;
    await widget.repo.delete(song);
    if (mounted) Navigator.of(context).pop();
  }

  void _edit({bool testing = false, int? from}) => setState(() {
        editing = true;
        _editTesting = testing;
        _editFrom = from;
      });

  @override
  void initState() {
    super.initState();
    final mode = widget.startPlaying;
    if (mode != null && song.chords.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play(mode: mode);
      });
    }
  }

  Future<void> _play({PlayMode? mode}) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PlayPage(
          song: song,
          repo: widget.repo,
          midi: widget.midi,
          engine: widget.engine,
          settings: settings,
          initialMode: mode,
          onOpenSong: widget.onOpenSong,
        ),
      ),
    );
    if (!mounted) return;
    // "Editar" desde Tocar: al editor, probando, para corregir al momento.
    if (result != null && result.startsWith('edit')) {
      final from = int.tryParse(result.split(':').last);
      _edit(testing: true, from: from == null || from < 0 ? null : from);
    } else {
      setState(() {}); // se refleja lo que se cambió al tocar (transporte, vista)
    }
  }

  @override
  Widget build(BuildContext context) {
    if (editing) {
      return SongEditor(
        song: song,
        repo: widget.repo,
        settings: settings,
        midi: widget.midi,
        engine: widget.engine,
        startTesting: _editTesting,
        startAt: _editFrom,
        onDone: () => setState(() => editing = false),
      );
    }
    final linear = view == SongView.linear;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: InkWell(
            onTap: _rename,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(song.title, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit, size: 18),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton.icon(
              onPressed: song.chords.isEmpty ? null : () => _play(),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Tocar'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.edit_note),
              label: const Text('Editar'),
            ),
            const SizedBox(width: 12),
            SegmentedButton<SongView>(
              segments: const [
                ButtonSegment(value: SongView.sections, label: Text('Secciones')),
                ButtonSegment(value: SongView.linear, label: Text('Lineal')),
              ],
              selected: {view},
              onSelectionChanged: (s) => setState(() => view = s.first),
            ),
            if (song.transpose != 0 && song.key != null) ...[
              const SizedBox(width: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text('Suena ${song.soundingKey!.name(settings.notation)}'),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Original ${song.key!.name(settings.notation)}'),
                  ),
                ],
                selected: {sounding},
                onSelectionChanged: (s) {
                  song.showOriginal = !s.first;
                  _save();
                },
              ),
            ],
            const SizedBox(width: 4),
            SettingsButton(settings: settings),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'parts' => _redetectParts(),
                'modulations' => _redetectModulations(),
                'delete' => _delete(),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'parts', child: Text('Volver a detectar partes')),
                PopupMenuItem(value: 'modulations', child: Text('Volver a detectar modulaciones')),
                PopupMenuItem(value: 'delete', child: Text('Eliminar canción')),
              ],
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: song.chords.isEmpty
                    ? Center(
                        child: FilledButton.icon(
                          onPressed: _edit,
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Sin acordes: abrir el editor'),
                        ),
                      )
                    : linear
                        ? _linear()
                        : _bySections(),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 320,
                child: SongKeyPanel(
                  song: song,
                  notation: settings.notation,
                  onChangeKey: _changeKey,
                  onRemoveModulation: _removeModulation,
                  onTranspose: _transpose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<SectionOccurrence> get _occurrences => song.arrangement.isEmpty
      ? [SectionOccurrence(sectionId: '', start: 0, end: song.chords.length)]
      : song.arrangement;

  Widget _linear() {
    final occurrences = _occurrences;
    return ListView(
      children: [
        for (final (i, o) in occurrences.indexed)
          _block(o, occurrenceIndex: i, appearance: _appearance(occurrences, i)),
      ],
    );
  }

  Widget _bySections() {
    final occurrences = _occurrences;
    return ListView(
      children: [
        _order(occurrences),
        const SizedBox(height: 8),
        for (final s in song.sections)
          if (occurrences.where((o) => o.sectionId == s.id).toList() case final list when list.isNotEmpty)
            _block(list.first, appearances: list.length, firstPassOnly: true),
      ],
    );
  }

  int _appearance(List<SectionOccurrence> all, int index) =>
      all.take(index + 1).where((o) => o.sectionId == all[index].sectionId).length;

  Widget _order(List<SectionOccurrence> occurrences) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Orden:', style: TextStyle(color: scheme.onSurfaceVariant)),
          for (final o in occurrences)
            Chip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(song.section(o.sectionId)?.label ?? '—'),
                  if (o.repeats > 1) ...[
                    const SizedBox(width: 6),
                    RepeatBadge(o.repeats, fontSize: 13),
                  ],
                ],
              ),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _header(
    SectionDef section,
    SectionOccurrence occurrence, {
    int? appearances,
    int? appearance,
    int? occurrenceIndex,
  }) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = text.titleMedium?.copyWith(color: scheme.onSurfaceVariant);
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(section.label, style: text.titleLarge?.copyWith(color: scheme.primary)),
        if (occurrence.repeats > 1) ...[
          const SizedBox(width: 10),
          RepeatBadge(occurrence.repeats, fontSize: 18),
        ],
        if (appearances != null && appearances > 1) Text('  · aparece $appearances veces', style: muted),
        if (appearance != null && appearance > 1)
          Text('  ($appearanceª vez)', style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
    final note = section.note;
    final noteLine = note == null || note.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text('📝 $note', style: text.bodyLarge?.copyWith(color: scheme.tertiary)),
          );
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _renameSection(section),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [title, const SizedBox(width: 6), Icon(Icons.edit, size: 14, color: scheme.onSurfaceVariant)],
              ),
            ),
          ),
          ?noteLine,
        ],
      );
  }

  Widget _block(
    SectionOccurrence occurrence, {
    int? appearances,
    int? appearance,
    int? occurrenceIndex,
    bool firstPassOnly = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final section = song.section(occurrence.sectionId);
    final modulations = {
      for (final (i, r) in song.keyRegions.indexed)
        if (i > 0) r.start: (i, r.key),
    };
    final end = firstPassOnly ? occurrence.start + occurrence.passLength : occurrence.end;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section != null)
            _header(
              section,
              occurrence,
              appearances: appearances,
              appearance: appearance,
              occurrenceIndex: occurrenceIndex,
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = occurrence.start; i < end; i++) ...[
                if (!firstPassOnly && occurrence.repeats > 1 && i > occurrence.start &&
                    (i - occurrence.start) % occurrence.passLength == 0)
                  _passMarker(occurrence.passOf(i)),
                if (modulations[i] case (final region, final key))
                  Tooltip(
                    message: 'Toca para quitar esta modulación',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _removeModulation(region),
                      child: Container(
                        height: 84,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.tertiary),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.trending_up, color: scheme.tertiary),
                            const SizedBox(width: 6),
                            Text(
                              key.transpose(_shown).label(settings.notation),
                              style: TextStyle(color: scheme.tertiary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ChordCell(
                  chord: song.chords[i].chord.transpose(_shown),
                  musicKey: song.keyAt(i)?.transpose(_shown),
                  settings: settings,
                  confidence: song.chords[i].confidence,
                  beats: song.chords[i].beats,
                  edited: song.chords[i].edited,
                  onTap: () => _editChord(i, occurrence: occurrence),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _passMarker(int pass) {
    final scheme = Theme.of(context).colorScheme;
    // Row (no alignment) para que el marcador mida lo que su texto.
    return SizedBox(
      height: 84,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          Text(
            '$passª vuelta',
            style: TextStyle(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
