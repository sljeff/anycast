import 'package:anycast/states/user.dart';
import 'package:anycast/widgets/handler.dart';
import 'package:dismissible_page/dismissible_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ic.dart';
import 'package:iconify_flutter/icons/ri.dart';

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
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, top: 12),
        child: Column(
          children: [
            const Handler(),
            Expanded(
              child: Center(
                child: Obx(
                  () {
                    if (controller.user.value != null) {
                      var icon = Ic.round_apple;
                      if (controller.user.value!.providerData[0].providerId ==
                          'google.com') {
                        icon = Ri.google_fill;
                      }

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Iconify(
                                icon,
                                size: 48,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Text(
                                  controller.user.value!.email!,
                                  style: GoogleFonts.comfortaa(
                                    color: Colors.white,
                                    fontSize: 18,
                                    decoration: TextDecoration.none,
                                  ),
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 50),
                          ElevatedButton(
                            child: const Text('Sign out'),
                            onPressed: () => controller.signOut(),
                          ),
                        ],
                      );
                    }

                    return Column(
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
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
