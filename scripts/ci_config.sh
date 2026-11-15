#!/usr/bin/env bash

set -euo pipefail
set +x

umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT
readonly RESOURCES_DIR="${PROJECT_ROOT}/native/Anycast/Resources"

if [[ -e "${RESOURCES_DIR}/GoogleService-Info.plist" ||
      -e "${RESOURCES_DIR}/Secrets.plist" ]]; then
  echo "Refusing to overwrite an existing local app configuration" >&2
  exit 1
fi

cat >"${RESOURCES_DIR}/GoogleService-Info.plist" <<'EOF'
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

cat >"${RESOURCES_DIR}/Secrets.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>PURCHASES_IOS_API_KEY</key>
	<string>appl_ci_public_sdk_key</string>
</dict>
</plist>
EOF

chmod 600 \
  "${RESOURCES_DIR}/GoogleService-Info.plist" \
  "${RESOURCES_DIR}/Secrets.plist"

echo "Generated synthetic CI configuration."
