#!/usr/bin/env bash
# Personal-device preview of the native app (development only, never a store
# candidate). Builds a separately-installed copy under your own bundle id and
# Apple Developer team, then installs and launches it on a connected iPhone.
#
#   native/scripts/preview_device.sh
#
# Settings come from the environment or native/.preview.env (gitignored):
#   ANYCAST_PREVIEW_TEAM       Apple Developer team id (required)
#   ANYCAST_PREVIEW_BUNDLE_ID  default com.qy9albh92w.anycast.dev
#   ANYCAST_PREVIEW_DEVICE     devicectl device id/name (default: first iPhone)
#
# The preview build drops the Sign in with Apple and App Group entitlements
# (a Personal Team cannot provision them), so Apple sign-in and the share
# extension hand-off are unavailable. It is a fresh install: existing app
# data is not visible. project.yml is untouched; the overrides live in a
# generated spec under build/preview that includes it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .preview.env ]]; then
  # shellcheck disable=SC1091
  source .preview.env
fi
team="${ANYCAST_PREVIEW_TEAM:-}"
bundle_id="${ANYCAST_PREVIEW_BUNDLE_ID:-com.qy9albh92w.anycast.dev}"
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
      properties: {}
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
