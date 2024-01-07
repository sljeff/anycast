import 'package:anycast/utils/audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'states/player.dart';
import 'states/playlist.dart';
import 'states/playlist_episode.dart';
import 'states/tab.dart';
import 'widgets/discover.dart';
import 'widgets/player.dart';
import 'widgets/playlists.dart';
import 'widgets/podcasts.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.kindjeff.anycast.audio',
      androidNotificationChannelName: 'Anycast',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  runApp(const NavigationBarApp());
}

class NavigationBarApp extends StatefulWidget {
  const NavigationBarApp({super.key});

  @override
  State<NavigationBarApp> createState() => _NavigationBarAppState();
}

class _NavigationBarAppState extends State<NavigationBarApp> {
  @override
  Widget build(BuildContext context) {
    var audioHandler = MyAudioHandler();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistEpisodeProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => TabProvider()),
        // player state
        StreamProvider<PlayerState?>(
          create: (context) => audioHandler.playbackStateStream,
          initialData: null,
        ),
        // position data
        StreamProvider(
          create: (context) => audioHandler.positionDataStream,
          initialData: null,
        ),
      ],
      child: MaterialApp(
        home: Consumer<TabProvider>(builder: (context, value, child) {
          var selectedIndex = value.selectedIndex;
          return Scaffold(
            floatingActionButton: const PlayerWidget(),
            body: Center(
              child: IndexedStack(
                index: selectedIndex,
                children: <Widget>[
                  const PodcastsPage(),
                  const Playlists(),
                  Discover(),
                ],
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (value) {
                Provider.of<TabProvider>(context, listen: false)
                    .setIndex(value);
              },
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
          );
        }),
      ),
    );
  }
}
