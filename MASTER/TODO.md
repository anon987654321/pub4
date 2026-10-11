# MASTER TODO

Updated: 2026-10-11. Scope: the Ruby runtime, constitutional law, /fix, operator tooling and device support. Cross-tree work is indexed in the repository-root `TODO.md`.

## P0 — correctness and proof

- [ ] Prove `--dry-run` is observational only: no content changes, generated files, index/ref changes, commits or external writes. Cover normal completion, blocked proposals, cancellation, model timeout, validation failure and partial delivery.
- [ ] Recheck `/fix` file scope against the current scanner for all four targets. Changed, untracked and newly created files must be handled deliberately; excluded/generated files must never enter the write set; unavailable Git inventory must fail closed rather than widen scope.
- [ ] Run the current MASTER test suite and operator gates on the pinned Ruby/Bundler stack; fix each reproducible failure and classify every skipped or inconclusive gate honestly. Repeat the focused test alone when order-dependent behavior is suspected.
- [ ] Exercise every `Master::Fix::FixLoop` terminal state with real fixtures: clean convergence, plateau, blocked, human decision, validation failure, delivery failure, timeout, crash/reload and recovery after a concurrent edit. Confirm the final status agrees with the files and gates actually observed.
- [ ] Validate Termux on a real Android device, not only by reading the installer: fresh install and existing-checkout update, native gem installation, internal-storage restrictions, no-key/local-model fallback, configured provider, microphone permission, Norwegian and English transcription, playback and interruption. Record device/Android/Ruby versions and exact command output.
- [ ] Run the LoRA and TurnRouter regressions on pinned Ruby, then verify an end-to-end transcript routes “make a video with the lora of me” to LoRA and never to shell inference. Source bugs fixed: latest-selfie lookup now searches `STUDIO/replicate/lora/<subject>/out` instead of the stale `STUDIO/lora/...` path; route-order and canonical-path regression tests are added, but runtime proof is still outstanding.
- [ ] Give the “generate me a selfie” route one live end-to-end test in addition to unit coverage. Report unavailable providers, credentials and network as explicit inconclusive/blocked outcomes, never as success.

## P1 — intelligence that earns its complexity

- [ ] Run `test_cognition_outcome_model.rb`, `test_memory_review.rb` and the current cognition suite on the pinned stack, then execute `MASTER/tools/cognition_benchmark.rb` against its no-learning baseline. OutcomeModel, evidence-backed review and a benchmark entrypoint already exist on current `main`; the old branches overlap and are far behind, so do not port their stale histories. Keep or simplify the model only after recorded metrics show whether it helps.
- [ ] Bound memory learning with provenance, confidence, retention/deletion rules and tests for stale or contradictory observations. Separate an observed result from a model's explanation of that result; never treat self-reported confidence as evidence of capability.
- [ ] Run `test_object_probe.rb` and verify the current bounded, opt-in `ObjectProbe` implementation remains safe on exceptions, recursive capture attempts and non-owner threads. The old branch's `start_trace`/`finish_trace` patch does not match current `build_trace` structure, so do not port it without a failing current test.
- [ ] Measure provider fallback, tool retry and voice interruption paths under failure. One audio playback owner must remain authoritative; a failed media attempt must not silently replay through another speech path.

## P2 — KISS and maintenance

- [ ] Run `test_snapshot_pack.rb` with the integrity footer now added to reading packs. Each inlined file carries a SHA-256 of its normalized source, the entire pack has a terminal SHA-256, the footer is budgeted, and tests cover truncation/source tampering; verify the pack is still under budget on representative trees and ensure consumers reject failed verification.

- [ ] Run the documented debugger command on a developer checkout under pinned Ruby 4.0.5 and confirm `-rdebug` is available. The README version mismatch is corrected, but this environment cannot execute the repository's test command.


- [ ] Compare the overlapping `fix-dryrun-*`, `bughunt/*`, `master/final-*`, `master/convergence-*` and `sweep/todo-wishlist-20261007` branch candidates with current source and tests. Port only missing, valuable changes; do not merge stale branch histories wholesale.
- [ ] Run the existing cognition and repair benchmark entrypoints on identical fixtures and budgets; preserve raw outcomes, regressions, wall time and model/tool spend so a lower score cannot be narrated as progress.
- [ ] Keep each policy, command recipe, gate inventory and generated agent contract under its canonical owner. When simplifying, remove a second source of truth rather than adding another wrapper or registry.
- [ ] Verify the generated agent-contract workflow end to end: edit `MASTER/AGENTS.md`, regenerate with `rake docs:agent_contracts`, then require `rake lint:agent_contracts` to pass.
- [ ] Run `test_fix_worktree_session.rb` and the full `/fix` suite on pinned Ruby, then exercise worktree delivery against GitHub staging and a local mirror. Source now isolates changes, refuses divergent/overlapping work, runs read-only proof, preserves failed candidates for recovery, and reports the actual squash-merge SHA rather than the pre-squash branch SHA. Confirm every failure path preserves the operator checkout and reports cleanup/delivery state accurately.

## Proof surfaces

`MASTER/bin/operator measure`, `MASTER/bin/operator gate`, `cd MASTER && rake test`, focused tests under `MASTER/test/`, and the actual /fix terminal report. Device, live-provider and rendered evidence must be recorded only when observed.
