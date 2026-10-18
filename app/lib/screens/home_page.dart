import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../midi/keyboard_state.dart';
import '../midi/midi_service.dart';
import '../settings.dart';
import '../storage/song_repository.dart';
import 'live_page.dart';
import 'song_list_page.dart';
import 'song_page.dart';

/// Navegación principal: tocar en vivo / biblioteca de canciones.
class HomePage extends StatefulWidget {
  const HomePage({
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
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  void openSong(Song song) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongPage(
          song: song,
          repo: widget.repo,
          settings: widget.settings,
          midi: widget.midi,
          engine: widget.engine,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          ListenableBuilder(
            listenable: widget.engine,
            builder: (context, _) => NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              // No se cambia de pantalla a mitad de una grabación.
              onDestinationSelected: widget.engine.recording ? null : (i) => setState(() => index = i),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.piano), label: Text('En vivo')),
                NavigationRailDestination(icon: Icon(Icons.library_music), label: Text('Canciones')),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [
                LivePage(
                  midi: widget.midi,
                  keyboard: widget.keyboard,
                  engine: widget.engine,
                  settings: widget.settings,
                  repo: widget.repo,
                  onOpenSong: openSong,
                ),
                SongListPage(repo: widget.repo, settings: widget.settings, onOpen: openSong),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
