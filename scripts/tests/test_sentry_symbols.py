import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "upload-sentry-symbols.sh"


class SentrySymbolUploadTests(unittest.TestCase):
    def test_missing_token_preserves_manual_upload_path(self):
        env = {key: value for key, value in os.environ.items() if key != "SENTRY_AUTH_TOKEN"}
        result = subprocess.run(["bash", str(SCRIPT), "/unused"], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("SENTRY_AUTH_TOKEN is not configured", result.stdout)

    def test_only_symbols_are_sent_and_token_is_not_a_cli_argument(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cli = root / "sentry-cli"
            cli.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$ARGUMENTS_FILE"\n')
            cli.chmod(0o700)
            arguments = root / "arguments.txt"
            symbols = root / "symbols"
            symbols.mkdir()
            dsym = symbols / "AHUTong.app.dSYM"
            dsym.mkdir()
            env = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                   "SENTRY_AUTH_TOKEN": "fixture-private-token", "ARGUMENTS_FILE": str(arguments)}
            result = subprocess.run(["bash", str(SCRIPT), str(symbols)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            args = arguments.read_text().splitlines()
            self.assertEqual(args, ["debug-files", "upload", "--org", "ratatoskr", "--project", "ahutong-ios",
                                    "--wait", str(dsym)])
            self.assertNotIn("fixture-private-token", arguments.read_text() + result.stdout + result.stderr)
            self.assertNotIn("--include-sources", args)

    def test_configured_upload_fails_if_symbols_are_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ, "SENTRY_AUTH_TOKEN": "fixture-private-token"}
            result = subprocess.run(["bash", str(SCRIPT), str(Path(directory) / "missing")],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn("fixture-private-token", result.stdout + result.stderr)
