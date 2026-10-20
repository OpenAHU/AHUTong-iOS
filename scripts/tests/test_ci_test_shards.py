import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("ci_test_shards", Path(__file__).parents[1] / "ci-test-shards.py")
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)


class TestCIShardCoverage(unittest.TestCase):
    def setUp(self):
        self.tests = {"ScreenTests/testOpen", "ScreenTests/testClose", "PaymentTests/testRetry"}

    def test_class_and_method_selectors_partition_the_whole_suite(self):
        result = shards.resolve_shards({"ui-screen": ["ScreenTests"], "ui-payment": ["PaymentTests/testRetry"]}, self.tests)
        self.assertEqual(set(result["ui-screen"]), {"ScreenTests/testOpen", "ScreenTests/testClose"})
        self.assertEqual(result["ui-payment"], ["PaymentTests/testRetry"])

    def test_new_unassigned_test_fails_instead_of_silently_reducing_coverage(self):
        with self.assertRaisesRegex(ValueError, "missing=.*PaymentTests/testRetry"):
            shards.resolve_shards({"ui-screen": ["ScreenTests"]}, self.tests)

    def test_overlapping_class_and_method_selectors_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "duplicated=.*ScreenTests/testOpen"):
            shards.resolve_shards({"ui-all": ["ScreenTests", "ScreenTests/testOpen", "PaymentTests"]}, self.tests)

    def test_renamed_or_deleted_test_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Stale selector"):
            shards.resolve_shards({"ui-all": ["OldTests"]}, self.tests)

    def test_empty_shard_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "empty UI shard"):
            shards.resolve_shards({"ui-empty": []}, self.tests)

    def test_source_audit_rejects_ambiguous_class_layout(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / "ScreenTests.swift").write_text("final class ScreenTests: XCTestCase { func testOpen() {} }")
            self.assertEqual(shards.discover_tests(path), {"ScreenTests/testOpen"})
            (path / "ScreenTests.swift").write_text("class A: XCTestCase {}\nclass B: XCTestCase { func testOpen() {} }")
            with self.assertRaisesRegex(ValueError, "Expected one XCTestCase"):
                shards.discover_tests(path)
