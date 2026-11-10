import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart' as iaw;
import 'package:scale_core/scale_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'score_server.dart';

/// Lo que el visor informa al terminar de dibujar (y al medir la fluidez).
class ViewerInfo {
  ViewerInfo(this.data);

  final Map<String, dynamic> data;

  int get pages => data['pages'] as int? ?? 0;
  int get engraveMs => data['engraveMs'] as int? ?? 0;
  int get domMs => data['domMs'] as int? ?? 0;
  int get preserved => data['preserved'] as int? ?? 0;
  int get matched => data['matched'] as int? ?? 0;
  int get total => data['total'] as int? ?? 0;
}

/// Controla el visor desde fuera: zoom y medición.
class ScoreViewerController {
  _ScoreViewerState? _state;

  Future<void> setZoom(int zoom) async => _state?._run('scale.setZoom($zoom)');

  /// Destello rojo en el cursor (una nota equivocada).
  Future<void> flash() async => _state?._run('scale.flash()');

  /// Recorre la partitura desplazándola y mide cuadros por segundo.
  Future<void> bench() async => _state?._run('scale.bench(4000)');
}

/// Partitura dibujada por Verovio dentro de un WebView, con las notas que
/// suenan resaltadas y el cursor siguiéndolas.
class ScoreViewer extends StatefulWidget {
  const ScoreViewer({
    super.key,
    required this.score,
    required this.lit,
    this.marked,
    this.controller,
    this.zoom = 45,
    this.revision = 0,
    this.onTapNote,
    this.onLoaded,
    this.onBench,
  });

  final Score score;

  /// Ids de las notas a resaltar.
  final ValueListenable<List<String>> lit;

  /// Ids de las notas ya tocadas (en verde), en el modo espera.
  final ValueListenable<List<String>>? marked;
  final ScoreViewerController? controller;
  final int zoom;

  /// Cambia cuando se corrige la partitura (sin cambiar de objeto): se vuelve
  /// a dibujar.
  final int revision;

  /// Toque en una nota (o en un silencio): su id.
  final ValueChanged<String>? onTapNote;
  final ValueChanged<ViewerInfo>? onLoaded;
  final ValueChanged<Map<String, dynamic>>? onBench;

  @override
  State<ScoreViewer> createState() => _ScoreViewerState();
}

class _ScoreViewerState extends State<ScoreViewer> {
  ScoreServer? _server;

  /// Ejecuta JavaScript en la página (según el WebView de la plataforma).
  Future<void> Function(String js)? _eval;

  /// Android: WebView del sistema (webview_flutter).
  WebViewController? _android;

  /// Windows: se crea una vez y se reconstruye con el mismo objeto.
  iaw.PlatformInAppWebViewWidget? _win;
  bool _ready = false;
  String? _error;

  /// Si el motor no arranca (a veces pasa al abrir una partitura justo
  /// tras cerrar otra), se recarga la página.
  Timer? _watchdog;
  int _reloads = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    widget.lit.addListener(_onLit);
    widget.marked?.addListener(_onLit);
    ScoreServer.instance().then(
      (s) {
        if (mounted) setState(() => _server = s);
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = 'No se pudo iniciar el visor: $e');
      },
    );
  }

  @override
  void didUpdateWidget(ScoreViewer old) {
    super.didUpdateWidget(old);
    if (old.lit != widget.lit) {
      old.lit.removeListener(_onLit);
      widget.lit.addListener(_onLit);
    }
    if (old.marked != widget.marked) {
      old.marked?.removeListener(_onLit);
      widget.marked?.addListener(_onLit);
    }
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if ((old.score != widget.score || old.revision != widget.revision) && _ready) _load();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _win?.dispose();
    widget.lit.removeListener(_onLit);
    widget.marked?.removeListener(_onLit);
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  Future<void> _run(String js) async {
    if (!_ready) return;
    try {
      await _eval?.call(js);
    } catch (e) {
      debugPrint('Visor: $e');
    }
  }

  /// Mensajes de la página: ready, loaded, tap, bench, error.
  void _onMessage(String name, Object? data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    switch (name) {
      case 'ready':
        _ready = true;
        _watchdog?.cancel();
        _load();
      case 'loaded':
        widget.onLoaded?.call(ViewerInfo(map));
        _onLit();
      case 'tap':
        final id = map['id'] as String?;
        if (id != null) widget.onTapNote?.call(id);
      case 'bench':
        widget.onBench?.call(map);
      case 'error':
        debugPrint('Visor: error ${map['message']}');
    }
  }

  void _onLit() =>
      _run('scale.highlight(${jsonEncode(widget.lit.value)}, true, ${jsonEncode(widget.marked?.value ?? const [])})');

  Future<void> _load() async {
    final server = _server;
    if (server == null) return;
    final score = widget.score;
    final (xml, notes) = await compute(_prepare, score);
    final (xmlUrl, notesUrl) = server.publish(xml, notes);
    await _run('scale.load(${jsonEncode(xmlUrl.toString())}, ${jsonEncode(notesUrl.toString())}, ${widget.zoom})');
  }

  /// MusicXML para Verovio y la lista de notas para unir sus ids con los de
  /// Scale si Verovio no los conserva.
  static (String, String) _prepare(Score score) {
    final xml = MusicXmlWriter.write(score);
    final notes = [
      for (final p in score.parts)
        for (final e in p.events) ...[
          for (final n in e.notes) {'id': n.id, 'q': e.tick / ticksPerQuarter, 'm': n.midi},
          if (e.isRest) {'id': e.id, 'r': 1},
        ],
    ];
    return (xml, jsonEncode(notes));
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) return Center(child: Text(error));
    final server = _server;
    if (server == null) return const Center(child: CircularProgressIndicator());
    return Platform.isWindows ? _windows(server) : _androidView(server);
  }

  Widget _androidView(ScoreServer server) {
    final c = _android ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF6F3EA))
      ..addJavaScriptChannel(
        'ScaleBridge',
        onMessageReceived: (m) {
          try {
            final msg = jsonDecode(m.message) as Map<String, dynamic>;
            _onMessage(msg['name'] as String, msg['data']);
          } catch (e) {
            debugPrint('Visor: mensaje ilegible: $e');
          }
        },
      )
      ..setOnConsoleMessage((m) => debugPrint('Visor JS: ${m.message}'))
      ..loadRequest(server.viewerUrl);
    _eval = c.runJavaScript;
    _watch(c.reload);
    return WebViewWidget(controller: c);
  }

  void _watch(Future<void> Function() reload) {
    if (_watchdog != null || _ready) return;
    _watchdog = Timer.periodic(const Duration(seconds: 6), (t) {
      if (_ready || _reloads >= 3) {
        t.cancel();
        return;
      }
      _reloads++;
      debugPrint('Visor: el motor no arrancó; recargando ($_reloads)');
      reload();
    });
  }

  /// Windows: WebView2 a través de flutter_inappwebview (solo su parte de Windows).
  Widget _windows(ScoreServer server) {
    final view = _win ??= iaw.PlatformInAppWebViewWidget(
      iaw.PlatformInAppWebViewWidgetCreationParams(
        initialUrlRequest: iaw.URLRequest(url: iaw.WebUri.uri(server.viewerUrl)),
        initialSettings: iaw.InAppWebViewSettings(
          javaScriptEnabled: true,
          supportZoom: false,
          disableContextMenu: true,
          transparentBackground: false,
          isInspectable: kDebugMode,
        ),
        onWebViewCreated: (c) {
          _eval = (js) => c.evaluateJavascript(source: js);
          for (final name in const ['ready', 'loaded', 'tap', 'bench', 'error']) {
            c.addJavaScriptHandler(
              handlerName: name,
              callback: (args) {
                _onMessage(name, args.isNotEmpty ? args.first : null);
                return null;
              },
            );
          }
        },
        onConsoleMessage: (c, m) => debugPrint('Visor JS: ${m.message}'),
      ),
    );
    return view.build(context);
  }
}
