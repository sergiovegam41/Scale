import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../ai/ai_client.dart';
import '../ai/groq_client.dart';
import '../settings.dart';

/// Botón ⚙ que abre la configuración de visualización.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Configuración',
        onPressed: () => showSettings(context, settings),
        icon: const Icon(Icons.settings_outlined),
      );
}

/// Campo de texto de la configuración. Si es [secret] (API key), va oculto
/// con un botón para mostrarlo. Se guarda solo en este dispositivo.
class _SettingField extends StatefulWidget {
  const _SettingField({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.helper,
    this.hint,
    this.secret = false,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final String? helper;
  final String? hint;
  final bool secret;

  @override
  State<_SettingField> createState() => _SettingFieldState();
}

class _SettingFieldState extends State<_SettingField> {
  late final TextEditingController controller = TextEditingController(text: widget.initial);
  bool visible = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: widget.secret && !visible,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 3,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
        suffixIcon: widget.secret
            ? IconButton(
                tooltip: visible ? 'Ocultar' : 'Mostrar',
                onPressed: () => setState(() => visible = !visible),
                icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
              )
            : null,
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// Servicio de IA para importar y su API key (cada servicio guarda la suya).
class _AiSettings extends StatelessWidget {
  const _AiSettings({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final provider = settings.aiProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<AiProvider>(
          segments: [
            for (final p in AiProvider.values)
              ButtonSegment(
                value: p,
                label: Text(p.label),
                icon: settings.apiKeyFor(p).isEmpty ? null : const Icon(Icons.key, size: 16),
              ),
          ],
          selected: {provider},
          onSelectionChanged: (s) => settings.aiProvider = s.first,
        ),
        const SizedBox(height: 6),
        Text(
          switch (provider) {
            AiProvider.claude => 'Claude lee mejor las fotos y capturas difíciles.',
            AiProvider.groq => 'Groq es muy rápido y tiene un plan gratis. Con fotos acepta hasta '
                '${GroqClient.maxImages} imágenes por mensaje.',
          },
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _SettingField(
          key: ValueKey('key-${provider.name}'),
          label: 'API key de ${provider.company}',
          helper: 'Se guarda solo en este dispositivo. Se saca en ${provider.console}.',
          initial: settings.apiKeyFor(provider),
          secret: true,
          onChanged: (v) => settings.setApiKey(provider, v),
        ),
        if (provider == AiProvider.groq)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Modelos de Groq (avanzado)'),
            subtitle: const Text('Déjalos vacíos para usar los recomendados.'),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              _SettingField(
                label: 'Modelo para texto',
                hint: GroqClient.defaultTextModel,
                initial: settings.groqTextModel,
                onChanged: (v) => settings.groqTextModel = v,
              ),
              const SizedBox(height: 12),
              _SettingField(
                label: 'Modelo para fotos (visión)',
                hint: GroqClient.defaultVisionModel,
                helper: 'Debe aceptar imágenes. Groq cambia sus modelos seguido: '
                    'si deja de funcionar, revisa console.groq.com/docs/vision.',
                initial: settings.groqVisionModel,
                onChanged: (v) => settings.groqVisionModel = v,
              ),
            ],
          ),
      ],
    );
  }
}

Future<void> showSettings(BuildContext context, AppSettings settings) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        return SafeArea(
          child: SingleChildScrollView(
            // Deja espacio al teclado al escribir la API key.
            padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configuración', style: text.titleLarge),
                const SizedBox(height: 20),
                Text('Notación', style: text.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<Notation>(
                  segments: const [
                    ButtonSegment(value: Notation.american, label: Text('Americana (C D E)')),
                    ButtonSegment(value: Notation.latin, label: Text('Latina (Do Re Mi)')),
                  ],
                  selected: {settings.notation},
                  onSelectionChanged: (s) => settings.notation = s.first,
                ),
                const SizedBox(height: 20),
                Text('En las canciones mostrar', style: text.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<ChordDisplay>(
                  segments: const [
                    ButtonSegment(value: ChordDisplay.chords, label: Text('Acordes')),
                    ButtonSegment(value: ChordDisplay.degrees, label: Text('Grados (1 4 5 6m)')),
                    ButtonSegment(value: ChordDisplay.both, label: Text('Ambos')),
                  ],
                  selected: {settings.display},
                  onSelectionChanged: (s) => settings.display = s.first,
                ),
                const Divider(height: 40),
                Text('Piano', style: text.titleMedium),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mi piano envía el MIDI ya transpuesto'),
                  subtitle: const Text(
                    'Con el TRANSPOSE del piano activo, llegan las notas que suenan. '
                    'La app resta la capa para mostrarte tus figuras originales.',
                  ),
                  value: settings.pianoSendsTransposed,
                  onChanged: (v) => settings.pianoSendsTransposed = v,
                ),
                const SizedBox(height: 8),
                Text('Rango del transpose del piano', style: text.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 6, label: Text('±6 semitonos')),
                    ButtonSegment(value: 12, label: Text('±12 semitonos')),
                  ],
                  selected: {settings.transposeRange},
                  onSelectionChanged: (s) => settings.transposeRange = s.first,
                ),
                const Divider(height: 40),
                Text('Importar con IA', style: text.titleMedium),
                const SizedBox(height: 8),
                _AiSettings(settings: settings),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Si falta la API key del servicio de IA elegido, lo dice y ofrece abrir
/// la configuración. Devuelve si ya hay key.
Future<bool> ensureApiKey(BuildContext context, AppSettings settings) async {
  if (settings.hasApiKey) return true;
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Falta la API key'),
      content: Text(
        'Para importar con IA escribe tu API key de ${settings.aiProvider.company} '
        '(o elige otro servicio) en ⚙ Configuración. Se guarda solo en este dispositivo.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abrir ⚙')),
      ],
    ),
  );
  if (open == true && context.mounted) await showSettings(context, settings);
  return settings.hasApiKey;
}
