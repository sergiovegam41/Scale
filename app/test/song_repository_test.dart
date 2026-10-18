import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scale/storage/song_repository.dart';
import 'package:scale_core/scale_core.dart';

void main() {
  test('guarda, recarga y elimina canciones', () async {
    final dir = await Directory.systemTemp.createTemp('scale_songs');
    addTearDown(() => dir.delete(recursive: true));

    final song = Song.create(title: 'Santo')
      ..chords.add(ChordEvent(chord: ChordParser.parse('D/F#')!))
      ..key = MusicKey(2, Mode.major);
    await SongRepository(dir).save(song);

    final reloaded = SongRepository(dir);
    await reloaded.load();
    expect(reloaded.songs.single.title, 'Santo');
    expect(reloaded.songs.single.chords.single.chord, ChordParser.parse('D/F#'));

    await reloaded.delete(reloaded.songs.single);
    expect(dir.listSync(), isEmpty);
  });

  test('un archivo dañado no impide cargar los demás', () async {
    final dir = await Directory.systemTemp.createTemp('scale_songs');
    addTearDown(() => dir.delete(recursive: true));
    await File('${dir.path}/roto.json').writeAsString('{no es json');
    await SongRepository(dir).save(Song.create(title: 'Bien'));

    final repo = SongRepository(dir);
    await repo.load();
    expect(repo.songs.single.title, 'Bien');
    expect(repo.unreadable, hasLength(1));
  });
}
