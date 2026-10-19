import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scale/ai/claude_client.dart';
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
      'sk-test',
      client: ClaudeClient('sk-test', client: MockClient((request) async {
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
      'sk-test',
      client: ClaudeClient('sk-test', client: MockClient((request) async {
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
      'sk-mala',
      client: ClaudeClient('sk-mala', client: MockClient((request) async {
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
      'sk-test',
      client: ClaudeClient('sk-test', client: MockClient((request) async {
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
}
