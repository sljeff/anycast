import 'package:anycast/design_system/anycast_theme.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class Privacy extends StatelessWidget {
  const Privacy({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(children: [
        const SizedBox(height: AnycastSpacing.md),
        GestureDetector(
          onTap: () {
            launchUrl(
              Uri(scheme: 'https', host: 'privacy.anycast.website'),
              mode: LaunchMode.inAppBrowserView,
            );
          },
          child: Text(
            'Privacy Policy',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
          ),
        ),
        const SizedBox(height: AnycastSpacing.md),
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
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
          ),
        ),
      ]),
    );
  }
}
