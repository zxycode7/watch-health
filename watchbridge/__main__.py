from __future__ import annotations

import argparse
import json
import os
import socket
from urllib.parse import urlencode, urlsplit

from .server import ensure_certificate, make_server
from .store import Store, inventory, state_dir


def lan_ip():
    # UDP connect selects the default interface; no packet is transmitted.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as connection:
        try:
            connection.connect(("192.0.2.1", 9))
            return connection.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description="健康桥：自托管 Apple 健康数据")
    commands = parser.add_subparsers(dest="command", required=True)
    serve = commands.add_parser("serve", help="启动本地 HTTPS 同步服务")
    serve.add_argument("--host", default="0.0.0.0")
    serve.add_argument("--port", type=int, default=8765)
    pair = commands.add_parser("pair", help="生成 5 分钟有效、仅用一次的配对链接")
    pair.add_argument("--endpoint", default=None)
    commands.add_parser("status", help="查看数据清单")
    revoke = commands.add_parser("revoke", help="撤销一台手机的同步权限；保留已有数据")
    revoke.add_argument("device_id")
    commands.add_parser("mcp", help="运行只读 stdio MCP")
    args = parser.parse_args()
    directory = state_dir()
    if args.command == "mcp":
        from .mcp import main as mcp_main
        mcp_main()
        return
    if args.command == "status":
        print(json.dumps(inventory(directory), ensure_ascii=False, indent=2))
        return
    store = Store(directory)
    if args.command == "revoke":
        print(json.dumps({"revoked": store.revoke(args.device_id)}))
    elif args.command == "pair":
        endpoint = args.endpoint or f"https://{lan_ip()}:8765"
        parsed = urlsplit(endpoint)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.path not in ("", "/") or parsed.query or parsed.fragment:
            parser.error("endpoint 必须是无路径、无账号密码的 HTTPS 地址")
        _, _, pin = ensure_certificate(directory)
        code = store.new_pairing()
        # Deliberate local output for the owner's pairing action; never sent to logs.
        print("watchbridge://pair?" + urlencode({"endpoint": endpoint.rstrip("/"), "pin": pin, "code": code}))
    else:
        server = make_server(directory, args.host, args.port)
        print(f"健康桥已启动：https://{lan_ip()}:{server.server_port}；Ctrl+C 停止。", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()


if __name__ == "__main__":
    main()
