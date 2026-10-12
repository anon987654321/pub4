# MASTER TODO

Updated: 2026-10-12. Scope: the Ruby runtime, constitutional law, /fix, operator tooling and device support. Cross-tree work is indexed in the repository-root `TODO.md`. Every entry below is a seam that cannot close in a checkout alone, or a red suite with a named owner; finished work is deleted, not logged.

## P0 — correctness and proof

- [ ] **Re-run the complete MASTER test census on current main.** The last available count (about 185 of 589 test files red) was measured at `f9a5a3083`; it is not a result for the current head. Reproduce each failing file and classify it as a real defect, an obsolete assertion, or a removed subject. Fix the source when the contract is right, update the test when the implementation is right, and remove a test only when its subject is gone. Done when the census on current `main` prints no failing files.
- [ ] `/fix --dry-run` is proven observational for `FixLoop#preview` (`test_preview_leaves_the_checkout_byte_identical`: content, `.git`, index and untracked files unchanged). The end-to-end dispatch is not: `dispatch_fix` resolves targets only inside the pub4 trees, so a temp fixture is refused. Remaining step: run `dispatch_fix ... --dry-run` against a tracked fixture inside a worktree and add model timeout, cancellation, blocked-proposal and partial-delivery cases. Proof: `ruby -Itest -Ilib test/test_fix_convergence.rb -n /byte_identical/` plus the same digest assertion around the dispatcher.
- [ ] **Reproduce and classify the `/fix` focused suites on current main:** `test_fix_protocol.rb`, `test_fix_convergence_wiring.rb`, `test_fix_homeostat_signals.rb`, and `test_fix_law_map_repair.rb`. The previous protocol diagnosis about `Protocol.rules` and `advisory_rules` does not match the current test source, which uses `Protocol.laws` and `capability_report`; collect actual test output before changing tests or implementation.
- [ ] Validate Termux on a real Android device, not only by reading the installer: fresh install and existing-checkout update, native gem installation, internal-storage restrictions, no-key/local-model fallback, configured provider, microphone permission, Norwegian and English transcription, playback and interruption. Blocked on a device; owner: the operator. Record device/Android/Ruby versions and exact command output.
- [ ] Give the "generate me a selfie" route one live end-to-end run. Blocked on a Replicate credential and a paid call; owner: the operator. Unit and transcript coverage is green (`test_lora_intent.rb`, `test_turn_router.rb`). Report unavailable providers, credentials and network as inconclusive, never as success.

## P1 — intelligence that earns its complexity

- [ ] Run `ruby MASTER/tools/cognition_benchmark.rb verified-outcomes.jsonl` against its `--no-learning` baseline, and the repair benchmark on the same fixtures and budgets. Blocked on input: the tool accepts only real, independently evidenced task outcomes (each row needs a receipt digest), and none are recorded in the checkout. Owner: whoever runs /fix with outcome recording on; fabricated rows would defeat the benchmark. Keep or simplify `OutcomeModel` only after the recorded Brier scores show whether learning beats the constant 0.5 baseline.
- [ ] Voice playback has one owner, but `test_voice_support.rb` fails 8 of 29 (queue item shape, a `drain` that does not terminate in the test harness, player-preference tests that assume no `sox` on the host, enrich dice stubs). Rewrite them against `Voice::Playback` as it is now, then measure a failed media attempt end to end: it must not replay through a second speech path.

## P2 — KISS and maintenance

- [ ] **Prove snapshot integrity across the current entrypoints.** Run `test_snapshot_generator.rb` and the related snapshot pack/parts/artifact suites; verify that the one-file reading pack, multipart reading pack, and byte-exact mirror each have a matching writer/reader integrity contract. `MASTER/tools/snapshot.rb` emits a `Pack:` header in its byte-exact mirror path, so locate the actually failing path before changing either writer or extractor.
- [ ] Exercise worktree delivery against GitHub staging. The local-mirror and PR paths pass in `test_fix_worktree_session.rb`; no staging repository or token exists in this checkout. Owner: the operator. Confirm every failure path preserves the operator checkout and reports cleanup/delivery state accurately.

## Proof surfaces

`MASTER/bin/operator measure`, `MASTER/bin/operator gate`, `cd MASTER && rake test`, focused tests under `MASTER/test/`, and the actual /fix terminal report. Device, live-provider and rendered evidence must be recorded only when observed.
