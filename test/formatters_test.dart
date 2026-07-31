import 'package:anycast/utils/formatters.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('duration formatting', () {
    test('formats zero, minute-only, and hour-long durations', () {
      expect(formatDuration(0), isEmpty);
      expect(
        formatDuration(const Duration(minutes: 99).inMilliseconds),
        '99m',
      );
      expect(
        formatDuration(const Duration(minutes: 100).inMilliseconds),
        '1h 40m',
      );
      expect(
        formatDuration(
          const Duration(hours: 2, minutes: 5).inMilliseconds,
        ),
        '2h 5m',
      );
    });

    test('formats remaining time and never reports a negative duration', () {
      expect(
        formatRemainingTime(Duration.zero, Duration.zero),
        isEmpty,
      );
      expect(
        formatRemainingTime(
          const Duration(minutes: 90),
          Duration.zero,
        ),
        '90m',
      );
      expect(
        formatRemainingTime(
          const Duration(hours: 2, minutes: 10),
          const Duration(minutes: 10),
        ),
        '2h 0m remaining',
      );
      expect(
        formatRemainingTime(
          const Duration(minutes: 10),
          const Duration(minutes: 12),
        ),
        '0m remaining',
      );
    });

    test('formats countdown and clock values at their special boundaries', () {
      expect(formatCountdown(Duration.zero), 'OFF');
      expect(formatCountdown(const Duration(seconds: -1)), 'OFF');
      expect(formatCountdown(const Duration(minutes: 60)), '1h');
      expect(
        formatCountdown(const Duration(minutes: 5, seconds: 7)),
        '05:07',
      );
      expect(
        formatTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '01:02:03',
      );
    });

    test('formats lyric timestamps with millisecond precision', () {
      expect(formatLrcTime(0), '00:00.000');
      expect(formatLrcTime(61.125), '01:01.125');
    });
  });

  group('URL formatting', () {
    test('extracts a host from a complete feed URL', () {
      expect(
        urlToDomain(
          'https://listener@example.com:8443/shows/feed.xml?from=app',
        ),
        'example.com',
      );
    });

    test('percent-encodes query keys and values in insertion order', () {
      expect(
        encodeQueryParameters({
          'episode url': 'https://example.com/a?x=1&y=2',
          'language': 'zh-TW',
        }),
        'episode%20url=https%3A%2F%2Fexample.com%2Fa%3Fx%3D1%26y%3D2'
        '&language=zh-TW',
      );
      expect(encodeQueryParameters({}), isEmpty);
    });
  });

  group('background safe colors', () {
    test('replaces colors that would make backgrounds unreadable', () {
      expect(getBackgroundSafeColor(Colors.white), const Color(0xFF113336));
      expect(getBackgroundSafeColor(Colors.black), Colors.black);
    });
  });

  group('HTML to text', () {
    test('handles missing, plain-text, and markup descriptions', () {
      expect(htmlToText(null), isEmpty);
      expect(htmlToText('  A plain description  '), 'A plain description');
      expect(
        htmlToText('<p>Hello <strong>world</strong> &amp; friends</p>'),
        'Hello world & friends',
      );
    });
  });
}
