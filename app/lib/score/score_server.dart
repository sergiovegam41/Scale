import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Servidor HTTP local (solo 127.0.0.1) que entrega al visor sus archivos y
/// la partitura abierta.
///
/// El WebView no puede cargar el motor (WebAssembly) desde `file://` en todas
/// las plataformas; desde un origen http local funciona igual en Android y
/// en Windows. Las rutas llevan un token aleatorio para que otra app del
/// equipo no pueda leer nada sin conocerlo.
class ScoreServer {
  ScoreServer._(this._server, this.token) {
    _server.listen(_handle);
  }

  static Future<ScoreServer>? _instance;

  static Future<ScoreServer> instance() => _instance ??= _start();

  static Future<ScoreServer> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final rnd = Random.secure();
    final token = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return ScoreServer._(server, token);
  }

  final HttpServer _server;
  final String token;

  /// Contenido servido en /score.musicxml y /notes.json.
  String scoreXml = '';
  String notesJson = '[]';

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}/$token/');
  Uri get viewerUrl => base.resolve('index.html');

  /// Cambia en cada carga para que el WebView no use una copia vieja.
  int _version = 0;

  (Uri, Uri) publish(String xml, String notes) {
    scoreXml = xml;
    notesJson = notes;
    _version++;
    return (base.resolve('score.musicxml?v=$_version'), base.resolve('notes.json?v=$_version'));
  }

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'application/javascript; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'txt': 'text/plain; charset=utf-8',
  };

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final segments = req.uri.pathSegments;
      if (segments.length < 2 || segments.first != token || req.method != 'GET') {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final path = segments.skip(1).join('/');
      if (path == 'score.musicxml') {
        _send(res, 'application/xml; charset=utf-8', scoreXml, cache: false);
      } else if (path == 'notes.json') {
        _send(res, _types['json']!, notesJson, cache: false);
      } else if (!path.contains('..')) {
        final data = await rootBundle.load('assets/score_viewer/$path');
        res.headers.contentType = ContentType.parse(_types[path.split('.').last] ?? 'application/octet-stream');
        res.headers.set(HttpHeaders.cacheControlHeader, 'max-age=86400');
        res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      debugPrint('Visor: ${req.uri.path}: $e');
      res.statusCode = HttpStatus.notFound;
    } finally {
      await res.close();
    }
  }

  static void _send(HttpResponse res, String type, String body, {required bool cache}) {
    res.headers.contentType = ContentType.parse(type);
    if (!cache) res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    res.write(body);
  }
}
