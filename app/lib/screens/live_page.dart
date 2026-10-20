import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../midi/keyboard_state.dart';
import '../midi/midi_service.dart';
import '../settings.dart';
import '../storage/song_repository.dart';
import '../widgets/connection_status.dart';
import '../widgets/dialogs.dart';
import '../widgets/key_panel.dart';
import '../widgets/piano_keyboard.dart';
import '../widgets/responsive.dart';
import '../widgets/settings_sheet.dart';
import 'midi_test_page.dart';

/// En vivo: modo libre (detecta sin guardar) y grabación de canciones.
class LivePage extends StatelessWidget {
  const LivePage({
    super.key,
    required this.midi,
    required this.keyboard,
    required this.engine,
    required this.settings,
    required this.repo,
    required this.onOpenSong,
  });

  final MidiService midi;
  final KeyboardState keyboard;
  final ChordEngine engine;
  final AppSettings settings;
  final SongRepository repo;
  final ValueChanged<Song> onOpenSong;

  static String defaultTitle(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Canción ${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _toggleRecording(BuildContext context) async {
    if (!engine.recording) {
      engine.startRecording();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final take = engine.stopRecording();
    final song = take == null ? null : SongAnalyzer.fromTake(title: defaultTitle(take.recordedAt), take: take);
    if (song == null || song.chords.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('No se grabó ningún acorde')));
      return;
    }
    final summary =
        '${song.chords.length} acordes'
        '${song.key == null ? '' : ' · ${song.key!.label(settings.notation)}'}';
    final title = await askText(context, title: 'Guardar canción ($summary)', initial: song.title);
    if (title == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Grabación descartada')));
      return;
    }
    if (title.isNotEmpty) song.title = title;
    // La canción recuerda la capa con la que se tocó (lo que sonaba).
    song.transpose = engine.layer;
    await repo.save(song);
    onOpenSong(song);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([engine, settings, keyboard]),
          builder: (context, _) => context.isCompact
              ? _compact(context)
              : Column(
                  children: [
                    _TopBar(
                      midi: midi,
                      engine: engine,
                      settings: settings,
                      onRecord: () => _toggleRecording(context),
                      onClear: engine.reset,
                      onDiagnostics: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MidiTestPage(midi: midi, keyboard: keyboard, settings: settings),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _CurrentChord(engine: engine, settings: settings),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 340,
                              child: KeyPanel(
                                estimate: engine.key,
                                notation: settings.notation,
                                previousKey: engine.previousKey,
                                layer: engine.layer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Sequence(engine: engine, settings: settings),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: PianoKeyboard(held: keyboard.held, sustained: keyboard.sustained),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

extension on LivePage {
  /// Teléfono: todo apilado; la tonalidad en una franja que abre su panel.
  Widget _compact(BuildContext context) {
    final short = context.screen.height < 500;
    return Column(
      children: [
        _TopBar(
          midi: midi,
          engine: engine,
          settings: settings,
          compact: true,
          onRecord: () => _toggleRecording(context),
          onClear: engine.reset,
          onDiagnostics: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MidiTestPage(midi: midi, keyboard: keyboard, settings: settings),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: KeySummary(
            estimate: engine.key,
            notation: settings.notation,
            panel: (_) => KeyPanel(
              estimate: engine.key,
              notation: settings.notation,
              previousKey: engine.previousKey,
              layer: engine.layer,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _CurrentChord(engine: engine, settings: settings),
          ),
        ),
        const SizedBox(height: 8),
        _Sequence(engine: engine, settings: settings),
        if (!short) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: PianoKeyboard(held: keyboard.held, sustained: keyboard.sustained),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.midi,
    required this.engine,
    required this.settings,
    required this.onRecord,
    required this.onClear,
    required this.onDiagnostics,
    this.compact = false,
  });

  final MidiService midi;
  final ChordEngine engine;
  final AppSettings settings;
  final bool compact;
  final VoidCallback onRecord;
  final VoidCallback onClear;
  final VoidCallback onDiagnostics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recording = engine.recording;
    final elapsed = engine.recordingElapsed.inSeconds;
    final clock = '${elapsed ~/ 60}:${(elapsed % 60).toString().padLeft(2, '0')}';
    const red = Color(0xFFE53935);
    final transpose = _TransposeControl(
      engine: engine,
      range: settings.transposeRange,
      onChanged: (v) {
        engine.layer = v;
        settings.liveLayer = engine.layer;
      },
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Column(
          children: [
            Row(
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: recording ? red : scheme.surfaceContainerHighest,
                    foregroundColor: recording ? Colors.white : scheme.onSurface,
                  ),
                  onPressed: onRecord,
                  icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record, color: recording ? Colors.white : red),
                  label: Text(recording ? 'Detener  $clock' : 'Grabar'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConnectionStatus(midi: midi),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => switch (v) {
                    'clear' => onClear(),
                    'diag' => onDiagnostics(),
                    _ => showSettings(context, settings),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'clear', enabled: !recording, child: const Text('Borrar secuencia')),
                    const PopupMenuItem(value: 'diag', child: Text('Diagnóstico MIDI')),
                    const PopupMenuItem(value: 'settings', child: Text('Configuración')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  recording ? '● Grabando' : 'Modo libre',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: recording ? red : scheme.onSurface),
                ),
                const Spacer(),
                transpose,
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Text(
            recording ? '● Grabando' : 'Modo libre',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: recording ? red : scheme.onSurface),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: recording ? red : scheme.surfaceContainerHighest,
              foregroundColor: recording ? Colors.white : scheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            onPressed: onRecord,
            icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record, color: recording ? Colors.white : red),
            label: Text(recording ? 'Detener  $clock' : 'Grabar', style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 16),
          ConnectionStatus(midi: midi),
          const Spacer(),
          transpose,
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Borrar secuencia',
            onPressed: recording ? null : onClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: 'Diagnóstico MIDI',
            onPressed: onDiagnostics,
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          SettingsButton(settings: settings),
        ],
      ),
    );
  }
}

/// Capa de transpose digital: lo mismo que tienes puesto en el TRANSPOSE del piano.
class _TransposeControl extends StatelessWidget {
  const _TransposeControl({required this.engine, required this.range, required this.onChanged});

  final ChordEngine engine;
  final int range;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layer = engine.layer;
    final enabled = !engine.recording;
    return Tooltip(
      message: 'Pon aquí lo mismo que en el TRANSPOSE del piano',
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: layer == 0 ? scheme.outlineVariant : scheme.tertiary),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: enabled && layer > -range ? () => onChanged(layer - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            GestureDetector(
              onLongPress: enabled ? () => onChanged(0) : null,
              child: Text(
                'Transpose ${TransposeAdvice.label(layer)}',
                style: TextStyle(fontWeight: FontWeight.w600, color: layer == 0 ? scheme.onSurface : scheme.tertiary),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: enabled && layer < range ? () => onChanged(layer + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentChord extends StatelessWidget {
  const _CurrentChord({required this.engine, required this.settings});

  final ChordEngine engine;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final current = engine.current;
    if (current == null) {
      return Card(
        child: Center(
          child: Text('Toca un acorde…', style: text.headlineMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      );
    }

    final fmt = settings.formatter;
    final key = engine.displayKey;
    final spell = key?.spell;
    final notes = current.notes.toList()..sort();
    final alternatives = current.recognition.alternatives.take(3).toList();

    return Card(
      child: Padding(
        padding: context.isCompact
            ? const EdgeInsets.fromLTRB(16, 10, 16, 10)
            : const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedOpacity(
                    opacity: engine.sounding ? 1 : 0.55,
                    duration: const Duration(milliseconds: 250),
                    child: FittedBox(
                      child: Text(
                        fmt.format(current.chord, spell: spell),
                        style: text.displayLarge?.copyWith(fontSize: 140, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (key != null)
                    Text(
                      'grado ${fmt.nashville(current.chord, key)} en ${key.name(settings.notation)}',
                      style: text.titleLarge?.copyWith(color: scheme.primary),
                    ),
                  if (engine.layer != 0)
                    Text(
                      'suena: ${fmt.format(current.chord.transpose(engine.layer), spell: key?.transpose(engine.layer).spell)}',
                      style: text.titleLarge?.copyWith(color: scheme.tertiary),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    notes.map(settings.noteName).join('  '),
                    style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Text('Seguridad ${(current.confidence * 100).round()} %', style: text.labelLarge),
                const SizedBox(width: 12),
                SizedBox(
                  width: context.isCompact ? 56 : 120,
                  child: LinearProgressIndicator(
                    value: current.confidence,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                SizedBox(width: context.isCompact ? 12 : 24),
                if (alternatives.isNotEmpty)
                  Expanded(
                    child: Text(
                      'También: ${alternatives.map((a) => '${fmt.format(a.chord, spell: spell)} ${(a.probability * 100).round()}%').join(' · ')}',
                      style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Sequence extends StatelessWidget {
  const _Sequence({required this.engine, required this.settings});

  final ChordEngine engine;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chords = engine.chords.reversed.toList();
    final fmt = settings.formatter;
    final key = engine.displayKey;
    return SizedBox(
      height: 72,
      child: chords.isEmpty
          ? Center(
              child: Text('Aquí aparecerá la secuencia de acordes', style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: chords.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final latest = i == 0;
                final chord = chords[i].chord;
                final fg = latest ? scheme.onPrimaryContainer : scheme.onSurface;
                return Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: latest ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        fmt.format(chord, spell: key?.spell),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: latest ? FontWeight.w700 : FontWeight.w500,
                          color: fg,
                        ),
                      ),
                      if (key != null)
                        Text(
                          fmt.nashville(chord, key),
                          style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.7)),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
