import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../settings.dart';

/// Botón ⚙ que abre la configuración de visualización.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Configuración',
        onPressed: () => showSettings(context, settings),
        icon: const Icon(Icons.settings_outlined),
      );
}

Future<void> showSettings(BuildContext context, AppSettings settings) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configuración', style: text.titleLarge),
                const SizedBox(height: 20),
                Text('Notación', style: text.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<Notation>(
                  segments: const [
                    ButtonSegment(value: Notation.american, label: Text('Americana (C D E)')),
                    ButtonSegment(value: Notation.latin, label: Text('Latina (Do Re Mi)')),
                  ],
                  selected: {settings.notation},
                  onSelectionChanged: (s) => settings.notation = s.first,
                ),
                const SizedBox(height: 20),
                Text('En las canciones mostrar', style: text.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<ChordDisplay>(
                  segments: const [
                    ButtonSegment(value: ChordDisplay.chords, label: Text('Acordes')),
                    ButtonSegment(value: ChordDisplay.degrees, label: Text('Grados (1 4 5 6m)')),
                    ButtonSegment(value: ChordDisplay.both, label: Text('Ambos')),
                  ],
                  selected: {settings.display},
                  onSelectionChanged: (s) => settings.display = s.first,
                ),
                const Divider(height: 40),
                Text('Piano', style: text.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mi piano envía el MIDI ya transpuesto'),
                  subtitle: const Text(
                    'Con el TRANSPOSE del piano activo, llegan las notas que suenan. '
                    'La app resta la capa para mostrarte tus figuras originales.',
                  ),
                  value: settings.pianoSendsTransposed,
                  onChanged: (v) => settings.pianoSendsTransposed = v,
                ),
                const SizedBox(height: 8),
                Text('Rango del transpose del piano', style: text.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 6, label: Text('±6 semitonos')),
                    ButtonSegment(value: 12, label: Text('±12 semitonos')),
                  ],
                  selected: {settings.transposeRange},
                  onSelectionChanged: (s) => settings.transposeRange = s.first,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
