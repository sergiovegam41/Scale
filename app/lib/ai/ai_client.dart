import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Servicio de IA que se usa para importar. Cada uno con su propia API key,
/// guardada solo en el dispositivo.
enum AiProvider {
  claude('Claude', 'Anthropic', 'console.anthropic.com'),
  groq('Groq', 'Groq', 'console.groq.com');

  const AiProvider(this.label, this.company, this.console);

  final String label;

  /// Quién da la API key (para los textos de ayuda).
  final String company;

  /// Dónde se saca la API key.
  final String console;
}

/// Imagen adjunta (ya reducida al tomarla de la cámara o la galería).
class ImportImage {
  const ImportImage(this.bytes, this.mediaType);

  final Uint8List bytes;

  /// image/jpeg, image/png o image/webp.
  final String mediaType;

  String get base64 => base64Encode(bytes);
}

/// Un turno de la conversación, igual para cualquier servicio.
class AiTurn {
  const AiTurn.user(this.text, [this.images = const []])
      : fromUser = true,
        raw = null;

  const AiTurn.assistant(this.text, this.raw)
      : fromUser = false,
        images = const [];

  final bool fromUser;
  final String text;
  final List<ImportImage> images;

  /// La respuesta tal como la devolvió el servicio. Claude necesita que se
  /// reenvíe sin cambios (lleva bloques de razonamiento firmados).
  final Object? raw;
}

/// Respuesta del servicio: el texto (JSON según el esquema pedido) y la
/// respuesta original para el historial.
class AiReply {
  const AiReply(this.text, this.raw);

  final String text;
  final Object? raw;
}

/// Error de la IA con un mensaje listo para mostrar.
class AiException implements Exception {
  const AiException(this.message, {this.retryable = false});

  final String message;

  /// Se puede reintentar (límite de uso, servicio ocupado, red).
  final bool retryable;

  @override
  String toString() => message;
}

/// Lo que necesita importar de un servicio de IA: mandar la conversación y
/// recibir un JSON que cumpla el esquema.
abstract class AiClient {
  AiProvider get provider;

  Future<AiReply> complete({
    required String system,
    required List<AiTurn> history,
    required Map<String, dynamic> schema,
    required String schemaName,

    /// Tarea corta y simple: que piense poco y responda rápido.
    bool quick = false,
  });
}

/// POST con los errores de red traducidos.
Future<http.Response> aiPost(
  http.Client client,
  String url,
  Map<String, String> headers,
  Map<String, dynamic> body,
) async {
  try {
    return await client
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(minutes: 5));
  } on TimeoutException {
    throw const AiException('La IA tardó demasiado en responder. Inténtalo de nuevo.', retryable: true);
  } on SocketException {
    throw const AiException('Sin conexión a internet. Importar necesita internet.', retryable: true);
  } on http.ClientException catch (e) {
    throw AiException('No se pudo conectar con la IA: ${e.message}', retryable: true);
  }
}

Map<String, dynamic> aiDecode(String body) {
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}

/// Mensaje del error que trae el cuerpo de la respuesta (los dos servicios
/// usan `{"error": {"message": ...}}`).
String aiErrorMessage(http.Response response) =>
    (aiDecode(response.body)['error'] as Map<String, dynamic>?)?['message'] as String? ?? response.body;

/// Error HTTP común a los servicios.
AiException aiHttpError(AiProvider provider, int status, String message) => switch (status) {
      401 => const AiException('La API key no es válida. Revísala en ⚙ Configuración.'),
      403 => const AiException('La API key no tiene permiso para usar este modelo.'),
      404 => AiException('${provider.label} no encontró el modelo: $message'),
      413 => const AiException('Las imágenes son demasiado grandes. Prueba con menos o más pequeñas.'),
      429 => const AiException('Se alcanzó el límite de uso de la API. Espera un momento.', retryable: true),
      498 || 529 || >= 500 =>
        const AiException('El servicio de IA está ocupado. Inténtalo en un momento.', retryable: true),
      _ => AiException('La IA rechazó la solicitud: $message'),
    };
