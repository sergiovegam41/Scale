import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart' as iaw;
import 'package:http/http.dart' as http;
import 'package:scale_core/scale_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../score/score_import.dart';
import '../screens/import_page.dart';
import '../settings.dart';
import '../storage/score_repository.dart';
import '../storage/song_repository.dart';
import '../widgets/responsive.dart';
import '../widgets/settings_sheet.dart';
import 'captured_page.dart';
import 'search_plan.dart';
import 'web_sites.dart';

/// Un archivo de música enlazado en la página.
class PageFile {
  const PageFile(this.url, this.label);

  final Uri url;
  final String label;

  String get extension {
    final m = RegExp(r'\.(midi?|mxl|musicxml|xml|pdf)$', caseSensitive: false).firstMatch(url.path);
    return m?.group(1)?.toLowerCase() ?? '';
  }

  String get kind => switch (extension) {
        'mid' || 'midi' => 'MIDI',
        'mxl' || 'musicxml' || 'xml' => 'MusicXML',
        'pdf' => 'PDF',
        _ => 'Descarga',
      };
}

/// Navegador dentro de la app: buscas la canción, y la página se importa con
/// la IA (acordes) o el archivo MIDI/MusicXML se abre como partitura.
class BrowserPage extends StatefulWidget {
  const BrowserPage({
    super.key,
    required this.start,
    required this.settings,
    required this.songs,
    required this.scores,
    required this.onOpenSong,
    required this.onOpenScore,
    this.plan,
  });

  final Uri start;
  final AppSettings settings;
  final SongRepository songs;
  final ScoreRepository scores;
  final ValueChanged<Song> onOpenSong;
  final ValueChanged<Score> onOpenScore;

  /// Lo que se busca: para saltar a otro sitio con el mismo texto.
  final SearchPlan? plan;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  // Android: WebView del sistema. Windows: WebView2.
  WebViewController? _android;
  iaw.PlatformInAppWebViewWidget? _win;
  iaw.PlatformInAppWebViewController? _winController;

  late Uri url = widget.start;
  String title = '';
  int progress = 0;
  bool canBack = false;
  bool canForward = false;
  List<PageFile> files = const [];
  String? busy;

  /// En Android, una descarga vuelve a pedir la misma dirección que se acaba
  /// de abrir sin que la página cargue: así se reconoce.
  String? _pendingUrl;
  DateTime _pendingAt = DateTime(0);
  String? _userAgent;

  static const int _maxBytes = 20 * 1024 * 1024;
  static final RegExp _fileUrl = RegExp(r'\.(midi?|mxl|musicxml)(\?|#|$)', caseSensitive: false);

  @override
  void dispose() {
    _win?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- WebView

  Future<void> _load(Uri u) async {
    if (_android != null) {
      await _android!.loadRequest(u);
    } else {
      await _winController?.loadUrl(urlRequest: iaw.URLRequest(url: iaw.WebUri.uri(u)));
    }
  }

  Future<void> _back() async => _android != null ? _android!.goBack() : _winController?.goBack();
  Future<void> _forward() async => _android != null ? _android!.goForward() : _winController?.goForward();
  Future<void> _reload() async => _android != null ? _android!.reload() : _winController?.reload();

  /// Ejecuta JavaScript que devuelve un texto (JSON.stringify).
  Future<String?> _eval(String js) async {
    try {
      final Object? result;
      if (_android != null) {
        result = await _android!.runJavaScriptReturningResult(js);
      } else {
        result = await _winController?.evaluateJavascript(source: js);
      }
      if (result == null) return null;
      var text = result is String ? result : '$result';
      // Android devuelve los textos entre comillas (como JSON).
      if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
        text = jsonDecode(text) as String;
      }
      return text;
    } catch (e) {
      debugPrint('Navegador: $e');
      return null;
    }
  }

  Future<void> _onPageFinished(String? current) async {
    if (!mounted) return;
    if (current != null) {
      url = Uri.tryParse(current) ?? url;
      if (current == _pendingUrl) _pendingUrl = null;
    }
    final t = _android != null ? await _android!.getTitle() : await _winController?.getTitle();
    final back = _android != null ? await _android!.canGoBack() : await _winController?.canGoBack() ?? false;
    final fwd = _android != null ? await _android!.canGoForward() : await _winController?.canGoForward() ?? false;
    if (!mounted) return;
    setState(() {
      title = t ?? '';
      canBack = back;
      canForward = fwd;
      progress = 100;
    });
    _scanFiles();
  }

  void _onPageStarted(String? current) {
    if (!mounted) return;
    setState(() {
      if (current != null) url = Uri.tryParse(current) ?? url;
      files = const [];
      progress = 0;
    });
  }

  /// Android: cada navegación pasa por aquí (también las descargas).
  FutureOr<NavigationDecision> _onNavigation(NavigationRequest request) {
    final u = Uri.tryParse(request.url);
    if (u == null) return NavigationDecision.prevent;
    if (u.scheme != 'http' && u.scheme != 'https') return NavigationDecision.prevent;
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final repeated = request.url == _pendingUrl && DateTime.now().difference(_pendingAt) < const Duration(minutes: 2);
    if (repeated || _fileUrl.hasMatch(request.url)) {
      _pendingUrl = null;
      _download(u);
      return NavigationDecision.prevent;
    }
    _pendingUrl = request.url;
    _pendingAt = DateTime.now();
    return NavigationDecision.navigate;
  }

  Widget _androidView() {
    final c = _android ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigation,
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished,
          onProgress: (p) {
            if (mounted) setState(() => progress = p);
          },
          onUrlChange: (change) {
            final u = change.url;
            if (u != null && mounted) setState(() => url = Uri.tryParse(u) ?? url);
          },
        ),
      )
      ..loadRequest(widget.start);
    return WebViewWidget(controller: c);
  }

  Widget _windowsView() {
    final view = _win ??= iaw.PlatformInAppWebViewWidget(
      iaw.PlatformInAppWebViewWidgetCreationParams(
        initialUrlRequest: iaw.URLRequest(url: iaw.WebUri.uri(widget.start)),
        initialSettings: iaw.InAppWebViewSettings(javaScriptEnabled: true, isInspectable: kDebugMode),
        onWebViewCreated: (c) => _winController = c,
        onLoadStart: (c, u) => _onPageStarted(u?.toString()),
        onLoadStop: (c, u) => _onPageFinished(u?.toString()),
        onProgressChanged: (c, p) {
          if (mounted) setState(() => progress = p);
        },
        onDownloadStartRequest: (c, request) => _download(request.url, name: request.suggestedFilename),
      ),
    );
    return view.build(context);
  }

  // ------------------------------------------------------------- Archivos

  /// Busca en la página enlaces a archivos de música.
  Future<void> _scanFiles() async {
    const js = '''
JSON.stringify(Array.from(document.querySelectorAll('a[href]')).map(function (a) {
  return {h: a.href, t: (a.innerText || a.title || a.getAttribute('download') || '').trim().slice(0, 80)};
}).filter(function (x) {
  return /\\.(midi?|mxl|musicxml|pdf)(\\?|#|\$)/i.test(x.h) || /\\/download\\b/i.test(x.h);
}).slice(0, 40))''';
    final text = await _eval(js);
    if (text == null || !mounted) return;
    try {
      final seen = <String>{};
      final found = <PageFile>[];
      for (final item in jsonDecode(text) as List) {
        if (item is! Map || !seen.add('${item['h']}')) continue;
        final u = Uri.tryParse('${item['h']}');
        if (u == null || !u.scheme.startsWith('http')) continue;
        final label = '${item['t']}'.trim();
        found.add(PageFile(u, label.isEmpty ? Uri.decodeComponent(u.pathSegments.lastOrNull ?? u.host) : label));
      }
      setState(() => files = found);
    } catch (e) {
      debugPrint('Navegador: enlaces ilegibles: $e');
    }
  }

  static String _nameFrom(Uri u, String? suggested, String? disposition) {
    if (suggested != null && suggested.trim().isNotEmpty) return suggested.trim();
    final m = RegExp(r'''filename\*?=(?:UTF-8'')?["']?([^"';]+)''', caseSensitive: false).firstMatch(disposition ?? '');
    if (m != null) return Uri.decodeComponent(m.group(1)!.trim());
    final last = u.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return last == null ? u.host : Uri.decodeComponent(last);
  }

  /// Descarga el archivo y, si es MIDI o MusicXML, lo abre como partitura.
  Future<void> _download(Uri u, {String? name}) async {
    if (busy != null) return;
    setState(() => busy = 'Descargando…');
    final messenger = ScaffoldMessenger.of(context);
    try {
      _userAgent ??= _android != null ? await _android!.getUserAgent() : null;
      final response = await http.get(
        u,
        headers: {'referer': url.toString(), 'user-agent': ?_userAgent},
      ).timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        throw FormatException('el sitio respondió ${response.statusCode}');
      }
      final bytes = response.bodyBytes;
      if (bytes.length > _maxBytes) throw const FormatException('el archivo es demasiado grande');
      final fileName = _nameFrom(u, name, response.headers['content-disposition']);
      final kind = ScoreFileKind.of(bytes, name: fileName, mimeType: response.headers['content-type'] ?? '');
      if (kind == ScoreFileKind.html) {
        // No era un archivo: se abre como página.
        if (mounted) setState(() => busy = null);
        _pendingUrl = null;
        await _load(u);
        return;
      }
      if (!mounted) return;
      setState(() => busy = 'Abriendo la partitura…');
      final score = await ScoreImport.fromBytes(context, bytes, fileName, kind: kind);
      if (score == null || !mounted) return;
      await widget.scores.save(score);
      messenger.showSnackBar(SnackBar(content: Text('Partitura guardada: ${score.title}')));
      widget.onOpenScore(score);
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir el archivo: ${e.message}')));
    } on TimeoutException {
      messenger.showSnackBar(const SnackBar(content: Text('La descarga tardó demasiado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo descargar: $e')));
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<void> _showFiles() async {
    final picked = await showModalBottomSheet<PageFile>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Archivos en esta página'),
              subtitle: Text('MIDI y MusicXML se abren como partitura. Los PDF todavía no se pueden importar.'),
            ),
            for (final f in files)
              ListTile(
                leading: Icon(f.kind == 'PDF' ? Icons.picture_as_pdf_outlined : Icons.queue_music),
                title: Text(f.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${f.kind} · ${f.url.host}'),
                enabled: f.kind != 'PDF',
                onTap: () => Navigator.pop(context, f),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _download(picked.url);
  }

  // -------------------------------------------------------- Importar página

  /// Texto de la página: si trae bloques preformateados (donde suelen estar
  /// los acordes alineados sobre la letra), esos; si no, todo el texto.
  static const String _textJs = '''
(function () {
  var pres = Array.from(document.querySelectorAll('pre')).map(function (p) { return p.innerText; })
    .filter(function (t) { return t.trim().length > 150; });
  var text = pres.length ? pres.join('\\n\\n') : (document.body ? document.body.innerText : '');
  return JSON.stringify(text.slice(0, 30000));
})()''';

  Future<void> _importPage() async {
    final settings = widget.settings;
    if (!await ensureApiKey(context, settings) || !mounted) return;
    final raw = await _eval(_textJs);
    String text = '';
    try {
      text = raw == null ? '' : (raw.startsWith('"') ? jsonDecode(raw) as String : raw);
    } catch (_) {
      text = raw ?? '';
    }
    if (!mounted) return;
    if (text.trim().length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta página no tiene texto para importar. Abre la página de la canción.')),
      );
      return;
    }
    final page = CapturedPage(url: url, title: title.isEmpty ? url.host : title, text: text);
    final song = await Navigator.of(context).push<Song>(
      MaterialPageRoute(builder: (_) => ImportPage(repo: widget.songs, settings: settings, page: page)),
    );
    if (song != null && mounted) widget.onOpenSong(song);
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final plan = widget.plan;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.isEmpty ? url.host : title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(url.host, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Atrás', onPressed: canBack ? _back : null, icon: const Icon(Icons.arrow_back_ios_new)),
          IconButton(
            tooltip: 'Adelante',
            onPressed: canForward ? _forward : null,
            icon: const Icon(Icons.arrow_forward_ios),
          ),
          IconButton(tooltip: 'Recargar', onPressed: _reload, icon: const Icon(Icons.refresh)),
          if (files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Badge.count(
                count: files.length,
                child: compact
                    ? IconButton(
                        tooltip: 'Archivos en la página',
                        onPressed: busy == null ? _showFiles : null,
                        icon: const Icon(Icons.queue_music),
                      )
                    : OutlinedButton.icon(
                        onPressed: busy == null ? _showFiles : null,
                        icon: const Icon(Icons.queue_music),
                        label: const Text('Archivos'),
                      ),
              ),
            ),
          const SizedBox(width: 8),
          compact
              ? IconButton.filled(
                  tooltip: 'Importar esta página',
                  onPressed: busy == null ? _importPage : null,
                  icon: const Icon(Icons.auto_awesome),
                )
              : FilledButton.icon(
                  onPressed: busy == null ? _importPage : null,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Importar esta página'),
                ),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: progress < 100 || busy != null
              ? LinearProgressIndicator(value: busy != null || progress == 0 ? null : progress / 100, minHeight: 3)
              : const SizedBox(height: 3),
        ),
      ),
      body: Column(
        children: [
          if (busy != null)
            Material(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [Text(busy!, style: TextStyle(color: scheme.onSecondaryContainer))]),
              ),
            ),
          Expanded(child: Platform.isWindows ? _windowsView() : _androidView()),
          if (plan != null) _sitesBar(plan, scheme),
        ],
      ),
    );
  }

  /// Saltar a otro sitio con la misma búsqueda.
  Widget _sitesBar(SearchPlan plan, ColorScheme scheme) {
    final sites = [
      ...plan.siteList,
      for (final s in WebSites.forWant(plan.want))
        if (!plan.sites.contains(s.id)) s,
    ];
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              Center(child: Text('Buscar "${plan.query}" en:  ')),
              for (final s in sites)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(s.name),
                    onPressed: () {
                      widget.settings.useSite(s.id);
                      _load(s.searchUri(plan.query));
                    },
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.search, size: 18),
                label: const Text('Google'),
                onPressed: () => _load(WebSites.googleFor(plan.query, plan.want)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
