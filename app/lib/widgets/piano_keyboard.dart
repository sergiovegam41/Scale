import 'package:flutter/material.dart';

/// Teclado de 88 teclas (A0–C8) que resalta notas presionadas y sostenidas.
class PianoKeyboard extends StatelessWidget {
  const PianoKeyboard({
    super.key,
    required this.held,
    required this.sustained,
    this.lowest = 21,
    this.highest = 108,
  });

  final Map<int, int> held;
  final Set<int> sustained;
  final int lowest;
  final int highest;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PianoPainter(
        held: held,
        sustained: sustained,
        lowest: lowest,
        highest: highest,
        accent: const Color(0xFF3D5AFE),
        labelColor: Colors.black54,
      ),
      size: Size.infinite,
    );
  }
}

bool isBlackKey(int note) => const [1, 3, 6, 8, 10].contains(note % 12);

class _PianoPainter extends CustomPainter {
  _PianoPainter({
    required this.held,
    required this.sustained,
    required this.lowest,
    required this.highest,
    required this.accent,
    required this.labelColor,
  });

  final Map<int, int> held;
  final Set<int> sustained;
  final int lowest;
  final int highest;
  final Color accent;
  final Color labelColor;

  Color? _highlight(int note) {
    final velocity = held[note];
    if (velocity != null) {
      return accent.withValues(alpha: 0.75 + 0.25 * (velocity / 127));
    }
    if (sustained.contains(note)) return accent.withValues(alpha: 0.35);
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final whiteCount = [
      for (var n = lowest; n <= highest; n++)
        if (!isBlackKey(n)) n,
    ].length;
    final whiteWidth = size.width / whiteCount;
    final blackWidth = whiteWidth * 0.62;
    final blackHeight = size.height * 0.62;
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final blacks = <(Rect, int)>[];
    var whiteIndex = 0;
    for (var n = lowest; n <= highest; n++) {
      if (isBlackKey(n)) {
        final x = whiteIndex * whiteWidth - blackWidth / 2;
        blacks.add((Rect.fromLTWH(x, 0, blackWidth, blackHeight), n));
        continue;
      }
      final rect = Rect.fromLTWH(whiteIndex * whiteWidth, 0, whiteWidth, size.height);
      canvas.drawRect(rect, Paint()..color = Colors.white);
      final hl = _highlight(n);
      if (hl != null) canvas.drawRect(rect, Paint()..color = hl);
      canvas.drawRect(rect, border);
      if (n % 12 == 0) _label(canvas, 'C${n ~/ 12 - 1}', rect);
      whiteIndex++;
    }
    for (final (rect, n) in blacks) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFF1B1B1F));
      final hl = _highlight(n);
      if (hl != null) canvas.drawRect(rect, Paint()..color = hl);
    }
  }

  void _label(Canvas canvas, String text, Rect key) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: labelColor, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: key.width);
    tp.paint(canvas, Offset(key.center.dx - tp.width / 2, key.bottom - tp.height - 4));
  }

  @override
  bool shouldRepaint(_PianoPainter old) => true;
}
