import 'dart:convert';

import 'package:anycast/pages/login.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

class ErrorHandler {
  static Future<void> handle(int code, http.Response response) async {
    debugPrint(code.toString());
    debugPrint(response.body);

    if (code == 401) {
      await handle401();
      return;
    } else if (code == 403) {
      await handle403(response);
      return;
    }

    var style = GoogleFonts.roboto(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );
    Get.dialog(
      AlertDialog(
        title: Text('Error $code', style: style),
        content: Text(response.body, style: style),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: Text('OK', style: style),
          ),
        ],
      ),
    );
  }

  static Future<void> handle401() async {
    showMaterialModalBottomSheet(
      expand: true,
      context: Get.context!,
      builder: (context) {
        return const LoginPage();
      },
      closeProgressThreshold: 0.9,
    );
  }

  static Future<void> handle403(http.Response response) async {
    var body = utf8.decode(response.bodyBytes);
    var data = jsonDecode(body) as Map<String, dynamic>;

    var error = data['error'] as String;
    var errorCode = data['code'] as int;

    if (errorCode == 2) {
      handle401();
      return;
    }

    var style = GoogleFonts.roboto(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );
    Get.dialog(
      AlertDialog(
        title: Text('Error', style: style),
        content: Text(error, style: style),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: Text('OK', style: style),
          ),
        ],
      ),
    );
  }
}
