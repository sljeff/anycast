# Agent constraints

This file contains durable safety and process constraints for automated agents.
Keep project overviews, directory tours, architecture notes, feature lists, and
tool-version pins out of this file.

## Side-effect boundaries

Do not perform an external or hard-to-reverse action unless a human explicitly
authorizes that exact action in the current conversation. In particular, do not
merge a pull request, create a tag, trigger a store candidate, use
release-only secrets, upload or promote a build, or change store state based
only on a documented procedure or an assumption that it is the next step.

Scripts are not all general-purpose local tools:

- `scripts/ci_config.sh` is CI-owned. Run it only in CI, or in a disposable
  clean clone when a human explicitly asks to reproduce CI configuration. Never
  replace or remove a maintainer's real ignored configuration so this script can
  run.
- `scripts/materialize_app_config.sh` and
  `scripts/prepare_ios_signing.sh` are pipeline-owned. Run them only in their
  owning workflows. A local diagnostic exception requires a human to name the
  exact script and purpose explicitly; authorization to diagnose does not
  authorize live secrets, signing, or store mutation. Do not invent a wrapper
  around these boundaries.
- `scripts/bootstrap.sh` is the maintainer-facing local initialization entry
  point, but agents must not run it merely because configuration is missing.
  Run it only when a human explicitly requests local bootstrap. Access to the
  Infisical `release` environment or any release-only path requires separate,
  explicit authorization.

Never commit, stage, print, or paste generated configuration, secret values,
keystores, certificates, provisioning profiles, private keys, or raw Infisical
secret output. Do not change `config/infisical-config.sha256` merely to make
validation pass; a digest change must correspond to an intentional, reviewed
Infisical configuration change.

## Git write operations require explicit user consent

Do not perform the following git write operations (including but not limited
to) without the user's **explicit consent in the current conversation**:

- `git commit`, `git push`
- creating / deleting / switching branches (including force operations)
- `git reset` / `revert` / `rebase` / `merge` / `cherry-pick`
- adding or deleting `git tag`s; changing `git remote`s
- any `git push --force`; deleting remote refs

Every such operation must be requested separately each time; consent given
once does not carry over to the next operation. Editing files, running tests,
and reading the repository are not restricted. When the user explicitly
instructs a commit or push in the current exchange, follow that instruction
for that instance.

## Language of committed artifacts

Write in English anything that is committed and consumed by others: code, code
comments, logic reference documentation, commit messages, and pull request
descriptions. Personal or limited-scope material — plan documents, user
conversations, temporary scripts — is not restricted and may use whatever
language suits its audience. Keep this file itself in English.

## Git and release flow

Use a short-lived branch and pull request for every change to `main`. Do not
push directly to `main` or bypass required checks.

Until an authorized `rc-*` tag is created, commits and builds are development
only. Pull request CI and manually dispatched CI use synthetic configuration
and do not publish to a store. They are not store candidates.

The application version source of truth is `native/project.yml`:
`MARKETING_VERSION` (the `major.minor.patch` name) and
`CURRENT_PROJECT_VERSION` (the build number). A version bump is an intentional
release step; do not include one in an unrelated feature or fix. Every uploaded
candidate must use a build number greater than all previously uploaded build
numbers, and a build number must never be reused.

Follow this order for every store candidate:

1. Merge all intended code to `main` through normal pull requests.
2. Make and merge the intentional `native/project.yml` version bump.
3. Only with explicit authorization for that exact tag, create
   `rc-<MARKETING_VERSION>+<CURRENT_PROJECT_VERSION>` on that `main` commit.
4. Let the tag-triggered workflow build once and upload directly to TestFlight;
   wait for store processing before testing.
5. If the candidate passes, promote that same store build manually. Do not
   rebuild it for production. An optional final `v<major.minor.patch>` source
   tag belongs on the same commit and does not trigger another build.

An `rc-*` tag performs a real upload; it is not a dry run. If candidate code is
rejected, merge a fix, increase the build number, and create a new tag. Treat
candidate tags as immutable: do not move, delete, force-update, or reuse them.
An exceptional situation requires a new version and tag, not rewritten history.
Do not work around the workflow checks that bind the tag to the exact
`native/project.yml` version and to a commit contained in `main`.

## Persisted-data compatibility

This application is already shipped. Treat every user-owned on-device schema
and encoding as backward-compatible release state. Never fix an upgrade by
deleting or recreating the database, clearing user tables, silently falling
back to fresh-install data, or relabeling user data as cache.

SQLite schema evolution is coordinated through
`native/AnycastKit/Sources/Database/Schema.swift` and applied by
`AppDatabase.openAt` in
`native/AnycastKit/Sources/Database/AppDatabase.swift`:

- `Schema.version` is the database schema version (stored as
  `PRAGMA user_version`), not the application version. An on-device version
  above it fails the open (downgrade guard).
- `Schema.tableCreators` define the complete latest schema for fresh installs.
- Each `Schema.migrations` key is a target schema version whose ordered
  statements move the preceding schema to that target. Reaching the latest
  schema applies every required target step in ascending order, inside the
  same write transaction that stamps `user_version`, so a failing step rolls
  everything back and the open fails rather than leaving a partially upgraded
  database. The journal stays rollback (never WAL).

Changing a table creator affects only fresh installs; it never substitutes for
a database version bump and an upgrade migration. A schema change must update
the latest table creators, increase `Schema.version`, and add every ordered
step needed for each supported released schema to reach the latest schema. A
stored-value encoding or semantic change must keep reading released encodings
or provide an explicit, versioned migration or backfill. If that
transformation runs through database upgrade, increase `Schema.version` and
add the corresponding ordered step.

Released schema versions and migration history are append-only. Do not lower,
renumber, reuse, remove, or squash released version steps. Prefer additive
migrations. Any intentional transformation or destructive rewrite requires an
explicit product decision plus tested copy, backfill, and validation behavior.
Migration and initialization operations must propagate failures and complete
atomically.

A persistence change is incomplete without automated tests using versioned
fixtures that are independent of the current fresh-install creators. The
native `AnycastTests` suite (L0DatabaseTests, HistoryMigrationTests) runs
against the fixtures under `test/fixtures/db/`; those buckets are FROZEN —
generated by the retired Flutter app and tracked in git, they can never be
regenerated (see `test/fixtures/README.md`) — so they must be retained
unmodified while users can still upgrade from those releases. Tests must
cover:

- fresh creation of the latest schema;
- upgrade from every supported released-schema fixture to latest;
- schema and required-seed parity between fresh and upgraded databases;
- preservation or explicitly expected transformation of representative rows,
  including data the migration should not touch;
- current model read/write behavior after upgrade, idempotent reopening, and
  failure without a partially upgraded database.

Tests must execute the real SQLite migration path rather than only mocks. Only
explicitly reconstructible cache data may be invalidated.

## Local Xcode build artifacts

Every local `xcodebuild` invocation must reuse a single shared DerivedData
directory and a single shared package checkout directory, from `native/`:

```sh
xcodebuild -project Anycast.xcodeproj -scheme Anycast \
  -derivedDataPath build/dd \
  -clonedSourcePackagesDirPath build/SourcePackages ...
```

- Never create a fresh `dd-*` path per run. Each new path recompiles the
  entire SwiftPM dependency graph (~7 GB for the Firebase/gRPC stack);
  scratch dirs previously consumed ~113 GB and filled the disk.
- Always pass `-clonedSourcePackagesDirPath build/SourcePackages`, as
  `native/scripts/ui_check.sh` and `native/scripts/preview_device.sh` do.
  Omitting it clones a second full copy of every package (~6 GB) into
  `build/dd/SourcePackages`.
- If a genuinely clean build is needed, delete `native/build/dd` first —
  do not add a sibling directory.
- Small per-run outputs (`.xcresult` bundles, screenshots, logs) may go
  under `native/build/runs/<name>/`.
- Everything under `native/build/` is disposable and gitignored; wipe the
  whole directory to reclaim space. Nothing else may live there.

## Simulator targets

The migration is validated against exactly two iOS versions — do not spin up
additional simulator runtimes or device types:

- **iOS 27 (primary).** iPhone 18 Pro, UDID `AFD8A99E-5B4B-43DB-B9E4-86BCC022B2F3`.
  This is the shipping target: all development iteration, screenshot review,
  and test runs go here first. The committed screen baselines live under
  `__Snapshots__/ScreenBaselineCaptureTests/iOS-27/`.
- **iOS 18 (acceptance only).** iPhone 16 Pro, UDID
  `E9B0FF99-0465-4B18-8D2B-947A8CC0DFF1`. Run it once at milestone sign-off to
  confirm the older-OS floor still works; do not use it as the iteration
  target.

If a UDID no longer resolves (runtime reinstalled), pick the same device
class and update this section.

## Required checks

Use the same development checks as CI (from `native/`, on the pinned iOS 27
simulator listed above):

```sh
xcodegen generate
xcodebuild -project Anycast.xcodeproj -scheme Anycast \
  -destination 'id=AFD8A99E-5B4B-43DB-B9E4-86BCC022B2F3' \
  -derivedDataPath build/dd \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -only-testing:AnycastTests/L0DatabaseTests \
  -only-testing:AnycastTests/HistoryMigrationTests \
  -only-testing:AnycastTests/CacheStoreTests \
  -only-testing:AnycastAppTests \
  test -parallel-testing-enabled NO
```

The required pull-request check is the CI `Build native iOS` job (build, the
tracked-fixture unit-test selection, and the UI smoke). It must pass before
merge. Do not weaken, skip, or reclassify it to make a change pass.
Persisted-data changes must include the migration tests above under the
`AnycastTests` suite. Do not invoke real signing, secret materialization, or
store upload scripts merely to make local verification look more complete.
