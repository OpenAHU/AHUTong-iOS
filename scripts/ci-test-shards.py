#!/usr/bin/env python3
"""Assign every UI test to exactly one shard, then emit xcodebuild selectors."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def discover_tests(directory):
    tests = set()
    for path in sorted(directory.glob("*.swift")):
        source = path.read_text()
        classes = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", source)
        methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", source)
        if not methods:
            continue
        # Keep the source audit fail-closed if the test layout changes.
        if len(classes) != 1:
            raise ValueError(f"Expected one XCTestCase class in {path.name}")
        for method in methods:
            identifier = f"{classes[0]}/{method}"
            if identifier in tests:
                raise ValueError(f"Duplicate test definition: {identifier}")
            tests.add(identifier)
    if not tests:
        raise ValueError("No UI tests discovered")
    return tests


def resolve_shards(shards, tests):
    resolved = {}
    for suite, selectors in shards.items():
        if not suite.startswith("ui-") or not selectors:
            raise ValueError(f"Invalid or empty UI shard: {suite}")
        selected = []
        for selector in selectors:
            matches = sorted(t for t in tests if t == selector or t.startswith(selector + "/"))
            if not matches:
                raise ValueError(f"Stale selector in {suite}: {selector}")
            selected.extend(matches)
        resolved[suite] = selected
    counts = Counter(test for selected in resolved.values() for test in selected)
    missing = sorted(tests - counts.keys())
    duplicated = sorted(t for t, count in counts.items() if count != 1)
    if missing or duplicated:
        raise ValueError(f"UI coverage mismatch; missing={missing}, duplicated={duplicated}")
    return resolved


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["validate", "matrix", "options"])
    parser.add_argument("suite", nargs="?")
    args = parser.parse_args()
    try:
        shards = resolve_shards(
            json.loads((ROOT / ".github/ci-test-shards.json").read_text()),
            discover_tests(ROOT / "AHUTongUITests"),
        )
        if args.command == "matrix":
            print(json.dumps({"suite": list(shards)}, separators=(",", ":")))
        elif args.command == "options":
            if args.suite == "unit":
                print("-only-testing:AHUTongTests")
            elif args.suite in shards:
                for test in shards[args.suite]:
                    print(f"-only-testing:AHUTongUITests/{test}")
            else:
                raise ValueError(f"Unknown suite: {args.suite}")
        else:
            for suite, tests in shards.items():
                print(f"{suite}: {len(tests)} UI tests")
            print(f"All {sum(map(len, shards.values()))} UI tests assigned exactly once")
    except ValueError as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
