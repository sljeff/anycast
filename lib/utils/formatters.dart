import 'package:anycast/styles.dart';
import 'package:anycast/utils/rss_fetcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:sanitize_html/sanitize_html.dart';
import 'package:timeago/timeago.dart' as timeago;

// my_custom_messages.dart
String formatDatetime(int ts) {
  var dt = DateTime.fromMillisecondsSinceEpoch(ts);
  // in a week: use timeago; in this year: use month and day; else: use yyyy-mm-dd
  var now = DateTime.now();
  if (dt.isAfter(now.subtract(const Duration(days: 7)))) {
    var ago = timeago.format(dt, locale: 'en_short');
    if (ago == 'now') {
      return 'just now';
    }
    return "$ago ago";
  } else if (dt.year == now.year) {
    return '${dt.month}-${dt.day}';
  } else {
    return '${dt.year}-${dt.month}-${dt.day}';
  }
}

String formatDate(int ts) {
  var dt = DateTime.fromMillisecondsSinceEpoch(ts);

  var now = DateTime.now();
  if (dt.year == now.year) {
    return '${dt.month}-${dt.day}';
  }

  return '${dt.year}-${dt.month}-${dt.day}';
}

String formatDuration(int ms) {
  if (ms == 0) {
    return '';
  }
  var d = Duration(milliseconds: ms);
  // in 100m: show {n}m; else: show {n}h {m}m
  if (d.inMinutes < 100) {
    return '${d.inMinutes}m';
  } else {
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }
}

// if played: 73m remaining, 1h 13m remaining
// if not played: 73m, 1h 13m
String formatRemainingTime(Duration duration, Duration playedDuration) {
  String remainingTime = '';
  if (duration.inSeconds == 0) {
    return '';
  }

  // duration and playedDuration are both in milliseconds
  var remainingDuration = duration - playedDuration;
  remainingDuration =
      remainingDuration > Duration.zero ? remainingDuration : Duration.zero;
  // if less than 100 minutes, show minutes; otherwise show hours and minutes
  if (remainingDuration.inMinutes < 100) {
    remainingTime = '${remainingDuration.inMinutes}m';
  } else {
    remainingTime =
        '${remainingDuration.inHours}h ${remainingDuration.inMinutes.remainder(60)}m';
  }

  if (playedDuration.inSeconds > 0) {
    return '$remainingTime remaining';
  } else {
    return remainingTime;
  }
}

Widget renderHtml(BuildContext context, String html) {
  if (html.isEmpty) {
    return const SizedBox.shrink();
  }
  // if starts with <
  if (html.trim().startsWith('<')) {
    var sanitized = sanitizeHtml(html).trim();
    if (sanitized.isEmpty) {
      sanitized = htmlToText(html);
    }
    return HtmlWidget(
      sanitized,
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        height: 1.2,
        inherit: false,
      ),
      onErrorBuilder: (context, error, any) => Text(
        error.toString(),
        style: GoogleFonts.robotoMono(
          color: Colors.red,
          fontSize: 12,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  return Text(html, style: DarkColor.defaultMainText);
}

String formatCountdown(Duration duration) {
  if (duration.inSeconds <= 0) {
    return 'OFF';
  }
  if (duration.inMinutes == 60) {
    return '1h';
  }

  var minutes = duration.inMinutes.remainder(60);
  var seconds = duration.inSeconds.remainder(60);
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

// hh:mm:ss
String formatTime(Duration duration) {
  var hours = duration.inHours.remainder(60);
  var minutes = duration.inMinutes.remainder(60);
  var seconds = duration.inSeconds.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

// example: https://www.ximalaya.com/album/41563226.xml => ximalaya.com
String urlToDomain(String url) {
  var uri = Uri.parse(url);
  return uri.host;
}

Color getTextSafeColor(Color dynamicColor) {
  // 定义亮度阈值，低于这个值就认为颜色太暗
  const double brightnessThreshold = 0.2;

  // 计算颜色的亮度
  double brightness = dynamicColor.computeLuminance();

  if (brightness < brightnessThreshold) {
    // 如果颜色太暗，返回一个替代颜色
    return const Color(0xFF10B981);
  } else {
    // 如果颜色亮度足够，返回原始的动态颜色
    return dynamicColor;
  }
}

Color getBackgroundSafeColor(Color dynamicColor) {
  const double brightnessThreshold = 0.7;

  double brightness = dynamicColor.computeLuminance();

  if (brightness > brightnessThreshold) {
    return const Color(0xFF113336);
  } else {
    return dynamicColor;
  }
}

Future<Color> updatePaletteGenerator(String imageUrl) async {
  final PaletteGenerator generator =
      await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(
    imageUrl,
  ));
  final Color dominantColor =
      generator.dominantColor?.color ?? const Color(0xFF111316);

  return dominantColor;
  // return getBackgroundSafeColor(dominantColor);
}

// seconds to mm:ss.xx
String formatLrcTime(double time) {
  var minutes = (time / 60).floor();
  var seconds = (time % 60).floor();
  var milliseconds = ((time * 1000) % 1000).floor();
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(3, '0')}';
}

String? encodeQueryParameters(Map<String, String> params) {
  return params.entries
      .map((MapEntry<String, String> e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}

double getTextWidth(String text, TextStyle style,
    {double maxWidth = double.infinity}) {
  final TextPainter textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout(minWidth: 0, maxWidth: maxWidth);
  return textPainter.width;
}
