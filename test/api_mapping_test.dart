import 'dart:convert';

import 'package:anycast/api/podcasts.dart';
import 'package:anycast/api/share.dart';
import 'package:anycast/api/subtitles.dart';
import 'package:anycast/models/subtitle.dart';
import 'package:anycast/models/translation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('podcast API mapping', () {
    test('normalizes a channel response into the persisted model', () {
      final channel = resMap2Channel({
        'rss_url': 'https://example.com/feed.xml',
        'title': '  Example Show  ',
        'description': '  A useful description  ',
        'small_cover_url': 'https://example.com/cover.jpg',
        'link': 'https://example.com/show',
        'keywords': ['technology', 'news'],
        'author': '  Example Host  ',
      });

      expect(channel.toMap(), {
        'rssFeedUrl': 'https://example.com/feed.xml',
        'title': 'Example Show',
        'description': 'A useful description',
        'imageUrl': 'https://example.com/cover.jpg',
        'link': 'https://example.com/show',
        'categories': 'technology,news',
        'author': 'Example Host',
        'email': '',
        'lastUpdated': null,
      });
    });

    test('parses release dates with offsets and accepts a missing date', () {
      expect(parsePubDate(null), isNull);
      expect(
        parsePubDate('2024-07-29T15:35:52+08:00')!.toUtc(),
        DateTime.utc(2024, 7, 29, 7, 35, 52),
      );
    });
  });

  group('subtitle API mapping', () {
    test('round-trips a subtitle segment', () {
      final subtitle = Subtitle.fromMap({
        'start': 1.25,
        'end': 2.5,
        'text': 'Hello',
      });

      expect(subtitle.toJson(), {
        'start': 1.25,
        'end': 2.5,
        'text': 'Hello',
      });
    });

    test('converts stored subtitle segments to LRC', () {
      final model = SubtitleModel.empty()
        ..subtitle = jsonEncode([
          {
            'start': 1.25,
            'end': 2.5,
            'text': 'Hello',
          },
          {
            'start': 61.125,
            'end': 62.0,
            'text': '世界',
          },
        ]);

      expect(
        model.toLrc(),
        '[00:01.250]Hello\n'
        '[00:02.500]\n'
        '[01:01.125]世界\n'
        '[01:02.000]\n',
      );
    });

    test('returns empty LRC for unavailable subtitle payloads', () {
      expect(SubtitleModel.empty().toLrc(), isEmpty);
      expect((SubtitleModel.empty()..subtitle = '').toLrc(), isEmpty);
      expect((SubtitleModel.empty()..subtitle = 'null').toLrc(), isEmpty);
    });

    test('converts stored translation segments to LRC', () {
      final model = TranslationModel.empty()
        ..translation = jsonEncode([
          {
            'start': 3.0,
            'end': 4.75,
            'text': 'Translated',
          },
        ]);

      expect(
        model.toLrc(),
        '[00:03.000]Translated\n'
        '[00:04.750]\n',
      );
      expect(TranslationModel.empty().toLrc(), isEmpty);
    });
  });

  test('short-link keys use stable MD5 hashing', () {
    expect(
      getMd5('https://example.com/episode?id=42'),
      '48725ff2a3c8d3e4094cd09e529fe590',
    );
  });
}
