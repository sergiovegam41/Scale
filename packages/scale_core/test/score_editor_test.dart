import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

const _q = ticksPerQuarter;

ScoreNote _n(String id, int midi, {bool tieStart = false, bool tieStop = false}) {
  final s = SpelledNote.byDefault(midi % 12);
  return ScoreNote(
    id: id,
    midi: midi,
    spelling: s,
    octave: ChordStaff.octaveOf(midi, s),
    tieStart: tieStart,
    tieStop: tieStop,
  );
}

ScoreEvent _e(String id, int tick, int dur, List<ScoreNote> notes, {int staff = 1, NoteType? type}) =>
    ScoreEvent(id: id, tick: tick, duration: dur, staff: staff, voice: staff == 1 ? 1 : 5, notes: notes, type: type);

/// Dos compases de 4/4. Derecha: Do Re Mi Fa | Sol (blanca, ligada) Sol
/// (negra) silencio. Izquierda: Do redonda | silencio de compás.
Score sample({int fifths = 0}) => Score(
  id: 's',
  title: 'Prueba',
  measures: [
    for (var m = 0; m < 2; m++)
      Measure(number: '${m + 1}', tick: m * 4 * _q, length: 4 * _q, time: TimeSignature.common, fifths: fifths),
  ],
  parts: [
    ScorePart(
      id: 'P1',
      name: 'Piano',
      staves: 2,
      events: [
        _e('e0', 0, _q, [_n('n0', 60)], type: NoteType.quarter),
        _e('l0', 0, 4 * _q, [_n('nl0', 48)], staff: 2, type: NoteType.whole),
        _e('e1', _q, _q, [_n('n1', 62)], type: NoteType.quarter),
        _e('e2', 2 * _q, _q, [_n('n2', 64)], type: NoteType.quarter),
        _e('e3', 3 * _q, _q, [_n('n3', 65)], type: NoteType.quarter),
        _e('e4', 4 * _q, 2 * _q, [_n('n4', 67, tieStart: true)], type: NoteType.half),
        _e('l1', 4 * _q, 4 * _q, [], staff: 2),
        _e('e5', 6 * _q, _q, [_n('n5', 67, tieStop: true)], type: NoteType.quarter),
        _e('e6', 7 * _q, _q, [], type: NoteType.quarter),
      ],
    ),
  ],
);

/// Cada voz de cada compás suma lo que dura el compás (o tiene huecos sin
/// solaparse).
void expectWellFormed(Score s) {
  for (final p in s.parts) {
    for (final m in s.measures) {
      final streams = <(int, int), List<ScoreEvent>>{};
      for (final e in p.events) {
        if (e.tick >= m.tick && e.tick < m.end && !e.grace) (streams[(e.staff, e.voice)] ??= []).add(e);
      }
      for (final list in streams.values) {
        list.sort((a, b) => a.tick - b.tick);
        for (var i = 0; i + 1 < list.length; i++) {
          expect(
            list[i].end,
            lessThanOrEqualTo(list[i + 1].tick),
            reason: 'se solapan ${list[i].id} y ${list[i + 1].id}',
          );
        }
        expect(list.last.end, lessThanOrEqualTo(m.end));
      }
    }
  }
  // Y se puede escribir y volver a leer.
  final xml = MusicXmlWriter.write(s);
  final back = MusicXmlReader.read(xml, id: 'x');
  expect(back.measures.length, s.measures.length);
}

List<ScoreEvent> right(ScoreEditor ed, int measure) {
  final m = ed.score.measures[measure];
  return [
    for (final e in ed.score.parts.first.events)
      if (e.staff == 1 && e.tick >= m.tick && e.tick < m.end) e,
  ]..sort((a, b) => a.tick - b.tick);
}

void main() {
  group('altura', () {
    test('cambiar la nota la escribe según la armadura', () {
      final ed = ScoreEditor(sample(fifths: -1)); // Fa mayor
      ed.setPitch('n3', 70);
      final n = ed.locate('n3')!.note!;
      expect(n.midi, 70);
      expect(n.spelling.name(), 'Bb');
      expect(n.octave, 4);
      expectWellFormed(ed.score);
    });

    test('las notas ligadas cambian juntas', () {
      final ed = ScoreEditor(sample());
      ed.transpose('n5', -2);
      expect(ed.locate('n4')!.note!.midi, 65);
      expect(ed.locate('n5')!.note!.midi, 65);
      expect(ed.locate('n4')!.note!.tieStart, isTrue);
    });

    test('la octava conserva la escritura y el enarmónico va y vuelve', () {
      final ed = ScoreEditor(sample());
      ed.setPitch('n0', 61);
      final first = ed.locate('n0')!.note!.spelling.name();
      ed.respell('n0');
      final second = ed.locate('n0')!.note!.spelling.name();
      expect({first, second}, {'C#', 'Db'});
      ed.transpose('n0', 12);
      expect(ed.locate('n0')!.note!.spelling.name(), second);
      expect(ed.locate('n0')!.note!.octave, 5);
    });

    test('tocar teclas sobre un silencio pone las notas; sobre un acorde lo reemplaza', () {
      final ed = ScoreEditor(sample());
      final id = ed.setPitches('e6', [72, 76]);
      final e = ed.locate('e6')!.event;
      expect([for (final n in e.notes) n.midi], [72, 76]);
      expect(e.notes.first.id, id);
      // Se conserva el id de la nota que sigue.
      final keep = e.notes.last.id;
      ed.setPitches(id, [74, 76]);
      expect([for (final n in e.notes) n.midi], [74, 76]);
      expect(e.notes.last.id, keep);
      expectWellFormed(ed.score);
    });

    test('agregar una nota al acorde', () {
      final ed = ScoreEditor(sample());
      final id = ed.addNote('n2', 67);
      expect(ed.locate(id)!.note!.midi, 67);
      expect(ed.locate('n2')!.event.notes.length, 2);
      expect(() => ed.addNote('n2', 64), throwsA(isA<EditError>()));
    });

    test('fuera del piano no se puede', () {
      final ed = ScoreEditor(sample());
      expect(() => ed.transpose('n0', -48), throwsA(isA<EditError>()));
      expect(ed.canUndo, isFalse);
    });
  });

  group('borrar', () {
    test('una nota sola deja un silencio y suelta la ligadura', () {
      final ed = ScoreEditor(sample());
      expect(ed.delete('n5'), 'e5');
      expect(ed.locate('e5')!.event.isRest, isTrue);
      expect(ed.locate('n4')!.note!.tieStart, isFalse);
      expectWellFormed(ed.score);
    });

    test('de un acorde solo se quita esa nota', () {
      final ed = ScoreEditor(sample());
      final added = ed.addNote('n1', 65);
      ed.delete(added);
      expect([for (final n in ed.locate('n1')!.event.notes) n.midi], [62]);
    });
  });

  group('figura', () {
    test('acortar deja un silencio detrás', () {
      final ed = ScoreEditor(sample());
      ed.setDuration('n1', NoteType.eighth, 0);
      final r = right(ed, 0);
      expect([for (final e in r) e.tick], [0, _q, _q + _q ~/ 2, 2 * _q, 3 * _q]);
      expect(r[2].isRest, isTrue);
      expect(r[2].type, NoteType.eighth);
      expectWellFormed(ed.score);
    });

    test('alargar se come la nota siguiente', () {
      final ed = ScoreEditor(sample());
      ed.setDuration('n0', NoteType.half, 0);
      expect(ed.locate('n1'), isNull);
      expect([for (final e in right(ed, 0)) e.duration], [2 * _q, _q, _q]);
      expectWellFormed(ed.score);
    });

    test('con puntillo, la siguiente queda más corta', () {
      final ed = ScoreEditor(sample());
      ed.setDuration('n0', NoteType.quarter, 1);
      final next = ed.locate('n1')!.event;
      expect(next.tick, _q + _q ~/ 2);
      expect(next.duration, _q ~/ 2);
      expect(next.type, NoteType.eighth);
      expectWellFormed(ed.score);
    });

    test('no pasa de la barra de compás', () {
      final ed = ScoreEditor(sample());
      expect(() => ed.setDuration('n3', NoteType.half, 0), throwsA(isA<EditError>()));
      expect(ed.locate('n3')!.event.duration, _q);
      expect(ed.canUndo, isFalse);
    });

    test('acortar una nota ligada suelta la ligadura', () {
      final ed = ScoreEditor(sample());
      ed.setDuration('n4', NoteType.quarter, 0);
      expect(ed.locate('n4')!.note!.tieStart, isFalse);
      expect(ed.locate('n5')!.note!.tieStop, isFalse);
      expectWellFormed(ed.score);
    });
  });

  group('mano', () {
    test('pasar a la izquierda ocupa un silencio', () {
      final ed = ScoreEditor(sample());
      final id = ed.moveToStaff('n5', 2);
      final e = ed.locate(id)!.event;
      expect(e.staff, 2);
      expect(e.voice, 5);
      expect(e.tick, 6 * _q);
      expect(ed.locate('e5')!.event.isRest, isTrue);
      expect(ed.locate('n4')!.note!.tieStart, isFalse);
      // El silencio de compás se partió alrededor.
      final left = [
        for (final x in ed.score.parts.first.events)
          if (x.staff == 2 && x.tick >= 4 * _q) x,
      ];
      expect([for (final x in left) x.duration], [2 * _q, _q, _q]);
      expectWellFormed(ed.score);
    });

    test('si no hay hueco va en una voz nueva', () {
      final ed = ScoreEditor(sample());
      final id = ed.moveToStaff('n2', 2);
      final e = ed.locate(id)!.event;
      expect(e.staff, 2);
      expect(e.voice, 6);
      expectWellFormed(ed.score);
    });

    test('se suma a un acorde que empieza y dura lo mismo', () {
      final ed = ScoreEditor(sample());
      ed.setDuration('n0', NoteType.whole, 0);
      ed.moveToStaff('n0', 2);
      expect([for (final n in ed.locate('nl0')!.event.notes) n.midi], [48, 60]);
    });
  });

  test('deshacer y rehacer', () {
    final ed = ScoreEditor(sample());
    final r0 = ed.revision;
    ed.setPitch('n0', 59);
    ed.setDuration('n1', NoteType.eighth, 0);
    expect(ed.revision, r0 + 2);
    ed.undo();
    expect(ed.locate('n1')!.event.duration, _q);
    expect(ed.locate('n0')!.note!.midi, 59);
    ed.undo();
    expect(ed.locate('n0')!.note!.midi, 60);
    expect(ed.canUndo, isFalse);
    ed.redo();
    ed.redo();
    expect(ed.locate('n1')!.event.duration, _q ~/ 2);
    expect(ed.canRedo, isFalse);
    // Una corrección nueva borra lo que se podía rehacer.
    ed.undo();
    ed.setPitch('n2', 65);
    expect(ed.canRedo, isFalse);
  });

  test('cifrado: escribir, cambiar y quitar', () {
    final ed = ScoreEditor(sample());
    ed.setChordSymbol(0, 'C');
    expect(ed.chordAt(0)!.chord.root, 0);
    ed.setChordSymbol(0, 'Am7');
    expect(ed.score.parts.first.chords.length, 1);
    expect(ed.chordAt(0)!.chord.root, 9);
    expect(() => ed.setChordSymbol(0, 'xyz'), throwsA(isA<EditError>()));
    ed.setChordSymbol(0, '');
    expect(ed.chordAt(0), isNull);
  });

  test('recorrer nota a nota', () {
    final ed = ScoreEditor(sample());
    expect(ed.neighbor('n0', 1), 'n1');
    expect(ed.neighbor('n1', -1), 'n0');
    expect(ed.neighbor('n0', -1), isNull);
    expect(ed.neighbor('n5', 1), 'e6');
    expect(ed.neighbor('nl0', 1), 'l1');
  });
}
