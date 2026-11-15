#!/usr/bin/env bash
# M0 corpus regeneration AFTER the Flutter cutover (2026-11-15).
#
# The Flutter app was removed from this repository, so payloads that only
# Flutter code could produce are FROZEN and tracked in git — never try to
# regenerate them:
#   - test/fixtures/db/**                  (the app's real table creators,
#                                           models and insertion algorithms)
#   - test/fixtures/opml/app_export.opml   (the app's real generateOPML)
# They are pinned to the Flutter app 1.2.1+38; the last commit that could
# rebuild them was a48c34d (branch `native`).
#
# What this script still regenerates is the live-collectable corpus and the
# payloads derived from it by shell/python/ffmpeg alone:
#   tool/m0/regen_all.sh          # offline: reconstruct buckets that are
#                                 # deterministic given the materialized
#                                 # corpus (constructed rss, audio, opml)
#   tool/m0/regen_all.sh --live   # re-collect the live corpus first
#                                 # (network: rss + api + covers), then
#                                 # reconstruct
#
# Capture records (manifests, headers) and goldens stay tracked; the frozen
# payloads above are tracked too (test/fixtures/README.md).
set -euo pipefail
cd "$(dirname "$0")/../.."

if [[ -n "${1:-}" && "${1:-}" != "--live" ]]; then
  echo "usage: $0 [--live]" >&2
  exit 1
fi

if [[ "${1:-}" == "--live" ]]; then
  echo "== live collection =="
  export UA_BROWSER="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
  export UA_DART="Dart/3.10 (dart:io)"
  bash tool/m0/fetch_rss.sh
  python3 tool/m0/construct_rss_buckets.py
  bash tool/m0/fetch_user_subs.sh
  bash tool/m0/fetch_api.sh
  bash tool/m0/fetch_media.sh
else
  # offline: live-collected payloads are gitignored; --live must have run
  # here once
  if [[ ! -f test/fixtures/channels_index.json || -z "$(ls test/fixtures/rss/standard/*.xml 2>/dev/null)" ]]; then
    echo "fixture payloads missing (git carries only capture records)" >&2
    echo "bootstrap once with: tool/m0/regen_all.sh --live" >&2
    exit 1
  fi
  # user_subs payloads (author's-subscription corpus)
  if [[ -z "$(ls test/fixtures/rss/user_subs/*.xml 2>/dev/null)" ]]; then
    echo "user_subs payloads missing; collect once with: bash tool/m0/fetch_user_subs.sh" >&2
    exit 1
  fi
  # constructed buckets are deterministic (template = first standard entry);
  # cheap and idempotent, always rebuild if absent
  if [[ -z "$(ls test/fixtures/rss/missing_fields/*.xml 2>/dev/null)" ]]; then
    python3 tool/m0/construct_rss_buckets.py
  fi
  # deterministic audio/opml depend only on the corpus; bootstrap if absent
  if [[ ! -f test/fixtures/audio/very_short_8s.mp3 ]]; then
    bash tool/m0/fetch_media.sh --skip-images
  fi
fi

echo "done. (db/** and opml/app_export.opml are frozen and tracked;"
echo "native suites run via xcodebuild — see native/README.md)"
