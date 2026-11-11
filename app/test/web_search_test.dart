import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scale/ai/groq_client.dart';
import 'package:scale/score/score_import.dart';
import 'package:scale/web/captured_page.dart';
import 'package:scale/web/search_plan.dart';
import 'package:scale/web/web_sites.dart';

void main() {
  group('sitios', () {
    test('con buscador propio o por Google con site:', () {
      final ug = WebSites.byId('ultimateguitar')!;
      expect(ug.searchUri('way maker').toString(),
          'https://www.ultimate-guitar.com/search.php?search_type=title&value=way+maker');
      final lc = WebSites.byId('lacuerda')!;
      final u = lc.searchUri('Santo Santo');
      expect(u.host, 'www.google.com');
      expect(u.queryParameters['q'], 'Santo Santo site:lacuerda.net');
    });

    test('Google agrega el tipo si falta', () {
      expect(WebSites.googleFor('Way Maker', WebWant.chords).queryParameters['q'], 'Way Maker acordes');
      expect(WebSites.googleFor('Way Maker acordes', WebWant.chords).queryParameters['q'], 'Way Maker acordes');
    });

    test('una dirección escrita se reconoce', () {
      expect(WebSites.asUrl('lacuerda.net')!.toString(), 'https://lacuerda.net');
      expect(WebSites.asUrl('https://bitmidi.com/x-mid')!.host, 'bitmidi.com');
      expect(WebSites.asUrl('way maker'), isNull);
      expect(WebSites.asUrl('sinach'), isNull);
    });

    test('todos los tipos tienen sitios', () {
      for (final w in WebWant.values) {
        expect(WebSites.forWant(w), isNotEmpty);
      }
    });
  });

  group('plan', () {
    test('sin IA adivina el tipo y limpia el texto', () {
      expect(SearchPlan.guess('Way Maker acordes').want, WebWant.chords);
      expect(SearchPlan.guess('Way Maker acordes').query, 'Way Maker');
      expect(SearchPlan.guess('observatorio astral partitura piano').want, WebWant.score);
      expect(SearchPlan.guess('tetris midi').want, WebWant.midi);
      expect(SearchPlan.guess('tetris midi').sites, contains('bitmidi'));
    });

    test('de la IA: se descartan sitios inventados y se completa', () {
      final p = SearchPlan.fromJson({
        'title': 'Way Maker',
        'artist': 'Sinach',
        'want': 'chords',
        'query': 'Way Maker Sinach',
        'sites': ['lacuerda', 'acordes-falsos.com', 'lacuerda', 'cifraclub'],
        'note': '',
      }, 'way maker');
      expect(p.sites, ['lacuerda', 'cifraclub']);
      expect(p.fromAi, isTrue);
      final empty = SearchPlan.fromJson({'want': 'midi', 'query': '', 'sites': []}, 'tetris');
      expect(empty.query, 'tetris');
      expect(empty.sites, isNotEmpty);
    });

    test('se pide a la IA rápido y con esquema', () async {
      late Map<String, dynamic> body;
      final client = GroqClient('gsk', client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        final plan = {
          'title': 'Observatorio Astral',
          'artist': 'Koji Kondo',
          'want': 'score',
          'query': 'Astral Observatory Majoras Mask',
          'sites': ['ninsheetmusic', 'musescore'],
          'note': 'Es de videojuego.',
        };
        return http.Response(
          jsonEncode({
            'choices': [
              {'finish_reason': 'stop', 'message': {'role': 'assistant', 'content': jsonEncode(plan)}},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }));
      final p = await SearchPlan.ask(client, 'el observatorio astral de zelda majoras mask para piano');
      expect(body['reasoning_effort'], 'low');
      expect(body['response_format']['json_schema']['schema']['properties']['sites']['items']['enum'],
          contains('ninsheetmusic'));
      expect(p.want, WebWant.score);
      expect(p.siteList.first.name, 'Ninsheetmusic');
    });
  });

  test('tipo de archivo descargado por su contenido', () {
    Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));
    expect(ScoreFileKind.of(b('MThd\x00\x00\x00\x06')), ScoreFileKind.midi);
    expect(ScoreFileKind.of(b('%PDF-1.7')), ScoreFileKind.pdf);
    expect(ScoreFileKind.of(b('<?xml version="1.0"?><!DOCTYPE score-partwise><score-partwise>')),
        ScoreFileKind.musicXml);
    expect(ScoreFileKind.of(b('<!DOCTYPE html><html>')), ScoreFileKind.html);
    expect(ScoreFileKind.of(b('PK\x03\x04 META-INF/container.xml')), ScoreFileKind.musicXml);
    expect(ScoreFileKind.of(b('PK\x03\x04 cosas')), ScoreFileKind.unknown);
    expect(ScoreFileKind.of(b('hola')), ScoreFileKind.unknown);
  });

  test('la página va a la IA con su origen y se muestra corta', () {
    final page = CapturedPage(
      url: Uri.parse('https://lacuerda.net/x/santo'),
      title: 'Santo - Acordes',
      text: 'D A Bm G\nSanto santo',
    );
    expect(page.prompt, contains('https://lacuerda.net/x/santo'));
    expect(page.prompt, endsWith('D A Bm G\nSanto santo'));
    expect(page.label, 'Página: Santo - Acordes\nlacuerda.net');
  });
}
