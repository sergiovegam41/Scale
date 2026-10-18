/// Mensaje MIDI de canal con su instante en microsegundos.
///
/// Es la unidad que se guarda en bruto en cada toma: todo el análisis se
/// puede recalcular a partir de una lista de estos eventos.
class MidiEvent {
  const MidiEvent(this.timeMicros, this.status, this.data1, [this.data2 = 0]);

  factory MidiEvent.noteOn(int timeMicros, int note, {int velocity = 100, int channel = 0}) =>
      MidiEvent(timeMicros, 0x90 | channel, note, velocity);

  factory MidiEvent.noteOff(int timeMicros, int note, {int channel = 0}) =>
      MidiEvent(timeMicros, 0x80 | channel, note, 0);

  factory MidiEvent.sustain(int timeMicros, {required bool down, int channel = 0}) =>
      MidiEvent(timeMicros, 0xB0 | channel, 64, down ? 127 : 0);

  /// Formato compacto de persistencia: [tiempo, status, data1, data2].
  factory MidiEvent.fromJson(List<dynamic> json) =>
      MidiEvent(json[0] as int, json[1] as int, json[2] as int, json[3] as int);

  static const int sustainController = 64;

  final int timeMicros;
  final int status;
  final int data1;
  final int data2;

  int get type => status & 0xF0;
  int get channel => status & 0x0F;
  bool get isNoteOn => type == 0x90 && data2 > 0;
  bool get isNoteOff => type == 0x80 || (type == 0x90 && data2 == 0);
  bool get isNote => type == 0x80 || type == 0x90;
  bool get isSustain => type == 0xB0 && data1 == sustainController;
  bool get sustainDown => data2 >= 64;

  /// Mueve la nota [semitones] (las demás clases de mensaje no cambian).
  MidiEvent transposed(int semitones) {
    if (!isNote || semitones == 0) return this;
    return MidiEvent(timeMicros, status, (data1 + semitones).clamp(0, 127), data2);
  }

  List<int> toJson() => [timeMicros, status, data1, data2];

  @override
  String toString() => 'MidiEvent($timeMicros, 0x${status.toRadixString(16)}, $data1, $data2)';
}
