import 'dart:convert';

import 'package:anycast/api/error_handler.dart';
import 'package:anycast/utils/http_client.dart';
import 'package:flutter/cupertino.dart';
import 'package:jiffy/jiffy.dart';

const host = 'https://api.anycast.website';

class User {
  late String uid;
  Jiffy? expireAt;
  // this month left
  late int remaining;
  late int plus;

  User.fromJson(Map<String, dynamic> json) {
    uid = json['uid'];
    if (json['expired_at'] == null) {
      expireAt = null;
    } else {
      // 2024-07-29T15:35:52+00:00
      expireAt = Jiffy.parse(
        json['expired_at'],
        pattern: 'yyyy-MM-ddTHH:mm:ssZ',
      );
    }
    remaining = json['remaining'];
    plus = json['plus'];
  }
}

Future<User?> getUser() async {
  var resp = await reqWithAuth('$host/user', method: 'GET');

  if (resp.statusCode == 401) {
    ErrorHandler.handle401();
    return null;
  }

  var data = jsonDecode(resp.body) as Map<String, dynamic>;

  try {
    return User.fromJson(data);
  } catch (e) {
    debugPrint(e.toString());
    return null;
  }
}
