#!/usr/bin/env python3
"""Check an app or IPA before and after re-signing, without launching it."""

import argparse
import json
import plistlib
import subprocess
import tempfile
import zipfile
from pathlib import Path


def read_plist(path):
    with path.open("rb") as source:
        return plistlib.load(source)


def signed_entitlements(bundle):
    subprocess.run(
        ["codesign", "--verify", "--strict", str(bundle)],
        check=True, capture_output=True,
    )
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(bundle)],
        check=True, capture_output=True,
    )
    return plistlib.loads(result.stdout)


def verify(app, require_signature):
    app_info = read_plist(app / "Info.plist")
    candidates = []
    for bundle in (app / "PlugIns").glob("*.appex"):
        info = read_plist(bundle / "Info.plist")
        if info.get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension":
            candidates.append((bundle, info))
    if len(candidates) != 1:
        raise ValueError("Expected one embedded Widget extension; re-signing may have removed it")
    widget, widget_info = candidates[0]
    app_id = app_info["CFBundleIdentifier"]
    widget_id = widget_info["CFBundleIdentifier"]
    if not widget_id.startswith(app_id + "."):
        raise ValueError("Widget bundle ID must have the containing app's bundle ID as its prefix")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if not app_info.get(key) or app_info.get(key) != widget_info.get(key):
            raise ValueError("App and Widget versions must match")
    group = app_info.get("AHUTongAppGroupIdentifier")
    if not group or "$(" in group or group != widget_info.get("AHUTongAppGroupIdentifier"):
        raise ValueError("App and Widget must declare the same resolved App Group identifier")
    app_actions = json.loads((app / "Metadata.appintents/extract.actionsdata").read_text()).get("actions", {})
    if not {"OpenPaymentCodeIntent", "QueryScheduleIntent"}.issubset(app_actions):
        raise ValueError("App is missing its Siri/Shortcuts action metadata")
    widget_metadata = json.loads((widget / "Metadata.appintents/extract.actionsdata").read_text())
    configuration = widget_metadata.get("actions", {}).get("ScheduleWidgetConfiguration", {})
    if "com.apple.link.systemProtocol.WidgetConfiguration" not in configuration.get("systemProtocols", []):
        raise ValueError("Widget is missing its editable configuration intent")
    appearance = next((value for value in widget_metadata.get("enums", []) if value.get("identifier") == "ScheduleWidgetAppearance"), {})
    if {case.get("identifier") for case in appearance.get("cases", [])} != {"system", "light", "dark"}:
        raise ValueError("Widget is missing its system/light/dark appearance options")
    signing_teams = set()
    for bundle, info in ((app, app_info), (widget, widget_info)):
        executable = bundle / info["CFBundleExecutable"]
        if not executable.is_file():
            raise ValueError("A bundle is missing its executable")
        if require_signature:
            entitlements = signed_entitlements(bundle)
            team = entitlements.get("com.apple.developer.team-identifier")
            if not team:
                raise ValueError("A signed App/Widget has no Team ID; App Intents may not register")
            signing_teams.add(team)
            if group not in entitlements.get("com.apple.security.application-groups", []):
                raise ValueError("Signed App/Widget do not both retain the configured App Group")
            profile = bundle / "embedded.mobileprovision"
            if profile.exists():
                result = subprocess.run(
                    ["security", "cms", "-D", "-i", str(profile)],
                    check=True, capture_output=True,
                )
                allowed = plistlib.loads(result.stdout).get("Entitlements", {}).get("com.apple.security.application-groups", [])
                if group not in allowed:
                    raise ValueError("Provisioning profile does not allow the configured App Group")
    if require_signature and len(signing_teams) != 1:
        raise ValueError("App and Widget must be signed by the same team")
    print("PASS: embedded Widget, bundle IDs, versions, executables, shared group and App Intents metadata")
    if require_signature:
        print("PASS: signatures and shared-group entitlements (profiles checked when present)")
    else:
        print("Structure checks only; repeat with --require-signature after re-signing")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path, help=".app bundle or .ipa file")
    parser.add_argument("--require-signature", action="store_true")
    args = parser.parse_args()
    try:
        if args.artifact.is_dir():
            verify(args.artifact, args.require_signature)
        else:
            with tempfile.TemporaryDirectory(prefix="ahutong-widget-check-") as temporary:
                root = Path(temporary).resolve()
                with zipfile.ZipFile(args.artifact) as archive:
                    for member in archive.infolist():
                        if not (root / member.filename).resolve().is_relative_to(root):
                            raise ValueError("IPA contains an unsafe archive path")
                    archive.extractall(root)
                apps = list((root / "Payload").glob("*.app"))
                if len(apps) != 1:
                    raise ValueError("Expected exactly one application in IPA Payload")
                verify(apps[0], args.require_signature)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        # Never dump profiles or codesign output, which can contain device IDs.
        parser.exit(1, f"FAIL: {error if not isinstance(error, subprocess.CalledProcessError) else 'signature or profile validation failed'}\n")


if __name__ == "__main__":
    main()
