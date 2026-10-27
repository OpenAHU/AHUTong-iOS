import base64
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "configure-canteen-key.py"


class CanteenKeyConfigTests(unittest.TestCase):
    def configure(self, directory, key, ci=False):
        path = Path(directory) / "Canteen.xcconfig.local"
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(path)],
            env={**os.environ, "CANTEEN_WRITE_KEY": key, "GITHUB_ACTIONS": "true" if ci else "false"},
            check=True, capture_output=True, text=True,
        )
        return path, result.stdout

    def test_local_file_is_private_and_stdout_does_not_reveal_key(self):
        key = "fixture:key /+special=characters"
        encoded = base64.b64encode(key.encode()).decode()
        with tempfile.TemporaryDirectory() as directory:
            path, output = self.configure(directory, key)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(path.read_text(), f"AHUTONG_CANTEEN_WRITE_KEY_BASE64 = {encoded}\n")
            self.assertNotIn(key, output)
            self.assertNotIn(encoded, output)

    def test_ci_masks_transformed_key_before_reporting_status(self):
        key = "ci-fixture-key"
        encoded = base64.b64encode(key.encode()).decode()
        with tempfile.TemporaryDirectory() as directory:
            _, output = self.configure(directory, key, ci=True)
            self.assertEqual(output.splitlines(), [f"::add-mask::{encoded}", "Canteen contribution configured"])
            self.assertNotIn(key, output)

    def test_missing_key_disables_contribution_without_mask_command(self):
        with tempfile.TemporaryDirectory() as directory:
            path, output = self.configure(directory, "", ci=True)
            self.assertEqual(path.read_text(), "AHUTONG_CANTEEN_WRITE_KEY_BASE64 = \n")
            self.assertEqual(output, "Canteen contribution disabled: no client write key\n")

    def test_device_build_requires_key_before_creating_config(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Canteen.xcconfig.local"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(path), "--require-key"],
                env={**os.environ, "CANTEEN_WRITE_KEY": ""}, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(path.exists())
            self.assertIn("required for this device build", result.stderr)

    def test_header_control_character_is_rejected_without_revealing_key(self):
        key = "fixture\ninjected-header"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Canteen.xcconfig.local"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(path)],
                env={**os.environ, "CANTEEN_WRITE_KEY": key}, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(path.exists())
            self.assertNotIn(key, result.stdout + result.stderr)

    def test_verifies_built_key_without_revealing_its_value(self):
        key = "built-app-fixture"
        encoded = base64.b64encode(key.encode()).decode()
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / "Info.plist").write_bytes(plistlib.dumps({"AHUTongCanteenWriteKey": encoded}))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(app), "--verify-app", "--require-key"],
                env={**os.environ, "CANTEEN_WRITE_KEY": key, "GITHUB_ACTIONS": "false"},
                check=True, capture_output=True, text=True,
            )
            self.assertIn("Verified built App", result.stdout)
            self.assertNotIn(key, result.stdout)
            self.assertNotIn(encoded, result.stdout)

    def test_verification_rejects_mismatched_built_key(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / "Info.plist").write_bytes(plistlib.dumps({"AHUTongCanteenWriteKey": ""}))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), str(app), "--verify-app", "--require-key"],
                env={**os.environ, "CANTEEN_WRITE_KEY": "expected-fixture", "GITHUB_ACTIONS": "false"},
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not contain the expected", result.stderr)
            self.assertNotIn("expected-fixture", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
