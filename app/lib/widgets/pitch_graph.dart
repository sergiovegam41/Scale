import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../voice/singer_engine.dart';

/// Gráfico en tiempo real de lo que se canta: la altura como una línea sobre
/// el espectrograma, con el eje en notas y las notas de la escala resaltadas.
class PitchGraph extends StatefulWidget {
  const PitchGraph({
    super.key,
    required this.engine,
    required this.notation,
    this.musicKey,
    this.showSpectrogram = true,
  });

  final SingerEngine engine;
  final Notation notation;

  /// Tonalidad en la que canta (se resaltan sus notas); null si aún no se sabe.
  final MusicKey? musicKey;
  final bool showSpectrogram;

  @override
  State<PitchGraph> createState() => _PitchGraphState();
}

class _PitchGraphState extends State<PitchGraph> {
  ui.Image? _image;
  int _imageVersion = -1;
  bool _decoding = false;

  /// Notas visibles (se acomodan solas a lo que se canta).
  double _low = 55, _high = 79;

  static final List<int> _palette = _buildPalette();

  SingerEngine get engine => widget.engine;

  @override
  void initState() {
    super.initState();
    engine.addListener(_onEngine);
    _followVoice();
    if (widget.showSpectrogram) _rebuildImage();
  }

  @override
  void didUpdateWidget(PitchGraph old) {
    super.didUpdateWidget(old);
    if (old.engine != engine) {
      old.engine.removeListener(_onEngine);
      engine.addListener(_onEngine);
    }
  }

  @override
  void dispose() {
    engine.removeListener(_onEngine);
    _image?.dispose();
    super.dispose();
  }

  void _onEngine() {
    _followVoice();
    if (widget.showSpectrogram) _rebuildImage();
    if (mounted) setState(() {});
  }

  /// El rango visible sigue a la voz: lo cantado en los últimos segundos con
  /// margen, al menos una octava y media.
  void _followVoice() {
    double? lo, hi;
    for (final p in engine.trace) {
      final m = p.midi;
      if (m == null) continue;
      lo = lo == null ? m : math.min(lo, m);
      hi = hi == null ? m : math.max(hi, m);
    }
    if (lo == null || hi == null) return;
    var low = lo.floorToDouble() - 3, high = hi.ceilToDouble() + 3;
    const minSpan = 18.0;
    if (high - low < minSpan) {
      final mid = (low + high) / 2;
      low = mid - minSpan / 2;
      high = mid + minSpan / 2;
    }
    final s = engine.spectrum;
    low = low.clamp(s.minMidi.toDouble(), s.maxMidi - minSpan);
    high = high.clamp(s.minMidi + minSpan, s.maxMidi.toDouble());
    _low += (low - _low) * 0.2;
    _high += (high - _high) * 0.2;
  }

  void _rebuildImage() {
    if (_decoding || engine.version == _imageVersion) return;
    final columns = engine.spectrogram;
    final width = SingerEngine.historyLength;
    final rows = engine.spectrum.rows;
    final pixels = Uint8List(width * rows * 4);
    final start = width - columns.length;
    for (var c = 0; c < columns.length; c++) {
      final column = columns[c];
      final x = start + c;
      for (var r = 0; r < rows; r++) {
        final v = column[r];
        if (v == 0) continue;
        final color = _palette[v];
        final i = ((rows - 1 - r) * width + x) * 4;
        pixels[i] = (color >> 16) & 0xFF;
        pixels[i + 1] = (color >> 8) & 0xFF;
        pixels[i + 2] = color & 0xFF;
        pixels[i + 3] = math.min(255, v * 3);
      }
    }
    _decoding = true;
    final version = engine.version;
    ui.decodeImageFromPixels(pixels, width, rows, ui.PixelFormat.rgba8888, (image) {
      _decoding = false;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _imageVersion = version;
      });
      if (engine.version != version) _rebuildImage();
    });
  }

  /// Paleta tipo "magma": negro → violeta → naranja → amarillo claro.
  static List<int> _buildPalette() {
    const stops = [
      (0.0, 0x000004),
      (0.25, 0x51127C),
      (0.5, 0xB73779),
      (0.75, 0xFC8961),
      (1.0, 0xFCFDBF),
    ];
    return List.generate(256, (i) {
      final t = i / 255;
      var k = 0;
      while (k < stops.length - 2 && t > stops[k + 1].$1) {
        k++;
      }
      final (t0, c0) = stops[k];
      final (t1, c1) = stops[k + 1];
      final f = ((t - t0) / (t1 - t0)).clamp(0.0, 1.0);
      int ch(int shift) => ((c0 >> shift & 0xFF) + ((c1 >> shift & 0xFF) - (c0 >> shift & 0xFF)) * f).round();
      return ch(16) << 16 | ch(8) << 8 | ch(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: _PitchPainter(
          trace: engine.trace,
          image: widget.showSpectrogram ? _image : null,
          spectrum: engine.spectrum,
          low: _low,
          high: _high,
          musicKey: widget.musicKey,
          notation: widget.notation,
          background: scheme.surfaceContainerLowest,
          text: scheme.onSurface,
          muted: scheme.onSurfaceVariant,
          tonic: scheme.primary,
          fontFamily: DefaultTextStyle.of(context).style.fontFamily,
          version: engine.version,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  _PitchPainter({
    required this.trace,
    required this.image,
    required this.spectrum,
    required this.low,
    required this.high,
    required this.musicKey,
    required this.notation,
    required this.background,
    required this.text,
    required this.muted,
    required this.tonic,
    required this.fontFamily,
    required this.version,
  });

  final List<PitchPoint> trace;
  final ui.Image? image;
  final NoteSpectrum spectrum;
  final double low, high;
  final MusicKey? musicKey;
  final Notation notation;
  final Color background, text, muted, tonic;
  final String? fontFamily;
  final int version;

  static const double gutter = 52;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(gutter, 0, size.width - 8, size.height);
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    double y(double midi) => plot.bottom - (midi - low) / (high - low) * plot.height;
    final rowHeight = plot.height / (high - low);
    final key = musicKey;

    // Franjas de la escala: las notas que pertenecen se aclaran, la tónica más.
    for (var m = low.floor(); m <= high.ceil(); m++) {
      final pc = m % 12;
      final inScale = key?.scale.contains(pc) ?? false;
      final isTonic = key != null && pc == key.tonic;
      if (!inScale) continue;
      canvas.drawRect(
        Rect.fromLTRB(plot.left, y(m + 0.5), plot.right, y(m - 0.5)),
        Paint()..color = isTonic ? tonic.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.045),
      );
    }

    // Espectrograma, recortado a las notas visibles.
    final img = image;
    if (img != null) {
      final rps = spectrum.rowsPerSemitone;
      final src = Rect.fromLTRB(
        0,
        (spectrum.maxMidi - high) * rps,
        img.width.toDouble(),
        (spectrum.maxMidi - low) * rps,
      );
      canvas.drawImageRect(img, src, plot, Paint()..filterQuality = FilterQuality.medium);
    }

    // Líneas y nombres de las notas.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var m = low.ceil(); m <= high.floor(); m++) {
      final pc = m % 12;
      final inScale = key?.scale.contains(pc) ?? false;
      final isTonic = key != null && pc == key.tonic;
      final natural = const [0, 2, 4, 5, 7, 9, 11].contains(pc);
      final ym = y(m.toDouble());
      if (pc == 0) {
        canvas.drawLine(Offset(plot.left, ym + rowHeight / 2), Offset(plot.right, ym + rowHeight / 2),
            Paint()..color = Colors.white.withValues(alpha: 0.18));
      }
      canvas.drawLine(Offset(plot.left, ym), Offset(plot.right, ym), line);
      // Con poco espacio, solo las de la escala (o las naturales si no hay tonalidad).
      if (rowHeight < 13 && !(key == null ? natural : inScale)) continue;
      if (ym < 8 || ym > plot.bottom - 8) continue; // no cortar nombres en los bordes
      final name = (key?.spell(pc) ?? SpelledNote.byDefault(pc)).name(notation);
      _label(
        canvas,
        '$name${m ~/ 12 - 1}',
        Offset(6, ym),
        TextStyle(
          fontSize: math.min(14, rowHeight * 0.9).clamp(9, 14).toDouble(),
          fontWeight: isTonic ? FontWeight.w800 : FontWeight.w500,
          color: isTonic ? tonic : (inScale || key == null ? text : muted.withValues(alpha: 0.6)),
        ),
      );
    }

    // La voz: una línea por tramo continuo; verde si está afinada.
    final step = plot.width / SingerEngine.historyLength;
    final n = trace.length;
    double x(int i) => plot.right - (n - 1 - i) * step;
    Offset? previous;
    double? previousMidi;
    for (var i = 0; i < n; i++) {
      final m = trace[i].midi;
      if (m == null || m < low - 1 || m > high + 1) {
        previous = null;
        continue;
      }
      final point = Offset(x(i), y(m));
      final cents = (m - m.round()).abs() * 100;
      final color = cents < 15 ? Colors.greenAccent : Colors.amberAccent;
      if (previous != null && previousMidi != null && (m - previousMidi).abs() < 1.5) {
        canvas.drawLine(
          previous,
          point,
          Paint()
            ..color = color
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawCircle(point, 2, Paint()..color = color);
      }
      previous = point;
      previousMidi = m;
    }

    // Lo último cantado: un punto con su nota.
    final last = n == 0 ? null : trace.last.midi;
    if (last != null && last >= low && last <= high) {
      final p = Offset(x(n - 1), y(last));
      canvas.drawCircle(p, 7, Paint()..color = Colors.white);
      final nearest = last.round();
      final name = (key?.spell(nearest % 12) ?? SpelledNote.byDefault(nearest % 12)).name(notation);
      _label(
        canvas,
        '$name${nearest ~/ 12 - 1}',
        Offset(p.dx - 60, p.dy - 22),
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
        background: Colors.black.withValues(alpha: 0.55),
      );
    }
  }

  void _label(Canvas canvas, String s, Offset at, TextStyle style, {Color? background}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style.copyWith(fontFamily: fontFamily)),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = Offset(at.dx, at.dy - tp.height / 2);
    if (background != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius((offset & tp.size).inflate(4), const Radius.circular(6)),
        Paint()..color = background,
      );
    }
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_PitchPainter old) =>
      old.version != version ||
      old.image != image ||
      old.low != low ||
      old.high != high ||
      old.musicKey != musicKey ||
      old.notation != notation;
}
