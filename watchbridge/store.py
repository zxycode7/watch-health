"""Local persistence. No network or third-party dependencies."""
from __future__ import annotations

import hashlib
import json
import math
import os
import secrets
import sqlite3
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

TYPES = {
    "steps": ("quantity", "count"),
    "heart_rate": ("quantity", "count/min"),
    "resting_heart_rate": ("quantity", "count/min"),
    "hrv": ("quantity", "ms"),
    "active_energy": ("quantity", "kcal"),
    "exercise_time": ("quantity", "min"),
    "blood_oxygen": ("quantity", "%"),
    "respiratory_rate": ("quantity", "count/min"),
    "body_mass": ("quantity", "kg"),
    "wrist_temperature": ("quantity", "degC"),
    "sleep": ("category", "category"),
    "workout": ("workout", "s"),
    "vo2_max": ("quantity", "ml/kg*min"),
    "heart_rate_recovery": ("quantity", "count/min"),
    "walking_heart_rate": ("quantity", "count/min"),
    "basal_energy": ("quantity", "kcal"),
    "distance_walking_running": ("quantity", "m"),
    "flights_climbed": ("quantity", "count"),
    "stand_time": ("quantity", "min"),
    "walking_speed": ("quantity", "m/s"),
    "walking_step_length": ("quantity", "m"),
    "walking_asymmetry": ("quantity", "%"),
    "walking_double_support": ("quantity", "%"),
    "walking_steadiness": ("quantity", "%"),
    "daylight": ("quantity", "min"),
    "environmental_audio": ("quantity", "dBASPL"),
    "headphone_audio": ("quantity", "dBASPL"),
    "breathing_disturbances": ("quantity", "count"),
}


class RequestError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


def state_dir() -> Path:
    return Path(os.environ.get("WATCHBRIDGE_HOME", str(Path.home() / "Library/Application Support/WatchBridge")))


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


def identifier(value) -> str:
    try:
        return str(uuid.UUID(str(value))).lower()
    except (ValueError, TypeError, AttributeError):
        raise RequestError("Invalid UUID") from None


def timestamp(value) -> str:
    if not isinstance(value, str) or len(value) > 64:
        raise RequestError("Invalid timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError("Timezone required")
        return parsed.astimezone(timezone.utc).isoformat(timespec="microseconds")
    except ValueError:
        raise RequestError("Timestamp must include a UTC offset") from None


def clean_text(value, maximum=200) -> str:
    if not isinstance(value, str) or len(value) > maximum:
        raise RequestError("Invalid text field")
    return value


class Store:
    def __init__(self, directory: Path):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.directory.chmod(0o700)
        self.path = self.directory / "health.sqlite3"
        with self.connect() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS pairing (
                    singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                    code_hash TEXT NOT NULL, expires REAL NOT NULL, attempts INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS devices (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL,
                    paired_at TEXT NOT NULL, last_sync TEXT, revoked INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS samples (
                    type TEXT NOT NULL, id TEXT NOT NULL, device_id TEXT NOT NULL,
                    start TEXT NOT NULL, end TEXT NOT NULL, value REAL NOT NULL, unit TEXT NOT NULL,
                    source_name TEXT NOT NULL, source_bundle TEXT NOT NULL, device_model TEXT NOT NULL,
                    metadata TEXT NOT NULL, received_at TEXT NOT NULL,
                    PRIMARY KEY(type,id), FOREIGN KEY(device_id) REFERENCES devices(id)
                );
                CREATE INDEX IF NOT EXISTS samples_type_start ON samples(type,start,id);
                CREATE TABLE IF NOT EXISTS checkpoints (
                    device_id TEXT NOT NULL, type TEXT NOT NULL, cursor TEXT NOT NULL,
                    PRIMARY KEY(device_id,type)
                );
                CREATE TABLE IF NOT EXISTS batches (
                    device_id TEXT NOT NULL, id TEXT NOT NULL, payload_hash TEXT NOT NULL,
                    response TEXT NOT NULL, PRIMARY KEY(device_id,id)
                );
            """)
        self.path.chmod(0o600)

    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    def new_pairing(self, lifetime=300) -> str:
        code = secrets.token_urlsafe(24)
        with self.connect() as db:
            db.execute("INSERT OR REPLACE INTO pairing VALUES(1,?,?,0)", (digest(code), time.time() + lifetime))
        return code

    def pair(self, code, device_id, name):
        code = clean_text(code, 100)
        device_id = identifier(device_id)
        name = clean_text(name, 100)
        failed = False
        token = secrets.token_urlsafe(32)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            pairing = db.execute("SELECT * FROM pairing WHERE singleton=1").fetchone()
            if not pairing or pairing["expires"] < time.time() or pairing["attempts"] >= 10:
                raise RequestError("Pairing expired. Generate a new link on the Mac.", 401)
            if not secrets.compare_digest(digest(code), pairing["code_hash"]):
                db.execute("UPDATE pairing SET attempts=attempts+1 WHERE singleton=1")
                failed = True
            else:
                db.execute("""INSERT INTO devices(id,name,token_hash,paired_at) VALUES(?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET name=excluded.name,token_hash=excluded.token_hash,revoked=0""",
                    (device_id, name, digest(token), utcnow()))
                db.execute("DELETE FROM pairing")
        if failed:
            raise RequestError("Invalid pairing code", 401)
        return {"device_id": device_id, "token": token}

    def authenticate(self, token) -> str:
        if not isinstance(token, str) or not 20 <= len(token) <= 200:
            raise RequestError("Authentication required", 401)
        with self.connect() as db:
            row = db.execute("SELECT id FROM devices WHERE token_hash=? AND revoked=0", (digest(token),)).fetchone()
        if not row:
            raise RequestError("Device is unpaired or revoked", 401)
        return row["id"]

    def revoke(self, device_id):
        with self.connect() as db:
            changed = db.execute("UPDATE devices SET revoked=1 WHERE id=?", (identifier(device_id),)).rowcount
        return bool(changed)

    def sync(self, device_id: str, payload: dict):
        if not isinstance(payload, dict):
            raise RequestError("Expected an object")
        batch_id = identifier(payload.get("batch_id"))
        kind = payload.get("type")
        if not isinstance(kind, str) or kind not in TYPES:
            raise RequestError("Unsupported health type")
        samples, deletions = payload.get("samples", []), payload.get("deleted", [])
        if not isinstance(samples, list) or not isinstance(deletions, list) or len(samples) + len(deletions) > 1000:
            raise RequestError("A batch can contain at most 1000 changes")
        cursor = clean_text(payload.get("cursor", ""), 65536)
        payload_hash = digest(json.dumps(payload, sort_keys=True, separators=(",", ":"), allow_nan=False))
        rows = []
        now = utcnow()
        for sample in samples:
            if not isinstance(sample, dict):
                raise RequestError("Invalid sample")
            sample_id = identifier(sample.get("id"))
            start, end = timestamp(sample.get("start")), timestamp(sample.get("end"))
            if end < start:
                raise RequestError("Sample end precedes start")
            value = sample.get("value")
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                raise RequestError("Sample value must be finite")
            if sample.get("unit") != TYPES[kind][1]:
                raise RequestError("Unexpected unit for health type")
            if kind == "sleep" and value not in (0, 1, 2, 3, 4, 5):
                raise RequestError("Unknown sleep category")
            metadata = sample.get("metadata", {})
            if not isinstance(metadata, dict):
                raise RequestError("Invalid metadata")
            encoded = json.dumps(metadata, ensure_ascii=False, allow_nan=False)
            if len(encoded) > 8192:
                raise RequestError("Metadata too large")
            rows.append((kind, sample_id, device_id, start, end, value, sample["unit"],
                         clean_text(sample.get("source_name", "")), clean_text(sample.get("source_bundle", "")),
                         clean_text(sample.get("device_model", "")), encoded, now))
        deleted_ids = [identifier(item) for item in deletions]
        response = {"ok": True, "batch_id": batch_id, "accepted": len(rows), "deleted": len(deleted_ids)}
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            # Recheck inside the commit transaction, so revocation also stops in-flight writes.
            active = db.execute("SELECT 1 FROM devices WHERE id=? AND revoked=0", (device_id,)).fetchone()
            if not active:
                raise RequestError("Device is revoked", 401)
            old = db.execute("SELECT * FROM batches WHERE device_id=? AND id=?", (device_id, batch_id)).fetchone()
            if old:
                if old["payload_hash"] != payload_hash:
                    raise RequestError("Batch ID reused with different content", 409)
                return json.loads(old["response"])
            db.executemany("""INSERT INTO samples VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(type,id) DO UPDATE SET device_id=excluded.device_id,start=excluded.start,
                end=excluded.end,value=excluded.value,unit=excluded.unit,source_name=excluded.source_name,
                source_bundle=excluded.source_bundle,device_model=excluded.device_model,
                metadata=excluded.metadata,received_at=excluded.received_at""", rows)
            db.executemany("DELETE FROM samples WHERE type=? AND id=? AND device_id=?",
                           [(kind, item, device_id) for item in deleted_ids])
            db.execute("INSERT OR REPLACE INTO checkpoints VALUES(?,?,?)", (device_id, kind, cursor))
            db.execute("UPDATE devices SET last_sync=? WHERE id=?", (now, device_id))
            db.execute("INSERT INTO batches VALUES(?,?,?,?)", (device_id, batch_id, payload_hash, json.dumps(response)))
        return response


def read_database(directory: Path):
    path = Path(directory) / "health.sqlite3"
    if not path.is_file():
        raise RequestError("No local database. Start the Mac service first.", 404)
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA query_only=ON")
    return db


def inventory(directory: Path):
    with read_database(directory) as db:
        metrics = [dict(row) for row in db.execute("""SELECT type,unit,COUNT(*) AS records,
            MIN(start) AS earliest,MAX(end) AS latest,MAX(received_at) AS last_received
            FROM samples GROUP BY type,unit ORDER BY type""")]
        devices = [dict(row) for row in db.execute("SELECT id,name,paired_at,last_sync,revoked FROM devices ORDER BY paired_at")]
    return {"metrics": metrics, "devices": devices,
            "note": "No samples may mean missing permission, no recorded data, or no successful sync. It does not mean zero activity."}


def records(directory: Path, kind: str, start: str, end: str, limit=100, offset=0, source=None):
    if not isinstance(kind, str) or kind not in TYPES:
        raise RequestError("Unsupported health type")
    start, end = timestamp(start), timestamp(end)
    if start >= end:
        raise RequestError("End must be after start")
    if isinstance(limit, bool) or not isinstance(limit, int) or not 1 <= limit <= 500:
        raise RequestError("Limit must be between 1 and 500")
    if isinstance(offset, bool) or not isinstance(offset, int) or offset < 0:
        raise RequestError("Invalid offset")
    # Include intervals overlapping the window, plus instantaneous measurements within it.
    where = "type=? AND start<? AND (end>? OR (start=end AND start>=?))"
    parameters = [kind, end, start, start]
    if source is not None:
        where += " AND source_bundle=?"
        parameters.append(clean_text(source))
    with read_database(directory) as db:
        count = db.execute("SELECT COUNT(*) FROM samples WHERE " + where, parameters).fetchone()[0]
        rows = [dict(row) for row in db.execute("SELECT * FROM samples WHERE " + where + " ORDER BY start,id LIMIT ? OFFSET ?",
                                               parameters + [limit, offset])]
    for row in rows:
        row["metadata"] = json.loads(row["metadata"])
    return {"type": kind, "start": start, "end": end, "total": count, "offset": offset,
            "next_offset": offset + len(rows) if offset + len(rows) < count else None,
            "records": rows, "note": "Raw records retain source and unit. Do not sum overlapping sources; in-bed and asleep categories overlap."}
