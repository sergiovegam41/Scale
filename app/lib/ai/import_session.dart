import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:scale_core/scale_core.dart';

import 'ai_client.dart';

export 'ai_client.dart' show AiClient, AiException, AiProvider, ImportImage;

/// Un mensaje del chat tal como se muestra.
class ChatEntry {
  const ChatEntry({required this.fromUser, required this.text, this.images = const [], this.sent});

  final bool fromUser;
  final String text;
  final List<ImportImage> images;

  /// Lo que se mandó de verdad cuando no es lo que se muestra (el texto de
  /// una página web).
  final String? sent;
}

/// Importar una canción desde imágenes o texto conversando con la IA: cada
/// respuesta trae un borrador completo que se valida con el núcleo y se
/// muestra como vista previa.
class ImportSession extends ChangeNotifier {
  ImportSession(this._client);

  final AiClient _client;

  AiProvider get provider => _client.provider;

  /// Conversación tal como se manda a la IA. Las respuestas se guardan
  /// completas (Claude necesita sus bloques de razonamiento) y nunca se editan.
  final List<AiTurn> _history = [];

  final List<ChatEntry> entries = [];
  SongDraft? draft;
  DraftResult? result;
  bool busy = false;
  String? error;

  bool get hasSong => result != null && result!.song.chords.isNotEmpty;

  static const String system = '''
Eres el asistente de importación de Scale, una app que usa un pianista de alabanza para anotar canciones.
Recibes capturas de cancioneros web, fotos de hojas o pizarras, o texto pegado, y devuelves la canción como datos.

Cómo leer la fuente:
- Acordes en notación americana (C, Dm, G7, D/F#, Bbsus4, Cmaj7). Si vienen en latina (Do, Rem, Sol7), conviértelos. Respeta exactamente el acorde escrito: no simplifiques ni "corrijas" la armonía.
- Si hay capo indicado para guitarra, escribe los acordes como suenan (transportados) y menciónalo en reply.
- Secciones en el orden en que se tocan. Si la fuente las nombra (Intro, Verso, Pre-coro, Coro, Puente, Final…), usa ese nombre y el tipo (kind) correspondiente. Si no las nombra, usa "Parte 1", "Parte 2"… con kind "other".
- repeats: vueltas seguidas de esa sección (×2, "2 veces", barras de repetición). Si no se indica, 1. Pon en chords una sola vuelta.
- Si una sección vuelve a aparecer más adelante (otro coro después del verso), agrégala de nuevo en su lugar como otra entrada.
- beats: tiempos del acorde solo si la fuente lo muestra (barras /, comillas ', compases); si no, 0.
- note: indicaciones para el músico que traiga la fuente ("suave", "sólo piano", "subir intensidad"); si no hay, "".
- key: la tonalidad si la fuente la indica ("Tono: G", "Key of D"); si no, "".
- lyrics: si hay letra, cópiala en formato ChordPro con los acordes entre corchetes donde caen; si no hay letra, "".
- Si no se lee bien un acorde, escribe tu mejor lectura y dilo en reply. No inventes partes que no estén.

En cada respuesta devuelve la canción completa (no solo los cambios) y en reply un mensaje breve en español: qué entendiste, dudas y qué cambiaste.
Cuando el usuario corrija algo (nombres, vueltas, acordes, orden), aplica su criterio: él conoce la canción.''';

  static final Map<String, dynamic> _schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['reply', 'song'],
    'properties': {
      'reply': {'type': 'string'},
      'song': SongDraft.jsonSchema,
    },
  };

  /// Con [shownAs], el chat muestra eso en vez del texto (largo) enviado.
  Future<void> send(String text, List<ImportImage> images, {String? shownAs}) async {
    final trimmed = text.trim();
    if (busy || (trimmed.isEmpty && images.isEmpty)) return;
    final first = _history.isEmpty;
    final prompt = trimmed.isEmpty
        ? (first ? 'Convierte esto en una canción.' : 'Agregué más imágenes de la misma canción.')
        : (first ? 'Convierte esto en una canción.\n\n$trimmed' : trimmed);

    entries.add(
      ChatEntry(fromUser: true, text: shownAs ?? trimmed, images: images, sent: shownAs == null ? null : trimmed),
    );
    _history.add(AiTurn.user(prompt, images));
    busy = true;
    error = null;
    lastFailed = null;
    notifyListeners();

    try {
      final reply = await _client.complete(
        system: system,
        history: _history,
        schema: _schema,
        schemaName: 'cancion',
      );
      final json = jsonDecode(reply.text) as Map<String, dynamic>;
      final newDraft = SongDraft.fromJson(json['song'] as Map<String, dynamic>);
      final newResult = newDraft.toSong(source: _hadImages ? SongSource.image : SongSource.import);
      // Validado: la respuesta completa queda en el historial, sin tocarla.
      _history.add(AiTurn.assistant(reply.text, reply.raw));
      draft = newDraft;
      result = newResult;
      entries.add(ChatEntry(fromUser: false, text: (json['reply'] as String? ?? '').trim()));
    } on AiException catch (e) {
      _undoLastUserTurn();
      error = e.message;
    } catch (e) {
      _undoLastUserTurn();
      error = 'La IA respondió en un formato inesperado. Inténtalo de nuevo.';
      debugPrint('Importar: respuesta no válida: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  bool get _hadImages => entries.any((e) => e.images.isNotEmpty);

  /// Si la vuelta falló, se quita el mensaje del usuario (y se le deja el
  /// texto para reintentar) para que el historial siga alternando turnos.
  void _undoLastUserTurn() {
    if (_history.isNotEmpty && _history.last.fromUser) _history.removeLast();
    if (entries.isNotEmpty && entries.last.fromUser) lastFailed = entries.removeLast();
  }

  /// Último mensaje que no se pudo enviar (para reintentarlo).
  ChatEntry? lastFailed;
}
