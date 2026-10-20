import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';
import '../settings.dart';

/// Pasa el MIDI entrante al análisis del núcleo y graba tomas.
///
/// En modo libre se conservan los últimos [freeHistory] acordes. Al grabar se
/// empieza de cero (la tonalidad se determina durante la toma) y se guarda
/// cada mensaje MIDI crudo con tiempo relativo al inicio.
class ChordEngine extends ChangeNotifier {
  ChordEngine(this.midi, this.settings) {
    _sub = midi.events.listen(_onInput);
  }

  static const int freeHistory = 64;

  final MidiService midi;
  final AppSettings settings;

  /// Capa de transpose digital: los semitonos que tiene puestos el piano.
  /// Lo que se analiza y muestra son las figuras (lo que tocan las manos);
  /// lo que suena es figuras + capa.
  int get layer => _layer;
  int _layer = 0;

  set layer(int value) {
    if (recording || value == _layer) return;
    _layer = value;
    analyzer.reset();
    // Cambia al abrir o cerrar una pantalla (en plena construcción de la
    // interfaz): se avisa apenas termine, no en medio.
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  bool _disposed = false;

  /// Semitonos que hay que restar a lo que llega para obtener las figuras.
  int get _inputShift => settings.pianoSendsTransposed ? -_layer : 0;
  late final StreamSubscription<MidiInput> _sub;
  Timer? _closeTimer;
  Timer? _clockTimer;

  LiveAnalyzer analyzer = LiveAnalyzer(maxHistory: freeHistory);

  List<MidiEvent>? _takeEvents;
  int _takeStart = 0;
  DateTime? _takeStartedAt;

  bool get recording => _takeEvents != null;

  Duration get recordingElapsed =>
      recording ? Duration(microseconds: midi.now.inMicroseconds - _takeStart) : Duration.zero;

  List<DetectedChord> get chords => analyzer.chords;
  DetectedChord? get current => chords.isEmpty ? null : chords.last;
  bool get sounding => analyzer.sounding;
  int get attacks => analyzer.attacks;
  int? get lastAttackMicros => analyzer.lastAttackMicros;
  KeyEstimate get key => analyzer.key;
  MusicKey? get previousKey => analyzer.previousKey;
  MusicKey? get displayKey => analyzer.displayKey;

  void startRecording() {
    _closeTimer?.cancel();
    analyzer = LiveAnalyzer();
    _takeEvents = [];
    _takeStart = midi.now.inMicroseconds;
    _takeStartedAt = DateTime.now();
    // Refresca el cronómetro en pantalla.
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => notifyListeners());
    notifyListeners();
  }

  /// Termina la toma; devuelve null si no se tocó nada.
  Take? stopRecording() {
    final events = _takeEvents;
    if (events == null) return null;
    _clockTimer?.cancel();
    _closeTimer?.cancel();
    _takeEvents = null;
    analyzer = LiveAnalyzer(maxHistory: freeHistory);
    notifyListeners();
    if (!events.any((e) => e.isNoteOn)) return null;
    // La toma guarda el MIDI tal como llegó y cuánto hay que restarle.
    return Take(
      id: Song.newId(),
      recordedAt: _takeStartedAt!,
      events: events,
      inputTranspose: -_inputShift,
    );
  }

  void _onInput(MidiInput input) {
    final event = input.toMidiEvent();
    final take = _takeEvents;
    if (take != null) {
      take.add(MidiEvent(event.timeMicros - _takeStart, event.status, event.data1, event.data2));
    }
    analyzer.add(event.transposed(_inputShift));
    _scheduleClose();
    notifyListeners();
  }

  // El ataque se cierra tras la ventana de agrupación aunque no lleguen
  // más mensajes, para mostrar el acorde sin esperar a la siguiente nota.
  void _scheduleClose() {
    _closeTimer?.cancel();
    final close = analyzer.pendingCloseMicros;
    if (close == null) return;
    final wait = math.max(0, close - midi.now.inMicroseconds);
    _closeTimer = Timer(Duration(microseconds: wait), () {
      if (analyzer.advanceTo(midi.now.inMicroseconds)) notifyListeners();
    });
  }

  void reset() {
    _closeTimer?.cancel();
    analyzer.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _closeTimer?.cancel();
    _clockTimer?.cancel();
    _sub.cancel();
    super.dispose();
  }
}
