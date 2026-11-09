import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';
import '../score/score_player.dart';
import '../score/score_viewer.dart';
import '../widgets/responsive.dart';

/// Una partitura abierta: verla, escucharla por el piano con el cursor
/// siguiendo las notas, y empezar desde cualquier nota tocándola.
class ScorePage extends StatefulWidget {
  const ScorePage({super.key, required this.score, required this.midi, this.autoplay = false});

  final Score score;
  final MidiService midi;

  /// Empieza a sonar en cuanto se dibuja (para pruebas).
  final bool autoplay;

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {
  late final ScoreTimeline timeline = ScoreTimeline.of(widget.score);
  late final ScorePlayer player = ScorePlayer(widget.midi, timeline);
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
    final parts = widget.score.parts;
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
          final s = widget.score;
          final lines = <String>[
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
            ListenableBuilder(
              listenable: player,
              builder: (context, _) => _bar(context, scheme, compact),
            ),
            const Divider(height: 1),
            Expanded(
              child: ScoreViewer(
                score: widget.score,
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
                    SnackBar(content: Text('Desplazamiento: ${b['fps']} cuadros/s, ${b['slow']} lentos, el peor ${b['worstMs']} ms')),
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
                Text(widget.score.title, style: text.titleMedium, overflow: TextOverflow.ellipsis),
                Text(
                  'Compás ${player.measureNumber} · ${_clock(player.position)} / ${_clock(player.duration)}'
                  '${noPiano ? ' · sin piano' : ''}',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Al principio',
            onPressed: player.stop,
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton.filled(
            tooltip: player.playing ? 'Pausa' : 'Reproducir',
            onPressed: player.toggle,
            icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
          ),
          TextButton(
            onPressed: _pickSpeed,
            child: Text('${(player.speed * 100).round()} %'),
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
              _ => _showInfo(),
            },
            itemBuilder: (_) => [
              if (compact) ...[
                const PopupMenuItem(value: 'in', child: Text('Más grande')),
                const PopupMenuItem(value: 'out', child: Text('Más pequeña')),
                for (final (i, (_, name, key)) in _hands.indexed)
                  CheckedPopupMenuItem(value: 'hand$i', checked: !player.muted.contains(key), child: Text(name)),
              ],
              const PopupMenuItem(value: 'info', child: Text('Información y rendimiento')),
            ],
          ),
        ],
      ),
    );
  }
}
