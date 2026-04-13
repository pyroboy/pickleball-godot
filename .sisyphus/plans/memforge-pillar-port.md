# MemForge 4-Pillar Auto-Segregation Port

## TL;DR

> **Quick Summary**: Port DuckDB's 4-pillar keyword classification system (magno/tech/style/tirol) into MemForge/SQLite at `~/.claude/secondbrain-upgrade/`, with Ollama semantic fallback and outcome-learning hooks into retrieval.
>
> **Deliverables**:
> - `pillar-classifier.mjs` — PILLAR_SEEDS (~245 keywords) + `classifyKeyword()` + `classifyKeywordSemantic()`
> - `pillar-centroids.mjs` — PillarCentroids with PILLAR_CENTROID_PHRASES + Ollama embedding
> - `pillar-learning.mjs` — `learnFromOutcome()` + `bumpPillarWeight()` → SQLite `pillar_stats`
> - `pillar-retrieval.mjs` — `applyPillarWeightBoost()` for ranking
> - `sleep-cycle/phases/pillar-segregation.js` — Phase 7 sleep cycle module
> - Schema upgrade: `upgrade-v4-pillar-segregation.sql`
> - 30+ new validation tests
>
> **Estimated Effort**: Large
> **Parallel Execution**: YES — 3 waves
> **Critical Path**: Schema (C1) → PILLAR_SEEDS (C2) → Semantic (C3+C4) → Learning (C5) → Retrieval (C6) → Phase7 (C7) → Tests (C8) → Docs (C9)

---

## Context

### Original Request
Port DuckDB's 4-pillar auto-segregation system to MemForge. DuckDB tech is outdated — target is SQLite at `~/.claude/secondbrain-upgrade/`. Must include: keyword sync, Ollama semantic fallback, outcome learning hooked into retrieval.

### Interview Summary
**Key Discussions**:
- DuckDB `pillar_weights` table is irrelevant/broken — do not port it as-is
- MemForge already has Ollama at `localhost:11434` via `embeddings.js`
- secondbrain-sqlite's separate 6-pillar `pillar-classifier.mjs` is also irrelevant — use DuckDB's 4 pillars (magno/tech/style/tirol)
- Outcome learning (`learnFromOutcome`) must hook into `retrieval/outcome.js` — existing hook point confirmed
- "Pillar weights" = NOT DuckDB `pillar_weights` table — instead: per-pillar keyword frequency/stats in SQLite

**Research Findings**:
- DuckDB `bumpPillarWeight()` has a silent-failure bug — UPDATE with 0 rows doesn't throw, catch block never reached, table stays empty
- Two separate pillar systems found: DuckDB `pillar_weights` (broken, 0 rows) vs secondbrain-sqlite `pillar-classifier.mjs` (6 pillars, separate system)
- MemForge already has Ollama client in `embeddings.js` — reuse it, don't duplicate

### Metis Review
**Identified Gaps** (addressed):
- Gap 1: `pillar_stats` schema design — resolved: separate `pillar_stats` table with `(pillar, keyword, frequency, last_updated)` from DuckDB's collapsed design
- Gap 2: Ollama offline graceful degradation — resolved: `classifyKeywordSemantic` falls back to 'tech' when Ollama unavailable
- Gap 3: `learnFromOutcome` hook location — resolved: hook into `retrieval/outcome.js` at existing outcome-processing call site
- Gap 4: Stop word handling — resolved: strip stop words before keyword classification in `learnFromOutcome`
- Gap 5: Test isolation — resolved: tests use temp DB, run independently

---

## Work Objectives

### Core Objective
Port 4-pillar classification (magno/tech/style/tirol) from DuckDB into MemForge with: exact keyword match, Ollama semantic fallback, and outcome-learning that adjusts pillar weights over time.

### Concrete Deliverables
- `~/.claude/secondbrain-upgrade/pillar-classifier.mjs` — PILLAR_SEEDS + `classifyKeyword()`
- `~/.claude/secondbrain-upgrade/pillar-centroids.mjs` — PillarCentroids + `classifyKeywordSemantic()`
- `~/.claude/secondbrain-upgrade/pillar-learning.mjs` — `learnFromOutcome()` + `bumpPillarWeight()`
- `~/.claude/secondbrain-upgrade/pillar-retrieval.mjs` — `applyPillarWeightBoost()`
- `~/.claude/secondbrain-upgrade/sleep-cycle/phases/pillar-segregation.js` — Phase 7 module
- `~/.claude/secondbrain-upgrade/schema/upgrade-v4-pillar-segregation.sql` — new tables
- `~/.claude/secondbrain-upgrade/CLAUDE.md` — updated documentation

### Definition of Done
- [ ] `bun test` → 100+ tests pass (currently 81/82)
- [ ] All new modules export functions that can be imported and called
- [ ] Ollama offline → falls back to keyword-only classification gracefully
- [ ] `learnFromOutcome` actually writes to `pillar_stats` table
- [ ] Phase 7 runs without breaking existing sleep cycle

### Must Have
- Keyword sync: all ~245 DuckDB PILLAR_SEEDS keywords verbatim
- Ollama semantic: cosine similarity vs 4 centroids
- Outcome learning: adjusts pillar keyword frequencies over time
- Retrieval boost: pillar-aware ranking in search results

### Must NOT Have
- NO DuckDB `pillar_weights` table port — use SQLite `pillar_stats` instead
- NO 6-pillar system from secondbrain-sqlite
- NO breaking changes to existing sleep cycle phases 1-6
- NO duplicate Ollama initialization — reuse `embeddings.js`

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES
- **Automated tests**: Tests-after (adding to existing validation suite)
- **Framework**: bun test + Node.js test runner at `~/.claude/secondbrain-upgrade/tests/`
- **Test files**: `tests/validation/` — follow existing pattern with `fw.test()` factory

### QA Policy
Every task includes agent-executed QA via:
- **Unit tests**: `bun test tests/validation/*.js` — assert function outputs
- **Integration**: Import all new modules, call exported functions with real data
- **Evidence**: test output logs showing pass/fail counts

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately - foundation):
├── C1: Schema upgrade SQL
├── C2: PILLAR_SEEDS + classifyKeyword()
├── C3: Ollama cosineSimilarity + PillarCentroids
└── C4: classifyKeywordSemantic() chaining

Wave 2 (After C2+C3 - core logic):
├── C5: learnFromOutcome() + bumpPillarWeight()
├── C6: applyPillarWeightBoost() retrieval
└── C7: Phase 7 pillar-segregation.js module

Wave 3 (After Wave 2 - integration + tests):
├── C8: Comprehensive validation tests (30+ tests)
└── C9: CLAUDE.md documentation update
```

### Critical Path
C1 → C2 → C3 → C4 → C5 → C6 → C7 → C8 → C9

---

## TODOs

- [ ] **C1: Schema Upgrade — `pillar_stats` + `note_pillars` tables**

  **What to do**:
  - Create `schema/upgrade-v4-pillar-segregation.sql` with:
    - `pillar_stats (pillar TEXT, keyword TEXT, frequency INTEGER DEFAULT 1, last_updated TIMESTAMP)` — PRIMARY KEY (pillar, keyword)
    - `note_pillars (note_id TEXT, pillar TEXT, confidence REAL, assigned_at TIMESTAMP)` — PRIMARY KEY (note_id, pillar)
  - Add upgrade registration in `schema/index.js` or equivalent

  **Must NOT do**:
  - Do NOT create a `pillar_weights` table — that was DuckDB's broken design
  - Do NOT alter existing `notes` or `context_tree_nodes` tables

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: SQL migration file, straightforward schema additions
  - **Skills**: []
    - No specific skills needed for SQL schema

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with C2, C3, C4)
  - **Blocks**: C5, C7
  - **Blocked By**: None (can start immediately)

  **References**:
  - `~/.claude/secondbrain-upgrade/schema/upgrade-v1.sql` — existing schema pattern to follow
  - `~/.claude/Documents/github-repos/claude_agent_teams_ui/src/main/services/infrastructure/RelayDuckDB.ts` — for reference only, do NOT port

  **Acceptance Criteria**:
  - [ ] File created: `schema/upgrade-v4-pillar-segregation.sql`
  - [ ] Two tables defined: `pillar_stats`, `note_pillars`
  - [ ] `bun test tests/validation/` → still 81/82 (no regressions)

  **QA Scenarios**:

  Scenario: SQL file syntax is valid
    Tool: Bash
    Steps:
      1. Read the SQL file content
      2. Parse with SQLite CLI: `sqlite3 :memory: < schema/upgrade-v4-pillar-segregation.sql`
    Expected Result: No syntax errors, two tables created
    Evidence: .sisyphus/evidence/c1-sql-syntax.txt

- [ ] **C2: Port PILLAR_SEEDS + `classifyKeyword()`**

  **What to do**:
  - Create `pillar-classifier.mjs` with:
    - `PILLARS = ['magno', 'tech', 'style', 'tirol']`
    - `PILLAR_SEEDS: Record<PillarName, ReadonlySet<string>>` — all ~245 keywords verbatim from DuckDB
    - `classifyKeyword(kw: string): PillarName` — exact match → return pillar, 4-char prefix match → return pillar, else 'tech'
  - Extract ALL keywords from DuckDB `pillar_weights` seeds (magno ~60, tech ~60, style ~60, tirol ~60) — confirmed exact transfer
  - Export all for use by other modules

  **Must NOT do**:
  - Do NOT add Ollama calls here — that's C3/C4
  - Do NOT change existing sleep cycle behavior
  - Do NOT use the 6-pillar system from secondbrain-sqlite

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Straight keyword port, no algorithmic complexity
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with C1, C3, C4)
  - **Blocks**: C4 (classifyKeywordSemantic chains from classifyKeyword)
  - **Blocked By**: None (can start immediately)

  **References**:
  - `~/.claude/Documents/github-repos/claude_agent_teams_ui/src/main/services/infrastructure/RelayDuckDB.ts` — PILLAR_SEEDS source (exact keywords to copy)
  - `~/.claude/secondbrain-upgrade/pillar-classifier.mjs` — DOES NOT EXIST YET (this is the creation)

  **Acceptance Criteria**:
  - [ ] File created: `pillar-classifier.mjs`
  - [ ] `PILLAR_SEEDS` contains all 4 pillars with ReadonlySet<string>
  - [ ] `classifyKeyword('code')` → 'tech'
  - [ ] `classifyKeyword('empathy')` → 'magno'
  - [ ] `classifyKeyword('design')` → 'style'
  - [ ] `classifyKeyword('revenue')` → 'tirol'
  - [ ] `classifyKeyword('unknown_xyz')` → 'tech' (fallback)
  - [ ] `classifyKeyword('emp')` → 'magno' (4-char prefix match)

  **QA Scenarios**:

  Scenario: classifyKeyword returns correct pillar for seed keywords
    Tool: Bash
    Preconditions: Node.js REPL with pillar-classifier.mjs imported
    Steps:
      1. Import `classifyKeyword`, `PILLAR_SEEDS`
      2. Test each pillar's first 3 keywords: `classifyKeyword(kw)`
      3. Assert returned pillar matches expected
    Expected Result: All assertions pass
    Evidence: .sisyphus/evidence/c2-keyword-classification.txt

  Scenario: Unknown keyword falls back to 'tech'
    Tool: Bash
    Steps:
      1. `classifyKeyword('asdfghjklqwerty')` → expect 'tech'
      2. `classifyKeyword('zzzz_not_a_keyword')` → expect 'tech'
    Expected Result: Both return 'tech'
    Evidence: .sisyphus/evidence/c2-unknown-fallback.txt

  Scenario: 4-char prefix match works
    Tool: Bash
    Steps:
      1. `classifyKeyword('empo')` → should match 'empo' prefix of 'empathy' → 'magno'
      2. `classifyKeyword('techq')` → should match 'tech' prefix → 'tech'
    Expected Result: Both return correct pillar via prefix
    Evidence: .sisyphus/evidence/c2-prefix-match.txt

- [ ] **C3: Ollama cosineSimilarity + PillarCentroids**

  **What to do**:
  - Add `cosineSimilarity(a: number[], b: number[]): number` to `embeddings.js`
  - Create `pillar-centroids.mjs` with:
    - `PILLAR_CENTROID_PHRASES` — 4 centroid strings (50-word each) from DuckDB source
    - `PillarCentroids` class — lazy-init, embeds centroids via Ollama once, caches them
    - Cache stored in memory (Map), not persisted across restarts
  - Ollama endpoint: reuse `embeddings.js` client at `localhost:11434`

  **Must NOT do**:
  - Do NOT duplicate Ollama client — import from `embeddings.js`
  - Do NOT re-embed centroids on every call — must cache
  - Do NOT use a persistent cache file — in-memory only

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Ollama integration + vector math — moderate complexity
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with C1, C2, C4)
  - **Blocks**: C4
  - **Blocked By**: None (can start immediately)

  **References**:
  - `~/.claude/secondbrain-upgrade/embeddings.js` — Ollama client to reuse
  - `~/.claude/Documents/github-repos/claude_agent_teams_ui/src/main/services/infrastructure/RelayDuckDB.ts` — PILLAR_CENTROID_PHRASES source

  **Acceptance Criteria**:
  - [ ] `cosineSimilarity([1,0,0], [1,0,0])` → ~0.999 (angle=0°)
  - [ ] `cosineSimilarity([1,0,0], [0,1,0])` → ~0.0 (orthogonal)
  - [ ] `cosineSimilarity([1,1,0], [1,0,1])` → ~0.5 (60°)
  - [ ] `PillarCentroids` class exists with `getCentroid(pillar)` method
  - [ ] `getCentroid('tech')` returns number[] array (embedded vector)
  - [ ] Second call to `getCentroid('tech')` uses cache (no second Ollama call)

  **QA Scenarios**:

  Scenario: cosineSimilarity math is correct
    Tool: Bash
    Preconditions: Node.js REPL with imported cosineSimilarity
    Steps:
      1. `cosineSimilarity([1,0,0], [1,0,0])` → assert > 0.999
      2. `cosineSimilarity([1,0,0], [0,1,0])` → assert < 0.01
      3. `cosineSimilarity([1,1,0], [1,0,1])` → assert between 0.4 and 0.6
    Expected Result: All three assertions pass
    Evidence: .sisyphus/evidence/c3-cosine-math.txt

  Scenario: PillarCentroids caches after first embed
    Tool: Bash
    Preconditions: Ollama running at localhost:11434
    Steps:
      1. Instantiate PillarCentroids, call `getCentroid('magno')` twice
      2. Verify only 1 Ollama HTTP call was made
    Expected Result: Only 1 Ollama call made, second returns cached
    Evidence: .sisyphus/evidence/c3-centroid-caching.txt

- [ ] **C4: `classifyKeywordSemantic()` chaining**

  **What to do**:
  - Implement `classifyKeywordSemantic(kw: string): PillarName` in `pillar-classifier.mjs`:
    1. Call `classifyKeyword(kw)` — if result != 'tech', return it immediately
    2. If 'tech' (fallback/unknown), try semantic: embed kw → cosine similarity vs 4 centroids → best match
    3. If Ollama offline, fall back to 'tech' silently
  - Chain existing sync → Ollama fallback flow
  - This is the main public API for semantic classification

  **Must NOT do**:
  - Do NOT call Ollama for keywords that already classified as non-tech via sync
  - Do NOT crash if Ollama is unavailable — must degrade gracefully
  - Do NOT cache semantic results — each call re-embeds

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Chaining logic with graceful degradation — moderate complexity
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with C1, C2, C3)
  - **Blocks**: C5
  - **Blocked By**: C2 (classifyKeyword) + C3 (PillarCentroids)

  **References**:
  - `pillar-classifier.mjs` — C2 deliverable
  - `pillar-centroids.mjs` — C3 deliverable

  **Acceptance Criteria**:
  - [ ] `classifyKeywordSemantic('code')` → 'tech' (sync hit)
  - [ ] `classifyKeywordSemantic('empathy')` → 'magno' (sync hit, not 'tech')
  - [ ] `classifyKeywordSemantic('zzzz_unknown')` → tries Ollama, returns best pillar or 'tech'
  - [ ] Ollama offline → `classifyKeywordSemantic('anything')` → 'tech' (fallback)

  **QA Scenarios**:

  Scenario: Sync hit returns immediately without Ollama call
    Tool: Bash
    Preconditions: Ollama mocked/unavailable, classifyKeywordSemantic imported
    Steps:
      1. `classifyKeywordSemantic('empathy')` → should return 'magno' WITHOUT calling Ollama
    Expected Result: 'magno' returned, no Ollama error
    Evidence: .sisyphus/evidence/c4-sync-hit-no-ollama.txt

  Scenario: Ollama offline gracefully degrades to 'tech'
    Tool: Bash
    Preconditions: Ollama NOT running
    Steps:
      1. `classifyKeywordSemantic('zzzz_unknown')` → should return 'tech' (not throw)
    Expected Result: Returns 'tech' with no error thrown
    Evidence: .sisyphus/evidence/c4-ollama-offline.txt

- [ ] **C5: `learnFromOutcome()` + `bumpPillarWeight()`**

  **What to do**:
  - Create `pillar-learning.mjs` with:
    - `learnFromOutcome(nodes: NoteNode[], outcome: OutcomeType): void` — main entry point
      1. Extract up to 5 keywords per node (remove stop words: the, a, is, of, etc.)
      2. Classify each keyword via `classifyKeywordSemantic()`
      3. For each classified keyword, call `bumpPillarWeight(pillar, keyword, outcome)`
    - `bumpPillarWeight(pillar, keyword, outcome): void` — SQLite upsert into `pillar_stats`
      - Positive outcome → frequency += 1
      - Negative outcome → frequency -= 1 (floor at 0)
      - Neutral → no change
  - Hook into `retrieval/outcome.js` — existing outcome-processing call site (see References)

  **Must NOT do**:
  - Do NOT skip stop word removal — 'the' is not a pillar keyword
  - Do NOT allow negative frequencies in DB
  - Do NOT call Ollama for stop-word-only inputs

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Outcome learning with multiple steps — moderate complexity
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with C6, C7)
  - **Blocks**: C6 (applyPillarWeightBoost needs learned weights)
  - **Blocked By**: C4 (classifyKeywordSemantic needed)

  **References**:
  - `~/.claude/secondbrain-upgrade/retrieval/outcome.js` — hook point for learnFromOutcome
  - `pillar-classifier.mjs` — C4 deliverable (classifyKeywordSemantic)
  - DuckDB `relayReasoningEngine.ts` — learnFromOutcome logic pattern to follow (do NOT copy code)

  **Acceptance Criteria**:
  - [ ] File created: `pillar-learning.mjs`
  - [ ] `learnFromOutcome` can be called with a node and positive/negative/neutral outcome
  - [ ] `bumpPillarWeight` upserts into `pillar_stats` table correctly
  - [ ] Negative outcome decreases frequency (floor at 0)
  - [ ] Hooked into `retrieval/outcome.js` without breaking existing functionality

  **QA Scenarios**:

  Scenario: Positive outcome increases pillar keyword frequency
    Tool: Bash
    Preconditions: Temp DB with `pillar_stats` table, `learnFromOutcome` imported
    Steps:
      1. `bumpPillarWeight('tech', 'code', 'positive')` — call twice
      2. Query DB: `SELECT frequency FROM pillar_stats WHERE pillar='tech' AND keyword='code'`
    Expected Result: frequency = 2
    Evidence: .sisyphus/evidence/c5-positive-outcome.txt

  Scenario: Negative outcome decreases frequency (floor at 0)
    Tool: Bash
    Preconditions: Temp DB, frequency of 'design' under 'style' = 3
    Steps:
      1. `bumpPillarWeight('style', 'design', 'negative')` — call twice
      2. Query DB: frequency should be 1
      3. `bumpPillarWeight('style', 'design', 'negative')` — call again
      4. Query DB: frequency should be 0 (not -1)
    Expected Result: frequency floors at 0
    Evidence: .sisyphus/evidence/c5-negative-floor.txt

- [ ] **C6: `applyPillarWeightBoost()` retrieval ranking**

  **What to do**:
  - Create `pillar-retrieval.mjs` with:
    - `applyPillarWeightBoost(nodes: NoteNode[], query: string): NoteNode[]` — ranks nodes by pillar relevance
      1. Classify query to dominant pillar via `classifyKeywordSemantic()`
      2. For each node, get its pillar assignment (from `note_pillars` or classify content)
      3. Boost score: if node.pillar == query.pillar → boost multiplier (e.g., 1.2x)
      4. Return sorted by boosted score
    - This is a post-processing step on top of existing TF/IDF or embedding similarity

  **Must NOT do**:
  - Do NOT replace existing retrieval ranking — only boost
  - Do NOT add pillars to nodes that don't have them — just skip boosting
  - Do NOT rank if query.classified_as 'tech' — tech is default, no boost

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Retrieval ranking with boosting — moderate complexity
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with C5, C7)
  - **Blocks**: None (final integration step)
  - **Blocked By**: C5 (needs learned weights), C4 (needs classifyKeywordSemantic)

  **References**:
  - `pillar-learning.mjs` — C5 deliverable
  - `pillar-classifier.mjs` — C4 deliverable

  **Acceptance Criteria**:
  - [ ] File created: `pillar-retrieval.mjs`
  - [ ] Node matching query pillar gets boosted ranking
  - [ ] Node not matching query pillar is not penalized
  - [ ] tech queries (default) produce no boost — unchanged ranking

  **QA Scenarios**:

  Scenario: Magno query boosts magno nodes
    Tool: Bash
    Preconditions: 3 nodes with different pillars, query = 'empathy community'
    Steps:
      1. Classify query → 'magno'
      2. Apply boost → nodes with pillar='magno' should be ranked higher
    Expected Result: magno node appears first
    Evidence: .sisyphus/evidence/c6-magno-boost.txt

- [ ] **C7: Phase 7 `pillar-segregation.js` sleep cycle module**

  **What to do**:
  - Create `sleep-cycle/phases/pillar-segregation.js`:
    - Phase 7 of sleep cycle — runs after conflict resolution (phase 4/5)
    - `runPillarSegregationPhase(db): void`:
      1. Scan all notes with no `note_pillars` entry
      2. For each, extract top 5 keywords (already done by reflection phase)
      3. Classify via `classifyKeywordSemantic()`
      4. Insert into `note_pillars` with confidence score
    - Follow existing phase module pattern (see References)
  - Register Phase 7 in `sleep-cycle/index.js`

  **Must NOT do**:
  - Do NOT re-classify notes that already have `note_pillars` entries
  - Do NOT run if previous phases failed
  - Do NOT modify existing phase 1-6 behavior

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Sleep cycle integration — needs to follow existing phase pattern
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with C5, C6)
  - **Blocks**: C8 (tests need Phase 7 to exist)
  - **Blocked By**: C4 (classifyKeywordSemantic), C5 (bumpPillarWeight)

  **References**:
  - `~/.claude/secondbrain-upgrade/sleep-cycle/phases/conflict-resolution.js` — existing phase pattern to follow
  - `sleep-cycle/index.js` — phase registration

  **Acceptance Criteria**:
  - [ ] File created: `sleep-cycle/phases/pillar-segregation.js`
  - [ ] Phase 7 registered in `sleep-cycle/index.js`
  - [ ] `runPillarSegregationPhase(db)` can be called without errors
  - [ ] Existing sleep cycle phases 1-6 still work

  **QA Scenarios**:

  Scenario: Phase 7 runs without errors on notes needing classification
    Tool: Bash
    Preconditions: Temp DB with 3 notes lacking `note_pillars` entries
    Steps:
      1. `runPillarSegregationPhase(db)` → no throws
      2. Query: `SELECT * FROM note_pillars` → 3 rows added
    Expected Result: 3 rows inserted, no errors
    Evidence: .sisyphus/evidence/c7-phase7-run.txt

- [ ] **C8: Comprehensive validation tests (30+ tests)**

  **What to do**:
  - Create `tests/validation/09-phase7-pillar-segregation.js` — Phase 7 module tests
  - Create `tests/validation/10-pillar-learning.js` — learnFromOutcome + bumpPillarWeight tests
  - Create `tests/validation/11-pillar-retrieval.js` — applyPillarWeightBoost tests
  - Create `tests/validation/12-pillar-centroids.js` — PillarCentroids + cosineSimilarity tests
  - Each file: follow existing `fw.test()` pattern from `tests/validation/*.js`
  - Total expected: +30 tests → ~111+ total

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Test writing following existing patterns
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (all 4 test files can be written in parallel)
  - **Parallel Group**: Wave 3 (with C9)
  - **Blocks**: None
  - **Blocked By**: C5, C6, C7 (need modules before tests can be written)

  **References**:
  - `~/.claude/secondbrain-upgrade/tests/validation/04-phase25-conflict.js` — existing test pattern
  - `pillar-learning.mjs` — C5 deliverable
  - `pillar-retrieval.mjs` — C6 deliverable
  - `pillar-centroids.mjs` — C3 deliverable

  **Acceptance Criteria**:
  - [ ] 4 new test files created
  - [ ] All new tests pass: `bun test tests/validation/`
  - [ ] Total test count: 111+ (81 current + 30 new)
  - [ ] No regressions in existing 81 tests

  **QA Scenarios**:

  Scenario: All pillar tests pass
    Tool: Bash
    Steps:
      1. Run: `bun test tests/validation/09-phase7-pillar-segregation.js`
      2. Run: `bun test tests/validation/10-pillar-learning.js`
      3. Run: `bun test tests/validation/11-pillar-retrieval.js`
      4. Run: `bun test tests/validation/12-pillar-centroids.js`
    Expected Result: All tests pass, no failures
    Evidence: .sisyphus/evidence/c8-all-pillar-tests.txt

- [ ] **C9: CLAUDE.md documentation update**

  **What to do**:
  - Update `~/.claude/secondbrain-upgrade/CLAUDE.md`:
    - Add new modules to "Key Files" section
    - Add new tables to "Database Schema" section
    - Update test count from "40 tests" / "81 tests" to "111+ tests"
    - Add Pillar System section: pillars, classification, learning
  - Follow existing CLAUDE.md structure

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Documentation update — straightforward
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with C8)
  - **Parallel Group**: Wave 3
  - **Blocks**: None
  - **Blocked By**: None (can start after C5-C7 are done)

  **References**:
  - `~/.claude/secondbrain-upgrade/CLAUDE.md` — current content to update

  **Acceptance Criteria**:
  - [ ] CLAUDE.md updated with new modules, tables, test count
  - [ ] Pillar System section added
  - [ ] File still parses correctly

---

## Final Verification Wave

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
>
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback → fix → re-run → present again → wait for okay.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists. For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Check evidence files exist in `.sisyphus/evidence/`. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `bun test tests/validation/`. Review all changed/created files for: `as any`/`@ts-ignore`, empty catches, `console.log` in prod, commented-out code, unused imports. Check AI slop: excessive comments, over-abstraction, generic names.
  Output: `Tests [N/N pass] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Real Manual QA** — `unspecified-high`
  Start from clean state. Execute EVERY QA scenario from EVERY task — follow exact steps, capture evidence. Test cross-task integration (features working together, not isolation). Test edge cases: Ollama offline, empty DB, stop words, frequency floor at 0. Save to `.sisyphus/evidence/final-qa/`.
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual diff (git log/diff). Verify 1:1 — everything in spec was built (no missing), nothing beyond spec was built (no creep). Check "Must NOT do" compliance. Detect cross-task contamination. Flag unaccounted changes.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | VERDICT`

---

## Commit Strategy

- **C1-C4**: `feat(pillar): schema, seeds, centroids, semantic classify` — schema/upgrade-v4-pillar-segregation.sql, pillar-classifier.mjs, pillar-centroids.mjs
- **C5-C7**: `feat(pillar): learning, retrieval, phase7` — pillar-learning.mjs, pillar-retrieval.mjs, pillar-segregation.js
- **C8**: `test(pillar): comprehensive pillar tests` — tests/validation/09-12
- **C9**: `docs(pillar): update CLAUDE.md` — CLAUDE.md

---

## Success Criteria

### Verification Commands
```bash
bun test tests/validation/                    # Expected: 111+ tests pass (currently 81/82)
```

### Final Checklist
- [ ] All 9 commits created
- [ ] All new modules export functions that can be imported
- [ ] Ollama offline graceful degradation works
- [ ] Frequency floor at 0 enforced in `pillar_stats`
- [ ] Phase 7 registered and runs without breaking sleep cycle
- [ ] CLAUDE.md updated with accurate test count

