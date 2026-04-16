#!/usr/bin/env python3
import subprocess, sys, os, time
from pathlib import Path

GODOT_PATH = str(
    Path.home() / "Downloads" / "Godot.app" / "Contents" / "MacOS" / "Godot"
)
PROJECT_PATH = Path(__file__).parent.parent.parent.absolute()
E2E_LOG = PROJECT_PATH / ".sisyphus" / "evidence" / "e2e-blocking-test.log"
SCREENSHOT = PROJECT_PATH / ".sisyphus" / "evidence" / "e2e-screenshot.png"

GODOT_CMD = [
    GODOT_PATH,
    "--path",
    str(PROJECT_PATH),
    "--headless",
    "--display-driver",
    "headless",
    "--audio-driver",
    "Dummy",
    "--disable-render-loop",
]


def run():
    print("=== E2E Ultra-Fast Test ===")
    E2E_LOG.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["GODOT_DISABLE_LEAK_CHECKS"] = "1"

    found_purple = found_p0 = found_p1 = False
    errors = []
    started = time.time()

    proc = subprocess.Popen(
        GODOT_CMD,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )

    with open(E2E_LOG, "w") as lf:
        while True:
            line = proc.stdout.readline()
            if not line:
                if proc.poll() is not None:
                    break
                if time.time() - started > 20:
                    proc.kill()
                    break
                continue

            lf.write(line)
            lf.flush()

            if "[PURPLE" in line:
                found_purple = True
            if "[P0]" in line and "Arms:" in line and "Arms: 0" not in line:
                found_p0 = True
            if "[P1]" in line and "Arms:" in line and "Arms: 0" not in line:
                found_p1 = True
            if "ERROR:" in line and "Script" in line:
                errors.append(line.strip())

            if found_purple and found_p0 and found_p1:
                print("[E2E] All checks passed, quitting...")
                proc.terminate()
                proc.wait()
                break

    elapsed = time.time() - started

    print("=== Results ===")
    print(f"PURPLE={found_purple} P0={found_p0} P1={found_p1} Errors={len(errors)}")
    print(f"Elapsed={elapsed:.1f}s")

    if found_purple and found_p0 and found_p1 and not errors:
        print("[E2E] PASS")
        return 0
    elif found_purple and found_p0 and found_p1:
        print("[E2E] PARTIAL")
        return 1
    print("[E2E] FAIL")
    print(f"Log: {E2E_LOG}")
    return 1


if __name__ == "__main__":
    sys.exit(run())
