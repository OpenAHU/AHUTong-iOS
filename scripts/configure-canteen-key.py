#!/usr/bin/env python3
"""Configure or verify the client contribution key without logging its value."""
import argparse
import base64
import os
from pathlib import Path
import plistlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("path", type=Path)
parser.add_argument("--require-key", action="store_true")
parser.add_argument("--verify-app", action="store_true")
args = parser.parse_args()
key = os.environ.get("CANTEEN_WRITE_KEY", "")
if key and (key != key.strip() or any(ord(character) < 32 or ord(character) == 127 for character in key)):
    parser.exit(1, "CANTEEN_WRITE_KEY contains invalid header whitespace or control characters\n")
if args.require_key and not key:
    parser.exit(1, "CANTEEN_WRITE_KEY is required for this device build\n")
# Encoding only makes xcconfig parsing safe; it does not conceal a key shipped in an app.
encoded = base64.b64encode(key.encode()).decode()
if encoded and os.environ.get("GITHUB_ACTIONS") == "true":
    print(f"::add-mask::{encoded}")
if args.verify_app:
    info = plistlib.loads((args.path / "Info.plist").read_bytes())
    if not key or info.get("AHUTongCanteenWriteKey") != encoded:
        parser.exit(1, "The built App does not contain the expected contribution configuration\n")
    print("Verified built App contribution configuration")
else:
    args.path.parent.mkdir(parents=True, exist_ok=True)
    args.path.touch(mode=0o600, exist_ok=True)
    args.path.chmod(0o600)
    args.path.write_text(f"AHUTONG_CANTEEN_WRITE_KEY_BASE64 = {encoded}\n")
    print("Canteen contribution configured" if encoded else "Canteen contribution disabled: no client write key")
