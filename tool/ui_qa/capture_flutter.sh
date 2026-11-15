#!/usr/bin/env bash
# Build and install the Flutter app on a simulator so the QA crawl can
# capture its AX tree as the reference for axdiff.py.
#
# Usage:
#   tool/ui_qa/capture_flutter.sh [--udid <udid>]
#   tool/ui_qa/crawl.sh ref-flutter --reference build/ios/iphonesimulator/Runner.app
#   python3 tool/ui_qa/axdiff.py native/build/runs/ref-flutter native/build/runs/<native-run>
set -euo pipefail

UDID="${UDID:-${QA_UDID:-AFD8A99E-5B4B-43DB-B9E4-86BCC022B2F3}}"
while [ $# -gt 0 ]; do
    case "$1" in
        --udid) UDID=$2; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

cd "$(dirname "$0")/../.."

echo "[flutter] building debug simulator app (this takes a while on cold caches)"
flutter build ios --debug --simulator --no-codesign

APP=build/ios/iphonesimulator/Runner.app
[ -d "$APP" ] || { echo "expected $APP" >&2; exit 1; }

xcrun simctl install "$UDID" "$APP"
INSTALLED=$(xcrun simctl get_app_container "$UDID" com.kindjeff.anycast app || true)
echo "[flutter] installed: $INSTALLED"
case "$INSTALLED" in
    *Runner.app*) ;;
    *) echo "warning: installed app does not look like the Flutter Runner — check bundle ids" >&2 ;;
esac

# Seed db_smoke so the reference tour sees real content, same as native runs.
xcrun simctl launch "$UDID" com.kindjeff.anycast || {
    echo "[flutter] error: could not launch com.kindjeff.anycast on $UDID" >&2
    exit 1
}
sleep 3
xcrun simctl terminate "$UDID" com.kindjeff.anycast || true
CONTAINER=$(xcrun simctl get_app_container "$UDID" com.kindjeff.anycast data || true)
# A skipped seed would leave the reference crawl shooting an empty app while
# the script still reports success — make every seed failure fatal.
if [ -z "$CONTAINER" ]; then
    echo "[flutter] error: no data container for com.kindjeff.anycast on $UDID" >&2
    exit 1
fi
if [ ! -d "test/fixtures/db/db_smoke" ]; then
    echo "[flutter] error: missing test/fixtures/db/db_smoke fixture" >&2
    exit 1
fi
mkdir -p "$CONTAINER/Documents" "$CONTAINER/Library/Application Support" "$CONTAINER/Library/Caches"
cp test/fixtures/db/db_smoke/anycast.db "$CONTAINER/Documents/"
cp -R test/fixtures/db/db_smoke/Library/. "$CONTAINER/Library/"
echo "[flutter] seeded db_smoke into $CONTAINER"

echo ""
echo "Next:"
echo "  tool/ui_qa/crawl.sh ref-flutter --reference $APP"
echo "  python3 tool/ui_qa/axdiff.py native/build/runs/ref-flutter native/build/runs/<native-run>"
