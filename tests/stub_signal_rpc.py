#!/usr/bin/env python3
"""Stub signal-cli JSON-RPC HTTP daemon for tests.

Usage: stub_signal_rpc.py <port-file> <requests-file> [error]
Binds 127.0.0.1 on an ephemeral port, writes the port to <port-file>, appends each
request body (one JSON object per line) to <requests-file>. With `error`, replies
with a JSON-RPC error object instead of a result.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT_FILE, REQ_FILE = sys.argv[1], sys.argv[2]
FAIL = len(sys.argv) > 3 and sys.argv[3] == "error"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        with open(REQ_FILE, "a") as handle:
            handle.write(json.dumps({"path": self.path, "body": json.loads(body)}) + "\n")
        request_id = json.loads(body).get("id")
        if FAIL:
            reply = {"jsonrpc": "2.0", "id": request_id,
                     "error": {"code": -1, "message": "Unregistered user"}}
        else:
            reply = {"jsonrpc": "2.0", "id": request_id, "result": {"timestamp": 1}}
        data = json.dumps(reply).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE, "w") as handle:
    handle.write(str(server.server_address[1]))
server.serve_forever()
