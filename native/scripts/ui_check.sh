#!/usr/bin/env bash
# Local UI verification: capture the live screens on iOS 27 (always) and on
# iOS 18 (only when the change touches an OS-version seam), then diff the
# captures against the committed baselines. Local only, never a CI step.
#
#   native/scripts/ui_check.sh [--os 27|18|both|auto] [--base <git-ref>]
#                              [--state <dir>] [--record] [--dry-run]
#
#   --os      auto (default) = iOS 27 + iOS 18 only if a seam file changed
#   --base    git ref the working tree is compared with (default HEAD)
#   --state   seeded app container snapshot with Documents/ and Library/
#             (default build/runs/audit/state-ios26)
#   --record  write the committed __Snapshots__ baselines instead of a run
#             directory (explicit re-baseline; no comparison is made)
#   --dry-run stop after the seam check
#
# Outputs: build/runs/ui-check/<timestamp>/ (build.log, <os>.log,
# <os>.xcresult, captures/, compare/summary.txt, compare/changed.png).
#
# The seeded container needs the M0 payloads' db fixtures; simulator UDIDs
# are the ones pinned in the repo AGENTS.md (override with
# ANYCAST_SIM_IOS27 / ANYCAST_SIM_IOS18).
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.kindjeff.anycast
UDID_27="${ANYCAST_SIM_IOS27:-97AB5067-9E1B-4DDB-A373-974FE70878A9}"
UDID_18="${ANYCAST_SIM_IOS18:-268F6131-6BA6-4762-A633-1A883566624E}"
BASELINES=AnycastSnapshotTests/__Snapshots__/ScreenBaselineCaptureTests
APP=build/dd/Build/Products/Debug-iphonesimulator/Anycast.app
SRC=Anycast/Sources

# Files whose behavior differs between iOS 18 and iOS 26+ without an
# #available check of their own (UIKit/system chrome the shell relies on).
FIXED_SEAMS=(
  DesignSystem/TextField.swift
  UI/Shells/PlayerBarView.swift
  UI/Shells/MainTabBarController.swift
  UI/Shells/SheetPresentation.swift
  UI/Shells/PlayerPageContainer.swift
  DesignSystem/Theme.swift
)

os_choice=auto
base=HEAD
state=build/runs/audit/state-ios26
record=0
dry_run=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --os) os_choice="${2:?--os needs a value}"; shift 2 ;;
    --base) base="${2:?--base needs a ref}"; shift 2 ;;
    --state) state="${2:?--state needs a directory}"; shift 2 ;;
    --record) record=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$os_choice" in 27|18|both|auto) ;; *) echo "--os must be 27, 18, both or auto" >&2; exit 2 ;; esac
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || { echo "unknown git ref: $base" >&2; exit 2; }

# MARK: - Seam detection

# Working tree vs base, plus untracked files; paths relative to native/.
changed=$( { git diff --name-only --relative "$base" -- .
             git ls-files --others --exclude-standard; } | sort -u)

seams=$(grep -rlE '#(un)?available\(iOS 26' "$SRC" || true)
dropped=()
for relative in "${FIXED_SEAMS[@]}"; do
  if [[ -f "$SRC/$relative" ]]; then seams+=$'\n'"$SRC/$relative"; else dropped+=("$relative"); fi
done
seams=$(printf '%s\n' "$seams" | sed '/^$/d' | sort -u)
touched=$(comm -12 <(printf '%s\n' "$changed" | sed '/^$/d') <(printf '%s\n' "$seams"))

echo "== Seam check (base: $base) =="
echo "changed files under native/: $(printf '%s\n' "$changed" | sed '/^$/d' | wc -l | tr -d ' ')"
echo "seam files tracked: $(printf '%s\n' "$seams" | wc -l | tr -d ' ')"
((${#dropped[@]})) && echo "fixed seams missing on disk (dropped): ${dropped[*]}"
if [[ -n "$touched" ]]; then
  echo "iOS 18 check needed: yes"
  printf '  %s\n' $touched
  need18=1
else
  echo "iOS 18 check needed: no"
  need18=0
fi

case "$os_choice" in
  27) oses=(27) ;;
  18) oses=(18) ;;
  both) oses=(27 18) ;;
  auto) oses=(27); ((need18)) && oses+=(18) ;;
esac
echo "OS selection ($os_choice): ${oses[*]}"
((dry_run)) && exit 0

# MARK: - Build

[[ -d "$state/Documents" && -d "$state/Library" ]] || {
  echo "seed state not found: $state (needs Documents/ and Library/); pass --state <dir>" >&2
  exit 1
}

run_dir="build/runs/ui-check/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run_dir"
captures="$run_dir/captures"
common=(-project Anycast.xcodeproj -scheme Anycast
        -derivedDataPath build/dd -clonedSourcePackagesDirPath build/SourcePackages)

echo "== Build =="
build_start=$SECONDS
if ! xcodebuild build-for-testing "${common[@]}" \
    -destination 'generic/platform=iOS Simulator' >"$run_dir/build.log" 2>&1; then
  tail -n 25 "$run_dir/build.log"
  echo "build failed; full log: $run_dir/build.log" >&2
  exit 1
fi
echo "build ok in $((SECONDS - build_start))s"

# MARK: - Capture

seed() {
  local udid=$1 container
  xcrun simctl install "$udid" "$APP"
  xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null   # creates the data container
  sleep 3
  xcrun simctl terminate "$udid" "$BUNDLE_ID" || true
  container=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)
  rsync -a --delete "$state/Documents/" "$container/Documents/"
  rsync -a "$state/Library/" "$container/Library/"
}

failed=0
for os in "${oses[@]}"; do
  udid_var="UDID_$os"; udid="${!udid_var}"
  echo "== Capture iOS $os ($udid) =="
  os_start=$SECONDS
  xcrun simctl boot "$udid" 2>/dev/null || true       # already booted is fine
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance light
  xcrun simctl ui "$udid" content_size large
  seed "$udid"

  env_args=(TEST_RUNNER_SNAPSHOT_CAPTURE=1)
  ((record)) || env_args+=("TEST_RUNNER_SNAPSHOT_OUTPUT_DIR=$PWD/$captures")
  if ! env "${env_args[@]}" timeout 1200 xcodebuild test-without-building "${common[@]}" \
      -destination "id=$udid" \
      -only-testing:AnycastSnapshotTests/ScreenBaselineCaptureTests \
      -parallel-testing-enabled NO -collect-test-diagnostics never \
      -resultBundlePath "$run_dir/ios$os.xcresult" >"$run_dir/ios$os.log" 2>&1; then
    failed=1
    echo "capture run failed on iOS $os; failures:" >&2
    grep -E "^✘|^↳" "$run_dir/ios$os.log" | cut -c1-200 | head -n 15 >&2 || true
  fi
  echo "iOS $os captures took $((SECONDS - os_start))s (log: $run_dir/ios$os.log)"
done

# MARK: - Compare

if ((record)); then
  echo "== Recorded into $BASELINES (review with git status) =="
else
  echo "== Compare against $BASELINES =="
  python3 scripts/ui_compare.py "$captures" "$BASELINES" "$run_dir/compare" || failed=1
fi
echo "run dir: $run_dir"
exit "$failed"
