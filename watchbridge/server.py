from __future__ import annotations

import hashlib
import json
import os
import ssl
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import __version__
from .store import RequestError, Store

MAX_BODY = 8 * 1024 * 1024


def ensure_certificate(directory: Path):
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    certificate, key = directory / "certificate.pem", directory / "private-key.pem"
    if certificate.exists() != key.exists():
        raise RuntimeError("Certificate/key pair is incomplete; restore both from your backup.")
    if not certificate.exists():
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256",
                        "-nodes", "-days", "3650", "-subj", "/CN=WatchBridge Local",
                        "-keyout", str(key), "-out", str(certificate)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        key.chmod(0o600)
        certificate.chmod(0o600)
    der = ssl.PEM_cert_to_DER_cert(certificate.read_text())
    return certificate, key, hashlib.sha256(der).hexdigest()


def make_server(directory: Path, host="0.0.0.0", port=8765):
    store = Store(directory)
    certificate, key, _ = ensure_certificate(directory)

    class Handler(BaseHTTPRequestHandler):
        server_version = "WatchBridge/" + __version__
        timeout = 20

        def log_message(self, *_):
            pass  # Never log request URLs, pairing credentials, or health payloads.

        def send_json(self, status, data):
            body = json.dumps(data, ensure_ascii=False, allow_nan=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/healthz":
                self.send_json(200, {"ok": True, "version": __version__})
            else:
                self.send_json(404, {"error": "Not found"})

        def do_POST(self):
            try:
                if self.path not in ("/v1/pair", "/v1/sync"):
                    raise RequestError("Not found", 404)
                device = None
                if self.path == "/v1/sync":
                    authorization = self.headers.get("Authorization", "")
                    device = store.authenticate(authorization[7:] if authorization.startswith("Bearer ") else "")
                if self.headers.get_content_type() != "application/json":
                    raise RequestError("Content-Type must be application/json", 415)
                if self.headers.get("Transfer-Encoding"):
                    raise RequestError("Chunked request bodies are unsupported")
                try:
                    size = int(self.headers.get("Content-Length", "-1"))
                except ValueError:
                    raise RequestError("Invalid Content-Length") from None
                if not 0 < size <= MAX_BODY:
                    raise RequestError("Request body must be between 1 byte and 8 MiB", 413)
                body = self.rfile.read(size)
                if len(body) != size:
                    raise RequestError("Incomplete body")
                payload = json.loads(body, parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Non-finite JSON")))
                if not isinstance(payload, dict):
                    raise RequestError("Expected a JSON object")
                if self.path == "/v1/pair":
                    result = store.pair(payload.get("code"), payload.get("device_id"), payload.get("name"))
                else:
                    result = store.sync(device, payload)
                self.send_json(200, result)
            except RequestError as error:
                self.send_json(error.status, {"error": str(error)})
            except (ValueError, UnicodeDecodeError):
                self.send_json(400, {"error": "Malformed JSON or invalid numeric data"})
            except (ConnectionError, TimeoutError):
                self.close_connection = True
            except Exception:
                self.send_json(500, {"error": "Local database operation failed; no checkpoint was acknowledged"})

    httpd = ThreadingHTTPServer((host, port), Handler)
    httpd.daemon_threads = True
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(certificate, key)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    return httpd
