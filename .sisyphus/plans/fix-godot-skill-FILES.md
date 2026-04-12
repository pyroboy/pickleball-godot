# /fix-godot Skill — Full Implementation Ready to Copy-Paste

## FILE 1: ~/.claude/skills/fix-godot/SKILL.md

```markdown
# fix-godot — Autonomous Godot Debug Fixer

**Triggers**: fix godot, godot crash, godot error, fix the game, debug godot, game crash, game error

## Prerequisites Check

**BEFORE doing anything else**, verify Godot is installed:

```bash
which godot || ls /Applications/Godot.app/Contents/MacOS/Godot 2>/dev/null
```

If NOT_FOUND or empty output:
```
Godot is not installed. Install with:
  brew install godot

This installs Godot 4.6.2 to /Applications/Godot.app
After installation, restart your terminal and try again.
```

If Godot IS found, proceed to Step 1.

## Health Check Protocol

### Step 1: Warm-up Import (REQUIRED - each session)

Godot 4.x won't recognize script classes without warm-up if .godot/ folder is clean:

```bash
cd /Users/arjomagno/Documents/github-repos/pickleball-godot
godot --headless --path . --quit-after 30 2>&1
echo "Exit code: $?"
```

Non-zero exit or parse errors here = fix these FIRST before anything else.

### Step 2: Run Game Headless (Error Capture)

Launch the main game scene and capture all output:

```bash
cd /Users/arjomagno/Documents/github-repos/pickleball-godot
timeout 25 godot --headless --path . 2>&1 | tee /tmp/godot_run.log
echo "Exit code: $?"
```

Wait for timeout (exit 124 is normal = game ran for full duration without crash).
Non-zero exit other than 124 = crash detected.

### Step 3: Parse Errors

```bash
grep -E "(SCRIPT ERROR|PARSE ERROR|ERROR:|Invalid call|on null|not in dictionary|nonexistent)" /tmp/godot_run.log | head -20
```

## Error → Fix Mapping

### Parse Error (Syntax)
**Detection**: SCRIPT ERROR: Parse Error: or PARSE ERROR:
**Action**: Read the file at the path:line shown. Fix syntax (missing comma, wrong indent, missing colon). Only fix syntax, don't refactor.

### Null Instance
**Detection**: Attempt to call on null instance, Attempt to access on null, on null.
**Action**: Find which node is null (before the dot). Check _ready() init. Add null check or fix node path.

### Invalid Call
**Detection**: Invalid call. Nonexistent function.
**Action**: Check function exists and argument count matches. Godot 4 is strict about arg counts.

### Dictionary Key Error
**Detection**: Index 'X' not in dictionary.
**Action**: Check dict init and key spelling. Use .get() for safe access.

### Signal Error
**Detection**: Signal not found, connects to nonexistent method
**Action**: Check signal defined with 'signal X' and method name matches in connect().

## Fix Protocol

1. Read file and error message
2. Fix minimally - correct only the error
3. Re-run warm-up import to verify
4. Report what was fixed

## Success Criteria

- godot --headless --path . --quit-after 30 exits 0 (warm-up)
- timeout 25 godot --headless --path . exits 124 (ran full duration, no crash)
- Zero SCRIPT ERROR or PARSE ERROR in output

## What This CANNOT Fix

Physics tuning, visual glitches, AI behavior, performance issues. Those need the Godot editor.

## Project Context

Project path: /Users/arjomagno/Documents/github-repos/pickleball-godot
Entry scene: scenes/game.tscn
Main script: scripts/game.gd
Player: scripts/player.gd (20 postures in PaddlePosture enum)
Hitting: scripts/player_hitting.gd (charge/FT system)
Postures: scripts/posture_library.gd (475 lines, all 20 posture definitions)
```

---

## FILE 2: ~/.claude/skills/fix-godot/scripts/health_check.py

```python
#!/usr/bin/env python3
"""
Godot health check script for pickleball-godot.
Runs Godot headless, captures output, parses errors, outputs JSON score.

Usage: python3 health_check.py
Output: JSON to stdout
"""

import subprocess
import json
import os
import re

PROJECT_DIR = "/Users/arjomagno/Documents/github-repos/pickleball-godot"
GODOT_CMD = "godot"


def run_command(cmd, timeout=35):
    """Run shell command, return stdout+stderr and exit code."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", 124
    except Exception as e:
        return str(e), 1


def parse_errors(output):
    """Parse Godot output for errors. Return list of error dicts."""
    errors = []

    patterns = [
        (r"SCRIPT ERROR: Parse Error: (.+)", "critical", "parse_error"),
        (r"PARSE ERROR: (.+)", "critical", "parse_error"),
        (r"SCRIPT ERROR: Invalid call\.", "high", "invalid_call"),
        (r"SCRIPT ERROR: Nonexistent function", "high", "invalid_call"),
        (r"SCRIPT ERROR: Attempt to call '.+' on null instance", "high", "null_call"),
        (r"SCRIPT ERROR: Attempt to access '.+' on null", "high", "null_access"),
        (r"ERROR: Condition.*is true", "medium", "error"),
        (r"Index '.+' not in dictionary", "high", "dict_key"),
        (r"Signal '.+' not found", "medium", "signal_not_found"),
        (r"connects to nonexistent method", "medium", "signal_not_found"),
    ]

    for line in output.split("\n"):
        for pattern, severity, error_type in patterns:
            match = re.search(pattern, line)
            if match:
                errors.append({
                    "type": error_type,
                    "severity": severity,
                    "line": line.strip(),
                    "snippet": match.group(1) if match.groups() else line.strip()[:100],
                })
                break

    return errors


def compute_score(errors, exit_code):
    """Compute 0-100 health score."""
    if exit_code == 0:
        return 100

    if exit_code == 124:
        if not errors:
            return 100
        penalty = 0
        for e in errors:
            if e["severity"] == "critical":
                penalty += 40
            elif e["severity"] == "high":
                penalty += 20
            else:
                penalty += 5
        return max(0, 100 - penalty)

    if exit_code in (1, 255):
        return 0

    if not errors:
        return 50
    return 20


def main():
    # Step 1: Warm-up import
    warmup_out, warmup_code = run_command(
        f'{GODOT_CMD} --headless --path . --quit-after 30 2>&1',
        timeout=35
    )

    warmup_errors = parse_errors(warmup_out)
    warmup_clean = warmup_code == 0 and not warmup_errors

    # Step 2: Run game headless
    game_out, game_code = run_command(
        f'timeout 25 {GODOT_CMD} --headless --path . 2>&1',
        timeout=30
    )

    game_errors = parse_errors(game_out)
    score = compute_score(game_errors, game_code)

    all_errors = warmup_errors + game_errors

    result = {
        "score": score,
        "warmup_clean": warmup_clean,
        "warmup_exit_code": warmup_code,
        "game_exit_code": game_code,
        "errors": all_errors,
        "crashed": game_code in (1, 255) or (game_code not in (0, 124)),
        "error_count": len(all_errors),
        "critical_count": sum(1 for e in all_errors if e["severity"] == "critical"),
        "high_count": sum(1 for e in all_errors if e["severity"] == "high"),
    }

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
```

---

## Setup Commands (run these manually)

```bash
# 1. Create directory
mkdir -p ~/.claude/skills/fix-godot/scripts

# 2. Write SKILL.md (copy content from FILE 1 above)
# 3. Write health_check.py (copy content from FILE 2 above)
# 4. Make executable
chmod +x ~/.claude/skills/fix-godot/scripts/health_check.py

# 5. Test
python3 ~/.claude/skills/fix-godot/scripts/health_check.py
```

---

## CLAUDE.md Addition (append to pickleball-godot/CLAUDE.md)

Add this section at the end:

```markdown
## Auto-Debug System (OpenCode)

OpenCode can autonomously find and fix Godot errors via `/fix-godot`.

### Prerequisites
```bash
brew install godot  # Godot 4.6.2 required
```

### Usage
```
/fix-godot
```
This will:
1. Check Godot is installed
2. Run warm-up import (registers all script classes)
3. Launch game headless for 15 seconds
4. Parse errors from stderr/stdout
5. Auto-fix common errors (parse errors, null calls, invalid calls)
6. Re-verify the fix

### What it fixes
- Parse/syntax errors in .gd files
- Null instance errors (uninitialized nodes)
- Invalid function calls (wrong arg count/type)
- Missing dictionary keys
- Signal connection errors

### What it CANNOT fix
- Physics tuning, visual glitches, AI behavior, performance

### Manual debug
```bash
cd /Users/arjomagno/Documents/github-repos/pickleball-godot
godot --headless --path . --quit-after 30 2>&1 | grep -i error
```
```
