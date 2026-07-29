#!/usr/bin/env bash

set -euo pipefail
set +x

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT

if [[ -e "${PROJECT_ROOT}/.env" ||
      -e "${PROJECT_ROOT}/android/app/google-services.json" ||
      -e "${PROJECT_ROOT}/ios/Runner/GoogleService-Info.plist" ||
      -e "${PROJECT_ROOT}/lib/firebase_options.dart" ]]; then
  echo "Refusing to overwrite an existing local app configuration" >&2
  exit 1
fi

cat >"${PROJECT_ROOT}/.env" <<'EOF'
PURCHASES_IOS_API_KEY=appl_ci_public_sdk_key
PURCHASES_ANDROID_API_KEY=goog_ci_public_sdk_key
EOF

cat >"${PROJECT_ROOT}/android/app/google-services.json" <<'EOF'
{
  "project_info": {
    "project_number": "000000000000",
    "project_id": "anycast-ci",
    "storage_bucket": "anycast-ci.invalid"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:000000000000:android:0000000000000000000000",
        "android_client_info": {
          "package_name": "com.kindjeff.anycast"
        }
      },
      "oauth_client": [],
      "api_key": [
        {
          "current_key": "ci-not-a-real-api-key"
        }
      ],
      "services": {
        "appinvite_service": {
          "other_platform_oauth_client": []
        }
      }
    }
  ],
  "configuration_version": "1"
}
EOF

cat >"${PROJECT_ROOT}/ios/Runner/GoogleService-Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>ci-not-a-real-api-key</string>
	<key>GCM_SENDER_ID</key>
	<string>000000000000</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>com.kindjeff.anycast</string>
	<key>PROJECT_ID</key>
	<string>anycast-ci</string>
	<key>STORAGE_BUCKET</key>
	<string>anycast-ci.invalid</string>
	<key>IS_ADS_ENABLED</key>
	<false/>
	<key>IS_ANALYTICS_ENABLED</key>
	<false/>
	<key>IS_APPINVITE_ENABLED</key>
	<false/>
	<key>IS_GCM_ENABLED</key>
	<true/>
	<key>IS_SIGNIN_ENABLED</key>
	<true/>
	<key>GOOGLE_APP_ID</key>
	<string>1:000000000000:ios:0000000000000000000000</string>
</dict>
</plist>
EOF

cat >"${PROJECT_ROOT}/lib/firebase_options.dart" <<'EOF'
// Synthetic values for static analysis and unit tests only.
// Store candidate builds replace this file with reviewed Infisical content.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Synthetic CI Firebase options only support Android, iOS, and web.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'ci-not-a-real-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'anycast-ci',
    authDomain: 'anycast-ci.invalid',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'ci-not-a-real-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'anycast-ci',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'ci-not-a-real-api-key',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'anycast-ci',
    iosBundleId: 'com.kindjeff.anycast',
  );
}
EOF

chmod 600 \
  "${PROJECT_ROOT}/.env" \
  "${PROJECT_ROOT}/android/app/google-services.json" \
  "${PROJECT_ROOT}/ios/Runner/GoogleService-Info.plist" \
  "${PROJECT_ROOT}/lib/firebase_options.dart"

echo "Generated synthetic CI configuration."
