"""Optional real Swift/TLS test, invoked explicitly rather than on Python-only hosts."""
import subprocess
import tempfile
import threading
from pathlib import Path
from urllib.parse import urlencode

from watchbridge.server import ensure_certificate, make_server
from watchbridge.store import Store, inventory


def main():
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        executable = directory / "transport-tests"
        files = [root / "ios/WatchBridge" / name for name in ["Models.swift", "BridgeClient.swift"]]
        subprocess.run(["/usr/bin/xcrun", "swiftc", *map(str, files), str(root / "tests/SwiftTransportTests.swift"), "-o", str(executable)], check=True)
        server = make_server(directory, "127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            _, _, pin = ensure_certificate(directory)
            code = Store(directory).new_pairing()
            url = "watchbridge://pair?" + urlencode({"endpoint": f"https://127.0.0.1:{server.server_port}", "pin": pin, "code": code})
            subprocess.run([str(executable)], input=url + "\n", text=True, check=True, timeout=45)
            assert inventory(directory)["metrics"][0]["records"] == 1
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    main()
