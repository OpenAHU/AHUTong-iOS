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
    parser.add_argument("--require-release", action="store_true", help="Reject coverage-instrumented or unstripped distribution executables")
    args = parser.parse_args()
    app = args.app.resolve()
    ipa = args.ipa.resolve()
    if not app.is_dir() or app.suffix != ".app":
        parser.error("Input must be a built iphoneos .app bundle")
    if ipa.exists():
        parser.error("Output IPA already exists; choose a new path")
    ipa.parent.mkdir(parents=True, exist_ok=True)
    verifier = Path(__file__).with_name("verify-widget-bundle.py")
    release_check = ["--require-release"] if args.require_release else []
    subprocess.run([sys.executable, str(verifier), str(app), *release_check], check=True)
    with tempfile.TemporaryDirectory(prefix="ahutong-resignable-") as temporary:
        root = Path(temporary)
        payload = root / "Payload"
        copied = payload / app.name
        shutil.copytree(app, copied, symlinks=True)
        widgets = list((copied / "PlugIns").glob("*.appex"))
        # Xcode can leave linker-signed stubs in static SDK resource frameworks.
        # Seal all nested code, including its resources, before its containing bundle.
        embedded = [path for path in copied.rglob("*")
                    if (path.suffix == ".framework" and path.is_dir())
                    or (path.suffix == ".dylib" and path.is_file())]
        for code in sorted(embedded, key=lambda path: len(path.parts), reverse=True):
            subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(code)], check=True)
        # Only App/Widget receive sharing declarations; never use --deep.
        for bundle in [*widgets, copied]:
            info = plistlib.loads((bundle / "Info.plist").read_bytes())
            declarations = root / "sharing.entitlements"
            declarations.write_bytes(plistlib.dumps({
                "com.apple.security.application-groups": [info["AHUTongAppGroupIdentifier"]]
            }))
            subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none",
                            "--generate-entitlement-der", "--entitlements", str(declarations), str(bundle)], check=True)
        subprocess.run([sys.executable, str(verifier), str(copied), "--require-entitlements", *release_check], check=True)
        subprocess.run(["ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent", str(payload), str(ipa)], check=True)
        subprocess.run([sys.executable, str(verifier), str(ipa), "--require-entitlements", *release_check], check=True)
    print(f"Created re-signable IPA: {ipa}")


if __name__ == "__main__":
    main()
