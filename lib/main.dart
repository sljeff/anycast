import 'package:anycast/states/cache.dart';
import 'package:anycast/states/discover.dart';
import 'package:anycast/states/feed_episode.dart';
import 'package:anycast/states/player.dart';
import 'package:anycast/states/playlist.dart';
import 'package:anycast/states/subscription.dart';
import 'package:anycast/states/subtitle.dart';
import 'package:anycast/states/tab.dart';
import 'package:anycast/states/translation.dart';
import 'package:anycast/states/user.dart';
import 'package:anycast/styles.dart';
import 'package:anycast/utils/audio_handler.dart';
import 'package:anycast/widgets/bottom_nav_bar.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pages/discover.dart';
import 'pages/playlists.dart';
import 'pages/podcasts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

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

  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://9168d8befab4c7bb5eeecd15beb2daa2@o359483.ingest.us.sentry.io/4507654787170304';
      // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
      // We recommend adjusting this value in production.
      options.tracesSampleRate = 1.0;
      // The sampling rate for profiling is relative to tracesSampleRate
      // Setting to 1.0 will profile 100% of sampled transactions:
      options.profilesSampleRate = 1.0;
    },
    appRunner: () => runApp(const NavigationBarApp()),
  );
}

class NavigationBarApp extends StatelessWidget {
  static final homeTabController = Get.put(HomeTabController());

  const NavigationBarApp({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(SettingsController());
    Get.put(SubtitleController());
    Get.put(SubscriptionController());
    Get.put(PlayerController());
    Get.put(PlaylistController());
    Get.put(CacheController());
    Get.lazyPut(() => DiscoverController());
    Get.lazyPut(() => FeedEpisodeController());
    Get.put(TranslationController());
    Get.put(AuthController());
    Get.put(RevenueCatController());
    return GetMaterialApp(
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          toolbarHeight: 156,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          centerTitle: false,
        ),
        colorScheme: const ColorScheme(
            brightness: Brightness.dark,
            primary: DarkColor.primary,
            onPrimary: DarkColor.primaryLightMax,
            secondary: DarkColor.secondaryColor,
            onSecondary: DarkColor.secondaryColor,
            error: DarkColor.accentColor,
            onError: DarkColor.accentColor,
            surface: DarkColor.primaryBackgroundDark,
            onSurface: DarkColor.primaryBackgroundDark),
        textTheme: TextTheme(
          displayLarge: DarkColor.mainTitle,
          displayMedium: DarkColor.secondaryTitle,
          displaySmall: DarkColor.defaultMainText,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          modalBackgroundColor: Color(0xFF111316),
          modalElevation: 0,
          backgroundColor: Color(0xFF111316),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
        ),
        tabBarTheme: TabBarTheme(
          labelColor: const Color(0xFF6EE7B7),
          indicatorColor: const Color(0xFF6EE7B7),
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: const Color(0xFF9CA3AF),
          dividerHeight: 1,
          labelStyle: TextStyle(
            fontSize: 12,
            fontFamily: GoogleFonts.comfortaa().fontFamily,
            fontWeight: FontWeight.w400,
          ),
          unselectedLabelColor: const Color(0xFFD1D5DB),
          unselectedLabelStyle: TextStyle(
            fontSize: 12,
            fontFamily: GoogleFonts.comfortaa().fontFamily,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      home: Scaffold(
        body: Obx(
          () => IndexedStack(
            index: homeTabController.selectedIndex.value,
            children: const [
              PodcastsPage(),
              Playlists(),
              Discover(),
            ],
          ),
        ),
        bottomNavigationBar: const BottomNavBar(),
      ),
    );
  }
}
