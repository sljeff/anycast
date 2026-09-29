#!/usr/bin/env bash
# QA crawl runner: builds the app, installs it, seeds the db_smoke fixture,
# runs the QACrawlUITests tour, exports the artifacts, and builds report.md.
#
# Usage:
#   tool/ui_qa/crawl.sh <run-name> [--udid <udid>] [--skip-build] [--no-seed]
#   tool/ui_qa/crawl.sh <run-name> --reference <target.app>
#
# --reference runs the dump-only tour against whatever app the xctestrun
# points at. Pass the Flutter build's Runner.app to capture the Flutter AX
# reference (see capture_flutter.sh), then axdiff.py against a native run.
#
# Artifacts under native/build/runs/<run-name>/ (disposable):
#   result.xcresult    raw test bundle
#   states/<state>/    axdump.json + shot.png per captured state
#   findings.json      all recorded findings
#   report.md          findings table + state index
set -euo pipefail

RUN_NAME=${1:?run name required}; shift
UDID="${UDID:-${QA_UDID:-AFD8A99E-5B4B-43DB-B9E4-86BCC022B2F3}}"
SKIP_BUILD=0
SEED=1
REFERENCE_APP=""

while [ $# -gt 0 ]; do
    case "$1" in
        --udid) UDID=$2; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --no-seed) SEED=0; shift ;;
        --reference) REFERENCE_APP=$2; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

cd "$(dirname "$0")/../.."
DD=native/build/dd
RUN_DIR=native/build/runs/"$RUN_NAME"
mkdir -p "$RUN_DIR"
# xcodebuild refuses to write into an existing result bundle; and stale
# states/attachments would otherwise be reported as if fresh.
rm -rf "$RUN_DIR/result.xcresult" "$RUN_DIR/attachments" "$RUN_DIR/states" \
    "$RUN_DIR/findings.json" "$RUN_DIR/report.md" \
    "$DD"/Build/Products/reference.xctestrun \
    "$DD"/Build/Products/qa-gated.xctestrun

if [ "$SKIP_BUILD" = 0 ]; then
    echo "[crawl] build-for-testing → $DD"
    xcodebuild -project native/Anycast.xcodeproj -scheme Anycast \
        -destination "id=$UDID" -derivedDataPath "$DD" \
        build-for-testing > "$RUN_DIR/build.log" 2>&1 || {
            tail -40 "$RUN_DIR/build.log"; exit 1; }
fi

XCTESTRUN=$(ls "$DD"/Build/Products/*.xctestrun 2>/dev/null | grep -v -e reference.xctestrun -e qa-gated.xctestrun | head -1 || true)
[ -n "$XCTESTRUN" ] || { echo "no .xctestrun under $DD — build first" >&2; exit 1; }

if [ -n "$REFERENCE_APP" ]; then
    # Point the xctestrun's target at the reference app (e.g. the Flutter
    # Runner.app). xcodebuild installs that path before testing, so the
    # crawl drives the reference binary under the shared bundle id.
    [ -d "$REFERENCE_APP" ] || { echo "reference app missing: $REFERENCE_APP" >&2; exit 1; }
    # Keep the patched xctestrun next to the original: __TESTROOT__ resolves
    # relative to its own directory, so moving it into runs/ would break the
    # test-runner app lookup.
    XCTESTRUN_REF="$(dirname "$XCTESTRUN")/reference.xctestrun"
    cp "$XCTESTRUN" "$XCTESTRUN_REF"
    python3 - "$XCTESTRUN_REF" "$(cd "$(dirname "$REFERENCE_APP")" && pwd)/$(basename "$REFERENCE_APP")" <<'PY'
import plistlib, sys
path, app = sys.argv[1], sys.argv[2]
doc = plistlib.load(open(path, 'rb'))
# xcodebuild installs every app referenced by the xctestrun — including the
# unit-test targets' TestHostPath=Anycast.app, which shares the reference
# app's bundle id and would overwrite it. Keep only the UITest target so the
# sole installed target app is UITargetAppPath.
for key in [k for k in doc if k not in ('AnycastUITests', '__xctestrun_metadata__')]:
    del doc[key]
# DependentProductPaths still names Anycast.app (and its embedded PlugIns);
# xcodebuild installs every dependent product, which would overwrite the
# reference app under the shared bundle id right before the tests launch it.
# The reference app is already covered by UITargetAppPath, so drop them.
for target in doc.values():
    if not isinstance(target, dict):
        continue
    deps = target.get('DependentProductPaths')
    if isinstance(deps, list):
        target['DependentProductPaths'] = [
            p for p in deps
            if not (p.endswith('Anycast.app') or 'Anycast.app/' in p)
        ]
def patch(node):
    if isinstance(node, dict):
        for key in list(node):
            if key in ('UITargetAppPath', 'TestTargetPath') and isinstance(node[key], str):
                node[key] = app
            else:
                patch(node[key])
    elif isinstance(node, list):
        for item in node:
            patch(item)
patch(doc)
plistlib.dump(doc, open(path, 'wb'))
PY
    # The reference tour drives the same gated QACrawlUITests class, so the
    # QA_CRAWL env patch from the native branch applies here too.
    python3 - "$XCTESTRUN_REF" <<'PY'
import plistlib, sys
path = sys.argv[1]
doc = plistlib.load(open(path, 'rb'))
doc.setdefault('AnycastUITests', {}).setdefault('EnvironmentVariables', {})['QA_CRAWL'] = '1'
plistlib.dump(doc, open(path, 'wb'))
PY
    # Install the reference app and prove the shared bundle id resolves to it
    # before spending a crawl on the wrong binary.
    xcrun simctl install "$UDID" "$REFERENCE_APP"
    RESOLVED=$(xcrun simctl get_app_container "$UDID" com.kindjeff.anycast app || true)
    echo "$RESOLVED" > "$RUN_DIR/reference-app.txt"
    case "$RESOLVED" in
        *"$(basename "$REFERENCE_APP")"*) echo "[crawl] reference app installed: $RESOLVED" ;;
        *) echo "[crawl] FAIL: bundle id did not resolve to reference app: $RESOLVED" >&2; exit 1 ;;
    esac
    XCTESTRUN="$XCTESTRUN_REF"
    TEST_ID="AnycastUITests/QACrawlUITests/testReferenceDump"
    TEST_ID_EXTRA="AnycastUITests/QACrawlUITests/testFlutterShots"
else
    APP="$DD/Build/Products/Debug-iphonesimulator/Anycast.app"
    [ -d "$APP" ] || { echo "missing $APP" >&2; exit 1; }
    xcrun simctl install "$UDID" "$APP"
    # Launch once so the data container exists, then seed db_smoke. A failed
    # launch used to be masked by `|| true` and surface later as a cryptic
    # get_app_container error — fail here with the real cause instead.
    xcrun simctl launch "$UDID" com.kindjeff.anycast || {
        echo "[crawl] FAIL: could not launch com.kindjeff.anycast on $UDID" >&2
        exit 1
    }
    sleep 2
    xcrun simctl terminate "$UDID" com.kindjeff.anycast || true
    if [ "$SEED" = 1 ]; then
        CONTAINER=$(xcrun simctl get_app_container "$UDID" com.kindjeff.anycast data)
        mkdir -p "$CONTAINER/Documents" "$CONTAINER/Library/Application Support" "$CONTAINER/Library/Caches"
        cp test/fixtures/db/db_smoke/anycast.db "$CONTAINER/Documents/"
        cp -R test/fixtures/db/db_smoke/Library/. "$CONTAINER/Library/"
        echo "[crawl] seeded db_smoke into $CONTAINER"
    fi
    # The QA_CRAWL gate must reach the UI-test *runner* process. xcodebuild's
    # TEST_RUNNER_-prefixed command-line settings do NOT propagate through
    # `test-without-building -xctestrun` on this toolchain (verified
    # 2026-09-29: the runner env never saw it, so every crawl since the gate
    # landed silently skipped with exit 0 — 0 states, all-green lie). Bake the
    # variable into a patched copy of the xctestrun instead — the same
    # plist-patching technique as the --reference path below. The copy stays
    # next to the original because __TESTROOT__ resolves relative to it.
    XCTESTRUN_GATED="$(dirname "$XCTESTRUN")/qa-gated.xctestrun"
    cp "$XCTESTRUN" "$XCTESTRUN_GATED"
    python3 - "$XCTESTRUN_GATED" <<'PY'
import plistlib, sys
path = sys.argv[1]
doc = plistlib.load(open(path, 'rb'))
doc.setdefault('AnycastUITests', {}).setdefault('EnvironmentVariables', {})['QA_CRAWL'] = '1'
plistlib.dump(doc, open(path, 'wb'))
PY
    XCTESTRUN="$XCTESTRUN_GATED"
    TEST_ID="AnycastUITests/QACrawlUITests/testAuditCrawl"
fi

echo "[crawl] running $TEST_ID${TEST_ID_EXTRA:+ +$TEST_ID_EXTRA}"
STATUS=0
EXTRA_FLAG=()
[ -n "${TEST_ID_EXTRA:-}" ] && EXTRA_FLAG=(-only-testing:"$TEST_ID_EXTRA")
xcodebuild test-without-building -xctestrun "$XCTESTRUN" \
    -destination "id=$UDID" \
    -resultBundlePath "$RUN_DIR/result.xcresult" \
    -only-testing:"$TEST_ID" ${EXTRA_FLAG[@]+"${EXTRA_FLAG[@]}"} > "$RUN_DIR/test.log" 2>&1 || STATUS=$?
tail -15 "$RUN_DIR/test.log"

if [ -d "$RUN_DIR/result.xcresult" ]; then
    xcrun xcresulttool export attachments \
        --path "$RUN_DIR/result.xcresult" \
        --output-path "$RUN_DIR/attachments" > /dev/null 2>&1 || true
    python3 tool/ui_qa/report.py "$RUN_DIR"
else
    echo "[crawl] no result bundle — see $RUN_DIR/test.log" >&2
fi
exit "$STATUS"
