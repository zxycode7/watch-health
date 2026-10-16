"""Dependency-free, read-only stdio MCP server. Logs never go to stdout."""
from __future__ import annotations

import json
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

from . import __version__
from .store import TYPES, RequestError, inventory, records, state_dir

PROTOCOLS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
TOOLS = [
    {"name": "watchbridge_status", "description": "Inspect locally paired devices, available metrics, record counts and freshness. Empty data is not zero activity.",
     "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
    {"name": "watchbridge_records", "description": "Read raw Apple Health records in an offset-aware half-open time range. Preserves sample UUID, source, device, unit and sleep category. Paginated; never sum overlapping sources.",
     "inputSchema": {"type": "object", "properties": {
         "type": {"type": "string", "enum": list(TYPES)},
         "start": {"type": "string", "description": "ISO 8601 timestamp with offset"},
         "end": {"type": "string", "description": "Exclusive ISO 8601 timestamp with offset"},
         "limit": {"type": "integer", "minimum": 1, "maximum": 500, "default": 100},
         "offset": {"type": "integer", "minimum": 0, "default": 0},
         "source": {"type": "string", "description": "Optional exact source bundle identifier"}},
         "required": ["type", "start", "end"], "additionalProperties": False}},
    {"name": "watchbridge_day", "description": "Read one local calendar day for one metric. Defaults to Asia/Shanghai. Sleep intervals overlapping midnight are retained; counts are records, not daily totals.",
     "inputSchema": {"type": "object", "properties": {
         "type": {"type": "string", "enum": list(TYPES)},
         "date": {"type": "string", "description": "YYYY-MM-DD, defaults to today in the requested timezone"},
         "timezone": {"type": "string", "default": "Asia/Shanghai"},
         "limit": {"type": "integer", "minimum": 1, "maximum": 500, "default": 100},
         "offset": {"type": "integer", "minimum": 0, "default": 0}},
         "required": ["type"], "additionalProperties": False}},
]
for tool in TOOLS:
    tool["annotations"] = {"readOnlyHint": True, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False}


def call_tool(directory: Path, name: str, arguments: dict):
    if not isinstance(arguments, dict):
        raise RequestError("Arguments must be an object")
    definition = next((tool for tool in TOOLS if tool["name"] == name), None)
    if definition is None:
        raise RequestError("Unknown tool")
    schema = definition["inputSchema"]
    if set(arguments) - set(schema["properties"]) or set(schema.get("required", [])) - set(arguments):
        raise RequestError("Unexpected or missing arguments")
    if name == "watchbridge_status":
        return inventory(directory)
    if name == "watchbridge_day":
        try:
            zone = ZoneInfo(arguments.get("timezone", "Asia/Shanghai"))
            day = date.fromisoformat(arguments["date"]) if "date" in arguments else datetime.now(zone).date()
            beginning = datetime.combine(day, time.min, zone)
            ending = datetime.combine(day + timedelta(days=1), time.min, zone)
        except (ValueError, KeyError, TypeError):
            raise RequestError("Invalid calendar date or timezone") from None
        return records(directory, arguments["type"], beginning.isoformat(), ending.isoformat(),
                       arguments.get("limit", 100), arguments.get("offset", 0))
    return records(directory, arguments["type"], arguments["start"], arguments["end"],
                   arguments.get("limit", 100), arguments.get("offset", 0), arguments.get("source"))


def dispatch(message: dict, directory: Path):
    request_id = message.get("id")
    if "id" not in message:
        return None
    response = {"jsonrpc": "2.0", "id": request_id}
    method, params = message.get("method"), message.get("params", {})
    try:
        if not isinstance(params, dict):
            raise RequestError("Invalid params")
        if method == "initialize":
            requested = params.get("protocolVersion")
            response["result"] = {"protocolVersion": requested if requested in PROTOCOLS else PROTOCOLS[0],
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "watchbridge", "version": __version__},
                "instructions": "Health data is local, raw and source-specific. Start with status. Missing records do not establish permission denial or zero activity. Never infer diagnosis from this connector."}
        elif method == "ping":
            response["result"] = {}
        elif method == "tools/list":
            response["result"] = {"tools": TOOLS}
        elif method == "tools/call":
            try:
                data = call_tool(directory, params.get("name"), params.get("arguments", {}))
                response["result"] = {"content": [{"type": "text", "text": json.dumps(data, ensure_ascii=False, allow_nan=False)}], "isError": False}
            except (RequestError, TypeError, ValueError) as error:
                response["result"] = {"content": [{"type": "text", "text": str(error)}], "isError": True}
        else:
            response["error"] = {"code": -32601, "message": "Method not found"}
    except RequestError as error:
        response["error"] = {"code": -32602, "message": str(error)}
    return response


def main():
    directory = state_dir()
    for line in sys.stdin:
        try:
            if len(line) > 1024 * 1024:
                raise ValueError("Message too large")
            message = json.loads(line)
            if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
                raise ValueError("Invalid JSON-RPC request")
            response = dispatch(message, directory)
        except (ValueError, TypeError):
            response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}
        except Exception:
            response = {"jsonrpc": "2.0", "id": None, "error": {"code": -32603, "message": "Local query failed"}}
        if response is not None:
            print(json.dumps(response, ensure_ascii=False, allow_nan=False), flush=True)


if __name__ == "__main__":
    main()
