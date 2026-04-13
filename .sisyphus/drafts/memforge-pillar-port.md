# Draft: MemForge 4-Pillar Auto-Segregation Port

## User Goal
Port DuckDB's 4-pillar auto-segregation (magno/tech/style/tirol) into MemForge/SQLite with full keyword sync + Ollama semantic fallback + outcome learning, plus comprehensive tests.

## Source System
- DuckDB: `relayReasoningEngine.ts` — 886 lines, key exports: `PILLARS`, `PILLAR_SEEDS`, `classifyKeyword()`, `classifyKeywordSemantic()`, `learnFromOutcome()`, `extractKeywords()`, `STOP_WORDS`

## Target System
- MemForge/SQLite at `~/.claude/secondbrain-upgrade/`
- Existing Ollama client: `embeddings.js` (generates 768-dim nomic-embed-text vectors)

## What's Being Ported

### Pillar Definitions
```
PILLARS = ['magno', 'tech', 'style', 'tirol']
- magno (~60 keywords): people, relationship, trust, empathy, community, team, feedback
- tech (~60 keywords): code, bug, deploy, api, database, docker, typescript, react
- style (~60 keywords): design, ui, ux, color, aesthetic, brand, creative, figma
- tirol (~60 keywords): revenue, profit, client, sales, growth, operations
```

### classifyKeyword(keyword) -> PillarName
- Exact seed match → return that pillar
- 4-char prefix match → return that pillar  
- Fallback → 'tech'

### classifyKeywordSemantic(keyword) -> Promise<PillarName>
- Try sync first; if 'tech' fallback, use Ollama
- Precomputed centroid embeddings per pillar (cached)
- Cosine similarity → best pillar; 'tech' if Ollama offline

### learnFromOutcome(noteIds[], outcome) 
- Hook into `retrieval/outcome.js:recordRetrievalOutcome()`
- Extract up to 5 keywords per note
- Classify each keyword to pillar
- Bump (pillar, keyword, outcome) in `pillar_stats` table

### Phase 7: PillarSegregation
- `sleep-cycle/phases/pillar-segregation.js`
- Reads graduated notes
- Classifies each note content to dominant pillar
- Stores in `note_pillars` table

### Schema Changes
```sql
CREATE TABLE note_pillars (
  note_id TEXT PRIMARY KEY,
  pillar TEXT NOT NULL,
  pillar_strength REAL DEFAULT 0.5,
  keywords TEXT DEFAULT '[]',
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE pillar_stats (
  pillar TEXT PRIMARY KEY,
  positive INTEGER DEFAULT 0,
  negative INTEGER DEFAULT 0,
  weight REAL DEFAULT 0.5,
  updated_at TEXT DEFAULT (datetime('now'))
);
```

## Test Plan
1. Unit: `classifyKeyword()` — seed match, prefix match, fallback
2. Unit: `classifyKeywordSemantic()` — mock Ollama
3. Unit: `extractKeywords()` — stop word removal, dedup, limit
4. Unit: `learnFromOutcome()` — positive/negative bumps
5. Integration: Phase 7 full segregation run
6. Integration: Ollama offline graceful degradation to 'tech'
7. Integration: `note_pillars` and `pillar_stats` table updates

## Open Questions
- Semantic centroids: precompute once and cache in SQLite? (Yes)
- Phase 7: every sleep cycle or on-demand? (Every cycle, lightweight)
- Backfill existing notes? (Yes — one-time migration)
