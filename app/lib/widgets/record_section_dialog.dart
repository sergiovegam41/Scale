import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../midi/midi_service.dart';
import '../settings.dart';
import 'chord_cell.dart';
import 'repeat_badge.dart';

/// Una sección tocada en el piano: una vuelta y cuántas veces se tocó (y,
/// si es nueva, cómo se llama).
class RecordedSection {
  const RecordedSection(this.pass, this.repeats, {this.label, this.kind = SectionKind.other});

  final List<ChordEvent> pass;
  final int repeats;
  final String? label;
  final SectionKind kind;
}

/// Regrabar una sección con el piano: se escriben los acordes mientras se
/// tocan. Si se tocó la misma vuelta varias veces, se propone ×N.
Future<RecordedSection?> recordSectionDialog(
  BuildContext context, {
  required String title,
  required ChordEngine piano,
  required MidiService midi,
  required AppSettings settings,
  MusicKey? musicKey,
  String action = 'Usar',
  String? replacing,
  String? newLabel,
}) =>
    showDialog<RecordedSection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecordDialog(
        title: title,
        piano: piano,
        midi: midi,
        settings: settings,
        musicKey: musicKey,
        action: action,
        replacing: replacing,
        newLabel: newLabel,
      ),
    );

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({
    required this.title,
    required this.piano,
    required this.midi,
    required this.settings,
    required this.musicKey,
    required this.action,
    required this.replacing,
    required this.newLabel,
  });

  final String title;
  final ChordEngine piano;
  final MidiService midi;
  final AppSettings settings;
  final MusicKey? musicKey;
  final String action;

  /// Cómo estaba la sección (texto), para comparar.
  final String? replacing;

  /// Sección nueva: se le puede poner nombre mientras se graba.
  final String? newLabel;

  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  late int _start = _now;

  /// Acordes que se quitaron tocándolos (por su inicio).
  final Set<int> _removed = {};

  /// Guardar como vueltas ×N (si se detectaron) o tal cual se tocó.
  bool groupRepeats = true;

  late final TextEditingController label = TextEditingController(text: widget.newLabel ?? '');
  SectionKind kind = SectionKind.other;

  int get _now => widget.midi.now.inMicroseconds;

  @override
  void initState() {
    super.initState();
    widget.piano.addListener(_onPiano);
  }

  @override
  void dispose() {
    widget.piano.removeListener(_onPiano);
    label.dispose();
    super.dispose();
  }

  void _onPiano() => setState(() {});

  void _restart() => setState(() {
        _start = _now;
        _removed.clear();
      });

  List<DetectedChord> get _captured => [
        for (final c in widget.piano.chords)
          if (c.startMicros >= _start && !_removed.contains(c.startMicros)) c,
      ];

  List<ChordEvent> _events(List<DetectedChord> captured) => [
        for (final (i, c) in captured.indexed)
          ChordEvent(
            chord: c.chord,
            confidence: c.confidence,
            alternatives: [for (final a in c.recognition.alternatives) a.chord],
            durationMicros: (c.endMicros ?? (i + 1 < captured.length ? captured[i + 1].startMicros : _now)) -
                c.startMicros,
          ),
      ];

  String _name(Chord c) => widget.settings.formatter.format(c, spell: widget.musicKey?.spell);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final captured = _captured;
    final (period, repeats) = ChordLine.repeatsOf([for (final c in captured) c.chord]);
    final grouped = groupRepeats && repeats > 1;
    final sounding = widget.piano.sounding;
    final connected = widget.midi.connected != null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.fiber_manual_record, color: connected ? const Color(0xFFE53935) : scheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              !connected
                  ? 'El piano no está conectado.'
                  : captured.isEmpty
                      ? 'Toca la sección en el piano. Los acordes se escriben mientras tocas.'
                      : sounding
                          ? 'Escuchando… cuando termines, pulsa "${widget.action}".'
                          : 'Sigue tocando o pulsa "${widget.action}". Toca un acorde de la lista para quitarlo.',
              style: text.bodyLarge?.copyWith(color: connected ? null : scheme.error),
            ),
            if (widget.newLabel != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final k in SectionKind.values.where((k) => k != SectionKind.other))
                    ChoiceChip(
                      label: Text(k.label),
                      selected: kind == k,
                      onSelected: (_) => setState(() {
                        kind = k;
                        label.text = k.label;
                      }),
                    ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: label,
                      decoration: const InputDecoration(labelText: 'Nombre', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.replacing != null) ...[
              const SizedBox(height: 6),
              Text('Antes: ${widget.replacing}', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 84, maxHeight: 300),
              child: SingleChildScrollView(
                reverse: true,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final (i, c) in captured.indexed) ...[
                      if (grouped && i > 0 && i % period == 0)
                        Text('${i ~/ period + 1}ª', style: TextStyle(color: scheme.onSurfaceVariant)),
                      Opacity(
                        opacity: grouped && i >= period ? 0.45 : 1,
                        child: ChordCell(
                          chord: c.chord,
                          musicKey: widget.musicKey,
                          settings: widget.settings,
                          confidence: c.confidence,
                          highlight: i == captured.length - 1 && sounding,
                          onTap: () => setState(() => _removed.add(c.startMicros)),
                        ),
                      ),
                    ],
                    if (captured.isEmpty)
                      Container(
                        height: ChordCell.heightOf(context),
                        alignment: Alignment.centerLeft,
                        child: Text('Esperando el primer acorde…', style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ),
            if (repeats > 1) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Switch(value: groupRepeats, onChanged: (v) => setState(() => groupRepeats = v)),
                  Text('Tocaste $repeats vueltas iguales: guardar ', style: text.bodyLarge),
                  Text(
                    captured.take(period).map((c) => _name(c.chord)).join(' '),
                    style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  RepeatBadge(repeats),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: captured.isEmpty ? null : _restart,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Empezar de nuevo'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: captured.isEmpty
              ? null
              : () {
                  final events = _events(captured);
                  final name = label.text.trim().isEmpty ? widget.newLabel : label.text.trim();
                  Navigator.pop(
                    context,
                    RecordedSection(
                      grouped ? events.sublist(0, period) : events,
                      grouped ? repeats : 1,
                      label: name,
                      kind: kind,
                    ),
                  );
                },
          child: Text(widget.action),
        ),
      ],
    );
  }
}
