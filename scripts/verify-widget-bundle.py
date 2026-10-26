#!/usr/bin/env python3
"""Check an app or IPA before and after re-signing, without launching it."""

import argparse
import json
import plistlib
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path


def read_plist(path):
    with path.open("rb") as source:
        return plistlib.load(source)


def verify_release_binary(path):
    data = path.read_bytes()
    if len(data) < 32 or struct.unpack_from("<II", data) != (0xFEEDFACF, 0x100000C):
        raise ValueError("Release bundle must contain a thin arm64 device executable")
    commands, command_bytes = struct.unpack_from("<II", data, 16)
    position, limit = 32, 32 + command_bytes
    if limit > len(data):
        raise ValueError("Invalid Mach-O load commands")
    platform, local_symbols = None, None
    for _ in range(commands):
        if position + 8 > limit:
            raise ValueError("Invalid Mach-O load commands")
        command, size = struct.unpack_from("<II", data, position)
        if size < 8 or position + size > limit:
            raise ValueError("Invalid Mach-O load commands")
        if command == 0x32 and size >= 24:  # LC_BUILD_VERSION
            platform = struct.unpack_from("<I", data, position + 8)[0]
        elif command == 0xB and size >= 80:  # LC_DYSYMTAB
            local_symbols = struct.unpack_from("<I", data, position + 12)[0]
        elif command == 0x19 and size >= 72:  # LC_SEGMENT_64
            count = struct.unpack_from("<I", data, position + 64)[0]
            if 72 + count * 80 > size:
                raise ValueError("Invalid Mach-O sections")
            for index in range(count):
                section, segment = struct.unpack_from("<16s16s", data, position + 72 + index * 80)
                if b"llvm" in section or segment.rstrip(b"\0") in (b"__LLVM_COV", b"__DWARF"):
                    raise ValueError("Release executable contains coverage or embedded debug data")
        position += size
    if platform != 2:  # PLATFORM_IOS, not the arm64 simulator platform
        raise ValueError("Release bundle must contain an iPhoneOS device executable")
    # A fully stripped Xcode executable retains at most its linker sentinel.
    if local_symbols is None or local_symbols > 1:
        raise ValueError("Release executable has not been stripped of local symbols")


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


def verify_embedded_code(app):
    # Verifying the outer App (even with --deep) can miss a linker-signed
    # resource framework. Check each nested framework/library explicitly.
    embedded = [path for path in app.rglob("*")
                if (path.suffix == ".framework" and path.is_dir())
                or (path.suffix == ".dylib" and path.is_file())]
    for code in sorted(embedded):
        try:
            subprocess.run(["codesign", "--verify", "--strict", str(code)],
                           check=True, capture_output=True)
        except subprocess.CalledProcessError as error:
            raise ValueError(f"Embedded code signature invalid: {code.relative_to(app)}") from error


def profile_entitlements(bundle):
    profile = bundle / "embedded.mobileprovision"
    if not profile.exists():
        return None
    result = subprocess.run(
        ["security", "cms", "-D", "-i", str(profile)],
        check=True, capture_output=True,
    )
    return plistlib.loads(result.stdout).get("Entitlements", {})


def verify_shared_group(configured, app_entitlements, widget_entitlements, app_profile, widget_profile):
    team_key = "com.apple.developer.team-identifier"
    group_key = "com.apple.security.application-groups"
    team = app_entitlements.get(team_key)
    if not team or team != widget_entitlements.get(team_key):
        raise ValueError("App and Widget must have the same nonempty signing Team ID")
    group = configured
    if app_profile is not None and widget_profile is not None:
        if any(profile.get(team_key) != team for profile in (app_profile, widget_profile)):
            raise ValueError("Signing Team ID and provisioning profiles must agree")
        common = set(app_profile.get(group_key, [])) & set(widget_profile.get(group_key, []))
        common = {value for value in common if value.startswith("group.") and "*" not in value and "$(" not in value and not any(character.isspace() for character in value)}
        if configured in common and configured in app_entitlements.get(group_key, []):
            group = configured
        elif len(common) == 1:
            group = next(iter(common))
        else:
            raise ValueError("Profiles must allow the configured group or exactly one common App Group")
    for entitlements, profile in ((app_entitlements, app_profile), (widget_entitlements, widget_profile)):
        if group not in entitlements.get(group_key, []):
            raise ValueError("Signed App/Widget do not both authorize the resolved App Group")
        if profile is not None and group not in profile.get(group_key, []):
            raise ValueError("Provisioning profile does not allow the resolved App Group")
    return group


def verify(app, require_signature, require_entitlements=False, require_release=False):
    app_info = read_plist(app / "Info.plist")
    candidates = []
    for bundle in (app / "PlugIns").glob("*.appex"):
        if not bundle.is_dir():
            continue
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
    for bundle, info in ((app, app_info), (widget, widget_info)):
        executable = bundle / info["CFBundleExecutable"]
        if not executable.is_file():
            raise ValueError("A bundle is missing its executable")
        if require_release:
            verify_release_binary(executable)
    if require_signature:
        verify_shared_group(group, signed_entitlements(app), signed_entitlements(widget),
                            profile_entitlements(app), profile_entitlements(widget))
    elif require_entitlements:
        for bundle in (app, widget):
            if group not in signed_entitlements(bundle).get("com.apple.security.application-groups", []):
                raise ValueError("Re-signable App/Widget must both preserve the configured App Group declaration")
    if require_signature or require_entitlements:
        verify_embedded_code(app)
    print("PASS: embedded Widget, bundle IDs, versions, executables, shared group and App Intents metadata")
    if require_release:
        print("PASS: arm64 iPhoneOS Release executables are stripped and contain no coverage/debug sections")
    if require_signature:
        print("PASS: App/Widget and embedded code signatures; shared-group entitlements (profiles checked when present)")
    elif require_entitlements:
        print("PASS: App/Widget and embedded code signatures; App Group declarations preserved; developer re-signing is still required")
    else:
        print("Structure checks only; repeat with --require-signature after re-signing")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path, help=".app bundle or .ipa file")
    parser.add_argument("--require-signature", action="store_true")
    parser.add_argument("--require-entitlements", action="store_true", help="Check re-signable ad-hoc App Group declarations, without requiring a developer team")
    parser.add_argument("--require-release", action="store_true", help="Require stripped arm64 iPhoneOS executables without test coverage")
    args = parser.parse_args()
    try:
        if args.artifact.is_dir():
            verify(args.artifact, args.require_signature, args.require_entitlements, args.require_release)
        else:
            with tempfile.TemporaryDirectory(prefix="ahutong-widget-check-") as temporary:
                root = Path(temporary).resolve()
                with zipfile.ZipFile(args.artifact) as archive:
                    for member in archive.infolist():
                        if not (root / member.filename).resolve().is_relative_to(root):
                            raise ValueError("IPA contains an unsafe archive path")
                    archive.extractall(root)
                apps = [bundle for bundle in (root / "Payload").glob("*.app") if bundle.is_dir()]
                if len(apps) != 1:
                    raise ValueError("Expected exactly one application in IPA Payload")
                verify(apps[0], args.require_signature, args.require_entitlements, args.require_release)
    except (OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        # Never dump profiles or codesign output, which can contain device IDs.
        parser.exit(1, f"FAIL: {error if not isinstance(error, subprocess.CalledProcessError) else 'signature or profile validation failed'}\n")


if __name__ == "__main__":
    main()
