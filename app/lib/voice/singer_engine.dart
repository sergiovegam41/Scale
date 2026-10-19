import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:scale_core/scale_core.dart';

/// Un análisis de altura (null si en ese instante no había voz clara).
class PitchPoint {
  const PitchPoint(this.timeMicros, this.midi);

  final int timeMicros;
  final double? midi;
}

/// Escucha al cantante por el micrófono y va estimando en qué tonalidad canta.
/// También guarda los últimos segundos de altura y espectro para graficarlos.
class SingerEngine extends ChangeNotifier {
  static const int sampleRate = 16000;
  static const int frameSize = 1024; // 64 ms: alcanza para voces graves
  static const int hop = 512; // ~31 análisis por segundo
  static const int _frameMicros = hop * 1000000 ~/ sampleRate;

  /// Análisis que se conservan para el gráfico (~8 s).
  static const int historyLength = 256;

  AudioRecorder? _recorderInstance;
  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();
  final PitchDetector _detector = PitchDetector(sampleRate: sampleRate);
  final MelodyTracker tracker = MelodyTracker();
  final NoteSpectrum spectrum = NoteSpectrum(sampleRate: sampleRate);
  StreamSubscription<Uint8List>? _sub;

  bool listening = false;
  String? error;

  /// Entradas de audio disponibles. Con el teclado conectado por USB, Android
  /// grabaría el audio del piano: por eso se elige el micrófono de la tablet.
  List<InputDevice> devices = const [];
  InputDevice? device;
  String? _chosenId;

  static String deviceName(InputDevice d) => switch (d.type) {
        InputDeviceType.builtIn => 'Micrófono de la tablet',
        InputDeviceType.usb => 'USB: ${d.label}',
        InputDeviceType.wiredHeadset => 'Micrófono con cable',
        InputDeviceType.bluetoothSco || InputDeviceType.bluetoothLe => 'Bluetooth: ${d.label}',
        _ => d.label,
      };

  Future<void> refreshDevices() async {
    try {
      devices = await _recorder.listInputDevices();
    } catch (_) {
      devices = const [];
    }
    InputDevice? pick(bool Function(InputDevice) test) {
      for (final d in devices) {
        if (test(d)) return d;
      }
      return null;
    }

    // En escritorio el tipo puede venir sin informar: se evita lo que suene a
    // USB o al teclado (que manda el audio del piano).
    bool looksLikeKeyboard(InputDevice d) {
      final label = d.label.toLowerCase();
      return d.type == InputDeviceType.usb ||
          label.contains('usb') ||
          label.contains('keyboard') ||
          label.contains('yamaha') ||
          label.contains('piano');
    }

    device = pick((d) => d.id == _chosenId) ??
        pick((d) => d.type == InputDeviceType.builtIn) ??
        pick((d) => !looksLikeKeyboard(d)) ??
        (devices.isEmpty ? null : devices.first);
    notifyListeners();
  }

  /// Cambiar de entrada (si se está escuchando, se reinicia con la nueva).
  Future<void> selectDevice(InputDevice d) async {
    _chosenId = d.id;
    device = d;
    notifyListeners();
    if (listening) {
      await stop();
      await start();
    }
  }
  KeyEstimate key = MelodyKeyEstimator.estimate(const []);

  /// Altura de cada análisis, de la más vieja a la más nueva.
  final List<PitchPoint> trace = [];

  /// Espectro de cada análisis (una columna por análisis, alineada con
  /// [trace]): intensidad 0–255 por fila de [spectrum], de grave a agudo.
  final List<Uint8List> spectrogram = [];

  /// Cambia con cada análisis nuevo (para redibujar el gráfico).
  int version = 0;

  final List<double> _buffer = [];
  final List<double> _past = [];
  int _samplesSeen = 0;
  int _lastNotify = 0;

  /// Nivel de referencia del espectrograma: sigue a lo más fuerte reciente.
  double _peakDb = 0;
  static const double _rangeDb = 60;
  static const double _quietestPeakDb = 25;

  List<SungNote> get notes => tracker.notes;
  double? get currentMidi => tracker.currentMidi;
  (int, int)? get range => MelodyKeyEstimator.range(tracker.notes);

  Future<void> start() async {
    if (listening) return;
    error = null;
    try {
      if (!await _recorder.hasPermission()) {
        error = 'Sin permiso para usar el micrófono. Actívalo en los ajustes de Android.';
        notifyListeners();
        return;
      }
      await refreshDevices();
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          device: device,
          androidConfig: const AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
        ),
      );
      _sub = stream.listen(feed, onError: (Object e) {
        error = 'Error del micrófono: $e';
        stop();
      });
      listening = true;
    } catch (e) {
      error = 'No se pudo abrir el micrófono: $e';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (!listening) return;
    listening = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    if (tracker.flush()) _updateKey();
    notifyListeners();
  }

  void reset() {
    tracker.reset();
    _buffer.clear();
    _past.clear();
    trace.clear();
    spectrogram.clear();
    version++;
    key = MelodyKeyEstimator.estimate(const []);
    notifyListeners();
  }

  /// Audio PCM de 16 bits little-endian (del micrófono, o de una prueba).
  void feed(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      _buffer.add(data.getInt16(i, Endian.little) / 32768);
    }
    var changed = false;
    while (_buffer.length >= frameSize) {
      final time = _samplesSeen * 1000000 ~/ sampleRate;
      final frame = _buffer.sublist(0, frameSize);
      final pitch = _detector.detect(frame);
      if (tracker.addFrame(time, pitch, _frameMicros)) changed = true;
      _record(time, pitch, frame);
      _past.addAll(_buffer.getRange(0, hop));
      if (_past.length > spectrum.size) _past.removeRange(0, _past.length - spectrum.size);
      _buffer.removeRange(0, hop);
      _samplesSeen += hop;
    }
    if (changed) _updateKey();
    // La nota actual y el gráfico se refrescan unas 15 veces por segundo.
    final now = _samplesSeen * 1000 ~/ sampleRate;
    if (changed || now - _lastNotify > 66) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  void _record(int time, PitchEstimate? pitch, List<double> frame) {
    trace.add(PitchPoint(time, pitch?.midi));
    // El espectro mira un poco más atrás (128 ms) para separar bien los graves.
    final db = spectrum.analyze([..._past, ...frame]);
    var loudest = db.first;
    for (final v in db) {
      if (v > loudest) loudest = v;
    }
    _peakDb = math.max(_quietestPeakDb, math.max(loudest, _peakDb - 0.15));
    final floor = _peakDb - _rangeDb;
    final column = Uint8List(db.length);
    for (var r = 0; r < db.length; r++) {
      final v = ((db[r] - floor) / _rangeDb).clamp(0.0, 1.0);
      column[r] = (math.pow(v, 1.6) * 255).round();
    }
    spectrogram.add(column);
    if (trace.length > historyLength) trace.removeAt(0);
    if (spectrogram.length > historyLength) spectrogram.removeAt(0);
    version++;
  }

  void _updateKey() => key = MelodyKeyEstimator.estimate(tracker.notes);

  @override
  void dispose() {
    _sub?.cancel();
    _recorderInstance?.dispose();
    super.dispose();
  }
}
