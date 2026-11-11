import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../ai/ai_client.dart';
import '../ai/ai_factory.dart';
import '../settings.dart';
import '../storage/score_repository.dart';
import '../storage/song_repository.dart';
import '../widgets/responsive.dart';
import 'browser_page.dart';
import 'search_plan.dart';
import 'web_sites.dart';

/// Antes de abrir el navegador: qué buscas y dónde. La IA llena el
/// formulario (canción, tipo y sitios sugeridos) y tú lo ajustas.
class WebSearchPage extends StatefulWidget {
  const WebSearchPage({
    super.key,
    required this.settings,
    required this.songs,
    required this.scores,
    required this.onOpenSong,
    required this.onOpenScore,
    this.want = WebWant.chords,
  });

  final AppSettings settings;
  final SongRepository songs;
  final ScoreRepository scores;
  final ValueChanged<Song> onOpenSong;
  final ValueChanged<Score> onOpenScore;
  final WebWant want;

  @override
  State<WebSearchPage> createState() => _WebSearchPageState();
}

class _WebSearchPageState extends State<WebSearchPage> {
  final TextEditingController input = TextEditingController();
  late WebWant want = widget.want;

  /// Lo que propuso la IA para el texto actual (null: sin IA o lo cambiaste).
  SearchPlan? aiPlan;
  bool thinking = false;
  String? error;

  AppSettings get settings => widget.settings;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  String get query => input.text.trim();

  /// Sitios para el tipo elegido: primero los que sugirió la IA, luego los
  /// usados hace poco y después el resto.
  List<(WebSite, bool)> get sites {
    final suggested = [
      if (aiPlan != null && aiPlan!.want == want)
        for (final s in aiPlan!.siteList)
          if (s.wants.contains(want)) s,
    ];
    final rest = WebSites.forWant(want).where((s) => !suggested.contains(s)).toList();
    final recent = settings.recentSites;
    int rank(WebSite s) {
      final i = recent.indexOf(s.id);
      return i < 0 ? 1000 + WebSites.all.indexOf(s) : i;
    }

    rest.sort((a, b) => rank(a) - rank(b));
    final custom = [
      for (final c in settings.customSites)
        WebSite(id: 'custom:${c.host}', name: c.name, host: c.host, wants: WebWant.values.toSet(), hint: 'Agregado por ti'),
    ];
    return [for (final s in suggested) (s, true), for (final s in [...rest, ...custom]) (s, false)];
  }

  SearchPlan get plan => SearchPlan(
        query: query,
        want: want,
        sites: [for (final (s, _) in sites) s.id],
        title: aiPlan?.title ?? '',
        artist: aiPlan?.artist ?? '',
        note: aiPlan?.note ?? '',
        fromAi: aiPlan != null,
      );

  Future<void> _prepare() async {
    final text = query;
    if (text.isEmpty || thinking) return;
    if (!settings.hasApiKey) {
      // Sin IA: solo se adivina el tipo por las palabras.
      setState(() => want = SearchPlan.guess(text, want: null).want);
      _snack('Sin API key de IA: elige tú el sitio. (Puedes ponerla en ⚙ Configuración.)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      thinking = true;
      error = null;
    });
    try {
      final p = await SearchPlan.ask(aiClientFor(settings), text);
      if (!mounted) return;
      setState(() {
        aiPlan = p;
        want = p.want;
        input.text = p.query;
      });
    } on AiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => thinking = false);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void _open(Uri start, {String? siteId}) {
    if (siteId != null) settings.useSite(siteId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          start: start,
          settings: settings,
          songs: widget.songs,
          scores: widget.scores,
          onOpenSong: widget.onOpenSong,
          onOpenScore: widget.onOpenScore,
          plan: query.isEmpty ? null : plan,
        ),
      ),
    );
  }

  void _openSite(WebSite site) {
    if (query.isEmpty) {
      _open(site.home, siteId: site.id);
    } else {
      _open(site.searchUri(query), siteId: site.id);
    }
  }

  void _submit() {
    final asUrl = WebSites.asUrl(query);
    if (asUrl != null) {
      _open(asUrl);
    } else {
      _prepare();
    }
  }

  Future<void> _addSite() async {
    final name = TextEditingController();
    final host = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar sitio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: host,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Dirección', hintText: 'ej.: acordesweb.com'),
            ),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre (opcional)')),
            const SizedBox(height: 12),
            const Text('Se busca en ese sitio con Google.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Agregar')),
        ],
      ),
    );
    final h = WebSites.asUrl(host.text)?.host.replaceFirst(RegExp(r'^www\.'), '');
    if (ok == true && h != null) settings.addCustomSite(name.text, h);
    name.dispose();
    host.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar en internet')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: EdgeInsets.all(context.isCompact ? 16 : 24),
              children: [
                TextField(
                  controller: input,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => setState(() {
                    // Si cambias el texto, la sugerencia anterior ya no aplica.
                    if (aiPlan != null && query != aiPlan!.query) aiPlan = null;
                  }),
                  decoration: InputDecoration(
                    labelText: '¿Qué canción buscas?',
                    hintText: 'Ej.: Way Maker · Observatorio Astral de Zelda para piano',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Borrar',
                            onPressed: () => setState(() {
                              input.clear();
                              aiPlan = null;
                            }),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: query.isEmpty || thinking ? null : _prepare,
                      icon: thinking
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome),
                      label: Text(thinking ? 'Preparando…' : 'Preparar con IA'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'La IA entiende qué buscas y sugiere dónde. También puedes elegir el sitio tú.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: TextStyle(color: scheme.error)),
                ],
                if (aiPlan != null) ...[
                  const SizedBox(height: 16),
                  _understood(aiPlan!, text, scheme),
                ],
                const SizedBox(height: 20),
                Text('Qué buscas', style: text.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<WebWant>(
                  segments: [for (final w in WebWant.values) ButtonSegment(value: w, label: Text(w.label))],
                  selected: {want},
                  onSelectionChanged: (s) => setState(() => want = s.first),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: Text('Dónde buscar', style: text.labelLarge)),
                    TextButton.icon(onPressed: _addSite, icon: const Icon(Icons.add), label: const Text('Agregar sitio')),
                  ],
                ),
                const SizedBox(height: 4),
                for (final (site, suggested) in sites) _siteTile(site, suggested, text, scheme),
                _tile(
                  icon: Icons.public,
                  title: 'Google',
                  subtitle: query.isEmpty ? 'Buscar en toda la web' : 'Buscar "$query ${want.googleWord}" en toda la web',
                  onTap: () => _open(query.isEmpty ? Uri.https('www.google.com', '/') : WebSites.googleFor(query, want)),
                ),
                const SizedBox(height: 16),
                Text(
                  want == WebWant.chords
                      ? 'Abre la página de la canción y toca "Importar esta página": la IA arma la canción con sus acordes.'
                      : 'Abre la página de la partitura y descarga el MIDI o MusicXML: se abre como partitura. '
                          'Los PDF todavía no se pueden importar.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _understood(SearchPlan p, TextTheme text, ColorScheme scheme) {
    final song = [p.title, p.artist].where((s) => s.isNotEmpty).join(' – ');
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.isEmpty ? 'Buscar: ${p.query}' : song,
                    style: text.titleMedium?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                  Text(p.want.label, style: text.bodyMedium?.copyWith(color: scheme.onSecondaryContainer)),
                  if (p.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(p.note, style: text.bodyMedium?.copyWith(color: scheme.onSecondaryContainer)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _siteTile(WebSite site, bool suggested, TextTheme text, ColorScheme scheme) {
    final custom = site.id.startsWith('custom:');
    return _tile(
      icon: suggested ? Icons.star : (custom ? Icons.bookmark_outline : Icons.language),
      iconColor: suggested ? scheme.primary : null,
      title: site.name + (suggested ? '  · sugerido' : ''),
      subtitle: '${site.host} · ${site.hint}',
      onTap: () => _openSite(site),
      trailing: custom
          ? IconButton(
              tooltip: 'Quitar',
              onPressed: () => settings.removeCustomSite(site.host),
              icon: const Icon(Icons.delete_outline),
            )
          : null,
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Widget? trailing,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          leading: Icon(icon, color: iconColor),
          title: Text(title),
          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: trailing ?? const Icon(Icons.open_in_browser),
          onTap: onTap,
        ),
      );
}
