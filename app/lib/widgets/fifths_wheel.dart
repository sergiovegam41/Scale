import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:scale_core/scale_core.dart';

/// Una "pieza" que se coloca sobre el círculo: sus ventanas muestran las notas
/// de la escala y los acordes que le pertenecen.
class WheelPiece {
  const WheelPiece({
    required this.name,
    required this.sub,
    required this.mode,
    required this.shape,
    required this.color,
    required this.note,
    this.chordDegrees,
  });

  final String name;
  final String sub;

  /// Cómo se llama la escala ("mayor", "menor armónica").
  final String mode;
  final ScaleShape shape;
  final Color color;

  /// Explicación breve de la pieza.
  final String note;

  /// Acordes que muestra (grado, calidad) si no son las tríadas de la escala.
  final List<(int, ChordQuality)>? chordDegrees;

  static const List<WheelPiece> all = [
    WheelPiece(
      name: 'Mayor',
      sub: 'y sus 7 modos',
      mode: 'mayor',
      shape: ScaleShape.ionian,
      color: Color(0xFFC9730F),
      note: 'Dórico, frigio, lidio, mixolidio, menor natural (eólico) y locrio usan esta misma forma: solo '
          'cambia qué casilla tomas como centro. La menor natural es el vi; el dórico, el ii; el mixolidio, el V.',
    ),
    WheelPiece(
      name: 'Menor armónica',
      sub: '7ª elevada',
      mode: 'menor armónica',
      shape: ScaleShape.harmonicMinor,
      color: Color(0xFFB3303D),
      note: 'Forma propia: al subir la 7ª aparecen un V mayor y un vii° que resuelven fuerte a la tónica. '
          'El ♭III+ aumentado no existe en el círculo; lo ves solo en la lista.',
    ),
    WheelPiece(
      name: 'Pentatónica',
      sub: 'mayor y menor',
      mode: 'pentatónica',
      shape: ScaleShape.pentatonicMajor,
      color: Color(0xFF0E857A),
      note: 'Cinco quintas seguidas: la escala mayor sin el 4 ni el 7, que son las notas del semitono. La '
          'pentatónica menor es la misma forma leída desde el 6. Solo I y vi tienen sus tres notas dentro; '
          'sobre los otros acordes de la tonalidad se usa como melodía.',
      chordDegrees: [(0, ChordQuality.major), (5, ChordQuality.minor)],
    ),
  ];
}

/// Un acorde de la pieza: grado, cifrado romano, acorde y su casilla en el
/// círculo (null si no está, como el ♭III+).
class PieceChord {
  const PieceChord(this.degree, this.roman, this.chord, this.cell);

  final int degree;
  final String roman;
  final Chord chord;
  final (WheelRing, int)? cell;
}

enum WheelRing { notes, major, minor, diminished }

/// Estado compartido de las herramientas: la pieza y hacia dónde apunta.
class WheelController extends ChangeNotifier {
  int _piece = 0;

  /// Ángulo de la pieza en grados (múltiplo de 30 salvo al arrastrar).
  double angle = 0;

  WheelPiece get piece => WheelPiece.all[_piece];
  int get pieceIndex => _piece;
  set pieceIndex(int i) {
    _piece = i;
    notifyListeners();
  }

  /// Tónica: la nota en la que quedó la punta de la pieza.
  int get tonic => Scale.circleNote(((angle / 30).round()) % 12);

  Scale get scale => Scale(tonic, piece.shape);

  void setAngle(double a) {
    angle = a;
    notifyListeners();
  }

  /// Gira lo mínimo para que [pc] quede como tónica.
  void setTonic(int pc) {
    final pos = Scale.circlePosition(pc % 12);
    final d = ((pos * 30 - angle + 180) % 360 + 360) % 360 - 180;
    setAngle(angle + d);
  }

  void rotateBy(int steps) => setAngle((angle / 30).round() * 30.0 + steps * 30);

  /// Acordes de la pieza para la tónica actual.
  List<PieceChord> chords() => chordsFor(piece, tonic);

  static List<PieceChord> chordsFor(WheelPiece piece, int tonic) {
    final scale = Scale(tonic, piece.shape);
    final defs = piece.chordDegrees;
    if (defs != null) {
      const major = [0, 2, 4, 5, 7, 9, 11];
      return [
        for (final (d, q) in defs)
          () {
            final chord = Chord(tonic + major[d], q);
            return PieceChord(d, Scale.romanOf(d, major[d], q), chord, cellOf(chord, tonic));
          }(),
      ];
    }
    return [
      for (final (i, chord) in scale.triads.indexed) PieceChord(i, scale.romans[i], chord, cellOf(chord, tonic)),
    ];
  }

  /// Casilla de un acorde, relativa a la tónica arriba.
  static (WheelRing, int)? cellOf(Chord chord, int tonic) {
    final r = (chord.root - tonic) % 12;
    return switch (chord.quality) {
      ChordQuality.major => (WheelRing.major, Scale.circlePosition(r)),
      ChordQuality.minor => (WheelRing.minor, Scale.circlePosition(r + 3)),
      ChordQuality.diminished => (WheelRing.diminished, Scale.circlePosition(r + 1)),
      _ => null,
    };
  }
}

/// Paleta oscura de la rueda (la misma de la página de referencia).
class WheelColors {
  static const surface = Color(0xFF171C23);
  static const ink = Color(0xFFE4E9EE);
  static const muted = Color(0xFF8C97A3);
  static const line = Color(0xFF2C343E);
  static const ringN = Color(0xFF141920);
  static const ringM = Color(0xFF1E242C);
  static const ringm = Color(0xFF191F26);
  static const ringd = Color(0xFF141920);
  static const veil = Color(0xFF0A0D11);
}

/// El círculo de quintas con la pieza encima. Se gira arrastrando; tocar una
/// nota o acorde lleva la tónica ahí.
class FifthsWheel extends StatefulWidget {
  const FifthsWheel({super.key, required this.controller, required this.notation});

  final WheelController controller;
  final Notation notation;

  @override
  State<FifthsWheel> createState() => _FifthsWheelState();
}

class _FifthsWheelState extends State<FifthsWheel> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  double _shown = 0;
  bool _dragging = false;
  double _dragStart = 0, _dragAcc = 0, _lastAngle = 0;

  WheelController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _shown = c.angle;
    c.addListener(_onChange);
  }

  @override
  void didUpdateWidget(FifthsWheel old) {
    super.didUpdateWidget(old);
    if (old.controller != c) {
      old.controller.removeListener(_onChange);
      c.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _ticker.dispose();
    super.dispose();
  }

  void _onChange() {
    if (_dragging) {
      setState(() => _shown = c.angle);
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _tick(Duration _) {
    final d = c.angle - _shown;
    setState(() => _shown = d.abs() < 0.05 ? c.angle : _shown + d * 0.2);
    if (_shown == c.angle) _ticker.stop();
  }

  /// Punto de la pantalla → coordenadas de diseño (0..600, centro en 300).
  Offset _design(Offset local, Size size) {
    final scale = size.shortestSide / 608;
    final origin = Offset((size.width - size.shortestSide) / 2, (size.height - size.shortestSide) / 2);
    return (local - origin) / scale - const Offset(4, 4);
  }

  static double _angleOf(Offset v) => (math.atan2(v.dx, -v.dy) * 180 / math.pi + 360) % 360;

  void _tap(Offset local, Size size) {
    final v = _design(local, size) - const Offset(300, 300);
    final r = v.distance;
    if (r < 90 || r > 300) return;
    final k = (_angleOf(v) / 30).round() % 12;
    final base = Scale.circleNote(k);
    final pc = r >= 250
        ? base
        : r >= 194
            ? base
            : r >= 142
                ? base + 9
                : r >= 96
                    ? base + 11
                    : null;
    if (pc != null) c.setTonic(pc);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size.square(box.biggest.shortestSide);
        return Center(
          child: GestureDetector(
            onTapUp: (d) => _tap(d.localPosition, size),
            onPanStart: (d) {
              final v = _design(d.localPosition, size) - const Offset(300, 300);
              _dragging = true;
              _dragStart = c.angle;
              _dragAcc = 0;
              _lastAngle = _angleOf(v);
              _ticker.stop();
            },
            onPanUpdate: (d) {
              final a = _angleOf(_design(d.localPosition, size) - const Offset(300, 300));
              _dragAcc += ((a - _lastAngle + 180) % 360 + 360) % 360 - 180;
              _lastAngle = a;
              c.setAngle(_dragStart + _dragAcc);
            },
            onPanEnd: (_) {
              _dragging = false;
              c.setAngle((c.angle / 30).round() * 30.0);
            },
            child: CustomPaint(
              size: size,
              painter: _WheelPainter(
                angle: _shown,
                tonic: c.tonic,
                piece: c.piece,
                notation: widget.notation,
                fontFamily: DefaultTextStyle.of(context).style.fontFamily,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.angle,
    required this.tonic,
    required this.piece,
    required this.notation,
    required this.fontFamily,
  });

  final double angle;
  final int tonic;
  final WheelPiece piece;
  final Notation notation;
  final String? fontFamily;

  static const double cx = 300, hub = 90;
  static const Map<WheelRing, (double, double)> rings = {
    WheelRing.notes: (250, 292),
    WheelRing.major: (194, 246),
    WheelRing.minor: (142, 194),
    WheelRing.diminished: (96, 142),
  };

  /// Centro de la casilla, desplazamiento del nombre (una y dos líneas) y de
  /// la píldora del grado, como en la página de referencia.
  static const Map<WheelRing, (double, double, (double, double), double)> layout = {
    WheelRing.notes: (271, -9, (-16, -6), 10),
    WheelRing.major: (220, -10, (-17, -4), 13),
    WheelRing.minor: (168, -9, (-15, -4), 12),
    WheelRing.diminished: (119, -8, (-14, -5), 10),
  };

  static const List<List<SpelledNote>> _majorNames = [
    [SpelledNote(0, 0)], [SpelledNote(4, 0)], [SpelledNote(1, 0)], [SpelledNote(5, 0)],
    [SpelledNote(2, 0)], [SpelledNote(6, 0)], [SpelledNote(3, 1), SpelledNote(4, -1)], [SpelledNote(1, -1)],
    [SpelledNote(5, -1)], [SpelledNote(2, -1)], [SpelledNote(6, -1)], [SpelledNote(3, 0)],
  ];
  static const List<List<SpelledNote>> _minorNames = [
    [SpelledNote(5, 0)], [SpelledNote(2, 0)], [SpelledNote(6, 0)], [SpelledNote(3, 1)],
    [SpelledNote(0, 1)], [SpelledNote(4, 1)], [SpelledNote(1, 1), SpelledNote(2, -1)], [SpelledNote(6, -1)],
    [SpelledNote(3, 0)], [SpelledNote(0, 0)], [SpelledNote(4, 0)], [SpelledNote(1, 0)],
  ];
  static const List<List<SpelledNote>> _dimNames = [
    [SpelledNote(6, 0)], [SpelledNote(3, 1)], [SpelledNote(0, 1)], [SpelledNote(4, 1)],
    [SpelledNote(1, 1)], [SpelledNote(5, 1)], [SpelledNote(2, 1), SpelledNote(3, 0)], [SpelledNote(0, 0)],
    [SpelledNote(4, 0)], [SpelledNote(1, 0)], [SpelledNote(5, 0)], [SpelledNote(2, 0)],
  ];

  static Offset pt(double r, double deg) {
    final a = deg * math.pi / 180;
    return Offset(cx + r * math.sin(a), cx - r * math.cos(a));
  }

  static Path sector(double r1, double r2, double centerDeg) {
    final a0 = (centerDeg - 15 - 90) * math.pi / 180;
    const sweep = 30 * math.pi / 180;
    return Path()
      ..arcTo(Rect.fromCircle(center: const Offset(cx, cx), radius: r2), a0, sweep, true)
      ..arcTo(Rect.fromCircle(center: const Offset(cx, cx), radius: r1), a0 + sweep, -sweep, false)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 608;
    canvas
      ..save()
      ..scale(scale)
      ..translate(4, 4);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = WheelColors.line
      ..strokeWidth = 1;
    const fills = {
      WheelRing.notes: WheelColors.ringN,
      WheelRing.major: WheelColors.ringM,
      WheelRing.minor: WheelColors.ringm,
      WheelRing.diminished: WheelColors.ringd,
    };

    // El círculo impreso.
    for (var k = 0; k < 12; k++) {
      for (final ring in WheelRing.values) {
        final (r1, r2) = rings[ring]!;
        final path = sector(r1, r2, k * 30);
        canvas
          ..drawPath(path, Paint()..color = fills[ring]!)
          ..drawPath(path, line);
      }
    }
    canvas
      ..drawCircle(const Offset(cx, cx), hub, Paint()..color = WheelColors.surface)
      ..drawCircle(const Offset(cx, cx), hub, line);

    // Las ventanas de la pieza (dibujada con la tónica arriba y girada).
    final chords = WheelController.chordsFor(piece, tonic);
    final scale7 = Scale(tonic, piece.shape);
    final windows = <(WheelRing, int, bool, String, String)>[]; // anillo, casilla, tónica, nombre, píldora
    for (final (i, pc) in scale7.notes.indexed) {
      windows.add((
        WheelRing.notes,
        Scale.circlePosition(pc - tonic),
        i == 0,
        scale7.spell(pc).name(notation),
        scale7.degreeLabels[i],
      ));
    }
    for (final ch in chords) {
      final cell = ch.cell;
      if (cell == null) continue;
      windows.add((cell.$1, cell.$2, ch.degree == 0, _chordName(ch.chord, scale7), ch.roman));
    }

    final rotation = Matrix4.translationValues(cx, cx, 0)
      ..rotateZ(angle * math.pi / 180)
      ..translateByDouble(-cx, -cx, 0, 1);
    var holes = Path()..addOval(Rect.fromCircle(center: const Offset(cx, cx), radius: hub + 2));
    final windowPaths = <(Path, bool)>[];
    for (final (ring, off, isTonic, _, _) in windows) {
      final (r1, r2) = rings[ring]!;
      final p = sector(r1, r2, off * 30.0).transform(rotation.storage);
      windowPaths.add((p, isTonic));
      holes = Path.combine(PathOperation.union, holes, p);
    }
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: const Offset(cx, cx), radius: 292)),
      holes,
    );

    // Nombres impresos (tapados dentro de las ventanas) y el velo.
    canvas
      ..save()
      ..clipPath(outside);
    for (var k = 0; k < 12; k++) {
      _staticLabel(canvas, [for (final n in _majorNames[k]) n.name(notation)], WheelRing.notes, k);
      _staticLabel(canvas, [for (final n in _majorNames[k]) n.name(notation)], WheelRing.major, k);
      _staticLabel(canvas, [for (final n in _minorNames[k]) '${n.name(notation)}m'], WheelRing.minor, k);
      _staticLabel(canvas, [for (final n in _dimNames[k]) '${n.name(notation)}°'], WheelRing.diminished, k);
    }
    canvas
      ..drawPath(outside, Paint()..color = WheelColors.veil.withValues(alpha: 0.8))
      ..restore();

    // La pieza: borde, punta y ventanas.
    final color = piece.color;
    canvas.drawCircle(
      const Offset(cx, cx),
      293.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 3,
    );
    final handle = Path()
      ..moveTo(pt(294, 0).dx, pt(294, 0).dy)
      ..lineTo(pt(303, -2.2).dx, pt(303, -2.2).dy)
      ..lineTo(pt(303, 2.2).dx, pt(303, 2.2).dy)
      ..close();
    canvas.drawPath(handle.transform(rotation.storage), Paint()..color = color);
    for (final (p, isTonic) in windowPaths) {
      canvas
        ..drawPath(p, Paint()..color = color.withValues(alpha: isTonic ? 0.32 : 0.14))
        ..drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = color
            ..strokeWidth = 2.5,
        );
    }

    // Nombre y grado de cada ventana, siempre derechos.
    for (final (ring, off, isTonic, name, pill) in windows) {
      final (rc, one, _, pillOff) = layout[ring]!;
      final center = pt(rc, off * 30.0 + angle);
      final size = switch (ring) {
        WheelRing.notes => 12.0,
        WheelRing.major => 17.0,
        WheelRing.minor => 14.0,
        WheelRing.diminished => 12.0,
      };
      _text(canvas, name, center + Offset(0, one), TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: WheelColors.ink));
      final pillCenter = center + Offset(0, pillOff);
      final style = TextStyle(
        fontSize: ring == WheelRing.notes ? (pill.length > 1 ? 9.0 : 10.5) : 12,
        fontWeight: FontWeight.w700,
        color: isTonic ? Colors.white : color,
      );
      final fill = Paint()..color = isTonic ? color : WheelColors.surface;
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 1.5;
      if (ring == WheelRing.notes) {
        canvas
          ..drawCircle(pillCenter, 9, fill)
          ..drawCircle(pillCenter, 9, stroke);
      } else {
        final w = 10 + pill.length * 6.8;
        final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: pillCenter, width: w, height: 17), const Radius.circular(8.5));
        canvas
          ..drawRRect(rect, fill)
          ..drawRRect(rect, stroke);
      }
      _text(canvas, pill, pillCenter, style);
    }

    // Centro: la tónica y la escala.
    final tonicChord = chords.where((ch) => ch.degree == 0).firstOrNull;
    final suffix = tonicChord?.chord.quality == ChordQuality.minor ? 'm' : '';
    final key = scale7.spell(tonic).name(notation) + suffix;
    _text(canvas, 'TÓNICA', const Offset(cx, cx - 38),
        const TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w500, color: WheelColors.muted));
    _text(canvas, key, const Offset(cx, cx - 4),
        TextStyle(fontSize: key.length > 4 ? 32 : 40, fontWeight: FontWeight.w800, color: WheelColors.ink));
    _text(canvas, piece.mode, const Offset(cx, cx + 32), TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color));
    canvas.restore();
  }

  String _chordName(Chord chord, Scale scale) {
    final root = scale.spell(chord.root).name(notation);
    return switch (chord.quality) {
      ChordQuality.minor => '${root}m',
      ChordQuality.diminished => '$root°',
      ChordQuality.augmented => '$root+',
      _ => root,
    };
  }

  void _staticLabel(Canvas canvas, List<String> parts, WheelRing ring, int k) {
    final (rc, one, two, _) = layout[ring]!;
    final center = pt(rc, k * 30.0);
    final double size = switch (ring) {
      WheelRing.notes => parts.length > 1 ? 9.5 : 12,
      WheelRing.major => parts.length > 1 ? 13 : 17,
      WheelRing.minor => parts.length > 1 ? 11 : 14,
      WheelRing.diminished => parts.length > 1 ? 9.5 : 12,
    };
    final dim = ring == WheelRing.notes || ring == WheelRing.diminished;
    final style = TextStyle(
      fontSize: size,
      fontWeight: ring == WheelRing.major ? FontWeight.w600 : FontWeight.w500,
      color: dim ? WheelColors.muted : WheelColors.ink,
    );
    if (parts.length == 1) {
      _text(canvas, parts.first, center + Offset(0, one), style);
    } else {
      _text(canvas, parts[0], center + Offset(0, two.$1), style);
      _text(canvas, parts[1], center + Offset(0, two.$2), style);
    }
  }

  void _text(Canvas canvas, String s, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style.copyWith(fontFamily: fontFamily)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.angle != angle || old.tonic != tonic || old.piece != piece || old.notation != notation;
}

/// Miniatura de una pieza (para elegirla).
class PieceThumbnail extends StatelessWidget {
  const PieceThumbnail(this.piece, {super.key, this.size = 42});

  final WheelPiece piece;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _ThumbPainter(piece));
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.piece);

  final WheelPiece piece;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 600);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = WheelColors.line
      ..strokeWidth = 6;
    for (var k = 0; k < 12; k++) {
      for (final (r1, r2) in _WheelPainter.rings.values) {
        canvas.drawPath(_WheelPainter.sector(r1, r2, k * 30.0), line);
      }
    }
    final scale = Scale(0, piece.shape);
    for (final (i, pc) in scale.notes.indexed) {
      final (r1, r2) = _WheelPainter.rings[WheelRing.notes]!;
      canvas.drawPath(
        _WheelPainter.sector(r1, r2, Scale.circlePosition(pc) * 30.0),
        Paint()..color = piece.color.withValues(alpha: i == 0 ? 1 : 0.55),
      );
    }
    for (final ch in WheelController.chordsFor(piece, 0)) {
      final cell = ch.cell;
      if (cell == null) continue;
      final (r1, r2) = _WheelPainter.rings[cell.$1]!;
      canvas.drawPath(
        _WheelPainter.sector(r1, r2, cell.$2 * 30.0),
        Paint()..color = piece.color.withValues(alpha: ch.degree == 0 ? 1 : 0.55),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.piece != piece;
}
