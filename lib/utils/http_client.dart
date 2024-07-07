import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

Future<http.Response?> fetchWithRetry(String url) async {
  try {
    return retry(
      () => http.get(Uri.parse(url)).timeout(const Duration(seconds: 10)),
      retryIf: (e) => e is SocketException || e is TimeoutException,
      maxAttempts: 3,
    );
  } catch (e) {
    return null;
  }
}

Future<Map<String, http.Response?>> fetchConcurrentWithRetry(
  List<String> urls, {
  int maxConcurrent = 8,
}) async {
  var results = <String, http.Response?>{};
  var futures = <Future<http.Response?>>[];
  var tempUrls = <String>[];
  for (var url in urls) {
    futures.add(fetchWithRetry(url));
    tempUrls.add(url);

    if (futures.length >= maxConcurrent) {
      var responses = await Future.wait(futures);

      for (var response in responses) {
        results[tempUrls[responses.indexOf(response)]] = response;
      }

      futures = <Future<http.Response?>>[];
      tempUrls = <String>[];
    }
  }

  if (futures.isNotEmpty) {
    var responses = await Future.wait(futures);

    for (var response in responses) {
      results[tempUrls[responses.indexOf(response)]] = response;
    }
  }

  return results;
}
