#!/usr/bin/env python3
"""Install this project's own runtime, a user LaunchAgent, and a local Codex MCP entry."""
import argparse
import json
import os
import plistlib
import shutil
import ssl
import subprocess
import sys
import time
import tempfile
import tomllib
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LABEL = "local.watchbridge.sync"


def main():
    if sys.version_info < (3, 11):
        raise SystemExit("需要 Python 3.11 或更新版本。")
    os.umask(0o077)
    parser = argparse.ArgumentParser(description="安装健康桥 Mac 服务与 MCP")
    parser.add_argument("--state-dir", type=Path, default=Path.home() / "Library/Application Support/WatchBridge")
    parser.add_argument("--no-autostart", action="store_true", help="只安装运行文件与 MCP，不注册开机启动")
    args = parser.parse_args()
    state = args.state_dir.expanduser().resolve()
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    runtime = state / "runtime"
    python = shutil.which("python3") or sys.executable
    config_root = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    config_file = config_root / "config.toml"
    original = config_file.read_bytes() if config_file.exists() else b""
    original_config = tomllib.loads(original.decode())
    desired_entry = {"command": python, "args": [str(runtime / "scripts/run.py"), "mcp"],
                     "env": {"WATCHBRIDGE_HOME": str(state)}}
    existing = original_config.get("mcp_servers", {}).get("watchbridge")
    if existing is not None and existing != desired_entry:
        raise SystemExit("已存在不同的 watchbridge MCP，未覆盖。请先检查现有配置。")
    if original:
        backup_dir = state / "backups"
        backup_dir.mkdir(mode=0o700, exist_ok=True)
        backup = backup_dir / ("codex-config-before-" + time.strftime("%Y%m%d-%H%M%S") + ".toml")
        backup.write_bytes(original)
        backup.chmod(0o600)
    if runtime.exists():
        marker = runtime / "INSTALL.json"
        if not marker.exists() or json.loads(marker.read_text()).get("source") != str(ROOT):
            raise SystemExit("已有其他来源的运行目录，未覆盖。")
        sources = list((ROOT / "watchbridge").glob("*.py")) + [ROOT / "scripts" / name for name in ("run.py", "pair.py", "PairingQR.swift")]
        for source in sources:
            installed = runtime / source.relative_to(ROOT)
            if not installed.is_file() or installed.read_bytes() != source.read_bytes():
                raise SystemExit("检测到代码版本差异；请先备份运行目录后再升级。数据库无需删除。")
    else:
        (runtime / "scripts").mkdir(parents=True)
        shutil.copytree(ROOT / "watchbridge", runtime / "watchbridge", ignore=shutil.ignore_patterns("__pycache__"))
        for name in ("run.py", "pair.py", "PairingQR.swift"):
            shutil.copy2(ROOT / "scripts" / name, runtime / "scripts" / name)
        (runtime / "INSTALL.json").write_text(json.dumps({"name": "WatchBridge", "version": "0.1.0", "source": str(ROOT)}, indent=2))
    sys.path.insert(0, str(ROOT))
    from watchbridge.store import Store
    from watchbridge.server import ensure_certificate
    Store(state)
    cert, _, _ = ensure_certificate(state)
    if existing is None:
        quote = lambda value: json.dumps(value, ensure_ascii=False)
        addition = ("\n[mcp_servers.watchbridge]\ncommand = " + quote(python) +
                    "\nargs = " + quote(desired_entry["args"]) +
                    "\n\n[mcp_servers.watchbridge.env]\nWATCHBRIDGE_HOME = " + quote(str(state)) + "\n")
        config_file.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        target = config_file.resolve()
        if (config_file.read_bytes() if config_file.exists() else b"") != original:
            raise SystemExit("Codex 配置刚被其他进程更新，未覆盖；稍后重试即可。")
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".watchbridge-config-", delete=False) as temporary:
            temporary.write(original + addition.encode())
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_path = Path(temporary.name)
        temporary_path.chmod(target.stat().st_mode & 0o777 if target.exists() else 0o600)
        temporary_path.replace(target)
    updated = tomllib.loads(config_file.read_text())
    new_entry = updated.get("mcp_servers", {}).pop("watchbridge", None)
    expected_config = tomllib.loads(original.decode())
    expected_config.get("mcp_servers", {}).pop("watchbridge", None)
    if not updated.get("mcp_servers") and "mcp_servers" not in original_config:
        updated.pop("mcp_servers", None)
    if updated != expected_config or not new_entry:
        raise SystemExit("检测到非预期配置差异，请检查已保留的配置备份。")
    if args.no_autostart:
        print("运行文件及只读 MCP 已安装；尚未启动 HTTPS 服务。")
        return
    agent_dir = Path.home() / "Library/LaunchAgents"
    agent_dir.mkdir(parents=True, exist_ok=True)
    agent = agent_dir / (LABEL + ".plist")
    definition = {"Label": LABEL, "ProgramArguments": [python, str(runtime / "scripts/run.py"), "serve"],
        "WorkingDirectory": str(runtime), "EnvironmentVariables": {"WATCHBRIDGE_HOME": str(state)},
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 10,
        "StandardOutPath": str(state / "service.log"), "StandardErrorPath": str(state / "service-error.log")}
    if agent.exists():
        if plistlib.loads(agent.read_bytes()) != definition:
            raise SystemExit("已有不同的同名 LaunchAgent，未覆盖；MCP 已安装。")
    else:
        agent.write_bytes(plistlib.dumps(definition))
        agent.chmod(0o600)
    loaded = subprocess.run(["/bin/launchctl", "print", f"gui/{os.getuid()}/{LABEL}"], capture_output=True).returncode == 0
    if not loaded:
        subprocess.run(["/bin/launchctl", "bootstrap", f"gui/{os.getuid()}", str(agent)], check=True)
    context = ssl.create_default_context(cafile=str(cert))
    context.check_hostname = False  # Only our exact local self-signed certificate is trusted.
    for attempt in range(20):
        try:
            with urllib.request.urlopen("https://127.0.0.1:8765/healthz", context=context, timeout=2) as response:
                if json.load(response).get("ok"):
                    print("健康桥已安装：HTTPS 服务在线，登录后自动启动，只读 MCP 已注册。")
                    print("数据与私钥保存在：" + str(state))
                    return
        except OSError:
            time.sleep(0.25)
    raise SystemExit("服务未通过健康检查。请查看本地 service-error.log；未声称启动成功。")


if __name__ == "__main__":
    main()
