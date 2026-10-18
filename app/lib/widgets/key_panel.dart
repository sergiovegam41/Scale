import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

/// Panel de tonalidad: la principal, su seguridad, equivalencias y alternativas.
class KeyPanel extends StatelessWidget {
  const KeyPanel({
    super.key,
    required this.estimate,
    required this.notation,
    this.previousKey,
    this.layer = 0,
  });

  final KeyEstimate estimate;
  final Notation notation;
  final MusicKey? previousKey;

  /// Capa de transpose digital: si no es 0, se indica lo que suena.
  final int layer;

  static (String, Color) status(double confidence, ColorScheme scheme) {
    if (confidence >= 0.7) return ('Confirmada', Colors.greenAccent);
    if (confidence >= 0.35) return ('Probable', Colors.amberAccent);
    return ('Explorando', scheme.onSurfaceVariant);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (estimate.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tonalidad', style: text.titleMedium),
              const Expanded(
                child: Center(
                  child: Text(
                    'Toca acordes para detectar la tonalidad',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final best = estimate.key;
    final relative = best.relative;
    final (label, color) = status(estimate.confidence, scheme);
    final enharmonic = best.enharmonicName(notation);
    final others = estimate.alternatives.where((c) => c.key != relative).take(3);

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
                  child: Text(label, style: text.labelMedium?.copyWith(color: color)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              child: Text(
                best.label(notation),
                style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (enharmonic != null)
              Text(
                '≡ $enharmonic (enarmónica)',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            if (layer != 0)
              Text(
                'Suena en ${best.transpose(layer).label(notation)} (${TransposeAdvice.label(layer)})',
                style: text.titleMedium?.copyWith(color: scheme.tertiary),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: estimate.confidence,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Text('${(estimate.confidence * 100).round()} %', style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            _Row(
              title: '≡ ${relative.label(notation)}',
              subtitle: 'relativa · mismas notas',
              probability: estimate.probabilityOf(relative),
            ),
            const Divider(height: 24),
            Text('Alternativas', style: text.labelLarge),
            const SizedBox(height: 6),
            for (final c in others)
              _Row(title: c.key.label(notation), probability: c.probability),
            const Spacer(),
            if (previousKey != null && previousKey != best)
              Row(
                children: [
                  Icon(Icons.trending_up, size: 18, color: scheme.tertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Modulación desde ${previousKey!.label(notation)}',
                      style: text.bodyMedium?.copyWith(color: scheme.tertiary),
                    ),
                  ),
                ],
              ),
            Text(
              '${estimate.observations} acordes analizados',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.probability, this.subtitle});

  final String title;
  final String? subtitle;
  final double probability;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                if (subtitle != null)
                  Text(subtitle!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            '${(probability * 100).round()} %',
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
