#!/usr/bin/env python3
"""Wrap a curl response (body + trailing '\n<http_code>' from -w) into a fixture envelope."""
import datetime
import json
import sys

out, url = sys.argv[1], sys.argv[2]
raw = sys.stdin.buffer.read().decode('utf-8', 'replace')
body, _, code = raw.rpartition('\n')
try:
    status = int(code.strip())
except ValueError:
    status = 0
json.dump({
    'status': status,
    'body': body,
    'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
    'source': 'recorded',
    'request_url': url,
}, open(out, 'w'), ensure_ascii=False, indent=1)
