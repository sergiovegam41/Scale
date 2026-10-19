import '../analysis/song_analyzer.dart';
import '../theory/chord_parser.dart';
import '../theory/key.dart';
import 'song.dart';

/// Una sección del borrador, en orden de interpretación.
class DraftSection {
  const DraftSection({
    required this.label,
    required this.kind,
    required this.repeats,
    required this.chords,
    this.note = '',
  });

  factory DraftSection.fromJson(Map<String, dynamic> json) => DraftSection(
        label: (json['label'] as String? ?? '').trim(),
        kind: SectionKind.values.asNameMap()[json['kind']] ?? SectionKind.other,
        repeats: (json['repeats'] as num?)?.toInt() ?? 1,
        note: (json['note'] as String? ?? '').trim(),
        chords: [
          for (final c in (json['chords'] as List?) ?? const [])
            (
              (c as Map<String, dynamic>)['symbol'] as String? ?? '',
              (c['beats'] as num?)?.toInt() ?? 0,
            ),
        ],
      );

  final String label;
  final SectionKind kind;

  /// Vueltas seguidas (×N) de una vuelta de [chords].
  final int repeats;

  /// (cifrado, tiempos) de una vuelta; tiempos 0 = no indicados.
  final List<(String, int)> chords;

  /// Indicación de la fuente o del usuario ("suave", "sólo piano"), vacía si no hay.
  final String note;
}

/// Lo que devuelve la importación (IA o texto): una canción todavía sin
/// validar. Los cifrados se leen con [ChordParser]; los que no se entienden
/// se informan en vez de inventarse.
class SongDraft {
  const SongDraft({
    required this.title,
    required this.key,
    required this.sections,
    required this.lyrics,
  });

  factory SongDraft.fromJson(Map<String, dynamic> json) => SongDraft(
        title: (json['title'] as String? ?? '').trim(),
        key: (json['key'] as String? ?? '').trim(),
        sections: [
          for (final s in (json['sections'] as List?) ?? const [])
            DraftSection.fromJson(s as Map<String, dynamic>),
        ],
        lyrics: (json['lyrics'] as String? ?? '').trim(),
      );

  final String title;

  /// Tonalidad indicada en la fuente ("G", "Mi menor"…), vacía si no aparece.
  final String key;
  final List<DraftSection> sections;

  /// Letra en ChordPro, vacía si no había.
  final String lyrics;

  /// Esquema JSON para la salida estructurada de la IA (sin recursión).
  static const Map<String, dynamic> jsonSchema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['title', 'key', 'sections', 'lyrics'],
    'properties': {
      'title': {'type': 'string'},
      'key': {'type': 'string'},
      'sections': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['label', 'kind', 'repeats', 'chords', 'note'],
          'properties': {
            'label': {'type': 'string'},
            'kind': {
              'type': 'string',
              'enum': [
                'intro', 'verse', 'preChorus', 'chorus', 'bridge',
                'interlude', 'tag', 'outro', 'other',
              ],
            },
            'repeats': {'type': 'integer'},
            'note': {'type': 'string'},
            'chords': {
              'type': 'array',
              'items': {
                'type': 'object',
                'additionalProperties': false,
                'required': ['symbol', 'beats'],
                'properties': {
                  'symbol': {'type': 'string'},
                  'beats': {'type': 'integer'},
                },
              },
            },
          },
        },
      },
      'lyrics': {'type': 'string'},
    },
  };

  Map<String, dynamic> toJson() => {
        'title': title,
        'key': key,
        'sections': [
          for (final s in sections)
            {
              'label': s.label,
              'kind': s.kind.name,
              'repeats': s.repeats,
              'note': s.note,
              'chords': [
                for (final (symbol, beats) in s.chords) {'symbol': symbol, 'beats': beats},
              ],
            },
        ],
        'lyrics': lyrics,
      };

  /// Convierte el borrador en canción. La secuencia lineal contiene todas las
  /// vueltas (como si se hubiera tocado). Tonalidad y modulaciones salen del
  /// mismo análisis que las grabaciones.
  DraftResult toSong({SongSource source = SongSource.import}) {
    final song = Song.create(title: title.isEmpty ? 'Canción importada' : title, source: source);
    final unknown = <String>[];
    for (final s in sections) {
      final pass = <ChordEvent>[];
      for (final (symbol, beats) in s.chords) {
        final chord = ChordParser.parse(symbol);
        if (chord == null) {
          if (symbol.trim().isNotEmpty) unknown.add(symbol);
          continue;
        }
        pass.add(ChordEvent(chord: chord, symbol: symbol, beats: beats > 0 ? beats : null));
      }
      if (pass.isEmpty) continue;
      final repeats = s.repeats < 1 ? 1 : s.repeats;
      final section = song.newSection(
        label: s.label.isEmpty ? song.nextPartLabel() : s.label,
        kind: s.kind,
      )..note = s.note.isEmpty ? null : s.note;
      final start = song.chords.length;
      for (var r = 0; r < repeats; r++) {
        song.chords.addAll(r == 0 ? pass : pass.map((c) => c.copyForRepeat()));
      }
      song
        ..sections.add(section)
        ..arrangement.add(
          SectionOccurrence(
            sectionId: section.id,
            start: start,
            end: song.chords.length,
            repeats: repeats,
          ),
        );
    }
    if (lyrics.isNotEmpty) song.lyrics = SongLyrics(format: 'chordpro', text: lyrics);
    SongAnalyzer.analyze(song, sections: false);

    final stated = key.isEmpty ? null : MusicKey.parse(key);
    return DraftResult(song, unknown, stated);
  }
}

class DraftResult {
  const DraftResult(this.song, this.unknownSymbols, this.statedKey);

  final Song song;

  /// Cifrados que no se pudieron leer (no se agregaron a la canción).
  final List<String> unknownSymbols;

  /// Tonalidad que indicaba la fuente, si la había.
  final MusicKey? statedKey;

  /// La fuente dice una tonalidad distinta (y no relativa) a la del análisis.
  bool get keyMismatch {
    final stated = statedKey;
    final analyzed = song.key;
    return stated != null && analyzed != null && stated != analyzed && stated != analyzed.relative;
  }
}
