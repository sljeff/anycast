# Anycast native (iOS)

The iOS-native rewrite of the Flutter app, per `docs/migration/00-execution-plan.md`.
Same repository as the Flutter line on purpose: the M0 regression assets under
`test/fixtures/` and `test/golden/` are read by the Swift test target via
relative path.

## Layout

- `project.yml` — xcodegen manifest. **The Xcode project is generated; never
  hand-edit `Anycast.xcodeproj`.** Regenerate with `xcodegen generate` (run
  inside `native/`).
- `AnycastKit/` — dynamic framework holding the data layer (GRDB), networking
  (URLSession), and the pure logic ported for the golden parity tests
  (G1–G16). Deliberately `Nonisolated` by default: repository work never runs
  on the main actor (migration doc 06 §4 / 08 §1.1).
- `Anycast/` — the application target: composition root, startup DAG, UI
  (arriving in M3). `MainActor` by default (Swift 6.2 Approachable
  Concurrency).
- `ShareExtension/` — vendored copy of the existing extension (kept
  byte-compatible with the shipped one; see 05 §11 "保留原样").
- `AnycastTests/` — Swift Testing suites: L0 (data migration matrix),
  L1 (golden parity), L2 (API contract replay).

## One-time local setup

```sh
cd native
cp ../ios/Runner/GoogleService-Info.plist Anycast/Resources/   # gitignored
python3 - <<'EOF'   # writes Anycast/Resources/Secrets.plist from .env
import re, plistlib
env = open('../.env').read()
plistlib.dump({'PURCHASES_IOS_API_KEY': re.search(r'PURCHASES_IOS_API_KEY=(\S+)', env).group(1)},
              open('Anycast/Resources/Secrets.plist', 'wb'))
EOF
xcodegen generate
```

## Build & test

```sh
xcodebuild -project Anycast.xcodeproj -scheme Anycast -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcodebuild -project Anycast.xcodeproj -scheme AnycastTests \
  -destination 'id=<simulator-udid>' test -parallel-testing-enabled NO
```

`-parallel-testing-enabled NO` is recommended: the heavy suites (G7 corpus,
palette rendering) are memory-hungry, and Swift Testing's parallel runner
processes have shown to get jetsammed on the simulator when run concurrently.

The test suites require the M0 payloads (gitignored by design): run
`tool/m0/regen_all.sh` from the repository root once on this machine.

### Test bundles

| Bundle | Covers | Needs M0 fixtures? |
|---|---|---|
| `AnycastTests` | L0–L2 parity: DB matrix, G1–G16 goldens, API contract replay | yes (TZ pinned to Asia/Shanghai) |
| `AnycastAppTests` | App-layer units (design system, screen logic, layout sanity sweep) | only the live-shell specs |
| `AnycastSnapshotTests` | Reference captures of the M3 screen states (05 §6.1) — gated behind `SNAPSHOT_CAPTURE=1` | content-bearing screens |
| `AnycastUITests` | XCUITest smoke (05 §6.2); data-dependent steps skip when unseeded. `QACrawlUITests` is additionally gated behind `QA_CRAWL=1` (set by `tool/ui_qa/crawl.sh`) | no (skips) |

Screen reference baselines live in
`AnycastSnapshotTests/__Snapshots__/ScreenBaselineCaptureTests/iOS-<major>/`
and are re-recorded against the seeded container below with
`TEST_RUNNER_SNAPSHOT_CAPTURE=1 xcodebuild … test` (a plain `test` run skips
the suite — the captures overwrite the committed references); M4 compares
them with the Flutter build per OS — structural comparison, not pixel diffs.

#### UI check

`scripts/ui_check.sh` is the one-command local check: it builds once, seeds a
simulator container, captures every screen and diffs the captures against the
committed baselines (status bar masked; `same` below 0.5% changed pixels).

```sh
scripts/ui_check.sh [--os 27|18|both|auto] [--base <git-ref>] [--state <dir>] [--record] [--dry-run]
```

- `--os auto` (default) always runs iOS 27, and iOS 18 only when a file changed
  against `--base` (default `HEAD`, working tree included) is an OS-version
  seam: a source file with `#available(iOS 26` / `#unavailable(iOS 26`, or one
  of the fixed shell/design-system files listed in the script. The seam check
  prints first; `--dry-run` stops right after it.
- `--state` is the seeded container snapshot (`Documents/`, `Library/`);
  default `build/runs/audit/state-ios26`.
- Outputs land in `build/runs/ui-check/<timestamp>/`: build and per-OS logs,
  `.xcresult` bundles, `captures/`, and `compare/summary.txt` plus
  `compare/changed.png` (baseline | capture for every changed or new screen).
  The committed `__Snapshots__` are not touched.
- `--record` is the explicit re-baseline mode: it writes the committed
  `__Snapshots__` directories (no comparison) — review the diff before
  committing. Network-fed screens (S4*, S8*, S9*) vary with live data.

### Manual runs in the simulator

Seed the database with the generator's `db_smoke` bucket (player pointer set,
queue head cached with in-file progress, far-future `validTill` so the stale
cleanup keeps the rows — `buildSmoke` in
`test/fixtures/generate_db_fixtures_test.dart`). The same container drives the
reference captures, the hosted screen searches and the data-dependent UI
smoke flows:

```sh
xcodebuild -project Anycast.xcodeproj -scheme Anycast \
  -destination 'id=<simulator-udid>' -derivedDataPath build/dd build
xcrun simctl install <udid> build/dd/Build/Products/Debug-iphonesimulator/Anycast.app
xcrun simctl launch <udid> com.kindjeff.anycast   # creates the data container
container=$(xcrun simctl get_app_container <udid> com.kindjeff.anycast data)
mkdir -p "$container/Documents" "$container/Library/Application Support" "$container/Library/Caches"
cp ../test/fixtures/db/db_smoke/anycast.db "$container/Documents/"
cp -R ../test/fixtures/db/db_smoke/Library/. "$container/Library/"
```

Query the live shell from tests with `UIContext`
(`(UIApplication.shared.delegate as? AppDelegate)?.environment.uiContext`) —
that is how the snapshot, layout and smoke suites reach the real screens.

### Personal-device preview

`scripts/preview_device.sh` builds a separately installed development copy
under your own Apple Developer team and bundle id (default
`com.qy9albh92w.anycast.dev`), then installs and launches it on a connected
iPhone. Put `ANYCAST_PREVIEW_TEAM=<team id>` in `native/.preview.env`
(gitignored). The preview drops the Sign in with Apple and App Group
entitlements, so Apple sign-in and the share-extension hand-off are
unavailable, and it starts without the store app's data. It never touches
`project.yml`, signing scripts, or store state.

## Conventions

- Architecture rules from migration docs 06 §4 / 08 §1-§3 are lint-grade:
  - No SQLite access on any `@MainActor` stack — repositories are async and
    hop off the main actor; `Codable & Sendable` value types cross the
    boundary.
  - Composition root only (`AppEnvironment`); no service locator, no lazy
    registration.
  - No timer is scheduled before settings finish loading (startup DAG).
- Version numbers mirror `pubspec.yaml`; a bump here is an intentional
  release step (see AGENTS.md).
