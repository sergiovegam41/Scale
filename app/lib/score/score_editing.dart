import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import '../midi/midi_service.dart';

/// Corregir una partitura: qué nota está elegida, las correcciones (con
/// deshacer) y el teclado como forma rápida de corregir: se elige una nota
/// en la partitura y se toca la correcta (o el acorde entero); al soltar las
/// teclas se aplica y pasa a la siguiente.
///
/// Trabaja sobre una copia: la partitura original no cambia hasta guardar.
class ScoreEditing extends ChangeNotifier {
  ScoreEditing(this.midi, this.original) : editor = ScoreEditor(Score.fromJson(original.toJson())) {
    _sub = midi.events.listen(_onInput);
  }

  final MidiService midi;

  /// La partitura tal como estaba al empezar.
  final Score original;
  final ScoreEditor editor;
  late final StreamSubscription<MidiInput> _sub;

  Score get score => editor.score;

  /// Nota (o silencio) elegida.
  String? get selected => _selected;
  String? _selected;

  /// Lo que se resalta en la partitura (la elegida).
  final ValueNotifier<List<String>> selection = ValueNotifier(const []);

  /// Algo que no se pudo hacer, para avisarlo.
  void Function(String message)? onError;

  /// Hacer sonar en el piano la nota elegida al cambiarla con los botones.
  bool sound = true;

  ScoreLocation? get location {
    final id = _selected;
    return id == null ? null : editor.locate(id);
  }

  void select(String? id, {bool play = true}) {
    _selected = id;
    selection.value = id == null ? const [] : [id];
    if (play) _preview();
    notifyListeners();
  }

  /// Aplica una corrección que devuelve lo que queda elegido.
  bool apply(String Function() change, {bool play = true, bool advance = false}) {
    try {
      final id = change();
      select(advance ? (editor.neighbor(id, 1) ?? id) : id, play: play);
      return true;
    } on EditError catch (e) {
      onError?.call(e.message);
      notifyListeners();
      return false;
    }
  }

  void undo() {
    editor.undo();
    _keepSelection();
  }

  void redo() {
    editor.redo();
    _keepSelection();
  }

  /// Tras deshacer, la nota elegida puede no existir.
  void _keepSelection() {
    final id = _selected;
    select(id != null && editor.locate(id) != null ? id : null, play: false);
  }

  // Teclado

  final Set<int> _held = {};
  final List<int> _pressed = [];

  /// Notas que la app acaba de hacer sonar o callar (por si el piano las
  /// devuelve como si se hubieran tocado): altura → hasta cuándo, en µs.
  final Map<int, int> _echo = {};

  void _onInput(MidiInput input) {
    if (input.channel == 9) return;
    final note = input.data1;
    final now = input.time.inMicroseconds;
    final echo = _echo[note];
    if (echo != null && now < echo) return;
    switch (input.kind) {
      case MidiInputKind.noteOn:
        _held.add(note);
        if (!_pressed.contains(note)) _pressed.add(note);
      case MidiInputKind.noteOff:
        _held.remove(note);
        if (_held.isEmpty && _pressed.isNotEmpty) {
          final notes = List<int>.of(_pressed);
          _pressed.clear();
          fromPiano(notes);
        }
      case MidiInputKind.controlChange:
        break;
    }
  }

  /// Lo tocado en el teclado (al soltar): una tecla cambia la nota elegida;
  /// varias, el acorde entero. Luego pasa a la siguiente.
  void fromPiano(List<int> notes) {
    final id = _selected;
    final loc = location;
    if (id == null || loc == null) {
      onError?.call('Primero toca en la partitura la nota que quieres corregir');
      return;
    }
    // Una tecla sobre una nota: cambia esa nota (aunque esté en un acorde).
    final single = notes.length == 1 && loc.note != null && loc.note!.id == id;
    apply(
      single ? () => editor.setPitch(id, notes.first) : () => editor.setPitches(id, notes),
      play: false,
      advance: true,
    );
  }

  static const _echoMicros = 80000;
  Timer? _off;
  List<int> _sounding = const [];

  /// Hace sonar la nota elegida (o su acorde) un momento.
  void _preview() {
    final loc = location;
    if (!sound || loc == null || loc.event.isRest || midi.connected == null) return;
    _stopPreview();
    final notes = [for (final n in loc.event.notes) n.midi];
    final until = midi.now.inMicroseconds + _echoMicros;
    for (final m in notes) {
      _echo[m] = until;
      midi.send([0x90, m, 72]);
    }
    _sounding = notes;
    _off = Timer(const Duration(milliseconds: 450), _stopPreview);
  }

  void _stopPreview() {
    _off?.cancel();
    final until = midi.now.inMicroseconds + _echoMicros;
    for (final m in _sounding) {
      _echo[m] = until;
      midi.send([0x80, m, 0]);
    }
    _sounding = const [];
  }

  @override
  void dispose() {
    _sub.cancel();
    _stopPreview();
    selection.dispose();
    super.dispose();
  }
}
