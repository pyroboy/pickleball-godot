# Handoff Template: How to Create Effective Handoff Prompts

## Purpose

This document captures the process for creating effective handoffs to Opus or other agents. Use this as a template for any future handoff — adapt the phases to your specific problem.

---

## Phase 1: Parallel Context Gathering (DO THIS FIRST)

### Why Parallel Research Matters

Single-threaded research wastes time. When investigating a bug or feature, launch multiple agents simultaneously:

1. **Explore agents** — internal codebase search
2. **Librarian agents** — external documentation/research
3. **Direct tools** — grep, ast-grep, glob for targeted searches
4. **Never** re-search what an agent is already searching

### Parallel Research Commands

```bash
# Explore agents (internal codebase)
task(subagent_type="explore", run_in_background=true,
    prompt="Find ALL files related to [TOPIC]. Search for [keywords]. Return file paths and brief descriptions of each file's role.")

task(subagent_type="explore", run_in_background=true,
    prompt="Find how [SPECIFIC FEATURE/INPUT] is handled. Trace the flow from trigger to effect.")

task(subagent_type="explore", run_in_background=true,
    prompt="Find [DATA HANDLING/STATE MANAGEMENT] code. Look for [related patterns].")

# Librarian agents (external knowledge)
task(subagent_type="librarian", run_in_background=true,
    prompt="Research [LIBRARY/FRAMEWORK] best practices for [SPECIFIC TASK]. Focus on production patterns, not tutorials.")

# Direct searches (run in parallel with agents)
grep(pattern="[pattern]", include="*.gd", path="...")
ast_grep_search(pattern="function_name($ARG)", lang="gdscript", paths=["/path"])
```

### Research Coverage Checklist

Adapt to your problem domain:

- [ ] **Input handling** — How does the trigger reach the system?
- [ ] **Core logic** — What calculations/algorithms are involved?
- [ ] **Data flow** — How does state propagate through the system?
- [ ] **UI/Output** — How does the system present results?
- [ ] **Edge cases** — What happens at boundaries or with invalid input?
- [ ] **External dependencies** — What libraries/APIs are used?

---

## Phase 2: Code Reading & Architecture Mapping

### Read Files in Priority Order

**Tier 1 — Must Read Completely:**
- Files containing the bug/feature
- Core state management
- Entry point handlers

**Tier 2 — Read for Context:**
- Supporting utilities
- Data models
- Configuration

### Architecture Documentation Template

```markdown
## Component Overview

| Component | File | Role |
|-----------|------|------|
| Name | file.ext | What it does |

## Data Flow

Trigger → Processing → Output chain:

```
1. [Trigger event]
    ↓
2. [What handles it]
    ↓
3. [What data flows]
    ↓
4. [Output/effect]
```

## Key Functions

| Function | Lines | Purpose |
|----------|-------|---------|
| name() | x-y | desc |

## Problem Areas Identified

1. [Specific issue with file:line reference]
2. [Another issue]
```

---

## Phase 3: Question Generation

### Question Categories

**A. Math/Logic Correctness**
- Are calculations correct for all edge cases?
- Is the algorithm appropriate for the problem?
- Are there off-by-one or boundary errors?

**B. Data Synchronization**
- Are multiple data sources in sync?
- Can there be timing/lag issues?
- Is there a race condition?

**C. Null Checks**
- What happens when expected values are missing?
- Are there silent failures?
- Are assumptions validated?

**D. Boundary Conditions**
- What happens at extreme values?
- What about overlapping/interfering elements?
- Is there input validation?

**E. Naming Consistency**
- Do names match across files?
- Are there typos or mismatches?
- Is terminology used consistently?

### Question Format

```markdown
**Q#[Category]:** [Specific question]

Context: [relevant code snippet or file:line]
Issue: [why this might be a problem]
```

---

## Phase 4: Prompt Construction

### Template Structure

```markdown
# Handoff Prompt: [Short Title]

## Problem Statement
[1-2 sentences: what is broken or needs to be built, observed symptoms]

## Files to Examine (PRIMARY)
### 1. [File Name]
**Why critical:** [one line]

Key areas:
- Lines X-Y: [function/event] — [what it does]
- Lines X-Y: [function/event] — [what it does]

Questions:
1. [specific question about this file]
2. [another question]

### 2. [File Name]
[...same format...]

## Files to Examine (SECONDARY)
[Same format, lower priority]

## Architecture Overview
[Simplified diagram or table of components]

## Research Required
1. [External knowledge needed - library docs, best practices, etc.]
2. [Another area]

## Constraints
- DO [things you must preserve]
- DON'T [break X]

## Verification Criteria
How to know the fix is correct:
1. [Test case 1]
2. [Test case 2]
```

### Writing Guidelines

1. **Be specific about line numbers** — "Line 168" not "around line 170"
2. **Include actual code snippets** — cut/paste the relevant code
3. **State assumptions explicitly** — "Assumes X never changes during Y"
4. **Flag uncertainty** — "Not sure if X or Y — investigate both"
5. **Prioritize** — PRIMARY files are critical; SECONDARY are context

---

## Phase 5: Self-Audit Before Sending

### Prompt Quality Checklist

- [ ] Did I provide **specific file paths** with line numbers?
- [ ] Did I explain **why** each file is important?
- [ ] Did I include **actual code snippets** for key functions?
- [ ] Did I generate **10+ specific questions** for investigation?
- [ ] Did I list **external research** needed?
- [ ] Did I specify **constraints** (what NOT to break)?
- [ ] Did I define **verification criteria**?
- [ ] Did I run **parallel research agents** instead of sequential?

### Prompt Weakness Detection

**Weak prompt indicators:**
- "Fix the bug" (too vague, no file refs)
- "Check the code" (which file?)
- No questions — just tells the agent to "figure it out"
- No verification criteria — how would we know if fixed?

**Strong prompt indicators:**
- File paths with line numbers
- Code snippets included
- Specific questions with context
- Research areas identified
- Constraints clearly stated
- Test cases defined

---

## Example: Before/After

### BEFORE (Weak Prompt)
```
"The hover functionality is broken. Fix it."
```

Problems:
- No file paths
- No specific symptoms
- No context about architecture
- No research guidance
- No constraints
- No verification criteria

### AFTER (Strong Prompt)
```
## Problem Statement
Hover detection highlights wrong elements. Observed: hovering over A shows B's label.

## Files to Examine (PRIMARY)
### 1. `src/hover_controller.ts`
**Critical — contains raycast logic at lines 45-78**

Key code:
```typescript
function raycast(rayOrigin: Vector3, rayDir: Vector3): string {
    for (const target of targets) {
        const distance = computeDistance(target.position, rayOrigin, rayDir);
        if (distance < RADIUS && distance < closestDist) {
```

Questions:
1. Is RADIUS=0.18 appropriate for all target sizes?
2. Could the distance calculation have edge cases?
[... continues with more detail ...]
```

---

## Parallel Research Template (For Future Handoffs)

When creating a new handoff, run parallel searches:

```bash
# Explore agents (internal codebase)
task(subagent_type="explore", run_in_background=true,
    prompt="Find files related to [TOPIC]. Return file paths with descriptions.")

# Librarian agents (external knowledge)
task(subagent_type="librarian", run_in_background=true,
    prompt="Research [library/framework] best practices for [specific task].")

# Direct searches
grep(pattern="[pattern]", include="*.ext", path="/project/path")
ast_grep_search(pattern="function_name($ARG)", lang="typescript", paths=["/path"])
```

---

## File Output Location

Save handoff prompts to:
```
docs/handovers/[feature-name]-[issue].md
```

Save this template to:
```
docs/templates/handoff-template.md
```

(End of file)
