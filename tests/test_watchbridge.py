import copy
import http.client
import json
import math
import os
import sqlite3
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
import uuid
from pathlib import Path

from watchbridge.mcp import call_tool
from watchbridge.server import ensure_certificate, make_server
from watchbridge.store import RequestError, Store, inventory, read_database, records


def uid():
    return str(uuid.uuid4())


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.store = Store(self.directory)
        self.device = uid()
        self.token = self.store.pair(self.store.new_pairing(), self.device, "我的 iPhone")["token"]

    def tearDown(self):
        self.temporary.cleanup()

    def batch(self, kind="steps", sample_id=None):
        return {"batch_id": uid(), "type": kind, "cursor": "opaque-healthkit-anchor", "deleted": [], "samples": [{
            "id": sample_id or uid(), "start": "2026-10-16T00:30:00+08:00", "end": "2026-10-16T00:31:00+08:00",
            "value": 42, "unit": "count", "source_name": "Apple Watch", "source_bundle": "com.apple.health",
            "device_model": "Watch", "metadata": {}}]}

    def test_pair_code_is_single_use_and_token_is_hashed(self):
        code = self.store.new_pairing()
        self.store.pair(code, uid(), "Phone")
        with self.assertRaises(RequestError):
            self.store.pair(code, uid(), "Phone")
        with self.store.connect() as db:
            self.assertNotIn(self.token, str([dict(row) for row in db.execute("SELECT * FROM devices")]))
        self.assertEqual(self.store.authenticate(self.token), self.device)

    def test_expired_and_failed_pairing_attempts(self):
        self.store.new_pairing(lifetime=-1)
        with self.assertRaises(RequestError):
            self.store.pair("bad", uid(), "Phone")
        code = self.store.new_pairing()
        for _ in range(10):
            with self.assertRaises(RequestError):
                self.store.pair("bad", uid(), "Phone")
        with self.assertRaises(RequestError):
            self.store.pair(code, uid(), "Phone")

    def test_idempotency_and_changed_batch_rejected(self):
        batch = self.batch()
        first = self.store.sync(self.device, batch)
        self.assertEqual(self.store.sync(self.device, batch), first)
        self.assertEqual(inventory(self.directory)["metrics"][0]["records"], 1)
        changed = copy.deepcopy(batch)
        changed["samples"][0]["value"] = 99
        with self.assertRaises(RequestError) as context:
            self.store.sync(self.device, changed)
        self.assertEqual(context.exception.status, 409)

    def test_invalid_batch_does_not_advance_checkpoint_or_partially_write(self):
        batch = self.batch()
        bad = copy.deepcopy(batch["samples"][0])
        bad["unit"] = "mile"
        batch["samples"].append(bad)
        with self.assertRaises(RequestError):
            self.store.sync(self.device, batch)
        with self.store.connect() as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM samples").fetchone()[0], 0)
            self.assertEqual(db.execute("SELECT COUNT(*) FROM checkpoints").fetchone()[0], 0)

    def test_duplicate_samples_and_deletions(self):
        batch = self.batch()
        self.store.sync(self.device, batch)
        batch["batch_id"] = uid()
        self.store.sync(self.device, batch)
        self.assertEqual(inventory(self.directory)["metrics"][0]["records"], 1)
        self.store.sync(self.device, {"batch_id": uid(), "type": "steps", "cursor": "next", "samples": [], "deleted": [batch["samples"][0]["id"]]})
        self.assertEqual(inventory(self.directory)["metrics"], [])

    def test_other_device_cannot_delete_sample_and_revocation_blocks_writes(self):
        batch = self.batch()
        self.store.sync(self.device, batch)
        other = uid()
        self.store.pair(self.store.new_pairing(), other, "Other")
        self.store.sync(other, {"batch_id": uid(), "type": "steps", "samples": [], "deleted": [batch["samples"][0]["id"]]})
        self.assertEqual(inventory(self.directory)["metrics"][0]["records"], 1)
        self.store.revoke(self.device)
        with self.assertRaises(RequestError):
            self.store.authenticate(self.token)
        with self.assertRaises(RequestError):
            self.store.sync(self.device, self.batch())

    def test_local_midnight_pagination_and_source_filter(self):
        self.store.sync(self.device, self.batch())
        batch = self.batch()
        batch["samples"][0]["source_bundle"] = "other.source"
        self.store.sync(self.device, batch)
        first = call_tool(self.directory, "watchbridge_day", {"type": "steps", "date": "2026-10-16", "limit": 1})
        self.assertEqual(first["total"], 2)
        self.assertEqual(first["next_offset"], 1)
        previous = call_tool(self.directory, "watchbridge_day", {"type": "steps", "date": "2026-10-15"})
        self.assertEqual(previous["total"], 0)
        filtered = records(self.directory, "steps", "2026-10-16T00:00:00+08:00", "2026-10-17T00:00:00+08:00", source="other.source")
        self.assertEqual(filtered["total"], 1)

    def test_sleep_crossing_midnight_and_read_only_connection(self):
        batch = self.batch("sleep")
        batch["samples"][0].update(unit="category", value=3, start="2026-10-15T23:00:00+08:00", end="2026-10-16T06:00:00+08:00")
        self.store.sync(self.device, batch)
        self.assertEqual(call_tool(self.directory, "watchbridge_day", {"type": "sleep", "date": "2026-10-16"})["total"], 1)
        with read_database(self.directory) as db:
            with self.assertRaises(sqlite3.OperationalError):
                db.execute("DELETE FROM samples")

    def test_bad_dates_nonfinite_and_unknown_type(self):
        for change in ({"value": float("nan")}, {"start": "2026-10-16T00:00:00"}, {"end": "2020-01-01T00:00:00Z"}):
            batch = self.batch()
            batch["samples"][0].update(change)
            with self.assertRaises((RequestError, ValueError)):
                self.store.sync(self.device, batch)
        with self.assertRaises(RequestError):
            call_tool(self.directory, "watchbridge_day", {"type": "steps", "date": "2026-02-30"})
        with self.assertRaises(RequestError):
            records(self.directory, "steps", "2026-10-16T00:00:00Z", "2026-10-17T00:00:00Z", limit=501)

    def test_stdio_mcp_interoperability(self):
        self.store.sync(self.device, self.batch())
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "watchbridge_day", "arguments": {"type": "steps", "date": "2026-10-16"}}},
        ]
        process = subprocess.run([sys.executable, "-m", "watchbridge", "mcp"],
            input="".join(json.dumps(item) + "\n" for item in messages), text=True, capture_output=True,
            env=dict(os.environ, WATCHBRIDGE_HOME=str(self.directory)), timeout=10)
        self.assertEqual(process.returncode, 0, process.stderr)
        responses = [json.loads(line) for line in process.stdout.splitlines()]
        self.assertEqual([item["id"] for item in responses], [1, 2, 3])
        self.assertEqual(len(responses[1]["result"]["tools"]), 3)
        self.assertEqual(json.loads(responses[2]["result"]["content"][0]["text"])["total"], 1)


class HTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.directory = Path(cls.temporary.name)
        cls.server = make_server(cls.directory, "127.0.0.1", 0)
        cls.worker = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.worker.start()
        cert, _, cls.pin = ensure_certificate(cls.directory)
        cls.context = ssl.create_default_context(cafile=str(cert))
        cls.context.check_hostname = False  # Test trusts only the freshly generated certificate.

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.worker.join(timeout=2)
        cls.temporary.cleanup()

    def request(self, method, path, body=None, headers=None):
        connection = http.client.HTTPSConnection("127.0.0.1", self.server.server_port, context=self.context, timeout=5)
        connection.request(method, path, body, headers or {})
        response = connection.getresponse()
        data = response.read()
        connection.close()
        return response.status, json.loads(data)

    def test_health_and_authentication(self):
        self.assertTrue(self.request("GET", "/healthz")[1]["ok"])
        self.assertEqual(self.request("GET", "/v1/samples")[0], 404)
        self.assertEqual(self.request("POST", "/v1/sync", "{}")[0], 401)

    def test_https_pair_and_malformed_json(self):
        store = Store(self.directory)
        code = store.new_pairing()
        status, response = self.request("POST", "/v1/pair", json.dumps({"code": code, "device_id": uid(), "name": "Test phone"}), {"Content-Type": "application/json"})
        self.assertEqual(status, 200)
        self.assertTrue(response["token"])
        self.assertEqual(self.request("POST", "/v1/pair", "{bad", {"Content-Type": "application/json"})[0], 400)


if __name__ == "__main__":
    unittest.main()
