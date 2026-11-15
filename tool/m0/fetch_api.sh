#!/usr/bin/env bash
# M0 API fixtures (05 §1.3): record live responses where possible (no-auth
# endpoints + unauthenticated error paths), construct the rest per 02 field spec.
# Output: test/fixtures/api/<endpoint>/<branch>.json  (self-contained envelopes)
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="test/fixtures/api"
mkdir -p "$OUT"
UA_BROWSER="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

rec() { # rec <endpoint> <branch> [curl args...] <url-last>
  local ep="$1" br="$2"
  shift 2
  local url="${@: -1}"
  set -- "${@:1:$#-1}"
  mkdir -p "$OUT/$ep"
  curl -sS --max-time 20 -A "$UA_BROWSER" -w '\n%{http_code}' "$@" "$url" \
    | python3 tool/m0/_envelope.py "$OUT/$ep/$br.json" "$url"
}

con() { # con <endpoint> <branch> <note> (body on stdin as raw json text)
  local ep="$1" br="$2" note="$3" tmpf
  tmpf="$(mktemp)"
  cat > "$tmpf"
  mkdir -p "$OUT/$ep"
  python3 - "$OUT/$ep/$br.json" "$note" "$tmpf" <<'PY'
import json, sys
out, note, bodyfile = sys.argv[1], sys.argv[2], sys.argv[3]
body = open(bodyfile).read()
json.dump({
    'status': 200,
    'body': body,
    'source': 'constructed',
    'note': note,
}, open(out, 'w'), ensure_ascii=False, indent=1)
PY
  rm -f "$tmpf"
}

echo "== live recordings =="
rec user_get unauthenticated_401 "https://anycast.website/api/user"
rec user_delete unauthenticated_401 -X DELETE "https://anycast.website/api/user"
rec categories ok "https://anycast.website/api/categories"
rec categories empty_country_probe "https://anycast.website/api/categories?country=US"
rec top_channels ok_us "https://anycast.website/api/top-channels?category_id=10001&country=US"
rec top_channels ok_cn "https://anycast.website/api/top-channels?category_id=10001&country=CN"
rec top_channels ok_jp "https://anycast.website/api/top-channels?category_id=10002&country=JP"
rec top_channels unknown_category_null_data "https://anycast.website/api/top-channels?category_id=99999999&country=US"
rec search_channels ok "https://anycast.website/api/search/channels?keyword=technology&limit=20"
rec search_channels no_results "https://anycast.website/api/search/channels?keyword=zzxxqqwwunlikelyterm12345&limit=20"
rec search_episodes ok "https://anycast.website/api/search/episodes?keyword=science&limit=20"
rec search_episodes no_results "https://anycast.website/api/search/episodes?keyword=zzxxqqwwunlikelyterm12345&limit=20"
rec subtitles_post unauthenticated_401 -X POST -H 'Content-Type: application/json' \
  -d '{"enclosure_url":"https://example.com/ep.mp3"}' "https://anycast.website/api/subtitles"
rec subtitles_chat_post unauthenticated_401 -X POST -H 'Content-Type: application/json' \
  -d '{"enclosure_url":"https://example.com/ep.mp3","user_input":"hello","history":[]}' "https://anycast.website/api/subtitles/chat"
rec subtitles_translate_post unknown_url "https://anycast.website/api/subtitles/translate" \
  -X POST -H 'Content-Type: application/json' \
  -d '{"enclosure_url":"https://example.com/nonexistent-episode.mp3","language":"zh"}'
rec shortlink_post ok -X POST -H 'Content-Type: application/json' \
  -d "{\"cmd\":\"add\",\"url\":\"https://anycast.website/player?rssfeedurl=https%3A%2F%2Fexample.com%2Ffeed.xml&enclosureurl=https%3A%2F%2Fexample.com%2Fep1.mp3\",\"password\":\"cjp2PGN3zuf5cfh\",\"key\":\"$(python3 -c "import hashlib;print(hashlib.md5(b'https://anycast.website/player?rssfeedurl=https%3A%2F%2Fexample.com%2Ffeed.xml&enclosureurl=https%3A%2F%2Fexample.com%2Fep1.mp3').hexdigest())")\"}" \
  "https://anycast.website/api/shortlink"

echo "== constructed branches =="
con user_get ok_free_plus0_expired_null 'plus=0, expired_at=null, remaining>0' <<'J'
{"uid":"fixture-uid-free-001","expired_at":null,"remaining":7,"plus":0}
J
con user_get ok_plus1_expired_set 'plus=1 with expiry (Jiffy pattern yyyy-MM-ddTHH:mm:ssZ)' <<'J'
{"uid":"fixture-uid-plus-001","expired_at":"2027-03-15T09:30:00+00:00","remaining":42,"plus":1}
J
con user_get ok_remaining_zero 'free user, quota exhausted' <<'J'
{"uid":"fixture-uid-free-002","expired_at":null,"remaining":0,"plus":0}
J
con user_get not_json_body 'non-JSON body: K4 crash-family (jsonDecode outside try, user.dart:41)' <<'J'
<html><head><title>502 Bad Gateway</title></head><body><h1>502 Bad Gateway</h1></body></html>
J
con search_channels empty_channel_list 'data.channel_list == []' <<'J'
{"data":{"channel_list":[]}}
J
con search_episodes empty_data 'data == []' <<'J'
{"data":[]}
J
con categories empty_list 'data == [] (Discover shows Network Error per 02 §4.2)' <<'J'
{"data":[]}
J
con top_channels null_data 'data == null -> client returns empty list (02 §1.2)' <<'J'
{"data":null}
J

# subtitles state machine frames
con subtitles_post processing_frame_1 'poll frame 1/3, 15s cadence' <<'J'
{"status":"processing"}
J
con subtitles_post processing_frame_2 'poll frame 2/3' <<'J'
{"status":"processing"}
J
con subtitles_post processing_frame_3 'poll frame 3/3' <<'J'
{"status":"processing"}
J
python3 - "$OUT" <<'PY'
import json, sys
out = sys.argv[1]
def w(ep, br, obj, note, status=200):
    json.dump({'status': status, 'body': json.dumps(obj, ensure_ascii=False),
               'source': 'constructed', 'note': note},
              open(f'{out}/{ep}/{br}.json', 'w'), ensure_ascii=False, indent=1)

segs = [{"start": round(0.0 + i * 4.2, 2), "end": round(4.0 + i * 4.2, 2),
         "text": f"Sample transcript segment number {i}."} for i in range(40)]
w('subtitles_post', 'succeeded_english',
  {"status": "succeeded", "subtitle": {"detected_language": "en", "segments": segs}},
  'plain English segments')
special = ["café résumé naïve — em—dash", "中文与日本語の混在", 'quotes "both" \'kinds\'',
           "tabs\tand\nnewlines", "emoji 🎧🚀 and RTL عربى text",
           "a very long sentence " * 30]
segs2 = [{"start": round(i * 3.7, 3), "end": round(3.5 + i * 3.7, 3), "text": special[i % len(special)]}
         for i in range(len(special) * 2)]
w('subtitles_post', 'succeeded_special_chars',
  {"status": "succeeded", "subtitle": {"detected_language": "en", "segments": segs2}},
  'special characters / CJK / RTL / emoji / long sentences / fractional seconds')
w('subtitles_post', 'failed', {"status": "failed"}, 'terminal failure')
w('subtitles_post', 'error_403_quota', {"error": "Monthly transcription limit exceeded. Upgrade to Plus for 50 transcriptions per month.", "code": 1},
  'quota exhausted', status=403)
w('subtitles_post', 'error_403_code2', {"error": "session expired", "code": 2},
  'code==2 -> login sheet (error_handler.dart)', status=403)
w('subtitles_post', 'error_429', "Too Many Requests", 'Cloudflare edge only; no app-layer rate limit (02 §7)', status=429)
w('subtitles_post', 'error_500', "Internal Server Error", 'K27: background polling must stay silent + keep processing', status=500)

tr = lambda lang: [{"start": s["start"], "end": s["end"], "text": f"[{lang}] " + s["text"]} for s in segs[:20]]
w('subtitles_translate_post', 'ok_zh', {"translation": tr('zh')}, 'target zh')
w('subtitles_translate_post', 'ok_ja', {"translation": tr('ja')}, 'target ja')
w('subtitles_translate_post', 'ok_de', {"translation": tr('de')}, 'target de')
w('subtitles_translate_post', 'translation_null', {"translation": None}, 'no translation yet')
w('subtitles_chat_post', 'ok_short', {"result": "This episode discusses the history of podcasting in brief."}, 'short reply')
w('subtitles_chat_post', 'ok_long', {"result": "A detailed answer. " * 120}, 'long reply, close to 10s latency budget')
w('subtitles_chat_post', 'non2xx_body_as_reply', {"error": "quota exceeded", "code": 1},
  'K8: old client displays raw body as AI message; 401/403 must not be shown as replies in native', status=403)
w('shortlink_post', 'status_not_200', {"status": 400, "message": "invalid url"}, 'status!=200 -> degrade to long url', status=200)
w('user_delete', 'ok_200', '', 'statusCode 200 == success (body ignored)', status=200)
w('user_delete', 'error_500', 'Internal Server Error', 'non-200 -> ErrorHandler + null', status=500)

# non-response branches (transport-level, for URLProtocol replay setup)
for ep, br, err, note in [
    ('user_get', 'network_timeout', 'timeout', 'request times out (10s reqWithAuth)'),
    ('search_channels', 'network_failure', 'connection_error', 'fetchWithRetry returns null -> response! crash (K4)'),
    ('search_episodes', 'network_failure', 'connection_error', 'same K4 family'),
    ('categories', 'network_failure', 'connection_error', 'old client: FutureBuilder stuck on spinner'),
    ('top_channels', 'network_failure', 'connection_error', 'bare http.get, no retry'),
    ('subtitles_post', 'network_timeout', 'timeout', '10s timeout; retry only network errors'),
    ('subtitles_translate_post', 'slow_response', 'slow', '>10s response; old client has NO timeout (K9 adds 30s)'),
    ('subtitles_chat_post', 'network_timeout', 'timeout', '10s timeout on non-stream endpoint'),
    ('shortlink_post', 'network_timeout', 'timeout', '3s timeout, 3 attempts, degrade to long url'),
]:
    json.dump({'status': 0, 'error': err, 'source': 'constructed', 'note': note},
              open(f'{out}/{ep}/{br}.json', 'w'), ensure_ascii=False, indent=1)
print('constructed branches written')
PY

echo "== summary =="
for d in "$OUT"/*/; do echo "$(basename "$d"): $(ls "$d" | wc -l | tr -d ' ') branches"; done
