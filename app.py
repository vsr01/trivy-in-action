"""Tiny demo HTTP service used to exercise the Trivy CI pipeline."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"
PORT = 8000


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path in ("/", "/health"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"ok\n")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        # Silence default access logging to keep the demo output clean.
        return


def main() -> None:
    with ThreadingHTTPServer((HOST, PORT), Handler) as server:
        print(f"listening on http://{HOST}:{PORT}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
