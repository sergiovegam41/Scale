import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';
import '../score/score_editing.dart';
import '../score/score_player.dart';
import '../score/score_practice.dart';
import '../score/score_viewer.dart';
import '../storage/score_repository.dart';
import '../widgets/responsive.dart';

/// Una partitura abierta: verla, escucharla por el piano con el cursor
/// siguiendo las notas, y empezar desde cualquier nota tocándola.
class ScorePage extends StatefulWidget {
  const ScorePage({
    super.key,
    required this.score,
    required this.midi,
    this.repo,
    this.notation = Notation.american,
    this.autoplay = false,
    this.practice = PracticeMode.off,
  });

  final Score score;
  final MidiService midi;

  /// Para guardar los cambios (volver a escribir una grabación).
  final ScoreRepository? repo;
  final Notation notation;

  /// Empieza a sonar en cuanto se dibuja (para pruebas).
  final bool autoplay;

  /// Abrir ya practicando (para pruebas).
  final PracticeMode practice;

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {
  late Score score = widget.score;
  late ScoreTimeline timeline = ScoreTimeline.of(score);
  late final ScorePlayer player = ScorePlayer(widget.midi, timeline);
  late final ScorePractice practice = ScorePractice(player)
    ..misses.addListener(() => viewer.flash())
    ..summary.addListener(_onSummary);
  bool rewriting = false;
  final ScoreViewerController viewer = ScoreViewerController();
  int zoom = 45;
  ViewerInfo? info;
  Map<String, dynamic>? bench;
  final Stopwatch _opened = Stopwatch()..start();
  int? _firstDrawMs;

  /// Corrigiendo la partitura (null si no).
  ScoreEditing? editing;
  int _editRev = 0;

  /// Lo que se resalta al corregir: la nota elegida, o lo que suena.
  final ValueNotifier<List<String>> _editLit = ValueNotifier(const []);
  final FocusNode _keys = FocusNode(debugLabel: 'corregir');

  @override
  void initState() {
    super.initState();
    player.lit.addListener(_syncLit);
    player.addListener(_syncLit);
  }

  @override
  void dispose() {
    editing?.dispose();
    _editLit.dispose();
    _keys.dispose();
    practice.dispose();
    player.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  // ---------------------------------------------------------------------
  // Corregir

  void _syncLit() {
    final ed = editing;
    if (ed == null) return;
    _editLit.value = player.playing ? player.lit.value : ed.selection.value;
  }

  /// Pulso desplegado (con repeticiones) de un pulso de la partitura: la
  /// primera vez que suena.
  int _playTickOf(int tick) {
    final mi = score.measureAt(tick);
    for (final pm in timeline.order) {
      if (pm.index == mi) return pm.playTick + tick - score.measures[mi].tick;
    }
    return 0;
  }

  void _startEditing() {
    if (editing != null) return;
    player.stop();
    practice.setMode(PracticeMode.off);
    final ed = ScoreEditing(widget.midi, score)..onError = _toast;
    ed.addListener(_onEditing);
    _editRev = ed.editor.revision;
    setState(() {
      editing = ed;
      score = ed.score;
      timeline = ScoreTimeline.of(score);
      player.timeline = timeline;
      _pendingA = null;
    });
    _syncLit();
    _keys.requestFocus();
  }

  void _onEditing() {
    final ed = editing;
    if (ed == null || !mounted) return;
    if (ed.editor.revision != _editRev) {
      _editRev = ed.editor.revision;
      if (player.playing) player.pause();
      score = ed.score;
      timeline = ScoreTimeline.of(score);
      player.timeline = timeline;
    }
    final loc = ed.location;
    if (loc != null && !player.playing) player.seek(_playTickOf(loc.event.tick));
    setState(() {});
    _syncLit();
  }

  /// Termina de corregir: guarda o vuelve a la partitura de antes.
  Future<void> _finishEditing({required bool save}) async {
    final ed = editing;
    if (ed == null) return;
    player.stop();
    final changed = ed.editor.dirty;
    final Score next;
    if (save && changed) {
      next = ed.score..edited = true;
      await widget.repo?.save(next);
    } else {
      next = ed.original;
    }
    ed
      ..removeListener(_onEditing)
      ..dispose();
    if (!mounted) return;
    setState(() {
      editing = null;
      score = next;
      timeline = ScoreTimeline.of(next);
      player.timeline = timeline;
    });
    practice.refresh();
    if (save && changed) _toast('Correcciones guardadas');
  }

  /// Salir sin guardar (preguntando si había cambios).
  Future<void> _closeEditing() async {
    final ed = editing;
    if (ed == null) return;
    if (ed.editor.dirty) {
      final choice = await _askUnsaved();
      if (choice == null) return;
      await _finishEditing(save: choice);
    } else {
      await _finishEditing(save: false);
    }
  }

  /// true: guardar; false: descartar; null: seguir corrigiendo.
  Future<bool?> _askUnsaved() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Guardar las correcciones?'),
      content: const Text('Hiciste cambios en la partitura que todavía no están guardados.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Seguir corrigiendo')),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Descartar')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Guardar')),
      ],
    ),
  );

  /// Aplica una corrección a la nota elegida.
  void _edit(String Function(ScoreEditor editor, String id) change) {
    final ed = editing;
    final id = ed?.selected;
    if (ed == null || id == null) {
      _toast('Primero toca una nota en la partitura');
      return;
    }
    if (player.playing) player.pause();
    ed.apply(() => change(ed.editor, id));
  }

  void _nav(int direction) {
    final ed = editing;
    final id = ed?.selected;
    if (ed == null || id == null) return;
    final next = ed.editor.neighbor(id, direction);
    if (next != null) ed.select(next);
  }

  void _figure(NoteType type, int dots) => _edit((e, id) => e.setDuration(id, type, dots));

  void _toggleDot() {
    final e = editing?.location?.event;
    if (e == null) return;
    final (type, dots) = ScoreEditor.writtenOf(e);
    _figure(type, dots == 0 ? 1 : 0);
  }

  Future<void> _editChord() async {
    final ed = editing;
    final loc = ed?.location;
    final id = ed?.selected;
    if (ed == null || loc == null || id == null) return;
    final tick = loc.event.tick;
    final current = ed.editor.chordAt(tick);
    final controller = TextEditingController(
      text: current == null ? '' : ChordFormatter(notation: widget.notation).format(current.chord),
    );
    final measure = score.measures[score.measureAt(tick)].number;
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cifrado en el compás $measure'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Acorde',
              hintText: 'C, Am7, D/F#, Sol7…',
              helperText: 'Va sobre la nota elegida. Vacío para quitarlo.',
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          if (current != null) TextButton(onPressed: () => Navigator.of(context).pop(''), child: const Text('Quitar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Escribir')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    ed.apply(() {
      ed.editor.setChordSymbol(tick, text);
      return id;
    }, play: false);
    _keys.requestFocus();
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _nav(-1),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nav(1),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => _edit((e, id) => e.transpose(id, 1)),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () => _edit((e, id) => e.transpose(id, -1)),
    const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () => _edit((e, id) => e.transpose(id, 12)),
    const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () => _edit((e, id) => e.transpose(id, -12)),
    const SingleActivator(LogicalKeyboardKey.delete): () => _edit((e, id) => e.delete(id)),
    const SingleActivator(LogicalKeyboardKey.backspace): () => _edit((e, id) => e.delete(id)),
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => editing?.undo(),
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => editing?.redo(),
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () => editing?.redo(),
    const SingleActivator(LogicalKeyboardKey.digit3): () => _figure(NoteType.sixteenth, 0),
    const SingleActivator(LogicalKeyboardKey.digit4): () => _figure(NoteType.eighth, 0),
    const SingleActivator(LogicalKeyboardKey.digit5): () => _figure(NoteType.quarter, 0),
    const SingleActivator(LogicalKeyboardKey.digit6): () => _figure(NoteType.half, 0),
    const SingleActivator(LogicalKeyboardKey.digit7): () => _figure(NoteType.whole, 0),
    const SingleActivator(LogicalKeyboardKey.period): _toggleDot,
    const SingleActivator(LogicalKeyboardKey.escape): _closeEditing,
  };

  static const _figures = [
    NoteType.whole,
    NoteType.half,
    NoteType.quarter,
    NoteType.eighth,
    NoteType.sixteenth,
    NoteType.thirtySecond,
  ];

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Barra de corrección: la nota elegida y qué cambiarle.
  Widget _editBar(BuildContext context, ColorScheme scheme) {
    final ed = editing!;
    final text = Theme.of(context).textTheme;
    final loc = ed.location;
    final e = loc?.event;
    final written = e == null ? null : ScoreEditor.writtenOf(e);
    final isNote = loc != null && loc.note != null && !loc.event.isRest;
    final twoStaves = loc != null && loc.part.staves >= 2;
    final figureEditable = e != null && !e.grace && e.tuplet == null;
    final String describe;
    if (loc == null || e == null || written == null) {
      describe = 'Ninguna nota elegida';
    } else {
      final measure = score.measures[score.measureAt(e.tick)].number;
      final figure = e.grace ? 'nota de adorno' : ScoreEditor.figureName(written.$1, written.$2);
      final hand = twoStaves ? ' · ${e.staff == 1 ? 'mano derecha' : 'mano izquierda'}' : '';
      final what = isNote
          ? '${ScoreEditor.pitchName(loc.note!, widget.notation)}'
                '${e.notes.length > 1 ? ' (acorde de ${e.notes.length})' : ''}'
          : 'Silencio';
      describe = '$what · $figure\nCompás $measure$hand';
    }
    Widget pitchButton(String label, String tooltip, int semitones) => Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: isNote ? () => _edit((ed, id) => ed.transpose(id, semitones)) : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(label),
      ),
    );
    final accent = figureEditable ? scheme.primary : scheme.outline;
    return Container(
      color: scheme.tertiaryContainer.withValues(alpha: 0.35),
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Deshacer (Ctrl+Z)',
                  onPressed: ed.editor.canUndo ? ed.undo : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Rehacer (Ctrl+Y)',
                  onPressed: ed.editor.canRedo ? ed.redo : null,
                  icon: const Icon(Icons.redo),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Nota anterior (←)',
                  onPressed: loc == null ? null : () => _nav(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                SizedBox(
                  width: 200,
                  child: Text(describe, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                ),
                IconButton(
                  tooltip: 'Nota siguiente (→)',
                  onPressed: loc == null ? null : () => _nav(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                const SizedBox(width: 8),
                pitchButton('−½', 'Medio tono abajo (↓)', -1),
                pitchButton('+½', 'Medio tono arriba (↑)', 1),
                pitchButton('−8ª', 'Una octava abajo (Ctrl+↓)', -12),
                pitchButton('+8ª', 'Una octava arriba (Ctrl+↑)', 12),
                Tooltip(
                  message: 'Escribirla con la otra alteración (Do♯ ↔ Re♭)',
                  child: TextButton(
                    onPressed: isNote ? () => _edit((ed, id) => ed.respell(id)) : null,
                    child: const Text('♯ ↔ ♭'),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<NoteType>(
                  tooltip: 'Figura (teclas 3 a 7)',
                  enabled: figureEditable,
                  onSelected: (t) => _figure(t, 0),
                  itemBuilder: (_) => [
                    for (final t in _figures)
                      CheckedPopupMenuItem(
                        value: t,
                        checked: written?.$1 == t,
                        child: Text(_capital(ScoreEditor.figureName(t, 0))),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.music_note, size: 18, color: accent),
                        Text(
                          written == null ? 'Figura' : _capital(ScoreEditor.figureName(written.$1, 0)),
                          style: text.labelLarge?.copyWith(color: accent),
                        ),
                        Icon(Icons.arrow_drop_down, color: accent),
                      ],
                    ),
                  ),
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Puntillo'),
                  tooltip: 'Puntillo: la figura dura la mitad más (tecla .)',
                  selected: (written?.$2 ?? 0) > 0,
                  onSelected: figureEditable ? (_) => _toggleDot() : null,
                ),
                const SizedBox(width: 8),
                if (twoStaves)
                  TextButton.icon(
                    onPressed: isNote ? () => _edit((ed, id) => ed.moveToStaff(id, e!.staff == 1 ? 2 : 1)) : null,
                    icon: const Icon(Icons.swap_vert, size: 18),
                    label: Text(e?.staff == 2 ? 'A la derecha' : 'A la izquierda'),
                  ),
                IconButton(
                  tooltip: 'Borrar la nota (Supr)',
                  onPressed: isNote ? () => _edit((ed, id) => ed.delete(id)) : null,
                  icon: const Icon(Icons.delete_outline),
                ),
                TextButton.icon(
                  onPressed: e == null ? null : _editChord,
                  icon: const Icon(Icons.text_fields, size: 18),
                  label: const Text('Cifrado'),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    loc == null
                        ? 'Toca una nota (o un silencio) en la partitura para corregirla.'
                        : 'En el piano, toca la nota correcta (o el acorde, todo a la vez) y suelta: '
                              'se cambia y pasa a la siguiente.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              TextButton(onPressed: _closeEditing, child: const Text('Descartar')),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () => _finishEditing(save: true),
                icon: const Icon(Icons.check, size: 18),
                label: Text(ed.editor.dirty ? 'Guardar' : 'Listo'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Al terminar la pieza (o una vuelta del bucle) practicando.
  void _onSummary() {
    final s = practice.summary.value;
    if (s == null || !mounted) return;
    final review = s.review;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: review == null ? 5 : 10),
        content: Text(s.text),
        action: review == null || player.looping
            ? null
            : SnackBarAction(label: 'Repasar ese compás', onPressed: () => _loopPlayed(review)),
      ),
    );
  }

  /// Bucle sobre un compás desplegado.
  void _loopPlayed(int played) {
    final pm = timeline.order[played];
    final start = pm.playTick;
    player.setLoop(start, start + score.measures[pm.index].length);
    setState(() => _pendingA = null);
  }

  void _togglePractice() => practice.setMode(practice.mode == PracticeMode.off ? PracticeMode.wait : PracticeMode.off);

  /// Las dos manos, si la partitura es de piano: dos pentagramas de una
  /// parte, o dos partes de un pentagrama.
  late final List<(String, String, (int, int))> _hands = () {
    final parts = score.parts;
    if (parts.isNotEmpty && parts.first.staves >= 2) {
      return [('Der.', 'Mano derecha', (0, 1)), ('Izq.', 'Mano izquierda', (0, 2))];
    }
    if (parts.length == 2 && parts.every((p) => p.staves == 1)) {
      return [('Der.', 'Mano derecha', (0, 1)), ('Izq.', 'Mano izquierda', (1, 1))];
    }
    return <(String, String, (int, int))>[];
  }();

  void _toggleHand((int, int) key) => setState(() {
    player.muted.contains(key) ? player.muted.remove(key) : player.muted.add(key);
  });

  void _tapNote(String id) {
    final ed = editing;
    if (ed != null) {
      if (player.playing) player.pause();
      ed.select(id);
      _keys.requestFocus();
      return;
    }
    final tick = timeline.firstTickOf(id);
    if (tick == null) return;
    player.seek(tick);
  }

  /// Inicio del bucle ya marcado, esperando el final: (pulso, compás).
  (int, String)? _pendingA;

  String _numberAt(int playTick) => score.measures[timeline.order[timeline.playedMeasureAt(playTick)].index].number;

  /// Bucle A–B en tres toques: el compás donde se está es el inicio; luego
  /// el compás donde se está es el final; un tercer toque lo quita.
  void _loopTap() {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (player.looping) {
      player.clearLoop();
      messenger.showSnackBar(const SnackBar(content: Text('Bucle quitado: sigue hasta el final.')));
      return;
    }
    final pm = player.measure;
    final start = pm.playTick;
    final end = start + score.measures[pm.index].length;
    final a = _pendingA;
    if (a == null) {
      setState(() => _pendingA = (start, player.measureNumber));
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            'El bucle empieza en el compás ${player.measureNumber}. '
            'Ve al último compás que quieres repetir (tocando una nota) y vuelve a pulsar Bucle.',
          ),
        ),
      );
      return;
    }
    // Si el segundo compás está antes que el primero, se ordenan.
    final aEnd = a.$1 + score.measures[timeline.order[timeline.playedMeasureAt(a.$1)].index].length;
    final from = start < a.$1 ? start : a.$1;
    final to = start < a.$1 ? aEnd : (end > aEnd ? end : aEnd);
    setState(() => _pendingA = null);
    player.setLoop(from, to);
    messenger.showSnackBar(SnackBar(content: Text('Se repite del compás ${_numberAt(from)} al ${_numberAt(to - 1)}.')));
  }

  String get _loopLabel {
    if (player.looping) return 'c. ${_numberAt(player.loopA!)}–${_numberAt(player.loopB! - 1)}';
    if (_pendingA != null) return 'Desde c. ${_pendingA!.$2}…';
    return 'Bucle';
  }

  void _zoom(int delta) {
    setState(() => zoom = (zoom + delta).clamp(25, 80));
    viewer.setZoom(zoom);
  }

  static String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _showInfo() async {
    final i = info;
    final b = bench;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final s = score;
          final rec = s.recording;
          final lines = <String>[
            if (rec != null && rec.followedMetronome)
              'Grabada con metrónomo a ${rec.settings.bpm.round()} en ${rec.settings.time}'
                  '${rec.appliedLatencyMicros.abs() >= 1000 ? ', corrigiendo un ${rec.appliedLatencyMicros < 0 ? 'adelanto' : 'retraso'} de ${(rec.appliedLatencyMicros.abs() / 1000).round()} ms' : ''}',
            if (rec != null && !rec.followedMetronome)
              'Escrita a tu tempo (unas ${rec.playedQuarterBpm?.round()} negras por minuto); el metrónomo iba a '
                  '${rec.settings.bpm.round()} en ${rec.settings.time}',
            '${s.parts.length} ${s.parts.length == 1 ? 'parte' : 'partes'} · ${s.measures.length} compases · ${s.noteCount} notas',
            'Duración: ${_clock(timeline.duration)} (${timeline.order.length} compases con repeticiones)',
            if (s.source?.name != null) 'Archivo: ${s.source!.name}',
            if (i != null) ...[
              '',
              'Dibujo: ${i.pages} ${i.pages == 1 ? 'página' : 'páginas'}, grabado ${i.engraveMs} ms + pantalla ${i.domMs} ms',
              if (_firstDrawMs != null) 'Desde que se abrió: $_firstDrawMs ms',
              'Notas enlazadas: ${i.preserved + i.matched}/${i.total}'
                  '${i.matched > 0 ? ' (${i.matched} por posición)' : ''}',
            ],
            if (b != null) ...[
              '',
              'Desplazamiento: ${b['fps']} cuadros/s, ${b['slow']} lentos de ${b['frames']}, el peor ${b['worstMs']} ms',
            ],
          ];
          return AlertDialog(
            title: Text(s.title),
            content: SelectableText(lines.join('\n')),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  viewer.bench();
                },
                child: const Text('Medir fluidez'),
              ),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  /// Vuelve a escribir la partitura desde la grabación con otros ajustes.
  Future<void> _rewrite() async {
    final rec = score.recording;
    if (rec == null) return;
    if (score.edited) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Volver a escribir'),
          content: const Text(
            'Esta partitura tiene correcciones hechas a mano. Al volver a escribirla desde la grabación se pierden.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Seguir')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final settings = await showDialog<TranscriptionSettings>(
      context: context,
      builder: (_) => _RewriteDialog(recording: rec, notation: widget.notation),
    );
    if (settings == null || !mounted) return;
    setState(() => rewriting = true);
    final next = await compute(_transcribe, (rec.take, settings, score.id, score.title));
    if (!mounted) return;
    setState(() => rewriting = false);
    if (next == null) return;
    next
      ..createdAt = score.createdAt
      ..composer = score.composer
      ..arranger = score.arranger;
    player.stop();
    await widget.repo?.save(next);
    setState(() {
      score = next;
      timeline = ScoreTimeline.of(next);
      player.timeline = timeline;
      _pendingA = null;
    });
    practice.refresh();
    player.seek(0);
  }

  static Score? _transcribe((Take, TranscriptionSettings, String, String) a) =>
      PerformanceTranscriber.transcribe(a.$1, a.$2, id: a.$3, title: a.$4);

  Future<void> _pickSpeed() async {
    const options = [0.5, 0.6, 0.75, 0.9, 1.0, 1.1, 1.25];
    final picked = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final o in options)
              ListTile(
                leading: Icon(o == player.speed ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text('${(o * 100).round()} %'),
                subtitle: Text('${(timeline.bpmAt(player.tick) * o).round()} negras por minuto'),
                onTap: () => Navigator.of(context).pop(o),
              ),
          ],
        ),
      ),
    );
    if (picked != null) player.speed = picked;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = context.isCompact;
    final ed = editing;
    return PopScope(
      canPop: !(ed?.editor.dirty ?? false),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final choice = await _askUnsaved();
        if (choice == null || !mounted) return;
        await _finishEditing(save: choice);
        if (mounted) Navigator.of(this.context).pop();
      },
      child: CallbackShortcuts(
        bindings: ed == null ? const {} : _shortcuts,
        child: Focus(focusNode: _keys, autofocus: true, child: _scaffold(context, scheme, compact)),
      ),
    );
  }

  Widget _scaffold(BuildContext context, ColorScheme scheme, bool compact) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([player, practice]),
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _bar(context, scheme, compact),
                  if (practice.mode != PracticeMode.off) _practiceBar(context, scheme),
                  if (editing != null) _editBar(context, scheme),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ScoreViewer(
                score: score,
                lit: editing != null ? _editLit : player.lit,
                marked: practice.done,
                controller: viewer,
                zoom: zoom,
                revision: editing?.editor.revision ?? 0,
                onTapNote: _tapNote,
                onLoaded: (i) {
                  if (_firstDrawMs == null) practice.setMode(widget.practice);
                  if (_firstDrawMs == null && widget.autoplay) player.play();
                  _firstDrawMs ??= _opened.elapsedMilliseconds;
                  debugPrint('Visor: ${i.data} · abierto en ${_opened.elapsedMilliseconds} ms');
                  setState(() => info = i);
                },
                onBench: (b) {
                  setState(() => bench = b);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Desplazamiento: ${b['fps']} cuadros/s, ${b['slow']} lentos, el peor ${b['worstMs']} ms',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Barra de práctica: esperar o seguir, qué mano, aciertos y fallos.
  Widget _practiceBar(BuildContext context, ColorScheme scheme) {
    final text = Theme.of(context).textTheme;
    final gate = practice.gate;
    final hand = practice.hand;
    final handIndex = hand == null ? 0 : (_hands.indexWhere((h) => h.$3 == hand) + 1);
    final String status;
    if (practice.mode == PracticeMode.wait && gate != null) {
      if (gate.finished) {
        status = 'Terminaste: ${gate.hits} bien · ${gate.misses} mal';
      } else if (gate.stepsDone == 0 && !player.playing) {
        status = 'Toca las notas azules (o dale a reproducir) para empezar';
      } else {
        status = '${player.waiting ? 'Te espero · ' : ''}${gate.hits} bien · ${gate.misses} mal';
      }
    } else {
      status = practice.followPosition < 0
          ? 'Toca a tu ritmo: la partitura te sigue'
          : 'Vas en el compás ${player.measureNumber}';
    }
    return Container(
      color: scheme.secondaryContainer.withValues(alpha: 0.35),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SegmentedButton<PracticeMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(
                  value: PracticeMode.wait,
                  icon: Icon(Icons.hourglass_bottom, size: 18),
                  label: Text('Esperarme'),
                  tooltip: 'La música avanza a tempo y se detiene hasta que tocas cada nota',
                ),
                ButtonSegment(
                  value: PracticeMode.follow,
                  icon: Icon(Icons.trending_flat, size: 18),
                  label: Text('Seguirme'),
                  tooltip: 'Toca a tu ritmo: la partitura va donde vas y pasa las páginas',
                ),
              ],
              selected: {practice.mode},
              onSelectionChanged: (v) => practice.setMode(v.first),
            ),
            if (_hands.length == 2) ...[
              const SizedBox(width: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: 0, label: Text('Las dos')),
                  ButtonSegment(
                    value: 1,
                    label: Text('Der.'),
                    tooltip: 'Tocas la mano derecha; la izquierda suena sola',
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text('Izq.'),
                    tooltip: 'Tocas la mano izquierda; la derecha suena sola',
                  ),
                ],
                selected: {handIndex},
                onSelectionChanged: (v) => practice.setHand(v.first == 0 ? null : _hands[v.first - 1].$3),
              ),
            ],
            const SizedBox(width: 12),
            Text(status, style: text.bodyMedium),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: practice.restart,
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('De nuevo'),
            ),
            IconButton(
              tooltip: 'Dejar de practicar',
              onPressed: () => practice.setMode(PracticeMode.off),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, ColorScheme scheme, bool compact) {
    final text = Theme.of(context).textTheme;
    final hands = [
      for (final (label, tooltip, key) in _hands)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: FilterChip(
            visualDensity: VisualDensity.compact,
            label: Text(label),
            tooltip: '$tooltip: suena o calla',
            selected: !player.muted.contains(key),
            onSelected: (_) => _toggleHand(key),
          ),
        ),
    ];
    final noPiano = widget.midi.connected == null;
    final editingNow = editing != null;
    final practicing = practice.mode != PracticeMode.off || editingNow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          const BackButton(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(score.title, style: text.titleMedium, overflow: TextOverflow.ellipsis),
                Text(
                  'Compás ${player.measureNumber} · ${_clock(player.position)} / ${_clock(player.duration)}'
                  '${noPiano ? ' · sin piano' : ''}',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(tooltip: 'Al principio', onPressed: player.stop, icon: const Icon(Icons.skip_previous)),
          IconButton.filled(
            tooltip: player.playing ? 'Pausa' : 'Reproducir',
            onPressed: practice.mode == PracticeMode.follow ? null : player.toggle,
            icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
          ),
          TextButton(onPressed: _pickSpeed, child: Text('${(player.speed * 100).round()} %')),
          if (!compact && !editingNow)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: FilterChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.edit, size: 18),
                label: const Text('Corregir'),
                showCheckmark: false,
                tooltip: 'Corregir notas, figuras, manos y cifrado',
                selected: false,
                onSelected: (_) => _startEditing(),
              ),
            ),
          if (!compact && !editingNow)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: FilterChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.piano, size: 18),
                label: const Text('Tocar yo'),
                showCheckmark: false,
                tooltip: 'Practicar tocando en el teclado: la partitura te espera o te sigue',
                selected: practice.mode != PracticeMode.off,
                onSelected: (_) => _togglePractice(),
              ),
            ),
          if (!compact && !editingNow) ...[
            IconButton(
              tooltip: player.metronome ? 'Quitar el metrónomo' : 'Metrónomo mientras suena',
              isSelected: player.metronome,
              onPressed: () => player.metronome = !player.metronome,
              icon: const Icon(Icons.av_timer_outlined),
              selectedIcon: const Icon(Icons.av_timer),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.repeat, size: 18),
                label: Text(_loopLabel),
                tooltip: 'Repetir un pasaje: marca el primer compás y luego el último',
                selected: player.looping || _pendingA != null,
                onSelected: (_) => _loopTap(),
              ),
            ),
          ],
          if (player.canPlayAsPlayed && !compact && !practicing)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Escrita'), tooltip: 'A tempo, como está escrita'),
                  ButtonSegment(value: true, label: Text('Como la toqué'), tooltip: 'La grabación original'),
                ],
                selected: {player.asPlayed},
                onSelectionChanged: (s) => player.asPlayed = s.first,
              ),
            ),
          if (!compact && !practicing) ...hands,
          if (!compact) ...[
            IconButton(tooltip: 'Más pequeña', onPressed: () => _zoom(-5), icon: const Icon(Icons.zoom_out)),
            IconButton(tooltip: 'Más grande', onPressed: () => _zoom(5), icon: const Icon(Icons.zoom_in)),
          ],
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'in' => _zoom(5),
              'out' => _zoom(-5),
              'hand0' => _toggleHand(_hands[0].$3),
              'hand1' => _toggleHand(_hands[1].$3),
              'asPlayed' => player.asPlayed = !player.asPlayed,
              'metronome' => player.metronome = !player.metronome,
              'loop' => _loopTap(),
              'practice' => _togglePractice(),
              'edit' => _startEditing(),
              'rewrite' => _rewrite(),
              _ => _showInfo(),
            },
            itemBuilder: (_) => [
              if (!editingNow) const PopupMenuItem(value: 'edit', child: Text('Corregir notas')),
              if (compact && !editingNow) ...[
                CheckedPopupMenuItem(
                  value: 'practice',
                  checked: practice.mode != PracticeMode.off,
                  child: const Text('Tocar yo'),
                ),
                CheckedPopupMenuItem(value: 'metronome', checked: player.metronome, child: const Text('Metrónomo')),
                PopupMenuItem(
                  value: 'loop',
                  child: Text(
                    player.looping
                        ? 'Quitar el bucle (${_loopLabel.substring(3)})'
                        : (_pendingA != null ? 'Bucle: hasta este compás' : 'Bucle: desde este compás'),
                  ),
                ),
                const PopupMenuItem(value: 'in', child: Text('Más grande')),
                const PopupMenuItem(value: 'out', child: Text('Más pequeña')),
                for (final (i, (_, name, key)) in _hands.indexed)
                  CheckedPopupMenuItem(value: 'hand$i', checked: !player.muted.contains(key), child: Text(name)),
                if (player.canPlayAsPlayed)
                  CheckedPopupMenuItem(
                    value: 'asPlayed',
                    checked: player.asPlayed,
                    child: const Text('Oír como la toqué'),
                  ),
              ],
              if (score.recording != null && !editingNow)
                PopupMenuItem(value: 'rewrite', enabled: !rewriting, child: const Text('Volver a escribir…')),
              const PopupMenuItem(value: 'info', child: Text('Información y rendimiento')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ajustes para volver a escribir una grabación.
class _RewriteDialog extends StatefulWidget {
  const _RewriteDialog({required this.recording, required this.notation});

  final ScoreRecording recording;
  final Notation notation;

  @override
  State<_RewriteDialog> createState() => _RewriteDialogState();
}

class _RewriteDialogState extends State<_RewriteDialog> {
  late final TranscriptionSettings original = widget.recording.settings;
  late TranscriptionSettings s = original;

  /// Pulso escrito respecto al tocado: ½, 1 o 2.
  late double factor = 1;

  static const _meters = [TimeSignature(2, 4), TimeSignature(3, 4), TimeSignature.common, TimeSignature(6, 8)];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rec = widget.recording;
    final auto = rec.appliedLatencyMicros - original.latencyMicros;
    final usesMetronome =
        s.tempoMode == TempoMode.metronome || (s.tempoMode == TempoMode.auto && rec.followedMetronome);
    return AlertDialog(
      title: const Text('Volver a escribir'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Se usa la misma grabación: cambia solo cómo se escribe.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text('Pulso', style: text.titleSmall),
              Text(
                rec.followedMetronome
                    ? 'Seguiste el metrónomo (${original.bpm.round()}).'
                    : 'No seguiste el metrónomo (${original.bpm.round()}): se escribió a tu tempo, '
                          'unas ${rec.playedQuarterBpm?.round()} negras por minuto.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              SegmentedButton<TempoMode>(
                segments: const [
                  ButtonSegment(value: TempoMode.auto, label: Text('Automático')),
                  ButtonSegment(value: TempoMode.metronome, label: Text('Metrónomo')),
                  ButtonSegment(value: TempoMode.player, label: Text('Mi tempo')),
                ],
                selected: {s.tempoMode},
                onSelectionChanged: (v) => setState(() => s = s.copyWith(tempoMode: v.first)),
              ),
              const SizedBox(height: 14),
              Text('Compás', style: text.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'auto', label: Text('Auto')),
                  for (final m in _meters) ButtonSegment(value: '$m', label: Text('$m')),
                ],
                selected: {s.meter?.toString() ?? 'auto'},
                onSelectionChanged: (v) => setState(() {
                  final m = _meters.where((m) => '$m' == v.first).firstOrNull;
                  s = m == null ? s.copyWith(clearMeter: true) : s.copyWith(meter: m);
                }),
              ),
              const SizedBox(height: 14),
              Text('Figuras más pequeñas', style: text.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, label: Text('Corcheas')),
                  ButtonSegment(value: 4, label: Text('Semicorcheas')),
                ],
                selected: {s.grid},
                onSelectionChanged: (v) => setState(() => s = s.copyWith(grid: v.first)),
              ),
              const SizedBox(height: 14),
              Text('Valor de las figuras', style: text.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0.5, label: Text('Más largas')),
                  ButtonSegment(value: 1, label: Text('Normal')),
                  ButtonSegment(value: 2, label: Text('Más cortas')),
                ],
                selected: {factor},
                onSelectionChanged: (v) => setState(() {
                  factor = v.first;
                  s = s.copyWith(bpm: original.bpm * factor);
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Detectar tresillos'),
                value: s.triplets,
                onChanged: (v) => setState(() => s = s.copyWith(triplets: v)),
              ),
              if (usesMetronome) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Corregir mi adelanto o retraso'),
                  subtitle: Text(
                    auto.abs() < 1000
                        ? 'Tocaste a tiempo con el metrónomo'
                        : 'Tocaste ${(auto.abs() / 1000).round()} ms ${auto < 0 ? 'antes' : 'después'} del metrónomo',
                  ),
                  value: s.autoLatency,
                  onChanged: (v) => setState(() => s = s.copyWith(autoLatency: v)),
                ),
                Row(
                  children: [
                    const Text('Ajuste fino'),
                    Expanded(
                      child: Slider(
                        min: -100,
                        max: 100,
                        divisions: 40,
                        value: (s.latencyMicros / 1000).clamp(-100, 100).toDouble(),
                        label: '${(s.latencyMicros / 1000).round()} ms',
                        onChanged: (v) => setState(() => s = s.copyWith(latencyMicros: (v * 1000).round())),
                      ),
                    ),
                    SizedBox(width: 64, child: Text('${(s.latencyMicros / 1000).round()} ms')),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Tonalidad'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButton<int?>(
                      isExpanded: true,
                      value: s.keyIndex,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Automática')),
                        for (final k in MusicKey.all)
                          DropdownMenuItem<int?>(value: k.index, child: Text(k.label(widget.notation))),
                      ],
                      onChanged: (v) =>
                          setState(() => s = v == null ? s.copyWith(clearKey: true) : s.copyWith(keyIndex: v)),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Escribir el cifrado (acordes)'),
                value: s.chordSymbols,
                onChanged: (v) => setState(() => s = s.copyWith(chordSymbols: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Escribir dinámicas (p, mf, f)'),
                value: s.dynamics,
                onChanged: (v) => setState(() => s = s.copyWith(dynamics: v)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(context).pop(s), child: const Text('Escribir')),
      ],
    );
  }
}
