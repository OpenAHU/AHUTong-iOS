import importlib.util
import json
import plistlib
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest
import zipfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("verify_widget", Path(__file__).parents[1] / "verify-widget-bundle.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class WidgetBundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "AHUTong.app"
        self.widget = self.app / "PlugIns/AHUTongWidget.appex"
        for bundle, identifier in ((self.app, "com.example.app"), (self.widget, "com.example.app.widget")):
            bundle.mkdir(parents=True)
            info = {"CFBundleIdentifier": identifier, "CFBundleShortVersionString": "1.0.2", "CFBundleVersion": "3", "CFBundleExecutable": "binary", "AHUTongAppGroupIdentifier": "group.example.shared"}
            if bundle == self.widget:
                info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}
            (bundle / "Info.plist").write_bytes(plistlib.dumps(info))
            (bundle / "binary").write_text("synthetic fixture")
            (bundle / "Metadata.appintents").mkdir()
        self.write_metadata(self.app, {"actions": {"OpenPaymentCodeIntent": {}, "QueryScheduleIntent": {}}})
        self.widget_metadata = {"actions": {"ScheduleWidgetConfiguration": {"systemProtocols": ["com.apple.link.systemProtocol.WidgetConfiguration"]}}, "enums": [{"identifier": "ScheduleWidgetAppearance", "cases": [{"identifier": name} for name in ("system", "light", "dark")]}]}
        self.write_metadata(self.widget, self.widget_metadata)

    def write_metadata(self, bundle, value):
        (bundle / "Metadata.appintents/extract.actionsdata").write_text(json.dumps(value))

    def test_complete_unsigned_structure_passes(self):
        verifier.verify(self.app, False)

    def test_appledouble_metadata_is_not_treated_as_an_extension(self):
        (self.widget.parent / "._AHUTongWidget.appex").write_bytes(b"AppleDouble metadata")
        verifier.verify(self.app, False)

    def test_ipa_with_appledouble_app_metadata_still_verifies(self):
        artifact = self.app.parent / "test.ipa"
        with zipfile.ZipFile(artifact, "w") as archive:
            for path in self.app.rglob("*"):
                if path.is_file():
                    archive.write(path, "Payload/" + str(path.relative_to(self.app.parent)))
            archive.writestr("Payload/._AHUTong.app", b"AppleDouble metadata")
        result = subprocess.run([sys.executable, verifier.__file__, str(artifact)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_resignable_package_keeps_both_group_declarations(self):
        with patch.object(verifier, "signed_entitlements", return_value={"com.apple.security.application-groups": ["group.example.shared"]}):
            verifier.verify(self.app, False, True)

    def test_missing_widget_group_declaration_fails_resignable_package(self):
        with patch.object(verifier, "signed_entitlements", side_effect=[{"com.apple.security.application-groups": ["group.example.shared"]}, {}]):
            with self.assertRaisesRegex(ValueError, "both preserve"):
                verifier.verify(self.app, False, True)

    def test_stripped_shortcut_actions_fail(self):
        self.write_metadata(self.app, {"actions": {}})
        with self.assertRaisesRegex(ValueError, "Siri/Shortcuts"):
            verifier.verify(self.app, False)

    def test_stripped_widget_configuration_fails(self):
        self.widget_metadata["actions"] = {}
        self.write_metadata(self.widget, self.widget_metadata)
        with self.assertRaisesRegex(ValueError, "configuration intent"):
            verifier.verify(self.app, False)

    def test_missing_dark_option_fails(self):
        self.widget_metadata["enums"][0]["cases"].pop()
        self.write_metadata(self.widget, self.widget_metadata)
        with self.assertRaisesRegex(ValueError, "appearance options"):
            verifier.verify(self.app, False)


class SignedWidgetGroupTests(unittest.TestCase):
    configured = "group.example.shared"
    renamed = "group.example.resigned.shared"

    def entitlements(self, groups, team="TESTTEAM"):
        return {"com.apple.developer.team-identifier": team, "com.apple.security.application-groups": groups}

    def test_configured_group_passes_with_matching_signatures_and_profiles(self):
        value = self.entitlements([self.configured])
        self.assertEqual(verifier.verify_shared_group(self.configured, value, value, value, value), self.configured)

    def test_unique_common_renamed_group_passes(self):
        value = self.entitlements([self.renamed])
        self.assertEqual(verifier.verify_shared_group(self.configured, value, value, value, value), self.renamed)

    def test_profile_permission_without_widget_signature_permission_fails(self):
        value = self.entitlements([self.renamed])
        with self.assertRaisesRegex(ValueError, "both authorize"):
            verifier.verify_shared_group(self.configured, value, self.entitlements([]), value, value)

    def test_configured_group_only_in_host_signature_cannot_fall_back_to_other_group(self):
        both = self.entitlements([self.configured, self.renamed])
        with self.assertRaisesRegex(ValueError, "both authorize"):
            verifier.verify_shared_group(self.configured, both, self.entitlements([self.renamed]), both, both)

    def test_multiple_renamed_groups_fail(self):
        value = self.entitlements([self.renamed, "group.example.another"])
        with self.assertRaisesRegex(ValueError, "exactly one"):
            verifier.verify_shared_group(self.configured, value, value, value, value)

    def test_different_signing_teams_fail(self):
        value = self.entitlements([self.configured])
        with self.assertRaisesRegex(ValueError, "same nonempty"):
            verifier.verify_shared_group(self.configured, value, self.entitlements([self.configured], "OTHER"), value, value)

    def test_profile_team_mismatch_fails(self):
        value = self.entitlements([self.configured])
        with self.assertRaisesRegex(ValueError, "profiles must agree"):
            verifier.verify_shared_group(self.configured, value, value, value, self.entitlements([self.configured], "OTHER"))

    def test_missing_profiles_cannot_enable_a_renamed_group(self):
        value = self.entitlements([self.renamed])
        with self.assertRaisesRegex(ValueError, "both authorize"):
            verifier.verify_shared_group(self.configured, value, value, None, None)
