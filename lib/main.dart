import 'package:flutter/material.dart';
import 'states/player.dart';
import 'states/playlist.dart';
import 'states/playlist_episode.dart';
import 'widgets/discover.dart';
import 'widgets/player.dart';
import 'widgets/playlists.dart';
import 'widgets/podcasts.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const NavigationBarApp());
}

class NavigationBarApp extends StatefulWidget {
  const NavigationBarApp({super.key});

  @override
  State<NavigationBarApp> createState() => _NavigationBarAppState();
}

class _NavigationBarAppState extends State<NavigationBarApp> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistEpisodeProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          floatingActionButton: const PlayerWidget(),
          body: Center(
            child: IndexedStack(
              index: _selectedIndex,
              children: <Widget>[
                const PodcastsPage(),
                const Playlists(),
                Discover(),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (value) => setState(() {
              _selectedIndex = value;
            }),
            destinations: const <Widget>[
              NavigationDestination(
                label: 'Podcasts',
                icon: Icon(Icons.podcasts),
              ),
              NavigationDestination(
                label: 'Playlists',
                icon: Icon(Icons.playlist_play),
              ),
              NavigationDestination(
                label: 'Discover',
                icon: Icon(Icons.explore),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
