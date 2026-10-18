import 'dart:convert';

import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

const ms = 1000;
const fmt = ChordFormatter();

List<Chord> chords(String text) => [for (final s in text.split(' ')) ChordParser.parse(s)!];

/// Toma MIDI que toca cada acorde en bloque durante 1 s.
Take takeOf(String text) {
  final events = <MidiEvent>[];
  var t = 0;
  for (final c in chords(text)) {
    final notes = [36 + (c.bass ?? c.root), for (final i in c.quality.intervals) 60 + c.root + i];
    for (final n in notes) {
      events.add(MidiEvent.noteOn(t * ms, n));
    }
    for (final n in notes) {
      events.add(MidiEvent.noteOff((t + 900) * ms, n));
    }
    t += 1000;
  }
  return Take(id: 't1', recordedAt: DateTime.utc(2026, 10, 18), events: events);
}

/// Toma con duración y silencio después de cada acorde: (cifrado, ms, pausa ms).
Take timedTake(List<(String, int, int)> plan) {
  final events = <MidiEvent>[];
  var t = 0;
  for (final (text, duration, pause) in plan) {
    final c = ChordParser.parse(text)!;
    final notes = [36 + (c.bass ?? c.root), for (final i in c.quality.intervals) 60 + c.root + i];
    for (final n in notes) {
      events.add(MidiEvent.noteOn(t * ms, n));
    }
    for (final n in notes) {
      events.add(MidiEvent.noteOff((t + duration - 50) * ms, n));
    }
    t += duration + pause;
  }
  return Take(id: 't', recordedAt: DateTime.utc(2026, 10, 18), events: events);
}

void main() {
  group('regiones de tonalidad', () {
    test('sin modulación: una sola región', () {
      final r = KeyAnalyzer.regions(chords('G D Em C G D C G Em C D G'));
      expect(r, hasLength(1));
      expect(r.single.key, MusicKey(7, Mode.major));
    });

    test('sube un tono en el último coro', () {
      final r = KeyAnalyzer.regions(
        chords('G C D G Em C D G G C D G A D E A F#m D E A A D E A'),
      );
      expect(r.map((x) => x.key), [MusicKey(7, Mode.major), MusicKey(9, Mode.major)]);
      expect(r.first.start, 0);
      expect(r.last.end, 24);
      expect(r.last.start, inInclusiveRange(11, 13));
    });

    test('la seguridad de la tonalidad principal se mide en su región', () {
      final song = SongAnalyzer.fromTake(
        title: 'Modula',
        take: takeOf('G C D G Em C D G G C D G Em C D G A D E A F#m D E A'),
      );
      expect(song.key, MusicKey(7, Mode.major));
      expect(song.keyRegions, hasLength(2));
      expect(song.keyConfidence, greaterThan(0.6));
    });

    test('pasar a la relativa menor no es modulación', () {
      final r = KeyAnalyzer.regions(
        chords('G D C G G D C G Em Bm C D Em Bm C D Em Bm C D Em Bm C D G D C G'),
      );
      expect(r, hasLength(1));
      expect(r.single.key, MusicKey(7, Mode.major));
    });

    test('un pasaje corto en otra tonalidad no es modulación', () {
      final r = KeyAnalyzer.regions(chords('D A Bm G D A G D E B C#m A D A G D A Bm G D'));
      expect(r, hasLength(1));
    });

    test('un préstamo aislado no es modulación', () {
      final r = KeyAnalyzer.regions(chords('C F G C Am F Bb C F G C'));
      expect(r, hasLength(1));
      expect(r.single.key, MusicKey(0, Mode.major));
    });
  });

  group('partes', () {
    List<ChordEvent> events(String text) => [for (final c in chords(text)) ChordEvent(chord: c)];

    List<String> order(PartDetection d) => [
          for (final o in d.arrangement)
            '${d.sections.firstWhere((s) => s.id == o.sectionId).label}'
                '${o.repeats > 1 ? ' ×${o.repeats}' : ''}',
        ];

    test('una progresión tocada dos veces seguidas es una parte ×2', () {
      final d = PartDetector.detect(events('G D Em C G D Em C Am F C G'));
      expect(order(d), ['Parte 1 ×2', 'Parte 2']);
      expect(d.arrangement.first.passLength, 4);
    });

    test('×N son solo las vueltas seguidas; si reaparece es otra sección', () {
      const verse = 'G D Em C G D Em C';
      const chorus = 'C G D Em C G D Em';
      final d = PartDetector.detect(events('$verse $chorus $verse $chorus $chorus'));
      expect(order(d), ['Parte 1 ×2', 'Parte 2 ×2', 'Parte 3 ×2', 'Parte 4 ×4']);
      expect(d.sections, hasLength(4));
    });

    test('una vuelta suelta de una progresión ya vista marca un cambio de patrón', () {
      final d = PartDetector.detect(events('G D Em C G D Em C C G D Am C G D Am G D Em C'));
      expect(order(d), ['Parte 1 ×2', 'Parte 2 ×2', 'Parte 3']);
    });

    test('una vuelta con un vaivén interno no se rompe', () {
      final d = PartDetector.detect(events('C G C G Am F C G C G C G Am F C G'));
      expect(order(d), ['Parte 1 ×2']);
      expect(d.arrangement.single.passLength, 8);
    });

    test('se queda con la vuelta más corta: G D G D G D = G D ×3', () {
      final d = PartDetector.detect(events('G D G D G D'));
      expect(order(d), ['Parte 1 ×3']);
      expect(d.arrangement.single.passLength, 2);
    });

    test('solo cuenta si la vuelta es idéntica', () {
      final d = PartDetector.detect(events('G D Em C G D Em D'));
      expect(d.arrangement.every((o) => o.repeats == 1), isTrue);
    });

    test('nunca nombra secciones con letras que parezcan tonalidades', () {
      final d = PartDetector.detect(events('E A B C#m G D Em C G D Em C B E'));
      for (final s in d.sections) {
        expect(MusicKey.parse(s.label), isNull, reason: s.label);
        expect(s.label, startsWith('Parte '));
      }
    });

    test('las partes cubren toda la canción', () {
      final list = events('E A B C#m G D Em C G D Em C B E');
      final d = PartDetector.detect(list);
      expect(d.arrangement.first.start, 0);
      expect(d.arrangement.last.end, d.chords.length);
      for (var i = 1; i < d.arrangement.length; i++) {
        expect(d.arrangement[i].start, d.arrangement[i - 1].end);
      }
    });

    test('una pausa empieza otra parte', () {
      final song = SongAnalyzer.fromTake(
        title: 'Pausa',
        take: timedTake([
          ('G', 1000, 0), ('C', 1000, 0), ('D', 1000, 0), ('Em', 1000, 2500),
          ('G', 1000, 0), ('C', 1000, 0), ('D', 1000, 0), ('Em', 1000, 0),
        ]),
      );
      // Sin la pausa sería "Parte 1 ×2"; con ella son dos partes.
      expect(song.arrangement, hasLength(2));
      expect(song.sections.map((s) => s.label), ['Parte 1', 'Parte 2']);
      expect(song.arrangement.map((o) => o.repeats), [1, 1]);
    });

    test('toma real: verso ×2 y luego coro, puente y cierre de 4 tiempos cada uno', () {
      // (cifrado, duración hasta el siguiente acorde en s, silencio antes en s)
      const plan = [
        ('D', 2.08, 2.67), ('A', 1.96, 0.37), ('Bm', 3.99, 0.39),
        ('D', 2.00, 0.39), ('A', 2.00, 0.46), ('Bm', 3.90, 0.47),
        ('G', 1.88, 0.73), ('A', 1.91, 0.26), ('D', 1.89, 0.54), ('D7', 1.89, 0.33),
        ('G', 1.93, 0.36), ('A', 1.86, 0.39), ('Bm', 0.95, 0.43), ('A', 0.95, 0.42),
        ('G', 3.72, 0.44), ('A', 1.89, 0.43), ('D', 1.63, 0.43), ('D5', 0.23, 0.0),
        ('D7', 2.62, 0.0), ('D', 0.48, 0.78),
      ];
      final list = [
        for (final (c, d, _) in plan)
          ChordEvent(chord: ChordParser.parse(c)!, durationMicros: (d * 1e6).round()),
      ];
      final d = PartDetector.detect(list, silenceBefore: [for (final (_, _, s) in plan) (s * 1e6).round()]);
      String pass(SectionOccurrence o) =>
          d.chords.sublist(o.start, o.start + o.passLength).map((c) => fmt.format(c.chord)).join(' ');
      expect(order(d), ['Parte 1 ×2', 'Parte 2', 'Parte 3', 'Parte 4']);
      expect(d.arrangement.map(pass), [
        'D A Bm',
        'G A D D7',
        'G A Bm A G',
        'G A D D7 D',
      ]);
    });

    test('la última vuelta cuenta aunque el acorde final se corte al detener', () {
      final list = [
        for (final (c, s) in [
          ('C', 1.7), ('D', 1.7), ('Em7', 3.4), ('C', 1.7), ('D', 1.7), ('Em7', 3.4),
          ('C', 1.7), ('D', 1.7), ('Em7', 3.4), ('C', 1.7), ('D', 1.7), ('Em7', 2.7),
        ])
          ChordEvent(chord: ChordParser.parse(c)!, durationMicros: (s * 1e6).round()),
      ];
      expect(order(PartDetector.detect(list)), ['Parte 1 ×4']);
    });

    test('un acorde sostenido entre dos vueltas se parte en ambas', () {
      // G C D G | G C D G con el G del cambio sostenido (un solo acorde de 2 s).
      final list = [
        for (final (c, ms) in [('G', 1000), ('C', 1000), ('D', 1000), ('G', 2000), ('C', 1000), ('D', 1000), ('G', 1000)])
          ChordEvent(chord: ChordParser.parse(c)!, durationMicros: ms * 1000),
      ];
      final d = PartDetector.detect(list);
      expect(order(d), ['Parte 1 ×2']);
      expect(d.chords.map((c) => fmt.format(c.chord)), ['G', 'C', 'D', 'G', 'G', 'C', 'D', 'G']);
      expect(d.chords[3].durationMicros, 1000 * ms);
    });
  });

  group('vueltas', () {
    Song songOf(String text, List<(int, int, int)> parts) {
      final song = Song.create(title: 'x')
        ..chords.addAll([for (final c in chords(text)) ChordEvent(chord: c)]);
      for (final (start, end, repeats) in parts) {
        final s = song.newSection(label: song.nextPartLabel());
        song
          ..sections.add(s)
          ..arrangement.add(SectionOccurrence(sectionId: s.id, start: start, end: end, repeats: repeats));
      }
      return song;
    }

    test('subir las vueltas copia la primera en la secuencia', () {
      final song = songOf('G D Em C Am F', [(0, 4, 1), (4, 6, 1)]);
      song.setRepeats(0, 2);
      expect(song.chords.map((c) => fmt.format(c.chord)), ['G', 'D', 'Em', 'C', 'G', 'D', 'Em', 'C', 'Am', 'F']);
      expect(song.arrangement.first.end, 8);
      expect(song.arrangement.last.start, 8);
      expect(song.chords[5].startMicros, isNull);
    });

    test('bajar las vueltas quita las últimas', () {
      final song = songOf('G D G D G D Am F', [(0, 6, 3), (6, 8, 1)]);
      song.setRepeats(0, 1);
      expect(song.chords, hasLength(4));
      expect(song.arrangement.last.start, 2);
    });

    test('partir en el inicio de una vuelta reparte las vueltas', () {
      final song = songOf('G D G D G D G D', [(0, 8, 4)]);
      song.startSectionAt(4, song.newSection(label: 'Coro'));
      expect(song.arrangement.map((o) => (o.start, o.end, o.repeats)), [(0, 4, 2), (4, 8, 2)]);
    });

    test('unir dos apariciones iguales suma las vueltas', () {
      final song = songOf('G D G D G D', [(0, 4, 2), (4, 6, 1)]);
      song.assignOccurrence(1, song.sections.first);
      song.mergeWithPrevious(1);
      expect(song.arrangement.single.repeats, 3);
    });

    test('borrar una sección quita sus acordes y ajusta lo demás', () {
      final song = songOf('E A G D Em C G D Em C', [(0, 2, 1), (2, 6, 1), (6, 10, 1)])
        ..keyRegions = [KeyRegion(start: 0, end: 10, key: MusicKey(7, Mode.major), confidence: 0.9)];
      song.removeOccurrence(0);
      expect(song.chords, hasLength(8));
      expect(song.arrangement.map((o) => (o.start, o.end)), [(0, 4), (4, 8)]);
      expect(song.sections, hasLength(2));
      expect(song.keyRegions.single.end, 8);
    });

    test('los tiempos anotados a mano se guardan', () {
      final song = songOf('D A Bm', [(0, 3, 1)]);
      song.chords[2].beats = 2;
      final back = Song.fromJson(song.toJson());
      expect(back.chords.map((c) => c.beats), [null, null, 2]);
      expect(back.arrangement.single.repeats, 1);
    });
  });

  group('canción', () {
    test('se reconstruye desde la toma MIDI', () {
      final song = SongAnalyzer.fromTake(
        title: 'Prueba',
        take: takeOf('G D/F# Em7 C G D/F# C G'),
      );
      expect([for (final c in song.chords) fmt.format(c.chord)],
          ['G', 'D/F#', 'Em7', 'C', 'G', 'D/F#', 'C', 'G']);
      expect(song.key, MusicKey(7, Mode.major));
      expect(song.keyConfidence, greaterThan(0.5));
      expect(song.chords.first.durationMicros, closeTo(1000 * ms, 100 * ms));
      expect(song.arrangement.fold<int>(0, (a, o) => a + o.length), 8);
    });

    test('json ida y vuelta conserva todo, incluso campos desconocidos', () {
      final song = SongAnalyzer.fromTake(title: 'Ida y vuelta', take: takeOf('D A Bm G D A G D'))
        ..lyrics = const SongLyrics(format: 'chordpro', text: '[D]Santo')
        ..transpose = 3
        ..sections.first.label = 'Coro'
        ..sections.first.kind = SectionKind.chorus;
      final json = jsonDecode(jsonEncode(song.toJson())) as Map<String, dynamic>;
      json['futureField'] = {'x': 1};

      final back = Song.fromJson(json);
      expect(back.title, 'Ida y vuelta');
      expect(back.key, song.key);
      expect(back.transpose, 3);
      expect(back.chords.map((c) => c.chord), song.chords.map((c) => c.chord));
      expect(back.takes.single.events.length, song.takes.single.events.length);
      expect(back.sections.first.kind, SectionKind.chorus);
      expect(back.lyrics?.text, '[D]Santo');
      expect(back.toJson()['futureField'], {'x': 1});
    });

    test('rechaza archivos que no son canciones', () {
      expect(() => Song.fromJson({'format': 'otro'}), throwsFormatException);
    });

    test('borrar un acorde ajusta las secciones', () {
      final song = Song.create(title: 'x')
        ..chords.addAll([for (final c in chords('C F G C Am F G C')) ChordEvent(chord: c)])
        ..sections.addAll([SectionDef(id: 's1', label: 'A'), SectionDef(id: 's2', label: 'B')])
        ..arrangement.addAll([
          SectionOccurrence(sectionId: 's1', start: 0, end: 4),
          SectionOccurrence(sectionId: 's2', start: 4, end: 8),
        ]);
      song.removeChordAt(1);
      expect(song.chords, hasLength(7));
      expect(song.arrangement.first.end, 3);
      expect(song.arrangement.last.start, 3);
      expect(song.arrangement.last.end, 7);
    });

    test('editar secciones: dividir, marcar repetición y unir', () {
      final song = Song.create(title: 'x')
        ..chords.addAll([for (final c in chords('G D Em C C G D G G D Em C C G D G')) ChordEvent(chord: c)]);
      song.ensureArrangement();
      expect(song.arrangement.single.length, 16);

      final verse = song.newSection(label: 'Verso', kind: SectionKind.verse);
      song.startSectionAt(0, verse);
      final chorus = song.newSection(label: 'Coro', kind: SectionKind.chorus);
      song.startSectionAt(4, chorus);
      song.startSectionAt(8, song.newSection(label: 'tmp'));
      song.assignOccurrence(2, verse);
      song.startSectionAt(12, chorus);

      List<String> order() => [for (final o in song.arrangement) song.section(o.sectionId)!.label];
      expect(order(), ['Verso', 'Coro', 'Verso', 'Coro']);
      expect([for (final o in song.arrangement) o.start], [0, 4, 8, 12]);
      expect(song.sections.map((s) => s.label), isNot(contains('tmp')));

      song.mergeWithPrevious(1);
      expect(order(), ['Verso', 'Verso', 'Coro']);
      expect(song.arrangement.first.end, 8);
    });

    test('quitar una modulación la fija frente a nuevos análisis', () {
      final song = SongAnalyzer.fromTake(
        title: 'Modula',
        take: takeOf('G C D G Em C D G G C D G Em C D G A D E A F#m D E A'),
      );
      expect(song.keyRegions, hasLength(2));
      song.removeModulation(1);
      expect(song.keyRegions, hasLength(1));
      expect(song.keyRegions.single.end, song.chords.length);
      SongAnalyzer.analyze(song, sections: false);
      expect(song.keyRegions, hasLength(1));
      final back = Song.fromJson(song.toJson());
      expect(back.keyRegionsManual, isTrue);
    });

    test('keyAt usa la región vigente', () {
      final song = Song.create(title: 'x')
        ..key = MusicKey(7, Mode.major)
        ..keyRegions = [
          KeyRegion(start: 0, end: 4, key: MusicKey(7, Mode.major), confidence: 0.9),
          KeyRegion(start: 4, end: 8, key: MusicKey(9, Mode.major), confidence: 0.9),
        ];
      expect(song.keyAt(2), MusicKey(7, Mode.major));
      expect(song.keyAt(5), MusicKey(9, Mode.major));
    });
  });
}
