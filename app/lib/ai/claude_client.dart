import 'package:http/http.dart' as http;

import 'ai_client.dart';

/// Cliente mínimo de la API de mensajes de Claude por HTTP (Dart no tiene SDK
/// oficial). Pide salida estructurada (JSON con esquema) y razonamiento
/// adaptativo; si el modelo declina por seguridad, el servidor reintenta con
/// otro modelo (fallbacks).
class ClaudeClient implements AiClient {
  ClaudeClient(this.apiKey, {http.Client? client}) : _http = client ?? http.Client();

  static const String model = 'claude-opus-5-5';
  static const String _endpoint = 'https://api.anthropic.com/v1/messages';
  static const String _fallbackBeta = 'server-side-fallback-2026-07-01';

  final String apiKey;
  final http.Client _http;

  @override
  AiProvider get provider => AiProvider.claude;

  @override
  Future<AiReply> complete({
    required String system,
    required List<AiTurn> history,
    required Map<String, dynamic> schema,
    required String schemaName,
  }) async {
    final messages = [for (final turn in history) _message(turn)];
    Map<String, dynamic> response;
    try {
      response = await _post(system, messages, schema, fallbacks: true);
    } on _FallbackRejected {
      // Si la cuenta o el modelo no aceptan fallbacks, se pide sin ellos.
      response = await _post(system, messages, schema, fallbacks: false);
    }
    return _reply(response);
  }

  static Map<String, dynamic> _message(AiTurn turn) => turn.fromUser
      ? {
          'role': 'user',
          'content': [
            for (final image in turn.images)
              {
                'type': 'image',
                'source': {'type': 'base64', 'media_type': image.mediaType, 'data': image.base64},
              },
            {'type': 'text', 'text': turn.text},
          ],
        }
      // La respuesta vuelve completa, con sus bloques de razonamiento.
      : {'role': 'assistant', 'content': turn.raw ?? [{'type': 'text', 'text': turn.text}]};

  static AiReply _reply(Map<String, dynamic> response) {
    final stop = response['stop_reason'];
    if (stop == 'refusal') {
      throw const AiException('La IA no pudo procesar esta solicitud. Prueba con otra imagen o texto.');
    }
    if (stop == 'max_tokens') {
      throw const AiException('La respuesta quedó incompleta (canción muy larga). Prueba por partes.');
    }
    final content = (response['content'] as List).cast<Map<String, dynamic>>();
    final text = content.where((b) => b['type'] == 'text').map((b) => b['text'] as String).join();
    return AiReply(text, content);
  }

  Future<Map<String, dynamic>> _post(
    String system,
    List<Map<String, dynamic>> messages,
    Map<String, dynamic> schema, {
    required bool fallbacks,
  }) async {
    final response = await aiPost(
      _http,
      _endpoint,
      {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        if (fallbacks) 'anthropic-beta': _fallbackBeta,
      },
      {
        'model': model,
        'max_tokens': 16000,
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
      },
    );
    if (response.statusCode == 200) return aiDecode(response.body);

    final error = aiErrorMessage(response);
    if (fallbacks && response.statusCode == 400 && error.toLowerCase().contains('fallback')) {
      throw _FallbackRejected();
    }
    throw aiHttpError(provider, response.statusCode, error);
  }
}

class _FallbackRejected implements Exception {}
