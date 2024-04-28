import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/states/user.dart';
import 'package:anycast/styles.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/widgets/bottom_nav_bar.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'pages/discover.dart';
import 'pages/playlists.dart';
import 'pages/podcasts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

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

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(NavigationBarApp());
}

class NavigationBarApp extends StatelessWidget {
  final homeTabController = Get.put(HomeTabController());

  NavigationBarApp({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(SettingsController());
    Get.put(SubtitleController());
    Get.put(SubscriptionController());
    Get.put(PlayerController());
    Get.put(PlaylistController());
    Get.put(UserController());
    return GetMaterialApp(
      theme: ThemeData(
        appBarTheme: AppBarTheme(
          toolbarHeight: 100,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          centerTitle: false,
          iconTheme: const IconThemeData(
            color: DarkColor.primaryLightMax,
          ),
          actionsIconTheme: const IconThemeData(
            color: DarkColor.primaryLightMax,
          ),
        ),
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
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          modalBackgroundColor: DarkColor.primaryBackground,
          modalElevation: 0,
          backgroundColor: DarkColor.primaryBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
        ),
      ),
      home: GetBuilder<HomeTabController>(
        builder: (controller) => Scaffold(
          body: Center(
            child: Obx(
              () => IndexedStack(
                index: controller.selectedIndex.value,
                children: <Widget>[
                  const PodcastsPage(),
                  const Playlists(),
                  Discover(),
                ],
              ),
            ),
          ),
          bottomNavigationBar: BottomNavBar(),
        ),
      ),
    );
  }
}
