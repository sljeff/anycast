import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class Privacy extends StatelessWidget {
  const Privacy({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(children: [
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            launchUrl(
              Uri(scheme: 'https', host: 'privacy.anycast.website'),
              mode: LaunchMode.inAppBrowserView,
            );
          },
          child: Text(
            'Privacy Policy',
            style: GoogleFonts.comfortaa(
              color: Colors.blueAccent,
              fontSize: 12,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            launchUrl(
              Uri(
                scheme: 'https',
                host: 'www.apple.com',
                path: '/legal/internet-services/itunes/dev/stdeula/',
              ),
              mode: LaunchMode.inAppBrowserView,
            );
          },
          child: Text(
            'Terms of Use (EULA)',
            style: GoogleFonts.comfortaa(
              color: Colors.blueAccent,
              fontSize: 12,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ]),
    );
  }
}
