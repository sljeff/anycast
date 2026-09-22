#!/usr/bin/env bash
# M0 media fixtures: audio samples (synthesized via ffmpeg), OPML variants,
# cover images (real, small). Output: test/fixtures/{audio,opml,images}
# Usage: fetch_media.sh [--skip-images]
#   --skip-images  offline mode: audio + opml only (covers need network);
#                  opml additionally needs channels_index.json materialized
set -euo pipefail
cd "$(dirname "$0")/../.."

SKIP_IMAGES=0
if [[ "${1:-}" == "--skip-images" ]]; then
  SKIP_IMAGES=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--skip-images]" >&2
  exit 1
fi

A="test/fixtures/audio"
O="test/fixtures/opml"
I="test/fixtures/images"
mkdir -p "$A" "$O" "$I"

echo "== audio (ffmpeg, deterministic) =="
# tone: 440Hz sine at low volume; all files CBR unless stated
gen() { ffmpeg -y -loglevel error "$@"; }
gen -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=8"     -b:a 64k "$A/very_short_8s.mp3"
gen -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=1800"  -b:a 32k -ac 1 -ar 22050 "$A/medium_30min.mp3"
gen -f lavfi -i "sine=frequency=440:sample_rate=22050:duration=7500"  -b:a 16k -ac 1 -ar 22050 "$A/long_2h05m.mp3"
# 60s with a 20s silent middle (skip-silence must stay a no-op, K2)
ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=440:duration=20" -f lavfi -i "anullsrc=duration=20:sample_rate=44100" -f lavfi -i "sine=frequency=440:duration=20" -filter_complex "[0:a][1:a][2:a]concat=n=3:v=0:a=1" -b:a 64k "$A/with_silence_60s.mp3"
gen -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=60"    -q:a 6 "$A/vbr_60s.mp3"
gen -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=60"    -b:a 128k "$A/cbr_128k_60s.mp3"
gen -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=60"    -c:a aac -b:a 64k "$A/aac_60s.m4a"
printf 'this is not audio data, it is a text file pretending to be an mp3 %.0s' {1..200} > "$A/garbage_not_audio.mp3"

cat > "$A/error_urls.txt" <<EOF
# Remote error-path URLs for player/cache tests (05 §1.4):
#   - serve locally with:  python3 tool/m0/serve_local.py test/fixtures/audio
#   - then request:
http://127.0.0.1:8765/missing.mp3     # -> 404
http://127.0.0.1:8765/error.mp3       # -> 500
http://127.0.0.1:8765/wrongtype.mp3   # -> 200 but Content-Type: text/plain
http://127.0.0.1:8765/no_range/medium_30min.mp3  # -> 200 full body, no Range support
EOF

echo "== opml =="
python3 - "$O" <<'PY'
import json, sys, os
o = sys.argv[1]
idx = json.load(open('test/fixtures/channels_index.json'))
idx = [c for c in idx if c.get('url')]
# Overcast export style: flat body, text/title/type/rss/xmlUrl/htmlUrl
def esc(s):
    return (s or '').replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')
over = ['<opml version="2.0">', '<head><title>Overcast Subscriptions</title></head>', '<body>']
for c in idx[:30]:
    over.append(f'  <outline text="{esc(c["title"])}" title="{esc(c["title"])}" type="rss" xmlUrl="{esc(c["url"])}" htmlUrl="{esc(c.get("link") or c["url"])}"/>')
over.append('</body></opml>')
open(os.path.join(o, 'overcast.opml'), 'w').write('\n'.join(over))

# 小宇宙 export style: nested category folders
xz = ['<opml version="2.0">', '<head><title>小宇宙订阅</title></head>', '<body>']
cats = [idx[0:10], idx[10:20], idx[20:30]]
for gi, group in enumerate(cats):
    xz.append(f'  <outline text="分组{gi+1}" title="分组{gi+1}">')
    for c in group:
        xz.append(f'    <outline text="{esc(c["title"])}" title="{esc(c["title"])}" type="rss" xmlUrl="{esc(c["url"])}"/>')
    xz.append('  </outline>')
xz.append('</body></opml>')
open(os.path.join(o, 'xiaoyuzhou.opml'), 'w').write('\n'.join(xz))

# giant 500-source OPML (05 §9 import stress)
g = ['<opml version="2.0">', '<head><title>Giant Import</title></head>', '<body>']
for i in range(500):
    g.append(f'  <outline text="Podcast {i}" title="Podcast {i}" type="rss" xmlUrl="https://example.com/feeds/{i}.xml"/>')
g.append('</body></opml>')
open(os.path.join(o, 'giant_500.opml'), 'w').write('\n'.join(g))
print('opml written (overcast / xiaoyuzhou / giant_500); app_export.opml comes from the Dart generator')
PY

echo "== images =="
if [[ $SKIP_IMAGES -eq 1 ]]; then
  echo "skipped (--skip-images)"
else
python3 - <<'PY'
import json, subprocess, os
idx = [c for c in json.load(open('test/fixtures/channels_index.json')) if c.get('image')]
picked = 0
for c in idx:
    if picked >= 8:
        break
    url = c['image']
    ext = '.png' if '.png' in url.lower() else '.jpg'
    dst = f'test/fixtures/images/cover_{picked:02d}{ext}'
    r = subprocess.run(['curl', '-sS', '-L', '--max-time', '20', '-o', dst, url], capture_output=True)
    if r.returncode == 0 and os.path.exists(dst) and 10_000 < os.path.getsize(dst) < 3_000_000:
        picked += 1
    elif os.path.exists(dst):
        os.remove(dst)
print(f'{picked} covers fetched')
PY
fi

du -sh "$A" "$O"
[[ -d "$I" ]] && du -sh "$I" || true
