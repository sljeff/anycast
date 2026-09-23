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

## M2 audio smoke (DEBUG only)

Seeds nothing itself — it plays the restored queue head through the real
stack (engine, session, Now Playing, 2 s persistence, cache). Removed when
the M3 player UI lands.

The reproducible container is the generator's `db_smoke` bucket (player
pointer set, queue head cached with in-file progress, far-future `validTill`
so the stale cleanup keeps the rows — `buildSmoke` in
`test/fixtures/generate_db_fixtures_test.dart`). An earlier smoke record
referenced a hand-modified `db_light` container whose steps were never
recorded and cannot be replayed from the generator output; `db_smoke` exists
so this cannot recur.

```sh
# App installed and terminated, then:
container=$(xcrun simctl get_app_container <udid> com.kindjeff.anycast data)
mkdir -p "$container/Documents" "$container/Library/Application Support" \
         "$container/Library/Caches"
cp test/fixtures/db/db_smoke/anycast.db "$container/Documents/"
cp -R test/fixtures/db/db_smoke/Library/. "$container/Library/"
xcrun simctl launch --console-pty <udid> com.kindjeff.anycast -m2-smoke-play local
# stdout: "[m2-smoke] isPlaying=… position=…ms error=…" — verified run
# (iPhone 16 Pro simulator, 2026-09-24): "isPlaying=true position=7500ms
# error=none" — cache hit resuming at 3000 ms, paused row persisted
# 7812 ms (K24); the hit also refreshes the row's `touched` in the meta DB.
# If isPlaying=false with "The operation could not be completed", the
# simulator's audio HAL is wedged — `simctl shutdown` + `boot` and re-seed.
# The uncached podtrac episode sits LAST in the queue for a manual
# miss-path run (stream + full-file download) after removing the head rows.
```

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
