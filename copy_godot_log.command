#!/usr/bin/env python3
import subprocess
import os

log_path = os.path.expanduser("~/godot_log.txt")

if not os.path.exists(log_path):
    subprocess.run(
        [
            "osascript",
            "-e",
            'display notification "godot_log.txt not found!" with title "Godot Log" subtitle "Error"',
        ]
    )
    exit(1)

with open(log_path, "r") as f:
    content = f.read()

# Copy to clipboard
process = subprocess.Popen("pbcopy", env={"PATH": "/usr/bin"}, stdin=subprocess.PIPE)
process.communicate(content.encode("utf-8"))

# Toast notification
line_count = content.count("\n")
msg = f"Copied {line_count} lines to clipboard!"
subprocess.run(
    [
        "osascript",
        "-e",
        f'display notification "{msg}" with title "Godot Log" subtitle "✅ Copied!"',
    ]
)

print(msg)
