# MASTER TODO

Updated: 2026-10-11. Scope: the Ruby runtime, constitutional law, /fix, operator tooling and device support. Cross-tree work is indexed in the repository-root `TODO.md`.

## P0 — correctness and proof

- [ ] Prove `--dry-run` is observational only: no content changes, generated files, index/ref changes, commits or external writes. Cover normal completion, blocked proposals, cancellation, model timeout, validation failure and partial delivery.
- [ ] Recheck `/fix` file scope against the current scanner for all four targets. Changed, untracked and newly created files must be handled deliberately; excluded/generated files must never enter the write set; unavailable Git inventory must fail closed rather than widen scope.
- [ ] Run the current MASTER test suite and operator gates on the pinned Ruby/Bundler stack; fix each reproducible failure and classify every skipped or inconclusive gate honestly. Repeat the focused test alone when order-dependent behavior is suspected.
- [ ] Exercise every `Master::Fix::FixLoop` terminal state with real fixtures: clean convergence, plateau, blocked, human decision, validation failure, delivery failure, timeout, crash/reload and recovery after a concurrent edit. Confirm the final status agrees with the files and gates actually observed.
- [ ] Validate Termux on a real Android device, not only by reading the installer: fresh install and existing-checkout update, native gem installation, internal-storage restrictions, no-key/local-model fallback, configured provider, microphone permission, Norwegian and English transcription, playback and interruption. Record device/Android/Ruby versions and exact command output.
- [ ] Trace and fix the reported intent-routing case where “make a video with the lora of me” ran `make` as a shell command; add a regression test proving natural-language intent cannot escape into arbitrary command execution.
- [ ] Give the “generate me a selfie” route one live end-to-end test in addition to unit coverage. Report unavailable providers, credentials and network as explicit inconclusive/blocked outcomes, never as success.

## P1 — intelligence that earns its complexity

- [ ] Review the unmerged cognition/memory candidates (`implement/cognitive-evidence-learning`, `recover/cognition-evidence-learning-20261011`, `recover/memory-governance-20261011`) against current `main`. Consolidate overlaps only after focused tests and a reproducible benchmark show that outcome feedback, memory retrieval/consolidation or the self-model improves results over a no-memory baseline.
- [ ] Bound memory learning with provenance, confidence, retention/deletion rules and tests for stale or contradictory observations. Separate an observed result from a model's explanation of that result; never treat self-reported confidence as evidence of capability.
- [ ] Review `debugging/object-centric-probe` for useful caller/local-state inspection. Keep only a tested, opt-in debugger path; no permanent global monkey patches, method wrappers or mandatory debugging dependencies.
- [ ] Measure provider fallback, tool retry and voice interruption paths under failure. One audio playback owner must remain authoritative; a failed media attempt must not silently replay through another speech path.

## P2 — KISS and maintenance

- [ ] Compare the overlapping `fix-dryrun-*`, `bughunt/*`, `master/final-*`, `master/convergence-*` and `sweep/todo-wishlist-20261007` branch candidates with current source and tests. Port only missing, valuable changes; do not merge stale branch histories wholesale.
- [ ] Add a small repeatable benchmark for repair precision, regressions, wall time and model/tool spend. Compare identical fixtures and budgets; preserve raw outcomes so a lower score cannot be narrated as progress.
- [ ] Keep each policy, command recipe, gate inventory and generated agent contract under its canonical owner. When simplifying, remove a second source of truth rather than adding another wrapper or registry.
- [ ] Verify the generated agent-contract workflow end to end: edit `MASTER/AGENTS.md`, regenerate with `rake docs:agent_contracts`, then require `rake lint:agent_contracts` to pass.
- [ ] Replace manual worktree integration with a safe operator path that checks for dirty work, proves the candidate against current `origin/main`, lands only reviewed paths and reports each result. Never reset or overwrite an operator's dirty checkout.

## Proof surfaces

`MASTER/bin/operator measure`, `MASTER/bin/operator gate`, `cd MASTER && rake test`, focused tests under `MASTER/test/`, and the actual /fix terminal report. Device, live-provider and rendered evidence must be recorded only when observed.
