import 'dart:convert';

import '../notation/chord_staff.dart';
import '../theory/chord_parser.dart';
import '../theory/key.dart';
import '../theory/pitch.dart';
import 'score.dart';

/// Una corrección que no se puede hacer (el mensaje es para quien edita).
class EditError implements Exception {
  const EditError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dónde está una nota o un silencio dentro de la partitura.
class ScoreLocation {
  const ScoreLocation(this.partIndex, this.part, this.event, this.note);

  final int partIndex;
  final ScorePart part;
  final ScoreEvent event;

  /// Null si es un silencio.
  final ScoreNote? note;
}

/// Correcciones de una partitura, con deshacer y rehacer.
///
/// Pensado para dejar bien una partitura grabada (o importada): cambiar la
/// altura de una nota, su figura, pasarla a la otra mano, borrarla o
/// convertir un silencio en nota. Cada corrección deja los compases
/// completos: lo que sobra se rellena con silencios y lo que no cabe se
/// rechaza con un [EditError].
///
/// Los ids de las notas que no se tocan no cambian; las nuevas reciben ids
/// que no existían.
class ScoreEditor {
  ScoreEditor(this._score) {
    _collectIds();
  }

  Score get score => _score;
  Score _score;

  final List<String> _undo = [];
  final List<String> _redo = [];
  final Set<String> _ids = {};
  int _next = 1;

  /// Cambia con cada corrección (también al deshacer y rehacer).
  int get revision => _revision;
  int _revision = 0;

  /// Correcciones hechas (sin contar las deshechas).
  bool get dirty => _undo.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _collectIds() {
    _ids.clear();
    for (final p in _score.parts) {
      for (final e in p.events) {
        _ids.add(e.id);
        for (final n in e.notes) {
          _ids.add(n.id);
        }
      }
    }
  }

  String _newId(String prefix) {
    while (true) {
      final id = '$prefix${_next++}x';
      if (_ids.add(id)) return id;
    }
  }

  // ---------------------------------------------------------------------
  // Buscar

  /// La nota (o el silencio) con este id.
  ScoreLocation? locate(String id) {
    for (final (pi, p) in _score.parts.indexed) {
      for (final e in p.events) {
        if (e.id == id) return ScoreLocation(pi, p, e, e.notes.isEmpty ? null : e.notes.first);
        for (final n in e.notes) {
          if (n.id == id) return ScoreLocation(pi, p, e, n);
        }
      }
    }
    return null;
  }

  /// Id que representa a un evento: su primera nota, o el propio evento si es
  /// un silencio.
  static String idOf(ScoreEvent e) => e.notes.isEmpty ? e.id : e.notes.first.id;

  /// Evento anterior o siguiente en el mismo pentagrama (para recorrer la
  /// partitura nota a nota). Null si no hay más.
  String? neighbor(String id, int direction) {
    final loc = locate(id);
    if (loc == null) return null;
    final list = [
      for (final e in loc.part.events)
        if (e.staff == loc.event.staff) e,
    ]..sort((a, b) => a.tick != b.tick ? a.tick - b.tick : a.voice - b.voice);
    final i = list.indexOf(loc.event);
    final j = i + direction;
    if (j < 0 || j >= list.length) return null;
    return idOf(list[j]);
  }

  /// Tonalidad de la armadura del compás de [tick].
  MusicKey keyAt(int tick) {
    final m = _score.measures[_score.measureAt(tick)];
    final major = (m.fifths * 7) % 12;
    return m.minor ? MusicKey(major + 9, Mode.minor) : MusicKey(major, Mode.major);
  }

  SpelledNote _spell(int midi, int tick) => keyAt(tick).spell(midi % 12);

  // ---------------------------------------------------------------------
  // Deshacer

  T _edit<T>(T Function() change) {
    final before = jsonEncode(_score.toJson());
    try {
      final out = change();
      _repairTies();
      _undo.add(before);
      if (_undo.length > 200) _undo.removeAt(0);
      _redo.clear();
      _revision++;
      return out;
    } on EditError {
      _restore(before);
      rethrow;
    }
  }

  void _restore(String json) {
    _score = Score.fromJson(jsonDecode(json) as Map<String, dynamic>);
    _collectIds();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(jsonEncode(_score.toJson()));
    _restore(_undo.removeLast());
    _revision++;
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(jsonEncode(_score.toJson()));
    _restore(_redo.removeLast());
    _revision++;
  }

  // ---------------------------------------------------------------------
  // Altura

  ScoreLocation _note(String id) {
    final loc = locate(id);
    if (loc == null) throw const EditError('Esa nota ya no está');
    if (loc.note == null) throw const EditError('Es un silencio: toca una tecla para poner una nota');
    return loc;
  }

  /// La nota y las ligadas a ella (se cambian juntas).
  List<ScoreNote> _tieChain(ScoreLocation loc) {
    final out = <ScoreNote>[loc.note!];
    final staff = loc.event.staff;
    var e = loc.event;
    var n = loc.note!;
    while (n.tieStop) {
      final prev = _partner(loc.part, staff, e, n, backwards: true);
      if (prev == null) break;
      (e, n) = prev;
      out.add(n);
    }
    e = loc.event;
    n = loc.note!;
    while (n.tieStart) {
      final next = _partner(loc.part, staff, e, n, backwards: false);
      if (next == null) break;
      (e, n) = next;
      out.add(n);
    }
    return out;
  }

  (ScoreEvent, ScoreNote)? _partner(ScorePart part, int staff, ScoreEvent e, ScoreNote n, {required bool backwards}) {
    for (final o in part.events) {
      if (o.staff != staff || o.grace || identical(o, e)) continue;
      if (backwards ? o.end != e.tick : o.tick != e.end) continue;
      for (final m in o.notes) {
        if (m.midi == n.midi && (backwards ? m.tieStart : m.tieStop)) return (o, m);
      }
    }
    return null;
  }

  void _setNote(ScoreNote n, int midi, SpelledNote spelling) {
    n
      ..midi = midi
      ..spelling = spelling
      ..octave = ChordStaff.octaveOf(midi, spelling);
  }

  void _checkRange(int midi) {
    if (midi < 21 || midi > 108) throw const EditError('Esa nota se sale del piano');
  }

  /// Cambia la altura de una nota (y de las ligadas a ella), escrita según
  /// la armadura.
  String setPitch(String id, int midi) => _edit(() {
    _checkRange(midi);
    final loc = _note(id);
    if (loc.event.notes.any((n) => n.midi == midi && !identical(n, loc.note))) {
      throw const EditError('Esa nota ya está en el acorde');
    }
    final chain = _tieChain(loc);
    final spelling = _spell(midi, loc.event.tick);
    for (final n in chain) {
      _setNote(n, midi, spelling);
    }
    _sortNotes(loc.event);
    return id;
  });

  /// Sube o baja una nota [semitones]; las octavas conservan la escritura.
  String transpose(String id, int semitones) {
    final loc = _note(id);
    final n = loc.note!;
    final midi = n.midi + semitones;
    if (semitones % 12 != 0) return setPitch(id, midi);
    return _edit(() {
      _checkRange(midi);
      if (loc.event.notes.any((o) => o.midi == midi)) throw const EditError('Esa nota ya está en el acorde');
      for (final c in _tieChain(loc)) {
        _setNote(c, midi, c.spelling);
      }
      _sortNotes(loc.event);
      return id;
    });
  }

  /// Escribe la misma altura con otra letra (F# ↔ Gb, E ↔ Fb…), una tras
  /// otra en cada llamada.
  String respell(String id) => _edit(() {
    final loc = _note(id);
    final n = loc.note!;
    final pc = n.midi % 12;
    final options = <SpelledNote>[];
    for (final limit in const [1, 2]) {
      for (var l = 0; l < 7; l++) {
        final s = SpelledNote.onLetter(l, pc);
        if (s.accidental.abs() <= limit && !options.any((o) => o.letter == s.letter)) options.add(s);
      }
      if (options.length >= 2) break;
    }
    options.sort(
      (a, b) =>
          a.accidental.abs() != b.accidental.abs() ? a.accidental.abs() - b.accidental.abs() : a.letter - b.letter,
    );
    if (options.length < 2) throw const EditError('Esa nota no tiene otra forma de escribirse');
    final i = options.indexWhere((o) => o.letter == n.spelling.letter);
    final next = options[(i + 1) % options.length];
    for (final c in _tieChain(loc)) {
      _setNote(c, c.midi, next);
    }
    return id;
  });

  /// Pone en el evento de [id] exactamente las notas [midis] (lo que se
  /// toca en el teclado): un silencio pasa a ser nota o acorde, y un acorde
  /// se reemplaza. Las notas que ya estaban conservan su id.
  String setPitches(String id, List<int> midis) => _edit(() {
    final loc = locate(id);
    if (loc == null) throw const EditError('Esa nota ya no está');
    final wanted = midis.toSet().toList()..sort();
    if (wanted.isEmpty) throw const EditError('No hay notas');
    for (final m in wanted) {
      _checkRange(m);
    }
    final e = loc.event;
    final keep = {for (final n in e.notes) n.midi: n};
    // Las que se van prestan su id a las nuevas (así la nota cambiada sigue
    // siendo la misma para el resto de la app).
    final freed = [
      for (final n in e.notes)
        if (!wanted.contains(n.midi)) n.id,
    ];
    final velocity = e.notes.isEmpty ? null : e.notes.first.velocity;
    e.notes = [
      for (final m in wanted)
        keep[m] ??
            () {
              final s = _spell(m, e.tick);
              return ScoreNote(
                id: freed.isNotEmpty ? freed.removeAt(0) : _newId('n'),
                midi: m,
                spelling: s,
                octave: ChordStaff.octaveOf(m, s),
                velocity: velocity,
              );
            }(),
    ];
    return e.notes.firstWhere((n) => n.id == id, orElse: () => e.notes.first).id;
  });

  /// Agrega una nota al acorde (o convierte el silencio en nota).
  String addNote(String id, int midi) {
    final loc = locate(id);
    if (loc == null) throw const EditError('Esa nota ya no está');
    if (loc.event.notes.any((n) => n.midi == midi)) throw const EditError('Esa nota ya está en el acorde');
    final ids = {for (final n in loc.event.notes) n.id};
    setPitches(id, [for (final n in loc.event.notes) n.midi, midi]);
    return loc.event.notes.firstWhere((n) => !ids.contains(n.id)).id;
  }

  /// Borra la nota: de un acorde se quita; si era sola queda un silencio.
  /// Devuelve lo que queda seleccionado.
  String delete(String id) => _edit(() {
    final loc = _note(id);
    final e = loc.event;
    if (e.notes.length > 1) {
      final i = e.notes.indexOf(loc.note!);
      e.notes.removeAt(i);
      return e.notes[i.clamp(0, e.notes.length - 1)].id;
    }
    if (e.grace) {
      loc.part.events.remove(e);
      final near = _nearest(loc.part, e.staff, e.tick);
      if (near == null) throw const EditError('No queda nada en ese pentagrama');
      return idOf(near);
    }
    e.notes = [];
    return e.id;
  });

  ScoreEvent? _nearest(ScorePart part, int staff, int tick) {
    ScoreEvent? best;
    for (final e in part.events) {
      if (e.staff != staff) continue;
      if (best == null || (e.tick - tick).abs() < (best.tick - tick).abs()) best = e;
    }
    return best;
  }

  // ---------------------------------------------------------------------
  // Figura

  /// Cambia la figura (y el puntillo). Al acortar queda un silencio; al
  /// alargar se come lo que sigue en la misma voz: silencios y notas
  /// enteras, y acorta la nota que quede a medias. No puede pasar de la
  /// barra de compás.
  String setDuration(String id, NoteType type, int dots) => _edit(() {
    final loc = locate(id);
    if (loc == null) throw const EditError('Esa nota ya no está');
    final e = loc.event;
    if (e.grace) throw const EditError('Las notas de adorno no tienen figura propia');
    if (e.tuplet != null) throw const EditError('No se puede cambiar la figura dentro de un tresillo');
    final m = _score.measures[_score.measureAt(e.tick)];
    final length = NoteType.dottedTicks(type, dots);
    final oldEnd = e.end;
    final end = e.tick + length;
    final part = loc.part;
    final stream = _stream(part, e, m);
    if (end > m.end) throw const EditError('No cabe: el compás se acaba antes');
    if (length < e.duration) {
      e.duration = length;
      part.events.addAll(_rests(e.staff, e.voice, end, oldEnd, m));
    } else if (length > e.duration) {
      for (final f in stream) {
        if (identical(f, e) || f.grace || f.tick < oldEnd || f.tick >= end) continue;
        if (f.end <= end) {
          part.events.remove(f);
          continue;
        }
        if (f.tuplet != null) throw const EditError('No cabe: lo que sigue es un tresillo');
        final left = f.end - end;
        if (f.isRest) {
          part.events.remove(f);
          part.events.addAll(_rests(e.staff, e.voice, end, f.end, m));
        } else {
          final written = NoteType.ofTicks(left);
          if (written == null) {
            throw const EditError('No cabe: la nota siguiente quedaría con una figura rara; acórtala primero');
          }
          f
            ..tick = end
            ..duration = left
            ..type = written.$1
            ..dots = written.$2;
        }
      }
      e.duration = length;
    }
    e
      ..type = type
      ..dots = dots;
    _clearBeams(part, e.staff, e.voice, m);
    _sortEvents(part);
    return id;
  });

  /// Eventos de la misma voz en el compás, por inicio.
  List<ScoreEvent> _stream(ScorePart part, ScoreEvent e, Measure m) => [
    for (final f in part.events)
      if (f.staff == e.staff && f.voice == e.voice && f.tick >= m.tick && f.tick < m.end) f,
  ]..sort((a, b) => a.tick - b.tick);

  void _clearBeams(ScorePart part, int staff, int voice, Measure m) {
    for (final f in part.events) {
      if (f.staff == staff && f.voice == voice && f.tick >= m.tick && f.tick < m.end) f.beams = const [];
    }
  }

  /// Silencios escribibles para [from, to) dentro del compás [m]: cada uno
  /// con la figura más larga alineada con su valor.
  List<ScoreEvent> _rests(int staff, int voice, int from, int to, Measure m) {
    final out = <ScoreEvent>[];
    if (from >= to) return out;
    if (from == m.tick && to == m.end) {
      return [ScoreEvent(id: _newId('r'), tick: from, duration: to - from, staff: staff, voice: voice, notes: [])];
    }
    var pos = from;
    while (pos < to) {
      final rel = pos - m.tick;
      NoteType? pick;
      for (final t in NoteType.values) {
        if (t.quarters > 4 || t.ticks > to - pos) continue;
        if (rel % t.ticks == 0) {
          pick = t;
          break;
        }
      }
      pick ??= NoteType.values.firstWhere((t) => t.ticks <= to - pos, orElse: () => NoteType.oneTwentyEighth);
      final len = pick.ticks <= to - pos ? pick.ticks : to - pos;
      out.add(ScoreEvent(id: _newId('r'), tick: pos, duration: len, staff: staff, voice: voice, notes: [], type: pick));
      pos += len;
    }
    return out;
  }

  void _sortEvents(ScorePart part) {
    final indexed = part.events.indexed.toList()
      ..sort((a, b) => a.$2.tick != b.$2.tick ? a.$2.tick - b.$2.tick : a.$1 - b.$1);
    part.events = [for (final (_, e) in indexed) e];
  }

  void _sortNotes(ScoreEvent e) => e.notes.sort((a, b) => a.midi - b.midi);

  // ---------------------------------------------------------------------
  // Mano

  /// Pasa la nota al otro pentagrama (mano derecha ↔ izquierda), en el mismo
  /// momento y con la misma figura: se suma al acorde que haya ahí, ocupa
  /// un silencio, o va en una voz nueva.
  String moveToStaff(String id, int staff) => _edit(() {
    final loc = _note(id);
    final part = loc.part;
    if (part.staves < 2) throw const EditError('Esta partitura tiene un solo pentagrama');
    if (staff < 1 || staff > part.staves || staff == loc.event.staff) throw const EditError('Ya está en esa mano');
    final e = loc.event;
    final n = loc.note!;
    n
      ..tieStart = false
      ..tieStop = false;
    // Quitarla de donde está.
    if (e.notes.length > 1) {
      e.notes.remove(n);
    } else if (e.grace) {
      part.events.remove(e);
    } else {
      e.notes = [];
    }
    final m = _score.measures[_score.measureAt(e.tick)];
    final start = e.tick;
    final end = e.end;
    // 1) Un evento que empieza y dura lo mismo en el otro pentagrama.
    for (final f in part.events) {
      if (f.staff == staff &&
          f.tick == start &&
          f.duration == e.duration &&
          f.grace == e.grace &&
          f.tuplet == e.tuplet) {
        if (f.notes.any((o) => o.midi == n.midi)) return idOf(f);
        f.notes.add(n);
        _sortNotes(f);
        return n.id;
      }
    }
    final copy = ScoreEvent(
      id: _newId('e'),
      tick: start,
      duration: e.duration,
      staff: staff,
      voice: 0,
      notes: [n],
      type: e.type,
      dots: e.dots,
      tuplet: e.tuplet,
      tupletSpan: e.tupletSpan,
      grace: e.grace,
    );
    // 2) Una voz que en ese tramo solo tiene silencios (o nada).
    final voices = {
      for (final f in part.events)
        if (f.staff == staff) f.voice,
    }.toList()..sort();
    if (!e.grace && e.tuplet == null) {
      for (final v in voices) {
        final over = [
          for (final f in part.events)
            if (f.staff == staff && f.voice == v && !f.grace && f.tick < end && f.end > start) f,
        ];
        if (!over.every((f) => f.isRest && f.tuplet == null)) continue;
        for (final r in over) {
          part.events.remove(r);
          part.events.addAll(_rests(staff, v, r.tick, start, m));
          part.events.addAll(_rests(staff, v, end, r.end, m));
        }
        copy.voice = v;
        part.events.add(copy);
        _clearBeams(part, staff, v, m);
        _sortEvents(part);
        return n.id;
      }
    }
    // 3) Una voz nueva, sin silencios de relleno.
    final used = {for (final f in part.events) f.voice};
    var v = staff == 1 ? 1 : 5;
    while (used.contains(v)) {
      v++;
    }
    copy.voice = v;
    part.events.add(copy);
    _sortEvents(part);
    return n.id;
  });

  // ---------------------------------------------------------------------
  // Cifrado

  /// Cifrado que hay en [tick] (en cualquier parte), o null.
  ChordSymbol? chordAt(int tick) {
    for (final p in _score.parts) {
      for (final c in p.chords) {
        if (c.tick == tick) return c;
      }
    }
    return null;
  }

  /// Escribe (o, con texto vacío, quita) el cifrado sobre [tick].
  void setChordSymbol(int tick, String text) => _edit(() {
    final t = text.trim();
    final chord = t.isEmpty ? null : ChordParser.parse(t);
    if (t.isNotEmpty && chord == null) throw EditError('No entiendo el cifrado "$t"');
    final existing = chordAt(tick);
    if (existing != null) {
      if (chord == null) {
        for (final p in _score.parts) {
          p.chords.remove(existing);
        }
      } else {
        existing
          ..chord = chord
          ..text = null;
      }
      return;
    }
    if (chord == null || _score.parts.isEmpty) return;
    final chords = _score.parts.first.chords
      ..add(ChordSymbol(tick: tick, chord: chord))
      ..sort((a, b) => a.tick - b.tick);
    _score.parts.first.chords = chords;
  });

  // ---------------------------------------------------------------------
  // Ligaduras

  /// Quita las ligaduras que quedaron sin pareja tras una corrección.
  void _repairTies() {
    for (final p in _score.parts) {
      final starts = <(int, int), List<ScoreEvent>>{};
      final ends = <(int, int), List<ScoreEvent>>{};
      for (final e in p.events) {
        if (e.grace) continue;
        (starts[(e.staff, e.tick)] ??= []).add(e);
        (ends[(e.staff, e.end)] ??= []).add(e);
      }
      bool hasNext(ScoreEvent e, ScoreNote n) =>
          (starts[(e.staff, e.end)] ?? const []).any((o) => o.notes.any((m) => m.midi == n.midi && m.tieStop));
      for (final e in p.events) {
        for (final n in e.notes) {
          if (n.tieStart && (e.grace || !hasNext(e, n))) n.tieStart = false;
        }
      }
      bool hasPrev(ScoreEvent e, ScoreNote n) =>
          (ends[(e.staff, e.tick)] ?? const []).any((o) => o.notes.any((m) => m.midi == n.midi && m.tieStart));
      for (final e in p.events) {
        for (final n in e.notes) {
          if (n.tieStop && (e.grace || !hasPrev(e, n))) n.tieStop = false;
        }
      }
    }
  }

  /// Nombre de la figura en español.
  static String figureName(NoteType type, int dots) {
    final base = switch (type) {
      NoteType.maxima => 'máxima',
      NoteType.long => 'longa',
      NoteType.breve => 'cuadrada',
      NoteType.whole => 'redonda',
      NoteType.half => 'blanca',
      NoteType.quarter => 'negra',
      NoteType.eighth => 'corchea',
      NoteType.sixteenth => 'semicorchea',
      NoteType.thirtySecond => 'fusa',
      NoteType.sixtyFourth => 'semifusa',
      NoteType.oneTwentyEighth => 'garrapatea',
    };
    return switch (dots) {
      0 => base,
      1 => '$base con puntillo',
      _ => '$base con doble puntillo',
    };
  }

  /// Figura escrita del evento (la guardada o la que sale de su duración).
  static (NoteType, int) writtenOf(ScoreEvent e) {
    if (e.type != null) return (e.type!, e.dots);
    var ticks = e.duration;
    final t = e.tuplet;
    if (t != null) ticks = (ticks * t.$1 / t.$2).round();
    return NoteType.ofTicks(ticks) ??
        (NoteType.values.firstWhere((x) => x.ticks <= ticks, orElse: () => NoteType.oneTwentyEighth), 0);
  }

  /// Altura escrita, como "Mi♭4" o "Eb4".
  static String pitchName(ScoreNote n, [Notation notation = Notation.american]) =>
      '${n.spelling.name(notation)}${n.octave}';
}
