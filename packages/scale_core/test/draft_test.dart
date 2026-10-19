import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

const fmt = ChordFormatter();

Map<String, dynamic> draftJson() => {
      'title': 'Santo',
      'key': 'G',
      'sections': [
        {
          'label': 'Verso',
          'kind': 'verse',
          'repeats': 2,
          'chords': [
            {'symbol': 'G', 'beats': 4},
            {'symbol': 'D/F#', 'beats': 4},
            {'symbol': 'Em7', 'beats': 0},
            {'symbol': 'C', 'beats': 0},
          ],
        },
        {
          'label': 'Coro',
          'kind': 'chorus',
          'repeats': 1,
          'note': 'Subir intensidad',
          'chords': [
            {'symbol': 'Do', 'beats': 0},
            {'symbol': 'Sol/Si', 'beats': 0},
            {'symbol': 'Re', 'beats': 0},
            {'symbol': 'N.C.', 'beats': 0},
          ],
        },
      ],
      'lyrics': '{title: Santo}\n[G]Santo, [D/F#]santo',
    };

void main() {
  test('convierte el borrador en canción con vueltas, tiempos y letra', () {
    final result = SongDraft.fromJson(draftJson()).toSong();
    final song = result.song;
    expect(song.title, 'Santo');
    expect(song.source, SongSource.import);
    expect(song.chords.map((c) => fmt.format(c.chord)),
        ['G', 'D/F#', 'Em7', 'C', 'G', 'D/F#', 'Em7', 'C', 'C', 'G/B', 'D']);
    expect(song.chords.first.beats, 4);
    expect(song.chords[2].beats, isNull);
    expect(song.arrangement.map((o) => (song.section(o.sectionId)!.label, o.repeats)),
        [('Verso', 2), ('Coro', 1)]);
    expect(song.sections.first.kind, SectionKind.verse);
    expect(song.sections.first.note, isNull);
    expect(song.sections.last.note, 'Subir intensidad');
    expect(Song.fromJson(song.toJson()).sections.last.note, 'Subir intensidad');
    expect(song.lyrics?.text, contains('[G]Santo'));
    expect(song.key, MusicKey(7, Mode.major));
  });

  test('informa los cifrados que no entiende en vez de inventarlos', () {
    final result = SongDraft.fromJson(draftJson()).toSong();
    expect(result.unknownSymbols, ['N.C.']);
  });

  test('compara la tonalidad indicada con la del análisis', () {
    final json = draftJson()..['key'] = 'Bb';
    final result = SongDraft.fromJson(json).toSong();
    expect(result.statedKey, MusicKey(10, Mode.major));
    expect(result.keyMismatch, isTrue);
    expect(SongDraft.fromJson(draftJson()).toSong().keyMismatch, isFalse);
    // La relativa no cuenta como discrepancia.
    final relative = draftJson()..['key'] = 'Em';
    expect(SongDraft.fromJson(relative).toSong().keyMismatch, isFalse);
  });

  test('json del borrador ida y vuelta, y valores por defecto', () {
    final draft = SongDraft.fromJson(draftJson());
    final back = SongDraft.fromJson(draft.toJson());
    expect(back.sections.first.chords, draft.sections.first.chords);
    final empty = SongDraft.fromJson({}).toSong();
    expect(empty.song.title, 'Canción importada');
    expect(empty.song.chords, isEmpty);
  });
}
