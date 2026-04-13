# SecondBrain Gap Fill — Port Vault Sync, Context Tree, Facts, FTS5 & Create-Note

## TL;DR

> **Quick Summary**: Fill 5 critical gaps in secondbrain-upgrade by porting vault sync engine, context tree search, facts K/V store, fixing broken FTS5 BM25 join, and porting create-note CLI.
>
> **Deliverables**:
> - `sync.mjs` — full/incremental vault sync with SHA256, tag/link extraction, folder→domain mapping
> - `context-tree.mjs` — context_tree CRUD + searchContext() with working FTS5 join
> - `facts.mjs` — facts K/V store with getFacts/setFacts/deleteFact
> - `semantic-search.js` fix — corrected FTS5 join + reindex trigger
> - `create-note.mjs` — create/capture/analyze CLI using 4-pillar system
> - 5 new test modules (~33 new tests)
>
> **Estimated Effort**: Large
> **Parallel Execution**: YES — 4 waves, max 5 parallel tasks
> **Critical Path**: FTS5 fix (T1) → Vault Sync (T6) → Context Tree (T7) → Facts (T8) → Create-Note (T9)

---

## Context

### Discovery Findings (DB Verification — Critical)

| Table | Exists? | Rows | Status |
|-------|---------|------|--------|
| `vault_notes` | ✅ | 1921 | Has data |
| `vault_fts` | ✅ | 1098 | **BROKEN JOIN** — only 57% indexed |
| `context_fts` | ✅ | 0 | Empty |
| `context_tree` | ✅ | 0 | Empty — needs write layer |
| `vault_tags` | ✅ | 0 | Empty — sync never populates |
| `vault_links` | ✅ | 0 | Empty — sync never populates |
| `facts` | ✅ | 5 | Has seed data — needs CRUD module |
| `sync_state` | ✅ | — | Exists but not used by upgrade |

**Critical bug**: `semantic-search.js:153` — `JOIN vault_notes vn ON vault_fts.rowid = vn.rowid` fails because `vault_notes.id` is TEXT (UUID), not integer rowid. FTS5 `content_rowid='id'` means `vault_fts.rowid = CAST(vn.id AS INTEGER)`. Only 1098/1921 notes are indexed (57%).

---

## Work Objectives

### Core Objective
Port missing functionality from `secondbrain-sqlite` to `secondbrain-upgrade`, fixing discovered bugs.

### Concrete Deliverables
- `~/.claude/secondbrain-upgrade/sync.mjs`
- `~/.claude/secondbrain-upgrade/context-tree.mjs`
- `~/.claude/secondbrain-upgrade/facts.mjs`
- `~/.claude/secondbrain-upgrade/create-note.mjs`
- Fix `~/.claude/secondbrain-upgrade/semantic-search.js`
- 5 new test modules

### Definition of Done
- [ ] `node sync.mjs full` completes without error and populates vault_tags + vault_links
- [ ] `searchContext('query')` returns results ranked by bm25
- [ ] `getFacts('key')` returns stored value
- [ ] `ftsSearch('test')` returns results (currently broken)
- [ ] `node create-note.mjs create "Title" "Content"` creates note in vault_notes
- [ ] All 5 new test modules pass

### Must Have
- Full/incremental vault sync with SHA256 hashing
- Context tree search with working FTS5 join
- Facts CRUD with confidence scores
- Create-note CLI using 4-pillar system (magno/tech/style/tirol)
- FTS5 reindex after note creation

### Must NOT Have
- NO filesystem writes (upgrade uses DB only)
- NO 6-pillar folder routing — use 4-pillar keyword system
- NO DuckDB — SQLite only
- NO writing to context_tree from sync (separate K/V)

---

## Verification Strategy

### Test Infrastructure
- **Framework**: Plain Node.js + custom TEST-FRAMEWORK (`fw.test()`, `fw.section()`)
- **LLM mocking**: `globalThis._testCallLLM` (pre-configured in TEST-runner.js)
- **DB path**: `~/.claude/secondbrain-sqlite/secondbrain.db` (shared — existing tables present)
- **Fixtures**: `createTestNote`, `createTestNoteScore`, etc. + new `createTestContextNode`, `createTestFact`

### QA Policy
Every task includes agent-executed QA scenarios. Evidence saved to `.sisyphus/evidence/`.

---

## Execution Strategy

### Parallel Waves

```
Wave 1 (Foundation — max parallel):
├── T1: Fix FTS5 join in semantic-search.js
├── T2: Add vault_tags + vault_links + sync_state tables via migration
├── T3: Add context_tree + context_fts triggers via migration
├── T4: Add facts CRUD module (getFacts, setFact, deleteFact)
└── T5: Add test fixtures (createTestContextNode, createTestFact)

Wave 2 (Core modules — 4 parallel):
├── T6: Vault sync.mjs (full/incr, SHA256, frontmatter, tag/link extract)
├── T7: context-tree.mjs (CRUD + searchContext + FTS5 join fix)
├── T8: facts.mjs complete (getFacts, setFact, deleteFact, updateConfidence)
└── T9: create-note.mjs skeleton + pillar helpers

Wave 3 (Integration — 3 parallel):
├── T10: Vault sync → FTS5 reindex on note insert/update
├── T11: create-note → vault_notes + note_pillars integration
└── T12: Full integration test — all modules working together

Wave 4 (Tests — 5 parallel):
├── T13: 13-vault-sync.js (8 tests)
├── T14: 14-context-tree.js (7 tests)
├── T15: 15-facts-kv.js (7 tests)
├── T16: 16-create-note-cli.js (6 tests)
└── T17: 17-fts5-fix.js (5 tests)

Wave FINAL:
├── F1: Plan compliance audit (oracle)
├── F2: Code quality review
├── F3: Real manual QA
└── F4: Scope fidelity check
```

### Dependency Matrix
- T1, T2, T3, T4, T5: **None** — Wave 1 starts immediately
- T6: T2 (needs vault_tags + vault_links schema)
- T7: T3 (needs context_tree schema)
- T8: T4 (needs facts schema)
- T9: T5 (needs fixtures)
- T10: T6 + T1 (sync needs engine + fixed FTS5)
- T11: T9 + T1 (create-note needs CLI + search)
- T12: T10 + T11
- T13: T6; T14: T7; T15: T8; T16: T11; T17: T1

---

## TODOs

- [ ] 1. **Fix FTS5 join in semantic-search.js**

  **What to do**:
  - Read `semantic-search.js:149-157` — the broken FTS5 JOIN
  - The bug: `JOIN vault_notes vn ON vault_fts.rowid = vn.rowid` — but `vault_notes.id` is TEXT UUID, not integer rowid
  - FTS5 `content='vault_notes', content_rowid='id'` means `vault_fts.rowid = CAST(vn.id AS INTEGER)`
  - Fix the JOIN to: `JOIN vault_notes vn ON vault_fts.rowid = CAST(vn.id AS INTEGER)`
  - Change `bm25(vault_fts) AS rank` to use the corrected join
  - After fix, verify `ftsSearch('test')` returns non-empty results
  - Also check: the `vault_fts` FTS5 table has `content='vault_notes', content_rowid='id'` — this is correct (rowid maps to id column). But the JOIN was using `vn.rowid` instead of `vn.id`

  **Must NOT do**:
  - Do NOT change the FTS5 table schema (content= and content_rowid= are correct)
  - Do NOT remove the LIKE fallback in the catch block — keep it as last-resort
  - Do NOT change the hybridSearch() RRF fusion logic

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — bug fix requiring understanding of FTS5 internals
  - **Skills**: none required — pure bug fix
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with T2, T3, T4, T5)
  - **Blocks**: T10 (sync→FTS5 reindex), T17 (FTS5 fix tests)
  - **Blocked By**: None

  **References**:
  - `~/.claude/secondbrain-upgrade/semantic-search.js:123-172` — ftsSearch() broken join (T1 PRIORITY)
  - `~/.claude/secondbrain-sqlite/schema.sql:22-27` — vault_fts FTS5 definition with content_rowid='id'
  - DB query: `sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT name, type FROM sqlite_master WHERE name='vault_fts'"` — verify FTS5 table config
  - WHY: The FTS5 virtual table's rowid maps to vault_notes.id (TEXT), not vault_notes.rowid (integer). The join must use CAST.

  **Acceptance Criteria**:
  - [ ] `node -e "const {ftsSearch} = require('~/.claude/secondbrain-upgrade/semantic-search.js'); ftsSearch('test').then(r => console.log('ROWS:', r.length)).catch(e => console.error('ERR:', e.message))"` → returns count > 0 (not error)
  - [ ] Fix verified: JOIN changed from `vn.rowid` to `CAST(vn.id AS INTEGER)`
  - [ ] `vault_fts` row count still = 1098 (data preserved)

  **QA Scenarios**:

  \`\`\`
  Scenario: ftsSearch returns results after join fix
    Tool: Bash
    Preconditions: DB has vault_fts with 1098 rows, vault_notes with 1921 rows
    Steps:
      1. Run: node -e "const {ftsSearch} = require('/Users/arjomagno/.claude/secondbrain-upgrade/semantic-search.js'); ftsSearch('project').then(r => console.log(JSON.stringify({count: r.length, first: r[0]?.title}))).catch(e => console.error(e.message))"
      2. Assert: output contains count > 0
      3. Assert: first result has title field populated
    Expected Result: {"count": N, "first": "..."} where N > 0
    Failure Indicators: "ERR:" output, count = 0, first = undefined
    Evidence: .sisyphus/evidence/task-01-fts5-fix.log

  Scenario: ftsSearch gracefully falls back to LIKE on malformed query
    Tool: Bash
    Preconditions: ftsSearch called with query that produces invalid FTS5 syntax
    Steps:
      1. Run: node -e "const {ftsSearch} = require('/Users/arjomagno/.claude/secondbrain-upgrade/semantic-search.js'); ftsSearch('').then(r => console.log('EMPTY:', r.length)).catch(e => console.log('CAUGHT:', e.message))"
    Expected Result: Returns array (empty or fallback), no uncaught error
    Failure Indicators: Unhandled promise rejection
    Evidence: .sisyphus/evidence/task-01-fts5-empty-query.log
  \`\`\`

  **Commit**: YES
  - Message: `fix(secondbrain): correct FTS5 join — use CAST(vn.id AS INTEGER) instead of vn.rowid`
  - Files: `semantic-search.js`

---

- [ ] 2. **Add vault_tags, vault_links, sync_state tables via migration**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/schema/upgrade-v5-vault-sync.sql`
  - These tables ALREADY exist in the shared DB (verified: vault_tags, vault_links, sync_state all present with 0 rows). This migration is a NO-OP that documents the schema.
  - Add the migration file that CREATES the tables IF NOT EXISTS (idempotent)
  - Schema from source (secondbrain-sqlite/schema.sql):
    ```sql
    CREATE TABLE IF NOT EXISTS vault_tags (
      note_id TEXT REFERENCES vault_notes(id) ON DELETE CASCADE,
      tag TEXT NOT NULL,
      PRIMARY KEY (note_id, tag)
    );
    CREATE TABLE IF NOT EXISTS vault_links (
      from_note TEXT REFERENCES vault_notes(id) ON DELETE CASCADE,
      to_note TEXT NOT NULL,
      link_text TEXT,
      PRIMARY KEY (from_note, to_note)
    );
    CREATE TABLE IF NOT EXISTS sync_state (
      file_path TEXT PRIMARY KEY,
      file_hash TEXT NOT NULL,
      file_mtime TEXT NOT NULL,
      last_synced_at TEXT DEFAULT CURRENT_TIMESTAMP,
      sync_status TEXT DEFAULT 'synced'
    );
    CREATE INDEX IF NOT EXISTS idx_sync_file_hash ON sync_state(file_hash);
    ```
  - The tables already exist — this migration documents the schema and ensures idempotency

  **Must NOT do**:
  - Do NOT drop or recreate existing tables
  - Do NOT change the existing vault_notes schema
  - Do NOT add columns to vault_notes

  **Recommended Agent Profile**:
  - **Category**: `quick` — schema definition only
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with T1, T3, T4, T5)
  - **Blocks**: T6 (vault sync engine)
  - **Blocked By**: None

  **References**:
  - `~/.claude/secondbrain-sqlite/schema.sql:47-69` — vault_tags, vault_links, sync_state definitions
  - DB: `sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT COUNT(*) FROM vault_tags; SELECT COUNT(*) FROM vault_links; SELECT COUNT(*) FROM sync_state;"`
  - WHY: These tables exist in the shared DB (0 rows) but have no migration file in upgrade

  **Acceptance Criteria**:
  - [ ] `upgrade-v5-vault-sync.sql` created with CREATE TABLE IF NOT EXISTS for all 3 tables
  - [ ] Tables verified to exist in DB: `vault_tags`, `vault_links`, `sync_state`
  - [ ] No data loss — tables still have 0 rows

  **QA Scenarios**:

  \`\`\`
  Scenario: Migration file is idempotent
    Tool: Bash
    Preconditions: Tables exist with 0 rows
    Steps:
      1. Run: sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db < ~/.claude/secondbrain-upgrade/schema/upgrade-v5-vault-sync.sql
      2. Run: sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT COUNT(*) FROM vault_tags; SELECT COUNT(*) FROM vault_links; SELECT COUNT(*) FROM sync_state;"
    Expected Result: All counts unchanged (0, 0, 0) — no data corruption
    Failure Indicators: Error on re-run, row count changed
    Evidence: .sisyphus/evidence/task-02-vault-schema.log
  \`\`\`

  **Commit**: YES (groups with T3, T4, T5)
  - Message: `chore(secondbrain): add vault sync schema migration (v5)`
  - Files: `schema/upgrade-v5-vault-sync.sql`

---

- [ ] 3. **Add context_tree + context_fts FTS5 triggers via migration**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/schema/upgrade-v6-context-tree.sql`
  - context_tree table ALREADY exists in DB (verified: 0 rows). Add migration that documents the schema.
  - Also add the FTS5 triggers for keeping context_fts in sync (these don't exist yet in upgrade)
  - Schema:
    ```sql
    CREATE TABLE IF NOT EXISTS context_tree (
      id TEXT PRIMARY KEY,
      parent_id TEXT REFERENCES context_tree(id),
      domain TEXT NOT NULL,
      label TEXT NOT NULL,
      content TEXT,
      node_type TEXT DEFAULT 'entry',
      relevance_score REAL DEFAULT 1.0,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX IF NOT EXISTS idx_context_domain ON context_tree(domain);
    CREATE INDEX IF NOT EXISTS idx_context_parent ON context_tree(parent_id);
    
    -- FTS5 triggers for context_fts (already exists but ensure triggers present)
    CREATE TRIGGER IF NOT EXISTS context_ai AFTER INSERT ON context_tree BEGIN
      INSERT INTO context_fts(rowid, label, content) VALUES (new.rowid, new.label, new.content);
    END;
    CREATE TRIGGER IF NOT EXISTS context_ad AFTER DELETE ON context_tree BEGIN
      INSERT INTO context_fts(context_fts, rowid, label, content) VALUES ('delete', old.rowid, old.label, old.content);
    END;
    CREATE TRIGGER IF NOT EXISTS context_au AFTER UPDATE ON context_tree BEGIN
      INSERT INTO context_fts(context_fts, rowid, label, content) VALUES ('delete', old.rowid, old.label, old.content);
      INSERT INTO context_fts(rowid, label, content) VALUES (new.rowid, new.label, new.content);
    END;
    ```
  - context_fts FTS5 table already exists in DB (verified: 0 rows). Just ensure triggers exist.

  **Must NOT do**:
  - Do NOT drop or recreate context_tree or context_fts
  - Do NOT modify existing vault_notes FTS5 triggers

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with T1, T2, T4, T5)
  - **Blocks**: T7 (context-tree module)
  - **Blocked By**: None

  **References**:
  - `~/.claude/secondbrain-sqlite/schema.sql:71-106` — context_tree + context_fts + triggers
  - DB: `sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT COUNT(*) FROM context_tree; SELECT COUNT(*) FROM context_fts;"`
  - WHY: context_tree exists in DB but upgrade has no migration for it, and triggers for context_fts are missing

  **Acceptance Criteria**:
  - [ ] `upgrade-v6-context-tree.sql` created
  - [ ] context_tree table verified: id, parent_id, domain, label, content, node_type, relevance_score, created_at
  - [ ] context_fts triggers verified working: INSERT to context_tree auto-indexes in context_fts

  **QA Scenarios**:

  \`\`\`
  Scenario: Insert to context_tree triggers FTS5 index update
    Tool: Bash
    Preconditions: context_tree empty, context_fts empty
    Steps:
      1. sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "INSERT INTO context_tree (id, domain, label, content) VALUES ('test-ctx-1', 'tech', 'JavaScript', 'JS is a programming language');"
      2. sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT COUNT(*) FROM context_fts;"
    Expected Result: context_fts has 1 row (auto-indexed by trigger)
    Failure Indicators: context_fts still 0 rows — trigger not working
    Evidence: .sisyphus/evidence/task-03-context-tree.log
  \`\`\`

  **Commit**: YES (groups with T2, T4, T5)
  - Message: `chore(secondbrain): add context tree schema migration (v6)`
  - Files: `schema/upgrade-v6-context-tree.sql`

---

- [ ] 4. **Add facts CRUD module**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/facts.mjs`
  - Facts table already exists in DB (verified: 5 rows). Write the CRUD module.
  - Functions to implement:
    ```javascript
    // Get facts by key pattern (like SQLite LIKE)
    async function getFacts(key = null) {
      // If key: SELECT * FROM facts WHERE key LIKE '%key%' ORDER BY confidence DESC
      // If no key: SELECT * FROM facts ORDER BY created_at DESC
    }
    
    // Set a fact (upsert)
    async function setFact(key, value, source = null, confidence = 1.0) {
      // INSERT OR REPLACE INTO facts (id, key, value, source, confidence, created_at)
      // id = hash(key) — deterministic
    }
    
    // Delete a fact
    async function deleteFact(key) {
      // DELETE FROM facts WHERE key = ?
    }
    
    // Update confidence of existing fact
    async function updateConfidence(key, newConfidence) {
      // UPDATE facts SET confidence = ? WHERE key = ?
    }
    
    // List all unique keys
    async function listFactKeys() {
      // SELECT DISTINCT key FROM facts ORDER BY key
    }
    ```
  - Import `db` from `require('./db')`
  - Use `createHash('sha256').update(key).digest('hex').slice(0, 16)` for deterministic ID (same as source)

  **Must NOT do**:
  - Do NOT delete existing facts rows
  - Do NOT use DuckDB — SQLite only
  - Do NOT assume facts table has more columns than (id, key, value, source, confidence, created_at)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with T1, T2, T3, T5)
  - **Blocks**: T8 (facts.mjs completion)
  - **Blocked By**: None

  **References**:
  - `~/.claude/secondbrain-sqlite/schema.sql:108-116` — facts table schema
  - `~/.claude/secondbrain-sqlite/query.mjs:148-156` — getFacts() implementation reference
  - DB: `sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT * FROM facts LIMIT 5;"` — see existing facts
  - WHY: Facts is a simple K/V store — direct port with deterministic ID hashing

  **Acceptance Criteria**:
  - [ ] `getFacts(null)` returns all facts
  - [ ] `getFacts('key')` returns facts matching key pattern
  - [ ] `setFact('test_key', 'test_value')` creates new fact
  - [ ] `deleteFact('test_key')` removes fact
  - [ ] `updateConfidence('test_key', 0.5)` updates confidence
  - [ ] Existing 5 facts preserved (no deletion of seed data)

  **QA Scenarios**:

  \`\`\`
  Scenario: getFacts returns all facts when called with null
    Tool: Bash
    Preconditions: DB has 5 facts rows
    Steps:
      1. node -e "const f = require('/Users/arjomagno/.claude/secondbrain-upgrade/facts.mjs'); f.getFacts(null).then(r => console.log('COUNT:', r.length, 'FIRST:', JSON.stringify(r[0])))"
    Expected Result: COUNT >= 5, FIRST has key/value/confidence fields
    Failure Indicators: Error, COUNT < 5
    Evidence: .sisyphus/evidence/task-04-facts-crud.log

  Scenario: setFact creates new fact with deterministic ID
    Tool: Bash
    Preconditions: Test fact does not exist
    Steps:
      1. node -e "const f = require('/Users/arjomagno/.claude/secondbrain-upgrade/facts.mjs'); f.setFact('test_prometheus_key', 'test_value', 'unit_test', 0.9).then(() => f.getFacts('test_prometheus_key')).then(r => console.log('CREATED:', r.length, 'KEY:', r[0]?.key))"
      2. node -e "const f = require('/Users/arjomagno/.claude/secondbrain-upgrade/facts.mjs'); f.deleteFact('test_prometheus_key')"
    Expected Result: CREATED: 1, KEY matches, cleanup succeeds
    Failure Indicators: CREATED: 0, error on create
    Evidence: .sisyphus/evidence/task-04-facts-set.log
  \`\`\`

  **Commit**: YES (groups with T2, T3, T5)
  - Message: `feat(secondbrain): add facts K/V store module`
  - Files: `facts.mjs`

---

- [ ] 5. **Add test fixtures for context tree and facts**

  **What to do**:
  - Read `~/.claude/secondbrain-upgrade/tests/validation/TEST-FRAMEWORK.js` — existing fixture pattern
  - Add two new fixture functions to TEST-FRAMEWORK.js:
    ```javascript
    async function createTestContextNode(db, overrides = {}) {
      const id = makeId('test-ctx');
      const now = new Date().toISOString();
      const defaults = {
        id,
        parent_id: null,
        domain: 'tech',
        label: 'Test Context Node',
        content: 'Test context content for validation.',
        node_type: 'entry',
        relevance_score: 1.0,
        created_at: now,
      };
      const node = { ...defaults, ...overrides };
      await db.run(`
        INSERT INTO context_tree (id, parent_id, domain, label, content, node_type, relevance_score, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `, node.id, node.parent_id, node.domain, node.label, node.content, node.node_type, node.relevance_score, node.created_at);
      TEST_CONTEXT_NODES.push(id);
      return { ...node, note_id: id };
    }
    
    async function createTestFact(db, overrides = {}) {
      const key = overrides.key || 'test-fact-' + Date.now();
      const now = new Date().toISOString();
      const defaults = {
        id: makeId('test-fact'),
        key,
        value: 'Test fact value',
        source: 'unit_test',
        confidence: 0.8,
        created_at: now,
      };
      const fact = { ...defaults, ...overrides };
      await db.run(`
        INSERT OR REPLACE INTO facts (id, key, value, source, confidence, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `, fact.id, fact.key, fact.value, fact.source, fact.confidence, fact.created_at);
      TEST_FACTS.push(fact.key);
      return fact;
    }
    ```
  - Also add `TEST_CONTEXT_NODES = []` and `TEST_FACTS = []` to cleanup arrays
  - Update `cleanupTestData()` to clean context_tree (WHERE id LIKE 'test-ctx-%') and facts (WHERE key LIKE 'test-fact-%')
  - Add to module.exports: `createTestContextNode`, `createTestFact`
  - Also update `fw.cleanupTestData()` to clean context_tree rows

  **Must NOT do**:
  - Do NOT change existing fixture behavior
  - Do NOT modify TEST_MODULES array (that's TEST-runner.js)
  - Do NOT change DB_PATH

  **Recommended Agent Profile**:
  - **Category**: `quick` — follows existing patterns exactly
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with T1, T2, T3, T4)
  - **Blocks**: T7 (context tree tests), T15 (facts tests)
  - **Blocked By**: None

  **References**:
  - `~/.claude/secondbrain-upgrade/tests/validation/TEST-FRAMEWORK.js:70-139` — existing fixture pattern
  - WHY: Follow same pattern as createTestNote, createTestEntity etc.

  **Acceptance Criteria**:
  - [ ] `createTestContextNode(db)` creates a row in context_tree
  - [ ] `createTestFact(db, {key: 'test-x'})` creates a row in facts
  - [ ] `cleanupTestData(db)` removes test context_tree and facts rows
  - [ ] Module exports include both new fixtures

  **QA Scenarios**:

  \`\`\`
  Scenario: createTestContextNode creates fixture and cleanup removes it
    Tool: Bash
    Preconditions: context_tree has N rows
    Steps:
      1. node -e "const fw = require('/Users/arjomagno/.claude/secondbrain-upgrade/tests/validation/TEST-FRAMEWORK.js'); fw.createTestContextNode({domain: 'tech', label: 'Test'}).then(r => { console.log('CREATED:', r.id); return fw.cleanupTestData(fw.getDb()); }).then(() => { const {all} = require('/Users/arjomagno/.claude/secondbrain-upgrade/tests/validation/TEST-FRAMEWORK.js'); return require('/Users/arjomagno/.claude/secondbrain-upgrade/tests/validation/TEST-FRAMEWORK.js').getDb().then(db => db.all(\"SELECT COUNT(*) as c FROM context_tree WHERE id LIKE 'test-ctx-%'\")); }).then(r => console.log('REMAINING:', r[0].c))"
    Expected Result: CREATED shows ID, REMAINING = 0
    Failure Indicators: Error, REMAINING > 0
    Evidence: .sisyphus/evidence/task-05-fixtures.log
  \`\`\`

  **Commit**: YES (groups with T2, T3, T4)
  - Message: `test(secondbrain): add createTestContextNode and createTestFact fixtures`
  - Files: `tests/validation/TEST-FRAMEWORK.js`

- [ ] 6. **Port vault sync.mjs engine**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/sync.mjs` — full port from secondbrain-sqlite/sync.mjs
  - Adaptations for upgrade:
    - Uses `db` from `./db` (upgrade's SQLite wrapper) instead of opening its own connection
    - Uses `require('./db')` pattern
    - Notes go to `vault_notes` table (already exists), NOT filesystem
    - Also populates `vault_tags` and `vault_links` (which sync.mjs in source does)
    - Uses `sync_state` table for incremental sync tracking
    - FOLDER_DOMAINS mapping: Maps 6 source folders to 4 upgrade pillars:
      ```
      '00-Claude' → 'tech' (AI tools → tech)
      '01-ArjoMagno' → 'magno'
      '02-ArjoTech' → 'tech'
      '03-ArjoStyle' → 'style'
      '04-ArjoTirol' → 'tirol'
      '05-Resources' → 'tech' (reference → tech)
      '06-Archives' → null (skip)
      ```
    - Domain column: Maps to 4-pillar names: magno/tech/style/tirol
    - Note ID: SHA256 first 16 chars of relative path (same as source)
    - File hash: SHA256 of content (same as source)
  - Commands: `node sync.mjs full`, `node sync.mjs incremental`, `node sync.mjs reset`
  - Algorithm from source:
    1. Walk vault folder (skip dotfiles, node_modules, _assets, .trash, 06-Archives)
    2. For each .md file: parse frontmatter, extract tags (#tag regex), extract wiki-links ([[link]] regex)
    3. Compute SHA256 hash of content
    4. For incremental: compare hash vs sync_state.file_hash
    5. Insert/update vault_notes, clear+repopulate vault_tags and vault_links, update sync_state
    6. Batch processing with BEGIN/COMMIT transactions

  **Must NOT do**:
  - Do NOT write to filesystem (no ~/Documents/ArjoSecondBrain/)
  - Do NOT use DuckDB — SQLite only
  - Do NOT use the source's 6-pillar SOUL structure — use 4-pillar mapping
  - Do NOT skip FTS5 reindex after note insert (handled separately in T10)

  **Recommended Agent Profile**:
  - **Category**: `deep` — complex algorithm with file walking, hashing, parsing
  - **Skills**: none required — port from known working implementation
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with T7, T8, T9)
  - **Blocks**: T10 (FTS5 reindex), T13 (vault sync tests)
  - **Blocked By**: T2 (needs vault_tags + vault_links + sync_state schema)

  **References**:
  - `~/.claude/secondbrain-sqlite/sync.mjs:1-469` — COMPLETE source implementation to port
  - `~/.claude/secondbrain-sqlite/schema.sql:47-69` — vault_tags, vault_links, sync_state schema
  - `~/.claude/secondbrain-upgrade/db.js` — upgrade's DB wrapper pattern
  - WHY: This is the critical missing piece — upgrade cannot ingest notes from vault without sync

  **Acceptance Criteria**:
  - [ ] `node sync.mjs full` completes without error
  - [ ] `node sync.mjs incremental` correctly skips unchanged files (uses sync_state)
  - [ ] vault_tags populated: each note's tags inserted
  - [ ] vault_links populated: each note's wiki-links inserted
  - [ ] sync_state tracks all synced files with file_hash

  **QA Scenarios**:

  \`\`\`
  Scenario: Full sync processes all vault .md files
    Tool: Bash
    Preconditions: Vault has .md files in ~/Documents/ArjoSecondBrain
    Steps:
      1. cd ~/.claude/secondbrain-upgrade && node sync.mjs full 2>&1 | tail -20
      2. sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT COUNT(*) FROM vault_notes; SELECT COUNT(*) FROM vault_tags; SELECT COUNT(*) FROM vault_links;"
    Expected Result: vault_notes > 0, vault_tags > 0, vault_links > 0
    Failure Indicators: Error on sync, counts = 0
    Evidence: .sisyphus/evidence/task-06-sync-full.log

  Scenario: Incremental sync skips unchanged files
    Tool: Bash
    Preconditions: Full sync completed, no files changed
    Steps:
      1. cd ~/.claude/secondbrain-upgrade && node sync.mjs incremental 2>&1 | tail -10
      2. Check output mentions "Skipped (unchanged): N" or similar
    Expected Result: All files skipped (unchanged)
    Failure Indicators: Re-syncing all files
    Evidence: .sisyphus/evidence/task-06-sync-incremental.log
  \`\`\`

  **Commit**: YES
  - Message: `feat(secondbrain): port vault sync engine (full/incr, SHA256, tag/link extract)`
  - Files: `sync.mjs`

---

- [ ] 7. **Port context-tree.mjs with working FTS5 join**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/context-tree.mjs`
  - Functions to port from secondbrain-sqlite/query.mjs:
    ```javascript
    // searchContext — FTS5 search with working join (THE CRITICAL FIX)
    async function searchContext(query, options = {}) {
      const { limit = 15, domain } = options;
      // THE JOIN FIX: Use CAST(vn.id AS INTEGER) not vn.rowid
      // SELECT c.*, rank AS score FROM context_fts
      // JOIN context_tree c ON context_fts.rowid = CAST(c.id AS INTEGER)
      // WHERE context_fts MATCH ?
      // [optional AND domain filter]
      // ORDER BY rank LIMIT ?
    }
    
    // addContextNode — insert new context tree node
    async function addContextNode(domain, label, content, parent_id = null, node_type = 'entry') {
      // INSERT INTO context_tree (id, parent_id, domain, label, content, node_type)
      // id = hash(domain + label + Date.now())[:16]
    }
    
    // getContextNode — fetch by ID
    async function getContextNode(id) {
      // SELECT * FROM context_tree WHERE id = ?
    }
    
    // getChildNodes — fetch children of a node
    async function getChildNodes(parent_id) {
      // SELECT * FROM context_tree WHERE parent_id = ? ORDER BY relevance_score DESC
    }
    
    // getContextByDomain — all nodes in a domain
    async function getContextByDomain(domain) {
      // SELECT * FROM context_tree WHERE domain = ? ORDER BY label
    }
    
    // updateContextScore — update relevance_score
    async function updateContextScore(id, newScore) {
      // UPDATE context_tree SET relevance_score = ? WHERE id = ?
    }
    
    // deleteContextNode — remove node (and optionally children)
    async function deleteContextNode(id, cascade = false) {
      // DELETE FROM context_tree WHERE id = ? [or WHERE parent_id = ? if cascade]
    }
    ```
  - The searchContext FTS5 join MUST use `CAST(c.id AS INTEGER)` — same bug as T1
  - context_fts uses `content='context_tree', content_rowid='id'` — rowid maps to id column

  **Must NOT do**:
  - Do NOT use the broken `context_fts.rowid = c.rowid` join
  - Do NOT write to context_tree from sync.mjs (separate operation)
  - Do NOT use DuckDB

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with T6, T8, T9)
  - **Blocks**: T14 (context tree tests)
  - **Blocked By**: T3 (needs context_tree schema + FTS5 triggers)

  **References**:
  - `~/.claude/secondbrain-sqlite/query.mjs:88-117` — searchContext() source
  - `~/.claude/secondbrain-sqlite/schema.sql:71-89` — context_tree + context_fts schema
  - `~/.claude/secondbrain-upgrade/semantic-search.js:149-157` — reference for correct FTS5 CAST join pattern
  - WHY: searchContext() uses same FTS5 join pattern as ftsSearch()

  **Acceptance Criteria**:
  - [ ] `searchContext('test')` returns results with score (bm25 rank)
  - [ ] `addContextNode()` creates node that appears in searchContext results
  - [ ] `getContextNode(id)` returns correct node
  - [ ] `getChildNodes(parent_id)` returns children
  - [ ] `getContextByDomain('tech')` returns all tech domain nodes
  - [ ] `updateContextScore(id, 0.5)` updates relevance_score
  - [ ] `deleteContextNode(id)` removes node

  **QA Scenarios**:

  \`\`\`
  Scenario: addContextNode creates searchable context entry
    Tool: Bash
    Preconditions: context_tree empty
    Steps:
      1. node -e "const ct = require('/Users/arjomagno/.claude/secondbrain-upgrade/context-tree.mjs'); ct.addContextNode('tech', 'JavaScript', 'JS programming language').then(n => { console.log('CREATED:', n.id); return ct.searchContext('JavaScript'); }).then(r => console.log('SEARCH:', r.length, 'RESULTS'))"
    Expected Result: CREATED has id, SEARCH returns >= 1 result
    Failure Indicators: Error, SEARCH returns 0
    Evidence: .sisyphus/evidence/task-07-context-tree.log

  Scenario: searchContext uses corrected FTS5 CAST join (not broken rowid join)
    Tool: Bash
    Preconditions: context_tree has 1+ entries
    Steps:
      1. node -e "const ct = require('/Users/arjomagno/.claude/secondbrain-upgrade/context-tree.mjs'); ct.searchContext('programming').then(r => { if (r.error) throw new Error(r.error); console.log('RESULTS:', r.length, r[0]?.domain); }).catch(e => console.error('FAIL:', e.message))"
    Expected Result: RESULTS >= 0 (empty OK, but NO ERROR)
    Failure Indicators: "no such column" error, "rowid" error
    Evidence: .sisyphus/evidence/task-07-fs5-join.log
  \`\`\`

  **Commit**: YES
  - Message: `feat(secondbrain): add context-tree module with working FTS5 search`
  - Files: `context-tree.mjs`

---

- [ ] 8. **Complete facts.mjs with all CRUD operations**

  **What to do**:
  - T4 created the initial facts.mjs with basic CRUD
  - This task completes the full module:
    - `getFacts(key)` — already implemented in T4
    - `setFact(key, value, source, confidence)` — already implemented in T4
    - `deleteFact(key)` — already implemented in T4
    - `updateConfidence(key, newConfidence)` — already implemented in T4
    - `listFactKeys()` — already implemented in T4
  - Verify all 5 functions work end-to-end
  - Add these additional operations:
    - `upsertFact(key, value, options)` — set with options {source, confidence, incrementConfidence}
    - `getFact(key)` — exact match (not LIKE pattern), returns single fact or null
    - `bulkSetFacts(facts[])` — set multiple facts in transaction
    - `searchFacts(query)` — full-text search on fact values
    - `getFactsByConfidence(minConfidence)` — filter by confidence threshold
    - `getFactsBySource(source)` — filter by source
  - Add example seed data loader (loads 5 facts from a seed file)

  **Must NOT do**:
  - Do NOT delete existing facts rows (preserve seed data)
  - Do NOT use DuckDB

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with T6, T7, T9)
  - **Blocks**: T15 (facts tests)
  - **Blocked By**: T4 (facts schema)

  **References**:
  - `~/.claude/secondbrain-sqlite/query.mjs:148-156` — getFacts() source reference
  - DB: `sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT * FROM facts;"` — see existing facts
  - WHY: Complete facts module for full K/V store capability

  **Acceptance Criteria**:
  - [ ] All 8 functions implemented and exported
  - [ ] `getFact('exact_key')` returns single fact or null
  - [ ] `bulkSetFacts([{key, value}])` sets multiple in one transaction
  - [ ] `searchFacts('query')` searches fact values
  - [ ] `getFactsByConfidence(0.5)` filters correctly
  - [ ] `getFactsBySource('unit_test')` filters correctly
  - [ ] All operations preserve existing 5 seed facts

  **QA Scenarios**:

  \`\`\`
  Scenario: getFact returns exact match (not LIKE)
    Tool: Bash
    Preconditions: facts has existing rows
    Steps:
      1. node -e "const f = require('/Users/arjomagno/.claude/secondbrain-upgrade/facts.mjs'); f.getFact('key_that_exists').then(r => console.log('EXACT:', r ? 'FOUND' : 'NULL'))"
    Expected Result: EXACT: FOUND (or NULL if key doesn't exist — no error)
    Failure Indicators: Error thrown
    Evidence: .sisyphus/evidence/task-08-facts-exact.log

  Scenario: bulkSetFacts sets multiple facts atomically
    Tool: Bash
    Preconditions: 5 facts exist
    Steps:
      1. node -e "const f = require('/Users/arjomagno/.claude/secondbrain-upgrade/facts.mjs'); f.bulkSetFacts([{key: 'bulk1', value: 'v1'}, {key: 'bulk2', value: 'v2'}]).then(() => f.getFacts(null)).then(r => console.log('TOTAL:', r.length))"
      2. Clean up: f.deleteFact('bulk1'); f.deleteFact('bulk2')
    Expected Result: TOTAL >= 7 (5 original + 2 new)
    Failure Indicators: Error, TOTAL still 5
    Evidence: .sisyphus/evidence/task-08-facts-bulk.log
  \`\`\`

  **Commit**: YES
  - Message: `feat(secondbrain): complete facts.mjs CRUD — bulk ops, filters, exact get`
  - Files: `facts.mjs`

---

- [ ] 9. **Port create-note.mjs CLI skeleton + pillar helpers**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/create-note.mjs`
  - Key differences from source:
    - Writes to `vault_notes` table (DB), NOT filesystem
    - Uses 4-pillar system (magno/tech/style/tirol), not 6-pillar SOUL structure
    - Uses upgrade's `pillar-classifier.mjs` for keyword classification
    - Uses `note_pillars` join table for pillar assignment
  - CLI commands to port:
    - `create <title> <content>` — create note with auto-pillar classification
    - `capture <text>` — quick capture with auto-generated title
    - `analyze <text>` — show classification analysis only
    - `pillars` — list all 4 pillars
  - Options: `--pillar <key>`, `--dry-run`
  - Helper functions to port (adapted to 4-pillar):
    - `suggestTitle(text)` — first sentence ≤60 chars or `Capture YYYY-MM-DD`
    - `generateClarifyingQuestions(text, classification)` — 3 questions for capture
    - `suggestTags(text, pillarKey)` — pattern-matched tags + pillar tag
  - NOT porting: screenshot workflow, SOUL file reading (too complex for initial port)
  - Pillar routing: classifyKeyword(text) from upgrade's pillar-classifier.mjs → returns one of magno/tech/style/tirol
  - Frontmatter stored as JSON string in vault_notes.frontmatter column

  **Must NOT do**:
  - Do NOT write to filesystem (no ~/Documents/ArjoSecondBrain/)
  - Do NOT use 6-pillar SOUL structure
  - Do NOT use DuckDB

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with T6, T7, T8)
  - **Blocks**: T11 (create-note integration), T16 (create-note tests)
  - **Blocked By**: T5 (fixtures)

  **References**:
  - `~/.claude/secondbrain-sqlite/create-note.mjs:1-416` — COMPLETE source to port
  - `~/.claude/secondbrain-upgrade/pillar-classifier.mjs` — 4-pillar keyword classifier
  - `~/.claude/secondbrain-upgrade/schema/upgrade-v4-pillar-segregation.sql` — note_pillars table schema
  - WHY: create-note CLI is needed for manual note ingestion

  **Acceptance Criteria**:
  - [ ] `node create-note.mjs create "Test Title" "Test content"` creates note in vault_notes
  - [ ] `node create-note.mjs analyze "JavaScript code"` shows pillar classification
  - [ ] `node create-note.mjs pillars` lists 4 pillars (magno, tech, style, tirol)
  - [ ] `node create-note.mjs capture "quick thought"` auto-generates title
  - [ ] `node create-note.mjs create --dry-run` previews without creating

  **QA Scenarios**:

  \`\`\`
  Scenario: create command inserts note into vault_notes
    Tool: Bash
    Preconditions: vault_notes accessible
    Steps:
      1. cd ~/.claude/secondbrain-upgrade && node create-note.mjs create "Prometheus Test Note" "Testing the create-note CLI" 2>&1
      2. sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT title, pillar FROM vault_notes v JOIN note_pillars np ON v.id = np.note_id WHERE title = 'Prometheus Test Note';"
      3. Cleanup: sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "DELETE FROM vault_notes WHERE title = 'Prometheus Test Note';"
    Expected Result: title found, pillar column has value (magno/tech/style/tirol)
    Failure Indicators: Error, note not created
    Evidence: .sisyphus/evidence/task-09-create-note.log

  Scenario: pillars command lists 4 pillars
    Tool: Bash
    Preconditions: None
    Steps:
      1. cd ~/.claude/secondbrain-upgrade && node create-note.mjs pillars 2>&1
    Expected Result: Output shows magno, tech, style, tirol (4 pillars)
    Failure Indicators: Shows 6 pillars, or error
    Evidence: .sisyphus/evidence/task-09-pillars-list.log
  \`\`\`

  **Commit**: YES
  - Message: `feat(secondbrain): port create-note CLI (4-pillar, DB-only, no filesystem)`
  - Files: `create-note.mjs`

- [ ] 10. **Vault sync → FTS5 reindex trigger on note insert/update**

  **What to do**:
  - The FTS5 virtual table `vault_fts` uses `content='vault_notes', content_rowid='id'`
  - Currently only 1098/1921 notes are indexed (57%) — the join bug + missing reindex
  - After T1 (FTS5 join fix) and T6 (vault sync engine), ensure FTS5 stays in sync:
  - Add an AFTER INSERT + AFTER UPDATE trigger on `vault_notes` that inserts into `vault_fts`:
    ```sql
    CREATE TRIGGER IF NOT EXISTS vault_notes_ai AFTER INSERT ON vault_notes BEGIN
      INSERT INTO vault_fts(rowid, title, content) VALUES (CAST(new.id AS INTEGER), new.title, new.content);
    END;
    CREATE TRIGGER IF NOT EXISTS vault_notes_au AFTER UPDATE ON vault_notes BEGIN
      INSERT INTO vault_fts(vault_fts, rowid, title, content) VALUES ('delete', CAST(old.id AS INTEGER), old.title, old.content);
      INSERT INTO vault_fts(rowid, title, content) VALUES (CAST(new.id AS INTEGER), new.title, new.content);
    END;
    ```
  - Also add AFTER DELETE trigger:
    ```sql
    CREATE TRIGGER IF NOT EXISTS vault_notes_ad AFTER DELETE ON vault_notes BEGIN
      INSERT INTO vault_fts(vault_fts, rowid, title, content) VALUES ('delete', CAST(old.id AS INTEGER), old.title, old.content);
    END;
    ```
  - Create as a new migration: `upgrade-v7-fts5-triggers.sql`
  - NOTE: These triggers already exist for `vault_notes` (source had them). Verify they exist. If missing, add them.

  **Must NOT do**:
  - Do NOT recreate vault_fts — the table exists with 1098 rows
  - Do NOT use `vn.rowid` in any new triggers — must use `CAST(new.id AS INTEGER)`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with T11, T12)
  - **Blocks**: T17 (FTS5 trigger tests)
  - **Blocked By**: T1 (FTS5 join fix), T6 (vault sync engine)

  **References**:
  - `~/.claude/secondbrain-sqlite/schema.sql:29-45` — source triggers for vault_fts
  - DB: `sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='vault_notes';"`
  - WHY: FTS5 must stay in sync when vault_notes changes

  **Acceptance Criteria**:
  - [ ] `vault_notes_ai` trigger exists and fires on INSERT
  - [ ] `vault_notes_au` trigger exists and fires on UPDATE
  - [ ] `vault_notes_ad` trigger exists and fires on DELETE
  - [ ] After INSERT to vault_notes, vault_fts row count increases

  **QA Scenarios**:

  \`\`\`
  Scenario: INSERT to vault_notes triggers FTS5 reindex
    Tool: Bash
    Preconditions: vault_fts has N rows
    Steps:
      1. sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "INSERT INTO vault_notes (id, file_path, file_name, folder, title, content, frontmatter, word_count, created_at, modified_at) VALUES ('test-fts-trigger', '/tmp/test.md', 'test.md', '/tmp', 'FTS Test', 'Testing FTS triggers', '{}', 3, datetime('now'), datetime('now'));"
      2. sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT COUNT(*) FROM vault_fts WHERE rowid = CAST('test-fts-trigger' AS INTEGER);"
      3. Cleanup: sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "DELETE FROM vault_notes WHERE id = 'test-fts-trigger';"
    Expected Result: vault_fts has N+1 indexed rows for the new note
    Failure Indicators: vault_fts count unchanged — trigger not working
    Evidence: .sisyphus/evidence/task-10-fts5-trigger.log
  \`\`\`

  **Commit**: YES
  - Message: `fix(secondbrain): add vault_notes→vault_fts AFTER INSERT/UPDATE/DELETE triggers`
  - Files: `schema/upgrade-v7-fts5-triggers.sql`

---

- [ ] 11. **Create-note → integrate with vault_notes + note_pillars + pillar-classifier**

  **What to do**:
  - T9 created the CLI skeleton — this task completes the full integration
  - `create-note.mjs create` must:
    1. Call `classifyKeyword(title + ' ' + content)` from upgrade's pillar-classifier.mjs to get dominant pillar
    2. Insert into `vault_notes` with all required fields (id, file_path, file_name, folder, domain, title, content, frontmatter, word_count, created_at, modified_at, file_hash)
    3. Insert into `note_pillars` (note_id, pillar, confidence, assigned_at) — confidence = keyword match score
    4. Generate SHA256 hash of content as file_hash
    5. Use `CAST(id AS INTEGER)` for FTS5 rowid (matches vault_fts content_rowid='id')
  - `create-note.mjs capture` must auto-generate title using suggestTitle()
  - `create-note.mjs analyze` must call classifyKeywordSemantic() if Ollama available, else classifyKeyword()
  - `create-note.mjs pillars` must list the 4 upgrade pillars (magno/tech/style/tirol)
  - For the `domain` field in vault_notes: use the pillar name (magno/tech/style/tirol)
  - For `file_path`: generate a virtual path like `magno/auto-generated-title.md` (for display purposes only — NOT filesystem)

  **Must NOT do**:
  - Do NOT write to filesystem
  - Do NOT use 6-pillar system
  - Do NOT skip note_pillars insertion

  **Recommended Agent Profile**:
  - **Category**: `deep` — integration across 3 modules
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with T10, T12)
  - **Blocks**: T16 (create-note integration tests)
  - **Blocked By**: T9 (create-note CLI), T1 (FTS5 fix)

  **References**:
  - `~/.claude/secondbrain-sqlite/create-note.mjs:64-137` — createNote() source pattern
  - `~/.claude/secondbrain-upgrade/pillar-classifier.mjs` — classifyKeyword() and classifyKeywordSemantic()
  - `~/.claude/secondbrain-upgrade/schema/upgrade-v4-pillar-segregation.sql` — note_pillars schema
  - WHY: Full integration of create-note with the upgrade's pillar system

  **Acceptance Criteria**:
  - [ ] `create-note.mjs create "JS Bug" "There is a bug in the JS code"` creates vault_notes row AND note_pillars row
  - [ ] `note_pillars.pillar` is one of magno/tech/style/tirol
  - [ ] `analyze` shows which pillar was selected
  - [ ] FTS5 trigger fires and indexes the new note

  **QA Scenarios**:

  \`\`\`
  Scenario: create-note inserts into both vault_notes AND note_pillars
    Tool: Bash
    Preconditions: Tables exist
    Steps:
      1. cd ~/.claude/secondbrain-upgrade && node create-note.mjs create "AI Agent Design" "Building autonomous agents with LLMs" 2>&1
      2. sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "SELECT v.title, np.pillar FROM vault_notes v JOIN note_pillars np ON v.id = np.note_id WHERE v.title = 'AI Agent Design';"
      3. Cleanup: sqlite3 ~/.claude/secondbrain-sqlite/secondbrain.db "DELETE FROM note_pillars WHERE note_id = (SELECT id FROM vault_notes WHERE title = 'AI Agent Design'); DELETE FROM vault_notes WHERE title = 'AI Agent Design';"
    Expected Result: 1 row with title + pillar (tech or magno based on keywords)
    Failure Indicators: note_pillars empty for this note
    Evidence: .sisyphus/evidence/task-11-create-note-integrated.log
  \`\`\`

  **Commit**: YES
  - Message: `feat(secondbrain): integrate create-note with vault_notes + note_pillars + pillar-classifier`
  - Files: `create-note.mjs`

---

- [ ] 12. **Full integration — all modules working together**

  **What to do**:
  - This is a verification/integration task — ensure all modules work together:
    1. Run `sync.mjs incremental` — syncs vault, populates tags/links
    2. Run `create-note.mjs create` — creates new note with pillar assignment
    3. `ftsSearch()` returns results including the new note
    4. `searchContext()` works for context tree
    5. `getFacts()` returns stored facts
  - Create a test script `test-integration.mjs` that:
    1. Runs incremental sync
    2. Creates a test note via create-note
    3. Verifies note appears in vault_notes
    4. Verifies note is indexed in vault_fts
    5. Verifies note_pillars has the correct pillar
    6. Verifies vault_tags and vault_links were populated by sync
  - This is the smoke test for the entire gap-fill effort

  **Must NOT do**:
  - Do NOT modify production data (use test-prefixed notes)
  - Do NOT skip any module — all must work

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with T10, T11)
  - **Blocks**: F1-F4 (final verification)
  - **Blocked By**: T10 (FTS5 reindex), T11 (create-note integration)

  **References**:
  - All Wave 1-3 modules: T1, T6, T7, T8, T9, T10, T11
  - WHY: End-to-end smoke test

  **Acceptance Criteria**:
  - [ ] `node test-integration.mjs` completes without error
  - [ ] All 5 modules verified: sync, ftsSearch, context-tree, facts, create-note
  - [ ] No production data corruption

  **QA Scenarios**:

  \`\`\`
  Scenario: Full integration test — all modules work together
    Tool: Bash
    Preconditions: All modules implemented
    Steps:
      1. cd ~/.claude/secondbrain-upgrade && node test-integration.mjs 2>&1
    Expected Result: All checks pass, no errors
    Failure Indicators: Any module returning error or wrong count
    Evidence: .sisyphus/evidence/task-12-integration.log
  \`\`\`

  **Commit**: YES
  - Message: `test(secondbrain): add integration smoke test`
  - Files: `test-integration.mjs`

- [ ] 13. **Test 13 — vault-sync.js (8 tests)**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/tests/validation/13-vault-sync.js`
  - Follow existing test pattern from TEST-FRAMEWORK.js
  - Tests to cover:
    1. `sync full` processes all vault files
    2. `sync incremental` skips unchanged files
    3. `sync incremental` detects new files
    4. `sync incremental` detects deleted files
    5. vault_tags populated correctly from #tag extraction
    6. vault_links populated correctly from [[wiki-link]] extraction
    7. sync_state tracks file_hash correctly
    8. frontmatter parsed and stored in vault_notes.frontmatter
  - Use `createTestNote` for setup where needed
  - Use actual sync.mjs calls (child_process spawn or direct require with mocking)
  - Cleanup: remove test notes and sync_state entries

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low` — follows existing test patterns
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with T14, T15, T16, T17)
  - **Blocks**: F1-F4
  - **Blocked By**: T6 (vault sync engine)

  **References**:
  - `~/.claude/secondbrain-upgrade/tests/validation/11-full-cycle.js` — example test pattern
  - WHY: Test the critical missing piece

  **QA Scenarios**: Tests themselves are the QA — run `node tests/validation/TEST-runner.js` and verify 13-vault-sync shows 8/8 PASS.

  **Commit**: YES
  - Message: `test(secondbrain): add vault-sync validation tests`
  - Files: `tests/validation/13-vault-sync.js`

---

- [ ] 14. **Test 14 — context-tree.js (7 tests)**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/tests/validation/14-context-tree.js`
  - Tests:
    1. `addContextNode()` creates node
    2. `getContextNode(id)` returns correct node
    3. `getChildNodes(parent_id)` returns children
    4. `getContextByDomain(domain)` filters correctly
    5. `searchContext(query)` returns FTS-ranked results
    6. `updateContextScore()` updates score
    7. `deleteContextNode()` removes node
  - Use `createTestContextNode` fixture (T5)
  - Cleanup: delete test context nodes after each test

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with T13, T15, T16, T17)
  - **Blocks**: F1-F4
  - **Blocked By**: T7 (context-tree module)

  **References**:
  - `~/.claude/secondbrain-upgrade/tests/validation/09-phase7-pillar-segregation.js` — example test pattern
  - WHY: Test context tree module

  **QA Scenarios**: Tests are the QA — run TEST-runner.js and verify 14-context-tree shows 7/7 PASS.

  **Commit**: YES
  - Message: `test(secondbrain): add context-tree validation tests`
  - Files: `tests/validation/14-context-tree.js`

---

- [ ] 15. **Test 15 — facts-kv.js (7 tests)**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/tests/validation/15-facts-kv.js`
  - Tests:
    1. `getFacts(null)` returns all facts
    2. `getFacts(key)` returns matching facts (LIKE pattern)
    3. `getFact(key)` returns exact match or null
    4. `setFact()` creates new fact
    5. `deleteFact()` removes fact
    6. `updateConfidence()` changes confidence
    7. `bulkSetFacts()` sets multiple atomically
  - Use `createTestFact` fixture (T5)
  - Must NOT delete existing seed facts (5 rows in DB)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with T13, T14, T16, T17)
  - **Blocks**: F1-F4
  - **Blocked By**: T8 (facts.mjs)

  **References**:
  - `~/.claude/secondbrain-upgrade/tests/validation/10-pillar-learning.js` — example fixture-based test
  - WHY: Test facts K/V store

  **QA Scenarios**: Tests are the QA — run TEST-runner.js and verify 15-facts-kv shows 7/7 PASS.

  **Commit**: YES
  - Message: `test(secondbrain): add facts-kv validation tests`
  - Files: `tests/validation/15-facts-kv.js`

---

- [ ] 16. **Test 16 — create-note-cli.js (6 tests)**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/tests/validation/16-create-note-cli.js`
  - Tests:
    1. `create` command inserts into vault_notes
    2. `create` command inserts into note_pillars
    3. `capture` auto-generates title
    4. `analyze` returns pillar classification
    5. `pillars` lists 4 pillars
    6. `create --dry-run` previews without inserting
  - Use child_process spawn to run create-note.mjs
  - Cleanup: DELETE test notes and note_pillars after each test

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with T13, T14, T15, T17)
  - **Blocks**: F1-F4
  - **Blocked By**: T11 (create-note integration)

  **References**:
  - `~/.claude/secondbrain-upgrade/tests/validation/12-pillar-centroids.js` — CLI output testing pattern
  - WHY: Test create-note CLI

  **QA Scenarios**: Tests are the QA — run TEST-runner.js and verify 16-create-note-cli shows 6/6 PASS.

  **Commit**: YES
  - Message: `test(secondbrain): add create-note-cli validation tests`
  - Files: `tests/validation/16-create-note-cli.js`

---

- [ ] 17. **Test 17 — fts5-fix.js (5 tests)**

  **What to do**:
  - Create `~/.claude/secondbrain-upgrade/tests/validation/17-fts5-fix.js`
  - Tests:
    1. `ftsSearch('test')` returns results (join fix working)
    2. `ftsSearch('test')` results have `rank` field
    3. `ftsSearch('')` returns empty array (no error)
    4. `ftsSearch('nonexistent')` returns empty array (no error)
    5. `hybridSearch()` combines FTS + semantic correctly
  - No fixtures needed — uses existing vault_fts data
  - Verify ftsSearch is no longer broken (T1 fix)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
  - **Skills**: none
  - **Skills Evaluated but Omitted**: n/a

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with T13, T14, T15, T16)
  - **Blocks**: F1-F4
  - **Blocked By**: T1 (FTS5 join fix)

  **References**:
  - `~/.claude/secondbrain-upgrade/tests/validation/11-pillar-retrieval.js` — search testing pattern
  - WHY: Verify the FTS5 join fix actually works

  **QA Scenarios**: Tests are the QA — run TEST-runner.js and verify 17-fts5-fix shows 5/5 PASS.

  **Commit**: YES
  - Message: `test(secondbrain): add FTS5 join fix validation tests`
  - Files: `tests/validation/17-fts5-fix.js`

---

## Final Verification Wave

- [ ] F1. **Plan Compliance Audit** — `oracle`
- [ ] F2. **Code Quality Review** — `unspecified-high`
- [ ] F3. **Real Manual QA** — `unspecified-high`
- [ ] F4. **Scope Fidelity Check** — `deep`

---

## Commit Strategy
- T1-T5: `chore(secondbrain): foundation fixes`
- T6-T9: `feat(secondbrain): core modules`
- T10-T12: `feat(secondbrain): integration`
- T13-T17: `test(secondbrain): gap-fill tests`

---

## Success Criteria
- `node sync.mjs full` → 0 errors
- `ftsSearch('test')` → returns results (not empty/error)
- `searchContext('query')` → returns bm25-ranked results
- `getFacts('key')` → returns stored value
- `create-note.mjs create "Test" "Content"` → note in vault_notes
- All 5 test modules → PASS
