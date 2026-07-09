# MASTER_NEW_PROPOSAL.md

**Status (2026-07-09):** M2, M3, M5–M8 done. **Bridge chosen** — agent turns wired;
M1 slices 5–6 and M4 remain. Delete this file only after full CLI cutover and M4.

## Remaining work

### M1 — Absorption program (in progress: Bridge)
Slices 0–4 done per `core/ABSORPTION.md`. **Bridge milestone 2:** `CLI#run_input` off pipeline — Fold for agent turns,
direct `command_registry` for slash. Slice 5 still open: web chat + standing
orders + pipeline deletion. `lib/` still ~368 files.

### M4 — CoreBridge sunset
Delete `lib/now/core_bridge.rb`, `/fold`, and `bin/cli --fold` only when
`command_registry` routes every handler through `Master::Core` — slash commands
still use the legacy pipeline.

## Done

- **M2** — `test/core/test_no_lib_backedges.rb`
- **M3** — `test/core/test_verb_closure.rb` (closed verb set)
- **M5** — `bin/check` profiles are the gate entrypoint (`full` → ci + probe + audit)
- **M6** — `test/core/test_model_single_llm_call.rb` (one `.ask(` site in `core/model.rb`)
- **M7** — docs updated: `kernel/` → `core/` in AGENTS.md, AGENT_CONTRACT.md
- **M8** — style floor enforced in core tests (bare rescue check in M6 test)