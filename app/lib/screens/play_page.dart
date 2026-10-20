import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../midi/midi_service.dart';
import '../play/live_follow.dart';
import '../play/song_player.dart';
import '../settings.dart';
import '../storage/song_repository.dart';
import '../widgets/chord_cell.dart';
import '../widgets/repeat_badge.dart';
import '../widgets/responsive.dart';
import '../widgets/settings_sheet.dart';
import 'song_list_page.dart';
import 'song_page.dart' show SongOpener;

enum PlayMode { original, live }

/// Tocar una canción: reproducir la toma original o seguir en vivo lo que tocas.
class PlayPage extends StatefulWidget {
  const PlayPage({
    super.key,
    required this.song,
    required this.repo,
    required this.midi,
    required this.engine,
    required this.settings,
    this.initialMode,
    this.onOpenSong,
  });

  /// Modo con el que empezar (el de la canción anterior de la lista).
  final PlayMode? initialMode;

  /// Para pasar a la canción anterior o siguiente de la lista para tocar.
  final SongOpener? onOpenSong;

  final Song song;
  final SongRepository repo;
  final MidiService midi;
  final ChordEngine engine;
  final AppSettings settings;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  late final SongPlayer player = SongPlayer(song: widget.song, midi: widget.midi);
  late final LiveFollow live = LiveFollow(song: widget.song, engine: widget.engine);
  late PlayMode mode = widget.initialMode == PlayMode.live || !player.canPlay ? PlayMode.live : PlayMode.original;
  final Map<int, GlobalKey> _cellKeys = {};
  int? _scrolledTo;

  Song get song => widget.song;
  AppSettings get settings => widget.settings;

  /// Ver lo que suena o las figuras originales (se guarda con la canción).
  bool get sounding => !song.showOriginal;
  int get _shown => sounding ? song.transpose : 0;

  Future<void> _setSounding(bool value) async {
    setState(() => song.showOriginal = !value);
    await widget.repo.save(song);
  }

  /// Cambia el transporte de la canción (y la capa del motor para seguir).
  Future<void> _setTranspose(int semitones) async {
    setState(() {
      song.transpose = semitones;
      if (semitones == 0) song.showOriginal = false;
    });
    widget.engine.layer = semitones;
    await widget.repo.save(song);
  }

  late final int _previousLayer;

  /// La pantalla de tocar que manda sobre la capa del motor. Al pasar de una
  /// canción a la siguiente, la anterior se cierra después de abrir la nueva:
  /// solo la última devuelve la capa que había antes de empezar a tocar.
  static _PlayPageState? _active;

  @override
  void initState() {
    super.initState();
    // Para tocar con el transporte de la canción, el motor usa la misma capa.
    _previousLayer = _active?._previousLayer ?? widget.engine.layer;
    _active = this;
    widget.engine.layer = song.transpose;
  }

  @override
  void dispose() {
    player.dispose();
    live.dispose();
    if (_active == this) {
      widget.engine.layer = _previousLayer;
      _active = null;
    }
    super.dispose();
  }

  int? get _current => switch (mode) {
    PlayMode.original => player.chordIndex,
    PlayMode.live => live.follower.position < 0 ? null : live.follower.position,
  };

  int? get _next {
    if (mode == PlayMode.live) return live.follower.next;
    final c = _current;
    if (c == null) return song.chords.isEmpty ? null : 0;
    return c + 1 < song.chords.length ? c + 1 : null;
  }

  void _setMode(PlayMode m) {
    if (m == mode) return;
    player.pause();
    setState(() => mode = m);
  }

  void _tapChord(int index) {
    switch (mode) {
      case PlayMode.original:
        final start = song.chords[index].startMicros;
        if (start != null) player.seek(start);
      case PlayMode.live:
        live.jumpTo(index);
    }
  }

  String _chordText(int index) {
    final chord = song.chords[index].chord.transpose(_shown);
    final key = song.keyAt(index)?.transpose(_shown);
    final fmt = settings.formatter;
    final name = fmt.format(chord, spell: key?.spell);
    return switch (settings.display) {
      ChordDisplay.chords => name,
      ChordDisplay.degrees => key == null ? name : fmt.nashville(chord, key),
      ChordDisplay.both => key == null ? name : '$name  ·  ${fmt.nashville(chord, key)}',
    };
  }

  /// Nota de apoyo de la sección donde está el acorde [index], si tiene.
  String? _noteAt(int? index) {
    if (index == null) return null;
    final o = song.occurrenceAt(index);
    final note = o == null ? null : song.section(o.sectionId)?.note;
    return note == null || note.trim().isEmpty ? null : note.trim();
  }

  String _whereLabel(int index) {
    final o = song.occurrenceAt(index);
    if (o == null) return '';
    final label = song.section(o.sectionId)?.label ?? '';
    return o.repeats > 1 ? '$label · vuelta ${o.passOf(index)} de ${o.repeats}' : label;
  }

  void _scrollToCurrent(int? index) {
    if (index == null || index == _scrolledTo) return;
    _scrolledTo = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _cellKeys[index]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.35,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([player, live, settings]),
      builder: (context, _) {
        final current = _current;
        _scrollToCurrent(current);
        if (context.isCompact) return _compact(current);
        return Scaffold(
          appBar: AppBar(
            title: Text(song.title, overflow: TextOverflow.ellipsis),
            actions: [
              SegmentedButton<PlayMode>(
                segments: [
                  ButtonSegment(
                    value: PlayMode.original,
                    enabled: player.canPlay,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Original'),
                    tooltip: 'Reproducir la toma original',
                  ),
                  const ButtonSegment(
                    value: PlayMode.live,
                    icon: Icon(Icons.piano),
                    label: Text('En vivo'),
                    tooltip: 'Tocar en vivo: avanza con lo que tocas',
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) => _setMode(s.first),
              ),
              const SizedBox(width: 12),
              _transposeStepper(),
              if (song.transpose != 0 && song.key != null) ...[
                const SizedBox(width: 12),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: true, label: Text('Suena ${song.soundingKey!.name(settings.notation)}')),
                    ButtonSegment(value: false, label: Text('Original ${song.key!.name(settings.notation)}')),
                  ],
                  selected: {sounding},
                  onSelectionChanged: (s) => _setSounding(s.first),
                ),
              ],
              const SizedBox(width: 8),
              // Algo está mal: al editor, probando, sin perder el hilo.
              OutlinedButton.icon(
                // Se sigue desde el acorde en el que ibas.
                onPressed: () => Navigator.of(context).pop('edit:${_current ?? -1}'),
                icon: const Icon(Icons.edit_note),
                label: const Text('Editar'),
              ),
              SettingsButton(settings: settings),
              const SizedBox(width: 8),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                SizedBox(height: 210, child: _nowNext(current, _next)),
                const SizedBox(height: 12),
                Expanded(child: _chart(current, _next)),
                if (mode == PlayMode.original) _transport(),
                _setlist(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// − Transpose +2 +: queda guardado en la canción para la próxima vez.
  Widget _transposeStepper() {
    final scheme = Theme.of(context).colorScheme;
    final t = song.transpose;
    final range = settings.transposeRange;
    return Tooltip(
      message: 'Transporte de la canción (se guarda). Ponlo igual en el TRANSPOSE del piano.',
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: t == 0 ? scheme.outlineVariant : scheme.tertiary),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: t > -range ? () => _setTranspose(t - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            Text(
              context.isCompact ? 'T ${TransposeAdvice.label(t)}' : 'Transpose ${TransposeAdvice.label(t)}',
              style: TextStyle(fontWeight: FontWeight.w600, color: t == 0 ? scheme.onSurface : scheme.tertiary),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: t < range ? () => _setTranspose(t + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  /// Teléfono: Ahora y Sigue arriba, el estado en una línea y el resto en el menú.
  Widget _compact(int? current) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final f = live.follower;
    final played = f.lastPlayed;
    final (label, color) = mode == PlayMode.original
        ? (player.playing ? 'Reproduciendo la toma' : 'Toma original', scheme.onSurfaceVariant)
        : switch (f.status) {
            FollowStatus.waiting => ('Toca el primer acorde', scheme.onSurfaceVariant),
            FollowStatus.onTrack => ('En curso', Colors.greenAccent),
            FollowStatus.jumped => ('Saltaste a ${_whereLabel(f.position)}', scheme.tertiary),
            FollowStatus.offScript => ('Esperando el acorde que sigue', Colors.amberAccent),
            FollowStatus.finished => ('¡Fin de la canción!', Colors.greenAccent),
          };
    final short = context.screen.height < 500;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(song.title, overflow: TextOverflow.ellipsis),
        actions: [
          SegmentedButton<PlayMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: PlayMode.original,
                enabled: player.canPlay,
                icon: const Icon(Icons.play_circle_outline),
                tooltip: 'Reproducir la toma original',
              ),
              const ButtonSegment(value: PlayMode.live, icon: Icon(Icons.piano), tooltip: 'Tocar en vivo'),
            ],
            selected: {mode},
            onSelectionChanged: (s) => _setMode(s.first),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: () => Navigator.of(context).pop('edit:${_current ?? -1}'),
            icon: const Icon(Icons.edit_note),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'piano' => setState(() {
                player.pause();
                player.soundOnPiano = !player.soundOnPiano;
              }),
              'sounding' => _setSounding(!sounding),
              'restart' => live.restart(),
              _ => showSettings(context, settings),
            },
            itemBuilder: (_) => [
              if (mode == PlayMode.original)
                CheckedPopupMenuItem(
                  value: 'piano',
                  checked: player.soundOnPiano,
                  child: const Text('Sonar en el piano'),
                ),
              if (mode == PlayMode.live) const PopupMenuItem(value: 'restart', child: Text('Desde el inicio')),
              if (song.transpose != 0 && song.key != null)
                PopupMenuItem(
                  value: 'sounding',
                  child: Text(
                    sounding
                        ? 'Ver figuras originales (${song.key!.name(settings.notation)})'
                        : 'Ver lo que suena (${song.soundingKey!.name(settings.notation)})',
                  ),
                ),
              const PopupMenuItem(value: 'settings', child: Text('Configuración')),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Column(
          children: [
            // Acostado no hay alto: el estado va al lado de Ahora y Sigue.
            if (short)
              SizedBox(
                height: 96,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _nowNext(current, _next, compact: true)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 200,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            widget.midi.connected == null ? 'Piano desconectado' : label,
                            maxLines: 2,
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: widget.midi.connected == null ? scheme.error : color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _transposeStepper(),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              SizedBox(height: 132, child: _nowNext(current, _next, compact: true)),
              Row(
                children: [
                  Icon(
                    widget.midi.connected == null ? Icons.usb_off : Icons.circle,
                    size: 12,
                    color: widget.midi.connected == null ? scheme.error : color,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.midi.connected == null
                          ? 'Piano desconectado'
                          : played != null && mode == PlayMode.live
                          ? '$label · tocaste ${settings.formatter.format(played.transpose(_shown))}'
                          : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: widget.midi.connected == null ? scheme.error : color),
                    ),
                  ),
                  _transposeStepper(),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Expanded(child: _chart(current, _next)),
            if (mode == PlayMode.original) _transport(),
            _setlist(),
          ],
        ),
      ),
    );
  }

  Widget _nowNext(int? current, int? next, {bool compact = false}) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget card(String title, int? index, {required bool main, String? note}) => Card(
      margin: compact ? const EdgeInsets.all(2) : null,
      color: main ? scheme.primaryContainer : null,
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: compact ? text.labelMedium : text.titleMedium),
            if (note != null)
              Text(
                '📝 $note',
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: (compact ? text.labelMedium : text.titleMedium)?.copyWith(
                  color: main ? scheme.onPrimaryContainer : scheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Expanded(
              child: Center(
                child: FittedBox(
                  child: Text(
                    index == null ? '—' : _chordText(index),
                    style: TextStyle(
                      fontSize: main ? 96 : 64,
                      fontWeight: FontWeight.w700,
                      color: main ? scheme.onPrimaryContainer : repeatColor,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              index == null ? '' : _whereLabel(index),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (compact ? text.labelSmall : text.titleMedium)?.copyWith(
                color: main ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    // La nota de la sección actual se ve en "Ahora"; la de la siguiente
    // sección se anticipa en "Sigue" cuando el próximo acorde ya es de otra.
    final currentNote = _noteAt(current ?? next);
    final nextSection = next == null ? null : song.occurrenceAt(next);
    final nextNote = next != null && nextSection != (current == null ? null : song.occurrenceAt(current))
        ? _noteAt(next)
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: card('Ahora', current, main: true, note: current == null ? null : currentNote)),
        SizedBox(width: compact ? 4 : 12),
        Expanded(
          flex: 2,
          child: card('Sigue', next, main: false, note: nextNote ?? (current == null ? currentNote : null)),
        ),
        if (!compact) ...[
          const SizedBox(width: 12),
          SizedBox(width: 300, child: mode == PlayMode.live ? _liveStatus() : _playbackInfo()),
        ],
      ],
    );
  }

  Widget _liveStatus() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final f = live.follower;
    final fmt = settings.formatter;
    final played = f.lastPlayed;
    final (label, color) = switch (f.status) {
      FollowStatus.waiting => ('Toca el primer acorde', scheme.onSurfaceVariant),
      FollowStatus.onTrack => ('En curso', Colors.greenAccent),
      FollowStatus.jumped => ('Saltaste a ${_whereLabel(f.position)}', scheme.tertiary),
      FollowStatus.offScript => ('Esperando el acorde que sigue', Colors.amberAccent),
      FollowStatus.finished => ('¡Fin de la canción!', Colors.greenAccent),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _connectionLine(),
            const SizedBox(height: 8),
            Text(label, style: text.titleMedium?.copyWith(color: color)),
            if (played != null) ...[
              const SizedBox(height: 4),
              Text(
                'Tocaste: ${fmt.format(played.transpose(_shown))}',
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (song.transpose != 0)
              Text(
                'TRANSPOSE del piano en ${TransposeAdvice.label(song.transpose)}',
                style: text.bodyMedium?.copyWith(color: scheme.tertiary),
              ),
            const Spacer(),
            if (f.status == FollowStatus.finished && widget.onOpenSong != null)
              if (_neighbors.$2 case final next?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: FilledButton.icon(
                    onPressed: () => _goTo(next),
                    icon: const Icon(Icons.skip_next),
                    label: Text('Siguiente: ${next.title}', overflow: TextOverflow.ellipsis),
                  ),
                ),
            Tooltip(
              message: 'También puedes tocar un acorde de la partitura para saltar ahí.',
              child: TextButton.icon(
                onPressed: live.restart,
                icon: const Icon(Icons.replay),
                label: const Text('Desde el inicio'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Canción anterior y siguiente de la lista para tocar.
  (Song?, Song?, int, int) get _neighbors {
    final list = SongListPage.liveList(widget.repo, settings);
    final i = list.indexWhere((s) => s.id == song.id);
    if (i < 0) return (null, null, -1, list.length);
    return (i > 0 ? list[i - 1] : null, i + 1 < list.length ? list[i + 1] : null, i, list.length);
  }

  void _goTo(Song other) {
    final open = widget.onOpenSong;
    if (open == null) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    open(other, play: mode);
  }

  Widget _setlist() {
    final (previous, next, index, total) = _neighbors;
    if (widget.onOpenSong == null || index < 0) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (context.isCompact) {
      return Row(
        children: [
          IconButton(
            tooltip: previous == null ? null : 'Anterior: ${previous.title}',
            onPressed: previous == null ? null : () => _goTo(previous),
            icon: const Icon(Icons.skip_previous),
          ),
          Text('${index + 1} de $total', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: next == null
                ? Text(
                    'Última de la lista',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _goTo(next),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.skip_next),
                      label: Text(next.title, overflow: TextOverflow.ellipsis),
                    ),
                  ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: previous == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _goTo(previous),
                      icon: const Icon(Icons.skip_previous),
                      label: Text(previous.title, overflow: TextOverflow.ellipsis),
                    ),
                  ),
          ),
          Text('Canción ${index + 1} de $total', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          Expanded(
            child: next == null
                ? Align(
                    alignment: Alignment.centerRight,
                    child: Text('Última de la lista', style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _goTo(next),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.skip_next),
                      label: Text('Siguiente: ${next.title}', overflow: TextOverflow.ellipsis),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Estado del piano en una línea (cabe en el panel angosto).
  Widget _connectionLine() {
    final scheme = Theme.of(context).colorScheme;
    final device = widget.midi.connected;
    return Row(
      children: [
        Icon(
          device == null ? Icons.usb_off : Icons.piano,
          size: 18,
          color: device == null ? scheme.error : Colors.greenAccent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            device?.name ?? 'Piano desconectado',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _playbackInfo() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Toma original', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Se reproduce el MIDI tal cual lo tocaste.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sonar en el piano'),
              subtitle: Text(widget.midi.connected == null ? 'Piano desconectado' : 'Por el cable MIDI'),
              value: player.soundOnPiano,
              onChanged: (v) => setState(() {
                player.pause();
                player.soundOnPiano = v;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transport() {
    final text = Theme.of(context).textTheme;
    String clock(int micros) {
      final s = micros ~/ 1000000;
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }

    final total = player.durationMicros;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton.filled(
            iconSize: 32,
            onPressed: player.toggle,
            icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(onPressed: player.restart, icon: const Icon(Icons.replay)),
          const SizedBox(width: 8),
          Text(clock(player.positionMicros), style: text.titleMedium),
          Expanded(
            child: Slider(
              value: total == 0 ? 0 : player.positionMicros.clamp(0, total) / total,
              onChanged: (v) => player.seek((v * total).round()),
            ),
          ),
          Text(clock(total), style: text.titleMedium),
        ],
      ),
    );
  }

  Widget _chart(int? current, int? next) {
    final occurrences = song.arrangement.isEmpty
        ? [SectionOccurrence(sectionId: '', start: 0, end: song.chords.length)]
        : song.arrangement;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListView(
      children: [
        for (final o in occurrences)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      song.section(o.sectionId)?.label ?? '',
                      style: text.titleMedium?.copyWith(color: scheme.primary),
                    ),
                    if (o.repeats > 1) ...[const SizedBox(width: 8), RepeatBadge(o.repeats, fontSize: 14)],
                    if (_noteAt(o.start) case final note?) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          '📝 $note',
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(color: scheme.tertiary),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = o.start; i < o.end; i++)
                      ChordCell(
                        key: _cellKeys.putIfAbsent(i, GlobalKey.new),
                        chord: song.chords[i].chord.transpose(_shown),
                        musicKey: song.keyAt(i)?.transpose(_shown),
                        settings: settings,
                        beats: song.chords[i].beats,
                        highlight: i == current,
                        ring: i == next ? repeatColor : null,
                        onTap: () => _tapChord(i),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
