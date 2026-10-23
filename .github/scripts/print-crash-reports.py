#!/usr/bin/env python3
"""Prints the newest simulator crash reports and the test-log lines that explain a failed CI test run."""
import glob
import json
import os
import re
import subprocess
import sys

LOG = sys.argv[1] if len(sys.argv) > 1 else "test.log"
RESULT_BUNDLE = sys.argv[2] if len(sys.argv) > 2 else None
MARKERS = re.compile(r"fatal error|terminating app|uncaught exception|crashed|signal|exc_|precondition|assertion|swift runtime failure|swift task continuation misuse", re.I)


def section(title):
    print(f"\n::group::{title}")


def end():
    print("::endgroup::")


section("Test log lines around crash markers")
try:
    with open(LOG, errors="replace") as handle:
        lines = handle.read().splitlines()
    shown = set()
    for index, line in enumerate(lines):
        if MARKERS.search(line):
            for j in range(max(0, index - 2), min(len(lines), index + 12)):
                if j not in shown:
                    shown.add(j)
                    print(f"{j + 1}: {lines[j][:400]}")
            print("--")
        if len(shown) > 400:
            print("(truncated)")
            break
except OSError as error:
    print(f"no log: {error}")
end()

def print_report(path):
    print(f"=== {path}")
    raw = open(path, errors="replace").read()
    newline = raw.find("\n")
    try:
        header = json.loads(raw[:newline])
        body = json.loads(raw[newline + 1:])
    except ValueError as error:
        print(f"unparseable ({error}); first 4000 chars follow")
        print(raw[:4000])
        return
    print("app:", header.get("app_name"), "at", header.get("timestamp"), "bug_type", header.get("bug_type"))
    for key in ("procName", "exception", "termination", "asi", "faultingThread", "exceptionReason"):
        if key in body:
            print(f"{key}: {json.dumps(body[key])[:2500]}")
    images = body.get("usedImages", [])

    def describe(frame):
        image = images[frame.get("imageIndex", -1)] if 0 <= frame.get("imageIndex", -1) < len(images) else {}
        symbol = frame.get("symbol", "")
        location = f" ({frame.get('sourceFile')}:{frame.get('sourceLine')})" if frame.get("sourceFile") else ""
        return f"    {image.get('name', '?')}  {symbol}+{frame.get('symbolLocation', 0)}{location}"

    if "lastExceptionBacktrace" in body:
        print("lastExceptionBacktrace:")
        for frame in body["lastExceptionBacktrace"][:40]:
            print(describe(frame))
    faulting = body.get("faultingThread", 0)
    threads = body.get("threads", [])
    if faulting < len(threads):
        thread = threads[faulting]
        print(f"faulting thread {faulting}: {thread.get('name') or thread.get('queue') or ''}")
        for frame in thread.get("frames", [])[:45]:
            print(describe(frame))


section("Crash reports")
reports = sorted(glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/*.ips")), key=os.path.getmtime)[-8:]
if not reports:
    print("no .ips crash reports found")
for path in reports:
    print_report(path)
end()

if RESULT_BUNDLE and os.path.exists(RESULT_BUNDLE):
    def xcresulttool(*arguments):
        try:
            output = subprocess.run(["xcrun", "xcresulttool", *arguments], capture_output=True, text=True, timeout=180, check=False)
            if output.returncode != 0:
                print(output.stderr[:3000])
            return output.stdout
        except (OSError, subprocess.SubprocessError) as error:
            print(f"xcresulttool failed: {error}")
            return ""

    section("xcresult test summary")
    print(xcresulttool("get", "test-results", "summary", "--path", RESULT_BUNDLE)[:30000])
    end()

    section("xcresult diagnostics (crash logs from the test host)")
    out_dir = os.path.join(os.getcwd(), "xcresult-diagnostics")
    xcresulttool("export", "diagnostics", "--path", RESULT_BUNDLE, "--output-path", out_dir)
    exported = sorted(glob.glob(os.path.join(out_dir, "**", "*"), recursive=True))
    for path in exported:
        if os.path.isfile(path):
            print(path)
    for path in exported:
        if path.endswith((".ips", ".crash")):
            print_report(path)
    end()

    section("xcresult console log around crash markers")
    console = xcresulttool("get", "log", "--path", RESULT_BUNDLE, "--type", "console").splitlines()
    shown = set()
    for index, line in enumerate(console):
        if MARKERS.search(line):
            for j in range(max(0, index - 3), min(len(console), index + 15)):
                if j not in shown:
                    shown.add(j)
                    print(f"{j + 1}: {console[j][:400]}")
            print("--")
        if len(shown) > 400:
            print("(truncated)")
            break
    print("... last 60 console lines:")
    for line in console[-60:]:
        print(line[:400])
    end()
