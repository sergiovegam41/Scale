import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';
import 'package:scale_core/scale_core.dart';

enum MidiInputKind { noteOn, noteOff, controlChange }

/// Mensaje MIDI entrante, reducido a lo que la app necesita.
class MidiInput {
  const MidiInput({
    required this.time,
    required this.kind,
    required this.channel,
    required this.data1,
    required this.data2,
  });

  /// Momento de llegada, medido desde que arrancó el servicio.
  final Duration time;
  final MidiInputKind kind;
  final int channel;

  /// Nota (note on/off) o número de controlador (CC).
  final int data1;

  /// Velocidad (note on/off) o valor (CC).
  final int data2;

  /// Versión del núcleo, en microsegundos, para análisis y grabación.
  MidiEvent toMidiEvent() => MidiEvent(
        time.inMicroseconds,
        switch (kind) {
              MidiInputKind.noteOn => 0x90,
              MidiInputKind.noteOff => 0x80,
              MidiInputKind.controlChange => 0xB0,
            } |
            channel,
        data1,
        data2,
      );
}

/// Descubre teclados MIDI por USB, se conecta solo al primero disponible
/// y publica los mensajes entrantes.
class MidiService extends ChangeNotifier {
  final MidiCommand _midi = MidiCommand();
  final Stopwatch _clock = Stopwatch()..start();
  final StreamController<MidiInput> _events = StreamController.broadcast();
  final Set<String> _autoConnectTried = {};
  StreamSubscription<MidiDataReceivedEvent>? _rxSub;
  StreamSubscription<MidiSetupChange>? _setupSub;
  Timer? _poll;
  AppLifecycleListener? _lifecycle;

  /// Cada cuánto se buscan dispositivos mientras no hay ninguno conectado,
  /// por si el sistema no avisa del cambio al reconectar el cable.
  static const Duration pollInterval = Duration(seconds: 3);

  List<MidiDevice> devices = const [];
  MidiDevice? connected;
  bool connecting = false;
  String? error;

  Stream<MidiInput> get events => _events.stream;

  /// Reloj con el que se marcan los mensajes entrantes.
  Duration get now => _clock.elapsed;

  Future<void> init() async {
    _midi.configureBleTransport(null);
    _midi.configureTransportPolicy(
      const MidiTransportPolicy(excludedTransports: {MidiTransport.ble}),
    );
    _setupSub = _midi.onMidiSetupChanged?.listen((_) => refresh());
    _rxSub = _midi.onMidiDataReceived?.listen(_onData);
    _lifecycle = AppLifecycleListener(onResume: refresh);
    _poll = Timer.periodic(pollInterval, (_) {
      if (connected == null && !connecting) refresh();
    });
    await refresh();
  }

  Future<void> refresh() async {
    try {
      devices = await _midi.devices ?? const [];
    } catch (e) {
      error = 'No se pudo listar dispositivos: $e';
      devices = const [];
    }
    // Un dispositivo que desapareció puede volver a autoconectarse al reconectar el cable.
    _autoConnectTried.removeWhere((id) => !devices.any((d) => d.id == id));
    final stillThere = devices.where((d) => d.id == connected?.id).toList();
    connected = stillThere.isEmpty ? null : stillThere.first;
    notifyListeners();

    if (connected == null && !connecting) {
      final candidates =
          devices.where((d) => !_autoConnectTried.contains(d.id)).toList();
      if (candidates.isNotEmpty) {
        _autoConnectTried.add(candidates.first.id);
        await connect(candidates.first);
      }
    }
  }

  Future<void> connect(MidiDevice device) async {
    connecting = true;
    error = null;
    notifyListeners();
    try {
      final previous = connected;
      if (previous != null && previous.id != device.id) {
        _midi.disconnectDevice(previous);
      }
      await _midi.connectToDevice(device);
      connected = device;
    } catch (e) {
      error = 'No se pudo conectar a ${device.name}: $e';
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  /// Envía bytes MIDI al dispositivo conectado (para que suene en el piano).
  bool send(List<int> bytes) {
    final device = connected;
    if (device == null) return false;
    try {
      _midi.sendData(Uint8List.fromList(bytes), deviceId: device.id);
      return true;
    } catch (e) {
      debugPrint('No se pudo enviar MIDI: $e');
      return false;
    }
  }

  void _onData(MidiDataReceivedEvent event) {
    final time = _clock.elapsed;
    final message = event.message;
    final MidiInput? input = switch (message) {
      NoteOnMessage(:final channel, :final note, :final velocity) => MidiInput(
          time: time,
          kind: velocity == 0 ? MidiInputKind.noteOff : MidiInputKind.noteOn,
          channel: channel,
          data1: note,
          data2: velocity,
        ),
      NoteOffMessage(:final channel, :final note, :final velocity) => MidiInput(
          time: time,
          kind: MidiInputKind.noteOff,
          channel: channel,
          data1: note,
          data2: velocity,
        ),
      CCMessage(:final channel, :final controller, :final value) => MidiInput(
          time: time,
          kind: MidiInputKind.controlChange,
          channel: channel,
          data1: controller,
          data2: value,
        ),
      _ => null,
    };
    if (input != null) _events.add(input);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle?.dispose();
    _rxSub?.cancel();
    _setupSub?.cancel();
    _events.close();
    _midi.dispose();
    super.dispose();
  }
}
