# Plan: /fix-godot Skill for OpenCode

## TL;DR

Build an OpenCode skill that autonomously finds and fixes Godot GDScript errors by running the game headless, parsing error output, and applying minimal fixes.

---

## Context

The user wants an autonomous debug loop for their Godot 4.6.2 pickleball game — similar to the `autoresearch` skill that exists for the TypeScript codebase, but for Godot GDScript. They use OpenCode (not Claude Code).

**Key constraint**: Prometheus (planning agent) can ONLY write `.md` files to `.sisyphus/`. Implementation must be delegated.

---

## Deliverables

### 1. Skill File: `~/.claude/skills/fix-godot/SKILL.md`

The skill Markdown file that OpenCode reads when `/fix-godot` is invoked. Must include:

- **Trigger phrases**: "fix godot", "godot crash", "godot error", "fix the game", "debug godot"
- **Prerequisites check**: Verify Godot is installed, tell user to `brew install godot` if not
- **Health check commands**: Warm-up import + headless run with error capture
- **Error → fix mapping table**: Parse Error, Null Instance, Invalid Call, Dict Key, Signal Not Found — each with fix strategy
- **Success criteria**: Exit code 0, zero SCRIPT ERROR/PARSE ERROR
- **What it CANNOT fix**: Physics tuning, visual glitches, AI behavior

### 2. Health Check Script: `~/.claude/skills/fix-godot/scripts/health_check.py`

Python script that wraps Godot CLI:

```
Input:  (none — reads from project path)
Output: JSON {score: 0-100, errors: [...], crashed: bool, stdout: "...", stderr: "..."}
```

Steps:
1. Change to project dir: `/Users/arjomagno/Documents/github-repos/pickleball-godot`
2. Run warm-up: `godot --headless --path . --quit-after 30`
3. Run game: `timeout 20 godot --headless --path . -- 2>&1`
4. Parse output for error patterns
5. Score: 100 if clean, else weighted by error severity

Error patterns to detect:
- `SCRIPT ERROR: Parse Error:` → severity=critical
- `SCRIPT ERROR: Invalid call.` → severity=high
- `SCRIPT ERROR: Attempt to call.*on null instance.` → severity=high
- `SCRIPT ERROR: Attempt to access.*on null.` → severity=high
- `PARSE ERROR:` → severity=critical
- `ERROR: Condition.*is true.` → severity=medium
- `Index.*not in dictionary.` → severity=high

### 3. CLAUDE.md Update

Add new section documenting the auto-debug system:

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

---

## Execution Strategy

### Wave 1: Create SKILL.md (quick)
Delegate to `quick` agent — write the skill markdown file with all trigger phrases, commands, and fix strategies.

### Wave 2: Create health_check.py (quick)
Delegate to `quick` agent — write the Python health check script. Must output valid JSON to stdout.

### Wave 3: Update CLAUDE.md (quick)
Delegate to `quick` agent — read current CLAUDE.md, append the Auto-Debug System section.

---

## Verification

1. Run `/fix-godot` — should output "Godot not found" if not installed, or run health check
2. After all waves: CLAUDE.md has the new section, skill file exists at correct path, health_check.py is executable

---

## Success Criteria

- `~/.claude/skills/fix-godot/SKILL.md` exists and is valid OpenCode skill
- `~/.claude/skills/fix-godot/scripts/health_check.py` exists and outputs JSON
- `CLAUDE.md` in pickleball-godot has Auto-Debug System section
- `/fix-godot` can be invoked in OpenCode and produces meaningful output
