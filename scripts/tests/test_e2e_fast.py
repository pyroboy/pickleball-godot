#!/usr/bin/env python3
import subprocess, sys, os, time
from pathlib import Path

GODOT_PATH = str(
    Path.home() / "Downloads" / "Godot.app" / "Contents" / "MacOS" / "Godot"
)
PROJECT = Path(__file__).parent.parent.parent.absolute()
LOG = PROJECT / ".sisyphus" / "evidence" / "e2e-fast.log"

GODOT_CMD = [
    GODOT_PATH,
    "--path",
    str(PROJECT),
    "--headless",
    "--display-driver",
    "headless",
    "--audio-driver",
    "Dummy",
    "--disable-render-loop",
    "--quit-after",
    "120",
]


def run():
    print("=== E2E Ultra-Fast Test (10x speed) ===")
    LOG.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["GODOT_DISABLE_LEAK_CHECKS"] = "1"
    env["GODOT_TEST_FAST"] = "10.0"
    env["GODOT_TEST_AUTO_LAUNCH"] = "1"

    started = time.time()
    proc = subprocess.Popen(
        GODOT_CMD,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )

    found = False
    with open(LOG, "w") as lf:
        for line in proc.stdout:
            lf.write(line)
            lf.flush()
            if "PURPLE" in line:
                print(f"    {line.strip()}")
                found = True
                break

    proc.wait()
    elapsed = time.time() - started
    print(f"=== Results ===  elapsed={elapsed:.1f}s  PURPLE={found}")
    print(f"Log: {LOG}")
    if found:
        print("[E2E] PASS")
        return 0
    print("[E2E] FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(run())
