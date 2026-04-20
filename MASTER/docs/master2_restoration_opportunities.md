# MASTER2Restoration Opportunities

This inventory compares the `MASTER2` directory to `MASTER` and lists items present in `MASTER2` but missing from `MASTER`. Restoring these gaps would achieve feature parity.

## Snapshot
- MASTER2 files scanned: **388**  
- MASTER files scanned: **107**  
- Missing in MASTER: **382**

## Opportunities by Area
1. **Core runtime and capabilities (`lib/`)** — 235 files.  
   - Largest gaps: agent subsystems (`agent`, `analysis`, `review`, `workflow`, `ui`, `session`).  
   - High‑impact restorations: `lib/master.rb`, `lib/commands.rb`, `lib/analysis.rb`, `lib/review.rb`, `lib/workflow.rb`, `lib/llm.rb`, `lib/server.rb`.

2. **CLI and operator workflows (`bin/`, `completions/`)** — 6 files.  
   - Missing CLIs and utilities: `bin/master`, `bin/mcp_server`, `bin/weekly`, simulation/validation tools, and zsh completions.

3. **Policy/config intelligence (`data/`)** — 30 files.  
   - Missing policy catalogs for models, personas, pipelines, quality gates, hooks, and prompts.

4. **Quality/safety regression net (`test/`, `.rubocop.yml`)** — 93 files.  
   - Missing end‑to‑end and unit tests for core orchestration, security gates, LLM flows, and pipeline behavior.

5. **Operational docs and automation (`docs/`, `scripts/`, `.github/`)** — 5 files.  
   - Missing deployment/testing documentation and CI workflow automation.

## Full Restoration Inventory
### Config files
- `.env.example`
- `.rubocop.yml`
- `.gitignore`
- `.session_recovery.template`

### GitHub
- `.github/copilot-instructions.md`
- `.github/workflows/test.yml`

### Documentation
- `AGENTS.md`
- `CLAUDE.md`
- `LLM.md`
- `README.md`
- `Rakefile`
- `instructions.txt`
- `docs/openbsd_execution.md`
- `docs/video_narration.md`

### Binaries- `bin/master`
- `bin/mcp_server`
- `bin/simulate`
- `bin/validate`
- `bin/weekly`

### Completions
- `completions/_master`

### Data
- 30 policy/config files (catalogs, pipelines, thresholds, etc.)