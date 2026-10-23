#!/usr/bin/env python3
"""Copies exported xcresult attachments into Media/screenshots using the human-readable names, and the
app icon renders into their own folder.

Usage: place-screenshots.py <artifacts-dir> <destination-dir> <icon-renders-dir>

The artifacts directory holds one folder per device ("screenshots-<device>"), with one subfolder per
result bundle exported by `xcrun xcresulttool export attachments`, which writes a manifest.json next
to the files. Only PNG attachments named like "01-overview-light" are placed, so failure recordings
and spindumps never reach the repository. iPhone captures land in the destination root; every other
device gets a lower-cased subfolder.

Stale captures are removed per device folder and appearance, and only when that appearance placed all
seven expected screens in this run: then any other "NN-name-<appearance>.png" directly in the folder is
deleted. An appearance with some captures missing is placed without deleting anything and reported as
INCOMPLETE; an appearance with no captures leaves its files untouched.

An "icon-renders" folder in a device folder holds the `ictool` renders of the app icon
("AppIcon-Default.png" and so on); its PNGs are copied unchanged into the icon renders directory.

With GITHUB_STEP_SUMMARY set, a placed / expected table is appended once per run (the commit job reruns
this script after a rejected push; a marker file in the artifacts directory keeps the summary single).
"""
import json
import os
import re
import shutil
import subprocess
import sys

EXPECTED = ["01-overview", "02-devices", "03-device-detail", "04-activity", "05-insights", "06-settings", "07-scan"]
APPEARANCES = ["light", "dark"]

artifacts_dir, destination, icon_destination = sys.argv[1], sys.argv[2], sys.argv[3]
placed = 0
icons = 0
# (device, target folder) -> appearance -> screen names placed in this run
results = {}

for device_dir in sorted(os.listdir(artifacts_dir)):
    device_path = os.path.join(artifacts_dir, device_dir)
    if not os.path.isdir(device_path):
        continue
    device = device_dir.removeprefix("screenshots-")
    if device.startswith("iPhone"):
        target_dir = destination
    else:
        target_dir = os.path.join(destination, re.sub(r"[^a-z0-9]+", "-", device.lower()).strip("-"))
    screens = results.setdefault((device, target_dir), {appearance: set() for appearance in APPEARANCES})

    for source_dir, _, files in sorted(os.walk(device_path)):
        if os.path.basename(source_dir) == "icon-renders":
            for file in sorted(files):
                if not file.lower().endswith(".png"):
                    continue
                os.makedirs(icon_destination, exist_ok=True)
                target = os.path.join(icon_destination, file)
                shutil.copyfile(os.path.join(source_dir, file), target)
                icons += 1
                print(f"{device}: {file} -> {target}")
            continue
        if "manifest.json" not in files:
            continue
        with open(os.path.join(source_dir, "manifest.json")) as handle:
            manifest = json.load(handle)
        if isinstance(manifest, dict):
            manifest = [manifest]
        entries = []
        for test in manifest:
            entries.extend(test.get("attachments", []))
        for attachment in entries:
            exported = attachment.get("exportedFileName")
            readable = attachment.get("suggestedHumanReadableName") or exported or ""
            if not exported or not exported.lower().endswith(".png"):
                continue
            name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", os.path.splitext(readable)[0])
            if not re.match(r"^\d\d-[a-z0-9-]+$", name):
                print(f"{device}: skipping {readable}")
                continue
            os.makedirs(target_dir, exist_ok=True)
            target = os.path.join(target_dir, f"{name}.png")
            shutil.copyfile(os.path.join(source_dir, exported), target)
            placed += 1
            print(f"{device}: {exported} -> {target}")
            screen, _, appearance = name.rpartition("-")
            if appearance in screens:
                screens[appearance].add(screen)

if placed == 0:
    raise SystemExit("no screenshots were placed")

summary = ["### Screenshots", "", "| Device | Appearance | Placed | Missing |", "| --- | --- | --- | --- |"]
incomplete = []
for (device, target_dir), screens in sorted(results.items()):
    for appearance in APPEARANCES:
        found = screens[appearance]
        missing = [screen for screen in EXPECTED if screen not in found]
        summary.append(f"| {device} | {appearance} | {len(EXPECTED) - len(missing)} / {len(EXPECTED)} | {', '.join(missing)} |")
        if not found:
            continue
        if missing:
            line = f"INCOMPLETE {device} {appearance}: missing {', '.join(missing)}"
            print(line)
            incomplete.append(line)
            continue
        keep = {f"{screen}-{appearance}.png" for screen in found}
        stale = re.compile(rf"^\d\d-[a-z0-9-]+-{appearance}\.png$")
        for file in sorted(os.listdir(target_dir)):
            path = os.path.join(target_dir, file)
            if stale.match(file) and file not in keep and os.path.isfile(path):
                os.remove(path)
                print(f"removed stale {path}")

summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
marker = os.path.join(artifacts_dir, ".placed-summary")
if summary_path and not os.path.exists(marker):
    with open(summary_path, "a") as handle:
        handle.write("\n".join(summary + [""] + incomplete) + "\n")
    open(marker, "w").close()

if shutil.which("optipng"):
    for directory in (destination, icon_destination):
        for root, _, files in os.walk(directory):
            for file in files:
                if file.endswith(".png"):
                    subprocess.run(["optipng", "-quiet", "-o2", os.path.join(root, file)], check=False)
print(f"placed {placed} screenshots and {icons} app icon renders")
