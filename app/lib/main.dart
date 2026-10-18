import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'analysis/chord_engine.dart';
import 'midi/keyboard_state.dart';
import 'midi/midi_service.dart';
import 'screens/home_page.dart';
import 'settings.dart';
import 'storage/song_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final midi = MidiService()..init();
  final settings = AppSettings();
  final engine = ChordEngine(midi, settings);
  settings.load().then((_) => engine.layer = settings.liveLayer);
  runApp(ScaleApp(
    midi: midi,
    keyboard: KeyboardState(midi.events),
    engine: engine,
    settings: settings,
    repo: SongRepository()..load(),
  ));
}

class ScaleApp extends StatelessWidget {
  const ScaleApp({
    super.key,
    required this.midi,
    required this.keyboard,
    required this.engine,
    required this.settings,
    required this.repo,
  });

  final MidiService midi;
  final KeyboardState keyboard;
  final ChordEngine engine;
  final AppSettings settings;
  final SongRepository repo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scale',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: HomePage(
        midi: midi,
        keyboard: keyboard,
        engine: engine,
        settings: settings,
        repo: repo,
      ),
    );
  }
}
