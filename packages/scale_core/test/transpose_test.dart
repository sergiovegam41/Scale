import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

MusicKey k(String s) => MusicKey.parse(s)!;

void main() {
  test('de D a F: +3 o −9, recomienda +3', () {
    final a = TransposeAdvice.between(k('D'), k('F'));
    expect(a.options, [3, -9]);
    expect(a.recommended, 3);
  });

  test('de G a D: +7 o −5, recomienda bajar 5', () {
    final a = TransposeAdvice.between(k('G'), k('D'));
    expect(a.options, [7, -5]);
    expect(a.recommended, -5);
  });

  test('respeta el rango del piano', () {
    // Con ±6, de C a G (+7 / −5) solo cabe −5; de C a F# (±6) se prefiere bajar.
    expect(TransposeAdvice.between(k('C'), k('G'), range: 6).recommended, -5);
    expect(TransposeAdvice.between(k('C'), k('F#'), range: 6).recommended, -6);
    expect(TransposeAdvice.between(k('C'), k('G'), range: 6).fits(7), isFalse);
  });

  test('misma tonalidad: nada que mover', () {
    final a = TransposeAdvice.between(k('Em'), k('Em'));
    expect(a.options, [0]);
    expect(a.recommended, 0);
  });

  test('etiquetas', () {
    expect(TransposeAdvice.label(3), '+3');
    expect(TransposeAdvice.label(-9), '-9');
  });

  test('la capa de transpose define la tonalidad que suena', () {
    final song = Song.create(title: 'x')
      ..key = k('D')
      ..transpose = 3;
    expect(song.soundingKey, k('F'));
  });

  test('el transporte y la vista elegida se guardan con la canción', () {
    final song = Song.create(title: 'x')
      ..key = k('D')
      ..transpose = 2
      ..showOriginal = true;
    final back = Song.fromJson(song.toJson());
    expect(back.transpose, 2);
    expect(back.showOriginal, isTrue);
    expect(Song.fromJson((Song.create(title: 'y')).toJson()).showOriginal, isFalse);
  });
}
