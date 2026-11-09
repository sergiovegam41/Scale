import 'dart:convert';
import 'dart:io';

import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

/// Piano a dos pentagramas: acorde, ligadura entre compases, voz de la
/// izquierda con `<backup>`, cifrado y tempo.
const _piano = '''<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <work><work-title>Prueba</work-title></work>
  <identification><creator type="composer">Alguien</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>2</divisions>
        <key><fifths>1</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <staves>2</staves>
        <clef number="1"><sign>G</sign><line>2</line></clef>
        <clef number="2"><sign>F</sign><line>4</line></clef>
      </attributes>
      <direction><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>120</per-minute></metronome></direction-type><sound tempo="120"/></direction>
      <harmony><root><root-step>G</root-step></root><kind>major</kind></harmony>
      <note id="a1"><pitch><step>G</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice><type>half</type><staff>1</staff></note>
      <note id="a2"><chord/><pitch><step>B</step><octave>4</octave></pitch><duration>4</duration><voice>1</voice><type>half</type><staff>1</staff></note>
      <note id="a3"><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>4</duration><tie type="start"/><voice>1</voice><type>half</type><staff>1</staff></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>G</step><octave>2</octave></pitch><duration>8</duration><voice>5</voice><type>whole</type><staff>2</staff></note>
    </measure>
    <measure number="2">
      <harmony><root><root-step>D</root-step></root><kind>dominant</kind><bass><bass-step>F</bass-step><bass-alter>1</bass-alter></bass><offset>4</offset></harmony>
      <note id="b1"><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><duration>2</duration><tie type="stop"/><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
      <note><rest/><duration>4</duration><voice>1</voice><type>half</type><staff>1</staff></note>
      <backup><duration>8</duration></backup>
      <note><rest measure="yes"/><duration>8</duration><voice>5</voice><staff>2</staff></note>
    </measure>
  </part>
</score-partwise>''';

String _measures(List<String> bodies) => '''<?xml version="1.0"?>
<score-partwise version="4.0"><part-list><score-part id="P1"><part-name>x</part-name></score-part></part-list>
<part id="P1">${[
      for (final (i, body) in bodies.indexed)
        '<measure number="${i + 1}">${i == 0 ? '<attributes><divisions>1</divisions><time><beats>1</beats><beat-type>4</beat-type></time></attributes>' : ''}'
            '$body<note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type></note></measure>',
    ].join()}</part></score-partwise>''';

const _fwd = '<barline location="left"><repeat direction="forward"/></barline>';
const _back = '<barline location="right"><repeat direction="backward"/></barline>';
String _endStart(String n) => '<barline location="left"><ending number="$n" type="start"/></barline>';
String _endStop(String n, {bool repeat = false}) =>
    '<barline location="right"><ending number="$n" type="${repeat ? 'stop' : 'discontinue'}"/>${repeat ? '<repeat direction="backward"/>' : ''}</barline>';

void main() {
  group('MusicXmlReader', () {
    late Score score;
    setUp(() => score = MusicXmlReader.read(_piano, id: 's1'));

    test('título, compositor y compases', () {
      expect(score.title, 'Prueba');
      expect(score.composer, 'Alguien');
      expect(score.measures.length, 2);
      expect(score.measures[0].tick, 0);
      expect(score.measures[0].length, 4 * ticksPerQuarter);
      expect(score.measures[1].tick, 4 * ticksPerQuarter);
      expect(score.measures[0].fifths, 1);
      expect(score.measures[0].tempo, 120);
      expect(score.measures[0].time, TimeSignature.common);
    });

    test('dos pentagramas, acorde y voz con backup', () {
      final part = score.parts.single;
      expect(part.staves, 2);
      expect(part.clefs, [Clef.treble, Clef.bass]);
      final first = part.events.first;
      expect(first.notes.map((n) => n.midi), [67, 71]);
      expect(first.notes.first.id, 'a1');
      expect(first.duration, 2 * ticksPerQuarter);
      expect(first.type, NoteType.half);
      final bass = part.events.where((e) => e.staff == 2).first;
      expect(bass.tick, 0);
      expect(bass.notes.single.midi, 43);
      expect(bass.voice, 5);
    });

    test('ligadura, alteraciones y silencios', () {
      final part = score.parts.single;
      final fs = part.events.firstWhere((e) => e.notes.any((n) => n.id == 'a3')).notes.single;
      expect(fs.midi, 66);
      expect(fs.spelling, const SpelledNote(3, 1));
      expect(fs.tieStart, isTrue);
      final cont = part.events.firstWhere((e) => e.notes.any((n) => n.id == 'b1')).notes.single;
      expect(cont.tieStop, isTrue);
      expect(part.events.where((e) => e.isRest).length, 2);
    });

    test('cifrados con bajo y desplazamiento', () {
      final chords = score.parts.single.chords;
      expect(chords.length, 2);
      expect(chords[0].chord, Chord(7, ChordQuality.major));
      expect(chords[1].chord, Chord(2, ChordQuality.dominant7, bass: 6));
      expect(chords[1].tick, 4 * ticksPerQuarter + 2 * ticksPerQuarter);
    });

    test('rechaza lo que no es MusicXML', () {
      expect(() => MusicXmlReader.read('<html/>', id: 'x'), throwsFormatException);
      expect(() => MusicXmlReader.read('no xml', id: 'x'), throwsFormatException);
    });

    test('título desde el nombre de archivo si no hay otro', () {
      final s = MusicXmlReader.read(_measures(['']), id: 'x', fileName: 'C:/a/Mi pieza.musicxml');
      expect(s.title, 'Mi pieza');
    });
  });

  group('ScoreTimeline', () {
    test('une las notas ligadas y aplica el tempo', () {
      final t = ScoreTimeline.of(MusicXmlReader.read(_piano, id: 's1'));
      final fs = t.notes.firstWhere((n) => n.noteId == 'a3');
      expect(fs.start, 2 * ticksPerQuarter);
      expect(fs.end, 5 * ticksPerQuarter);
      expect(fs.tiedIds, ['a3', 'b1']);
      expect(t.notes.where((n) => n.midi == 66).length, 1);
      // 120 negras por minuto: 8 negras = 4 s.
      expect(t.duration, const Duration(seconds: 4));
      expect(t.tickAtMicros(1e6), 2 * ticksPerQuarter);
    });

    List<int> order(List<String> bodies) =>
        ScoreTimeline.unroll(MusicXmlReader.read(_measures(bodies), id: 'x').measures).map((m) => m.index).toList();

    test('repetición simple', () {
      expect(order(['', _fwd, _back, '']), [0, 1, 2, 1, 2, 3]);
    });

    test('repetición desde el principio sin signo de inicio', () {
      expect(order(['', _back, '']), [0, 1, 0, 1, 2]);
    });

    test('casillas de 1ª y 2ª vez', () {
      expect(order([_fwd, '', _endStart('1') + _endStop('1', repeat: true), _endStart('2') + _endStop('2'), '']),
          [0, 1, 2, 0, 1, 3, 4]);
    });

    test('dos repeticiones seguidas', () {
      expect(order([_fwd, _back, _fwd, _back]), [0, 1, 0, 1, 2, 3, 2, 3]);
    });

    test('casilla de varios compases', () {
      expect(order(['', _endStart('1'), _endStop('1', repeat: true), _endStart('2') + _endStop('2'), '']),
          [0, 1, 2, 0, 3, 4]);
    });
  });

  group('MusicXmlWriter', () {
    test('ida y vuelta conserva notas, ids, voces y ligaduras', () {
      final a = MusicXmlReader.read(_piano, id: 's1');
      final xml = MusicXmlWriter.write(a);
      final b = MusicXmlReader.read(xml, id: 's1');
      expect(b.title, a.title);
      expect(b.measures.map((m) => (m.tick, m.length, m.fifths)), a.measures.map((m) => (m.tick, m.length, m.fifths)));
      String sig(Score s) => [
            for (final e in s.parts.single.events)
              '${e.tick}/${e.duration}/${e.staff}/${e.voice}/${e.notes.map((n) => '${n.id}:${n.midi}:${n.tieStart}${n.tieStop}').join(',')}',
          ].join(' ');
      expect(sig(b).replaceAll(RegExp(r'n0_\d+'), '?'), sig(a).replaceAll(RegExp(r'n0_\d+'), '?'));
      expect(b.parts.single.chords.map((c) => c.chord), a.parts.single.chords.map((c) => c.chord));
      expect(b.measures[0].tempo, 120);
    });

    test('las ids de las notas van en el MusicXML', () {
      final xml = MusicXmlWriter.write(MusicXmlReader.read(_piano, id: 's1'));
      expect(xml, contains('id="a1"'));
      expect(xml, contains('id="b1"'));
    });

    test('alteraciones según armadura y compás', () {
      // En G mayor, F# no lleva alteración; F natural sí, y el siguiente F# la recupera.
      final score = Score(
        id: 'x',
        title: 'x',
        measures: [Measure(number: '1', tick: 0, length: 1920, time: TimeSignature.common, fifths: 1)],
        parts: [
          ScorePart(id: 'P1', name: 'p', events: [
            for (final (i, (letter, acc)) in [(3, 1), (3, 0), (3, 1), (3, 1)].indexed)
              ScoreEvent(
                id: 'e$i',
                tick: i * 480,
                duration: 480,
                staff: 1,
                voice: 1,
                notes: [
                  ScoreNote(id: 'n$i', midi: 65 + acc, spelling: SpelledNote(letter, acc), octave: 4),
                ],
              ),
          ]),
        ],
      );
      final xml = MusicXmlWriter.write(score);
      final accidentals = RegExp(r'<accidental>(\w+)</accidental>').allMatches(xml).map((m) => m[1]).toList();
      expect(accidentals, ['natural', 'sharp']);
    });

    test('barras: se conservan las escritas y se agrupan solas las que faltan', () {
      ScoreEvent eighth(int i, {List<String> beams = const []}) => ScoreEvent(
            id: 'e$i',
            tick: i * 240,
            duration: 240,
            staff: 1,
            voice: 1,
            type: NoteType.eighth,
            beams: beams,
            notes: [ScoreNote(id: 'n$i', midi: 60, spelling: const SpelledNote(0, 0), octave: 4)],
          );
      Score withEvents(List<ScoreEvent> events) => Score(
            id: 'x',
            title: 'x',
            measures: [Measure(number: '1', tick: 0, length: 1920, time: TimeSignature.common, fifths: 0)],
            parts: [ScorePart(id: 'P1', name: 'p', events: events)],
          );
      List<String?> beamsOf(String xml) => RegExp(r'<beam number="1">([a-z ]+)</beam>').allMatches(xml).map((m) => m[1]).toList();
      // Sin barras escritas: de dos en dos por negra.
      final auto = MusicXmlWriter.write(withEvents([for (var i = 0; i < 4; i++) eighth(i)]));
      expect(beamsOf(auto), ['begin', 'end', 'begin', 'end']);
      // Con barras escritas (cuatro juntas) se respetan.
      final kept = MusicXmlWriter.write(withEvents([
        for (var i = 0; i < 4; i++) eighth(i, beams: [i == 0 ? 'begin' : (i == 3 ? 'end' : 'continue')]),
      ]));
      expect(beamsOf(kept), ['begin', 'continue', 'continue', 'end']);
      final back = MusicXmlReader.read(kept, id: 'x');
      expect(back.parts.single.events.first.beams, ['begin']);
    });

    test('repeticiones y casillas sobreviven la ida y vuelta', () {
      final a = MusicXmlReader.read(
          _measures([_fwd, '', _endStart('1') + _endStop('1', repeat: true), _endStart('2') + _endStop('2'), '']),
          id: 'x');
      final b = MusicXmlReader.read(MusicXmlWriter.write(a), id: 'x');
      expect(ScoreTimeline.unroll(b.measures).map((m) => m.index), [0, 1, 2, 0, 1, 3, 4]);
    });
  });

  test('JSON ida y vuelta', () {
    final a = MusicXmlReader.read(_piano, id: 's1');
    final b = Score.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(b.toJson()), jsonEncode(a.toJson()));
    expect(b.noteCount, a.noteCount);
  });

  // Archivos reales: SCALE_MUSICXML_DIR apunta a una carpeta con partituras.
  final dir = Platform.environment['SCALE_MUSICXML_DIR'];
  if (dir != null) {
    test('archivos reales', () {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        final sw = Stopwatch()..start();
        final s = MusicXmlReader.readBytes(f.readAsBytesSync(), id: 'x', fileName: f.path);
        final t = ScoreTimeline.of(s);
        final xml = MusicXmlWriter.write(s);
        final back = MusicXmlReader.read(xml, id: 'x');
        print('${f.uri.pathSegments.last}: "${s.title}" ${s.parts.length} partes, ${s.measures.length} compases, '
            '${s.noteCount} notas, ${t.order.length} compases tocados, ${t.duration.inSeconds}s, '
            'ida y vuelta ${back.noteCount == s.noteCount ? 'ok' : 'DIFIERE ${back.noteCount}'} (${sw.elapsedMilliseconds} ms)');
      }
    });
  }
}
