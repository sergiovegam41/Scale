import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

/// Glifos SMuFL de Bravura que usa el pentagrama.
abstract final class Smufl {
  static const family = 'Bravura';
  static const brace = '';
  static const gClef = '';
  static const fClef = '';
  static const noteheadWhole = '';
  static const noteheadBlack = '';
  static const flat = '';
  static const natural = '';
  static const sharp = '';
  static const doubleSharp = '';
  static const doubleFlat = '';

  static String accidental(int a) => switch (a) {
    -2 => doubleFlat,
    -1 => flat,
    1 => sharp,
    2 => doubleSharp,
    _ => natural,
  };

  /// Ancho en espacios de pentagrama (metadatos de Bravura).
  static double accidentalWidth(int a) => switch (a) {
    -2 => 1.644,
    -1 => 0.904,
    1 => 0.996,
    2 => 0.988,
    _ => 0.672,
  };
}

/// Un acorde en pentagrama doble (claves de sol y fa), con armadura.
///
/// Las notas se escriben según el acorde reconocido y la tonalidad: la 3ª de
/// E es G#, en F la armadura ya pone el Bb.
class GrandStaff extends StatelessWidget {
  const GrandStaff({super.key, required this.notes, this.chord, this.musicKey, this.dimmed = false});

  /// Notas MIDI.
  final Iterable<int> notes;
  final Chord? chord;
  final MusicKey? musicKey;

  /// Atenuado (el acorde ya no suena).
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final staff = ChordStaff.layout(notes, chord: chord, key: musicKey);
    return RepaintBoundary(
      child: CustomPaint(
        painter: GrandStaffPainter(
          staff: staff,
          rootPc: chord?.root,
          ink: scheme.onSurface.withValues(alpha: dimmed ? 0.55 : 1),
          lines: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          root: scheme.primary.withValues(alpha: dimmed ? 0.6 : 1),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class GrandStaffPainter extends CustomPainter {
  GrandStaffPainter({required this.staff, required this.ink, required this.lines, required this.root, this.rootPc});

  final ChordStaff staff;
  final int? rootPc;
  final Color ink;
  final Color lines;
  final Color root;

  // Medidas en espacios de pentagrama.
  static const double _gap = 6; // entre la línea inferior de sol y la superior de fa
  static const double _noteW = 1.688;
  static const double _accColW = 1.2;
  static const double _ledgerExt = 0.4;

  @override
  void paint(Canvas canvas, Size size) {
    final treble = staff.on(StaffClef.treble);
    final bass = staff.on(StaffClef.bass);
    final maxTreble = treble.fold(8, (m, n) => math.max(m, n.step));
    final minBass = bass.fold(0, (m, n) => math.min(m, n.step));
    final top = math.max(3.0, (maxTreble - 8) / 2 + 1.5);
    final bottom = math.max(3.0, -minBass / 2 + 1.5);
    final height = top + 4 + _gap + 4 + bottom;

    final sigCount = staff.signature.fifths.abs();
    final sigW = sigCount * 1.15;
    final accCols = math.max(2, staff.accidentalColumns);
    const braceW = 1.0;
    const clefX = braceW + 0.25 + 0.7;
    final sigX = clefX + 2.7 + 0.6;
    final accX = sigX + sigW + (sigCount > 0 ? 0.8 : 0.2);
    final noteX = accX + accCols * _accColW + 0.3;
    final width = noteX + _noteW * 2 + 2.2;

    final sp = math.min(size.height / height, size.width / width);
    if (sp <= 0) return;
    final ox = (size.width - width * sp) / 2;
    final oy = (size.height - height * sp) / 2;
    final trebleTop = top;
    final bassTop = top + 4 + _gap;

    double x(double spaces) => ox + spaces * sp;
    double yOf(StaffClef clef, num step) =>
        oy + ((clef == StaffClef.treble ? trebleTop : bassTop) + (8 - step) / 2) * sp;

    final linePaint = Paint()
      ..color = lines
      ..strokeWidth = math.max(1, 0.13 * sp);
    final staffLeft = x(braceW + 0.25);
    final staffRight = x(width);

    // Líneas de los dos pentagramas y la barra que los une.
    for (final clef in StaffClef.values) {
      for (var s = 0; s <= 8; s += 2) {
        final y = yOf(clef, s);
        canvas.drawLine(Offset(staffLeft, y), Offset(staffRight, y), linePaint);
      }
    }
    final systemTop = yOf(StaffClef.treble, 8);
    final systemBottom = yOf(StaffClef.bass, 0);
    canvas.drawLine(
      Offset(staffLeft, systemTop),
      Offset(staffLeft, systemBottom),
      Paint()
        ..color = lines
        ..strokeWidth = math.max(1, 0.16 * sp),
    );

    // Llave: su glifo mide 4 espacios con el tamaño normal; se estira al sistema.
    final span = (systemBottom - systemTop) / sp;
    _glyph(canvas, Smufl.brace, x(0.05), systemBottom, 4 * sp * span / 4, lines);

    // Claves: la de sol apoya en la 2ª línea (Sol4), la de fa en la 4ª (Fa3).
    _glyph(canvas, Smufl.gClef, x(clefX), yOf(StaffClef.treble, 2), 4 * sp, ink);
    _glyph(canvas, Smufl.fClef, x(clefX), yOf(StaffClef.bass, 6), 4 * sp, ink);

    // Armadura.
    final sigGlyph = staff.signature.fifths >= 0 ? Smufl.sharp : Smufl.flat;
    for (final clef in StaffClef.values) {
      for (final (i, step) in staff.signature.steps(clef).indexed) {
        _glyph(canvas, sigGlyph, x(sigX + i * 1.15), yOf(clef, step), 4 * sp, ink);
      }
    }

    // Notas: líneas adicionales, alteraciones y cabezas.
    final ledger = Paint()
      ..color = ink
      ..strokeWidth = math.max(1, 0.16 * sp);
    for (final n in staff.notes) {
      final headX = noteX + (n.shifted ? _noteW : 0);
      final color = n.midi % 12 == rootPc ? root : ink;
      for (final s in _ledgerSteps(n.step)) {
        final y = yOf(n.clef, s);
        canvas.drawLine(Offset(x(headX - _ledgerExt), y), Offset(x(headX + _noteW + _ledgerExt), y), ledger);
      }
      final acc = n.accidental;
      if (acc != null) {
        final right = noteX - 0.25 - n.accidentalColumn * _accColW;
        _glyph(
          canvas,
          Smufl.accidental(acc),
          x(right - Smufl.accidentalWidth(acc)),
          yOf(n.clef, n.step),
          4 * sp,
          color,
        );
      }
      _glyph(canvas, Smufl.noteheadWhole, x(headX), yOf(n.clef, n.step), 4 * sp, color);
    }
  }

  /// Líneas adicionales que necesita una nota en la posición [step].
  static Iterable<int> _ledgerSteps(int step) sync* {
    for (var s = -2; s >= step; s -= 2) {
      yield s;
    }
    for (var s = 10; s <= step; s += 2) {
      yield s;
    }
  }

  /// Dibuja [glyph] con su línea base en [baseline] (así se anclan los
  /// glifos SMuFL: la cabeza centrada en su línea o espacio).
  static void _glyph(Canvas canvas, String glyph, double left, double baseline, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(fontFamily: Smufl.family, fontSize: fontSize, color: color, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(canvas, Offset(left, baseline - base));
    tp.dispose();
  }

  @override
  bool shouldRepaint(GrandStaffPainter old) =>
      old.rootPc != rootPc ||
      old.ink != ink ||
      old.lines != lines ||
      old.root != root ||
      old.staff.signature != staff.signature ||
      !_sameNotes(old.staff.notes, staff.notes);

  static bool _sameNotes(List<StaffNote> a, List<StaffNote> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].midi != b[i].midi || a[i].spelling != b[i].spelling || a[i].clef != b[i].clef) return false;
    }
    return true;
  }
}
