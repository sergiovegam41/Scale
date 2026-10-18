import '../model/song.dart';
import '../theory/chord.dart';

class PartDetection {
  const PartDetection(this.chords, this.sections, this.arrangement);

  /// Acordes, con los sostenidos a través de un límite partidos en dos y los
  /// rozones de menos de un tercio de tiempo absorbidos por el anterior.
  final List<ChordEvent> chords;
  final List<SectionDef> sections;
  final List<SectionOccurrence> arrangement;
}

/// Propone partes objetivas ("Parte 1, 2, 3…") sin adivinar si son verso o
/// coro: eso lo decide el usuario.
///
/// 1. Una pausa (silencio ≥ umbral) empieza una parte nueva.
/// 2. Una progresión tocada dos o más veces seguidas, idéntica, es una sola
///    parte ×N (la menor progresión que se repite: G D G D G D = G D ×3).
/// 3. Donde la progresión deja de repetirse empieza otra parte; también donde
///    vuelve a sonar una vuelta de una progresión ya vista.
/// 4. Lo que queda sin repetir se corta en frases de la misma duración que la
///    vuelta repetida (si dura al menos 4 tiempos): en worship las partes
///    suelen durar lo mismo (verso, coro, puente y cierre de 4 tiempos).
/// 5. Cada parte es su propia sección (Parte 1, 2, 3…): ×N son solo las vueltas
///    seguidas; si la progresión reaparece más adelante, es otra sección.
///
/// El tiempo se mide en "tiempos" (la duración típica de un acorde en la
/// canción) con resolución de medio tiempo: así Bm½ A½ ocupan un tiempo, y un
/// acorde sostenido entre dos partes (el G que cierra una y abre la otra)
/// cuenta en ambas y se parte en dos acordes.
///
/// Dos acordes son "el mismo" si coinciden fundamental y bajo y la familia es
/// compatible: D = D5 = Dadd9 = Dsus2 (el mismo acorde con otra voz), pero
/// D ≠ Dm y D ≠ D/F#.
class PartDetector {
  const PartDetector._();

  /// Unidades por tiempo (2 = medio tiempo).
  static const int resolution = 2;
  static const int maxPatternUnits = 16 * resolution;

  /// Frase mínima (4 tiempos): una vuelta repetida más corta no sirve de medida.
  static const int defaultPhraseUnits = 4 * resolution;

  static const int defaultPauseMicros = 1500000;

  /// Un acorde de menos de esta fracción de tiempo es un roce al cambiar de
  /// acorde (soltar y volver a presionar), no un acorde.
  static const double flickFraction = 0.3;

  static bool sameChord(Chord a, Chord b) =>
      a.root == b.root &&
      (a.bass ?? a.root) == (b.bass ?? b.root) &&
      a.quality.family.compatibleWith(b.quality.family);

  /// [silenceBefore]: silencio (µs) antes de cada acorde, de [silencesBefore].
  static PartDetection detect(
    List<ChordEvent> input, {
    List<int>? silenceBefore,
    int pauseMicros = defaultPauseMicros,
  }) {
    if (input.isEmpty) return const PartDetection([], [], []);
    var (chords, silences) = _mergeRepeatedChords(input, silenceBefore, pauseMicros);
    final beat = _typicalSounding(chords, silences, pauseMicros);
    (chords, silences) = _absorbFlicks(chords, silences, beat);
    (chords, silences) = _mergeRepeatedChords(chords, silences, pauseMicros);

    final units = _units(chords, silences, beat, pauseMicros);
    final unitChords = [for (final u in units) chords[u.chord].chord];
    bool same(int a, int b, int length) {
      for (var i = 0; i < length; i++) {
        if (!sameChord(unitChords[a + i], unitChords[b + i])) return false;
      }
      return true;
    }

    // 1. Bloques separados por pausas.
    final blocks = <(int, int)>[];
    var blockStart = 0;
    for (var u = 1; u < units.length; u++) {
      if (units[u].sub == 0 && (silences?[units[u].chord] ?? 0) >= pauseMicros) {
        blocks.add((blockStart, u));
        blockStart = u;
      }
    }
    blocks.add((blockStart, units.length));

    // 2. Repeticiones seguidas dentro de cada bloque.
    final parts = <_Part>[];
    for (final (start, end) in blocks) {
      int? freeStart;
      var i = start;
      while (i < end) {
        final repeat = _tandem(i, end, unitChords, same);
        if (repeat == null) {
          freeStart ??= i;
          i++;
          continue;
        }
        if (freeStart != null) parts.add(_Part(freeStart, i, i - freeStart, 1));
        freeStart = null;
        parts.add(repeat);
        i = repeat.end;
      }
      if (freeStart != null) parts.add(_Part(freeStart, end, end - freeStart, 1));
    }

    // 3. Tramos sin repetir que contienen una vuelta de una progresión ya vista
    // (de al menos una frase, para no partir en fragmentos): ahí cambia el patrón.
    final known = [
      for (final p in parts)
        if (p.repeats > 1 && p.pass >= defaultPhraseUnits) (p.start, p.pass),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    var changed = true;
    while (changed) {
      changed = false;
      for (var k = 0; k < parts.length && !changed; k++) {
        final p = parts[k];
        if (p.repeats > 1 || p.fixed) continue;
        for (final (patternStart, length) in known) {
          if (length > p.length) continue;
          for (var at = p.start; at + length <= p.end; at++) {
            if (!same(at, patternStart, length)) continue;
            parts.replaceRange(k, k + 1, [
              if (at > p.start) _Part(p.start, at, at - p.start, 1),
              _Part(at, at + length, length, 1, fixed: true),
              if (at + length < p.end) _Part(at + length, p.end, p.end - at - length, 1),
            ]);
            changed = true;
            break;
          }
          if (changed) break;
        }
      }
    }

    // 4. Lo que queda sin repetir se corta en frases regulares.
    final phrase = _phraseLength(parts);
    for (var k = parts.length - 1; k >= 0 && phrase != null; k--) {
      final p = parts[k];
      if (p.repeats > 1 || p.fixed || p.length * 2 <= phrase * 3) continue;
      final chunks = <_Part>[];
      var at = p.start;
      while (p.end - at >= phrase) {
        chunks.add(_Part(at, at + phrase, phrase, 1));
        at += phrase;
      }
      final rest = p.end - at;
      if (rest > 0) {
        if (rest * 2 < phrase) {
          final last = chunks.removeLast();
          chunks.add(_Part(last.start, p.end, p.end - last.start, 1));
        } else {
          chunks.add(_Part(at, p.end, rest, 1));
        }
      }
      parts.replaceRange(k, k + 1, chunks);
    }

    // 5. Cada parte es su propia sección, numerada en orden.
    final sections = <SectionDef>[];
    String sectionFor(_Part p) {
      final def = SectionDef(id: 's${sections.length + 1}', label: 'Parte ${sections.length + 1}');
      sections.add(def);
      return def.id;
    }

    // Se parten los acordes sostenidos a través de un límite de vuelta o parte.
    final cuts = <int>{
      for (final p in parts) ...[
        for (var r = 0; r <= p.repeats; r++) p.start + r * p.pass,
      ],
    };
    final out = <ChordEvent>[];
    final unitToChord = List<int>.filled(units.length + 1, 0);
    var u = 0;
    for (var c = 0; c < chords.length; c++) {
      final event = chords[c];
      final count = units.where((x) => x.chord == c).length;
      var pieceStart = 0;
      for (var s = 1; s <= count; s++) {
        final atCut = s < count && cuts.contains(u + s);
        if (s < count && !atCut) continue;
        final index = out.length;
        out.add(_piece(event, pieceStart, s, count));
        for (var k = pieceStart; k < s; k++) {
          unitToChord[u + k] = index;
        }
        pieceStart = s;
      }
      u += count;
    }
    unitToChord[units.length] = out.length;

    final arrangement = <SectionOccurrence>[];
    for (final p in parts) {
      final start = unitToChord[p.start];
      final end = unitToChord[p.end];
      final repeats = (end - start) % p.repeats == 0 ? p.repeats : 1;
      arrangement.add(
        SectionOccurrence(sectionId: sectionFor(p), start: start, end: end, repeats: repeats),
      );
    }
    return PartDetection(out, sections, arrangement);
  }

  /// Silencio (µs) justo antes de cada acorde, a partir del MIDI crudo
  /// (el pedal cuenta como sonido).
  static List<int> silencesBefore(Take take, List<ChordEvent> chords) {
    final silences = <(int, int)>[]; // (inicio, fin)
    final held = <int>{};
    var pedal = false;
    var sustained = false;
    int? silentSince = 0;
    for (final e in take.events) {
      final wasSilent = held.isEmpty && !(pedal && sustained);
      if (e.isNoteOn) {
        held.add(e.data1);
        if (pedal) sustained = true;
      } else if (e.isNoteOff) {
        held.remove(e.data1);
      } else if (e.isSustain) {
        pedal = e.sustainDown;
        sustained = pedal && held.isNotEmpty;
      }
      final silent = held.isEmpty && !(pedal && sustained);
      if (silent && !wasSilent) silentSince = e.timeMicros;
      if (!silent && wasSilent && silentSince != null) {
        silences.add((silentSince, e.timeMicros));
        silentSince = null;
      }
    }
    final byEnd = {for (final (start, end) in silences) end: end - start};
    return [for (final c in chords) byEnd[c.startMicros] ?? 0];
  }

  /// La frase: la vuelta repetida (de al menos 4 tiempos) que más cubre. Sin
  /// una así la canción no muestra una estructura regular y no se corta: es
  /// mejor un tramo largo que el usuario divide que muchos fragmentos.
  static int? _phraseLength(List<_Part> parts) {
    _Part? best;
    for (final p in parts) {
      if (p.repeats > 1 && p.pass >= defaultPhraseUnits && (best == null || p.length > best.length)) {
        best = p;
      }
    }
    return best?.pass;
  }

  /// En una toma, el mismo acorde dos veces seguidas (sin pausa) es uno solo;
  /// sin duraciones (escrito o importado), "C | C" es intencional y se respeta.
  static (List<ChordEvent>, List<int>?) _mergeRepeatedChords(
    List<ChordEvent> chords,
    List<int>? silenceBefore,
    int pauseMicros,
  ) {
    final out = <ChordEvent>[];
    final silences = <int>[];
    for (var i = 0; i < chords.length; i++) {
      final c = chords[i];
      final silence = silenceBefore?[i] ?? 0;
      final a = out.isEmpty ? null : out.last.durationMicros;
      final b = c.durationMicros;
      if (a != null && b != null && out.last.chord == c.chord && silence < pauseMicros) {
        out.last = _withDuration(out.last, a + b, edited: c.edited);
        continue;
      }
      out.add(c);
      silences.add(silence);
    }
    return (out, silenceBefore == null ? null : silences);
  }

  /// Los roces (acordes de menos de [flickFraction] de tiempo) se suman al
  /// acorde anterior.
  static (List<ChordEvent>, List<int>?) _absorbFlicks(
    List<ChordEvent> chords,
    List<int>? silenceBefore,
    int? beat,
  ) {
    if (beat == null) return (chords, silenceBefore);
    final out = <ChordEvent>[];
    final silences = <int>[];
    for (var i = 0; i < chords.length; i++) {
      final c = chords[i];
      final d = c.durationMicros;
      // El último acorde no: su duración se corta al detener la grabación.
      final last = i == chords.length - 1;
      final flick = d != null && d < beat * flickFraction && !c.edited && !last;
      if (flick && out.isNotEmpty && out.last.durationMicros != null) {
        out.last = _withDuration(out.last, out.last.durationMicros! + d);
        continue;
      }
      out.add(c);
      silences.add(silenceBefore?[i] ?? 0);
    }
    return (out, silenceBefore == null ? null : silences);
  }

  static ChordEvent _withDuration(ChordEvent e, int duration, {bool edited = false}) => ChordEvent(
        chord: e.chord,
        startMicros: e.startMicros,
        durationMicros: duration,
        confidence: e.confidence,
        alternatives: List.of(e.alternatives),
        edited: e.edited || edited,
        symbol: e.symbol,
        lyric: e.lyric,
        beats: e.beats,
      );

  /// Duración musical de cada acorde: hasta el inicio del siguiente, sin
  /// contar una pausa que le siga (el respiro normal entre acordes sí cuenta).
  static int? _sounding(List<ChordEvent> chords, List<int>? silenceBefore, int i, int pauseMicros) {
    final d = chords[i].durationMicros;
    if (d == null) return null;
    final silence = i + 1 < chords.length ? (silenceBefore?[i + 1] ?? 0) : 0;
    return silence >= pauseMicros ? d - silence : d;
  }

  /// Duración típica de un acorde: un "tiempo". Es la más frecuente (el grupo
  /// de duraciones parecidas, ±15 %, con más acordes), no la mediana: así un
  /// tramo con otro ritmo no desajusta la medida del resto de la canción.
  static int? _typicalSounding(List<ChordEvent> chords, List<int>? silenceBefore, int pauseMicros) {
    final durations = [
      for (var i = 0; i < chords.length; i++)
        if ((_sounding(chords, silenceBefore, i, pauseMicros) ?? 0) > 0)
          _sounding(chords, silenceBefore, i, pauseMicros)!,
    ]..sort();
    if (durations.isEmpty) return null;
    List<int> near(int d) => [for (final x in durations) if ((x - d).abs() <= d * 0.15) x];
    var best = near(durations.first);
    for (final d in durations.skip(1)) {
      final cluster = near(d);
      if (cluster.length > best.length) best = cluster;
    }
    return best[best.length ~/ 2];
  }

  static List<_Unit> _units(List<ChordEvent> chords, List<int>? silenceBefore, int? beat, int pauseMicros) {
    int count(int i) {
      var d = _sounding(chords, silenceBefore, i, pauseMicros);
      if (d == null || beat == null || beat <= 0) return resolution;
      // El último acorde se corta al detener la grabación: se completa hasta
      // la duración más corta que tuvo ese mismo acorde y que no sea menor.
      if (i == chords.length - 1) {
        final longer = [
          for (var j = 0; j < i; j++)
            if (sameChord(chords[j].chord, chords[i].chord))
              if (_sounding(chords, silenceBefore, j, pauseMicros) case final s? when s >= d) s,
        ]..sort();
        if (longer.isNotEmpty) d = longer.first;
      }
      return (d * resolution / beat).round().clamp(1, 4 * resolution);
    }

    return [
      for (var i = 0; i < chords.length; i++)
        for (var s = 0; s < count(i); s++) _Unit(i, s),
    ];
  }

  /// La repetición seguida que más cubre desde [i]. Se descarta una vuelta
  /// formada enteramente por repeticiones menores: "V V C C" ×2 son en
  /// realidad V ×2 y C ×2.
  static _Part? _tandem(
    int i,
    int end,
    List<Chord> chords,
    bool Function(int, int, int) same, {
    bool allowComposite = false,
  }) {
    _Part? best;
    for (var length = 2; length <= maxPatternUnits && i + 2 * length <= end; length++) {
      if (chords.sublist(i, i + length).map((c) => c.root).toSet().length < 2) continue;
      var repeats = 1;
      while (i + (repeats + 1) * length <= end && same(i, i + repeats * length, length)) {
        repeats++;
      }
      if (repeats < 2) continue;
      // A igual cobertura se queda la progresión más corta (la vuelta básica).
      if (best != null && repeats * length <= best.length) continue;
      if (!allowComposite && _madeOfRepeats(i, i + length, chords, same)) continue;
      best = _Part(i, i + repeats * length, length, repeats);
    }
    return best;
  }

  static bool _madeOfRepeats(
    int start,
    int end,
    List<Chord> chords,
    bool Function(int, int, int) same,
  ) {
    var j = start;
    while (j < end) {
      final inner = _tandem(j, end, chords, same, allowComposite: true);
      if (inner == null) return false;
      j = inner.end;
    }
    return true;
  }

  static ChordEvent _piece(ChordEvent e, int from, int to, int count) {
    if (from == 0 && to == count) return e;
    final duration = e.durationMicros;
    final start = e.startMicros;
    return ChordEvent(
      chord: e.chord,
      startMicros: start == null || duration == null ? start : start + duration * from ~/ count,
      durationMicros: duration == null ? null : duration * (to - from) ~/ count,
      confidence: e.confidence,
      alternatives: List.of(e.alternatives),
      edited: e.edited,
      symbol: e.symbol,
      lyric: from == 0 ? e.lyric : null,
      beats: e.beats,
    );
  }
}

class _Unit {
  const _Unit(this.chord, this.sub);

  final int chord;
  final int sub;
}

class _Part {
  _Part(this.start, this.end, this.pass, this.repeats, {this.fixed = false});

  final int start;
  final int end;

  /// Unidades por vuelta.
  final int pass;
  final int repeats;

  /// Vuelta suelta de una progresión ya vista: no se vuelve a cortar.
  final bool fixed;

  int get length => end - start;
}
