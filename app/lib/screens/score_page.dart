import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';
import '../score/score_player.dart';
import '../score/score_viewer.dart';
import '../storage/score_repository.dart';
import '../widgets/responsive.dart';

/// Una partitura abierta: verla, escucharla por el piano con el cursor
/// siguiendo las notas, y empezar desde cualquier nota tocándola.
class ScorePage extends StatefulWidget {
  const ScorePage({
    super.key,
    required this.score,
    required this.midi,
    this.repo,
    this.notation = Notation.american,
    this.autoplay = false,
  });

  final Score score;
  final MidiService midi;

  /// Para guardar los cambios (volver a escribir una grabación).
  final ScoreRepository? repo;
  final Notation notation;

  /// Empieza a sonar en cuanto se dibuja (para pruebas).
  final bool autoplay;

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {
  late Score score = widget.score;
  late ScoreTimeline timeline = ScoreTimeline.of(score);
  late final ScorePlayer player = ScorePlayer(widget.midi, timeline);
  bool rewriting = false;
  final ScoreViewerController viewer = ScoreViewerController();
  int zoom = 45;
  ViewerInfo? info;
  Map<String, dynamic>? bench;
  final Stopwatch _opened = Stopwatch()..start();
  int? _firstDrawMs;

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  /// Las dos manos, si la partitura es de piano: dos pentagramas de una
  /// parte, o dos partes de un pentagrama.
  late final List<(String, String, (int, int))> _hands = () {
    final parts = score.parts;
    if (parts.isNotEmpty && parts.first.staves >= 2) {
      return [('Der.', 'Mano derecha', (0, 1)), ('Izq.', 'Mano izquierda', (0, 2))];
    }
    if (parts.length == 2 && parts.every((p) => p.staves == 1)) {
      return [('Der.', 'Mano derecha', (0, 1)), ('Izq.', 'Mano izquierda', (1, 1))];
    }
    return <(String, String, (int, int))>[];
  }();

  void _toggleHand((int, int) key) => setState(() {
    player.muted.contains(key) ? player.muted.remove(key) : player.muted.add(key);
  });

  void _tapNote(String id) {
    final tick = timeline.firstTickOf(id);
    if (tick == null) return;
    player.seek(tick);
  }

  void _zoom(int delta) {
    setState(() => zoom = (zoom + delta).clamp(25, 80));
    viewer.setZoom(zoom);
  }

  static String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _showInfo() async {
    final i = info;
    final b = bench;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final s = score;
          final rec = s.recording;
          final lines = <String>[
            if (rec != null && rec.followedMetronome)
              'Grabada con metrónomo a ${rec.settings.bpm.round()} en ${rec.settings.time}'
                  '${rec.appliedLatencyMicros.abs() >= 1000 ? ', corrigiendo un ${rec.appliedLatencyMicros < 0 ? 'adelanto' : 'retraso'} de ${(rec.appliedLatencyMicros.abs() / 1000).round()} ms' : ''}',
            if (rec != null && !rec.followedMetronome)
              'Escrita a tu tempo (unas ${rec.playedQuarterBpm?.round()} negras por minuto); el metrónomo iba a '
                  '${rec.settings.bpm.round()} en ${rec.settings.time}',
            '${s.parts.length} ${s.parts.length == 1 ? 'parte' : 'partes'} · ${s.measures.length} compases · ${s.noteCount} notas',
            'Duración: ${_clock(timeline.duration)} (${timeline.order.length} compases con repeticiones)',
            if (s.source?.name != null) 'Archivo: ${s.source!.name}',
            if (i != null) ...[
              '',
              'Dibujo: ${i.pages} ${i.pages == 1 ? 'página' : 'páginas'}, grabado ${i.engraveMs} ms + pantalla ${i.domMs} ms',
              if (_firstDrawMs != null) 'Desde que se abrió: $_firstDrawMs ms',
              'Notas enlazadas: ${i.preserved + i.matched}/${i.total}'
                  '${i.matched > 0 ? ' (${i.matched} por posición)' : ''}',
            ],
            if (b != null) ...[
              '',
              'Desplazamiento: ${b['fps']} cuadros/s, ${b['slow']} lentos de ${b['frames']}, el peor ${b['worstMs']} ms',
            ],
          ];
          return AlertDialog(
            title: Text(s.title),
            content: SelectableText(lines.join('\n')),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  viewer.bench();
                },
                child: const Text('Medir fluidez'),
              ),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  /// Vuelve a escribir la partitura desde la grabación con otros ajustes.
  Future<void> _rewrite() async {
    final rec = score.recording;
    if (rec == null) return;
    final settings = await showDialog<TranscriptionSettings>(
      context: context,
      builder: (_) => _RewriteDialog(recording: rec, notation: widget.notation),
    );
    if (settings == null || !mounted) return;
    setState(() => rewriting = true);
    final next = await compute(_transcribe, (rec.take, settings, score.id, score.title));
    if (!mounted) return;
    setState(() => rewriting = false);
    if (next == null) return;
    next
      ..createdAt = score.createdAt
      ..composer = score.composer
      ..arranger = score.arranger;
    player.stop();
    await widget.repo?.save(next);
    setState(() {
      score = next;
      timeline = ScoreTimeline.of(next);
      player.timeline = timeline;
    });
    player.seek(0);
  }

  static Score? _transcribe((Take, TranscriptionSettings, String, String) a) =>
      PerformanceTranscriber.transcribe(a.$1, a.$2, id: a.$3, title: a.$4);

  Future<void> _pickSpeed() async {
    const options = [0.5, 0.6, 0.75, 0.9, 1.0, 1.1, 1.25];
    final picked = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final o in options)
              ListTile(
                leading: Icon(o == player.speed ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text('${(o * 100).round()} %'),
                subtitle: Text('${(timeline.bpmAt(player.tick) * o).round()} negras por minuto'),
                onTap: () => Navigator.of(context).pop(o),
              ),
          ],
        ),
      ),
    );
    if (picked != null) player.speed = picked;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final compact = context.isCompact;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ListenableBuilder(listenable: player, builder: (context, _) => _bar(context, scheme, compact)),
            const Divider(height: 1),
            Expanded(
              child: ScoreViewer(
                score: score,
                lit: player.lit,
                controller: viewer,
                zoom: zoom,
                onTapNote: _tapNote,
                onLoaded: (i) {
                  if (_firstDrawMs == null && widget.autoplay) player.play();
                  _firstDrawMs ??= _opened.elapsedMilliseconds;
                  debugPrint('Visor: ${i.data} · abierto en ${_opened.elapsedMilliseconds} ms');
                  setState(() => info = i);
                },
                onBench: (b) {
                  setState(() => bench = b);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Desplazamiento: ${b['fps']} cuadros/s, ${b['slow']} lentos, el peor ${b['worstMs']} ms',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, ColorScheme scheme, bool compact) {
    final text = Theme.of(context).textTheme;
    final hands = [
      for (final (label, tooltip, key) in _hands)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: FilterChip(
            visualDensity: VisualDensity.compact,
            label: Text(label),
            tooltip: '$tooltip: suena o calla',
            selected: !player.muted.contains(key),
            onSelected: (_) => _toggleHand(key),
          ),
        ),
    ];
    final noPiano = widget.midi.connected == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          const BackButton(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(score.title, style: text.titleMedium, overflow: TextOverflow.ellipsis),
                Text(
                  'Compás ${player.measureNumber} · ${_clock(player.position)} / ${_clock(player.duration)}'
                  '${noPiano ? ' · sin piano' : ''}',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(tooltip: 'Al principio', onPressed: player.stop, icon: const Icon(Icons.skip_previous)),
          IconButton.filled(
            tooltip: player.playing ? 'Pausa' : 'Reproducir',
            onPressed: player.toggle,
            icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
          ),
          TextButton(onPressed: _pickSpeed, child: Text('${(player.speed * 100).round()} %')),
          if (player.canPlayAsPlayed && !compact)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Escrita'), tooltip: 'A tempo, como está escrita'),
                  ButtonSegment(value: true, label: Text('Como la toqué'), tooltip: 'La grabación original'),
                ],
                selected: {player.asPlayed},
                onSelectionChanged: (s) => player.asPlayed = s.first,
              ),
            ),
          if (!compact) ...hands,
          if (!compact) ...[
            IconButton(tooltip: 'Más pequeña', onPressed: () => _zoom(-5), icon: const Icon(Icons.zoom_out)),
            IconButton(tooltip: 'Más grande', onPressed: () => _zoom(5), icon: const Icon(Icons.zoom_in)),
          ],
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'in' => _zoom(5),
              'out' => _zoom(-5),
              'hand0' => _toggleHand(_hands[0].$3),
              'hand1' => _toggleHand(_hands[1].$3),
              'asPlayed' => player.asPlayed = !player.asPlayed,
              'rewrite' => _rewrite(),
              _ => _showInfo(),
            },
            itemBuilder: (_) => [
              if (compact) ...[
                const PopupMenuItem(value: 'in', child: Text('Más grande')),
                const PopupMenuItem(value: 'out', child: Text('Más pequeña')),
                for (final (i, (_, name, key)) in _hands.indexed)
                  CheckedPopupMenuItem(value: 'hand$i', checked: !player.muted.contains(key), child: Text(name)),
                if (player.canPlayAsPlayed)
                  CheckedPopupMenuItem(
                    value: 'asPlayed',
                    checked: player.asPlayed,
                    child: const Text('Oír como la toqué'),
                  ),
              ],
              if (score.recording != null)
                PopupMenuItem(value: 'rewrite', enabled: !rewriting, child: const Text('Volver a escribir…')),
              const PopupMenuItem(value: 'info', child: Text('Información y rendimiento')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ajustes para volver a escribir una grabación.
class _RewriteDialog extends StatefulWidget {
  const _RewriteDialog({required this.recording, required this.notation});

  final ScoreRecording recording;
  final Notation notation;

  @override
  State<_RewriteDialog> createState() => _RewriteDialogState();
}

class _RewriteDialogState extends State<_RewriteDialog> {
  late final TranscriptionSettings original = widget.recording.settings;
  late TranscriptionSettings s = original;

  /// Pulso escrito respecto al tocado: ½, 1 o 2.
  late double factor = 1;

  static const _meters = [TimeSignature(2, 4), TimeSignature(3, 4), TimeSignature.common, TimeSignature(6, 8)];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rec = widget.recording;
    final auto = rec.appliedLatencyMicros - original.latencyMicros;
    final usesMetronome =
        s.tempoMode == TempoMode.metronome || (s.tempoMode == TempoMode.auto && rec.followedMetronome);
    return AlertDialog(
      title: const Text('Volver a escribir'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Se usa la misma grabación: cambia solo cómo se escribe.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text('Pulso', style: text.titleSmall),
              Text(
                rec.followedMetronome
                    ? 'Seguiste el metrónomo (${original.bpm.round()}).'
                    : 'No seguiste el metrónomo (${original.bpm.round()}): se escribió a tu tempo, '
                          'unas ${rec.playedQuarterBpm?.round()} negras por minuto.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              SegmentedButton<TempoMode>(
                segments: const [
                  ButtonSegment(value: TempoMode.auto, label: Text('Automático')),
                  ButtonSegment(value: TempoMode.metronome, label: Text('Metrónomo')),
                  ButtonSegment(value: TempoMode.player, label: Text('Mi tempo')),
                ],
                selected: {s.tempoMode},
                onSelectionChanged: (v) => setState(() => s = s.copyWith(tempoMode: v.first)),
              ),
              const SizedBox(height: 14),
              Text('Compás', style: text.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'auto', label: Text('Auto')),
                  for (final m in _meters) ButtonSegment(value: '$m', label: Text('$m')),
                ],
                selected: {s.meter?.toString() ?? 'auto'},
                onSelectionChanged: (v) => setState(() {
                  final m = _meters.where((m) => '$m' == v.first).firstOrNull;
                  s = m == null ? s.copyWith(clearMeter: true) : s.copyWith(meter: m);
                }),
              ),
              const SizedBox(height: 14),
              Text('Figuras más pequeñas', style: text.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, label: Text('Corcheas')),
                  ButtonSegment(value: 4, label: Text('Semicorcheas')),
                ],
                selected: {s.grid},
                onSelectionChanged: (v) => setState(() => s = s.copyWith(grid: v.first)),
              ),
              const SizedBox(height: 14),
              Text('Valor de las figuras', style: text.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0.5, label: Text('Más largas')),
                  ButtonSegment(value: 1, label: Text('Normal')),
                  ButtonSegment(value: 2, label: Text('Más cortas')),
                ],
                selected: {factor},
                onSelectionChanged: (v) => setState(() {
                  factor = v.first;
                  s = s.copyWith(bpm: original.bpm * factor);
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Detectar tresillos'),
                value: s.triplets,
                onChanged: (v) => setState(() => s = s.copyWith(triplets: v)),
              ),
              if (usesMetronome) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Corregir mi adelanto o retraso'),
                  subtitle: Text(
                    auto.abs() < 1000
                        ? 'Tocaste a tiempo con el metrónomo'
                        : 'Tocaste ${(auto.abs() / 1000).round()} ms ${auto < 0 ? 'antes' : 'después'} del metrónomo',
                  ),
                  value: s.autoLatency,
                  onChanged: (v) => setState(() => s = s.copyWith(autoLatency: v)),
                ),
                Row(
                  children: [
                    const Text('Ajuste fino'),
                    Expanded(
                      child: Slider(
                        min: -100,
                        max: 100,
                        divisions: 40,
                        value: (s.latencyMicros / 1000).clamp(-100, 100).toDouble(),
                        label: '${(s.latencyMicros / 1000).round()} ms',
                        onChanged: (v) => setState(() => s = s.copyWith(latencyMicros: (v * 1000).round())),
                      ),
                    ),
                    SizedBox(width: 64, child: Text('${(s.latencyMicros / 1000).round()} ms')),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Tonalidad'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButton<int?>(
                      isExpanded: true,
                      value: s.keyIndex,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('Automática')),
                        for (final k in MusicKey.all)
                          DropdownMenuItem<int?>(value: k.index, child: Text(k.label(widget.notation))),
                      ],
                      onChanged: (v) =>
                          setState(() => s = v == null ? s.copyWith(clearKey: true) : s.copyWith(keyIndex: v)),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Escribir el cifrado (acordes)'),
                value: s.chordSymbols,
                onChanged: (v) => setState(() => s = s.copyWith(chordSymbols: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Escribir dinámicas (p, mf, f)'),
                value: s.dynamics,
                onChanged: (v) => setState(() => s = s.copyWith(dynamics: v)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(context).pop(s), child: const Text('Escribir')),
      ],
    );
  }
}
