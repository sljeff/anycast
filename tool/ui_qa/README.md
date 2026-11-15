# UI QA automation (M3/M4)

Automated verification for the native rewrite's UI fidelity. The premise:
static snapshots only prove a screen *renders* — the expensive defect class
is interaction-only (dead gestures, buried controls, stuck spinners, empty
sheets), which nothing found until a human operated the app.

## The pipeline

```
tool/ui_qa/crawl.sh <run-name>
```

One command does: build-for-testing → install → seed `db_smoke` → run
`QACrawlUITests/testAuditCrawl` → export artifacts → `report.md`.

Per state (19 stops covering the 21 screens) the crawl:

- dumps the full AX tree → `states/<state>/axdump.json` (type, label,
  identifier, frame, enabled/selected, value)
- captures a screenshot → `states/<state>/shot.png`
- asserts required markers (e.g. Detail must contain "Share episode" AND a
  rendered show-notes body — picked from a card that actually has a
  description)
- scans invariants: zero-size interactive elements, offscreen/oversized
  frames, spinners surviving settle, leaked placeholder copy
- **probes every visible interactive element** — tap, then compare the AX
  signature + pixel hash. No change = `dead-candidate` (the R1/R3 class).
  Taps that navigate are walked back (toggle → dialog buttons → sheet
  dismiss → tab). Mutating/destructive labels are blocklisted.

Findings land in `findings.json` + `report.md` (severity-sorted table) and
fail the test on P0/P1. Everything lands under `native/build/runs/<name>/`
(disposable, gitignored).

Options: `--skip-build`, `--no-seed`, `--udid`, `QA_UDID` env.

## Flutter↔native AX diff (the "和之前不一致" finder)

The same crawl tour drives *any* installed `com.kindjeff.anycast` — the
UITest talks to apps through accessibility, not linkage. So:

```sh
tool/ui_qa/capture_flutter.sh                     # build + install + seed Flutter Runner.app
tool/ui_qa/crawl.sh ref-flutter --reference build/ios/iphonesimulator/Runner.app
tool/ui_qa/crawl.sh qa-native --skip-build        # native build (already installed)
python3 tool/ui_qa/axdiff.py native/build/runs/ref-flutter native/build/runs/qa-native
```

`axdiff.py` matches elements per state by (type, label) and reports
missing / extra / moved (>4pt) / resized (>2pt) / enabled-flipped — the
icon-misaligned, size-inconsistent, missing-surface classes as a table
instead of a vibe. Flutter's AX tree is coarser (semantics nodes), so
unlabeled decorative noise is expected; labeled controls and text are the
signal. `--reference` patches the xctestrun's `UITargetAppPath`, so the
crawl binary is unchanged.

## Video + frame heuristics

`record.sh` (existing) records any driver; `scan_frames.py` post-processes.
It needs Pillow — `python3 -m pip install -r tool/ui_qa/requirements.txt`
(the only Python dependency of this tooling):

```sh
tool/ui_qa/record.sh walkthrough $UDID \
  xcodebuild -project native/Anycast.xcodeproj -scheme Anycast \
    -derivedDataPath native/build/dd -destination "id=$UDID" \
    -only-testing:AnycastUITests/QACrawlUITests test-without-building
python3 tool/ui_qa/scan_frames.py native/build/runs/walkthrough
```

Flags near-blank, frozen (≥5 identical frames after motion), and
dominant-color frames; emits `suspicious.md` + labeled `contact/*.jpg`
grids. Upload `video.mp4` to Gemini with `GEMINI_PROMPT.md` for the VLM
pass — **verify every VLM claim against frames before filing** (appendix A,
Gemini round: 6/8 were false positives).

## Workflow contract

1. Run `crawl.sh`, read `report.md` top-down (P0 first).
2. For each finding, open `states/<state>/shot.png` + compare against
   `03-baseline-ui-interaction.md` / the Flutter screenshot before fixing —
   some "findings" are faithful quirks kept for parity.
3. Dead candidates need one manual confirm-tap; AX-silent taps *can* be
   cosmetic (marquee/animation) — those land as `visual-only`, not P1.
4. File real defects as code fixes with regression tests; keep the run name
   in the commit message.
