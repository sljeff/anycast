import 'package:anycast/states/user.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginPage extends GetView<AuthController> {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DismissiblePage(
      backgroundColor: const Color(0xFF111316),
      isFullScreen: false,
      direction: DismissiblePageDismissDirection.down,
      onDismissed: () {
        Get.back();
      },
      child: Column(
        children: [
          const Handler(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                const FlutterLogo(size: 100),
                const SizedBox(height: 50),
                // Google Sign In Button
                ElevatedButton(
                  child: const Text('Sign in with Google'),
                  onPressed: () => controller.signInWithGoogle(),
                ),
                const SizedBox(height: 20),
                // Apple Sign In Button
                ElevatedButton(
                  child: const Text('Sign in with Apple'),
                  onPressed: () => controller.signInWithApple(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
