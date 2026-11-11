import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scale/ai/claude_client.dart';
import 'package:scale/ai/groq_client.dart';
import 'package:scale/ai/import_session.dart';
import 'package:scale_core/scale_core.dart';

Map<String, dynamic> songJson({int repeats = 1}) => {
      'title': 'Santo',
      'key': 'D',
      'sections': [
        {
          'label': 'Verso',
          'kind': 'verse',
          'repeats': repeats,
          'note': '',
          'chords': [
            {'symbol': 'D', 'beats': 0},
            {'symbol': 'A', 'beats': 0},
            {'symbol': 'Bm', 'beats': 0},
            {'symbol': 'G', 'beats': 0},
          ],
        },
      ],
      'lyrics': '',
    };

http.Response reply(Map<String, dynamic> song, String text) => http.Response(
      jsonEncode({
        'id': 'msg_1',
        'type': 'message',
        'role': 'assistant',
        'model': 'claude-opus-5-5',
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'thinking', 'thinking': '', 'signature': 'sig-abc'},
          {'type': 'text', 'text': jsonEncode({'reply': text, 'song': song})},
        ],
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('primera vuelta: imagen + texto, salida estructurada y vista previa', () async {
    late http.Request sent;
    final session = ImportSession(
      ClaudeClient('sk-test', client: MockClient((request) async {
        sent = request;
        return reply(songJson(), 'Leí un verso en D.');
      })),
    );

    await session.send('Es de alabanza', [ImportImage(Uint8List.fromList([1, 2, 3]), 'image/jpeg')]);

    expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(sent.headers['x-api-key'], 'sk-test');
    expect(sent.headers['anthropic-version'], '2023-06-01');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['output_config']['format']['type'], 'json_schema');
    expect(body['thinking'], {'type': 'adaptive'});
    final content = body['messages'][0]['content'] as List;
    expect(content.first['type'], 'image');
    expect(content.first['source']['media_type'], 'image/jpeg');
    expect(content.last['text'], contains('Es de alabanza'));

    expect(session.error, isNull);
    expect(session.hasSong, isTrue);
    expect(session.result!.song.source, SongSource.image);
    expect(session.result!.song.key, MusicKey(2, Mode.major));
    expect(session.entries.map((e) => e.fromUser), [true, false]);
    expect(session.entries.last.text, 'Leí un verso en D.');
  });

  test('las correcciones reenvían la respuesta anterior sin cambios', () async {
    final bodies = <Map<String, dynamic>>[];
    var turn = 0;
    final session = ImportSession(
      ClaudeClient('sk-test', client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        turn++;
        return reply(songJson(repeats: turn), 'Listo.');
      })),
    );
    await session.send('D A Bm G', const []);
    await session.send('El verso se repite dos veces', const []);

    final messages = bodies.last['messages'] as List;
    expect(messages.map((m) => m['role']), ['user', 'assistant', 'user']);
    // El bloque de razonamiento vuelve tal cual, con su firma.
    expect(messages[1]['content'][0], {'type': 'thinking', 'thinking': '', 'signature': 'sig-abc'});
    expect(session.result!.song.arrangement.single.repeats, 2);
    expect(session.result!.song.chords, hasLength(8));
  });

  test('un error deja el historial intacto y devuelve el mensaje para reintentar', () async {
    final session = ImportSession(
      ClaudeClient('sk-mala', client: MockClient((request) async {
        return http.Response(jsonEncode({'type': 'error', 'error': {'message': 'invalid x-api-key'}}), 401);
      })),
    );
    await session.send('D A Bm G', const []);
    expect(session.error, contains('API key'));
    expect(session.entries, isEmpty);
    expect(session.lastFailed?.text, 'D A Bm G');
    expect(session.hasSong, isFalse);
  });

  test('si no se aceptan fallbacks, reintenta sin ellos', () async {
    final bodies = <Map<String, dynamic>>[];
    final session = ImportSession(
      ClaudeClient('sk-test', client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        if (body.containsKey('fallbacks')) {
          return http.Response(jsonEncode({'type': 'error', 'error': {'message': 'fallbacks: not supported'}}), 400);
        }
        return reply(songJson(), 'Ok');
      })),
    );
    await session.send('D A Bm G', const []);
    expect(bodies, hasLength(2));
    expect(bodies.last.containsKey('fallbacks'), isFalse);
    expect(session.hasSong, isTrue);
  });

  group('Groq', () {
    http.Response groqReply(Map<String, dynamic> song, String text, {String? wrap}) {
      final json = jsonEncode({'reply': text, 'song': song});
      return http.Response(
        jsonEncode({
          'id': 'chatcmpl-1',
          'object': 'chat.completion',
          'choices': [
            {
              'index': 0,
              'finish_reason': 'stop',
              'message': {'role': 'assistant', 'content': wrap == null ? json : wrap.replaceFirst('JSON', json)},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    test('texto: modelo de texto, esquema estricto y la conversación como chat', () async {
      final bodies = <Map<String, dynamic>>[];
      late http.Request sent;
      final session = ImportSession(GroqClient('gsk-test', client: MockClient((request) async {
        sent = request;
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return groqReply(songJson(repeats: bodies.length), 'Listo.');
      })));
      await session.send('D A Bm G', const []);
      await session.send('El verso va dos veces', const []);

      expect(sent.url.toString(), 'https://api.groq.com/openai/v1/chat/completions');
      expect(sent.headers['authorization'], 'Bearer gsk-test');
      final body = bodies.last;
      expect(body['model'], GroqClient.defaultTextModel);
      expect(body['response_format']['type'], 'json_schema');
      expect(body['response_format']['json_schema']['strict'], isTrue);
      final messages = body['messages'] as List;
      expect(messages.map((m) => m['role']), ['system', 'user', 'assistant', 'user']);
      expect(jsonDecode(messages[2]['content'] as String)['reply'], 'Listo.');
      expect(session.provider, AiProvider.groq);
      expect(session.result!.song.arrangement.single.repeats, 2);
    });

    test('fotos: modelo de visión y solo se reenvían las imágenes del último mensaje', () async {
      final bodies = <Map<String, dynamic>>[];
      final session = ImportSession(GroqClient('gsk-test', visionModel: 'mi/vision', client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        // Algunos modelos envuelven el JSON en razonamiento o en ```.
        return groqReply(songJson(), 'Ok', wrap: '<think>mmm</think>\n```json\nJSON\n```');
      })));
      final image = ImportImage(Uint8List.fromList([1, 2, 3]), 'image/png');
      await session.send('', [image]);
      expect(session.error, isNull);
      expect(bodies.last['model'], 'mi/vision');
      final parts = bodies.last['messages'][1]['content'] as List;
      expect(parts.last['image_url']['url'], 'data:image/png;base64,AQID');

      await session.send('La segunda página', [image]);
      final messages = bodies.last['messages'] as List;
      expect(messages[1]['content'], isA<String>());
      expect(messages[1]['content'], contains('adjunté 1 imagen'));
      expect((messages[3]['content'] as List).whereType<Map>().where((p) => p['type'] == 'image_url'), hasLength(1));

      // Después, una corrección solo de texto usa el modelo de texto.
      await session.send('Cambia el título', const []);
      expect(bodies.last['model'], GroqClient.defaultTextModel);
    });

    test('más de 3 imágenes en un mensaje: avisa sin llamar', () async {
      var calls = 0;
      final session = ImportSession(GroqClient('gsk-test', client: MockClient((request) async {
        calls++;
        return groqReply(songJson(), 'Ok');
      })));
      final image = ImportImage(Uint8List.fromList([1]), 'image/jpeg');
      await session.send('', List.filled(4, image));
      expect(calls, 0);
      expect(session.error, contains('hasta 3'));
      expect(session.lastFailed!.images, hasLength(4));
    });

    test('si el modelo no acepta esquema, pide JSON con el esquema en las instrucciones', () async {
      final bodies = <Map<String, dynamic>>[];
      final session = ImportSession(GroqClient('gsk-test', textModel: 'otro/modelo', client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        if (body['response_format']['type'] == 'json_schema') {
          return http.Response(
            jsonEncode({'error': {'message': 'This model does not support response format `json_schema`', 'type': 'invalid_request_error'}}),
            400,
          );
        }
        return groqReply(songJson(), 'Ok');
      })));
      await session.send('D A Bm G', const []);
      expect(bodies, hasLength(2));
      expect(bodies.last['response_format'], {'type': 'json_object'});
      expect(bodies.last['messages'][0]['content'], contains('"sections"'));
      expect(session.hasSong, isTrue);
    });

    test('errores: key mala y límite de uso', () async {
      var status = 401;
      final session = ImportSession(GroqClient('gsk-mala', client: MockClient((request) async {
        return http.Response(jsonEncode({'error': {'message': 'Invalid API Key', 'type': 'invalid_request_error'}}), status);
      })));
      await session.send('D A Bm G', const []);
      expect(session.error, contains('API key'));
      status = 429;
      await session.send('D A Bm G', const []);
      expect(session.error, contains('límite'));
      expect(session.entries, isEmpty);
    });
  });
}
