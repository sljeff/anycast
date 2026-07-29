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
- `scripts/materialize_app_config.sh`,
  `scripts/prepare_android_signing.sh`,
  `scripts/prepare_ios_signing.sh`, and `scripts/upload_play.sh` are
  pipeline-owned. Run them only in their owning workflows. A local diagnostic
  exception requires a human to name the exact script and purpose explicitly;
  authorization to diagnose does not authorize live secrets, signing, or store
  mutation. Do not invent a wrapper around these boundaries.
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

## Git and release flow

Use a short-lived branch and pull request for every change to `main`. Do not
push directly to `main` or bypass required checks.

Until an authorized `rc-*` tag is created, commits and builds are development
only. Pull request CI and manually dispatched branch CI use synthetic
configuration and do not publish to a store. They are not store candidates.

The application version source of truth is `version` in `pubspec.yaml`, in
`major.minor.patch+build` form. A version bump is an intentional release step;
do not include one in an unrelated feature or fix. Every uploaded candidate
must use a build number greater than all previously uploaded build numbers, and
a build number must never be reused.

Follow this order for every store candidate:

1. Merge all intended code to `main` through normal pull requests.
2. Make and merge the intentional `pubspec.yaml` version bump.
3. Only with explicit authorization for that exact tag, create
   `rc-<exact pubspec version>` on that `main` commit.
4. Let the tag-triggered workflow build once and upload directly to Google Play
   Internal and TestFlight; wait for store processing before testing.
5. If the candidate passes, promote those same store builds manually. Do not
   rebuild them for production. An optional final `v<major.minor.patch>` source
   tag belongs on the same commit and does not trigger another build.

An `rc-*` tag performs real uploads; it is not a dry run. If a platform job
fails while the other platform has already uploaded, rerun only the failed job.
If candidate code is rejected, merge a fix, increase the build number, and
create a new tag. Treat candidate tags as immutable: do not move, delete,
force-update, or reuse them. An exceptional situation requires a new version
and tag, not rewritten history. Do not work around the workflow checks that
bind the tag to the exact `pubspec.yaml` version and to a commit contained in
`main`.

## Persisted-data compatibility

This application is already shipped. Treat every user-owned on-device schema
and encoding as backward-compatible release state. Never fix an upgrade by
deleting or recreating the database, clearing user tables, silently falling
back to fresh-install data, or relabeling user data as cache.

SQLite schema evolution is coordinated through `lib/models/helper.dart`:

- The `openDatabase` version is the database schema version, not the application
  version.
- Table creators define the complete latest schema for fresh installs.
- Each `migrations` key is a target schema version whose ordered operations move
  the preceding schema to that target. Reaching the latest schema applies every
  required target step in ascending order.

Changing a `CREATE TABLE` statement affects only fresh installs; it never
substitutes for a database version bump and an upgrade migration. A schema
change must update the latest table creators, increase the database version,
and add every ordered step needed for each supported released schema to reach
the latest schema. A stored-value encoding or semantic change must keep reading
released encodings or provide an explicit, versioned migration or backfill. If
that transformation runs through database upgrade, increase the database
version and add the corresponding ordered step.

Released schema versions and migration history are append-only. Do not lower,
renumber, reuse, remove, or squash released version steps. Prefer additive
migrations. Any intentional transformation or destructive rewrite requires an
explicit product decision plus tested copy, backfill, and validation behavior.
Migration and initialization operations must be awaited, propagate failures,
and complete atomically; database open must fail rather than continue after a
partial migration.

A persistence change is incomplete without automated tests using synthetic,
versioned fixtures that are independent of the current fresh-install creators.
Tests must cover:

- fresh creation of the latest schema;
- upgrade from every supported released-schema fixture to latest;
- schema and required-seed parity between fresh and upgraded databases;
- preservation or explicitly expected transformation of representative rows,
  including data the migration should not touch;
- current model read/write behavior after upgrade, idempotent reopening, and
  failure without a partially upgraded database.

Retain old-schema fixtures and their coverage while users can still upgrade
from those releases. Tests must execute the real SQLite migration path rather
than only mocks. Only explicitly reconstructible cache data may be invalidated.

## Required checks

Use the same dependency and development checks as CI:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test
```

Required pull-request checks, including the Android and unsigned iOS release
builds, must pass before merge. Do not weaken, skip, or reclassify those checks
to make a change pass. Persisted-data changes must include the migration tests
above under `flutter test`. Do not invoke real signing, secret materialization,
or store upload scripts merely to make local verification look more complete.
