import 'dart:convert';

import '../ai/ai_client.dart';
import 'web_sites.dart';

/// Qué buscar y dónde: lo arma la IA (o una suposición sin IA) y el usuario
/// lo puede cambiar antes de abrir el navegador.
class SearchPlan {
  SearchPlan({
    required this.query,
    required this.want,
    required this.sites,
    this.title = '',
    this.artist = '',
    this.note = '',
    this.fromAi = false,
  });

  /// Texto para los buscadores (título y artista, sin "acordes" ni similares).
  String query;
  WebWant want;

  /// Ids de [WebSites], en orden de preferencia.
  List<String> sites;
  final String title;
  final String artist;

  /// Consejo breve de la IA ("es de videojuego: prueba Ninsheetmusic").
  final String note;
  final bool fromAi;

  List<WebSite> get siteList => [for (final id in sites) ?WebSites.byId(id)];

  /// Sin IA: el texto tal cual, el tipo por palabras clave y los sitios de
  /// ese tipo.
  static SearchPlan guess(String text, {WebWant? want}) {
    final lower = text.toLowerCase();
    final w = want ??
        (RegExp(r'\bmidi\b').hasMatch(lower)
            ? WebWant.midi
            : RegExp(r'partitura|piano|sheet|musicxml|score').hasMatch(lower)
                ? WebWant.score
                : WebWant.chords);
    final query = text
        .replaceAll(RegExp(r'\b(acordes?|letra|partitura|midi|musicxml|para piano|sheet music)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return SearchPlan(
      query: query.isEmpty ? text.trim() : query,
      want: w,
      sites: [for (final s in WebSites.forWant(w)) s.id],
    );
  }

  static final Map<String, dynamic> schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['title', 'artist', 'want', 'query', 'sites', 'note'],
    'properties': {
      'title': {'type': 'string'},
      'artist': {'type': 'string'},
      'want': {
        'type': 'string',
        'enum': [for (final w in WebWant.values) w.name],
      },
      'query': {'type': 'string'},
      'sites': {
        'type': 'array',
        'items': {
          'type': 'string',
          'enum': [for (final s in WebSites.all) s.id],
        },
      },
      'note': {'type': 'string'},
    },
  };

  static String get system => '''
Ayudas a un pianista de alabanza a buscar canciones en internet desde la app Scale. Él escribe lo que busca y tú preparas la búsqueda; él la abre en el navegador de la app y elige la página.
No buscas ni abres páginas: solo propones qué buscar y en qué sitios de esta lista (usa solo estos ids):
${[for (final s in WebSites.all) '- ${s.id}: ${s.name} (${s.host}), ${s.hint}. Sirve para: ${s.wants.map((w) => w.name).join(', ')}'].join('\n')}

Responde:
- title y artist: la canción que crees que busca, bien escrita. Si no sabes el artista con seguridad, artist = "". No inventes.
- want: chords (acordes y letra; lo normal para canciones de alabanza o populares), score (partitura para piano) o midi (archivo MIDI). Si pide "partitura" o "para piano", score; si dice "midi", midi.
- query: el texto para los buscadores de los sitios: título y artista si lo sabes, sin palabras como "acordes" o "partitura".
- sites: de 2 a 4 ids, el más prometedor primero, que sirvan para ese want.
- note: un consejo breve en español (una frase) o "".''';

  /// Pide el plan a la IA. Si falla, lanza [AiException].
  static Future<SearchPlan> ask(AiClient client, String text) async {
    final reply = await client.complete(
      system: system,
      history: [AiTurn.user(text)],
      schema: schema,
      schemaName: 'busqueda',
      quick: true,
    );
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(reply.text) as Map<String, dynamic>;
    } catch (_) {
      throw const AiException('La IA respondió en un formato inesperado.', retryable: true);
    }
    return fromJson(json, text);
  }

  static SearchPlan fromJson(Map<String, dynamic> json, String text) {
    final want = WebWant.values.asNameMap()[json['want']] ?? guess(text).want;
    final sites = [
      ...{
        for (final id in (json['sites'] as List? ?? const []))
          if (id is String && WebSites.byId(id) != null) id,
      },
    ];
    final query = (json['query'] as String? ?? '').trim();
    return SearchPlan(
      title: (json['title'] as String? ?? '').trim(),
      artist: (json['artist'] as String? ?? '').trim(),
      query: query.isEmpty ? text.trim() : query,
      want: want,
      sites: sites.isEmpty ? [for (final s in WebSites.forWant(want)) s.id] : sites,
      note: (json['note'] as String? ?? '').trim(),
      fromAi: true,
    );
  }
}
