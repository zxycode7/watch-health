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

    def test_upgrade_backs_up_runtime_and_preserves_data_and_config(self):
        import sqlite3
        with tempfile.TemporaryDirectory() as temporary:
            base=Path(temporary); config=base/"codex"; config.mkdir(); state=base/"state"
            command=[sys.executable,str(Path(__file__).resolve().parents[1]/"scripts/install_mac.py"),"--state-dir",str(state),"--no-autostart"]
            env=dict(os.environ,CODEX_HOME=str(config))
            subprocess.run(command,env=env,capture_output=True,check=True,timeout=20)
            before_config=(config/"config.toml").read_bytes()
            with sqlite3.connect(state/"health.sqlite3") as db: db.execute("CREATE TABLE owner_note (message TEXT)"); db.execute("INSERT INTO owner_note VALUES ('keep this data')")
            installed=state/"runtime/watchbridge/store.py"; installed.write_text("# previous runtime\n")
            result=subprocess.run(command+["--upgrade"],env=env,capture_output=True,text=True,timeout=20)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertEqual((config/"config.toml").read_bytes(),before_config)
            self.assertIn("class Store:",installed.read_text())
            backups=list((state/"backups").glob("before-upgrade-*"))
            self.assertEqual(len(backups),1)
            self.assertEqual((backups[0]/"runtime/watchbridge/store.py").read_text(),"# previous runtime\n")
            for database in [state/"health.sqlite3",backups[0]/"health.sqlite3"]:
                with sqlite3.connect(database) as db:self.assertEqual(db.execute("SELECT message FROM owner_note").fetchone()[0],"keep this data")


if __name__ == "__main__":
    unittest.main()
