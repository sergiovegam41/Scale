/// Qué se busca en internet.
enum WebWant {
  chords('Acordes y letra', 'acordes'),
  score('Partitura', 'partitura'),
  midi('MIDI', 'midi');

  const WebWant(this.label, this.googleWord);

  final String label;

  /// Palabra que se agrega al buscar en Google (no en los sitios).
  final String googleWord;
}

/// Un sitio donde buscar. Si su buscador propio no se puede abrir con una
/// dirección (o no está comprobado), se busca en Google con `site:`.
class WebSite {
  const WebSite({
    required this.id,
    required this.name,
    required this.host,
    required this.wants,
    required this.hint,
    this.search,
  });

  final String id;
  final String name;
  final String host;
  final Set<WebWant> wants;

  /// Para qué sirve, en pocas palabras (se le muestra al usuario y a la IA).
  final String hint;

  /// Dirección del buscador del sitio con `{q}` en el lugar del texto.
  final String? search;

  Uri searchUri(String query) {
    final template = search;
    if (template == null) return WebSites.google('$query site:$host');
    return Uri.parse(template.replaceAll('{q}', Uri.encodeQueryComponent(query)));
  }

  Uri get home => Uri.https(host, '/');
}

/// Sitios conocidos. La IA solo puede elegir entre estos: las direcciones las
/// arma la app, así nunca abre una página inventada.
class WebSites {
  WebSites._();

  static const List<WebSite> all = [
    WebSite(
      id: 'lacuerda',
      name: 'LaCuerda',
      host: 'lacuerda.net',
      wants: {WebWant.chords},
      hint: 'acordes y letra en español, mucha alabanza',
    ),
    WebSite(
      id: 'cifraclub',
      name: 'Cifra Club',
      host: 'cifraclub.com',
      wants: {WebWant.chords},
      hint: 'acordes y letra en español y portugués, mucha alabanza',
    ),
    WebSite(
      id: 'ultimateguitar',
      name: 'Ultimate Guitar',
      host: 'ultimate-guitar.com',
      wants: {WebWant.chords},
      hint: 'acordes, sobre todo canciones en inglés',
      search: 'https://www.ultimate-guitar.com/search.php?search_type=title&value={q}',
    ),
    WebSite(
      id: 'musescore',
      name: 'MuseScore',
      host: 'musescore.com',
      wants: {WebWant.score},
      hint: 'muchísimas partituras de todo tipo; descargar pide cuenta',
      search: 'https://musescore.com/sheetmusic?text={q}',
    ),
    WebSite(
      id: 'ninsheetmusic',
      name: 'Ninsheetmusic',
      host: 'ninsheetmusic.org',
      wants: {WebWant.score, WebWant.midi},
      hint: 'partituras de videojuegos (Nintendo y otros)',
    ),
    WebSite(
      id: 'imslp',
      name: 'IMSLP',
      host: 'imslp.org',
      wants: {WebWant.score},
      hint: 'música clásica de dominio público (casi todo en PDF)',
    ),
    WebSite(
      id: 'flat',
      name: 'Flat',
      host: 'flat.io',
      wants: {WebWant.score},
      hint: 'partituras de la comunidad, algunas descargables en MusicXML',
    ),
    WebSite(
      id: 'bitmidi',
      name: 'BitMidi',
      host: 'bitmidi.com',
      wants: {WebWant.midi},
      hint: 'archivos MIDI gratis de todo tipo, descarga directa',
      search: 'https://bitmidi.com/search?q={q}',
    ),
    WebSite(
      id: 'midiworld',
      name: 'MIDIWORLD',
      host: 'midiworld.com',
      wants: {WebWant.midi},
      hint: 'archivos MIDI gratis (pop, rock, clásica)',
      search: 'https://www.midiworld.com/search/?q={q}',
    ),
  ];

  static WebSite? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  static List<WebSite> forWant(WebWant want) => [
        for (final s in all)
          if (s.wants.contains(want)) s,
      ];

  static Uri google(String query) => Uri.https('www.google.com', '/search', {'q': query});

  /// Búsqueda general en Google con la palabra del tipo ("acordes",
  /// "partitura", "midi") si no está ya.
  static Uri googleFor(String query, WebWant want) {
    final word = want.googleWord;
    final q = query.toLowerCase().contains(word) ? query : '$query $word';
    return google(q);
  }

  /// Si [text] es una dirección web, la dirección; si no, null.
  static Uri? asUrl(String text) {
    final t = text.trim();
    if (t.contains(' ') || !t.contains('.')) return null;
    final uri = Uri.tryParse(t.startsWith('http') ? t : 'https://$t');
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) return null;
    return uri;
  }
}
