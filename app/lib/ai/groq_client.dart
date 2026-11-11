import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';

/// Cliente de Groq (API compatible con la de chat de OpenAI). Usa un modelo
/// de texto para las conversaciones sin imágenes y uno de visión cuando el
/// mensaje trae fotos o capturas.
///
/// Groq acepta pocas imágenes por solicitud, así que solo se mandan las del
/// último mensaje: las anteriores ya están transcritas en la respuesta previa
/// (que lleva la canción completa).
class GroqClient implements AiClient {
  GroqClient(
    this.apiKey, {
    String? textModel,
    String? visionModel,
    http.Client? client,
  })  : textModel = _or(textModel, defaultTextModel),
        visionModel = _or(visionModel, defaultVisionModel),
        _http = client ?? http.Client();

  static const String defaultTextModel = 'openai/gpt-oss-120b';
  static const String defaultVisionModel = 'qwen/qwen3.8-27b';
  static const int maxImages = 3;
  static const String _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  final String apiKey;
  final String textModel;
  final String visionModel;
  final http.Client _http;

  static String _or(String? value, String fallback) =>
      value == null || value.trim().isEmpty ? fallback : value.trim();

  @override
  AiProvider get provider => AiProvider.groq;

  @override
  Future<AiReply> complete({
    required String system,
    required List<AiTurn> history,
    required Map<String, dynamic> schema,
    required String schemaName,
  }) async {
    final lastUser = history.lastIndexWhere((t) => t.fromUser);
    final images = lastUser < 0 ? const <ImportImage>[] : history[lastUser].images;
    if (images.length > maxImages) {
      throw const AiException(
        'Groq acepta hasta $maxImages imágenes por mensaje. '
        'Envía las demás en otro mensaje (de la misma canción) o usa Claude.',
      );
    }
    final model = images.isEmpty ? textModel : visionModel;
    final messages = [
      for (var i = 0; i < history.length; i++) _message(history[i], withImages: i == lastUser),
    ];

    // Primero con esquema estricto; si el modelo no lo acepta, en modo JSON
    // con el esquema en las instrucciones.
    var strict = true;
    for (var attempt = 0;; attempt++) {
      final response = await aiPost(
        _http,
        _endpoint,
        {'content-type': 'application/json', 'authorization': 'Bearer $apiKey'},
        {
          'model': model,
          'messages': [
            {'role': 'system', 'content': strict ? system : _withSchema(system, schema)},
            ...messages,
          ],
          'response_format': strict
              ? {
                  'type': 'json_schema',
                  'json_schema': {'name': schemaName, 'strict': true, 'schema': schema},
                }
              : {'type': 'json_object'},
          'max_completion_tokens': 16000,
        },
      );
      if (response.statusCode == 200) return _reply(aiDecode(response.body));

      final error = aiErrorMessage(response);
      final lower = error.toLowerCase();
      if (response.statusCode == 400 && strict && _rejectsSchema(lower)) {
        strict = false;
        continue;
      }
      // El JSON no cumplió el esquema: se reintenta una vez.
      if ((response.statusCode == 400 || response.statusCode == 422) && _badJson(lower)) {
        if (attempt < 1) continue;
        throw const AiException('La IA respondió en un formato inesperado. Inténtalo de nuevo.', retryable: true);
      }
      if (response.statusCode == 400 && images.isNotEmpty && lower.contains('image')) {
        throw AiException('Groq no aceptó las imágenes: $error');
      }
      throw aiHttpError(provider, response.statusCode, error);
    }
  }

  static bool _rejectsSchema(String error) =>
      (error.contains('response_format') || error.contains('json_schema') || error.contains('strict')) &&
      !_badJson(error);

  static bool _badJson(String error) =>
      error.contains('json_validate') ||
      error.contains('does not match') ||
      error.contains('failed to generate json') ||
      error.contains('invalid json');

  static String _withSchema(String system, Map<String, dynamic> schema) =>
      '$system\n\nResponde solo con un objeto JSON (sin texto antes ni después) '
      'que cumpla exactamente este esquema JSON:\n${jsonEncode(schema)}';

  static Map<String, dynamic> _message(AiTurn turn, {required bool withImages}) {
    if (!turn.fromUser) return {'role': 'assistant', 'content': turn.text};
    if (turn.images.isEmpty) return {'role': 'user', 'content': turn.text};
    if (!withImages) {
      final n = turn.images.length;
      return {
        'role': 'user',
        'content': '${turn.text}\n\n(Aquí adjunté $n ${n == 1 ? 'imagen' : 'imágenes'}; '
            'tu respuesta a este mensaje ya ${n == 1 ? 'la' : 'las'} transcribió.)',
      };
    }
    return {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': turn.text},
        for (final image in turn.images)
          {
            'type': 'image_url',
            'image_url': {'url': 'data:${image.mediaType};base64,${image.base64}'},
          },
      ],
    };
  }

  static AiReply _reply(Map<String, dynamic> response) {
    final choices = response['choices'] as List? ?? const [];
    if (choices.isEmpty) throw const AiException('La IA no devolvió respuesta. Inténtalo de nuevo.', retryable: true);
    final choice = choices.first as Map<String, dynamic>;
    if (choice['finish_reason'] == 'length') {
      throw const AiException('La respuesta quedó incompleta (canción muy larga). Prueba por partes.');
    }
    final content = (choice['message'] as Map<String, dynamic>?)?['content'] as String? ?? '';
    final text = cleanJson(content);
    return AiReply(text, text);
  }

  /// Quita razonamiento visible (`<think>…</think>`) y bloques ``` que algunos
  /// modelos ponen alrededor del JSON.
  static String cleanJson(String content) {
    var text = content.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);
    return text;
  }
}
