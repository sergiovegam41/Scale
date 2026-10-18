import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import 'key_panel.dart';

/// Esquina de la canción: tonalidad original, equivalencias y modulaciones.
class SongKeyPanel extends StatelessWidget {
  const SongKeyPanel({
    super.key,
    required this.song,
    required this.notation,
    required this.onChangeKey,
    required this.onRemoveModulation,
    required this.onTranspose,
  });

  final Song song;
  final Notation notation;
  final VoidCallback onChangeKey;
  final VoidCallback onTranspose;

  /// Recibe el índice de la región cuya modulación se quiere quitar.
  final ValueChanged<int> onRemoveModulation;

  static String duration(int micros) {
    final s = micros ~/ 1000000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final key = song.key;
    final confidence = song.keyConfidence;
    final (status, color) = song.keyManual
        ? ('Manual', scheme.tertiary)
        : KeyPanel.status(confidence ?? 0, scheme);
    final takeMicros = song.takes.fold<int>(0, (a, t) => a + t.durationMicros);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Tonalidad', style: text.titleMedium),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: color),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(status, style: text.labelMedium?.copyWith(color: color)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (key == null)
              Text('Sin determinar', style: text.headlineSmall)
            else ...[
              FittedBox(
                child: Text(
                  key.label(notation),
                  style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (key.enharmonicName(notation) != null)
                Text(
                  '≡ ${key.enharmonicName(notation)} (enarmónica)',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              Text(
                '≡ ${key.relative.label(notation)} (relativa)',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (!song.keyManual && confidence != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: confidence,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${(confidence * 100).round()} %', style: text.titleMedium),
                  ],
                ),
              ],
            ],
            if (song.keyRegions.length > 1) ...[
              const Divider(height: 28),
              Text('Modulaciones', style: text.labelLarge),
              const SizedBox(height: 6),
              for (final (i, r) in song.keyRegions.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        r.start == 0 ? Icons.flag_outlined : Icons.trending_up,
                        size: 18,
                        color: scheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r.start == 0
                              ? 'Inicio: ${r.key.label(notation)}'
                              : 'Acorde ${r.start + 1}: ${r.key.label(notation)}',
                          style: text.bodyLarge,
                        ),
                      ),
                      if (key != null && r.start > 0)
                        Text(_interval(key, r.key), style: text.bodyMedium),
                      if (i > 0)
                        IconButton(
                          tooltip: 'No es una modulación',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onRemoveModulation(i),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                    ],
                  ),
                ),
            ],
            if (key != null) ...[
              const Divider(height: 28),
              Text('Transporte', style: text.labelLarge),
              const SizedBox(height: 6),
              if (song.transpose == 0)
                Text(
                  'Sin transporte: suena en ${key.name(notation)}.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                )
              else ...[
                Text(
                  'Suena en ${song.soundingKey!.label(notation)}',
                  style: text.titleMedium?.copyWith(color: scheme.tertiary),
                ),
                Text(
                  'TRANSPOSE del piano en ${TransposeAdvice.label(song.transpose)} '
                  'y figuras de ${key.name(notation)}',
                  style: text.bodyMedium,
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: onTranspose,
                icon: const Icon(Icons.swap_vert),
                label: const Text('Transportar…'),
              ),
            ],
            const Spacer(),
            Text(
              '${song.chords.length} acordes · ${song.sections.length} secciones'
              '${takeMicros > 0 ? ' · ${duration(takeMicros)}' : ''}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onChangeKey,
              icon: const Icon(Icons.tune),
              label: const Text('Cambiar tonalidad'),
            ),
          ],
        ),
      ),
    );
  }

  static String _interval(MusicKey from, MusicKey to) {
    final s = signedInterval(to.tonic - from.tonic);
    return s > 0 ? '+$s st' : '$s st';
  }
}
