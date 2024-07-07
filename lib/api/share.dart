import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:retry/retry.dart';
import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;

const password = 'cjp2PGN3zuf5cfh';
const headers = {'Content-Type': 'application/json'};

Future<String?> getShortUrl(Uri origin) async {
  var api = Uri(
    scheme: 'https',
    host: 's.anycast.website',
    path: '/',
  );

  Object? err;
  var resp = http.Response('', 500);

  try {
    resp = await (retry(
      () => http
          .post(api,
              headers: headers,
              body: jsonEncode({
                "cmd": "add",
                "url": origin.toString(),
                "password": password,
                "key": getMd5(origin.toString()),
              }))
          .timeout(const Duration(seconds: 3)),
      retryIf: (e) => e is SocketException || e is TimeoutException,
      maxAttempts: 3,
    ));
  } catch (e) {
    err = e;
  }
  if (err != null || resp.statusCode != 200) {
    return null;
  }
  var body = utf8.decode(resp.bodyBytes);
  Map<String, dynamic> data = jsonDecode(body);
  print(data);
  if (data['status'] != 200) {
    return null;
  }
  return Uri(
    scheme: 'https',
    host: 's.anycast.website',
    path: '/${data['key']}',
  ).toString();
}

String getMd5(String input) {
  return md5.convert(utf8.encode(input)).toString();
}
