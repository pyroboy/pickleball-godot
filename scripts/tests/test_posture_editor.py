#!/usr/bin/env python3
"""Super-fast posture editor check using godot_run_project + MCP tools."""

import subprocess, sys, time, socket, json
from pathlib import Path

PROJECT = Path("/Users/arjomagno/Documents/github-repos/pickleball-godot")
LOG = PROJECT / ".sisyphus" / "evidence" / "e2e-pe-check.log"
MCP_PORT = 9900


def wait_bridge(timeout=15):
    t = time.time()
    while time.time() - t < timeout:
        try:
            s = socket.socket()
            s.settimeout(0.2)
            s.connect(("127.0.0.1", MCP_PORT))
            s.close()
            return True
        except:
            time.sleep(0.05)
    return False


def mcp_send(cmd):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3.0)
    try:
        sock.sendto(json.dumps(cmd).encode(), ("127.0.0.1", MCP_PORT))
        data, _ = sock.recvfrom(65536)
        return json.loads(data.decode())
    finally:
        sock.close()


RUN_SCRIPT_PE = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "run_script",
    "params": {
        "script": """
extends RefCounted
func execute(scene_tree) -> Variant:
    var game = scene_tree.get_root().get_node("Game")
    var peui = null
    for c in game.get_children():
        if c is CanvasLayer:
            peui = c.get_node_or_null("PostureEditorUI")
            break
    if not peui:
        return {"error": "no PostureEditorUI"}
    return {"visible": peui.visible}
"""
    },
}

SIM_E = {
    "jsonrpc": "2.0",
    "id": 2,
    "method": "simulate_input",
    "params": {
        "actions": [
            {"type": "key", "key": "E", "pressed": True},
            {"type": "wait", "ms": 50},
            {"type": "key", "key": "E", "pressed": False},
        ]
    },
}


def start_godot():
    proc = subprocess.Popen(
        ["python3", "-m", "godot_mcp_runtime", "--path", str(PROJECT), "--headless"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return proc


def run():
    print("=== E2E Ultra-Fast: Posture Editor Check ===")
    LOG.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()

    print("[1] Starting Godot MCP runtime...")
    proc = start_godot()

    print("[2] Waiting for bridge...")
    if not wait_bridge():
        print("[E2E] FAIL — no MCP bridge")
        proc.kill()
        return 1
    print(f"    {time.time() - started:.1f}s")

    print("[3] Simulating E key...")
    mcp_send(SIM_E)
    time.sleep(0.15)

    print("[4] Querying PostureEditorUI.visible...")
    resp = mcp_send(RUN_SCRIPT_PE)
    result = resp.get("result", {})
    visible = result.get("visible", False)

    elapsed = time.time() - started
    print(f"=== Results ===  elapsed={elapsed:.1f}s  PostureEditor={visible}")
    print(f"Log: {LOG}")

    proc.terminate()
    proc.wait()

    if visible:
        print("[E2E] PASS")
        return 0
    print("[E2E] FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(run())
