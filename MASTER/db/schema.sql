-- MASTER SQLite Schema
-- Single source of truth for all configuration and state

CREATE TABLE IF NOT EXISTS principles (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  text TEXT NOT NULL,
  protection_level TEXT NOT NULL CHECK(protection_level IN ('absolute','protected','negotiable','flexible')),
  category TEXT,
  tier TEXT,
  priority INTEGER DEFAULT 50,
  weight REAL DEFAULT 1.0,
  active INTEGER DEFAULT 1,
  auto_fixable INTEGER DEFAULT 0,
  created_at INTEGER DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_principles_protection ON principles(protection_level);
CREATE INDEX IF NOT EXISTS idx_principles_active ON principles(active);
CREATE INDEX IF NOT EXISTS idx_principles_category ON principles(category);

CREATE TABLE IF NOT EXISTS personas (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  greeting TEXT,
  traits TEXT,  -- JSON array
  style TEXT,
  focus TEXT,   -- JSON array
  sources TEXT, -- JSON array
  rules TEXT,   -- JSON array
  system_prompt TEXT,
  weight REAL DEFAULT 0.15,
  veto_domains TEXT,  -- JSON array of domains this persona can veto
  active INTEGER DEFAULT 1,
  created_at INTEGER DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_personas_active ON personas(active);
CREATE INDEX IF NOT EXISTS idx_personas_name ON personas(name);

CREATE TABLE IF NOT EXISTS memory (
  id INTEGER PRIMARY KEY,
  content TEXT NOT NULL,
  embedding BLOB,  -- vector embedding as packed floats
  context TEXT,     -- what conversation/task this belongs to
  decay_factor REAL DEFAULT 1.0,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  accessed_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_memory_context ON memory(context);
CREATE INDEX IF NOT EXISTS idx_memory_created ON memory(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_memory_accessed ON memory(accessed_at DESC);

CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY,
  messages TEXT NOT NULL,  -- JSON array of messages
  context TEXT,
  total_cost REAL DEFAULT 0.0,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_sessions_created ON sessions(created_at DESC);

CREATE TABLE IF NOT EXISTS costs (
  id INTEGER PRIMARY KEY,
  model TEXT NOT NULL,
  tier TEXT,
  tokens_in INTEGER DEFAULT 0,
  tokens_out INTEGER DEFAULT 0,
  cost_usd REAL DEFAULT 0.0,
  session_id INTEGER REFERENCES sessions(id),
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_costs_created ON costs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_costs_model ON costs(model);
CREATE INDEX IF NOT EXISTS idx_costs_session ON costs(session_id);

CREATE TABLE IF NOT EXISTS evolution (
  id INTEGER PRIMARY KEY,
  file_path TEXT NOT NULL,
  before_sha TEXT,
  after_sha TEXT,
  diff TEXT,
  test_result INTEGER,  -- 1=passed, 0=failed
  rolled_back INTEGER DEFAULT 0,
  reason TEXT,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_evolution_file ON evolution(file_path);
CREATE INDEX IF NOT EXISTS idx_evolution_created ON evolution(created_at DESC);

CREATE TABLE IF NOT EXISTS hooks (
  id INTEGER PRIMARY KEY,
  event TEXT NOT NULL,  -- before_edit, after_fix, on_stuck, etc.
  handler TEXT NOT NULL,  -- Ruby class/method or shell command
  priority INTEGER DEFAULT 50,
  active INTEGER DEFAULT 1,
  created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_hooks_event ON hooks(event);
CREATE INDEX IF NOT EXISTS idx_hooks_active ON hooks(active);

CREATE TABLE IF NOT EXISTS config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  protection_level TEXT DEFAULT 'flexible',
  description TEXT,
  created_at INTEGER DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE TABLE IF NOT EXISTS quality_checks (
  id INTEGER PRIMARY KEY,
  file_path TEXT NOT NULL,
  check_type TEXT NOT NULL,  -- metz, complexity, dry, coverage
  passed INTEGER DEFAULT 0,
  score REAL,
  details TEXT,  -- JSON
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_quality_file ON quality_checks(file_path);
CREATE INDEX IF NOT EXISTS idx_quality_type ON quality_checks(check_type);
CREATE INDEX IF NOT EXISTS idx_quality_created ON quality_checks(created_at DESC);

-- Circuit breaker state for models
CREATE TABLE IF NOT EXISTS circuit_breakers (
  id INTEGER PRIMARY KEY,
  model TEXT NOT NULL UNIQUE,
  failure_count INTEGER DEFAULT 0,
  last_failure_at INTEGER,
  state TEXT DEFAULT 'closed' CHECK(state IN ('closed','open','half_open')),
  opened_at INTEGER,
  updated_at INTEGER DEFAULT (strftime('%s', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_circuit_model ON circuit_breakers(model);
CREATE INDEX IF NOT EXISTS idx_circuit_state ON circuit_breakers(state);
