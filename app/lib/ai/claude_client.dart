import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Error de la API de Claude con un mensaje listo para mostrar.
class ClaudeException implements Exception {
  const ClaudeException(this.message, {this.retryable = false});

  final String message;

  /// Se puede reintentar (límite de uso, servicio ocupado, red).
  final bool retryable;

  @override
  String toString() => message;
}

/// Cliente mínimo de la API de mensajes de Claude por HTTP (Dart no tiene SDK
/// oficial). Pide salida estructurada (JSON con esquema) y razonamiento
/// adaptativo; si el modelo declina por seguridad, el servidor reintenta con
/// otro modelo (fallbacks).
class ClaudeClient {
  ClaudeClient(this.apiKey, {http.Client? client}) : _http = client ?? http.Client();

  static const String model = 'claude-opus-5-5';
  static const String _endpoint = 'https://api.anthropic.com/v1/messages';
  static const String _fallbackBeta = 'server-side-fallback-2026-07-01';

  final String apiKey;
  final http.Client _http;

  /// Envía la conversación y devuelve el mensaje de respuesta tal cual
  /// (incluye bloques de razonamiento que hay que reenviar sin cambios).
  Future<Map<String, dynamic>> createMessage({
    required String system,
    required List<Map<String, dynamic>> messages,
    required Map<String, dynamic> schema,
    int maxTokens = 16000,
  }) async {
    try {
      return await _post(system, messages, schema, maxTokens, fallbacks: true);
    } on _FallbackRejected {
      // Si la cuenta o el modelo no aceptan fallbacks, se pide sin ellos.
      return _post(system, messages, schema, maxTokens, fallbacks: false);
    }
  }

  Future<Map<String, dynamic>> _post(
    String system,
    List<Map<String, dynamic>> messages,
    Map<String, dynamic> schema,
    int maxTokens, {
    required bool fallbacks,
  }) async {
    final body = {
      'model': model,
      'max_tokens': maxTokens,
      'system': system,
      'messages': messages,
      'thinking': {'type': 'adaptive'},
      'output_config': {
        'effort': 'medium',
        'format': {'type': 'json_schema', 'schema': schema},
      },
      // Las imágenes se reenvían en cada vuelta del chat: el caché las abarata.
      'cache_control': {'type': 'ephemeral'},
      if (fallbacks) 'fallbacks': 'default',
    };
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              if (fallbacks) 'anthropic-beta': _fallbackBeta,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 5));
    } on TimeoutException {
      throw const ClaudeException('La IA tardó demasiado en responder. Inténtalo de nuevo.', retryable: true);
    } on SocketException {
      throw const ClaudeException('Sin conexión a internet. Importar necesita internet.', retryable: true);
    } on http.ClientException catch (e) {
      throw ClaudeException('No se pudo conectar con la IA: ${e.message}', retryable: true);
    }

    final json = _decode(response.body);
    if (response.statusCode == 200) return json;

    final error = (json['error'] as Map<String, dynamic>?)?['message'] as String? ?? response.body;
    if (fallbacks && response.statusCode == 400 && error.toLowerCase().contains('fallback')) {
      throw _FallbackRejected();
    }
    throw switch (response.statusCode) {
      401 => const ClaudeException('La API key no es válida. Revísala en ⚙ Configuración.'),
      403 => const ClaudeException('La API key no tiene permiso para usar este modelo.'),
      413 => const ClaudeException('Las imágenes son demasiado grandes. Prueba con menos o más pequeñas.'),
      429 => const ClaudeException('Se alcanzó el límite de uso de la API. Espera un momento.', retryable: true),
      529 || >= 500 =>
        const ClaudeException('El servicio de IA está ocupado. Inténtalo en un momento.', retryable: true),
      _ => ClaudeException('La IA rechazó la solicitud: $error'),
    };
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }
}

class _FallbackRejected implements Exception {}
