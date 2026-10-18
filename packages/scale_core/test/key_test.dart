import 'package:scale_core/scale_core.dart';
import 'package:test/test.dart';

List<Chord> chords(String text) => [for (final s in text.split(' ')) ChordParser.parse(s)!];

KeyEstimate estimate(String text) => KeyEstimator.fromChords(chords(text));

void main() {
  group('tonalidad', () {
    test('nombres, relativa y enarmonía', () {
      final g = MusicKey(7, Mode.major);
      expect(g.name(), 'G');
      expect(g.label(Notation.latin), 'Sol mayor');
      expect(g.relative, MusicKey(4, Mode.minor));
      expect(g.relative.name(), 'Em');
      expect(MusicKey(6, Mode.major).name(), 'F#');
      expect(MusicKey(6, Mode.major).enharmonicName(), 'Gb');
      expect(MusicKey(1, Mode.major).name(), 'Db');
      expect(MusicKey(1, Mode.major).enharmonicName(), 'C#');
      expect(g.enharmonicName(), isNull);
    });

    test('ortografía según la tonalidad', () {
      const fmt = ChordFormatter();
      final e = MusicKey(4, Mode.major);
      final f = MusicKey(5, Mode.major);
      final d = MusicKey(2, Mode.major);
      expect(fmt.format(Chord(11, ChordQuality.major, bass: 3), spell: e.spell), 'B/D#');
      expect(fmt.format(Chord(3, ChordQuality.minor), spell: e.spell), 'D#m');
      expect(fmt.format(Chord(10, ChordQuality.major), spell: f.spell), 'Bb');
      expect(fmt.format(Chord(0, ChordQuality.major), spell: d.spell), 'C');
      expect(fmt.format(Chord(8, ChordQuality.major), spell: MusicKey(7, Mode.major).spell), 'Ab');
    });

    test('grados Nashville', () {
      const fmt = ChordFormatter();
      final g = MusicKey(7, Mode.major);
      String n(String s) => fmt.nashville(ChordParser.parse(s)!, g);
      expect(n('G'), '1');
      expect(n('Em7'), '6m7');
      expect(n('D/F#'), '5/7');
      expect(n('C'), '4');
      expect(n('F'), 'b7');
      expect(n('Asus4'), '2sus4');
      // Un sufijo numérico no se pega al grado: D7 en G es 5⁷, no 57.
      expect(n('D7'), '5⁷');
      expect(n('G5'), '1⁵');
      expect(n('C6/9'), '4⁶ᐟ⁹');
      expect(n('D7sus4'), '5⁷sus4');
      expect(n('Cmaj7'), '4maj7');
    });

    test('parse', () {
      expect(MusicKey.parse('G'), MusicKey(7, Mode.major));
      expect(MusicKey.parse('Em'), MusicKey(4, Mode.minor));
      expect(MusicKey.parse('Sol mayor'), MusicKey(7, Mode.major));
      expect(MusicKey.parse('Mi menor'), MusicKey(4, Mode.minor));
      expect(MusicKey.parse('F# minor'), MusicKey(6, Mode.minor));
      expect(MusicKey.parse('Verso'), isNull);
    });

    test('json', () {
      final k = MusicKey(10, Mode.minor);
      expect(MusicKey.fromJson(k.toJson()), k);
    });
  });

  group('estimador', () {
    test('progresiones de worship en mayor', () {
      expect(estimate('G D/F# Em7 C').key, MusicKey(7, Mode.major));
      expect(estimate('D A Bm G').key, MusicKey(2, Mode.major));
      expect(estimate('Em C G D').key, MusicKey(7, Mode.major));
      expect(estimate('C Am F G7').key, MusicKey(0, Mode.major));
      expect(estimate('E B C#m A B/D# E').key, MusicKey(4, Mode.major));
    });

    test('menor con dominante mayor', () {
      expect(estimate('Am Dm E7 Am').key, MusicKey(9, Mode.minor));
      expect(estimate('Em C D B7 Em').key, MusicKey(4, Mode.minor));
    });

    test('la relativa aparece como alternativa principal', () {
      final est = estimate('G D Em C');
      final alts = est.alternatives.take(3).map((c) => c.key);
      expect(alts, contains(MusicKey(4, Mode.minor)));
    });

    test('más acordes coherentes → más seguridad', () {
      final short = estimate('G D');
      final long = estimate('G D Em C G D C G Em C D G');
      expect(long.key, MusicKey(7, Mode.major));
      expect(long.confidence, greaterThan(short.confidence));
      expect(long.confidence, greaterThan(0.6));
    });

    test('sigue una modulación (sube un tono en el último coro)', () {
      final est = estimate('G C D G Em C D G A D E A F#m D E A F#m D E A');
      expect(est.key, MusicKey(9, Mode.major));
    });

    test('sin acordes no hay estimación', () {
      expect(KeyEstimator().estimate.isEmpty, isTrue);
    });
  });
}
