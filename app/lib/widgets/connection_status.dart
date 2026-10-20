import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

import '../midi/midi_service.dart';
import 'responsive.dart';

/// Estado de la conexión MIDI con acciones para elegir o reconectar.
class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({super.key, required this.midi, this.iconOnly = false});

  final MidiService midi;

  /// Solo el ícono (el nombre queda en la ayuda): para filas con poco espacio.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: midi,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final device = midi.connected;
        final (icon, color, label) = switch ((device, midi.connecting)) {
          (_, true) => (Icons.sync, scheme.tertiary, 'Conectando…'),
          (final MidiDevice d?, _) => (Icons.piano, Colors.greenAccent, d.name),
          _ when midi.devices.isEmpty => (Icons.usb_off, scheme.error, 'Sin dispositivos MIDI'),
          _ => (Icons.link_off, scheme.error, 'Desconectado'),
        };
        if (iconOnly) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: midi.error ?? label,
                child: Icon(icon, color: color),
              ),
              if (device == null && midi.devices.isNotEmpty && !midi.connecting)
                TextButton(onPressed: () => midi.connect(midi.devices.first), child: const Text('Conectar')),
              IconButton(tooltip: 'Buscar dispositivos', onPressed: midi.refresh, icon: const Icon(Icons.refresh)),
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Tooltip(
                message: midi.error ?? label,
                child: Chip(
                  avatar: Icon(icon, color: color, size: 18),
                  label: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: context.isCompact ? 150 : 260),
                    child: Text(label, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
            if (midi.devices.length > 1) ...[
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: device?.id,
                hint: const Text('Elegir'),
                items: [for (final d in midi.devices) DropdownMenuItem(value: d.id, child: Text(d.name))],
                onChanged: (id) => midi.connect(midi.devices.firstWhere((d) => d.id == id)),
              ),
            ],
            if (device == null && midi.devices.isNotEmpty && !midi.connecting) ...[
              const SizedBox(width: 8),
              FilledButton(onPressed: () => midi.connect(midi.devices.first), child: const Text('Conectar')),
            ],
            IconButton(tooltip: 'Buscar dispositivos', onPressed: midi.refresh, icon: const Icon(Icons.refresh)),
          ],
        );
      },
    );
  }
}
