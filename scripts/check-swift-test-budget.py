#!/usr/bin/env python3
"""Keep hosted Swift unit tests within the project's 500-method budget."""

from pathlib import Path
import re
import sys


root = Path(__file__).resolve().parents[1]
count = sum(
    len(re.findall(r"^\s+func\s+test\w+\s*\(\s*\)", path.read_text(), re.MULTILINE))
    for path in (root / "AHUTongTests").rglob("*.swift")
)
print(f"Swift unit test methods: {count}/500 (UI, Rust and Python excluded)")
if count > 500:
    sys.exit("Review redundant or obsolete tests before adding more; keep independent scenarios separate.")
