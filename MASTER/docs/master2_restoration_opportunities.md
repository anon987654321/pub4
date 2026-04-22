# MASTER2 Restoration Opportunities

This document enumerates the gaps between the **MASTER2** reference implementation and the current **MASTER** repository. Restoring the missing artefacts will bring MASTER back to feature parity and unlock the full runtime, CLI, policies, tests, and documentation stack.

## Snapshot

| Metric                | MASTER2 | MASTER | Missing |
|----------------------:|--------:|-------:|--------:|
| Files scanned         | **388** | **107** | **381** |
| Top‑level directories | `lib/`, `bin/`, `docs/`, `data/`, `test/`, `.github/`, `completions/` | `lib/` (core only) | – |
| Effort (high‑level)   | 235 runtime files + 6 CLI + 30 policy + 93 tests + 5 docs | – | – |

**Goal:** Restore the 381 missing artefacts, prioritising high‑impact runtime and CLI components first.

## Opportunities by Area

| Area                              | Missing items | High‑impact restorations | Impact |
|----------------------------------:|--------------:|--------------------------|--------|
| **Core runtime (`lib/`)**         | 235 files     | `lib/master.rb`, `lib/master/agent.rb`, `lib/master/memory.rb`, `lib/master/session.rb`, `lib/master/platform.rb`, `lib/master/cli.rb` | ★★★★★ |
| **CLI & utilities (`bin/`, `completions/`)** | 6 files      | `bin/master`, `bin/mcp_server`, `bin/weekly`, Zsh completion `_master`, simulation & validation scripts | ★★★ |
| **Policy & config (`data/`)**     | 30 files      | Model/persona catalogs, pipeline definitions, quality gates, hook scripts, prompt templates | ★★ |
| **Tests & quality (`test/`, `.rubocop.yml`)** | 93 files | End‑to‑end orchestration specs, security‑gate unit tests, LLM flow fixtures, pipeline regression suites | ★★★★ |
| **Docs & automation (`docs/`, `scripts/`, `.github/`)** | 5 files | Deployment guide, CI workflow, OpenBSD execution notes, video‑narration markdown | ★ |

*Stars indicate relative impact (★ = low, ★★★★★ = critical).*

## Full Restoration Inventory

### 1. Config & Boilerplate
- `.env.example`
- `.rubocop.yml`
- `.gitignore`
- `.session_recovery.template`

### 2. GitHub Support
- `.github/copilot-instructions.md`
- `.github/workflows/test.yml`

### 3. Documentation
- `README.md`
- `AGENTS.md`
- `CLAUDE.md`
- `LLM.md`
- `Rakefile`
- `instructions.txt`
- `docs/openbsd_execution.md`
- `docs/video_narration.md`

### 4. Binaries (`bin/`)
- `bin/master` — main entry point  
- `bin/mcp_server` — MCP service daemon  
- `bin/simulate` — simulation harness  
- `bin/validate` — test‑suite validator  
- `bin/weekly` — scheduled maintenance runner  

### 5. Shell Completions
- `completions/_master` — Zsh completion script

### 6. Policy & Data (`data/`)
- 30+ YAML/JSON files (model catalogs, persona definitions, pipeline specs, quality thresholds, hook configs, prompt templates, etc.)

### 7. Tests (`test/`)
- Unit and integration suites covering:
  - Core orchestration (`Master::Pipeline`, `Master::Agent`)
  - Security gates (`Master::Security::Permissions`, `InjectionGuard`)
  - LLM tool interactions (`Master::Tools::*`)
  - Routing and model selection
  - End‑to‑end scenario simulations

## Prioritisation Roadmap

1. **Core Runtime** – restore `lib/master.rb` and its subsystems; without them the system cannot start.  
2. **CLI Entrypoint** – bring back `bin/master` and `bin/mcp_server` to enable operator control.  
3. **Policy Catalogs** – load model/persona configurations so the runtime can make informed decisions.  
4. **Test Suite** – add missing tests to guard against regressions and to drive future refactors.  
5. **Documentation & CI** – ensure new contributors can set up, run, and verify the system reliably.

## Next Steps

1. Fork the repository.  
2. Create a `restoration` branch.  
3. Incrementally copy missing files from MASTER2, adjusting module namespaces where necessary.  
4. Run the test suite after each batch to surface integration issues early.  
5. Update the `README` with restoration‑status badges.

Restoring these artefacts will reconstitute the full MASTER2 feature set, improve reliability, and provide a solid foundation for future development.