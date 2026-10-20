import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../settings.dart';
import 'responsive.dart';

/// Un acorde de la partitura: cifrado, grado o ambos según la preferencia.
class ChordCell extends StatelessWidget {
  const ChordCell({
    super.key,
    required this.chord,
    required this.musicKey,
    required this.settings,
    this.confidence,
    this.beats,
    this.edited = false,
    this.highlight = false,
    this.ring,
    this.onTap,
  });

  /// Borde de color (p. ej. para marcar el acorde que sigue).
  final Color? ring;

  /// Bajo esta seguridad el acorde se marca para revisarlo.
  static const double doubtfulBelow = 0.5;

  final Chord chord;
  final MusicKey? musicKey;
  final AppSettings settings;
  final double? confidence;

  /// Tiempos anotados a mano: se muestran como primas (D′, B′′).
  final int? beats;
  final bool edited;

  /// Alto de una celda (y de lo que va a su lado en la partitura).
  static double heightOf(BuildContext context) => context.isCompact ? 64 : 84;

  // Prima (′) y no apóstrofo: dos apóstrofos se leen como comillas.
  static String ticks(int? beats) => beats == null ? '' : '′' * beats;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fmt = settings.formatter;
    final key = musicKey;
    final name = fmt.format(chord, spell: key?.spell);
    final degree = key == null ? null : fmt.nashville(chord, key);
    final (main, secondary) = switch (settings.display) {
      ChordDisplay.chords => (name, null),
      ChordDisplay.degrees => (degree ?? name, degree == null ? null : name),
      ChordDisplay.both => (name, degree),
    };
    final doubtful = !edited && confidence != null && confidence! < doubtfulBelow;
    final fg = highlight ? scheme.onPrimaryContainer : scheme.onSurface;
    final compact = context.isCompact;

    return Material(
      color: highlight ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: ring == null ? BorderSide.none : BorderSide(color: ring!, width: 3),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minWidth: compact ? 66 : 104),
          height: heightOf(context),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          // Stack centrado (no Center) para que la celda mida lo que su texto.
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      text: main,
                      children: [
                        // Separadas para que dos primas no se lean como comillas.
                        if (beats != null)
                          TextSpan(
                            text: ticks(beats),
                            style: TextStyle(letterSpacing: 4, color: scheme.primary),
                          ),
                      ],
                    ),
                    style: TextStyle(fontSize: compact ? 21 : 28, fontWeight: FontWeight.w600, color: fg),
                  ),
                  if (secondary != null)
                    Text(
                      secondary,
                      style: TextStyle(fontSize: compact ? 12 : 14, color: fg.withValues(alpha: 0.7)),
                    ),
                ],
              ),
              if (doubtful)
                const Positioned(
                  top: 8,
                  right: 0,
                  child: Tooltip(
                    message: 'Lectura dudosa: toca para revisar',
                    child: Icon(Icons.circle, size: 10, color: Colors.amberAccent),
                  ),
                ),
              if (edited)
                Positioned(
                  top: 6,
                  right: 0,
                  child: Icon(Icons.edit, size: 12, color: fg.withValues(alpha: 0.6)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
