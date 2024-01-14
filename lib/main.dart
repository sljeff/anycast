import 'package:anycast/states/tab.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'widgets/discover.dart';
import 'widgets/player.dart';
import 'widgets/playlists.dart';
import 'widgets/podcasts.dart';

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

  runApp(NavigationBarApp());
}

class NavigationBarApp extends StatelessWidget {
  final HomeTabController homeTabController = Get.put(HomeTabController());

  NavigationBarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      home: GetBuilder<HomeTabController>(
        builder: (controller) => Scaffold(
          floatingActionButton: PlayerWidget(),
          body: Center(
            child: IndexedStack(
              index: controller.selectedIndex,
              children: <Widget>[
                const PodcastsPage(),
                Playlists(),
                Discover(),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: controller.selectedIndex,
            onDestinationSelected: homeTabController.onItemTapped,
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
