#!/usr/bin/env python3
"""
E2E test: paddle gizmo drag → save → reload round-trip precision.

Launches Godot headless with --script test_e2e_gizmo_save_runner.gd,
captures stdout, parses RESULT line, reports PASS or FAIL.

Bypass: GODOT_TEST_BYPASS_GIZMO_SAVE=1 → exits 0 with "SKIPPED".
"""

import subprocess
import sys
import os
import re
import time
from pathlib import Path

PROJECT = Path(__file__).parent.parent.parent.absolute()
LOG = PROJECT / ".sisyphus" / "evidence" / "e2e-gizmo-save.log"

GODOT_PATH = str(Path.home() / "Downloads" / "Godot.app" / "Contents" / "MacOS" / "Godot")
RUNNER_SCRIPT = "scripts/tests/test_e2e_gizmo_save_runner.gd"

GODOT_CMD = [
    GODOT_PATH,
    "--path", str(PROJECT),
    "--headless",
    "--display-driver", "headless",
    "--audio-driver", "Dummy",
    "--disable-render-loop",
    "--quit-after", "30",
    "--script", RUNNER_SCRIPT,
]


def run():
    # ── Bypass ────────────────────────────────────────────────────────────────
    if os.environ.get("GODOT_TEST_BYPASS_GIZMO_SAVE") == "1":
        print("[E2E] SKIPPED (bypass)")
        return 0

    LOG.parent.mkdir(parents=True, exist_ok=True)

    print("[E2E] Launching Godot headless with E2E runner...")
    started = time.time()

    env = os.environ.copy()
    env["GODOT_DISABLE_LEAKS"] = "1"

    try:
        proc = subprocess.Popen(
            GODOT_CMD,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
        )
    except FileNotFoundError:
        print("[E2E] FAIL: Godot not found at %s" % GODOT_PATH)
        return 1

    result_line = None
    with open(LOG, "w") as lf:
        for line in proc.stdout:
            lf.write(line)
            lf.flush()
            if "RESULT" in line:
                result_line = line.strip()
                print(f"    {line.strip()}")
                break

    proc.wait()
    elapsed = time.time() - started

    if result_line is None:
        print("[E2E] FAIL: no RESULT line found in output (elapsed=%.1fs)" % elapsed)
        print("[E2E] Log: %s" % LOG)
        return 1

    # Parse RESULT ok:=True forehand:=0.123 ...
    m = re.search(r"RESULT\s+ok:=(\w+)\s+forehand:=([-\d.e]+)\s+forward:=([-\d.e]+)\s+y_offset:=([-\d.e]+)\s+error:=(.*)$", result_line)
    if not m:
        print("[E2E] FAIL: could not parse RESULT line: %s" % result_line)
        return 1

    ok = m.group(1) == "True"
    error_msg = m.group(5)

    if ok:
        print("[E2E] PASS  (%.1fs)" % elapsed)
        return 0
    else:
        print("[E2E] FAIL: %s  (%.1fs)" % (error_msg, elapsed))
        return 1


if __name__ == "__main__":
    sys.exit(run())
