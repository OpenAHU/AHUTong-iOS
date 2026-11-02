#!/usr/bin/env python3
"""Write public build identity; never read signing or contribution credentials."""
import datetime
import os
import pathlib
import plistlib
import sys

output = pathlib.Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(plistlib.dumps({
    "actionsRun": int(os.environ.get("AHUTONG_ACTIONS_RUN_NUMBER", "0")),
    "builtAt": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
}))
