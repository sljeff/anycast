import 'package:anycast/models/feed_episode.dart';
import 'package:anycast/models/history_episode.dart';
import 'package:anycast/models/player.dart';
import 'package:anycast/models/playlist.dart';
import 'package:anycast/models/playlist_episode.dart';
import 'package:anycast/models/settings.dart';
import 'package:anycast/models/subscription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('database model mapping', () {
    test('subscription preserves every API and persistence field', () {
      final source = <String, dynamic>{
        'id': 7,
        'rssFeedUrl': 'https://example.com/feed.xml',
        'title': 'Example Show',
        'description': 'A description',
        'imageUrl': 'https://example.com/cover.jpg',
        'link': 'https://example.com',
        'categories': 'technology,news',
        'author': 'Example Author',
        'email': 'host@example.com',
        'lastUpdated': 1722345678000,
      };

      expect(SubscriptionModel.fromMap(source).toMap(), source);
    });

    test('episode variants preserve common fields', () {
      final source = <String, dynamic>{
        'id': 8,
        'channelTitle': 'Example Show',
        'rssFeedUrl': 'https://example.com/feed.xml',
        'title': 'Episode 8',
        'description': 'Episode description',
        'duration': 3723000,
        'enclosureUrl': 'https://example.com/episode-8.mp3',
        'pubDate': 1722345678000,
        'imageUrl': 'https://example.com/episode-8.jpg',
      };

      expect(FeedEpisodeModel.fromMap(source).toMap(), source);
      expect(HistoryEpisodeModel.fromMap(source).toMap(), source);
    });

    test('playlist episode preserves queue-specific and common fields', () {
      final source = <String, dynamic>{
        'id': 9,
        'playlistId': 2,
        'position': 1.5,
        'playedDuration': 62000,
        'title': 'Queued Episode',
        'description': 'Queue description',
        'duration': 3661000,
        'enclosureUrl': 'https://example.com/queued.mp3',
        'pubDate': 1722345678000,
        'imageUrl': 'https://example.com/queued.jpg',
        'channelTitle': 'Queue Show',
        'rssFeedUrl': 'https://example.com/queue.xml',
      };

      final episode = PlaylistEpisodeModel.fromMap(source);

      expect(episode.toMap(), source);
      expect(
        PlaylistEpisodeModel.getPlayedAndTotalTime(62000, 3661000),
        '1:02 / 61:01',
      );
    });

    test('settings converts stored integers into application booleans', () {
      final settings = SettingsModel.fromMap({
        'id': 1,
        'darkMode': 1,
        'speed': 1.25,
        'skipSilence': 0,
        'autoSleepTimer': '22,7,2',
        'maxCacheCount': 20,
        'countryCode': 'TW',
        'targetLanguage': 'zh',
        'autoRefreshInterval': 600,
        'maxFeedEpisodes': 200,
        'maxHistoryEpisodes': 150,
        'continuousPlaying': 1,
      });

      expect(settings.darkMode, isTrue);
      expect(settings.skipSilence, isFalse);
      expect(settings.continuousPlaying, isTrue);
      expect(settings.speed, 1.25);
      expect(settings.countryCode, 'TW');
      expect(settings.targetLanguage, 'zh');
    });

    test('small models omit absent IDs and include present IDs', () {
      expect(
        PlaylistModel.fromMap({
          'id': 3,
          'title': 'Later',
          'position': 2,
        }).toMap(),
        {
          'id': 3,
          'title': 'Later',
          'position': 2,
        },
      );

      expect(
        PlayerModel.fromMap({
          'id': 1,
          'currentPlaylistId': 3,
        }).toMap(),
        {
          'id': 1,
          'currentPlaylistId': 3,
        },
      );

      expect(
        PlayerModel.empty().toMap(),
        {'currentPlaylistId': null},
      );
    });
  });
}
