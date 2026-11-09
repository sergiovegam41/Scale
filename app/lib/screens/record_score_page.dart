import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../midi/keyboard_state.dart';
import '../midi/midi_service.dart';
import '../score/metronome.dart';
import '../storage/score_repository.dart';
import '../storage/song_repository.dart';
import '../widgets/grand_staff.dart';
import '../widgets/responsive.dart';
import 'score_page.dart';

/// Grabar tocando con metrónomo y obtener la partitura (y, si se quiere,
/// también la hoja de acordes) de la misma toma.
class RecordScorePage extends StatefulWidget {
  const RecordScorePage({
    super.key,
    required this.midi,
    required this.keyboard,
    required this.engine,
    required this.scores,
    required this.songs,
    this.notation = Notation.american,
  });

  final Notation notation;
  final MidiService midi;
  final KeyboardState keyboard;
  final ChordEngine engine;
  final ScoreRepository scores;
  final SongRepository songs;

  @override
  State<RecordScorePage> createState() => _RecordScorePageState();
}

enum _Stage { setup, recording, writing }

class _RecordScorePageState extends State<RecordScorePage> {
  // Se recuerdan mientras la app esté abierta.
  static double _lastBpm = 80;
  static TimeSignature _lastTime = TimeSignature.common;
  static bool _lastSound = true;
  static bool _lastSong = true;

  late final Metronome metronome = Metronome(widget.midi)
    ..bpm = _lastBpm
    ..time = _lastTime
    ..sound = _lastSound;
  _Stage stage = _Stage.setup;
  bool createSong = _lastSong;
  StreamSubscription<MidiInput>? _sub;
  final List<MidiEvent> _events = [];
  final List<int> _taps = [];
  DateTime? _startedAt;

  static const _times = [TimeSignature(2, 4), TimeSignature(3, 4), TimeSignature.common, TimeSignature(6, 8)];

  @override
  void dispose() {
    _sub?.cancel();
    metronome.dispose();
    super.dispose();
  }

  void _setBpm(double v) => setState(() => metronome.bpm = v.clamp(30, 220).roundToDouble());

  /// Tocar el pulso para fijar el tempo (media de los últimos toques).
  void _tap() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (_taps.isNotEmpty && now - _taps.last > 2000000) _taps.clear();
    _taps.add(now);
    if (_taps.length > 5) _taps.removeAt(0);
    if (_taps.length >= 2) {
      final avg = (_taps.last - _taps.first) / (_taps.length - 1);
      _setBpm(60e6 / avg);
    }
  }

  void _start() {
    _events.clear();
    _startedAt = DateTime.now();
    metronome.start();
    final origin = metronome.startMicros;
    _sub = widget.midi.events.listen((input) {
      final e = input.toMidiEvent();
      _events.add(MidiEvent(e.timeMicros - origin, e.status, e.data1, e.data2));
    });
    setState(() => stage = _Stage.recording);
  }

  void _discard() {
    _sub?.cancel();
    _sub = null;
    metronome.stop();
    setState(() => stage = _Stage.setup);
  }

  Future<void> _stop() async {
    _sub?.cancel();
    _sub = null;
    metronome.stop();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (!_events.any((e) => e.isNoteOn)) {
      messenger.showSnackBar(const SnackBar(content: Text('No se grabó ninguna nota')));
      setState(() => stage = _Stage.setup);
      return;
    }
    _lastBpm = metronome.bpm;
    _lastTime = metronome.time;
    _lastSound = metronome.sound;
    _lastSong = createSong;
    setState(() => stage = _Stage.writing);

    final take = Take(
      id: Song.newId(),
      recordedAt: _startedAt ?? DateTime.now(),
      events: List.of(_events),
      inputTranspose: widget.engine.inputTranspose,
    );
    final settings = TranscriptionSettings(
      bpm: metronome.bpm,
      time: metronome.time,
      startMicros: (metronome.countInPulses * metronome.pulseMicros).round(),
    );
    final d = take.recordedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final title = 'Partitura ${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
    final score = await compute(_transcribe, (take, settings, ScoreRepository.newId(), title));
    if (!mounted) return;
    if (score == null) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo escribir la partitura')));
      setState(() => stage = _Stage.setup);
      return;
    }
    await widget.scores.save(score);
    if (createSong) {
      final song = SongAnalyzer.fromTake(title: title, take: take)..transpose = widget.engine.layer;
      if (song.chords.isNotEmpty) await widget.songs.save(song);
    }
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => ScorePage(score: score, midi: widget.midi, repo: widget.scores, notation: widget.notation),
      ),
    );
  }

  static Score? _transcribe((Take, TranscriptionSettings, String, String) a) =>
      PerformanceTranscriber.transcribe(a.$1, a.$2, id: a.$3, title: a.$4);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grabar partitura'),
        automaticallyImplyLeading: stage != _Stage.recording,
      ),
      body: SafeArea(
        child: switch (stage) {
          _Stage.setup => _setup(context),
          _Stage.recording => ListenableBuilder(
              listenable: Listenable.merge([metronome, widget.keyboard]),
              builder: (context, _) => _recording(context),
            ),
          _Stage.writing => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Escribiendo la partitura…')],
              ),
            ),
        },
      ),
    );
  }

  Widget _setup(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final connected = widget.midi.connected != null;
    final unit = pulseQuarters(metronome.time) == 1.5 ? 'negra con puntillo' : (metronome.time.beatType == 2 ? 'blanca' : 'negra');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Toca a tempo con el metrónomo: así la partitura sale limpia. Antes de empezar suena un compás '
                'de cuenta. Se guarda todo lo que toques, con su fuerza, para poder volver a escribirlo después.',
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Text('Tempo', style: text.titleMedium),
              Row(
                children: [
                  IconButton.filledTonal(onPressed: () => _setBpm(metronome.bpm - 1), icon: const Icon(Icons.remove)),
                  Expanded(
                    child: Column(
                      children: [
                        Text('${metronome.bpm.round()}', style: text.displayMedium),
                        Text('pulsos por minuto ($unit)', style: text.bodySmall),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(onPressed: () => _setBpm(metronome.bpm + 1), icon: const Icon(Icons.add)),
                ],
              ),
              Slider(min: 30, max: 220, value: metronome.bpm, onChanged: _setBpm),
              Align(
                child: OutlinedButton.icon(
                  onPressed: _tap,
                  icon: const Icon(Icons.touch_app),
                  label: const Text('Marcar el tempo tocando aquí'),
                ),
              ),
              const SizedBox(height: 20),
              Text('Compás', style: text.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<TimeSignature>(
                segments: [for (final t in _times) ButtonSegment(value: t, label: Text('$t'))],
                selected: {metronome.time},
                onSelectionChanged: (s) => setState(() => metronome.time = s.first),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Metrónomo en el piano'),
                subtitle: Text(connected ? 'Suena por el canal de percusión' : 'Piano no conectado: solo se ve en pantalla'),
                value: metronome.sound,
                onChanged: (v) => setState(() => metronome.sound = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Crear también la hoja de acordes'),
                subtitle: const Text('Una canción con los acordes de la misma toma, para tocar en vivo'),
                value: createSong,
                onChanged: (v) => setState(() => createSong = v),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                onPressed: _start,
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('Empezar', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recording(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final m = metronome;
    final counting = m.pulse < m.countInPulses;
    final beats = m.pulsesPerBar;
    final dots = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < beats; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: i == 0 ? 34 : 26,
            height: i == 0 ? 34 : 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: m.pulse >= 0 && m.beatInBar == i
                  ? (counting ? scheme.tertiary : (i == 0 ? const Color(0xFFE53935) : scheme.primary))
                  : scheme.surfaceContainerHighest,
            ),
          ),
      ],
    );
    final status = counting
        ? Text(m.pulse < 0 ? 'Prepárate…' : '${m.countdown}', style: text.displayMedium?.copyWith(color: scheme.tertiary))
        : Text('Compás ${m.bar}', style: text.displaySmall);
    final held = widget.keyboard.held.keys.toList();
    final compact = context.isCompact;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          dots,
          const SizedBox(height: 12),
          status,
          Text(
            counting ? 'Cuenta: empieza a tocar en el primer pulso del compás 1' : '● Grabando · ${m.bpm.round()} · ${m.time}',
            style: text.bodyLarge?.copyWith(color: counting ? scheme.onSurfaceVariant : const Color(0xFFE53935)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: held.isEmpty
                    ? Center(child: Text('Lo que toques aparece aquí', style: TextStyle(color: scheme.onSurfaceVariant)))
                    : GrandStaff(notes: held),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(onPressed: _discard, icon: const Icon(Icons.close), label: const Text('Descartar')),
              SizedBox(width: compact ? 12 : 32),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                ),
                onPressed: _stop,
                icon: const Icon(Icons.stop),
                label: const Text('Terminar y escribir', style: TextStyle(fontSize: 17)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
