import 'package:flutter/material.dart';

/// Color de las vueltas (×N): resalta sobre el tema oscuro.
const Color repeatColor = Color(0xFFFFC94D);

/// Etiqueta "×N" para las vueltas seguidas de una parte.
class RepeatBadge extends StatelessWidget {
  const RepeatBadge(this.repeats, {super.key, this.fontSize = 16});

  final int repeats;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.45, vertical: fontSize * 0.1),
      decoration: BoxDecoration(
        color: repeatColor,
        borderRadius: BorderRadius.circular(fontSize),
      ),
      child: Text(
        '×$repeats',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF2B2000),
        ),
      ),
    );
  }
}
