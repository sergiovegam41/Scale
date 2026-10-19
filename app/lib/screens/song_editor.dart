import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../midi/midi_service.dart';
import '../play/live_follow.dart';
import '../settings.dart';
import '../storage/song_repository.dart';
import '../widgets/chord_cell.dart';
import '../widgets/dialogs.dart';
import '../widgets/record_section_dialog.dart';
import '../widgets/repeat_badge.dart';
import '../widgets/section_dialog.dart';
import '../widgets/settings_sheet.dart';

/// Lo que se arrastra en el editor: un acorde de la partitura o uno nuevo
/// (de la paleta o del piano).
sealed class _DragItem {}

class _MoveItem extends _DragItem {
  _MoveItem(this.occurrence, this.offset);
  final int occurrence;
  final int offset;
}

class _NewItem extends _DragItem {
  _NewItem(this.chord);
  final Chord chord;
}

/// Editor de una canción: cada sección se ve como una vuelta (×N), los
/// acordes se arrastran para moverlos (entre secciones o de lado a lado) y
/// "Probar" sigue lo que tocas en el piano ahí mismo, para corregir sin
/// salir. Todo se guarda al momento y se puede deshacer.
class SongEditor extends StatefulWidget {
  const SongEditor({
    super.key,
    required this.song,
    required this.repo,
    required this.settings,
    required this.midi,
    required this.engine,
    required this.onDone,
    this.startTesting = false,
    this.startAt,
  });

  final Song song;
  final SongRepository repo;
  final AppSettings settings;
  final MidiService midi;
  final ChordEngine engine;
  final VoidCallback onDone;
  final bool startTesting;

  /// Al probar, seguir desde este acorde (el que se estaba tocando).
  final int? startAt;

  @override
  State<SongEditor> createState() => _SongEditorState();
}

class _SongEditorState extends State<SongEditor> {
  late final SongHistory history = SongHistory(song);
  LiveFollow? live;
  late final int _previousLayer;

  /// Se está arrastrando un acorde de la partitura (aparece la papelera).
  bool movingChord = false;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _chartKey = GlobalKey();
  final Map<int, GlobalKey> _cellKeys = {};
  Timer? _autoScroll;
  double _scrollSpeed = 0;
  int? _scrolledTo;

  Song get song => widget.song;
  AppSettings get settings => widget.settings;
  ChordEngine get engine => widget.engine;
  bool get testing => live != null;
  ChordFormatter get fmt => settings.formatter;

  @override
  void initState() {
    super.initState();
    // Se editan las figuras: el piano se lee con la capa de la canción.
    _previousLayer = engine.layer;
    engine.layer = song.transpose;
    song.ensureArrangement();
    if (widget.startTesting && song.chords.isNotEmpty) {
      _setTesting(true);
      final at = widget.startAt;
      if (at != null && at < song.chords.length) live?.placeAt(at);
    }
    if (song.chords.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addSection();
      });
    }
  }

  @override
  void dispose() {
    live?.dispose();
    _autoScroll?.cancel();
    _scroll.dispose();
    engine.layer = _previousLayer;
    super.dispose();
  }

  // ── Cambios ──────────────────────────────────────────────────────────

  /// Aplica un cambio: se puede deshacer, se reanaliza la tonalidad, se
  /// guarda y la prueba sigue desde el mismo acorde.
  Future<void> _mutate(VoidCallback change, {bool reanalyze = true}) async {
    final anchor = live?.currentEvent;
    history.record();
    setState(change);
    if (reanalyze) SongAnalyzer.analyze(song, sections: false);
    live?.rebuild(at: anchor);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await widget.repo.save(song);
    } catch (e) {
      _toast('No se pudo guardar: $e');
    }
  }

  void _undo() => _travel(history.undo);
  void _redo() => _travel(history.redo);

  void _travel(bool Function() step) {
    final position = live?.follower.position ?? -1;
    if (!step()) return;
    setState(() {});
    if (live != null) {
      live!.rebuild();
      if (position >= 0 && song.chords.isNotEmpty) live!.placeAt(position.clamp(0, song.chords.length - 1));
    }
    _persist();
  }

  /// Mientras un diálogo escucha el piano, la prueba no avanza.
  Future<T> _paused<T>(Future<T> Function() dialog) async {
    live?.paused = true;
    try {
      return await dialog();
    } finally {
      live?.paused = false;
    }
  }

  void _toast(String message, {bool undo = false}) {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
      action: undo ? SnackBarAction(label: 'Deshacer', onPressed: _undo) : null,
    ));
  }

  /// Posición (aparición, lugar en la vuelta) de un acorde lineal.
  (int, int)? _locate(int index) {
    for (final (i, o) in song.arrangement.indexed) {
      if (index >= o.start && index < o.end) return (i, (index - o.start) % o.passLength);
    }
    return null;
  }

  /// Sugerencias para acordes nuevos: los de la tonalidad y los de la canción.
  List<Chord> get _suggestions {
    final counts = <Chord, int>{};
    for (final c in song.chords) {
      counts[c.chord] = (counts[c.chord] ?? 0) + 1;
    }
    final used = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return {...?song.key?.diatonicChords, ...used.take(12)}.toList();
  }

  void _replaceAt(int occurrence, int offset, Chord chord) {
    for (final i in song.passPositions(occurrence, offset)) {
      final e = song.chords[i];
      if (e.chord == chord) continue;
      e
        ..alternatives = [e.chord, ...e.alternatives.where((a) => a != chord)]
        ..chord = chord
        ..edited = true;
    }
  }

  // ── Acordes ──────────────────────────────────────────────────────────

  Future<void> _tapChord(int occurrence, int offset) async {
    final o = song.arrangement[occurrence];
    final index = o.start + offset;
    final passes = o.length ~/ o.passLength;
    final edit = await _paused(() => editChord(
      context,
      event: song.chords[index],
      musicKey: song.keyAt(index),
      settings: settings,
      piano: engine,
      structure: true,
      canFollow: testing,
      where: passes > 1 ? 'Se cambia en las $passes vueltas' : null,
    ));
    if (edit == null || !mounted) return;
    switch (edit) {
      case ReplaceChord(:final chord):
        await _mutate(() => _replaceAt(occurrence, offset, chord));
      case SetBeats(:final beats):
        await _mutate(() {
          for (final i in song.passPositions(occurrence, offset)) {
            song.chords[i].beats = beats;
          }
        }, reanalyze: false);
      case DeleteChord():
        await _mutate(() => song.removeChord(occurrence, offset));
        _toast('Acorde eliminado', undo: true);
      case InsertNear(:final after):
        await _insert(occurrence, after ? offset + 1 : offset);
      case SplitHere():
        await _split(occurrence, offset);
      case FollowFromHere():
        live?.jumpTo(index);
    }
  }

  Future<void> _insert(int occurrence, int offset) async {
    final chord = await _paused(() => pickChord(
          context,
          title: 'Agregar acorde',
          settings: settings,
          musicKey: song.key,
          piano: engine,
          suggestions: _suggestions,
        ));
    if (chord == null || !mounted) return;
    await _mutate(() => song.insertChord(occurrence, offset, ChordEvent(chord: chord)));
  }

  Future<void> _split(int occurrence, int offset) async {
    if (offset == 0) return _editSection(occurrence);
    final choice = await chooseSection(
      context,
      title: 'Sección que empieza en este acorde',
      existing: const [],
      suggestedLabel: song.nextPartLabel(),
    );
    if (choice is! NewSection || !mounted) return;
    final repeats = song.arrangement[occurrence].repeats;
    await _mutate(() => song.splitPasses(
          occurrence,
          offset,
          song.newSection(label: choice.label, kind: choice.kind),
        ));
    if (repeats > 1) _toast('Se partió cada una de las $repeats vueltas', undo: true);
  }

  void _drop(_DragItem item, int occurrence, int offset) {
    switch (item) {
      case _MoveItem(occurrence: final from, offset: final at):
        _mutate(() => song.moveChord(from, at, occurrence, offset));
      case _NewItem(:final chord):
        _mutate(() => song.insertChord(occurrence, offset, ChordEvent(chord: chord)));
    }
  }

  // ── Secciones ────────────────────────────────────────────────────────

  Future<void> _editSection(int occurrence) async {
    final o = song.arrangement[occurrence];
    final section = song.section(o.sectionId);
    if (section == null) return;
    final pass = song.chords.sublist(o.start, o.start + o.passLength);
    final result = await _paused(() => editSectionDialog(
      context,
      title: 'Editar sección',
      settings: settings,
      label: section.label,
      kind: section.kind,
      note: section.note,
      chords: ChordLine.format(pass, formatter: fmt, key: song.keyAt(o.start), repeats: o.length ~/ o.passLength),
      musicKey: song.keyAt(o.start),
      piano: engine,
    ));
    if (result == null || !mounted) return;
    await _mutate(() {
      section
        ..label = result.label
        ..kind = result.kind
        ..note = result.note.isEmpty ? null : result.note;
      song.replacePass(occurrence, result.line.chords, repeats: result.line.repeats);
    });
  }

  Future<void> _addSection({int? at}) async {
    final result = await _paused(() => editSectionDialog(
      context,
      title: song.chords.isEmpty ? 'Primera sección' : 'Sección nueva',
      settings: settings,
      label: song.chords.isEmpty ? 'Intro' : song.nextPartLabel(),
      kind: song.chords.isEmpty ? SectionKind.intro : SectionKind.other,
      musicKey: song.key,
      piano: engine,
      action: 'Agregar',
    ));
    if (result == null || !mounted) return;
    await _mutate(() {
      final section = song.newSection(label: result.label, kind: result.kind)
        ..note = result.note.isEmpty ? null : result.note;
      song.addSection(section, result.line.chords, repeats: result.line.repeats, at: at);
    });
  }

  /// Regrabar la sección con el piano: lo tocado reemplaza su vuelta (los
  /// acordes que siguen igual conservan su lugar en la toma).
  Future<void> _rerecord(int occurrence) async {
    final o = song.arrangement[occurrence];
    final section = song.section(o.sectionId);
    final pass = song.chords.sublist(o.start, o.start + o.passLength);
    final passes = o.length ~/ o.passLength;
    final result = await _paused(() => recordSectionDialog(
          context,
          title: 'Regrabar "${section?.label ?? ''}" con el piano',
          piano: engine,
          midi: widget.midi,
          settings: settings,
          musicKey: song.keyAt(o.start),
          replacing: ChordLine.format(pass, formatter: fmt, key: song.keyAt(o.start), repeats: passes),
          action: 'Reemplazar',
        ));
    if (result == null || !mounted) return;
    await _mutate(() => song.replacePass(occurrence, result.pass, repeats: result.repeats));
    _toast('Sección regrabada', undo: true);
  }

  /// Grabar una sección nueva tocándola.
  Future<void> _recordNew({int? at}) async {
    final result = await _paused(() => recordSectionDialog(
          context,
          title: 'Grabar sección nueva con el piano',
          piano: engine,
          midi: widget.midi,
          settings: settings,
          musicKey: song.key,
          action: 'Agregar',
          newLabel: song.chords.isEmpty ? 'Intro' : song.nextPartLabel(),
        ));
    if (result == null || !mounted) return;
    await _mutate(() => song.addSection(
          song.newSection(label: result.label ?? song.nextPartLabel(), kind: result.kind),
          result.pass,
          repeats: result.repeats,
          at: at,
        ));
  }

  Future<void> _sectionAction(int occurrence, String action) async {
    final o = song.arrangement[occurrence];
    switch (action) {
      case 'edit':
        await _editSection(occurrence);
      case 'duplicate':
        await _mutate(() => song.duplicateOccurrence(occurrence));
      case 'up':
        await _mutate(() => song.moveOccurrence(occurrence, occurrence - 1));
      case 'down':
        await _mutate(() => song.moveOccurrence(occurrence, occurrence + 1));
      case 'merge':
        await _mutate(() => song.mergeWithPrevious(occurrence));
      case 'ungroup':
        await _mutate(() => song.ungroup(occurrence), reanalyze: false);
      case 'addAfter':
        await _addSection(at: occurrence + 1);
      case 'recordAfter':
        await _recordNew(at: occurrence + 1);
      case 'delete':
        final label = song.section(o.sectionId)?.label ?? 'la sección';
        await _mutate(() => song.removeOccurrence(occurrence));
        _toast('Se eliminó $label', undo: true);
    }
  }

  // ── Prueba ───────────────────────────────────────────────────────────

  void _setTesting(bool on) {
    if (on == testing) return;
    if (on) {
      live = LiveFollow(song: song, engine: engine)..addListener(_onLive);
    } else {
      live?.dispose();
      live = null;
      _scrolledTo = null;
    }
    if (mounted) setState(() {});
  }

  void _onLive() {
    if (!mounted) return;
    setState(() {});
    final p = live?.follower.position;
    if (p == null || p < 0) return;
    final at = _locate(p);
    if (at == null) return;
    final cell = song.arrangement[at.$1].start + at.$2;
    if (cell == _scrolledTo) return;
    _scrolledTo = cell;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _cellKeys[cell]?.currentContext;
      if (context != null && mounted) {
        Scrollable.ensureVisible(context, alignment: 0.3, duration: const Duration(milliseconds: 250));
      }
    });
  }

  /// Corrección rápida al probar: lo que tocaste va donde se esperaba otro.
  Future<void> _fixReplace(int expected, Chord played) async {
    final at = _locate(expected);
    if (at == null) return;
    await _mutate(() => _replaceAt(at.$1, at.$2, played));
    live?.placeAt(expected);
  }

  /// Corrección rápida al probar: faltaba lo que tocaste antes del esperado.
  Future<void> _fixInsert(int expected, Chord played) async {
    final at = _locate(expected);
    if (at == null) return;
    final next = song.chords[expected];
    await _mutate(() => song.insertChord(at.$1, at.$2, ChordEvent(chord: played)));
    final now = song.chords.indexWhere((e) => identical(e, next));
    if (now > 0) live?.placeAt(now - 1);
  }

  // ── Arrastre ─────────────────────────────────────────────────────────

  void _dragStarted(bool moving) => setState(() => movingChord = moving);

  /// Cerca del borde de la partitura se desplaza sola mientras se arrastra.
  void _dragAt(Offset global) {
    final box = _chartKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    const edge = 90.0;
    const max = 22.0;
    _scrollSpeed = global.dy < top + edge
        ? -max * ((top + edge - global.dy) / edge).clamp(0, 1)
        : global.dy > bottom - edge
            ? max * ((global.dy - bottom + edge) / edge).clamp(0, 1)
            : 0;
    if (_scrollSpeed != 0 && _autoScroll == null) {
      _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) {
        if (!_scroll.hasClients || _scrollSpeed == 0) return;
        final p = _scroll.position;
        _scroll.jumpTo((p.pixels + _scrollSpeed).clamp(p.minScrollExtent, p.maxScrollExtent));
      });
    }
  }

  void _dragEnded() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _scrollSpeed = 0;
    if (mounted) setState(() => movingChord = false);
  }

  /// Se arrastra de lado sin esperar (de arriba abajo se desplaza la
  /// partitura) o en cualquier dirección manteniendo presionado.
  Widget _draggable({required _DragItem data, required Widget feedback, required Widget child, Widget? ghost}) {
    final lifted = Transform.translate(
      offset: const Offset(-52, -42),
      child: Material(color: Colors.transparent, elevation: 10, borderRadius: BorderRadius.circular(12), child: feedback),
    );
    final moving = data is _MoveItem;
    Widget wrap(Widget inner, {required bool longPress}) {
      if (longPress) {
        return LongPressDraggable<_DragItem>(
          data: data,
          delay: const Duration(milliseconds: 220),
          hapticFeedbackOnStart: true,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: lifted,
          childWhenDragging: ghost ?? inner,
          onDragStarted: () => _dragStarted(moving),
          onDragUpdate: (d) => _dragAt(d.globalPosition),
          onDragEnd: (_) => _dragEnded(),
          child: inner,
        );
      }
      return Draggable<_DragItem>(
        data: data,
        affinity: Axis.horizontal,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: lifted,
        childWhenDragging: ghost ?? inner,
        onDragStarted: () => _dragStarted(moving),
        onDragUpdate: (d) => _dragAt(d.globalPosition),
        onDragEnd: (_) => _dragEnded(),
        child: inner,
      );
    }

    return wrap(wrap(child, longPress: false), longPress: true);
  }

  // ── Pantalla ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onDone();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
            const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  tooltip: 'Terminar de editar',
                  onPressed: widget.onDone,
                  icon: const Icon(Icons.arrow_back),
                ),
                title: InkWell(
                  onTap: _rename,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note, color: scheme.primary),
                        const SizedBox(width: 8),
                        Flexible(child: Text(song.title, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Deshacer (Ctrl+Z)',
                    onPressed: history.canUndo ? _undo : null,
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: 'Rehacer (Ctrl+Y)',
                    onPressed: history.canRedo ? _redo : null,
                    icon: const Icon(Icons.redo),
                  ),
                  const SizedBox(width: 8),
                  if (testing)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.greenAccent.shade700),
                      onPressed: () => _setTesting(false),
                      icon: const Icon(Icons.stop),
                      label: const Text('Probando'),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: song.chords.isEmpty ? null : () => _setTesting(true),
                      icon: const Icon(Icons.piano),
                      label: const Text('Probar'),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _recordNew(),
                    icon: const Icon(Icons.fiber_manual_record, color: Color(0xFFE53935)),
                    label: const Text('Grabar sección'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _addSection(),
                    icon: const Icon(Icons.add),
                    label: const Text('Escribir sección'),
                  ),
                  const SizedBox(width: 4),
                  SettingsButton(settings: settings),
                  FilledButton.icon(
                    onPressed: widget.onDone,
                    icon: const Icon(Icons.check),
                    label: const Text('Listo'),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    if (testing) SizedBox(height: 150, child: _testStrip()),
                    if (testing) const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _chart()),
                          const SizedBox(width: 16),
                          SizedBox(width: 290, child: _palette()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rename() async {
    final title = await askText(context, title: 'Título de la canción', initial: song.title);
    if (title == null || title.isEmpty) return;
    await _mutate(() => song.title = title, reanalyze: false);
  }

  String _chordText(int index) {
    final chord = song.chords[index].chord;
    final key = song.keyAt(index);
    final name = fmt.format(chord, spell: key?.spell);
    return switch (settings.display) {
      ChordDisplay.chords => name,
      ChordDisplay.degrees => key == null ? name : fmt.nashville(chord, key),
      ChordDisplay.both => key == null ? name : '$name · ${fmt.nashville(chord, key)}',
    };
  }

  String _whereLabel(int index) {
    final o = song.occurrenceAt(index);
    if (o == null) return '';
    final label = song.section(o.sectionId)?.label ?? '';
    final passes = o.length ~/ o.passLength;
    return passes > 1 ? '$label · vuelta ${o.passOf(index)} de $passes' : label;
  }

  Widget _testStrip() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final f = live!.follower;
    final current = f.position < 0 ? null : f.position;
    final next = f.next;
    final played = f.lastPlayed;

    Widget card(String title, int? index, {required bool main}) {
      final note = index == null ? null : song.section(song.occurrenceAt(index)?.sectionId ?? '')?.note;
      return Card(
        margin: EdgeInsets.zero,
        color: main ? scheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          index == null ? '—' : _chordText(index),
                          style: TextStyle(
                            fontSize: main ? 60 : 44,
                            fontWeight: FontWeight.w700,
                            color: main ? scheme.onPrimaryContainer : repeatColor,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      index == null ? '' : _whereLabel(index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: main ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (main && note != null && note.trim().isNotEmpty)
                Flexible(
                  child: Text(
                    '📝 ${note.trim()}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final (label, color) = switch (f.status) {
      FollowStatus.waiting => ('Toca el primer acorde', scheme.onSurfaceVariant),
      FollowStatus.onTrack => ('En curso', Colors.greenAccent),
      FollowStatus.jumped => ('Saltaste a ${current == null ? '' : _whereLabel(current)}', scheme.tertiary),
      FollowStatus.offScript => ('No es lo que sigue', Colors.amberAccent),
      FollowStatus.finished => ('¡Fin de la canción!', Colors.greenAccent),
    };
    final offScript = f.status == FollowStatus.offScript && played != null && next != null;
    final key = next == null ? song.key : song.keyAt(next);
    String name(Chord c) => fmt.format(c, spell: key?.spell);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: card('Ahora', current, main: true)),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: card('Sigue', next, main: false)),
        const SizedBox(width: 8),
        SizedBox(
          width: 340,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.midi.connected == null ? Icons.usb_off : Icons.circle,
                        size: 12,
                        color: widget.midi.connected == null ? scheme.error : color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.midi.connected == null ? 'Piano desconectado' : label,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(color: color),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Desde el inicio',
                        visualDensity: VisualDensity.compact,
                        onPressed: live!.restart,
                        icon: const Icon(Icons.replay),
                      ),
                    ],
                  ),
                  if (played != null)
                    Text(
                      offScript
                          ? 'Tocaste ${name(played)}; se esperaba ${name(song.chords[next].chord)}'
                          : 'Tocaste ${name(played)}',
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  const Spacer(),
                  if (offScript)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => _fixReplace(next, played),
                          child: Text('Cambiar por ${name(played)}'),
                        ),
                        OutlinedButton(
                          onPressed: () => _fixInsert(next, played),
                          child: Text('Agregar ${name(played)} antes'),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Toca un acorde de la partitura para corregirlo o seguir desde ahí.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chart() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (song.chords.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('La canción todavía no tiene acordes', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              "Escribe cada sección como texto (G D/F# Em7 C x2) o tócala en el piano.",
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => _addSection(),
                  icon: const Icon(Icons.edit),
                  label: const Text('Escribir la primera sección'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _recordNew(),
                  icon: const Icon(Icons.fiber_manual_record, color: Color(0xFFE53935)),
                  label: const Text('Tocarla en el piano'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final f = live?.follower;
    final current = f == null || f.position < 0 ? null : _locate(f.position);
    final next = f?.next == null ? null : _locate(f!.next!);
    return ListView(
      key: _chartKey,
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        if (song.transpose != 0 && song.key != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Se editan las figuras originales (${song.key!.name(settings.notation)}); con TRANSPOSE '
              '${TransposeAdvice.label(song.transpose)} suena en ${song.soundingKey!.name(settings.notation)}.',
              style: text.bodyMedium?.copyWith(color: scheme.tertiary),
            ),
          ),
        for (var i = 0; i < song.arrangement.length; i++)
          _section(i, current: current?.$1 == i ? current!.$2 : null, next: next?.$1 == i ? next!.$2 : null),
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => _addSection(),
                icon: const Icon(Icons.add),
                label: const Text('Escribir sección al final'),
              ),
              OutlinedButton.icon(
                onPressed: () => _recordNew(),
                icon: const Icon(Icons.fiber_manual_record, color: Color(0xFFE53935)),
                label: const Text('Grabar sección al final con el piano'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(int i, {int? current, int? next}) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final o = song.arrangement[i];
    final section = song.section(o.sectionId);
    final pass = o.passLength;
    final passes = o.length ~/ pass;
    final playingHere = testing && current != null;
    final position = live?.follower.position ?? -1;
    final note = section?.note;
    final modulations = {
      for (final (r, region) in song.keyRegions.indexed)
        if (r > 0 && region.start >= o.start && region.start < o.start + pass) region.start - o.start: region.key,
    };

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: playingHere ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _editSection(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(section?.label ?? '—', style: text.titleLarge?.copyWith(color: scheme.primary)),
                      const SizedBox(width: 6),
                      Icon(Icons.edit, size: 16, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _repeatStepper(i, passes),
              if (playingHere && passes > 1) ...[
                const SizedBox(width: 12),
                Text(
                  'vuelta ${o.passOf(position)} de $passes',
                  style: text.titleSmall?.copyWith(color: scheme.primary),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: () => _rerecord(i),
                icon: const Icon(Icons.fiber_manual_record, color: Color(0xFFE53935), size: 18),
                label: const Text('Regrabar'),
              ),
              IconButton(
                tooltip: 'Subir',
                onPressed: i > 0 ? () => _sectionAction(i, 'up') : null,
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Bajar',
                onPressed: i + 1 < song.arrangement.length ? () => _sectionAction(i, 'down') : null,
                icon: const Icon(Icons.arrow_downward),
              ),
              PopupMenuButton<String>(
                onSelected: (a) => _sectionAction(i, a),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(leading: Icon(Icons.edit), title: Text('Editar nombre, acordes y nota')),
                  ),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: ListTile(leading: Icon(Icons.copy), title: Text('Duplicar debajo')),
                  ),
                  const PopupMenuItem(
                    value: 'addAfter',
                    child: ListTile(leading: Icon(Icons.add), title: Text('Sección nueva debajo')),
                  ),
                  const PopupMenuItem(
                    value: 'recordAfter',
                    child: ListTile(leading: Icon(Icons.piano), title: Text('Grabar sección nueva debajo')),
                  ),
                  if (i > 0)
                    const PopupMenuItem(
                      value: 'merge',
                      child: ListTile(leading: Icon(Icons.merge), title: Text('Unir con la anterior')),
                    ),
                  if (passes > 1)
                    const PopupMenuItem(
                      value: 'ungroup',
                      child: ListTile(leading: Icon(Icons.unfold_more), title: Text('Ver las vueltas por separado')),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: scheme.error),
                      title: Text('Eliminar sección', style: TextStyle(color: scheme.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (note != null && note.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text('📝 ${note.trim()}', style: text.bodyLarge?.copyWith(color: scheme.tertiary)),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var k = 0; k < pass; k++) ...[
                if (modulations[k] case final key?)
                  Container(
                    height: 84,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.tertiary),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.trending_up, color: scheme.tertiary),
                        const SizedBox(width: 4),
                        Text(key.name(settings.notation), style: TextStyle(color: scheme.tertiary)),
                      ],
                    ),
                  ),
                _DropSlot(
                  onDrop: (item, after) => _drop(item, i, after ? k + 1 : k),
                  child: _cell(i, k, current: current == k, next: next == k),
                ),
              ],
              _DropSlot(
                onDrop: (item, _) => _drop(item, i, pass),
                end: true,
                child: Tooltip(
                  message: 'Agregar acorde al final',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _insert(i, pass),
                    child: Container(
                      width: 64,
                      height: 84,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Icon(Icons.add, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _repeatStepper(int i, int passes) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: passes > 1 ? repeatColor : scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Una vuelta menos',
            visualDensity: VisualDensity.compact,
            onPressed: passes > 1 ? () => _mutate(() => song.setRepeats(i, passes - 1)) : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
          Text(
            '×$passes',
            style: text.titleMedium?.copyWith(
              color: passes > 1 ? repeatColor : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Una vuelta más',
            visualDensity: VisualDensity.compact,
            onPressed: passes < 16 ? () => _mutate(() => song.setRepeats(i, passes + 1)) : null,
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _cell(int i, int k, {required bool current, required bool next}) {
    final o = song.arrangement[i];
    final index = o.start + k;
    final e = song.chords[index];
    Widget cell({bool interactive = true}) => ChordCell(
          chord: e.chord,
          musicKey: song.keyAt(index),
          settings: settings,
          confidence: e.confidence,
          beats: e.beats,
          edited: e.edited,
          highlight: current,
          ring: next ? repeatColor : null,
          onTap: interactive ? () => _tapChord(i, k) : null,
        );
    return KeyedSubtree(
      key: _cellKeys.putIfAbsent(index, GlobalKey.new),
      child: _draggable(
        data: _MoveItem(i, k),
        feedback: cell(interactive: false),
        ghost: Opacity(opacity: 0.25, child: cell(interactive: false)),
        child: cell(),
      ),
    );
  }

  Widget _palette() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final key = song.key;
    final counts = <Chord, int>{};
    for (final c in song.chords) {
      counts[c.chord] = (counts[c.chord] ?? 0) + 1;
    }
    final used = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    Widget chip(Chord chord, {Color? color}) {
      final label = fmt.format(chord, spell: key?.spell);
      Widget body({double elevation = 0}) => Material(
            color: color ?? scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            elevation: elevation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(label, style: text.titleLarge),
            ),
          );
      return _draggable(data: _NewItem(chord), feedback: body(elevation: 8), child: body());
    }

    if (movingChord) {
      return DragTarget<_DragItem>(
        onWillAcceptWithDetails: (d) => d.data is _MoveItem,
        onAcceptWithDetails: (d) {
          final item = d.data as _MoveItem;
          _mutate(() => song.removeChord(item.occurrence, item.offset));
          _toast('Acorde eliminado', undo: true);
        },
        builder: (context, candidates, _) => Container(
          decoration: BoxDecoration(
            color: candidates.isEmpty ? scheme.errorContainer.withValues(alpha: 0.4) : scheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.error, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline, size: 56, color: scheme.onErrorContainer),
                const SizedBox(height: 8),
                Text('Suelta aquí para eliminar', style: text.titleMedium?.copyWith(color: scheme.onErrorContainer)),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Acordes', style: text.titleMedium),
          Text(
            'Arrástralos a la partitura. Los de la partitura también se arrastran para moverlos.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text('Del piano', style: text.labelLarge),
          const SizedBox(height: 6),
          ListenableBuilder(
            listenable: engine,
            builder: (context, _) {
              final c = engine.current?.chord;
              return c == null
                  ? Text('Toca un acorde y arrástralo', style: TextStyle(color: scheme.onSurfaceVariant))
                  : Align(alignment: Alignment.centerLeft, child: chip(c, color: scheme.tertiaryContainer));
            },
          ),
          if (key != null) ...[
            const SizedBox(height: 16),
            Text('De ${key.label(settings.notation)}', style: text.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final c in key.diatonicChords) chip(c)]),
          ],
          if (used.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('En esta canción', style: text.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final c in used.take(16)) chip(c)]),
          ],
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  key == null ? 'Tonalidad sin determinar' : 'Tonalidad: ${key.label(settings.notation)}',
                  style: text.bodyLarge,
                ),
              ),
              TextButton(onPressed: _changeKey, child: const Text('Cambiar')),
            ],
          ),
          Text(
            '${song.chords.length} acordes · ${song.arrangement.length} secciones',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Future<void> _changeKey() async {
    final result = await pickKey(context, current: song.keyManual ? song.key : null, notation: settings.notation);
    if (result == null) return;
    final (key,) = result;
    await _mutate(() {
      if (key == null) {
        song.keyManual = false;
      } else {
        song
          ..key = key
          ..keyManual = true;
      }
    });
  }
}

/// Lugar donde se puede soltar un acorde: marca con una barra si cae antes o
/// después del acorde que tiene debajo.
class _DropSlot extends StatefulWidget {
  const _DropSlot({required this.child, required this.onDrop, this.end = false});

  final Widget child;
  final void Function(_DragItem item, bool after) onDrop;

  /// El "+" del final: siempre agrega al final.
  final bool end;

  @override
  State<_DropSlot> createState() => _DropSlotState();
}

class _DropSlotState extends State<_DropSlot> {
  bool? _after;

  bool _sideOf(Offset global) {
    if (widget.end) return false;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;
    return box.globalToLocal(global).dx > box.size.width / 2;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return DragTarget<_DragItem>(
      onMove: (d) {
        final after = _sideOf(d.offset);
        if (after != _after) setState(() => _after = after);
      },
      onLeave: (_) => setState(() => _after = null),
      onAcceptWithDetails: (d) {
        final after = _sideOf(d.offset);
        setState(() => _after = null);
        widget.onDrop(d.data, after);
      },
      builder: (context, candidates, _) {
        final after = _after;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (candidates.isNotEmpty && after != null)
              Positioned(
                top: 2,
                bottom: 2,
                left: after ? null : -6,
                right: after ? -6 : null,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
              ),
          ],
        );
      },
    );
  }
}
