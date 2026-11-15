# Anycast

An AI-powered podcast app — cross-platform RSS subscription, global content
discovery, AI transcription and translation. Available on the
[App Store](https://apps.apple.com/hk/app/anycast/id6499069246).

The shipping app is the native iOS client in [`native/`](native/README.md)
(Swift, UIKit, GRDB). The previous Flutter app and the Android target were
removed on 2026-11-15; git history and `docs/migration/` archive them and the
migration that replaced them.

- Building, testing and local setup: [`native/README.md`](native/README.md)
- CI and store-candidate releases: `.github/workflows/`, `AGENTS.md`
- On-device data compatibility and the frozen regression fixtures:
  `test/fixtures/README.md`
