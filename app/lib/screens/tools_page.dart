import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';
import '../play/chord_sound.dart';
import '../settings.dart';
import '../widgets/fifths_wheel.dart';
import '../widgets/responsive.dart';
import '../widgets/settings_sheet.dart';

/// Herramientas de teoría: la rueda de quintas y la tabla de grados.
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key, required this.midi, required this.settings});

  final MidiService midi;
  final AppSettings settings;

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final WheelController wheel = WheelController();
  late final ChordSound sound = ChordSound(widget.midi);
  int tool = 0;

  AppSettings get settings => widget.settings;

  @override
  void dispose() {
    sound.dispose();
    wheel.dispose();
    super.dispose();
  }

  void _play(Chord chord) {
    if (sound.play(chord)) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Conecta el piano para escuchar el acorde')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([settings, wheel]),
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    SegmentedButton<int>(
                      showSelectedIcon: !context.isCompact,
                      segments: [
                        ButtonSegment(
                          value: 0,
                          icon: const Icon(Icons.donut_large),
                          label: Text(context.isCompact ? 'Rueda' : 'Rueda de quintas'),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: const Icon(Icons.grid_on),
                          label: Text(context.isCompact ? 'Grados' : 'Tabla de grados'),
                        ),
                      ],
                      selected: {tool},
                      onSelectionChanged: (s) => setState(() => tool = s.first),
                    ),
                    const Spacer(),
                    if (context.isCompact)
                      PopupMenuButton<Object>(
                        onSelected: (v) => v is Notation ? settings.notation = v : showSettings(context, settings),
                        itemBuilder: (_) => [
                          CheckedPopupMenuItem<Object>(
                            value: Notation.latin,
                            checked: settings.notation == Notation.latin,
                            child: const Text('Do Re Mi'),
                          ),
                          CheckedPopupMenuItem<Object>(
                            value: Notation.american,
                            checked: settings.notation == Notation.american,
                            child: const Text('C D E'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<Object>(value: 'settings', child: Text('Configuración')),
                        ],
                      )
                    else ...[
                      SegmentedButton<Notation>(
                        segments: const [
                          ButtonSegment(value: Notation.latin, label: Text('Do Re Mi')),
                          ButtonSegment(value: Notation.american, label: Text('C D E')),
                        ],
                        selected: {settings.notation},
                        onSelectionChanged: (s) => settings.notation = s.first,
                      ),
                      const SizedBox(width: 4),
                      SettingsButton(settings: settings),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: tool == 0
                    ? _WheelTool(wheel: wheel, settings: settings, onPlay: _play)
                    : _DegreeTable(wheel: wheel, settings: settings, onPlay: _play),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nombre corto de un acorde para las herramientas (B°, C+, Am).
String chordLabel(Chord chord, Scale scale, AppSettings settings) {
  final root = scale.spell(chord.root).name(settings.notation);
  return switch (chord.quality) {
    ChordQuality.diminished => '$root°',
    ChordQuality.augmented => '$root+',
    ChordQuality.halfDiminished => '$rootø7',
    _ => settings.formatter.format(chord, spell: scale.spell),
  };
}

TextStyle? _heading(BuildContext context) => Theme.of(context).textTheme.labelLarge?.copyWith(
  letterSpacing: 1.2,
  color: Theme.of(context).colorScheme.onSurfaceVariant,
  fontWeight: FontWeight.w700,
);

// ── Rueda de quintas ─────────────────────────────────────────────────────

class _WheelTool extends StatefulWidget {
  const _WheelTool({required this.wheel, required this.settings, required this.onPlay});

  final WheelController wheel;
  final AppSettings settings;
  final ValueChanged<Chord> onPlay;

  @override
  State<_WheelTool> createState() => _WheelToolState();
}

class _WheelToolState extends State<_WheelTool> {
  final TextEditingController prog = TextEditingController(text: 'I V vi IV');

  static const examples = ['I V vi IV', 'ii V I', 'I vi IV V', 'I IV V I', 'vi IV I V', 'i iv V i', 'I ♭VII IV I'];

  WheelController get wheel => widget.wheel;
  AppSettings get settings => widget.settings;

  @override
  void dispose() {
    prog.dispose();
    super.dispose();
  }

  String _name(int pc, Scale scale) => scale.spell(pc).name(settings.notation);

  @override
  Widget build(BuildContext context) {
    final piece = wheel.piece;
    final scale = wheel.scale;
    final left = Scale(wheel.tonic + 5, piece.shape);
    final right = Scale(wheel.tonic + 7, piece.shape);

    final controls = _controls(piece, left, right);
    final panel = _panel(piece, scale);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => wheel.rotateBy(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => wheel.rotateBy(1),
      },
      child: Focus(
        autofocus: true,
        child: context.isCompact
            ? ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: FifthsWheel(controller: wheel, notation: settings.notation),
                  ),
                  ...controls,
                  const SizedBox(height: 16),
                  ...panel,
                ],
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 11,
                      child: Column(
                        children: [
                          Expanded(
                            child: FifthsWheel(controller: wheel, notation: settings.notation),
                          ),
                          ...controls,
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(flex: 10, child: ListView(children: panel)),
                  ],
                ),
              ),
      ),
    );
  }

  /// Botones para girar la pieza y la ayuda.
  List<Widget> _controls(WheelPiece piece, Scale left, Scale right) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        children: [
          OutlinedButton(onPressed: () => wheel.setTonic(wheel.tonic - 1), child: const Text('−½ tono')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: piece.color, foregroundColor: Colors.white),
            onPressed: () => wheel.rotateBy(-1),
            child: Text('↺ ${_name(left.tonic, left)}'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: piece.color, foregroundColor: Colors.white),
            onPressed: () => wheel.rotateBy(1),
            child: Text('${_name(right.tonic, right)} ↻'),
          ),
          OutlinedButton(onPressed: () => wheel.setTonic(wheel.tonic + 1), child: const Text('+½ tono')),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Arrastra la pieza para girarla o toca cualquier nota o acorde para llevar la tónica allí.',
        textAlign: TextAlign.center,
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ];
  }

  /// El panel: pieza, escala, acordes, progresión y leyenda.
  List<Widget> _panel(WheelPiece piece, Scale scale) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return [
      Text('PIEZA', style: _heading(context)),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final (i, p) in WheelPiece.all.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _pieceCard(p, i == wheel.pieceIndex, () => wheel.pieceIndex = i)),
          ],
        ],
      ),
      const SizedBox(height: 8),
      Text(piece.note, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 20),
      Text('ESCALA · ${_name(scale.tonic, scale)} ${piece.mode}'.toUpperCase(), style: _heading(context)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (i, pc) in scale.notes.indexed)
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: WheelColors.surface,
                border: Border.all(color: i == 0 ? piece.color : WheelColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(_name(pc, scale), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(scale.degreeLabels[i], style: text.labelSmall?.copyWith(color: piece.color)),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      Text.rich(
        TextSpan(
          text: 'ACORDES DE LA ESCALA',
          children: [
            TextSpan(
              text: '  · toca para escuchar',
              style: text.bodySmall?.copyWith(letterSpacing: 0, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        style: _heading(context),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final (i, ch) in wheel.chords().indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _chordChip(
                roman: ch.roman,
                name: chordLabel(ch.chord, scale, settings),
                color: piece.color,
                tonic: ch.degree == 0,
                tag: ch.cell == null ? 'fuera del círculo' : null,
                onTap: () => widget.onPlay(ch.chord),
              ),
            ),
          ],
          // La pentatónica tiene solo dos: que no se estiren.
          if (wheel.chords().length < 7) Spacer(flex: 7 - wheel.chords().length),
        ],
      ),
      const SizedBox(height: 20),
      Text('TRANSPORTAR UNA PROGRESIÓN POR GRADOS', style: _heading(context)),
      const SizedBox(height: 8),
      TextField(
        controller: prog,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 18, fontFamily: 'monospace', fontWeight: FontWeight.w600),
        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'I V vi IV'),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in examples)
            ActionChip(
              label: Text(e, style: const TextStyle(fontFamily: 'monospace')),
              onPressed: () => setState(() => prog.text = e),
            ),
        ],
      ),
      const SizedBox(height: 10),
      _progression(scale, piece),
      const SizedBox(height: 20),
      Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          _legend(WheelColors.ringN, 'Anillo exterior: notas y su grado (1, 2, ♭3…)'),
          _legend(WheelColors.ringM, 'Acordes mayores'),
          _legend(WheelColors.ringm, 'Menores'),
          _legend(WheelColors.ringd, 'Disminuidos'),
        ],
      ),
    ];
  }

  Widget _progression(Scale scale, WheelPiece piece) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final tokens = prog.text.trim().split(RegExp(r'[\s,|\-–]+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) {
      return Text(
        'Escribe grados separados por espacios, por ejemplo: I V vi IV',
        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    final inScale = scale.notes.toSet();
    final borrowed = scale.notes.length == 7 ? 'prestado' : 'fuera de la escala';
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final token in tokens)
          if (RomanProgression.chordOf(token, scale.tonic) case final chord?)
            _chordChip(
              roman: token,
              name: chordLabel(chord, scale, settings),
              color: piece.color,
              tag: chord.pitchClasses.every(inScale.contains) ? null : borrowed,
              width: 76,
              onTap: () => widget.onPlay(chord),
            )
          else
            _chordChip(roman: token, name: '?', color: piece.color, tag: 'no lo entiendo', width: 76),
      ],
    );
  }

  Widget _pieceCard(WheelPiece p, bool selected, VoidCallback onTap) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: WheelColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? p.color : WheelColors.line, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: context.isCompact
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  children: [
                    PieceThumbnail(p, size: 34),
                    const SizedBox(height: 4),
                    Text(
                      p.name,
                      textAlign: TextAlign.center,
                      style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    PieceThumbnail(p),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text(p.sub, style: text.labelSmall?.copyWith(color: WheelColors.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _chordChip({
    required String roman,
    required String name,
    required Color color,
    bool tonic = false,
    String? tag,
    double? width,
    VoidCallback? onTap,
  }) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Material(
        color: tonic ? color : WheelColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: tonic ? color : (tag == null ? WheelColors.line : WheelColors.muted.withValues(alpha: 0.5)),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              children: [
                Text(
                  roman,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: tonic ? Colors.white : color,
                  ),
                ),
                FittedBox(
                  child: Text(
                    name,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: tonic ? Colors.white : null),
                  ),
                ),
                if (tag != null) Text(tag, style: text.labelSmall?.copyWith(color: WheelColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: WheelColors.line),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WheelColors.muted)),
    ],
  );
}

// ── Tabla de grados ──────────────────────────────────────────────────────

enum _TableKind {
  major('Mayores', ScaleShape.ionian),
  minor('Menor natural', ScaleShape.aeolian),
  harmonic('Menor armónica', ScaleShape.harmonicMinor);

  const _TableKind(this.label, this.shape);

  final String label;
  final ScaleShape shape;
}

class _DegreeTable extends StatefulWidget {
  const _DegreeTable({required this.wheel, required this.settings, required this.onPlay});

  final WheelController wheel;
  final AppSettings settings;
  final ValueChanged<Chord> onPlay;

  @override
  State<_DegreeTable> createState() => _DegreeTableState();
}

class _DegreeTableState extends State<_DegreeTable> {
  _TableKind kind = _TableKind.major;
  bool sevenths = false;

  WheelController get wheel => widget.wheel;
  AppSettings get settings => widget.settings;

  /// Función armónica de cada grado: tónica, subdominante o dominante.
  static const _majorFunctions = ['T', 'S', 'T', 'S', 'D', 'T', 'D'];
  static const _minorFunctions = ['T', 'S', 'T', 'S', 'D', 'S', 'D'];

  /// Tónica de la fila [k]: las tonalidades en el orden del círculo de quintas.
  int _tonicOf(int k) => Scale.circleNote(k) + (kind == _TableKind.major ? 0 : 9);

  bool _isCurrent(int tonic) => switch (kind) {
    _TableKind.major => wheel.pieceIndex == 0 && wheel.tonic == tonic % 12,
    // La menor natural es la mayor relativa leída desde el vi.
    _TableKind.minor => wheel.pieceIndex == 0 && wheel.tonic == (tonic + 3) % 12,
    _TableKind.harmonic => wheel.pieceIndex == 1 && wheel.tonic == tonic % 12,
  };

  void _select(int tonic) {
    switch (kind) {
      case _TableKind.major:
        wheel
          ..pieceIndex = 0
          ..setTonic(tonic);
      case _TableKind.minor:
        wheel
          ..pieceIndex = 0
          ..setTonic(tonic + 3);
      case _TableKind.harmonic:
        wheel
          ..pieceIndex = 1
          ..setTonic(tonic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sample = Scale(kind == _TableKind.major ? 0 : 9, kind.shape);
    final romans = sevenths ? sample.seventhRomans : sample.romans;
    final functions = kind == _TableKind.major ? _majorFunctions : _minorFunctions;
    final accent = kind == _TableKind.harmonic ? WheelPiece.all[1].color : WheelPiece.all[0].color;

    Widget cell(Widget child, {Color? color, VoidCallback? onTap, bool header = false}) => Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: color ?? (header ? Colors.transparent : WheelColors.surface),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(height: 40, child: Center(child: child)),
        ),
      ),
    );

    // En el teléfono la tabla no cabe: se desplaza de lado.
    Widget wide(Widget table) => context.isCompact
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: 92 + 7 * 78, child: table),
          )
        : table;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_TableKind>(
                segments: [for (final k in _TableKind.values) ButtonSegment(value: k, label: Text(k.label))],
                selected: {kind},
                onSelectionChanged: (s) => setState(() => kind = s.first),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Con séptimas'),
                selected: sevenths,
                onSelected: (v) => setState(() => sevenths = v),
              ),

              Text(
                'T tónica · S subdominante · D dominante · toca un acorde para escucharlo',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: wide(
                Table(
                  columnWidths: context.isCompact
                      ? {0: const FixedColumnWidth(92), for (var c = 1; c <= 7; c++) c: const FixedColumnWidth(78)}
                      : const {0: FixedColumnWidth(150)},
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      children: [
                        cell(Text('Tonalidad', style: _heading(context)), header: true),
                        for (final (i, r) in romans.indexed)
                          cell(
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  r,
                                  style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, color: accent),
                                ),
                                Text(functions[i], style: text.labelSmall?.copyWith(color: WheelColors.muted)),
                              ],
                            ),
                            header: true,
                          ),
                      ],
                    ),
                    for (var k = 0; k < 12; k++)
                      () {
                        final tonic = _tonicOf(k);
                        final scale = Scale(tonic, kind.shape);
                        final key = scale.spellingKey;
                        final chords = sevenths ? scale.sevenths : scale.triads;
                        final current = _isCurrent(tonic);
                        final keyName = kind == _TableKind.major
                            ? key.name(settings.notation)
                            : '${scale.spell(tonic).name(settings.notation)}m';
                        final other = kind == _TableKind.major ? key.enharmonicName(settings.notation) : null;
                        return TableRow(
                          children: [
                            cell(
                              Text.rich(
                                TextSpan(
                                  text: keyName,
                                  children: [
                                    if (other != null)
                                      TextSpan(
                                        text: '  ≡ $other',
                                        style: text.bodySmall?.copyWith(color: WheelColors.muted),
                                      ),
                                  ],
                                ),
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: current ? Colors.white : null,
                                ),
                              ),
                              color: current ? accent : WheelColors.surface,
                              onTap: () => _select(tonic),
                            ),
                            for (final (i, chord) in chords.indexed)
                              cell(
                                Text(
                                  chordLabel(chord, scale, settings),
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
                                    color: current ? Colors.white : null,
                                  ),
                                ),
                                color: current ? accent.withValues(alpha: i == 0 ? 0.9 : 0.45) : null,
                                onTap: () => widget.onPlay(chord),
                              ),
                          ],
                        );
                      }(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
