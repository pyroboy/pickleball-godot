# Fix Graphify KeyError 'source' Bug

## TL;DR

> **Quick Summary**: Add edge normalization before `existing_pairs` is built in extract.py to handle edges with `from`/`to` keys instead of `source`/`target`.
>
> **Deliverables**:
> - 4 lines of defensive code added to extract.py at line 3526
> - Full graphify pipeline runs without KeyError
>
> **Estimated Effort**: Trivial (<5 min)
> **Parallel Execution**: NO - sequential single task
> **Critical Path**: Fix → Verify

---

## Context

### Original Problem
`graphify update .` fails at line 3526:
```python
existing_pairs = {(e["source"], e["target"]) for e in all_edges}
KeyError: 'source'
```

### Root Cause
When extracting 10+ files, somewhere in cross-file resolution, edges get added with `from`/`to` keys instead of `source`/`target`. The code at line 3526 assumes all edges already have `source`/`target`.

### Reference Fix
`build.py` at lines 63-66 already handles this remapping:
```python
if "source" not in edge and "from" in edge:
    edge["source"] = edge["from"]
if "target" not in edge and "to" in edge:
    edge["target"] = edge["to"]
```

### Files Involved
- `/opt/homebrew/lib/python3.14/site-packages/graphify/extract.py` — line 3526 (fix site)
- `/opt/homebrew/lib/python3.14/site-packages/graphify/build.py` — reference implementation

---

## Work Objectives

### Core Objective
Fix KeyError 'source' bug in extract.py cross-file edge assembly

### Must Have
- [ ] Edge normalization code added before `existing_pairs` is built
- [ ] Pipeline runs without KeyError on 10+ files

### Must NOT Have
- [ ] No changes to build.py (fix is already there)
- [ ] No changes to cached extraction results

---

## Execution Strategy

Single wave - one task.

---

## TODOs

- [ ] 1. Add edge normalization in extract.py

  **What to do**:
  At line 3526 in `/opt/homebrew/lib/python3.14/site-packages/graphify/extract.py`, replace:
  ```python
  existing_pairs = {(e["source"], e["target"]) for e in all_edges}
  ```
  With:
  ```python
  # Normalize edges: some extractors or cross-file resolution may produce
  # edges with "from"/"to" keys instead of the canonical "source"/"target".
  for e in all_edges:
      if "source" not in e and "from" in e:
          e["source"] = e["from"]
      if "target" not in e and "to" in e:
          e["target"] = e["to"]

  existing_pairs = {(e["source"], e["target"]) for e in all_edges if "source" in e and "target" in e}
  ```

  **Must NOT do**:
  - Do not modify build.py
  - Do not change cached files

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Trivial 4-line change, no complexity
  - **Skills**: []
    - None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Blocks**: Task 2

  **References**:
  - `extract.py:3526` — current buggy line
  - `build.py:63-66` — reference for from/to remapping

  **Acceptance Criteria**:
  - [ ] Fix applied to extract.py line 3526

  **QA Scenarios**:

  \`\`\`
  Scenario: Verify edge normalization fix
    Tool: Bash
    Preconditions: pickleball-godot repo at current state
    Steps:
      1. Run: /opt/homebrew/bin/python3.14 -c "
from graphify.extract import extract
from graphify.detect import detect
from pathlib import Path
detected = detect(Path('.'))
code_files = [Path(f) for f in detected['files']['code']]
result = extract(code_files, cache_root=Path('.'))
print(f'Nodes: {len(result[\"nodes\"])}, Edges: {len(result[\"edges\"])}')"
    Expected Result: No KeyError, prints node/edge counts
    Failure Indicators: KeyError 'source' at extract.py line 3526
    Evidence: .sisyphus/evidence/task-1-extract-success.txt
  \`\`\`

  **Commit**: NO

---

## Final Verification Wave

- [ ] F1. **Full Pipeline Test** — `unspecified-high`
  Run `graphify update .` and verify it completes without KeyError. Check graph.json output.

  **QA Scenarios**:

  \`\`\`
  Scenario: Full graphify update pipeline
    Tool: Bash
    Preconditions: pickleball-godot repo, extract fix applied
    Steps:
      1. cd /Users/arjomagno/Documents/github-repos/pickleball-godot
      2. /opt/homebrew/bin/python3.14 -m graphify update .
    Expected Result: Completes without error, produces graph.json
    Failure Indicators: KeyError, traceback, missing output
    Evidence: .sisyphus/evidence/task-f1-pipeline-success.txt

  Scenario: Verify graph output
    Tool: Bash
    Preconditions: graphify update completed
    Steps:
      1. wc -l graphify-out/graph.json
      2. /opt/homebrew/bin/python3.14 -c "import json; g=json.load(open('graphify-out/graph.json')); print(f'Nodes: {len(g[\"nodes\"])}, Edges: {len(g[\"edges\"])}')"
    Expected Result: Nodes > 2000, Edges > 0
    Failure Indicators: Empty graph, 0 nodes
    Evidence: .sisyphus/evidence/task-f1-graph-output.txt
  \`\`\`

---

## Success Criteria

### Verification Commands
```bash
/opt/homebrew/bin/python3.14 -c "
from graphify.extract import extract
from graphify.detect import detect
from pathlib import Path
detected = detect(Path('.'))
code_files = [Path(f) for f in detected['files']['code']]
result = extract(code_files, cache_root=Path('.'))
print(f'Nodes: {len(result[\"nodes\"])}, Edges: {len(result[\"edges\"])}')"
# Expected: Nodes > 2000, Edges > 0 (no KeyError)
```

### Final Checklist
- [ ] Fix applied to extract.py line 3526
- [ ] `graphify update .` completes without KeyError
- [ ] graph.json has > 2000 nodes from GDScript files
