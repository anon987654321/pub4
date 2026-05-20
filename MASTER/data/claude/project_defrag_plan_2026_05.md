---
name: pub4 defrag/dedup/rename plan (2026-05-07)
description: Multi-commit refactor plan from a sister chat — collapse duplication across docs, shrink data/, flatten repo root, rename for clarity. Priority-1 (Master::Orient) shipped then reverted on 2026-05-20 as a useless wrapper.
type: project
originSessionId: 038b16d9-fc5e-4144-9a47-5bd746b2d3ac
---
**Update 2026-05-20:** Master::Orient and the `/orient` slash command were removed. The five constitutional YAMLs are already injected into every system prompt by Constitution/Personality — `/orient` just re-exposed data the LLM already had. The rest of the plan (data/ shrinks, top-level shrinks, renames, smoothing) is independent.

User shared a full defrag/dedup/rename proposal on 2026-05-07 covering:

1. **Single source of truth** — banned commands, voice rules, ASCII-art ban, house rules currently duplicated across AGENTS.md / CLAUDE.md / data/*.yml. Move each fact to one yml file; prose docs reference, never restate.
2. **data/ shrinks 11 → 8 files** — merge `council.yml`+`council_patterns.yml`, merge `infer_patterns.yml`+`sweep_prompts.yml`+`zsh_patterns.yml` → `patterns.yml` (namespaced).
3. **Top-level shrinks 26 → 10 entries** — fold `pub`/`pub2`/`pub3`/`railsy` into `__predecessors/`, merge `mix/`+`multimedia/`+`.mp3/` → `audio/`, merge `sh/`+`scripts/`+`bp/` → `scripts/`, static HTML → `web/`, rename `:memory:/` → `memory/`.
4. **Renames** — `MASTER/DEPLOY/openbsd/openbsd.sh` → `MASTER/deploy/openbsd.sh`; `data/standing_orders.yml` → `state.yml`; `workflow.yml` → `limits.yml`; `rules.yml` → `voice.yml`; `ruby_style.yml` → `style.yml`. CONVENTIONS.md either generated to tmp/ or deleted.
5. **Smoothing** — `master orient` command replaces five-cat bootstrap. Stash before `git reset --hard`. Replace `Thread.current[:master_visitor]` with explicit `scope:` arg on `Master.build`. Unify two `Result` impls (the `respond_to?(:ok?)` smell). Pipeline per-stage budget in `limits.yml`. Reconcile `Guard` stage with auto-approve. Unify `exe/master` boot paths (rcd + ssh-autostart). Generalize WhyExplainer's local-lookup-then-LLM pattern.

**Priority-1 patch (drop-in code provided):**
- `MASTER/lib/master/orient.rb` — 35 LOC, prints all five bootstrap yml files
- Slimmed `AGENTS.md` (46 → 27 lines) and `CLAUDE.md` (238 → ~85 lines) — delete duplicated constitution, point at `/orient`
- CLI dispatch: add `/orient` slash branch and `orient` subcommand
- `~/.zshrc` top: `[[ -o interactive ]] || return` + `[[ -t 0 ]] || return` to fix non-interactive SSH stealing stdin
- Commit message provided: "master: collapse five-cat bootstrap into orient"

**Why:** Reduce drift (one fact = one place), reduce friction (one command vs five cats), shrink visual surface so the repo reads in one screen. Each move is independently shippable.

**How to apply:** Treat priority-1 as the next reversible commit when user greenlights. Treat the broader plan as a sequence of small commits — never bundle. The smoothing items (#3-#9 of execution path) are individual follow-up tickets.
