#!/usr/bin/env python3
"""Package a device app with ad-hoc entitlement declarations for re-signers.

No developer identity, profile, or Team ID is generated or used. The resulting
IPA cannot be installed until a real signing tool authorizes and signs it.
"""

import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    ipa = args.ipa.resolve()
    if not app.is_dir() or app.suffix != ".app":
        parser.error("Input must be a built iphoneos .app bundle")
    if ipa.exists():
        parser.error("Output IPA already exists; choose a new path")
    ipa.parent.mkdir(parents=True, exist_ok=True)
    verifier = Path(__file__).with_name("verify-widget-bundle.py")
    subprocess.run([sys.executable, str(verifier), str(app)], check=True)
    with tempfile.TemporaryDirectory(prefix="ahutong-resignable-") as temporary:
        root = Path(temporary)
        payload = root / "Payload"
        copied = payload / app.name
        shutil.copytree(app, copied, symlinks=True)
        widgets = list((copied / "PlugIns").glob("*.appex"))
        # Sign embedded bundles first; never use --deep to invent capabilities.
        for bundle in [*widgets, copied]:
            info = plistlib.loads((bundle / "Info.plist").read_bytes())
            declarations = root / "sharing.entitlements"
            declarations.write_bytes(plistlib.dumps({
                "com.apple.security.application-groups": [info["AHUTongAppGroupIdentifier"]]
            }))
            subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none",
                            "--generate-entitlement-der", "--entitlements", str(declarations), str(bundle)], check=True)
        subprocess.run([sys.executable, str(verifier), str(copied), "--require-entitlements"], check=True)
        subprocess.run(["ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", str(payload), str(ipa)], check=True)
        subprocess.run([sys.executable, str(verifier), str(ipa), "--require-entitlements"], check=True)
    print(f"Created re-signable IPA: {ipa}")


if __name__ == "__main__":
    main()
