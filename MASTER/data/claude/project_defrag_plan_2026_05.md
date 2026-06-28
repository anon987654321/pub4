---
name: pub4 defrag/dedup/rename plan (2026-05-07)
description: Multi-commit refactor plan from a sister chat — collapse duplication across docs, shrink data/, flatten repo root, rename for clarity. Priority-1 (Master::Orient) shipped then reverted on 2026-05-20 as a useless wrapper.
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
**2026-05-20:** `Master::Orient` and `/orient` removed — five constitutional YAMLs already in every system prompt via Constitution/Personality. Rest of plan stands.

**2026-05-07 proposal:** (1) single source of truth — one yml per fact, prose references only; (2) data/ 11→8 files (merge council, infer/sweep/zsh → `patterns.yml`); (3) root 26→10 (`__predecessors/`, `audio/`, `scripts/`, `web/`, `memory/`); (4) renames — `deploy/openbsd.sh`, `state.yml`, `limits.yml`, `voice.yml`, `style.yml`; CONVENTIONS.md generated or deleted; (5) smoothing — stash before `git reset --hard`, explicit `scope:` on `Master.build`, unify `Result`, per-stage budget in `limits.yml`, reconcile Guard/auto-approve, unify `exe/master` boot, generalize WhyExplainer lookup-then-LLM.

**Priority-1 (reverted):** `orient.rb`, slim AGENTS/CLAUDE, `/orient` + subcommand, zshrc `[[ -t 0 ]]` guard.

One fact = one place; small reversible commits; smoothing items are follow-up tickets.