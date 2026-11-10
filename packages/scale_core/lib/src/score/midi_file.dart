import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../midi/midi_event.dart';
import '../model/song.dart';
import '../theory/key.dart';
import 'score.dart';
import 'transcriber.dart';

/// Un mensaje de un archivo MIDI, en pulsos del archivo.
class MidiFileEvent {
  const MidiFileEvent(this.tick, this.status, this.data1, this.data2);

  final int tick;
  final int status;
  final int data1;
  final int data2;

  int get type => status & 0xF0;
  int get channel => status & 0x0F;
  bool get isNoteOn => type == 0x90 && data2 > 0;
}

/// Lo que suena en un canal de una pista: lo que se elige al importar
/// (una pista por mano, la melodía sin el acompañamiento…).
class MidiSource {
  MidiSource({required this.track, required this.channel, this.name});

  final int track;
  final int channel;

  /// Nombre de la pista, si tiene.
  final String? name;

  /// Instrumento General MIDI (el primero que se elige en el canal).
  int? program;
  int notes = 0;
  int lowest = 127;
  int highest = 0;

  /// Clave para elegirla.
  String get id => '$track:$channel';

  bool get drums => channel == 9;

  /// Familia del instrumento, en español.
  String get instrument {
    if (drums) return 'Batería';
    final p = program;
    if (p == null) return 'Piano';
    return _families[p ~/ 8];
  }

  static const _families = [
    'Piano',
    'Percusión afinada',
    'Órgano',
    'Guitarra',
    'Bajo',
    'Cuerdas',
    'Conjunto',
    'Metales',
    'Lengüetas',
    'Flautas',
    'Sintetizador',
    'Sintetizador (fondo)',
    'Efectos',
    'Étnico',
    'Percusión',
    'Efectos de sonido',
  ];
}

/// Archivo MIDI estándar (.mid): pistas, tempos, compases y armaduras.
class MidiFile {
  MidiFile._(this.format, this.ticksPerQuarter, this.tracks, this.trackNames);

  /// Formato 0 (todo en una pista) o 1 (varias pistas a la vez).
  final int format;
  final int ticksPerQuarter;
  final List<List<MidiFileEvent>> tracks;
  final List<String?> trackNames;

  /// (pulso del archivo, negras por minuto).
  final List<(int, double)> tempos = [];

  /// (pulso del archivo, compás).
  final List<(int, TimeSignature)> meters = [];

  /// (pulso del archivo, sostenidos (+) o bemoles (−), menor).
  final List<(int, int, bool)> keys = [];

  /// Nombre de la pieza (la primera pista de un formato 1, si no tiene notas).
  String? title;

  late final List<MidiSource> sources = _sources();

  /// Lee un archivo .mid. Lanza [FormatException] si no lo es.
  static MidiFile parse(Uint8List bytes) {
    final r = _Reader(bytes);
    if (bytes.length < 14 || r.ascii(4) != 'MThd') {
      throw const FormatException('No es un archivo MIDI');
    }
    final headerLength = r.u32();
    final format = r.u16();
    final count = r.u16();
    final division = r.u16();
    r.pos = 8 + headerLength;
    if (division & 0x8000 != 0) {
      throw const FormatException('Archivo MIDI con tiempo SMPTE: no se puede importar');
    }
    if (division == 0) throw const FormatException('Archivo MIDI dañado');
    final tracks = <List<MidiFileEvent>>[];
    final names = <String?>[];
    final file = MidiFile._(format, division, tracks, names);
    while (tracks.length < count && r.pos + 8 <= bytes.length) {
      final id = r.ascii(4);
      final length = r.u32();
      final end = math.min(bytes.length, r.pos + length);
      if (id == 'MTrk') {
        final (events, name) = file._readTrack(r, end, tracks.length);
        tracks.add(events);
        names.add(name);
      }
      r.pos = end;
    }
    if (tracks.isEmpty) throw const FormatException('El archivo MIDI no tiene pistas');
    file.tempos.sort((a, b) => a.$1.compareTo(b.$1));
    file.meters.sort((a, b) => a.$1.compareTo(b.$1));
    file.keys.sort((a, b) => a.$1.compareTo(b.$1));
    if (format == 1 && names.first != null && !tracks.first.any((e) => e.isNoteOn)) file.title = names.first;
    if (format == 0) file.title = names.first;
    return file;
  }

  (List<MidiFileEvent>, String?) _readTrack(_Reader r, int end, int index) {
    final out = <MidiFileEvent>[];
    String? name;
    var tick = 0;
    var running = 0;
    while (r.pos < end) {
      tick += r.varLen();
      if (r.pos >= end) break;
      var status = r.peek();
      if (status & 0x80 != 0) {
        r.pos++;
      } else {
        status = running; // estado continuo: se repite el último
        if (status == 0) throw const FormatException('Archivo MIDI dañado');
      }
      if (status == 0xFF) {
        final type = r.u8();
        final len = r.varLen();
        final data = r.bytes(math.min(len, end - r.pos));
        switch (type) {
          case 0x03:
            name ??= _text(data);
          case 0x51 when data.length >= 3:
            final micros = data[0] << 16 | data[1] << 8 | data[2];
            if (micros > 0) tempos.add((tick, 60e6 / micros));
          case 0x58 when data.length >= 2:
            if (data[0] > 0 && data[1] < 7) meters.add((tick, TimeSignature(data[0], 1 << data[1])));
          case 0x59 when data.length >= 2:
            keys.add((tick, data[0].toSigned(8), data[1] == 1));
          case 0x2F:
            return (out, name);
        }
        continue;
      }
      if (status == 0xF0 || status == 0xF7) {
        r.pos += r.varLen();
        continue;
      }
      running = status;
      final type = status & 0xF0;
      final d1 = r.u8();
      final d2 = type == 0xC0 || type == 0xD0 ? 0 : r.u8();
      out.add(MidiFileEvent(tick, status, d1 & 0x7F, d2 & 0x7F));
    }
    return (out, name);
  }

  static String? _text(Uint8List data) {
    final s = utf8.decode(data, allowMalformed: true).replaceAll('\u0000', '').trim();
    // Muchos archivos viejos usan Latin-1.
    final t = s.contains('�') ? latin1.decode(data).trim() : s;
    return t.isEmpty ? null : t;
  }

  List<MidiSource> _sources() {
    final out = <String, MidiSource>{};
    for (final (t, events) in tracks.indexed) {
      final programs = <int, int>{};
      for (final e in events) {
        if (e.type == 0xC0) programs.putIfAbsent(e.channel, () => e.data1);
        if (!e.isNoteOn) continue;
        final s = out.putIfAbsent(
          '$t:${e.channel}',
          () => MidiSource(track: t, channel: e.channel, name: trackNames[t]),
        );
        s.notes++;
        s.lowest = math.min(s.lowest, e.data1);
        s.highest = math.max(s.highest, e.data1);
      }
      for (final s in out.values) {
        if (s.track == t) s.program = programs[s.channel];
      }
    }
    return out.values.toList();
  }

  /// Negras por minuto al principio (120 si el archivo no lo dice).
  double get initialTempo => tempos.isEmpty || tempos.first.$1 > 0 ? 120 : tempos.first.$2;

  /// Si cambia de compás en algún momento (solo se usa el primero).
  bool get changesMeter => meters.map((m) => m.$2).toSet().length > 1;
}

/// Convierte un archivo MIDI en partitura de piano: las notas de las
/// fuentes elegidas, en su sitio exacto, escritas con las mismas reglas que
/// una grabación (figuras, manos, ortografía, cifrado), con el compás, la
/// armadura y los tempos del archivo.
class MidiFileImporter {
  /// [sources]: ids de [MidiFile.sources] a incluir (por defecto todas
  /// menos la batería). Devuelve null si no queda ninguna nota.
  static Score? toScore(MidiFile file, {required String id, String? title, String? fileName, Set<String>? sources}) {
    final chosen = [
      for (final s in file.sources)
        if (sources == null ? !s.drums : sources.contains(s.id)) s,
    ];
    if (chosen.isEmpty) return null;
    // Cada fuente en un canal. Pentagrama fijo por pista: con dos, la más
    // aguda arriba (una pista por mano); con más, según su registro, salvo
    // las que lo recorren todo (esas se reparten nota a nota).
    final byId = <String, int>{};
    final staffByChannel = <int, int>{};
    const channels = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15];
    double middle(MidiSource s) => (s.lowest + s.highest) / 2;
    for (final (i, s) in chosen.indexed) {
      final ch = channels[math.min(i, channels.length - 1)];
      byId[s.id] = ch;
      if (chosen.length > channels.length || chosen.length < 2) continue;
      if (chosen.length == 2) {
        final other = chosen[1 - i];
        staffByChannel[ch] = middle(s) > middle(other) || (middle(s) == middle(other) && i == 0) ? 1 : 2;
      } else if (s.highest - s.lowest <= 24) {
        staffByChannel[ch] = middle(s) >= 60 ? 1 : 2;
      }
    }

    // Tiempo virtual: una negra por segundo (los tempos van aparte).
    final ppq = file.ticksPerQuarter;
    int micros(int tick) => (tick * 1e6 / ppq).round();
    final events = <MidiEvent>[];
    final velocities = <int>{};
    for (final (t, track) in file.tracks.indexed) {
      for (final e in track) {
        final channel = byId['$t:${e.channel}'];
        if (channel == null) continue;
        if (e.type == 0x90 || e.type == 0x80) {
          events.add(MidiEvent(micros(e.tick), e.type | channel, e.data1, e.type == 0x80 ? 0 : e.data2));
          if (e.isNoteOn) velocities.add(e.data2);
        } else if (e.type == 0xB0 && e.data1 == MidiEvent.sustainController) {
          events.add(MidiEvent(micros(e.tick), 0xB0 | channel, e.data1, e.data2));
        }
      }
    }
    // Ordenadas por instante; a la vez, primero lo que se suelta.
    events.sort((a, b) {
      final c = a.timeMicros.compareTo(b.timeMicros);
      if (c != 0) return c;
      return (a.isNoteOff ? 0 : 1).compareTo(b.isNoteOff ? 0 : 1);
    });
    if (!events.any((e) => e.isNoteOn)) return null;

    // Compases del archivo; el pulso, el del compás que más dura.
    final map = [for (final (t, m) in file.meters) ((t * ticksPerQuarter / ppq).round(), m)];
    if (map.isEmpty || map.first.$1 > 0) map.insert(0, (0, TimeSignature.common));
    final lasting = <TimeSignature, int>{};
    for (var i = 0; i < map.length; i++) {
      final until = i + 1 < map.length ? map[i + 1].$1 : map[i].$1 + 1;
      lasting[map[i].$2] = (lasting[map[i].$2] ?? 0) + until - map[i].$1;
    }
    final time = lasting.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    final key = file.keys.isEmpty ? null : file.keys.first;
    int? keyIndex;
    if (key != null && key.$2 != 0) {
      final major = (key.$2 * 7) % 12;
      keyIndex = (key.$3 ? MusicKey(major + 9, Mode.minor) : MusicKey(major, Mode.major)).index;
    }
    final settings = TranscriptionSettings(
      bpm: 60 / pulseQuarters(time),
      time: time,
      meter: time,
      startMicros: 0,
      autoLatency: false,
      tempoMode: TempoMode.metronome,
      keyIndex: keyIndex,
      dynamics: velocities.length > 1 && velocities.reduce(math.max) - velocities.reduce(math.min) > 10,
    );
    final name = title ?? file.title ?? _baseName(fileName) ?? 'MIDI';
    final score = PerformanceTranscriber.transcribe(
      Take(id: id, recordedAt: DateTime.now(), events: events),
      settings,
      id: id,
      title: name,
      exact: true,
      staffByChannel: staffByChannel.isEmpty ? null : staffByChannel,
      measureMap: map,
    );
    if (score == null) return null;

    // Dónde quedó el pulso 0 del archivo en la partitura (se quitan los
    // compases vacíos del principio), y los tempos.
    final firstOn = events.firstWhere((e) => e.isNoteOn).timeMicros;
    final firstWritten = score.parts.single.events.firstWhere((e) => !e.isRest).tick;
    final originTick = (firstOn / 1e6 * ticksPerQuarter).round() - firstWritten;
    final tempos = file.tempos.isEmpty ? [(0, 120.0)] : file.tempos;
    double tempoAt(int scoreTick) {
      final fileTick = (scoreTick + originTick) * ppq / ticksPerQuarter;
      var bpm = file.initialTempo;
      for (final (t, b) in tempos) {
        if (t > fileTick + ppq / 32) break;
        bpm = b;
      }
      return double.parse(bpm.toStringAsFixed(1));
    }

    double? last;
    for (final m in score.measures) {
      final bpm = tempoAt(m.tick);
      m.tempo = bpm == last ? null : bpm;
      last = bpm;
    }
    score
      ..recording = null
      ..source = ScoreSource(kind: 'midi', name: fileName);
    return score;
  }

  static String? _baseName(String? fileName) {
    if (fileName == null) return null;
    final base = fileName.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    final s = (dot > 0 ? base.substring(0, dot) : base).replaceAll('_', ' ').trim();
    return s.isEmpty ? null : s;
  }
}

class _Reader {
  _Reader(this.data);

  final Uint8List data;
  int pos = 0;

  void _need(int n) {
    if (pos + n > data.length) throw const FormatException('Archivo MIDI incompleto');
  }

  int peek() {
    _need(1);
    return data[pos];
  }

  int u8() {
    _need(1);
    return data[pos++];
  }

  int u16() => u8() << 8 | u8();
  int u32() => u16() << 16 | u16();

  String ascii(int n) {
    _need(n);
    final s = String.fromCharCodes(data, pos, pos + n);
    pos += n;
    return s;
  }

  Uint8List bytes(int n) {
    _need(n);
    final b = Uint8List.sublistView(data, pos, pos + n);
    pos += n;
    return b;
  }

  int varLen() {
    var v = 0;
    for (var i = 0; i < 4; i++) {
      final b = u8();
      v = v << 7 | (b & 0x7F);
      if (b & 0x80 == 0) return v;
    }
    return v;
  }
}
