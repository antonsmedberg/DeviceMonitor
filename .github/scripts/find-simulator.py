#!/usr/bin/env python3
"""Prints the UDID of an available simulator with exactly this name on the newest iOS runtime."""
import json
import re
import subprocess
import sys

name = sys.argv[1]
devices = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"], capture_output=True, text=True, check=True).stdout)["devices"]
candidates = []
for runtime, entries in devices.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in entries:
        if device["name"] == name and device.get("isAvailable", False):
            candidates.append((version, device["udid"]))
if not candidates:
    raise SystemExit(f"No available simulator named {name!r}")
candidates.sort()
print(candidates[-1][1])
