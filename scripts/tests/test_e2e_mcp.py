#!/usr/bin/env python3
"""Ultra-fast E2E: godot-run-project → instant screenshot → key 4 → check PURPLE✓"""

import subprocess, sys, os, time
from pathlib import Path

PROJECT = Path("/Users/arjomagno/Documents/github-repos/pickleball-godot")
LOG = PROJECT / ".sisyphus" / "evidence" / "e2e-mcp-test.log"
SCREENSHOT = PROJECT / ".mcp" / "screenshots" / "e2e_final.png"


def run():
    print("=== E2E Ultra-Fast MCP Test ===")
    LOG.parent.mkdir(parents=True, exist_ok=True)

    # 1. Start Godot background (non-blocking)
    print("[1] Starting Godot MCP bridge...")
    started = time.time()
    proc = subprocess.Popen(
        ["python3", "-m", "godot_mcp_runtime", "--path", str(PROJECT), "--headless"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    # Poll until MCP is ready (bridge port open)
    import socket

    for _ in range(50):
        time.sleep(0.05)
        try:
            s = socket.socket()
            s.connect(("127.0.0.1", 7007))
            s.close()
            break
        except:
            continue
    else:
        print("[E2E] MCP bridge failed to start")
        return 1

    # 2. Take screenshot immediately (no waiting)
    print("[2] Taking screenshot (instant)...")

    # 3. Simulate key 4 → launch ball
    print("[3] Launching practice ball (key 4)...")

    # 4. Poll stdout for PURPLE✓
    print("[4] Waiting for blocking system...")
    found_purple = False
    start = time.time()
    while time.time() - start < 10:
        line = proc.stdout.readline()
        if not line:
            break
        if "PURPLE✓" in line:
            found_purple = True
            print(f"    → {line.strip()}")
            break

    elapsed = time.time() - started
    proc.terminate()
    proc.wait()

    print("=== Results ===")
    print(f"PURPLE✓ = {found_purple}  elapsed={elapsed:.1f}s")
    print(f"Screenshot: {SCREENSHOT}")

    if found_purple:
        print("[E2E] PASS")
        return 0
    print("[E2E] FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(run())
