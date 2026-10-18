import 'package:flutter/material.dart';

import '../midi/keyboard_state.dart';
import '../midi/midi_service.dart';
import '../settings.dart';
import '../widgets/connection_status.dart';
import '../widgets/piano_keyboard.dart';

/// Diagnóstico: cada mensaje MIDI que llega, sin análisis.
class MidiTestPage extends StatelessWidget {
  const MidiTestPage({
    super.key,
    required this.midi,
    required this.keyboard,
    required this.settings,
  });

  final MidiService midi;
  final KeyboardState keyboard;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico MIDI'),
        actions: [
          ConnectionStatus(midi: midi),
          IconButton(
            tooltip: 'Limpiar',
            onPressed: keyboard.clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([keyboard, settings]),
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _NowPlaying(state: keyboard, settings: settings)),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _EventLog(state: keyboard, settings: settings)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: PianoKeyboard(held: keyboard.held, sustained: keyboard.sustained),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.state, required this.settings});

  final KeyboardState state;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final held = state.held.keys.toList()..sort();
    final sustained = state.sustained.toList()..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Teclas presionadas', style: text.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: Text(
                  held.isEmpty ? '—' : held.map(settings.noteName).join('  '),
                  style: text.displayMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (sustained.isNotEmpty)
              Text(
                'Sostenidas por pedal: ${sustained.map(settings.noteName).join(' ')}',
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Pill(label: state.pedalDown ? 'Pedal abajo' : 'Pedal arriba', active: state.pedalDown),
                const SizedBox(width: 12),
                _Pill(label: 'Velocidad: ${state.lastVelocity ?? '—'}', active: false),
                const SizedBox(width: 12),
                _Pill(label: 'Mensajes: ${state.messageCount}', active: false),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: active ? scheme.onPrimary : scheme.onSurface)),
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.state, required this.settings});

  final KeyboardState state;
  final AppSettings settings;

  String describe(MidiInput e) {
    final t = (e.time.inMilliseconds / 1000).toStringAsFixed(3).padLeft(8);
    final note = settings.noteName(e.data1).padRight(5);
    final body = switch (e.kind) {
      MidiInputKind.noteOn => 'NOTE ON   $note vel ${e.data2}',
      MidiInputKind.noteOff => 'NOTE OFF  $note',
      MidiInputKind.controlChange => e.data1 == KeyboardState.sustainController
          ? 'PEDAL     ${e.data2 >= 64 ? 'abajo' : 'arriba'} (${e.data2})'
          : 'CC ${e.data1.toString().padRight(6)} ${e.data2}',
    };
    return '$t  ch${e.channel + 1}  $body';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mensajes MIDI', style: text.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: state.log.isEmpty
                  ? const Center(child: Text('Toca una tecla del piano…'))
                  : ListView(
                      children: [
                        for (final e in state.log)
                          Text(describe(e), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
