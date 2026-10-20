import 'package:flutter/material.dart';
import 'package:scale_core/scale_core.dart';

import '../analysis/chord_engine.dart';
import '../midi/keyboard_state.dart';
import '../midi/midi_service.dart';
import '../settings.dart';
import '../storage/song_repository.dart';
import '../voice/singer_engine.dart';
import '../widgets/responsive.dart';
import 'live_page.dart';
import 'play_page.dart';
import 'singer_page.dart';
import 'song_list_page.dart';
import 'song_page.dart';
import 'tools_page.dart';

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
  final SingerEngine singer = SingerEngine();

  static const int _singerTab = 2;

  @override
  void dispose() {
    singer.dispose();
    super.dispose();
  }

  void _select(int i) {
    // El micrófono solo escucha mientras la pestaña del cantante está abierta.
    if (i != _singerTab) singer.stop();
    setState(() => index = i);
  }

  /// Abre una canción; con [play], directo a tocarla en ese modo.
  void openSong(Song song, {bool edit = false, PlayMode? play}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongPage(
          song: song,
          startEditing: edit,
          startPlaying: play,
          onOpenSong: openSong,
          repo: widget.repo,
          settings: widget.settings,
          midi: widget.midi,
          engine: widget.engine,
        ),
      ),
    );
  }

  static const _tabs = [
    (Icons.piano, 'En vivo'),
    (Icons.library_music, 'Canciones'),
    (Icons.mic, 'Cantante'),
    (Icons.donut_large, 'Herramientas'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
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
        SongListPage(
          repo: widget.repo,
          settings: widget.settings,
          onOpen: openSong,
          onCreate: (song) => openSong(song, edit: true),
        ),
        SingerPage(engine: singer, repo: widget.repo, settings: widget.settings),
        ToolsPage(midi: widget.midi, settings: widget.settings),
      ],
    );
    // En el teléfono las pestañas van abajo; en la tablet, al costado.
    if (context.isCompact) {
      return Scaffold(
        body: pages,
        bottomNavigationBar: ListenableBuilder(
          listenable: widget.engine,
          builder: (context, _) => NavigationBar(
            height: 64,
            selectedIndex: index,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            // No se cambia de pantalla a mitad de una grabación.
            onDestinationSelected: widget.engine.recording ? null : _select,
            destinations: [
              for (final (icon, label) in _tabs) NavigationDestination(icon: Icon(icon), label: label),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          ListenableBuilder(
            listenable: widget.engine,
            builder: (context, _) => NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              // No se cambia de pantalla a mitad de una grabación.
              onDestinationSelected: widget.engine.recording ? null : _select,
              destinations: [
                for (final (icon, label) in _tabs) NavigationRailDestination(icon: Icon(icon), label: Text(label)),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages),
        ],
      ),
    );
  }
}
