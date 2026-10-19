import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../settings.dart';
import 'chord_cell.dart';
import 'repeat_badge.dart';

/// Lo que se escribió en el editor de una sección.
class SectionEdit {
  const SectionEdit({required this.label, required this.kind, required this.note, required this.line});

  final String label;
  final SectionKind kind;
  final String note;
  final ChordLine line;
}

/// Una sección completa en un solo diálogo: nombre, acordes como texto
/// ("D' A' Bm'' x2"), nota de apoyo. Los acordes también se pueden tocar en
/// el piano para que se escriban solos.
Future<SectionEdit?> editSectionDialog(
  BuildContext context, {
  required String title,
  required AppSettings settings,
  String label = '',
  SectionKind kind = SectionKind.other,
  String? note,
  String chords = '',
  MusicKey? musicKey,
  ChordEngine? piano,
  String action = 'Guardar',
}) =>
    showDialog<SectionEdit>(
      context: context,
      builder: (_) => _SectionDialog(
        title: title,
        settings: settings,
        label: label,
        kind: kind,
        note: note ?? '',
        chords: chords,
        musicKey: musicKey,
        piano: piano,
        action: action,
      ),
    );

class _SectionDialog extends StatefulWidget {
  const _SectionDialog({
    required this.title,
    required this.settings,
    required this.label,
    required this.kind,
    required this.note,
    required this.chords,
    required this.musicKey,
    required this.piano,
    required this.action,
  });

  final String title;
  final AppSettings settings;
  final String label;
  final SectionKind kind;
  final String note;
  final String chords;
  final MusicKey? musicKey;
  final ChordEngine? piano;
  final String action;

  @override
  State<_SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<_SectionDialog> {
  late final TextEditingController label = TextEditingController(text: widget.label);
  late final TextEditingController note = TextEditingController(text: widget.note);
  late final TextEditingController chords = TextEditingController(text: widget.chords);
  late SectionKind kind = widget.kind;
  late ChordLine line = ChordLine.parse(widget.chords);

  /// Escribir solo lo que se toca en el piano.
  bool listening = false;
  int _seenAttacks = 0;
  String? _lastToken;

  ChordFormatter get fmt => widget.settings.formatter;

  @override
  void initState() {
    super.initState();
    final piano = widget.piano;
    if (piano != null) {
      _seenAttacks = piano.attacks;
      piano.addListener(_onPiano);
    }
    chords.addListener(() => setState(() => line = ChordLine.parse(chords.text)));
  }

  @override
  void dispose() {
    widget.piano?.removeListener(_onPiano);
    label.dispose();
    note.dispose();
    chords.dispose();
    super.dispose();
  }

  String _token(Chord chord, [MusicKey? key]) => fmt.format(chord, spell: (key ?? widget.musicKey)?.spell);

  void _onPiano() {
    final piano = widget.piano!;
    final current = piano.current;
    if (!listening || current == null) return;
    final token = _token(current.chord);
    if (piano.attacks != _seenAttacks) {
      _seenAttacks = piano.attacks;
      // Volver a atacar el mismo acorde es ritmo, no otro acorde.
      if (token == _lastToken && chords.text.trimRight().endsWith(token)) return;
      _append(token);
    } else if (_lastToken != null && token != _lastToken && chords.text.trimRight().endsWith(_lastToken!)) {
      // El mismo ataque se terminó de leer (Gsus → G): se corrige el último.
      final text = chords.text.trimRight();
      _setText(text.substring(0, text.length - _lastToken!.length) + token);
    } else {
      return;
    }
    _lastToken = token;
  }

  void _setText(String text) {
    chords.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void _append(String token) {
    final text = chords.text.trimRight();
    _setText(text.isEmpty ? token : '$text $token');
  }

  void _removeLast() {
    final tokens = chords.text.trim().split(RegExp(r'\s+'))..removeLast();
    _setText(tokens.join(' '));
    _lastToken = null;
  }

  /// Agrega o quita un tiempo (′) al último acorde.
  void _tick() {
    final text = chords.text.trimRight();
    if (text.isEmpty) return;
    _setText("$text'");
  }

  void _setRepeats(int repeats) {
    final tokens = chords.text.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty && !RegExp(r'^[x×]\d+$', caseSensitive: false).hasMatch(t)).toList();
    if (repeats > 1) tokens.add('x$repeats');
    _setText(tokens.join(' '));
  }

  bool get _valid => label.text.trim().isNotEmpty && line.isValid;

  void _save() {
    if (!_valid) return;
    Navigator.pop(
      context,
      SectionEdit(label: label.text.trim(), kind: kind, note: note.text.trim(), line: line),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Canción sin tonalidad todavía: se deduce de lo que se va escribiendo.
    final regions = widget.musicKey != null || line.chords.length < 3
        ? const <KeyRegion>[]
        : KeyAnalyzer.regions([for (final e in line.chords) e.chord]);
    final key = widget.musicKey ?? (regions.isEmpty ? null : regions.first.key);
    // Sin tonalidad: los acordes mayores y menores sin alteraciones.
    final keyboard = key?.diatonicChords ??
        [
          for (final q in [ChordQuality.major, ChordQuality.minor])
            for (final pc in const [0, 2, 4, 5, 7, 9, 11]) Chord(pc, q),
        ];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: label,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nombre (p. ej. Verso 2)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: chords,
                autofocus: widget.chords.isEmpty && widget.piano == null,
                style: const TextStyle(fontSize: 22),
                decoration: InputDecoration(
                  labelText: 'Acordes',
                  hintText: "G D/F# Em7 C",
                  helperText: "Separados por espacios · D'' = 2 tiempos · x2 = la parte se repite dos veces",
                  errorText: line.unknown.isEmpty ? null : 'No reconozco: ${line.unknown.join(', ')}',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              Text('Así queda', style: text.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final e in line.chords)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text.rich(
                        TextSpan(
                          text: _token(e.chord),
                          children: [
                            if (e.beats != null)
                              TextSpan(
                                text: ChordCell.ticks(e.beats),
                                style: TextStyle(letterSpacing: 3, color: scheme.primary),
                              ),
                          ],
                        ),
                        style: text.titleMedium,
                      ),
                    ),
                  if (line.repeats > 1) RepeatBadge(line.repeats),
                  if (line.chords.isEmpty)
                    Text('Todavía sin acordes', style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 16),
              // Teclado de acordes para escribir sin teclado.
              Text('Toca para agregar', style: text.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final c in keyboard)
                    ActionChip(label: Text(_token(c, key)), onPressed: () => _append(_token(c, key))),
                  ActionChip(
                    tooltip: 'Un tiempo más al último acorde',
                    label: const Text("+ tiempo ′"),
                    onPressed: _tick,
                  ),
                  for (final r in [1, 2, 3, 4])
                    ChoiceChip(
                      label: Text(r == 1 ? '×1' : '×$r'),
                      selected: line.repeats == r,
                      onSelected: (_) => _setRepeats(r),
                    ),
                  ActionChip(
                    tooltip: 'Borrar el último',
                    avatar: const Icon(Icons.backspace_outlined, size: 18),
                    label: const Text('Borrar'),
                    onPressed: chords.text.trim().isEmpty ? null : _removeLast,
                  ),
                ],
              ),
              if (widget.piano != null) ...[
                const SizedBox(height: 8),
                FilterChip(
                  avatar: Icon(Icons.piano, color: listening ? scheme.onTertiaryContainer : null),
                  selectedColor: scheme.tertiaryContainer,
                  selected: listening,
                  label: Text(listening ? 'Escribiendo lo que tocas en el piano…' : 'Escribir lo que toco en el piano'),
                  onSelected: (v) => setState(() {
                    listening = v;
                    _seenAttacks = widget.piano!.attacks;
                    _lastToken = null;
                  }),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: note,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota (aparece al tocar en vivo)',
                  hintText: 'Hacer adorno acá · Puente rápido · Cambio de ritmo…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _valid ? _save : null, child: Text(widget.action)),
      ],
    );
  }
}
