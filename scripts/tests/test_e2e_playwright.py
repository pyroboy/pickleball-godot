#!/usr/bin/env python3
import subprocess
import sys
import time
import os
from pathlib import Path

GODOT_PATH = str(Path.home() / "Downloads" / "Godot.app" / "Contents" / "MacOS" / "Godot")
PROJECT_PATH = Path(__file__).parent.parent.parent.absolute()
E2E_LOG = PROJECT_PATH / ".sisyphus" / "evidence" / "e2e-blocking-test.log"

def run_test():
    print("=== E2E Blocking System Test ===")
    E2E_LOG.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["GODOT_DISABLE_LEAK_CHECKS"] = "1"
    cmd = [GODOT_PATH, "--path", str(PROJECT_PATH), "--headless", "--display-driver", "headless", "--audio-driver", "Dummy", "--disable-render-loop", "--quit-after", "600"]
    print("[E2E] Starting Godot headless...")
    with open(E2E_LOG, "w") as log_file:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        purple_count = 0
        p0_logs = 0
        p1_logs = 0
        script_errors = []
        start = time.time()
        while True:
            line = proc.stdout.readline()
            if not line:
                if proc.poll() is not None:
                    break
                if time.time() - start > 15:
                    proc.kill()
                    break
                time.sleep(0.1)
                continue
            log_file.write(line)
            log_file.flush()
            if "[PURPLE" in line: purple_count += 1
            if "[P0]" in line and "Arms:" in line: p0_logs += 1
            if "[P1]" in line and "Arms:" in line: p1_logs += 1
            if "ERROR:" in line and "Script" in line: script_errors.append(line.strip())
        print(f"[E2E] Collected {time.time() - start:.1f}s output")
    print("=== Results ===")
    print(f"PURPLE logs: {purple_count}")
    print(f"Player0 init: {p0_logs}")
    print(f"Player1 init: {p1_logs}")
    print(f"Script errors: {len(script_errors)}")
    blocking_active = purple_count > 0 and p0_logs > 0 and p1_logs > 0
    print(f"Log: {E2E_LOG}")
    if blocking_active and len(script_errors) == 0:
        print("[E2E] PASS")
        return 0
    elif blocking_active:
        print("[E2E] PARTIAL")
        return 1
    else:
        print("[E2E] FAIL")
        return 1

if __name__ == "__main__":
    sys.exit(run_test())
