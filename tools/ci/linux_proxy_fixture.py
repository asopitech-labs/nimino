#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer


class ProxyFixtureHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        body = (
            b"<!doctype html><script>"
            b"window.webkit.messageHandlers.nimino."
            b"postMessage('Nimino Linux proxy');"
            b"</script>"
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        pass


server = HTTPServer(("127.0.0.1", 0), ProxyFixtureHandler)
server.timeout = 15
print(server.server_port, flush=True)
server.handle_request()
server.server_close()
