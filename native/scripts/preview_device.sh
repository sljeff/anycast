#!/usr/bin/env bash
# Personal-device preview of the native app (development only, never a store
# candidate). Builds a separately-installed copy under your own bundle id and
# Apple Developer team, then installs and launches it on a connected iPhone.
#
#   native/scripts/preview_device.sh
#
# Settings come from the environment or native/.preview.env (gitignored):
#   ANYCAST_PREVIEW_TEAM       Apple Developer team id (required)
#   ANYCAST_PREVIEW_BUNDLE_ID  default com.kindjeff.anycast.dev (the shipped
#                              app's bundle with a .dev seed — see below)
#   ANYCAST_PREVIEW_DEVICE     devicectl device id/name (default: first iPhone)
#
# The preview build keeps Sign in with Apple (the paid team provisions the
# explicit App ID automatically) but still drops the App Group entitlement,
# so the share extension hand-off is unavailable. It is a fresh install:
# existing app data is not visible. project.yml is untouched; the overrides
# live in a generated spec under build/preview that includes it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .preview.env ]]; then
  # shellcheck disable=SC1091
  source .preview.env
fi
team="${ANYCAST_PREVIEW_TEAM:-}"
# The production bundle id is com.kindjeff.anycast (ios/Runner and
# native/project.yml agree); the backend validates the Sign in with Apple
# ID token audience against it, so testing login requires overriding
# ANYCAST_PREVIEW_BUNDLE_ID=com.kindjeff.anycast. The default below keeps
# a .dev seed so a day-to-day preview never collides with a real store
# install of the shipped app.
bundle_id="${ANYCAST_PREVIEW_BUNDLE_ID:-com.kindjeff.anycast.dev}"
device="${ANYCAST_PREVIEW_DEVICE:-}"

if [[ -z "$team" ]]; then
  echo "Set ANYCAST_PREVIEW_TEAM (e.g. in native/.preview.env)." >&2
  exit 1
fi

for file in Anycast/Resources/GoogleService-Info.plist Anycast/Resources/Secrets.plist; do
  if [[ ! -f "$file" ]]; then
    echo "warning: $file is missing; sign-in and purchases will be unavailable." >&2
  fi
done

out=build/preview
mkdir -p "$out"
cat > "$out/project.yml" <<SPEC
include:
  - path: ../../project.yml
targets:
  Anycast:
    entitlements:REPLACE:
      path: Anycast.preview.entitlements
      properties:
        # Sign in with Apple needs an explicit (non-wildcard) App ID with
        # the capability; automatic signing registers it. Without this
        # entitlement ASAuthorization fails immediately with error 1000.
        com.apple.developer.applesignin: [Default]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $bundle_id
  ShareExtension:
    entitlements:REPLACE:
      path: ShareExtension.preview.entitlements
      properties: {}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $bundle_id.Share-Extension
SPEC

xcodegen generate --quiet --spec "$out/project.yml" --project "$out"

# Pin dependencies to the committed lockfile.
resolved=Anycast.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
if [[ -f "$resolved" ]]; then
  mkdir -p "$out/$(dirname "$resolved")"
  cp "$resolved" "$out/$resolved"
fi

log="$out/build.log"
if ! xcodebuild \
  -project "$out/Anycast.xcodeproj" \
  -scheme Anycast \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$out/DerivedData" \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$team" \
  build > "$log" 2>&1; then
  grep -E 'error' "$log" | head -20 >&2
  echo "Build failed; full log: native/$log" >&2
  exit 1
fi
app="$out/DerivedData/Build/Products/Debug-iphoneos/Anycast.app"

if [[ -z "$device" ]]; then
  device="$(xcrun devicectl list devices 2>/dev/null \
    | awk '/iPhone/ && $0 !~ /unavailable/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-/) { print $i; exit } }')"
fi
if [[ -z "$device" ]]; then
  echo "No available iPhone. Connect and unlock it (Developer Mode on), or set ANYCAST_PREVIEW_DEVICE." >&2
  exit 1
fi

xcrun devicectl device install app --device "$device" "$app"
xcrun devicectl device process launch --device "$device" "$bundle_id"
