import 'package:timeago/timeago.dart' as timeago;

String formatDatetime(int ts) {
  var dt = DateTime.fromMillisecondsSinceEpoch(ts);
  // in a week: use timeago; in this year: use month and day; else: use yyyy-mm-dd
  var now = DateTime.now();
  if (dt.isAfter(now.subtract(const Duration(days: 7)))) {
    return timeago.format(dt);
  } else if (dt.year == now.year) {
    return '${dt.month}-${dt.day}';
  } else {
    return '${dt.year}-${dt.month}-${dt.day}';
  }
}

String formatDuration(int ms) {
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
  // duration and playedDuration are both in milliseconds
  var remainingDuration = duration - playedDuration;
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
