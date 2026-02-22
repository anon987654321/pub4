#!/usr/bin/env python3
"""
RG69 terminal log relay.
Run this in Termux, then open rg69.html in the browser.
Log messages will appear here in real time.
"""
from http.server import HTTPServer, BaseHTTPRequestHandler

class LogHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        msg = self.rfile.read(n).decode('utf-8', errors='replace')
        print(msg, flush=True)
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.end_headers()

    def log_message(self, *args):
        pass  # suppress access log noise

print('RG69 log relay listening on http://localhost:3001')
print('Open rg69.html in the browser — logs will appear here.\n')
HTTPServer(('localhost', 3001), LogHandler).serve_forever()
