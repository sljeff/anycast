#!/usr/bin/env python3
"""Local test server for player error paths (05 §1.4):
- /missing.mp3   -> 404
- /error.mp3     -> 500
- /wrongtype.mp3 -> 200 with Content-Type: text/plain
- /no_range/...  -> 200 full body, Range header ignored (plain http.server already ignores it)

Usage: python3 tool/m0/serve_local.py <serve_dir> [port]
"""
import os
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        name = self.path.rsplit('/', 1)[-1]
        if name == 'missing.mp3':
            self.send_error(404, 'Not Found')
            return
        if name == 'error.mp3':
            self.send_error(500, 'Internal Server Error')
            return
        if name == 'wrongtype.mp3':
            body = b'pretend audio bytes'
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        # Range support deliberately absent (SimpleHTTPRequestHandler ignores it)
        super().do_GET()


if __name__ == '__main__':
    root = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8765
    os.chdir(root)
    srv = ThreadingHTTPServer(('127.0.0.1', port), partial(Handler, directory=root))
    print(f'serving {root} on http://127.0.0.1:{port} (no Range support)')
    srv.serve_forever()
