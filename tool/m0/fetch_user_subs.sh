#!/usr/bin/env bash
# M0 corpus collection: the author's real subscription export (OPML ->
# tool/m0/feeds_user.txt) -> test/fixtures/rss/user_subs/
# Same provenance model as fetch_rss.sh: *.xml payloads are gitignored,
# *.headers.txt + manifest.json are the committed capture records.
#
# Re-running refreshes the live content; afterwards re-run the golden export.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="test/fixtures/rss/user_subs"
UA_BROWSER="${UA_BROWSER:-Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15}"

mkdir -p "$OUT"

grep -vE '^\s*(#|$)' tool/m0/feeds_user.txt | sort -u > "$OUT/.urls.txt"
total=$(wc -l < "$OUT/.urls.txt" | tr -d ' ')
echo "fetching $total user feeds"

# NNNN<TAB>url work list; sequential fetch keeps ordering stable and is
# gentle on small self-hosted feeds (ximalaya/xyzfm/fireside et al).
awk '{printf "%04d\t%s\n", NR, $0}' "$OUT/.urls.txt" > "$OUT/.work.txt"
while IFS=$'\t' read -r slug url; do
  # -L: unlike the redirect bucket (which records the 3xx exchange itself),
  # this bucket exists to supply usable feed content for db_user
  curl -sSL --max-time 25 -A "$UA_BROWSER" \
    -D "$OUT/$slug.headers.txt" \
    -o "$OUT/$slug.xml" \
    -w '%{http_code}' "$url" > "$OUT/$slug.code" 2>/dev/null \
    || echo "000" > "$OUT/$slug.code"
  # keep manifest<->payload parity: a failed fetch leaves an empty file
  [[ -f "$OUT/$slug.xml" ]] || : > "$OUT/$slug.xml"
done < "$OUT/.work.txt"

python3 - <<'PYEOF'
import json, os, re, hashlib, datetime
from xml.etree import ElementTree as ET

out = 'test/fixtures/rss/user_subs'

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

items = []
for line in open(f'{out}/.work.txt'):
    slug, url = line.rstrip('\n').split('\t')
    code_f = f'{out}/{slug}.code'
    code = open(code_f).read().strip() if os.path.exists(code_f) else '000'
    status, headers = read_headers(f'{out}/{slug}.headers.txt')
    body = open(f'{out}/{slug}.xml', 'rb').read() if os.path.exists(f'{out}/{slug}.xml') else b''
    rec = {
        'file': f'{slug}.xml',
        'url': url,
        'bucket': 'user_subs',
        'status': int(code) if code.isdigit() else 0,
        'content_type': (headers.get('content-type') or [''])[0],
        'sha256': hashlib.sha256(body).hexdigest(),
        'bytes': len(body),
        'fetched_ua': 'browser',
        'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
    }
    if 300 <= rec['status'] < 400 and 'location' in headers:
        rec['location'] = headers['location'][0]
    if rec['status'] == 200 and body:
        rec.update(rss_meta(body))
    else:
        rec['note'] = 'fetch_failed_or_empty'
    items.append(rec)

for line in open(f'{out}/.work.txt'):
    slug = line.split('\t')[0]
    code_f = f'{out}/{slug}.code'
    if os.path.exists(code_f):
        os.remove(code_f)
os.remove(f'{out}/.work.txt')
os.remove(f'{out}/.urls.txt')

ok = [i for i in items if 'parse_error' not in i and i.get('items')]
json.dump(items, open(f'{out}/manifest.json', 'w'), ensure_ascii=False, indent=1)
print(f'   user_subs: {len(items)} fetched, {len(ok)} parseable')

# embed into the merged rss manifest (same shape as live.* buckets)
m_path = 'test/fixtures/rss/manifest.json'
m = json.load(open(m_path))
m.setdefault('live', {})['user_subs'] = items
json.dump(m, open(m_path, 'w'), ensure_ascii=False, indent=1)
print('   merged into rss/manifest.json as live.user_subs')
PYEOF

echo "done."
