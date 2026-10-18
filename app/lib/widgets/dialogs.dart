import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../settings.dart';

Future<String?> askText(
  BuildContext context, {
  required String title,
  required String initial,
  String confirm = 'Guardar',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(confirm),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String action = 'Eliminar'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Nombre y tipo de una sección.
Future<(String, SectionKind)?> askSection(BuildContext context, SectionDef section) {
  final controller = TextEditingController(text: section.label);
  var kind = section.kind;
  return showDialog<(String, SectionKind)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Nombre de la sección'),
        content: SizedBox(
          width: 420,
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
                        controller.text = k.label;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Nombre (p. ej. Verso 2)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final label = controller.text.trim();
              if (label.isNotEmpty) Navigator.pop(context, (label, kind));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

sealed class SectionChoice {}

class ExistingSection extends SectionChoice {
  ExistingSection(this.section);
  final SectionDef section;
}

class NewSection extends SectionChoice {
  NewSection(this.label, this.kind);
  final String label;
  final SectionKind kind;
}

/// Elegir qué sección empieza (o es) un tramo: la repetición de una que ya
/// existe ("el Coro otra vez") o una nueva.
Future<SectionChoice?> chooseSection(
  BuildContext context, {
  required String title,
  required List<SectionDef> existing,
  required String suggestedLabel,
}) {
  final controller = TextEditingController(text: suggestedLabel);
  var kind = SectionKind.other;
  return showDialog<SectionChoice>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final text = Theme.of(context).textTheme;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existing.isNotEmpty) ...[
                  Text('Repetición de', style: text.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in existing)
                        ActionChip(
                          label: Text(s.label),
                          onPressed: () => Navigator.pop(context, ExistingSection(s)),
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                ],
                Text('Sección nueva', style: text.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in SectionKind.values.where((k) => k != SectionKind.other))
                      ChoiceChip(
                        label: Text(k.label),
                        selected: kind == k,
                        onSelected: (selected) => setState(() {
                          kind = selected ? k : SectionKind.other;
                          controller.text = selected ? k.label : suggestedLabel;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Nombre (p. ej. Parte 3, Verso 2)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final label = controller.text.trim();
                if (label.isNotEmpty) Navigator.pop(context, NewSection(label, kind));
              },
              child: const Text('Crear sección'),
            ),
          ],
        );
      },
    ),
  );
}

sealed class ChordEdit {}

class ReplaceChord extends ChordEdit {
  ReplaceChord(this.chord);
  final Chord chord;
}

class DeleteChord extends ChordEdit {}

/// Tiempos anotados a mano (null = sin anotar).
class SetBeats extends ChordEdit {
  SetBeats(this.beats);
  final int? beats;
}

/// Corregir un acorde: alternativas detectadas, escribirlo o eliminarlo.
Future<ChordEdit?> editChord(
  BuildContext context, {
  required ChordEvent event,
  required MusicKey? musicKey,
  required AppSettings settings,
}) {
  final fmt = settings.formatter;
  final spell = musicKey?.spell;
  final controller = TextEditingController();
  String? error;
  return showModalBottomSheet<ChordEdit>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit(String text) {
          final chord = ChordParser.parse(text);
          if (chord == null) {
            setState(() => error = 'No reconozco "$text" como acorde');
          } else {
            Navigator.pop(context, ReplaceChord(chord));
          }
        }

        final text = Theme.of(context).textTheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Corregir acorde', style: text.titleLarge),
                  const SizedBox(width: 16),
                  Text(fmt.format(event.chord, spell: spell), style: text.headlineMedium),
                  if (event.confidence != null) ...[
                    const SizedBox(width: 12),
                    Text('seguridad ${(event.confidence! * 100).round()} %', style: text.bodyMedium),
                  ],
                ],
              ),
              if (event.alternatives.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Otras lecturas de las mismas notas', style: text.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final alt in event.alternatives)
                      ActionChip(
                        label: Text(fmt.format(alt, spell: spell), style: const TextStyle(fontSize: 20)),
                        onPressed: () => Navigator.pop(context, ReplaceChord(alt)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text('Tiempos (solo para anotar: D′ = 1, B′′ = 2)', style: text.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('—'),
                    selected: event.beats == null,
                    onSelected: (_) => Navigator.pop(context, SetBeats(null)),
                  ),
                  for (var b = 1; b <= 8; b++)
                    ChoiceChip(
                      label: Text('$b'),
                      selected: event.beats == b,
                      onSelected: (_) => Navigator.pop(context, SetBeats(b)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Escribir cifrado (D/F#, Sol7, Rem…)',
                  border: const OutlineInputBorder(),
                  errorText: error,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () => submit(controller.text),
                  ),
                ),
                onSubmitted: submit,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => Navigator.pop(context, DeleteChord()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar acorde'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Simulador de transporte: eliges la tonalidad en la que quieren cantar y te
/// dice cuántos semitonos poner en el TRANSPOSE del piano para seguir tocando
/// con tus figuras originales. Devuelve los semitonos elegidos.
Future<int?> pickTranspose(
  BuildContext context, {
  required MusicKey original,
  required int current,
  required int range,
  required Notation notation,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text('Transportar desde ${original.label(notation)}'),
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿En qué tonalidad la quieren? Pon esos semitonos en el TRANSPOSE del piano '
                'y sigue tocando con las figuras de ${original.name(notation)}.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var s = 0; s < 12; s++)
                    () {
                      final target = original.transpose(s);
                      final advice = TransposeAdvice.between(original, target, range: range);
                      final selected = current % 12 == s;
                      return Container(
                        width: 196,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: selected ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              target.label(notation) + (s == 0 ? ' (original)' : ''),
                              style: text.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                for (final option in advice.options)
                                  if (option == advice.recommended)
                                    FilledButton(
                                      onPressed: () => Navigator.pop(context, option),
                                      child: Text(TransposeAdvice.label(option)),
                                    )
                                  else
                                    OutlinedButton(
                                      onPressed: advice.fits(option)
                                          ? () => Navigator.pop(context, option)
                                          : null,
                                      child: Text(TransposeAdvice.label(option)),
                                    ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }(),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      );
    },
  );
}

/// Elegir la tonalidad a mano (o volver a la detectada).
Future<(MusicKey?,)?> pickKey(BuildContext context, {required MusicKey? current, required Notation notation}) {
  return showDialog<(MusicKey?,)>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Tonalidad de la canción'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final mode in Mode.values) ...[
              Text(mode == Mode.major ? 'Mayores' : 'Menores'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var tonic = 0; tonic < 12; tonic++)
                    ChoiceChip(
                      label: Text(MusicKey(tonic, mode).name(notation)),
                      selected: current == MusicKey(tonic, mode),
                      onSelected: (_) => Navigator.pop(context, (MusicKey(tonic, mode),)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, (null,)),
          child: const Text('Usar la detectada'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    ),
  );
}
