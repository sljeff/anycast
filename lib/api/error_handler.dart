import 'package:anycast/pages/login.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class ErrorHandler {
  static Future<void> handle(int code, String error) async {
    debugPrint(code.toString());
    debugPrint(error);

    if (code == 401) {
      await handle401();
      return;
    } else if (code == 403) {
      await handle403(error);
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

  static Future<void> handle401() async {
    Get.to(() => const LoginPage());
  }

  static Future<void> handle403(String error) async {
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
