#!/usr/bin/env bash
# Captures simulator screenshots of the app running on a local snapshot of real
# podcasts (DEBUG, simulator-only demo mode; see DemoContent/README.md).
#
#   native/scripts/demo_shots.sh [--appearance light|dark|both] [--skip-build]
#                                [--release-check]
#
# Output: build/runs/demo-shots/<timestamp>/{light,dark}/NN-name.png, plus a
# state dir in build/runs/demo-state. Local only, never a CI step. Targets
# only the pinned iPhone 18 Pro (iOS 27) simulator from the repo AGENTS.md.
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONDONTWRITEBYTECODE=1

BUNDLE_ID=com.kindjeff.anycast
UDID=97AB5067-9E1B-4DDB-A373-974FE70878A9
APP=build/dd/Build/Products/Debug-iphonesimulator/Anycast.app
STATE=build/runs/demo-state
common=(-project Anycast.xcodeproj -scheme Anycast
        -derivedDataPath build/dd -clonedSourcePackagesDirPath build/SourcePackages)

appearance=both
skip_build=0
release_check=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --appearance) appearance="${2:?--appearance needs a value}"; shift 2 ;;
    --skip-build) skip_build=1; shift ;;
    --release-check) release_check=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$appearance" in light) modes=(light) ;; dark) modes=(dark) ;; both) modes=(light dark) ;;
  *) echo "--appearance must be light, dark or both" >&2; exit 2 ;; esac

if pgrep -x xcodebuild >/dev/null; then
  echo "another xcodebuild is running; wait for it to finish" >&2
  exit 1
fi

run="build/runs/demo-shots/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run"

# MARK: - Build

if ((!skip_build)); then
  echo "== Build =="
  xcodegen generate >/dev/null
  if ! xcodebuild build-for-testing "${common[@]}" \
      -destination 'generic/platform=iOS Simulator' >"$run/build.log" 2>&1; then
    tail -n 25 "$run/build.log"
    echo "build failed; full log: $run/build.log" >&2
    exit 1
  fi
fi

# MARK: - Simulator and state

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" content_size large
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" \
  --batteryState charged --batteryLevel 100

echo "== Fresh container + demo state =="
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null   # the app creates its own schema-v5 database
container=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
for _ in $(seq 1 60); do
  [[ -f "$container/Documents/anycast.db" ]] && break
  sleep 1
done
sleep 3
xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
python3 DemoContent/build_demo_state.py --container "$container" --out "$STATE"

seed() {
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  rsync -a --delete "$STATE/Documents/" "$container/Documents/"
  rsync -a "$STATE/Library/" "$container/Library/"
}

# MARK: - Capture

failed=0
for mode in "${modes[@]}"; do
  echo "== Capture $mode =="
  xcrun simctl ui "$UDID" appearance "$mode"
  sleep 2
  seed
  handshake="$run/handshake-$mode"
  final="$run/$mode"
  mkdir -p "$handshake" "$final"

  TEST_RUNNER_ANYCAST_DEMO_CONTENT=1 TEST_RUNNER_DEMO_SHOTS_DIR="$PWD/$handshake" TEST_RUNNER_DEMO_SHOTS_APPEARANCE="$mode" \
    timeout 900 xcodebuild test-without-building "${common[@]}" \
      -destination "id=$UDID" \
      -only-testing:AnycastSnapshotTests/DemoShotsCaptureTests \
      -parallel-testing-enabled NO -collect-test-diagnostics never \
      -resultBundlePath "$run/$mode.xcresult" >"$run/$mode.log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    for ready in "$handshake"/*.ready; do
      [[ -e "$ready" ]] || continue
      name=$(basename "$ready" .ready)
      [[ -e "$final/$name.png" ]] && continue
      xcrun simctl io "$UDID" screenshot --type=png "$final/$name.png" >/dev/null 2>&1
      touch "$handshake/$name.done"
      echo "  $mode/$name.png"
    done
    sleep 0.3
  done
  wait "$pid" || { failed=1; echo "capture run failed ($mode); see $run/$mode.log" >&2; }

done

# Fail loudly if a dark run came out light (mean luminance of the content area).
if [[ " ${modes[*]} " == *" dark "* ]]; then
  bad=$(python3 - "$run/dark" <<'PY'
import glob, sys
from PIL import Image, ImageStat
for f in sorted(glob.glob(sys.argv[1] + "/*.png")):
    mean = ImageStat.Stat(Image.open(f).convert("L").crop((0, 300, 1206, 2000))).mean[0]
    if mean > 140:
        print(f, round(mean))
PY
)
  [[ -z "$bad" ]] || { echo "dark frames that look light:" >&2; echo "$bad" >&2; failed=1; }
fi

xcrun simctl status_bar "$UDID" clear || true
echo "== Screenshots =="
for file in "$run"/*/*.png; do
  [[ -e "$file" ]] && echo "$file $(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel/{printf "%s ", $2}')"
done

# MARK: - Release safety check

if ((release_check)); then
  echo "== Release check =="
  xcodebuild build "${common[@]}" -configuration Release -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO >"$run/release.log" 2>&1 \
    || { tail -n 25 "$run/release.log"; echo "release build failed" >&2; exit 1; }
  bin=build/dd/Build/Products/Release-iphonesimulator/Anycast.app
  hits=0
  for binary in "$bin/Anycast" "$bin/Frameworks/AnycastKit.framework/AnycastKit"; do
    [[ -f "$binary" ]] || continue
    hits=$((hits + $(strings - "$binary" | grep -c -e anycast-demo-content -e DemoURLProtocol -e ANYCAST_DEMO_CONTENT || true)))
  done
  echo "demo symbols in Release: $hits"
  ((hits == 0)) || failed=1
fi

echo "run dir: $run"
exit "$failed"
