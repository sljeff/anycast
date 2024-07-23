import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anycast/states/user.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

Future<T> myRetry<T>(
  Future<T> Function() fn, {
  int retryTimes = 3,
}) async {
  return retry(
    () => fn(),
    retryIf: (e) => e is SocketException || e is TimeoutException,
    maxAttempts: retryTimes,
  );
}

Future<http.Response> reqWithAuth(
  String url, {
  String method = 'GET',
  Map<String, String>? headers,
  Object? data,
  int timeout = 10,
}) async {
  var token = await Get.find<AuthController>().getToken();
  if (token == null) {
    return http.Response('Unauthorized', 401);
  }
  headers = headers ?? {};
  headers['Authorization'] = 'Bearer $token';
  if (data != null) {
    headers['Content-Type'] = 'application/json';
    data = jsonEncode(data);
  }

  switch (method) {
    case 'GET':
      return myRetry(
        () => http
            .get(Uri.parse(url), headers: headers)
            .timeout(Duration(seconds: timeout)),
      );
    case 'POST':
      return myRetry(
        () => http
            .post(Uri.parse(url), headers: headers, body: data)
            .timeout(Duration(seconds: timeout)),
      );
    case 'PUT':
      return myRetry(
        () => http
            .put(Uri.parse(url), headers: headers, body: data)
            .timeout(Duration(seconds: timeout)),
      );
    case 'DELETE':
      return myRetry(
        () => http
            .delete(Uri.parse(url), headers: headers)
            .timeout(Duration(seconds: timeout)),
      );
    default:
      return myRetry(
        () => http
            .get(Uri.parse(url), headers: headers)
            .timeout(Duration(seconds: timeout)),
      );
  }
}

Future<http.Response?> fetchWithRetry(String url) async {
  try {
    return myRetry(
      () => http.get(Uri.parse(url)).timeout(const Duration(seconds: 10)),
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
