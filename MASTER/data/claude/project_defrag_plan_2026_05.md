---
name: pub4 defrag/dedup/rename plan (2026-05-07)
description: Multi-commit refactor plan from a sister chat — collapse duplication across docs, shrink data/, flatten repo root, rename for clarity. Priority-1 (Master::Orient) shipped then reverted on 2026-05-20 as a useless wrapper.
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---

On 2026-05-20, `Master::Orient` and `/orient` were removed—the five constitutional YAMLs already appear in every system prompt via Constitution and Personality. The rest of the plan stands.

The 2026-05-07 proposal aimed for a single source of truth with one yml per fact and prose references only; shrinking `data/` from eleven to eight files by merging council, infer, sweep, and zsh into `patterns.yml`; flattening the repo root from twenty-six to ten entries including `__predecessors/`, `audio/`, `scripts/`, `web/`, and `memory/`; renames such as `deploy/openbsd.sh`, `state.yml`, `limits.yml`, `voice.yml`, and `style.yml`, with CONVENTIONS.md generated or deleted; and smoothing work—stash before `git reset --hard`, explicit `scope:` on `Master.build`, unified `Result`, per-stage budget in `limits.yml`, reconciled Guard and auto-approve, unified `exe/master` boot, and generalized WhyExplainer lookup-then-LLM.

Priority-1 Orient work—`orient.rb`, slim AGENTS and CLAUDE, `/orient` plus subcommand, zshrc `[[ -t 0 ]]` guard—shipped then reverted as a useless wrapper. One fact equals one place; commits stay small and reversible; smoothing items remain follow-up tickets.