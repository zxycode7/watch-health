#!/usr/bin/env python3
"""Generate a local QR image, then open it; never publish the link."""
import os
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
state = Path(os.environ.get("WATCHBRIDGE_HOME", str(Path.home() / "Library/Application Support/WatchBridge")))
result = subprocess.run([sys.executable, str(root / "scripts/run.py"), "pair", *sys.argv[1:]], check=True, capture_output=True)
output = state / "pairing.png"
subprocess.run(["/usr/bin/swift", str(root / "scripts/PairingQR.swift"), str(output)], input=result.stdout, check=True)
output.chmod(0o600)
subprocess.run(["/usr/bin/open", str(output)], check=True)
print("配对二维码已打开。请在 5 分钟内用 iPhone 系统相机扫码；配对成功后可删除此图片。")
