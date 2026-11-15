#!/usr/bin/env bash
# M0 corpus collection: real RSS feeds -> test/fixtures/rss/<bucket>/
# Buckets (05 §1.2): standard / http_plain / redirect / ua_sensitive (3 UA variants)
# Constructed buckets (missing_fields / giant / malformed / weird_dates) are built
# offline afterwards by tool/m0/construct_rss_buckets.py from a captured template.
#
# Re-running this script refreshes the live corpus (content changes over time);
# regeneration also requires re-running the golden export afterwards.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="test/fixtures/rss"
STAGE="$(mktemp -d /tmp/m0_rss.XXXXXX)"
UA_BROWSER="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
UA_DART="Dart/3.10 (dart:io)"

echo "== 1. collecting feed candidates (backend discovery + curated) =="
{
  grep -vE '^\s*(#|$)' tool/m0/feeds_curated.txt
  for spec in "10001 US" "10001 CN" "10001 JP" "10001 DE" "10002 US" "10002 CN" "10004 US" "10005 US" "10006 US"; do
    set -- $spec
    curl -sS --max-time 15 "https://anycast.website/api/top-channels?category_id=$1&country=$2" \
      | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    for x in (d.get("data") or {}).get("list") or []:
        print(x["rss_url"])
except Exception:
    pass' || true
  done
} | grep -E '^https?://' | sort -u > "$STAGE/candidates.txt"
echo "   $(wc -l < "$STAGE/candidates.txt" | tr -d ' ') candidates"

echo "== 2. probing each candidate (no redirect follow, browser UA) =="
mkdir -p "$STAGE/probe"
# Each line: url<TAB>slug
awk '{printf "%s\t%04d\n", $0, NR}' "$STAGE/candidates.txt" > "$STAGE/work.txt"
cat > "$STAGE/probe_one.sh" <<EOS
#!/usr/bin/env bash
slug="\$1"
url="\$(awk -F'\\t' -v s="\$slug" '\$2==s {print \$1; exit}' "$STAGE/work.txt")"
curl -sS --max-time 25 -A "$UA_BROWSER" \\
  -D "$STAGE/probe/\$slug.headers" \\
  -o "$STAGE/probe/\$slug.body" \\
  -w "%{http_code}" "\$url" > "$STAGE/probe/\$slug.code" 2>/dev/null || echo "000" > "$STAGE/probe/\$slug.code"
EOS
chmod +x "$STAGE/probe_one.sh"
cut -f2 "$STAGE/work.txt" | xargs -P 8 -I{} "$STAGE/probe_one.sh" {}

echo "== 3. classifying =="
python3 - "$STAGE" "$OUT" <<'PYEOF'
import json, os, re, shutil, sys, hashlib, datetime
from xml.etree import ElementTree as ET

stage, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

def read_headers(path):
    status, headers = None, {}
    if not os.path.exists(path):
        return None, {}
    for line in open(path, 'rb').read().decode('utf-8', 'replace').splitlines():
        m = re.match(r'HTTP/\S+\s+(\d+)', line)
        if m:
            status = int(m.group(1))
            continue
        if ':' in line:
            k, v = line.split(':', 1)
            headers.setdefault(k.strip().lower(), []).append(v.strip())
    return status, headers

def probe(slug):
    code_f = f'{stage}/probe/{slug}.code'
    code = open(code_f).read().strip() if os.path.exists(code_f) else '000'
    status, headers = read_headers(f'{stage}/probe/{slug}.headers')
    body = open(f'{stage}/probe/{slug}.body', 'rb').read() if os.path.exists(f'{stage}/probe/{slug}.body') else b''
    return int(code) if code.isdigit() else 0, headers, body

entries = []
for line in open(f'{stage}/work.txt'):
    url, slug = line.rstrip('\n').split('\t')
    status, headers, body = probe(slug)
    entries.append({'url': url, 'slug': slug, 'status': status, 'headers': headers, 'body': body,
                    'body_path': f'{stage}/probe/{slug}.body', 'headers_path': f'{stage}/probe/{slug}.headers'})

def classify(e):
    """returns bucket or None"""
    url, status, body = e['url'], e['status'], e['body']
    if 300 <= status < 400 and 'location' in e['headers']:
        return 'redirect'
    if status != 200 or not body:
        return None
    head = body[:4096].lstrip().decode('utf-8', 'replace')
    if head.startswith('<?xml') or head.startswith('<rss') or head.startswith('<feed'):
        if url.startswith('http://'):
            return 'http_plain'
        return 'standard'
    return None

usable = [e for e in entries if classify(e)]
print(f'   usable: {len(usable)} / {len(entries)}')

def save(e, bucket, fname=None, extra=None):
    d = os.path.join(out, bucket)
    os.makedirs(d, exist_ok=True)
    name = fname or e['slug']
    shutil.copyfile(e['body_path'], os.path.join(d, f'{name}.xml'))
    shutil.copyfile(e['headers_path'], os.path.join(d, f'{name}.headers.txt'))
    item = {
        'file': f'{name}.xml',
        'url': e['url'],
        'bucket': bucket,
        'status': e['status'],
        'content_type': (e['headers'].get('content-type') or [''])[0],
        'sha256': hashlib.sha256(e['body']).hexdigest(),
        'bytes': len(e['body']),
        'fetched_ua': 'browser',
        'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
    }
    if extra:
        item.update(extra)
    return item

def rss_meta(body):
    meta = {}
    try:
        root = ET.fromstring(body)
        chan = root if root.tag.endswith('channel') else root.find('.//channel')
        if chan is None and root.tag.endswith('feed'):
            meta['title'] = (root.findtext('{http://www.w3.org/2005/Atom}title') or '').strip()
            meta['items'] = len(root.findall('{http://www.w3.org/2005/Atom}entry'))
            return meta
        ns = {'itunes': 'http://www.itunes.com/dtds/podcast-1.0.dtd'}
        meta['title'] = (chan.findtext('title') or '').strip()
        meta['items'] = len(chan.findall('item'))
        meta['itunes_duration_count'] = len(chan.findall('./item/itunes:duration', ns))
    except ET.ParseError as pe:
        meta['parse_error'] = str(pe)
    return meta

manifest = {'standard': [], 'http_plain': [], 'redirect': []}

# channel-level metadata for ALL parseable feeds (full set; feeds whose XML is
# not kept in git still contribute realistic subscription rows for db fixtures)
std = [e for e in usable if classify(e) == 'standard']
std_meta_full = []
for e in std:
    std_meta_full.append((e, rss_meta(e['body'])))
channels_index = []
for e, m in std_meta_full:
    if m.get('parse_error'):
        continue
    chan_meta = {
        'url': e['url'], 'title': m.get('title'), 'items': m.get('items'),
        'content_type': (e['headers'].get('content-type') or [''])[0],
    }
    body = e['body']
    mo = re.search(rb'<itunes:image[^>]+href="([^"]+)"', body)
    if mo:
        chan_meta['image'] = mo.group(1).decode('utf-8', 'replace')
    mo = re.search(rb'<link>([^<]{1,300})</link>', body)
    if mo:
        chan_meta['link'] = mo.group(1).decode('utf-8', 'replace')
    mo = re.search(rb'<description>(.{0,4096})</description>', body, re.S)
    if mo:
        chan_meta['description'] = mo.group(1).decode('utf-8', 'replace')[:2000]
    dates = re.findall(rb'<pubDate>([^<]{1,60})</pubDate>', body)
    if dates:
        chan_meta['latest_pub_date'] = dates[0].decode('utf-8', 'replace')
    channels_index.append(chan_meta)
json.dump(channels_index, open(f'{out}/../channels_index.json', 'w'), ensure_ascii=False, indent=1)
print(f'   channels_index: {len(channels_index)} feeds')

# standard: parseable, per-file <=4MB (giants go to the constructed giant bucket),
# prefer >=50 items, then by item count desc; cap 16 files / ~25MB total
std_meta = [(e, m) for e, m in std_meta_full
            if not m.get('parse_error') and len(e['body']) <= 4 * 1024 * 1024]
std_meta.sort(key=lambda t: (-(t[1].get('items') or 0), -len(t[0]['body'])))
total = 0
kept = []
for e, m in std_meta:
    if len(kept) >= 16 or total > 25 * 1024 * 1024:
        break
    kept.append((e, m))
    total += len(e['body'])
for e, m in kept:
    manifest['standard'].append(save(e, 'standard', extra=m))

# http_plain: cap 6 files / per-file 4MB
hp_kept, hp_total = [], 0
for e in usable:
    if classify(e) != 'http_plain' or len(e['body']) > 4 * 1024 * 1024:
        continue
    if len(hp_kept) >= 6 or hp_total + len(e['body']) > 16 * 1024 * 1024:
        continue
    hp_kept.append(e)
    hp_total += len(e['body'])
for e in hp_kept:
    manifest['http_plain'].append(save(e, 'http_plain', extra=rss_meta(e['body'])))

# redirect: record the 3xx exchange (cap 6); final content kept only if <=2MB
import subprocess
red_count = 0
for e in entries:
    if classify(e) != 'redirect':
        continue
    red_count += 1
    if red_count > 6:
        break
    loc = e['headers']['location'][0]
    if loc.startswith('/'):
        from urllib.parse import urlsplit
        p = urlsplit(e['url'])
        loc = f'{p.scheme}://{p.netloc}{loc}'
    d = os.path.join(out, 'redirect')
    os.makedirs(d, exist_ok=True)
    shutil.copyfile(e['headers_path'], os.path.join(out, 'redirect', f'{e["slug"]}.headers.txt'))
    body, hdr = f'{d}/{e["slug"]}.final.xml', f'{d}/{e["slug"]}.final.headers.txt'
    subprocess.run(['curl', '-sS', '-L', '--max-time', '25', '-A', os.environ.get('UA_BROWSER', 'curl/8'),
                    '-D', hdr, '-o', body, loc], check=False)
    rec = {
        'file': f'{e["slug"]}.headers.txt', 'url': e['url'], 'bucket': 'redirect',
        'status': e['status'], 'location': loc,
        'sha256': hashlib.sha256(e['body']).hexdigest(),
        'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
    }
    if os.path.exists(body) and os.path.getsize(body) <= 2 * 1024 * 1024:
        rec['final_file'] = f'{e["slug"]}.final.xml'
    elif os.path.exists(body):
        os.remove(body)
        os.remove(hdr)
    manifest['redirect'].append(rec)

json.dump(manifest, open(f'{stage}/manifest_live.json', 'w'), ensure_ascii=False, indent=1)
print(f"   standard={len(manifest['standard'])} http_plain={len(manifest['http_plain'])} redirect={len(manifest['redirect'])}")
PYEOF

echo "== 4. probing UA sensitivity (browser / Dart / none) =="
python3 - "$STAGE" "$OUT" <<'PYEOF'
import json, os, subprocess, hashlib, datetime, sys
stage, out = sys.argv[1], sys.argv[2]
manifest = json.load(open(f'{stage}/manifest_live.json'))
uas = {
    'browser': os.environ['UA_BROWSER'],
    'dart': os.environ['UA_DART'],
    'none': '',
}
sensitive = []
for item in manifest.get('standard', []) + manifest.get('http_plain', []):
    url = item['url']
    codes = {}
    for name, ua in uas.items():
        r = subprocess.run(['curl', '-sS', '--max-time', '20'] + (['-A', ua] if ua else ['-A', '']) +
                           ['-o', '/dev/null', '-w', '%{http_code}', url],
                           capture_output=True, text=True)
        codes[name] = r.stdout.strip()
    if len(set(codes.values())) > 1:
        sensitive.append((item, codes))
print(f'   ua-sensitive feeds: {len(sensitive)}')
out_items = []
for item, codes in sensitive[:6]:
    d = os.path.join(out, 'ua_sensitive')
    os.makedirs(d, exist_ok=True)
    base = os.path.splitext(item['file'])[0]
    rec = {'url': item['url'], 'bucket': 'ua_sensitive', 'status_by_ua': codes,
           'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')}
    for name, ua in uas.items():
        hdr = os.path.join(d, f'{base}.{name}.headers.txt')
        body = os.path.join(d, f'{base}.{name}.xml')
        subprocess.run(['curl', '-sS', '--max-time', '25'] + (['-A', ua] if ua else ['-A', '']) +
                       ['-D', hdr, '-o', body, url], check=False)
        if os.path.exists(body):
            if os.path.getsize(body) > 2 * 1024 * 1024:
                os.remove(body)
                rec[f'{name}_body_too_large'] = True
            else:
                rec[f'{name}_sha256'] = hashlib.sha256(open(body, 'rb').read()).hexdigest()
    out_items.append(rec)
json.dump(out_items, open(f'{out}/ua_sensitive/manifest.json', 'w'), ensure_ascii=False, indent=1)
PYEOF

echo "== 5. writing merged manifest =="
python3 - "$STAGE" "$OUT" <<'PYEOF'
import json, sys
stage, out = sys.argv[1], sys.argv[2]
m = json.load(open(f'{stage}/manifest_live.json'))
ua = []
p = f'{out}/ua_sensitive/manifest.json'
import os
if os.path.exists(p):
    ua = json.load(open(p))
merged = {'captured_at': m['standard'][0]['captured_at'] if m['standard'] else None,
          'live': {k: m[k] for k in ('standard', 'http_plain', 'redirect')},
          'ua_sensitive': ua}
# preserve the author-subscription bucket if it was collected separately
# (fetch_user_subs.sh); it is not re-fetched by this script
us_path = f'{out}/user_subs/manifest.json'
if os.path.exists(us_path):
    merged['live']['user_subs'] = json.load(open(us_path))
json.dump(merged, open(f'{out}/manifest.json', 'w'), ensure_ascii=False, indent=1)
print('   manifest written')
PYEOF

echo "done. live corpus in $OUT (constructed buckets pending -> run construct_rss_buckets.py)"
