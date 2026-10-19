import 'dart:math' as math;

import '../midi/midi_event.dart';
import '../theory/chord.dart';
import '../theory/key.dart';

/// Un acorde de la canción, en su tonalidad original (sin capa de transpose).
class ChordEvent {
  ChordEvent({
    required this.chord,
    this.startMicros,
    this.durationMicros,
    this.confidence,
    List<Chord>? alternatives,
    this.edited = false,
    this.symbol,
    this.lyric,
    this.beats,
  }) : alternatives = alternatives ?? [];

  /// Copia del acorde para una vuelta agregada a mano (sin tiempos de la toma).
  ChordEvent copyForRepeat() => ChordEvent(
        chord: chord,
        confidence: confidence,
        alternatives: List.of(alternatives),
        edited: edited,
        symbol: symbol,
        beats: beats,
      );

  factory ChordEvent.fromJson(Map<String, dynamic> json) => ChordEvent(
        chord: Chord.fromJson(json['chord'] as Map<String, dynamic>),
        startMicros: json['start'] as int?,
        durationMicros: json['duration'] as int?,
        confidence: (json['confidence'] as num?)?.toDouble(),
        alternatives: [
          for (final a in (json['alternatives'] as List?) ?? const [])
            Chord.fromJson(a as Map<String, dynamic>),
        ],
        edited: json['edited'] as bool? ?? false,
        symbol: json['symbol'] as String?,
        lyric: json['lyric'] as String?,
        beats: json['beats'] as int?,
      );

  Chord chord;

  /// Posición en la toma (null en canciones importadas sin tiempo).
  int? startMicros;
  int? durationMicros;

  /// Seguridad del reconocimiento (null si se escribió a mano o se importó).
  double? confidence;

  /// Otras lecturas posibles de las mismas notas, para corregir con un toque.
  List<Chord> alternatives;

  /// El usuario lo corrigió.
  bool edited;

  /// Texto original del cifrado al importar ("D/F#", "Re/Fa#").
  String? symbol;

  /// Fragmento de letra asociado (conector opcional, no es el centro).
  String? lyric;

  /// Tiempos que dura, anotados a mano (D' = 1, B'' = 2). Solo representativo:
  /// no lo usa ningún análisis todavía.
  int? beats;

  Map<String, dynamic> toJson() => {
        'chord': chord.toJson(),
        if (startMicros != null) 'start': startMicros,
        if (durationMicros != null) 'duration': durationMicros,
        if (confidence != null) 'confidence': double.parse(confidence!.toStringAsFixed(3)),
        if (alternatives.isNotEmpty) 'alternatives': [for (final a in alternatives) a.toJson()],
        if (edited) 'edited': true,
        if (symbol != null) 'symbol': symbol,
        if (lyric != null) 'lyric': lyric,
        if (beats != null) 'beats': beats,
      };
}

/// Grabación MIDI cruda: la fuente de verdad para volver a analizar.
class Take {
  Take({
    required this.id,
    required this.recordedAt,
    required this.events,
    this.inputTranspose = 0,
  });

  factory Take.fromJson(Map<String, dynamic> json) => Take(
        id: json['id'] as String,
        recordedAt: DateTime.parse(json['recordedAt'] as String).toLocal(),
        events: [for (final e in json['events'] as List) MidiEvent.fromJson(e as List)],
        inputTranspose: json['inputTranspose'] as int? ?? 0,
      );

  final String id;
  final DateTime recordedAt;

  /// Eventos con tiempo relativo al inicio de la toma.
  final List<MidiEvent> events;

  /// Capa de transpose digital activa al grabar (el piano ya enviaba las
  /// notas movidas; se resta para obtener la tonalidad original).
  final int inputTranspose;

  int get durationMicros => events.isEmpty ? 0 : events.last.timeMicros;

  Map<String, dynamic> toJson() => {
        'id': id,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
        if (inputTranspose != 0) 'inputTranspose': inputTranspose,
        'events': [for (final e in events) e.toJson()],
      };
}

/// Tramo de la canción en una tonalidad: acordes [start, end).
class KeyRegion {
  const KeyRegion({
    required this.start,
    required this.end,
    required this.key,
    required this.confidence,
  });

  factory KeyRegion.fromJson(Map<String, dynamic> json) => KeyRegion(
        start: json['start'] as int,
        end: json['end'] as int,
        key: MusicKey.fromJson(json['key'] as Map<String, dynamic>),
        confidence: (json['confidence'] as num).toDouble(),
      );

  final int start;
  final int end;
  final MusicKey key;
  final double confidence;

  int get length => end - start;

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'key': key.toJson(),
        'confidence': double.parse(confidence.toStringAsFixed(3)),
      };
}

enum SectionKind {
  intro('Intro'),
  verse('Verso'),
  preChorus('Pre-coro'),
  chorus('Coro'),
  bridge('Puente'),
  interlude('Interludio'),
  tag('Tag'),
  outro('Final'),
  other('Otra');

  const SectionKind(this.label);

  final String label;
}

/// Una sección distinta de la canción (Verso, Coro…).
class SectionDef {
  SectionDef({required this.id, required this.label, this.kind = SectionKind.other, this.note});

  factory SectionDef.fromJson(Map<String, dynamic> json) => SectionDef(
        id: json['id'] as String,
        label: json['label'] as String,
        kind: SectionKind.values.asNameMap()[json['kind']] ?? SectionKind.other,
        note: json['note'] as String?,
      );

  final String id;
  String label;
  SectionKind kind;

  /// Nota libre de apoyo ("Hacer adorno acá", "Cambio de ritmo"); se muestra
  /// al tocar en vivo mientras se está en esta sección.
  String? note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        if (note != null && note!.trim().isNotEmpty) 'note': note,
      };
}

/// Dónde aparece una sección en la secuencia lineal: acordes [start, end).
///
/// La secuencia lineal es la interpretación completa: una aparición ×2 contiene
/// las dos vueltas, cada una de [passLength] acordes.
class SectionOccurrence {
  SectionOccurrence({
    required this.sectionId,
    required this.start,
    required this.end,
    this.repeats = 1,
  });

  factory SectionOccurrence.fromJson(Map<String, dynamic> json) => SectionOccurrence(
        sectionId: json['section'] as String,
        start: json['start'] as int,
        end: json['end'] as int,
        repeats: json['repeats'] as int? ?? 1,
      );

  String sectionId;
  int start;
  int end;

  /// Vueltas seguidas de la misma progresión (×N).
  int repeats;

  int get length => end - start;
  int get passLength => repeats > 1 && length % repeats == 0 ? length ~/ repeats : length;

  /// Vuelta (1, 2…) a la que pertenece el acorde [index].
  int passOf(int index) => (index - start) ~/ passLength + 1;

  Map<String, dynamic> toJson() => {
        'section': sectionId,
        'start': start,
        'end': end,
        if (repeats > 1) 'repeats': repeats,
      };
}

/// Una aparición vista como sus vueltas (para editar todas a la vez).
class _Block {
  _Block(this.sectionId, this.passes);

  final String sectionId;
  final List<List<ChordEvent>> passes;
}

/// Letra opcional (por ejemplo importada de un cancionero).
class SongLyrics {
  const SongLyrics({required this.format, required this.text});

  factory SongLyrics.fromJson(Map<String, dynamic> json) =>
      SongLyrics(format: json['format'] as String, text: json['text'] as String);

  /// 'chordpro' o 'plain'.
  final String format;
  final String text;

  Map<String, dynamic> toJson() => {'format': format, 'text': text};
}

enum SongSource { midi, image, manual, import }

/// Una canción anotada.
///
/// La secuencia [chords] es lineal, tal como se tocó; [sections] y
/// [arrangement] son una capa encima para verla por secciones. Los campos
/// desconocidos de versiones futuras se conservan en [extra].
class Song {
  Song({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.source = SongSource.midi,
    List<Take>? takes,
    List<ChordEvent>? chords,
    this.key,
    this.keyConfidence,
    this.keyManual = false,
    List<KeyRegion>? keyRegions,
    this.keyRegionsManual = false,
    List<SectionDef>? sections,
    List<SectionOccurrence>? arrangement,
    this.transpose = 0,
    this.showOriginal = false,
    this.lyrics,
    Map<String, dynamic>? extra,
  })  : takes = takes ?? [],
        chords = chords ?? [],
        keyRegions = keyRegions ?? [],
        sections = sections ?? [],
        arrangement = arrangement ?? [],
        extra = extra ?? {};

  factory Song.create({required String title, SongSource source = SongSource.midi}) {
    final now = DateTime.now();
    return Song(id: newId(), title: title, createdAt: now, updatedAt: now, source: source);
  }

  static const String format = 'scale.song';
  static const int schemaVersion = 1;

  static const Set<String> _knownFields = {
    'format', 'schemaVersion', 'id', 'title', 'createdAt', 'updatedAt', 'source', 'takes',
    'chords', 'key', 'keyConfidence', 'keyManual', 'keyRegions', 'keyRegionsManual', 'sections',
    'arrangement',
    'transpose', 'showOriginal', 'lyrics',
  };

  factory Song.fromJson(Map<String, dynamic> json) {
    if (json['format'] != format) {
      throw FormatException('No es una canción de Scale (format=${json['format']})');
    }
    final version = json['schemaVersion'] as int? ?? 1;
    if (version > schemaVersion) {
      throw FormatException('Canción de una versión más nueva de Scale (v$version)');
    }
    List<T> list<T>(String field, T Function(Map<String, dynamic>) parse) => [
          for (final e in (json[field] as List?) ?? const []) parse(e as Map<String, dynamic>),
        ];
    return Song(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      source: SongSource.values.asNameMap()[json['source']] ?? SongSource.manual,
      takes: list('takes', Take.fromJson),
      chords: list('chords', ChordEvent.fromJson),
      key: json['key'] == null ? null : MusicKey.fromJson(json['key'] as Map<String, dynamic>),
      keyConfidence: (json['keyConfidence'] as num?)?.toDouble(),
      keyManual: json['keyManual'] as bool? ?? false,
      keyRegions: list('keyRegions', KeyRegion.fromJson),
      keyRegionsManual: json['keyRegionsManual'] as bool? ?? false,
      sections: list('sections', SectionDef.fromJson),
      arrangement: list('arrangement', SectionOccurrence.fromJson),
      transpose: json['transpose'] as int? ?? 0,
      showOriginal: json['showOriginal'] as bool? ?? false,
      lyrics: json['lyrics'] == null
          ? null
          : SongLyrics.fromJson(json['lyrics'] as Map<String, dynamic>),
      extra: {
        for (final e in json.entries)
          if (!_knownFields.contains(e.key)) e.key: e.value,
      },
    );
  }

  final String id;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  SongSource source;
  final List<Take> takes;
  final List<ChordEvent> chords;

  /// Tonalidad principal (la original: la de las figuras que se tocan).
  MusicKey? key;
  double? keyConfidence;

  /// La eligió el usuario; el análisis no la cambia.
  bool keyManual;
  List<KeyRegion> keyRegions;

  /// El usuario ajustó las modulaciones; el análisis no las recalcula.
  bool keyRegionsManual;
  List<SectionDef> sections;
  List<SectionOccurrence> arrangement;

  /// Capa de transpose digital en semitonos (lo que suena = original + capa).
  int transpose;

  /// Con transporte: mostrar las figuras originales en vez de lo que suena.
  bool showOriginal;
  SongLyrics? lyrics;
  final Map<String, dynamic> extra;

  static String newId() {
    final r = math.Random.secure();
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final noise = List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
    return '$stamp-$noise';
  }

  /// Tonalidad que suena con la capa de transpose (la original si es 0).
  MusicKey? get soundingKey => key?.transpose(transpose);

  /// Tonalidad vigente en el acorde [index] (considera modulaciones; si el
  /// usuario fijó la tonalidad y no hay modulaciones, manda la suya).
  MusicKey? keyAt(int index) {
    if (keyManual && keyRegions.length <= 1) return key;
    for (final r in keyRegions) {
      if (index >= r.start && index < r.end) return r.key;
    }
    return key;
  }

  SectionDef? section(String id) {
    for (final s in sections) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Ocurrencia que contiene el acorde [index].
  SectionOccurrence? occurrenceAt(int index) {
    for (final o in arrangement) {
      if (index >= o.start && index < o.end) return o;
    }
    return null;
  }

  /// Elimina un acorde manteniendo secciones y modulaciones (se ajustan los rangos).
  void removeChordAt(int index) {
    final o = occurrenceAt(index);
    // Al quitar un acorde de una vuelta, las vueltas dejan de ser iguales.
    if (o != null) o.repeats = 1;
    _removeRange(index, index + 1);
  }

  void _removeRange(int from, int to) {
    final n = to - from;
    if (n <= 0) return;
    chords.removeRange(from, to);
    int shift(int p) => p <= from ? p : (p >= to ? p - n : from);
    _remap(shift);
  }

  void _insertAt(int index, List<ChordEvent> events) {
    if (events.isEmpty) return;
    chords.insertAll(index, events);
    final n = events.length;
    _remap((p) => p >= index ? p + n : p);
  }

  /// Ajusta secciones y modulaciones a un cambio de posiciones.
  void _remap(int Function(int) position) {
    for (final o in arrangement) {
      o
        ..start = position(o.start)
        ..end = position(o.end);
    }
    arrangement.removeWhere((o) => o.length <= 0);
    _dropUnusedSections();
    keyRegions = [
      for (final r in keyRegions)
        if (position(r.end) > position(r.start))
          KeyRegion(
            start: position(r.start),
            end: position(r.end),
            key: r.key,
            confidence: r.confidence,
          ),
    ];
  }

  // ── Edición de secciones ─────────────────────────────────────────────

  /// Garantiza que las secciones cubran todos los acordes.
  void ensureArrangement() {
    if (chords.isEmpty || arrangement.isNotEmpty) return;
    final section = newSection(label: 'Parte 1');
    sections.add(section);
    arrangement.add(SectionOccurrence(sectionId: section.id, start: 0, end: chords.length));
  }

  /// Sección nueva (todavía sin agregar) con un id libre.
  SectionDef newSection({required String label, SectionKind kind = SectionKind.other}) {
    var n = sections.length + 1;
    while (sections.any((s) => s.id == 's$n')) {
      n++;
    }
    return SectionDef(id: 's$n', label: label, kind: kind);
  }

  /// Nombre libre del estilo "Parte N" para una sección nueva.
  String nextPartLabel() {
    var n = sections.length + 1;
    while (sections.any((s) => s.label == 'Parte $n')) {
      n++;
    }
    return 'Parte $n';
  }

  /// Empieza [section] en el acorde [index], partiendo la aparición que lo
  /// contiene. Si [index] ya es el inicio de una, solo se reasigna. Partir en
  /// el inicio de una vuelta reparte las vueltas; en medio de una, las anula.
  void startSectionAt(int index, SectionDef section) {
    ensureArrangement();
    if (!sections.any((s) => s.id == section.id)) sections.add(section);
    final i = arrangement.indexWhere((o) => index >= o.start && index < o.end);
    if (i < 0) return;
    final o = arrangement[i];
    if (o.start == index) {
      o.sectionId = section.id;
    } else {
      final offset = index - o.start;
      final atPass = o.repeats > 1 && offset % o.passLength == 0;
      final before = atPass ? offset ~/ o.passLength : 1;
      final after = atPass ? o.repeats - before : 1;
      arrangement.insert(
        i + 1,
        SectionOccurrence(sectionId: section.id, start: index, end: o.end, repeats: after),
      );
      o
        ..end = index
        ..repeats = before;
    }
    _dropUnusedSections();
  }

  /// Une la aparición [occurrence] con la anterior (queda la anterior). Si son
  /// la misma sección con vueltas idénticas, se suman las vueltas.
  void mergeWithPrevious(int occurrence) {
    if (occurrence <= 0 || occurrence >= arrangement.length) return;
    final a = arrangement[occurrence - 1];
    final b = arrangement[occurrence];
    final samePass = a.sectionId == b.sectionId &&
        a.passLength == b.passLength &&
        _equalChords(a.start, b.start, a.passLength);
    a
      ..repeats = samePass ? a.repeats + b.repeats : 1
      ..end = b.end;
    arrangement.removeAt(occurrence);
    _dropUnusedSections();
  }

  /// Borra la aparición [occurrence] con todos sus acordes (la toma MIDI
  /// original no se toca).
  void removeOccurrence(int occurrence) {
    final o = arrangement[occurrence];
    _removeRange(o.start, o.end);
  }

  /// Cambia las vueltas de una aparición. La secuencia lineal sigue siendo la
  /// interpretación completa: agregar vueltas copia la primera; quitarlas
  /// borra las últimas (la toma MIDI original no se toca). Si una aparición
  /// sin vueltas ya está hecha de [repeats] vueltas iguales, solo se agrupan.
  void setRepeats(int occurrence, int repeats) {
    final o = arrangement[occurrence];
    if (repeats < 1 || repeats == o.repeats) return;
    if (o.repeats == 1 && o.length % repeats == 0 && o.length > repeats) {
      final pass = o.length ~/ repeats;
      if ([for (var r = 1; r < repeats; r++) _equalChords(o.start, o.start + r * pass, pass)].every((e) => e)) {
        o.repeats = repeats;
        return;
      }
    }
    final pass = o.passLength;
    final current = o.length ~/ pass;
    if (repeats > current) {
      final firstPass = chords.sublist(o.start, o.start + pass);
      _insertAt(o.end, [
        for (var r = current; r < repeats; r++) ...firstPass.map((c) => c.copyForRepeat()),
      ]);
    } else {
      _removeRange(o.start + repeats * pass, o.end);
    }
    o.repeats = repeats;
  }

  bool _equalChords(int a, int b, int length) {
    if (a + length > chords.length || b + length > chords.length) return false;
    for (var i = 0; i < length; i++) {
      if (chords[a + i].chord != chords[b + i].chord) return false;
    }
    return true;
  }

  /// Marca la ocurrencia [occurrence] como repetición de [section].
  void assignOccurrence(int occurrence, SectionDef section) {
    if (!sections.any((s) => s.id == section.id)) sections.add(section);
    arrangement[occurrence].sectionId = section.id;
    _dropUnusedSections();
  }

  void _dropUnusedSections() =>
      sections.removeWhere((s) => !arrangement.any((o) => o.sectionId == s.id));

  // ── Edición por vueltas ──────────────────────────────────────────────
  //
  // Una aparición ×N se edita como una sola vuelta: lo que se cambia en la
  // vuelta se aplica a todas, así el ×N sigue siendo cierto.

  /// Posiciones lineales del acorde [offset] en cada vuelta de la aparición.
  List<int> passPositions(int occurrence, int offset) {
    final o = arrangement[occurrence];
    final pass = o.passLength;
    if (offset < 0 || offset >= pass) return const [];
    return [for (var p = 0; p < o.length ~/ pass; p++) o.start + p * pass + offset];
  }

  /// Inserta [event] en la posición [offset] de cada vuelta de la aparición.
  void insertChord(int occurrence, int offset, ChordEvent event) {
    final blocks = _blocks();
    for (final (k, pass) in blocks[occurrence].passes.indexed) {
      pass.insert(offset.clamp(0, pass.length), k == 0 ? event : event.copyForRepeat());
    }
    _setBlocks(blocks);
  }

  /// Quita el acorde [offset] de cada vuelta (si la aparición queda vacía,
  /// desaparece).
  void removeChord(int occurrence, int offset) {
    final blocks = _blocks();
    for (final pass in blocks[occurrence].passes) {
      if (offset >= 0 && offset < pass.length) pass.removeAt(offset);
    }
    _setBlocks(blocks);
  }

  /// Mueve un acorde de una vuelta a otra posición, en la misma sección o en
  /// otra. [toOffset] es la posición antes de quitarlo (insertar delante del
  /// acorde que hoy está ahí; igual al largo = al final).
  void moveChord(int fromOccurrence, int fromOffset, int toOccurrence, int toOffset) {
    if (fromOccurrence == toOccurrence && (toOffset == fromOffset || toOffset == fromOffset + 1)) return;
    final blocks = _blocks();
    final moved = [
      for (final pass in blocks[fromOccurrence].passes)
        if (fromOffset < pass.length) pass.removeAt(fromOffset),
    ];
    if (moved.isEmpty) return;
    var at = toOffset;
    if (fromOccurrence == toOccurrence && fromOffset < toOffset) at--;
    for (final (k, pass) in blocks[toOccurrence].passes.indexed) {
      pass.insert(at.clamp(0, pass.length), k < moved.length ? moved[k] : moved.first.copyForRepeat());
    }
    _setBlocks(blocks);
  }

  /// Cambia el orden de las apariciones: [from] queda en la posición [to].
  void moveOccurrence(int from, int to) {
    final blocks = _blocks();
    if (from < 0 || from >= blocks.length) return;
    blocks.insert(to.clamp(0, blocks.length - 1), blocks.removeAt(from));
    _setBlocks(blocks);
  }

  /// Copia la aparición justo después, como sección nueva con el mismo nombre
  /// y nota (cada aparición es su propia sección).
  void duplicateOccurrence(int occurrence) {
    final blocks = _blocks();
    final source = blocks[occurrence];
    final original = section(source.sectionId);
    final copy = newSection(label: original?.label ?? nextPartLabel(), kind: original?.kind ?? SectionKind.other)
      ..note = original?.note;
    sections.add(copy);
    blocks.insert(
      occurrence + 1,
      _Block(copy.id, [
        for (final pass in source.passes) [for (final e in pass) e.copyForRepeat()],
      ]),
    );
    _setBlocks(blocks);
  }

  /// Agrega una sección con los acordes de una vuelta ×[repeats], en la
  /// posición [at] del orden (al final si es null).
  void addSection(SectionDef section, List<ChordEvent> pass, {int repeats = 1, int? at}) {
    if (pass.isEmpty) return;
    final blocks = _blocks();
    if (!sections.any((s) => s.id == section.id)) sections.add(section);
    blocks.insert(
      (at ?? blocks.length).clamp(0, blocks.length),
      _Block(section.id, [
        pass,
        for (var r = 1; r < repeats; r++) [for (final e in pass) e.copyForRepeat()],
      ]),
    );
    _setBlocks(blocks);
  }

  /// Reemplaza la vuelta de una aparición (por ejemplo, escrita como texto).
  /// Los acordes que siguen igual conservan su lugar en la toma y su lectura;
  /// los tiempos anotados se toman de [pass]. Con [repeats] cambian las vueltas.
  void replacePass(int occurrence, List<ChordEvent> pass, {int? repeats}) {
    final blocks = _blocks();
    final block = blocks[occurrence];
    final old = block.passes.first;
    final match = _alignment([for (final e in old) e.chord], [for (final e in pass) e.chord]);
    final n = (repeats ?? block.passes.length).clamp(1, 64);
    final passes = <List<ChordEvent>>[
      for (var k = 0; k < n; k++)
        [
          for (final (j, e) in pass.indexed)
            if (match[j] case final i? when k < block.passes.length && i < block.passes[k].length)
              block.passes[k][i]..beats = e.beats
            else if (k == 0)
              e
            else
              e.copyForRepeat(),
        ],
    ];
    block.passes
      ..clear()
      ..addAll(passes);
    _setBlocks(blocks);
  }

  /// Empieza [second] en el acorde [offset] de cada vuelta: (A B) ×2 queda
  /// A B A B. Cada trozo es su propia sección; los de las otras vueltas
  /// llevan los mismos nombres. Sin vueltas es partir la sección en dos.
  void splitPasses(int occurrence, int offset, SectionDef second) {
    final blocks = _blocks();
    final block = blocks[occurrence];
    if (offset <= 0 || offset >= block.passes.first.length) return;
    if (!sections.any((s) => s.id == second.id)) sections.add(second);
    final first = section(block.sectionId);
    SectionDef copyOf(SectionDef? s, SectionDef fallback) {
      final copy = newSection(label: (s ?? fallback).label, kind: (s ?? fallback).kind)..note = s?.note;
      sections.add(copy);
      return copy;
    }

    final pieces = <_Block>[];
    for (final (k, pass) in block.passes.indexed) {
      final a = k == 0 ? block.sectionId : copyOf(first, second).id;
      final b = k == 0 ? second.id : copyOf(second, second).id;
      pieces
        ..add(_Block(a, [pass.sublist(0, offset)]))
        ..add(_Block(b, [pass.sublist(offset)]));
    }
    blocks.replaceRange(occurrence, occurrence + 1, pieces);
    _setBlocks(blocks);
  }

  /// Separa las vueltas: la aparición queda ×1 con todos sus acordes a la vista.
  void ungroup(int occurrence) => arrangement[occurrence].repeats = 1;

  /// Para cada acorde de [b], el índice del mismo acorde en [a] según la
  /// subsecuencia común más larga (null si es nuevo).
  static List<int?> _alignment(List<Chord> a, List<Chord> b) {
    final dp = List.generate(a.length + 1, (_) => List<int>.filled(b.length + 1, 0));
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : math.max(dp[i + 1][j], dp[i][j + 1]);
      }
    }
    final result = List<int?>.filled(b.length, null);
    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        result[j] = i;
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    return result;
  }

  List<_Block> _blocks() {
    ensureArrangement();
    return [
      for (final o in arrangement)
        _Block(o.sectionId, [
          if (o.repeats > 1 && o.length % o.repeats == 0)
            for (var p = 0; p < o.repeats; p++)
              chords.sublist(o.start + p * o.passLength, o.start + (p + 1) * o.passLength)
          else
            chords.sublist(o.start, o.end),
        ]),
    ];
  }

  /// Vuelve a armar la secuencia lineal desde las vueltas. Las modulaciones
  /// siguen al acorde con el que empezaban (o al siguiente que quede).
  void _setBlocks(List<_Block> blocks) {
    final old = List.of(chords);
    chords.clear();
    arrangement.clear();
    for (final b in blocks) {
      final passes = b.passes.where((p) => p.isNotEmpty).toList();
      if (passes.isEmpty) continue;
      final start = chords.length;
      for (final p in passes) {
        chords.addAll(p);
      }
      final equal = passes.every((p) => p.length == passes.first.length);
      arrangement.add(SectionOccurrence(
        sectionId: b.sectionId,
        start: start,
        end: chords.length,
        repeats: equal ? passes.length : 1,
      ));
    }
    _dropUnusedSections();

    final index = Map<ChordEvent, int>.identity();
    for (final (i, e) in chords.indexed) {
      index[e] = i;
    }
    final starts = <(int, KeyRegion)>[];
    for (final r in keyRegions) {
      for (var i = r.start; i < r.end && i < old.length; i++) {
        final at = index[old[i]];
        if (at != null) {
          starts.add((at, r));
          break;
        }
      }
    }
    starts.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, KeyRegion)>[];
    for (final s in starts) {
      if (merged.isNotEmpty && (merged.last.$1 == s.$1 || merged.last.$2.key == s.$2.key)) continue;
      merged.add(s);
    }
    keyRegions = [
      for (final (i, (start, r)) in merged.indexed)
        KeyRegion(
          start: i == 0 ? 0 : start,
          end: i + 1 < merged.length ? merged[i + 1].$1 : chords.length,
          key: r.key,
          confidence: r.confidence,
        ),
    ];
  }

  // ── Deshacer ─────────────────────────────────────────────────────────

  /// Todo lo editable (sin las tomas MIDI), para deshacer y rehacer.
  Map<String, dynamic> editState() => {
        'title': title,
        if (key != null) 'key': key!.toJson(),
        if (keyConfidence != null) 'keyConfidence': keyConfidence,
        'keyManual': keyManual,
        'chords': [for (final c in chords) c.toJson()],
        'keyRegions': [for (final r in keyRegions) r.toJson()],
        'keyRegionsManual': keyRegionsManual,
        'sections': [for (final s in sections) s.toJson()],
        'arrangement': [for (final o in arrangement) o.toJson()],
      };

  void restoreEditState(Map<String, dynamic> state) {
    List<T> list<T>(String field, T Function(Map<String, dynamic>) parse) => [
          for (final e in (state[field] as List?) ?? const []) parse(e as Map<String, dynamic>),
        ];
    title = state['title'] as String;
    key = state['key'] == null ? null : MusicKey.fromJson(state['key'] as Map<String, dynamic>);
    keyConfidence = (state['keyConfidence'] as num?)?.toDouble();
    keyManual = state['keyManual'] as bool;
    chords
      ..clear()
      ..addAll(list('chords', ChordEvent.fromJson));
    keyRegions = list('keyRegions', KeyRegion.fromJson);
    keyRegionsManual = state['keyRegionsManual'] as bool;
    sections = list('sections', SectionDef.fromJson);
    arrangement = list('arrangement', SectionOccurrence.fromJson);
  }

  // ── Modulaciones ─────────────────────────────────────────────────────

  /// Quita la modulación que empieza la región [region]: se une a la anterior
  /// y las modulaciones quedan fijadas por el usuario.
  void removeModulation(int region) {
    if (region <= 0 || region >= keyRegions.length) return;
    final previous = keyRegions[region - 1];
    keyRegions = [
      ...keyRegions.take(region - 1),
      KeyRegion(
        start: previous.start,
        end: keyRegions[region].end,
        key: previous.key,
        confidence: previous.confidence,
      ),
      ...keyRegions.skip(region + 1),
    ];
    keyRegionsManual = true;
  }

  Map<String, dynamic> toJson() => {
        'format': format,
        'schemaVersion': schemaVersion,
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'source': source.name,
        if (key != null) 'key': key!.toJson(),
        if (keyConfidence != null) 'keyConfidence': double.parse(keyConfidence!.toStringAsFixed(3)),
        if (keyManual) 'keyManual': true,
        'transpose': transpose,
        if (showOriginal) 'showOriginal': true,
        'chords': [for (final c in chords) c.toJson()],
        'keyRegions': [for (final r in keyRegions) r.toJson()],
        if (keyRegionsManual) 'keyRegionsManual': true,
        'sections': [for (final s in sections) s.toJson()],
        'arrangement': [for (final o in arrangement) o.toJson()],
        if (lyrics != null) 'lyrics': lyrics!.toJson(),
        'takes': [for (final t in takes) t.toJson()],
        ...extra,
      };
}
