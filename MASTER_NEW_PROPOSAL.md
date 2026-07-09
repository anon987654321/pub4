# MASTER_NEW_PROPOSAL.md

**Status (2026-07-09):** M2, M3, M5–M8 implemented or satisfied. **M1 and M4 remain**
— blocked on the Bridge vs Replace product decision documented in `core/ABSORPTION.md`
(§ "The runtime cutover is a reimplementation, not a deletion"). Delete this file only
after M1 absorption cutover and M4 CoreBridge sunset are complete.

## Remaining work

### M1 — Absorption program (blocked: Bridge vs Replace)
Slices 0–4 done per `core/ABSORPTION.md`. Slices 5–6 (CLI cutover, sever lib boot
dependencies) require choosing Bridge (wire CLI through Fold) or Replace (Fold-only
runtime). `lib/` still ~368 files until cutover lands.

### M4 — CoreBridge sunset (blocked: same gate)
Delete `lib/now/core_bridge.rb`, `/fold` alias, and `bin/cli --fold` only when
`command_registry` routes every handler through `Master::Core` — not yet true.

## Done

- **M2** — `test/core/test_no_lib_backedges.rb`
- **M3** — `test/core/test_verb_closure.rb` (closed verb set)
- **M5** — `bin/check` profiles are the gate entrypoint (`full` → ci + probe + audit)
- **M6** — `test/core/test_model_single_llm_call.rb` (one `.ask(` site in `core/model.rb`)
- **M7** — docs updated: `kernel/` → `core/` in AGENTS.md, AGENT_CONTRACT.md
- **M8** — style floor enforced in core tests (bare rescue check in M6 test)