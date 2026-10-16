import os
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path


class InstallerTests(unittest.TestCase):
    def test_preserves_exact_existing_settings_and_can_resume(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            config = base / "codex"
            config.mkdir()
            original = b'# Keep this comment.\n[mcp_servers.existing]\ncommand = "/usr/bin/true"\nargs = []\nenabled = true\n'
            file = config / "config.toml"
            file.write_bytes(original)
            state = base / "state"
            root = Path(__file__).resolve().parents[1]
            command = [sys.executable, str(root / "scripts/install_mac.py"), "--state-dir", str(state), "--no-autostart"]
            environment = dict(os.environ, CODEX_HOME=str(config))
            for _ in range(2):
                result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(file.read_bytes().startswith(original))
            after = tomllib.loads(file.read_text())
            self.assertEqual(after["mcp_servers"]["existing"], tomllib.loads(original.decode())["mcp_servers"]["existing"])
            self.assertEqual(after["mcp_servers"]["watchbridge"]["env"]["WATCHBRIDGE_HOME"], str(state.resolve()))
            installed = state / "runtime/watchbridge/store.py"
            installed.write_text("# a user change must be preserved\n")
            result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(installed.read_text(), "# a user change must be preserved\n")


if __name__ == "__main__":
    unittest.main()
