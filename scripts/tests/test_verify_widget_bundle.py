import importlib.util
import json
import plistlib
from pathlib import Path
import tempfile
import unittest

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
