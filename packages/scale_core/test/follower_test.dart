import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

Chord c(String s) => ChordParser.parse(s)!;

/// Verso ×2 (G D Em C), coro ×2 (C G D D), puente (Em C G D).
Song song() {
  final song = Song.create(title: 'x');
  const text = 'G D Em C G D Em C C G D Dsus4 C G D Dsus4 Em C G D';
  song.chords.addAll([for (final s in text.split(' ')) ChordEvent(chord: c(s))]);
  final verse = song.newSection(label: 'Verso');
  song.sections.add(verse);
  final chorus = song.newSection(label: 'Coro');
  song.sections.add(chorus);
  final bridge = song.newSection(label: 'Puente');
  song.sections.add(bridge);
  song.arrangement.addAll([
    SectionOccurrence(sectionId: verse.id, start: 0, end: 8, repeats: 2),
    SectionOccurrence(sectionId: chorus.id, start: 8, end: 16, repeats: 2),
    SectionOccurrence(sectionId: bridge.id, start: 16, end: 20),
  ]);
  return song;
}

void main() {
  test('avanza con cada acorde esperado y recorre las vueltas', () {
    final f = SongFollower(song());
    expect(f.status, FollowStatus.waiting);
    for (final s in 'G D Em C G D Em C'.split(' ')) {
      f.onChordPlayed(c(s));
    }
    expect(f.position, 7);
    expect(f.status, FollowStatus.onTrack);
    expect(f.expected, c('C'));
  });

  test('coincidencia flexible y repetir el acorde actual', () {
    final f = SongFollower(song());
    f.onChordPlayed(c('G/B'));
    expect(f.position, 0);
    f.onChordPlayed(c('Gadd9'));
    expect(f.position, 0);
    f.onChordPlayed(c('Dsus4'));
    expect(f.position, 1);
  });

  test('un acorde que no corresponde no avanza', () {
    final f = SongFollower(song())..onChordPlayed(c('G'));
    expect(f.onChordPlayed(c('F#m')), FollowStatus.offScript);
    expect(f.position, 0);
    f.onChordPlayed(c('D'));
    expect(f.position, 1);
  });

  test('saltar al puente: el acorde de inicio es único', () {
    final f = SongFollower(song());
    for (final s in 'G D Em C'.split(' ')) {
      f.onChordPlayed(c(s));
    }
    // Esperaba G (2ª vuelta del verso) y toca Em: solo el puente empieza en Em.
    expect(f.onChordPlayed(c('Em')), FollowStatus.jumped);
    expect(f.position, 16);
  });

  test('repetir el coro al final: solo el coro empieza con C', () {
    final f = SongFollower(song())..jumpTo(16);
    for (final s in 'Em C G D'.split(' ')) {
      f.onChordPlayed(c(s));
    }
    expect(f.status, FollowStatus.finished);
    expect(f.onChordPlayed(c('C')), FollowStatus.jumped);
    expect(f.position, 8);
    f.onChordPlayed(c('G'));
    expect(f.status, FollowStatus.onTrack);
    expect(f.position, 9);
  });

  test('D → Dsus4 seguidos: avanza al más parecido', () {
    final f = SongFollower(song())..jumpTo(8);
    for (final s in 'C G D Dsus4'.split(' ')) {
      f.onChordPlayed(c(s));
    }
    expect(f.position, 11);
  });

  test('sin inicio único, dos acordes seguidos confirman el salto', () {
    final f = SongFollower(song());
    for (final s in 'G D Em C'.split(' ')) {
      f.onChordPlayed(c(s));
    }
    // Esperaba G y toca D: ninguna parte empieza en D.
    expect(f.onChordPlayed(c('D')), FollowStatus.offScript);
    // D Em: la más cercana hacia adelante es la 2ª vuelta del verso.
    expect(f.onChordPlayed(c('Em')), FollowStatus.jumped);
    expect(f.position, 6);
  });

  test('una parte termina en G y la otra empieza en G', () {
    // Parte 3: Em C D G · Parte 4: G D C (G de 2 s cada uno en la grabación).
    final s = Song.create(title: 'x');
    for (final (text, seconds) in [
      ('Em', 2), ('C', 2), ('D', 2), ('G', 2), ('G', 2), ('D', 2), ('C', 2),
    ]) {
      s.chords.add(ChordEvent(chord: c(text), durationMicros: seconds * 1000000));
    }
    final p3 = s.newSection(label: 'Parte 3');
    s.sections.add(p3);
    final p4 = s.newSection(label: 'Parte 4');
    s.sections.add(p4);
    s.arrangement.addAll([
      SectionOccurrence(sectionId: p3.id, start: 0, end: 4),
      SectionOccurrence(sectionId: p4.id, start: 4, end: 7),
    ]);
    const sec = 1000000;
    final f = SongFollower(s)
      ..onChordPlayed(c('Em'), atMicros: 0)
      ..onChordPlayed(c('C'), atMicros: 2 * sec)
      ..onChordPlayed(c('D'), atMicros: 4 * sec)
      ..onChordPlayed(c('G'), atMicros: 6 * sec);
    expect(f.position, 3);
    // Un golpe de ritmo al poco tiempo no pasa a la parte 4…
    f.onChordPlayed(c('G'), atMicros: 6 * sec + 500000);
    expect(f.position, 3);
    // …pero volver a atacar G cuando ya pasó su tiempo, sí.
    f.onChordPlayed(c('G'), atMicros: 8 * sec);
    expect(f.position, 4);
    expect(f.status, FollowStatus.onTrack);
    f.onChordPlayed(c('D'), atMicros: 10 * sec);
    expect(f.position, 5);
  });

  test('saltar a mano', () {
    final f = SongFollower(song())..jumpTo(8);
    expect(f.expected, c('C'));
    f.onChordPlayed(c('C'));
    expect(f.position, 8);
  });
}
