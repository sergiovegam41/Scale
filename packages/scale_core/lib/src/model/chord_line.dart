import '../theory/chord.dart';
import '../theory/chord_format.dart';
import '../theory/chord_parser.dart';
import '../theory/key.dart';
import 'song.dart';

/// Una vuelta de acordes escrita como texto: "D' A' Bm'' x2".
///
/// Las primas (o apóstrofos) anotan los tiempos y "x2" las vueltas. Sirve para
/// escribir una sección de un tirón y para corregirla igual de rápido.
class ChordLine {
  const ChordLine({required this.chords, this.repeats = 1, this.unknown = const []});

  final List<ChordEvent> chords;
  final int repeats;

  /// Lo que no se reconoció como acorde.
  final List<String> unknown;

  bool get isValid => chords.isNotEmpty && unknown.isEmpty;

  static final RegExp _separators = RegExp(r'[\s,|]+');
  static final RegExp _repeat = RegExp(r'^(?:[x×*](\d{1,2})|(\d{1,2})[x×])$', caseSensitive: false);
  static final RegExp _ticks = RegExp("['′’`´]+\$");

  static ChordLine parse(String text) {
    final chords = <ChordEvent>[];
    final unknown = <String>[];
    var repeats = 1;
    for (final token in text.split(_separators)) {
      if (token.isEmpty) continue;
      final r = _repeat.firstMatch(token);
      if (r != null) {
        repeats = int.parse(r.group(1) ?? r.group(2)!).clamp(1, 16);
        continue;
      }
      final ticks = _ticks.firstMatch(token)?.group(0);
      final symbol = ticks == null ? token : token.substring(0, token.length - ticks.length);
      final chord = ChordParser.parse(symbol);
      if (chord == null) {
        unknown.add(token);
      } else {
        chords.add(ChordEvent(chord: chord, symbol: symbol, beats: ticks?.length));
      }
    }
    return ChordLine(chords: chords, repeats: repeats, unknown: unknown);
  }

  /// Si la secuencia son vueltas iguales seguidas (D A Bm D A Bm), el largo
  /// de una vuelta y cuántas hay; si no, (largo, 1).
  static (int, int) repeatsOf(List<Chord> chords) {
    final n = chords.length;
    for (var p = 2; p <= n ~/ 2; p++) {
      if (n % p != 0) continue;
      var same = true;
      for (var i = p; i < n && same; i++) {
        same = chords[i] == chords[i % p];
      }
      if (same) return (p, n ~/ p);
    }
    return (n, 1);
  }

  /// La vuelta como texto editable (con apóstrofos, fáciles de teclear).
  static String format(
    List<ChordEvent> pass, {
    ChordFormatter formatter = const ChordFormatter(),
    MusicKey? key,
    int repeats = 1,
  }) =>
      [
        for (final e in pass) formatter.format(e.chord, spell: key?.spell) + "'" * (e.beats ?? 0),
        if (repeats > 1) 'x$repeats',
      ].join(' ');
}
