#!/usr/bin/env bash
# M0 one-click regeneration (DoD: goldens + provenance records in git;
# payloads regenerable from their sources with one command).
#
#   tool/m0/regen_all.sh          # offline: rebuild db fixtures + goldens from
#                                 # the corpus materialized on this machine
#   tool/m0/regen_all.sh --live   # ALSO re-collect live corpus (network!)
#                                 #   (rss + api + media), then rebuild
#
# Fixture payloads are gitignored; only capture records (manifests, headers)
# and goldens are tracked, so a fresh clone bootstraps with --live.
# The offline path is deterministic given the materialized corpus; the --live
# path refreshes real-world content (feeds change daily) and therefore also
# refreshes every golden derived from it.
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
  bash tool/m0/fetch_api.sh
  bash tool/m0/fetch_media.sh
else
  # offline: payloads are gitignored; --live must have run here once
  if [[ ! -f test/fixtures/channels_index.json || -z "$(ls test/fixtures/rss/standard/*.xml 2>/dev/null)" ]]; then
    echo "fixture payloads missing (git carries only provenance records)" >&2
    echo "bootstrap once with: tool/m0/regen_all.sh --live" >&2
    exit 1
  fi
  # deterministic audio/opml depend only on the corpus; bootstrap if absent
  if [[ ! -f test/fixtures/audio/very_short_8s.mp3 ]]; then
    bash tool/m0/fetch_media.sh --skip-images
  fi
fi

echo "== db fixtures =="
flutter test --no-pub --dart-define=m0-regen=true \
  test/fixtures/generate_db_fixtures_test.dart

echo "== goldens =="
flutter test --no-pub --dart-define=m0-regen=true \
  test/golden/export_golden_test.dart

echo "== full test suite (gated tests must be skipped, rest green) =="
flutter test --no-pub

echo "done."
