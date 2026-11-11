import '../settings.dart';
import 'ai_client.dart';
import 'claude_client.dart';
import 'groq_client.dart';

/// El cliente del servicio de IA elegido en Configuración.
AiClient aiClientFor(AppSettings s) => switch (s.aiProvider) {
      AiProvider.claude => ClaudeClient(s.anthropicApiKey),
      AiProvider.groq => GroqClient(
          s.groqApiKey,
          textModel: s.groqTextModel,
          visionModel: s.groqVisionModel,
        ),
    };
