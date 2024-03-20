import 'package:anycast/states/player.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/styles.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/widgets/bottom_nav_bar.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'pages/discover.dart';
import 'pages/player.dart';
import 'pages/playlists.dart';
import 'pages/podcasts.dart';

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
    Get.put(SettingsController());
    Get.put(SubtitleController());
    return GetMaterialApp(
      theme: ThemeData(
          colorScheme: const ColorScheme(
              brightness: Brightness.dark,
              primary: DarkColor.primary,
              onPrimary: DarkColor.primaryLightMax,
              secondary: DarkColor.secondaryColor,
              onSecondary: DarkColor.secondaryColor,
              error: DarkColor.accentColor,
              onError: DarkColor.accentColor,
              background: DarkColor.primaryBackgroundDark,
              onBackground: DarkColor.primaryBackgroundDark,
              surface: DarkColor.primaryBackgroundDark,
              onSurface: DarkColor.primaryBackgroundDark),
          textTheme: TextTheme(
            displayLarge: DarkColor.mainTitle,
            displayMedium: DarkColor.secondaryTitle,
            displaySmall: DarkColor.defaultMainText,
          )),
      home: GetBuilder<HomeTabController>(
        builder: (controller) => Scaffold(
          floatingActionButton: PlayerWidget(),
          body: Center(
            child: Obx(
              () => IndexedStack(
                index: controller.selectedIndex.value,
                children: <Widget>[
                  const PodcastsPage(),
                  Playlists(),
                  Discover(),
                ],
              ),
            ),
          ),
          bottomNavigationBar: const BottomNavBar(),
        ),
      ),
    );
  }
}
