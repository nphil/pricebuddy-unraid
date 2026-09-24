#!/usr/bin/env python3
"""Pass-through proxy that lets PriceBuddy's AI run on llama.cpp (and llama-swap).

PriceBuddy's AI library calls OpenAI's /v1/responses with the reply schema in
`text.format`. llama.cpp converts /v1/responses to chat completions but drops
`text.format`, so the model answers free-form and every structured call fails. It
does keep unknown fields, so this adds the same schema as a chat-style
`response_format`, which llama.cpp enforces. Everything else is forwarded untouched.
"""
import http.client
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

UPSTREAM = urlsplit(os.environ["AI_COMPAT_URL"].rstrip("/"))
LISTEN_PORT = int(os.environ.get("AI_COMPAT_PORT", "9380"))
HOP = {"connection", "keep-alive", "transfer-encoding", "te", "trailer", "upgrade",
       "proxy-authorization", "proxy-authenticate", "host", "content-length"}


def add_response_format(body: bytes) -> bytes:
    try:
        data = json.loads(body)
    except ValueError:
        return body
    fmt = (data.get("text") or {}).get("format") if isinstance(data, dict) else None
    if not isinstance(fmt, dict) or "response_format" in data:
        return body
    if fmt.get("type") == "json_schema":
        data["response_format"] = {"type": "json_schema", "json_schema": {
            "name": fmt.get("name", "response"),
            "strict": fmt.get("strict", True),
            "schema": fmt.get("schema", {}),
        }}
    elif fmt.get("type") == "json_object":
        data["response_format"] = {"type": "json_object"}
    else:
        return body
    return json.dumps(data).encode()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"  # the body ends when the connection closes

    def forward(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if self.command == "POST" and self.path.rstrip("/").endswith("/responses"):
            body = add_response_format(body)
        conn_cls = http.client.HTTPSConnection if UPSTREAM.scheme == "https" else http.client.HTTPConnection
        conn = conn_cls(UPSTREAM.netloc, timeout=600)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP}
        headers["Content-Length"] = str(len(body))
        try:
            conn.request(self.command, UPSTREAM.path + self.path, body=body or None, headers=headers)
            res = conn.getresponse()
        except OSError as e:
            self.send_error(502, f"AI server unreachable: {e}")
            return
        self.send_response(res.status, res.reason)
        for k, v in res.getheaders():
            if k.lower() not in HOP:
                self.send_header(k, v)
        self.end_headers()
        while chunk := res.read1(65536):
            self.wfile.write(chunk)
            self.wfile.flush()
        conn.close()

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = forward

    def log_message(self, fmt, *args):
        sys.stdout.write("[ai-compat] %s\n" % (fmt % args))
        sys.stdout.flush()


if __name__ == "__main__":
    print(f"[ai-compat] 127.0.0.1:{LISTEN_PORT} -> {UPSTREAM.geturl()}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), Handler).serve_forever()
