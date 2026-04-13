# SecondBrain Upgrade — Full Documentation + Gap Analysis Plan

## TL;DR

> **Quick Summary**: Create comprehensive documentation for `secondbrain-upgrade/` contrasting it against `secondbrain-sqlite/` (the original source), identifying what was built, what was left behind, and what gaps remain.
>
> **Deliverables**:
> - Full architecture documentation for `secondbrain-upgrade/`
> - Gap analysis: what `secondbrain-sqlite` had that upgrade is missing
> - Structured comparison: schema, retrieval, pillars, learning, workflow, ops
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES — Wave 1 (D1+D2 parallel), Wave 2 (D3), Wave 3 (D4+D5 sequential)
> **Critical Path**: D1 → D2 → D3 → D4 → D5

---

## Context

### Original Request
"plan create a full documentation for the secondbrain upgraded and contrast it to memforge so the user can see what are the gaps or coverage"

### Key Discovery
- `~/.claude/memforge/` does **not exist**
- `secondbrain-sqlite/` is the **original source system** — SQLite-based, 6-pillar, no sleep cycle
- `secondbrain-upgrade/` is the **new system** — 10-phase sleep cycle, 4-pillar auto-segregation, Ollama-backed semantic, outcome learning, audit chain
- The user likely conflates "memforge" with the new `secondbrain-upgrade/` system

---

## Work Objectives

### Core Objective
Create a single canonical comparison document that shows:
1. What `secondbrain-upgrade/` contains (full architecture)
2. What `secondbrain-sqlite/` originally had (capability baseline)
3. What was **carried forward** vs **left behind** in the upgrade
4. What **gaps** remain in the upgrade (features in source but not ported)

### Concrete Deliverables
- [ ] `secondbrain-upgrade/docs/COMPARISON.md` — Full comparison document

### Definition of Done
- [ ] All major functional areas compared (schema, retrieval, pillars, learning, workflow, ops)
- [ ] Every source capability either marked as: ✅ PORTED / ❌ NOT PORTED / 🟡 PARTIAL
- [ ] Each gap has a brief explanation of why (if known)
- [ ] Document is readable and actionable

### Must Have
- Side-by-side comparison of pillar systems (6-pillar source → 4-pillar upgrade)
- Schema diff: source schema.sql vs upgrade's 4 incremental SQL files
- Retrieval comparison: BM25+FTS5 source vs semantic+Ollama upgrade
- Gap list for unported features (vault sync, context tree, facts, tags/links)
- Sleep cycle architecture fully documented for first time

### Must NOT Have
- Implementation code in the document
- Repetitive content already in CLAUDE.md (reference CLAUDE.md instead)
- Speculation about why things weren't ported without evidence

---

## Verification Strategy

### QA Policy
- Agent-executed verification by reading source files to verify accuracy
- No automated tests needed (documentation task)
- Human review: user reads COMPARISON.md and confirms it matches their understanding

---

## Execution Strategy

### Wave 1 (Start Immediately — parallel mapping):

**D1: Map upgrade codebase structure** — `unspecified-low`
- Read every major module in `secondbrain-upgrade/`
- Document: phases, pillars, retrieval, learning, schema, scheduler, ops modules
- Output: structured notes for each functional area

**D2: Map source codebase structure** — `unspecified-low`
- Read `secondbrain-sqlite/schema.sql`, `pillar-classifier.mjs`, `query.mjs`, `sync.mjs`, `create-note.mjs`
- Document: vault sync, FTS5/BM25 search, 6-pillar system, facts, context tree, tags/links
- Output: structured notes for each functional area

### Wave 2 (After Wave 1):

**D3: Analyze gaps across all functional areas** — `unspecified-low`
- Compare D1 notes vs D2 notes across: schema, retrieval, pillars, learning, workflow, ops
- Classify each capability: ✅ PORTED / ❌ NOT PORTED / 🟡 PARTIAL
- Identify root causes if known (from CLAUDE.md comments, code comments)
- Output: gap analysis matrix

### Wave 3 (After Wave 2 — writing):

**D4: Write comprehensive comparison document** — `writing`
- Write `secondbrain-upgrade/docs/COMPARISON.md`
- Follow structure below
- Output: complete markdown document

**D5: Verify documentation accuracy** — `unspecified-low`
- Cross-check every claim in COMPARISON.md against actual source files
- Fix any inaccuracies
- Output: verified document

---

## TODOs

- [ ] D1. Map upgrade codebase structure

  **What to do**:
  - Read all major modules in `secondbrain-upgrade/`: `db.js`, `llm.js`, `hot-events.js`, `health.js`, `contradiction.js`, `procedural.js`, `semantic-search.js`, `embeddings.js`
  - Read all sleep-cycle phase files: `sleep-cycle/index.js` + all `phases/*.js`
  - Read pillar modules: `pillar-classifier.mjs`, `pillar-centroids.mjs`, `pillar-learning.mjs`, `pillar-retrieval.mjs`
  - Read schema files: all `schema/*.sql`
  - Read ops modules: `scheduler/idle-trigger.js`, `retrieval/outcome.js`
  - Document each module's purpose, key functions, and how it fits into the architecture

  **Must NOT do**:
  - Don't read test files (not needed for documentation)
  - Don't read log files

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Reading and summarizing 20+ files is low-complexity work requiring breadth
  - **Skills**: []
    - None needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with D2)
  - **Blocks**: D3, D4
  - **Blocked By**: None

  **References**:

  **Pattern References** (existing code to follow):
  - `~/.claude/secondbrain-upgrade/CLAUDE.md` — Existing doc showing architecture overview

  **Source Files** (must read and summarize):
  - `~/.claude/secondbrain-upgrade/sleep-cycle/index.js` — Phase orchestrator
  - `~/.claude/secondbrain-upgrade/sleep-cycle/phases/*.js` — All 11 phase files
  - `~/.claude/secondbrain-upgrade/pillar-*.mjs` — All 4 pillar modules
  - `~/.claude/secondbrain-upgrade/schema/*.sql` — All 4 schema upgrade files
  - `~/.claude/secondbrain-upgrade/{db,llm,health,hot-events,contradiction,procedural,semantic-search,embeddings}.js` — Core modules
  - `~/.claude/secondbrain-upgrade/scheduler/idle-trigger.js` — Scheduler
  - `~/.claude/secondbrain-upgrade/retrieval/outcome.js` — Retrieval outcome loop

  **Acceptance Criteria**:
  - [ ] All major modules read and summarized
  - [ ] Each module has: filename, size, purpose, key functions listed
  - [ ] Architecture diagram description (text-based) created
  - [ ] Notes ready for gap analysis

  **QA Scenarios**:

  Scenario: Completeness check
    Tool: Bash
    Preconditions: All module files exist
    Steps:
      1. Count total .js/.mjs files in secondbrain-upgrade/ (excluding node_modules, tests, logs)
      2. Verify each major module was read
    Expected Result: All major modules accounted for
    Evidence: file list

- [ ] D2. Map source codebase structure

  **What to do**:
  - Read `secondbrain-sqlite/schema.sql` — full DDL for source system
  - Read `secondbrain-sqlite/pillar-classifier.mjs` — 6-pillar classification system
  - Read `secondbrain-sqlite/query.mjs` — BM25+FTS5 search, stats, facts
  - Read `secondbrain-sqlite/sync.mjs` — vault sync logic
  - Read `secondbrain-sqlite/create-note.mjs` — note ingestion workflow
  - Document each module's purpose, key functions, tables, and capabilities

  **Must NOT do**:
  - Don't read backups or logs
  - Don't read package.json (not needed)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Reading and summarizing 5 files is straightforward work
  - **Skills**: []
    - None needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with D1)
  - **Blocks**: D3, D4
  - **Blocked By**: None

  **References**:

  **Pattern References** (existing code to follow):
  - `~/.claude/secondbrain-sqlite/schema.sql` — Source schema (already read)
  - `~/.claude/secondbrain-sqlite/pillar-classifier.mjs` — Source pillars (already read)
  - `~/.claude/secondbrain-sqlite/query.mjs` — Source query layer (already read)

  **Source Files** (must read and summarize):
  - `~/.claude/secondbrain-sqlite/schema.sql` — vault_notes, vault_fts (FTS5 BM25), vault_tags, vault_links, sync_state, context_tree, context_fts, facts, stats
  - `~/.claude/secondbrain-sqlite/pillar-classifier.mjs` — 6-pillar system: Claude, ArjoMagno, ArjoTech, ArjoStyle, ArjoTirol, Resources
  - `~/.claude/secondbrain-sqlite/query.mjs` — searchVault (BM25), searchContext, getNote, getFacts, getStats, getTags, getDomains
  - `~/.claude/secondbrain-sqlite/sync.mjs` — vault sync (needs reading)
  - `~/.claude/secondbrain-sqlite/create-note.mjs` — note creation (needs reading)

  **Acceptance Criteria**:
  - [ ] All 5 source files read and summarized
  - [ ] All source tables documented
  - [ ] All source capabilities listed
  - [ ] Notes ready for gap analysis

  **QA Scenarios**:

  Scenario: Completeness check
    Tool: Bash
    Preconditions: All source files exist
    Steps:
      1. List all .mjs files in secondbrain-sqlite/
      2. Verify each was read
    Expected Result: All 5 key files accounted for
    Evidence: file list

- [ ] D3. Analyze gaps across all functional areas

  **What to do**:
  - Compare D1 notes (upgrade) vs D2 notes (source) across 6 functional areas
  - For each capability area, determine: PORTED / NOT PORTED / PARTIAL / NEW
  - Document what specifically was carried forward vs left behind
  - Identify which gaps are significant (workflow-breaking) vs minor

  **Functional Areas to Compare**:
  1. **Schema/Storage**: tables, indexes, FTS, triggers
  2. **Retrieval**: search, ranking, recall
  3. **Pillar Classification**: keyword system, number of pillars, semantic fallback
  4. **Learning**: outcome tracking, weight adaptation, feedback loops
  5. **Workflow**: sync, create-note, update, delete
  6. **Ops**: scheduling, health monitoring, audit, error handling

  **Must NOT do**:
  - Don't speculate without evidence from source files
  - Don't claim something was ported without checking

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Comparison analysis across 6 areas is straightforward but requires attention to detail
  - **Skills**: []
    - None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 2 (sequential after Wave 1)
  - **Blocks**: D4, D5
  - **Blocked By**: D1, D2

  **References**:

  **Pattern References** (existing code to follow):
  - D1 notes — upgrade structure
  - D2 notes — source structure
  - `~/.claude/secondbrain-upgrade/CLAUDE.md` lines 142-156 — known resolved issues

  **Acceptance Criteria**:
  - [ ] Gap analysis matrix created for all 6 functional areas
  - [ ] Each gap has: what was in source, what's in upgrade (if anything), status
  - [ ] Clear ✅/❌/🟡 classification per capability
  - [ ] Notes ready for D4 document writing

  **QA Scenarios**:

  Scenario: Gap matrix completeness
    Tool: Bash
    Preconditions: D1 and D2 notes exist
    Steps:
      1. Verify 6 functional areas all have gap entries
      2. Verify each entry has source state and upgrade state
    Expected Result: 6 areas × N capabilities covered
    Evidence: gap matrix

- [ ] D4. Write comprehensive comparison document

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/docs/` directory
  - Write `COMPARISON.md` with full structure defined in Success Criteria
  - Include all gap analysis findings from D3
  - Make it readable and actionable for the user

  **Must NOT do**:
  - Don't copy implementation code
  - Don't duplicate CLAUDE.md content (reference it instead)
  - Don't leave any "TBD" sections

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Writing structured documentation with analysis and recommendations
  - **Skills**: []
    - None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3
  - **Blocks**: D5
  - **Blocked By**: D3

  **References**:

  **Pattern References** (existing code to follow):
  - `~/.claude/secondbrain-upgrade/CLAUDE.md` — reference for upgrade architecture
  - D3 gap analysis notes — source for comparison content

  **Document Target**:
  - `~/.claude/secondbrain-upgrade/docs/COMPARISON.md`

  **Acceptance Criteria**:
  - [ ] All 6 sections from Success Criteria structure written
  - [ ] Capability matrix table complete with ✅/❌/🟡 status
  - [ ] Document is self-contained and readable
  - [ ] No placeholder text or TBDs

  **QA Scenarios**:

  Scenario: Readability review
    Tool: Bash
    Preconditions: COMPARISON.md created
    Steps:
      1. Count words in COMPARISON.md (should be >2000 for comprehensive doc)
      2. Verify all section headers from structure exist
      3. Verify capability matrix table exists and has >15 rows
    Expected Result: Document is substantial and complete
    Evidence: word count, section check

- [ ] D5. Verify documentation accuracy

  **What to do**:
  - Read COMPARISON.md
  - For each factual claim, verify against actual source files
  - Fix any inaccuracies found
  - Mark D4 complete once verified

  **Must NOT do**:
  - Don't change structure, only fix accuracy issues

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Spot-checking claims against source is low-complexity verification
  - **Skills**: []
    - None needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3
  - **Blocks**: None (final task)
  - **Blocked By**: D4

  **References**:

  **Pattern References** (existing code to follow):
  - `secondbrain-upgrade/` source files — for upgrade claims
  - `secondbrain-sqlite/` source files — for source claims

  **Acceptance Criteria**:
  - [ ] Key factual claims spot-checked against source
  - [ ] Any inaccuracies fixed
  - [ ] Document ready for user review

  **QA Scenarios**:

  Scenario: Spot-check claims
    Tool: Read
    Preconditions: COMPARISON.md exists
    Steps:
      1. Read a sample of 10 factual claims from the document
      2. Verify each against actual source file
    Expected Result: >= 8/10 accurate
    Evidence: verification notes

---

## Final Verification Wave

- [ ] F1. **Accuracy check** — `unspecified-low`
  Read COMPARISON.md claims, verify against source files line-by-line.
  Check: pillar counts, schema tables, phase count, capability matrix accuracy.
  Output: `Claims verified [N/N] | inaccuracies [N] | VERDICT`

---

## Commit Strategy

- **1**: `docs(COMPARISON): add full documentation + gap analysis` - `docs/COMPARISON.md`

---

## Success Criteria

### Document Structure
```
docs/COMPARISON.md
├── 1. Executive Summary
│   ├── What is secondbrain-upgrade?
│   ├── What was the source (secondbrain-sqlite)?
│   └── How to read this document
├── 2. Architecture Overview (upgrade)
│   ├── Sleep Cycle (10 phases)
│   ├── Pillar System
│   ├── Retrieval + Learning
│   └── Ops (scheduler, health, audit)
├── 3. Side-by-Side Comparison
│   ├── Schema
│   ├── Retrieval
│   ├── Pillar Classification
│   ├── Learning System
│   ├── Workflow (sync, create, update)
│   └── Ops & Scheduling
├── 4. Gap Analysis
│   ├── NOT PORTED (source features missing in upgrade)
│   ├── PARTIAL (incompletely ported)
│   └── NEW (only in upgrade)
├── 5. Capability Matrix
│   └── Table: Feature → Source → Upgrade → Status
└── 6. Recommendations
    └── Which gaps to fill first
```
