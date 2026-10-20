import 'package:flutter/material.dart';
import 'package:record/record.dart' show InputDevice;
import 'package:scale_core/scale_core.dart';

import '../settings.dart';
import '../storage/song_repository.dart';
import '../voice/singer_engine.dart';
import '../widgets/key_panel.dart';
import '../widgets/pitch_graph.dart';
import '../widgets/responsive.dart';
import '../widgets/settings_sheet.dart';

/// Tonalidad del cantante: lo escucha por el micrófono, estima en qué
/// tonalidad canta y dice cuánto transportar una canción para él.
class SingerPage extends StatefulWidget {
  const SingerPage({super.key, required this.engine, required this.repo, required this.settings});

  final SingerEngine engine;
  final SongRepository repo;
  final AppSettings settings;

  @override
  State<SingerPage> createState() => _SingerPageState();
}

class _SingerPageState extends State<SingerPage> {
  String? songId;
  bool showSpectrogram = true;

  SingerEngine get engine => widget.engine;
  AppSettings get settings => widget.settings;

  String _note(int midi) => '${SpelledNote.byDefault(midi).name(settings.notation)}${midi ~/ 12 - 1}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([engine, settings, widget.repo]),
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: context.isCompact
              ? _compact()
              : Column(
                  children: [
                    _topBar(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _nowSinging()),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 360,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: KeyPanel(
                                      estimate: engine.key,
                                      notation: settings.notation,
                                      emptyMessage:
                                          'Pídele que cante la canción (o una parte) y aquí verás su tonalidad.',
                                      unit: 'notas',
                                      showScale: true,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _compare(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Teléfono: todo en una columna que se desplaza; el gráfico con alto fijo.
  Widget _compact() {
    const red = Color(0xFFE53935);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: engine.listening ? red : scheme.surfaceContainerHighest,
                  foregroundColor: engine.listening ? Colors.white : scheme.onSurface,
                ),
                onPressed: engine.listening ? engine.stop : engine.start,
                icon: Icon(engine.listening ? Icons.stop : Icons.mic, color: engine.listening ? Colors.white : red),
                label: Text(engine.listening ? 'Detener' : 'Escuchar'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  engine.error ??
                      (engine.device == null ? 'Micrófono de la tablet' : SingerEngine.deviceName(engine.device!)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: engine.error != null ? scheme.error : scheme.onSurfaceVariant),
                ),
              ),
              PopupMenuButton<Object>(
                onOpened: engine.refreshDevices,
                onSelected: (v) => switch (v) {
                  InputDevice d => engine.selectDevice(d),
                  'spectrogram' => setState(() => showSpectrogram = !showSpectrogram),
                  'reset' => engine.reset(),
                  _ => showSettings(context, settings),
                },
                itemBuilder: (_) => [
                  for (final d in engine.devices)
                    CheckedPopupMenuItem<Object>(
                      value: d,
                      checked: d.id == engine.device?.id,
                      child: Text(SingerEngine.deviceName(d)),
                    ),
                  if (engine.devices.isNotEmpty) const PopupMenuDivider(),
                  CheckedPopupMenuItem<Object>(
                    value: 'spectrogram',
                    checked: showSpectrogram,
                    child: const Text('Espectrograma'),
                  ),
                  const PopupMenuItem<Object>(value: 'reset', child: Text('Empezar de nuevo')),
                  const PopupMenuItem<Object>(value: 'settings', child: Text('Configuración')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              SizedBox(height: (context.screen.height * 0.62).clamp(300, 520).toDouble(), child: _nowSinging()),
              const SizedBox(height: 8),
              KeySummary(
                estimate: engine.key,
                notation: settings.notation,
                emptyMessage: 'Tonalidad: pídele que cante y aquí aparece',
                panel: (_) => KeyPanel(
                  estimate: engine.key,
                  notation: settings.notation,
                  emptyMessage: 'Pídele que cante la canción (o una parte) y aquí verás su tonalidad.',
                  unit: 'notas',
                  showScale: true,
                ),
              ),
              const SizedBox(height: 8),
              _compare(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topBar() {
    const red = Color(0xFFE53935);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Text(
            engine.listening ? '● Escuchando' : 'Tonalidad del cantante',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: engine.listening ? red : scheme.onSurface),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: engine.listening ? red : scheme.surfaceContainerHighest,
              foregroundColor: engine.listening ? Colors.white : scheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            onPressed: engine.listening ? engine.stop : engine.start,
            icon: Icon(engine.listening ? Icons.stop : Icons.mic, color: engine.listening ? Colors.white : red),
            label: Text(engine.listening ? 'Detener' : 'Escuchar', style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          if (engine.error != null)
            Expanded(
              child: Text(
                engine.error!,
                style: TextStyle(color: scheme.error),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          PopupMenuButton<InputDevice>(
            tooltip: 'Entrada de audio',
            onOpened: engine.refreshDevices,
            onSelected: engine.selectDevice,
            itemBuilder: (_) => [
              for (final d in engine.devices)
                CheckedPopupMenuItem(
                  value: d,
                  checked: d.id == engine.device?.id,
                  child: Text(SingerEngine.deviceName(d)),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.mic_none, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    engine.device == null ? 'Micrófono de la tablet' : SingerEngine.deviceName(engine.device!),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Espectrograma'),
            selected: showSpectrogram,
            onSelected: (v) => setState(() => showSpectrogram = v),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Empezar de nuevo',
            onPressed: engine.reset,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          SettingsButton(settings: settings),
        ],
      ),
    );
  }

  Widget _nowSinging() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final midi = engine.currentMidi;
    final nearest = midi?.round();
    final cents = midi == null ? 0.0 : (midi - nearest!) * 100;
    final range = engine.range;
    final key = engine.key.isEmpty ? null : engine.key.key;

    return Card(
      child: Padding(
        padding: context.isCompact ? const EdgeInsets.all(12) : const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: context.isCompact ? 104 : 170,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ahora canta', style: text.titleMedium),
                      FittedBox(
                        child: Text(
                          nearest == null ? '—' : _note(nearest),
                          style: text.displayLarge?.copyWith(
                            fontSize: context.isCompact ? 48 : 72,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Afinación respecto de la nota más cercana (±50 ¢).
                      SizedBox(
                        width: context.isCompact ? 150 : 240,
                        height: 14,
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            Center(child: Container(width: 2, color: scheme.onSurfaceVariant)),
                            if (midi != null)
                              Align(
                                alignment: Alignment((cents / 50).clamp(-1, 1).toDouble(), 0),
                                child: Container(
                                  width: 14,
                                  decoration: BoxDecoration(
                                    color: cents.abs() < 15 ? Colors.greenAccent : Colors.amberAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        midi == null
                            ? (engine.listening ? 'Esperando la voz…' : 'Pulsa Escuchar')
                            : cents.abs() < 15
                            ? 'Afinado (${cents >= 0 ? '+' : ''}${cents.round()} ¢)'
                            : '${cents > 0 ? 'Alto' : 'Bajo'} (${cents >= 0 ? '+' : ''}${cents.round()} ¢)',
                        style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (range != null) Text('Rango: ${_note(range.$1)} – ${_note(range.$2)}', style: text.bodyLarge),
                    ],
                  ),
                ),
                if (key != null && !context.isCompact)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Canta en', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        Text(
                          key.label(settings.notation),
                          style: text.headlineSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: PitchGraph(
                engine: engine,
                notation: settings.notation,
                musicKey: key,
                showSpectrogram: showSpectrogram,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'La línea es la nota que canta (verde: afinada). Las franjas claras son las notas de su escala; '
              'la tónica, en color. Funciona mejor a capela o con el piano bajo.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// Comparar con una canción guardada: cuánto transportarla para el cantante.
  Widget _compare() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final songs = widget.repo.songs.where((s) => s.key != null).toList();
    final song = songs.where((s) => s.id == songId).firstOrNull;
    final estimate = engine.key;

    Widget? advice;
    if (song != null && !estimate.isEmpty) {
      final songKey = song.key!;
      // Si detectó la relativa (mismas notas), se compara en el mismo modo.
      var sung = estimate.key;
      if (sung.mode != songKey.mode) sung = sung.relative;
      final a = TransposeAdvice.between(songKey, sung, range: settings.transposeRange);
      final other = a.options.where((o) => o != a.recommended).firstOrNull;
      advice = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'La canción está en ${songKey.label(settings.notation)}; '
            'canta en ${sung.label(settings.notation)}.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            a.recommended == 0
                ? 'No hace falta transportar.'
                : 'TRANSPOSE ${TransposeAdvice.label(a.recommended)}'
                      '${other == null ? '' : '  (o ${TransposeAdvice.label(other)})'}',
            style: text.titleLarge?.copyWith(color: scheme.tertiary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: song.transpose == a.recommended
                ? null
                : () async {
                    song.transpose = a.recommended;
                    song.showOriginal = false;
                    await widget.repo.save(song);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"${song.title}" quedó con TRANSPOSE ${TransposeAdvice.label(a.recommended)}'),
                      ),
                    );
                  },
            child: Text(
              song.transpose == a.recommended
                  ? 'Ya está guardado en la canción'
                  : 'Guardar ${TransposeAdvice.label(a.recommended)} en la canción',
            ),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Comparar con una canción', style: text.titleMedium),
            const SizedBox(height: 6),
            DropdownButton<String>(
              isExpanded: true,
              value: song?.id,
              hint: Text(songs.isEmpty ? 'No hay canciones con tonalidad' : 'Elegir canción'),
              items: [
                for (final s in songs)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text('${s.title} · ${s.key!.name(settings.notation)}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() => songId = id),
            ),
            ?advice,
          ],
        ),
      ),
    );
  }
}
