"""Exercise packaging with real device Mach-O signatures, without installing."""

import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPTS = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location("package_verifier", SCRIPTS / "verify-widget-bundle.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun") and shutil.which("codesign"),
                     "Real signing fixtures require macOS and Xcode")
class ResignableIPATests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binaries = tempfile.TemporaryDirectory(prefix="ahutong-signing-fixtures-")
        cls.addClassCleanup(cls.binaries.cleanup)
        root = Path(cls.binaries.name)
        result = subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"],
                                capture_output=True, text=True)
        if result.returncode:
            raise unittest.SkipTest("Real signing fixtures require a selected Xcode with the iPhoneOS SDK")
        sdk = result.stdout.strip()
        source = root / "fixture.c"
        source.write_text("int main(void) { return 0; }\n")
        cls.executable = root / "app"
        cls.stub = root / "stub"
        cls.sdk = sdk
        subprocess.run(["xcrun", "clang", "-target", "arm64-apple-ios17.0", "-isysroot", sdk,
                        str(source), "-o", str(cls.executable)], check=True, capture_output=True)
        # Match Xcode's resource-only static-framework stub, including iOS 100.
        source.write_text("void fixture(void) {}\n")
        subprocess.run(["xcrun", "clang", "-target", "arm64-apple-ios100.0", "-isysroot", sdk,
                        "-dynamiclib", "-Wl,-install_name,@rpath/Fixture.framework/Fixture",
                        str(source), "-o", str(cls.stub)], check=True, capture_output=True)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ahutong-package-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "AHUTong.app"
        self.widget = self.app / "PlugIns/AHUTongWidget.appex"
        for bundle, identifier, kind in ((self.app, "com.example.app", "APPL"),
                                          (self.widget, "com.example.app.widget", "XPC!")):
            bundle.mkdir(parents=True)
            info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": "binary",
                    "CFBundlePackageType": kind, "CFBundleShortVersionString": "1.0.4",
                    "CFBundleVersion": "6", "MinimumOSVersion": "17.0",
                    "AHUTongAppGroupIdentifier": "group.example.shared"}
            if bundle == self.widget:
                info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}
            (bundle / "Info.plist").write_bytes(plistlib.dumps(info))
            shutil.copy2(self.executable, bundle / "binary")
            (bundle / "Metadata.appintents").mkdir()
        (self.app / "Metadata.appintents/extract.actionsdata").write_text(json.dumps({
            "actions": {"OpenPaymentCodeIntent": {}, "QueryScheduleIntent": {}}
        }))
        (self.widget / "Metadata.appintents/extract.actionsdata").write_text(json.dumps({
            "actions": {"ScheduleWidgetConfiguration": {"systemProtocols": [
                "com.apple.link.systemProtocol.WidgetConfiguration"]}},
            "enums": [{"identifier": "ScheduleWidgetAppearance", "cases": [
                {"identifier": name} for name in ("system", "light", "dark")]}]
        }))
        self.framework = self.app / "Frameworks/Fixture.framework"
        self.framework.mkdir(parents=True)
        (self.framework / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.example.fixture", "CFBundleExecutable": "Fixture",
            "CFBundlePackageType": "FMWK", "CFBundleVersion": "1", "MinimumOSVersion": "100.0"
        }))
        shutil.copy2(self.stub, self.framework / "Fixture")
        self.privacy = self.framework / "PrivacyInfo.xcprivacy"
        self.privacy.write_bytes(plistlib.dumps({"NSPrivacyTracking": False}))
        self.declarations = self.root / "sharing.entitlements"
        self.declarations.write_bytes(plistlib.dumps({
            "com.apple.security.application-groups": ["group.example.shared"]
        }))

    def sign_outer_bundles(self):
        for bundle in (self.widget, self.app):
            subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none",
                            "--generate-entitlement-der", "--entitlements", str(self.declarations),
                            str(bundle)], check=True, capture_output=True)

    def compile_fixture(self, name, source, extra=(), simulator=False):
        path = self.root / (name + ".c")
        path.write_text(source)
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip() if simulator else self.sdk
        output = self.root / name
        target = "arm64-apple-ios17.0-simulator" if simulator else "arm64-apple-ios17.0"
        subprocess.run(["xcrun", "clang", "-target", target, "-isysroot", sdk,
                        *extra, str(path), "-o", str(output)], check=True, capture_output=True)
        return output

    def test_distribution_rejects_coverage_in_device_executable(self):
        binary = self.compile_fixture("coverage", "int main(void) { return 0; }",
                                      ["-fprofile-instr-generate", "-fcoverage-mapping"])
        with self.assertRaisesRegex(ValueError, "coverage"):
            verifier.verify_release_binary(binary)

    def test_distribution_accepts_stripped_executable_but_rejects_local_symbols(self):
        binary = self.compile_fixture("locals", "static volatile int first, second; int main(void) { return first + second; }")
        with self.assertRaisesRegex(ValueError, "local symbols"):
            verifier.verify_release_binary(binary)
        stripped = self.root / "stripped"
        subprocess.run(["xcrun", "strip", "-u", "-r", "-o", str(stripped), str(binary)],
                       check=True, capture_output=True)
        verifier.verify_release_binary(stripped)

    def test_distribution_rejects_arm64_simulator_executable(self):
        binary = self.compile_fixture("simulator", "int main(void) { return 0; }", simulator=True)
        with self.assertRaisesRegex(ValueError, "iPhoneOS device"):
            verifier.verify_release_binary(binary)

    def test_linker_signed_resource_framework_is_rejected_despite_valid_outer_signatures(self):
        self.sign_outer_bundles()
        # This was the previous gate: outer signatures and groups both pass.
        self.assertIn("group.example.shared", verifier.signed_entitlements(self.app)[
            "com.apple.security.application-groups"])
        verifier.signed_entitlements(self.widget)
        with self.assertRaisesRegex(ValueError, "Frameworks/Fixture.framework"):
            verifier.verify(self.app, False, True)

    def test_package_seals_nested_code_and_preserves_privacy_and_group_declarations(self):
        library = self.widget / "Frameworks/libFixture.dylib"
        library.parent.mkdir()
        shutil.copy2(self.stub, library)
        subprocess.run(["codesign", "--remove-signature", str(library)], check=True, capture_output=True)
        output = self.root / "corrected.ipa"
        result = subprocess.run([sys.executable, str(SCRIPTS / "package-resignable-ipa.py"),
                                 str(self.app), str(output)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(archive.read("Payload/AHUTong.app/Frameworks/Fixture.framework/PrivacyInfo.xcprivacy"),
                             self.privacy.read_bytes())
            self.assertTrue(archive.getinfo("Payload/AHUTong.app/binary").external_attr >> 16 & 0o111)
            archive.extractall(self.root / "unpacked")
        packaged = self.root / "unpacked/Payload/AHUTong.app"
        verifier.verify(packaged, False, True)
        framework = packaged / "Frameworks/Fixture.framework"
        entitlements = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(framework)],
                                     check=True, capture_output=True).stdout
        self.assertNotIn(b"com.apple.security.application-groups", entitlements)
        self.assertFalse(list(packaged.rglob("embedded.mobileprovision")))
        self.assertFalse((self.framework / "_CodeSignature").exists(), "Input must remain untouched")

    def test_tampered_framework_resource_is_rejected(self):
        subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none", str(self.framework)],
                       check=True, capture_output=True)
        self.sign_outer_bundles()
        verifier.verify(self.app, False, True)
        # Reseal the outer App to isolate the broken inner resource seal.
        self.privacy.write_bytes(plistlib.dumps({"NSPrivacyTracking": True}))
        self.sign_outer_bundles()
        with self.assertRaisesRegex(ValueError, "Frameworks/Fixture.framework"):
            verifier.verify(self.app, False, True)
