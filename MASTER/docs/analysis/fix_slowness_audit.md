# Why `/fix` is slow — audit and 2026-11-06 changes

Findings from tracing one `/fix` pass end to end: entry (`bin/master`) →
`FixLoop::PassRunner#run_pass` → scan → council → repair loop → commit. Each
finding names the code that was read. The changes at the end are the ones this
audit shipped; the fences at the very end are deliberate non-changes.

## The cost model of one violation

`Kernel::RepairAdapter#attempt_fix` (lib/fix/kernel/repair_adapter.rb) is the
per-violation hot path. For a single error-severity violation, worst case:

1. `ModelGate.before_call` — polls every 15s, up to 315s for a lane cool-off
   plus 300s for host load, per file (lib/fix/model_gate.rb:21-54).
2. Generation — `council_fix` for errors, else `request_fix`: over 200 lines
   that is `architect_then_fix` (one strong-model plan call, then N fast-model
   candidates); N is `UserSimulation.candidate_count`, default 3
   (lib/fix/best_of_n.rb:143-147).
3. `best_candidate` — a deterministic rescan per candidate, then user-simulation
   oracles, then focused tests (bounded, real subprocess cost).
4. `reflexion_verify` — 1-2 verifier LLM calls (lib/fix/repair_loop/fix_strategies.rb:28-56).
5. `consensus_approves?` — a panel call for error/critical severities.
6. `RETRYABLE` — one full retry of steps 2-5 with the refusal note appended.
7. `commit_applied_fix` — one git commit per violation, deliberately
   (lib/fix/kernel/repair_adapter.rb: "One fix, one commit, one push").

A stubborn violation can therefore cost 10-20 LLM calls and two commits; the
pass loop then repeats until `clean_runs_required` consecutive clean passes.
That multiplicative structure — not any single slow call — is why `/fix` runs
for hours on a dirty tree.

## Ranked findings

1. **The constitutional preamble rode on every candidate prompt.**
   `build_soul_preamble` joined every law's practice text (~225 rows) into one
   string prepended to each generation prompt (lib/fix/kernel/repair_adapter.rb,
   `soul_preamble`). At roughly 20-50 KB per prompt, repeated per candidate
   (×3), per violation, per law, per pass, this was the largest single token
   sink in the loop. Verifier and consensus prompts did not carry it.

2. **Whole-file prompts and whole-file answers for small violations.** For
   files at or under 8 KB (`PatchApplier::DIFF_THRESHOLD`), `genetic_fix` sends
   the whole file and asks for the whole corrected file back — for a one-line
   fix. Over 200 lines, `architect_then_fix` also collects whole-file
   candidates. Input and output both scale with file size, not fix size.

3. **Candidates were generated sequentially.** `propose_candidates` and
   `diff_fix` walked `count.times` one at a time — three LLM latencies stacked
   where the calls are independent (they share only the unchanged source).
   The tree already runs rule groups in threads (`LlmStage#run_rule_group`)
   and the dispatcher is thread-safe by design (test_llm_dispatcher.rb:750).

4. **The semantic checklist invited printed deliberation.** `SEMANTIC_PASS_CHECKLIST`
   asked the model, on every prompt, to "summarize what the file does in 3
   lines … enumerate … list …" — output that `extract_code` then discarded,
   because only the fenced code block survives. Paying output tokens for text
   nobody reads, three times per violation.

5. **Free-lane quota blindness caused 429 storms, and storms cost retries.**
   `Io::ModelQuota` counted only `:free`-suffixed ids (lib/io/model_quota.rb,
   `FREE_RE`), so Cerebras' 100/day or Groq's documented caps were never
   consulted by `LaneSelection#alive?` or `ComputePool` — the router kept
   picking an exhausted lane until the provider said no, and every "no" costs
   a failover hop (`retry_on_broke_lane`) plus `ModelSkipCache` parking.

6. **Key rotation existed only for OpenRouter.** `KeyRotator::ROTATABLE_RE`
   (lib/io/key_rotator.rb) matched `:free`/`openrouter/` ids alone, and the
   hosted sender used the key frozen into the endpoint index at build time
   (`HttpSender#send_hosted`), so a rotated key could not take effect without
   a router rebuild.

7. **Replicate chat lanes could never rank.** `ModelRouter::Pool#replicate_models`
   produces `replicate:<slug>` lanes, but `model_defs` holds no scoring rows for
   them, so `ComputePool#candidate` drops them from the ranking. That keeps
   paid per-call lanes out of rank-based selection; it stays.

8. **Structural multiplication that stands.** Council rounds are capped at 12
   files but "a panel over a dozen files costs minutes" (lib/fix/fix_loop/
   council_round.rb:12-15) and run once per pass; visual, wishlist,
   opportunity and improvement stages each add their own stage calls. The
   semantic scan is 50-190s per LLM read per file (the file's own comment,
   lib/fix/scan/file_processor.rb) and is sampled for clean files — the right
   trade, documented in place.

## Changes shipped (2026-11-06)

- **Preamble budget** — `soul_preamble` stops at `MASTER_FIX_PREAMBLE_BUDGET`
  (default 12,288 chars) following laws.yml's own most- to least-important
  order, and says `(law guidance continues in data/laws.yml)` when truncated.
  Enforcement is untouched: scanners and apply-time gates read every law.
- **Silent-reasoning checklist** — the seven printed bullets became three
  lines that require the same diligence silently and forbid printing it.
- **Parallel candidates** — `candidate_threads` asks the independent
  candidates concurrently (bounded by candidate_count, ≤5; ordering and
  events preserved), with `MASTER_FIX_PARALLEL_CANDIDATES=0` as the declared
  sequential escape.
- **Hosted free-tier quotas** — `openai_compatible.<name>.daily_quota`
  (groq 14,400; cerebras 100, the figures the file already stated) is
  validated by the catalogue guard and enforced by `Io::ModelQuota` for
  `<name>:<model>` lanes; endpoints with no documented day cap stay
  untracked. Existing `:free` behavior and both quota test contracts are
  unchanged.
- **Per-provider key rotation** — `KeyRotator` rotates a hosted endpoint's
  `key_env` list (a second var may be declared per endpoint, e.g.
  `GROQ_API_KEY_2`), and `HttpSender#send_hosted` resolves the active key at
  call time so rotation lands on the next call.

## Fences left standing (deliberately)

- One commit per violation (`commit_applied_fix`) — the comment records why.
- `ModelGate`'s 15s polls and wait ceilings — written after the 2026-11-05
  all-files-fail-at-once incident; changed only by evidence of a new one.
- Per-candidate rescans and user simulations — they are the verification that
  lets the preamble shrink safely.
- The semantic scan's sampling design — its cost comment is the reasoning of
  the person who built it; revisit with data, not by feel.

## Verification status

No Ruby runtime was available on the audit machine. Every patched file parses
(tree-sitter Ruby grammar: zero errors), the YAML parses and its new fields
sit inside the catalogue guard's whitelist, and the quota/rotation decision
tables were simulated against both new code semantics and the existing test
contracts (`test_model_quota_forecast.rb`, `test_ecosystem_features.rb`,
`test_io_key_rotator.rb`) — all pass. The repo's own suite (`bin/check`) has
not been run here and remains the gate before merging.

## Verification status, updated 2026-11-06: the suite ran

A Ruby 3.3.6 runtime and the full bundle were set up, and the claims above
were re-checked against the live code instead of the tree-sitter simulation.

The repo's own tests, run individually so each count is honest:

- `test_io_key_rotator.rb` 12 runs, `test_model_quota_forecast.rb` 9 runs,
  `test_model_quota_shared_state.rb` 6 runs, `test_llm_dispatcher.rb` 61 runs
  (including the hosted-endpoint socket test that exercises the per-call key
  resolution), `test_repair_loop_per_fix_commit.rb` 23 runs,
  `test_llm_stage_failure.rb` 4, `test_fix_model_gate.rb` 10,
  `test_fix_run_budget.rb` 36, `test_fix_loop_oscillation.rb` 14,
  `test_recovery_gates.rb` 9, `test_fix_watchdog.rb` 30,
  `test_fix_interruption_restart.rb` 5, `test_fix_loop_committer.rb` 37,
  `test_fix_crash_leaves_tree.rb` 11 - all green.
- `test_fix_loop_file_collector.rb` 6 failures. The same 6 fail at the commit
  before this branch (95b42b7) on this machine: pre-existing environment
  drift (git inventory behaviour, scanner path filter), not this branch.
- `ModelCatalogueGuard.validate` against the live `data/models.yml` returns
  clean with the shipped `daily_quota` / `key_env` rows. The replicate
  scoring rows present during this run were withdrawn later the same day
  (176e152: unrowed replicate lanes are dropped from ranking, not scored at
  zeros, so the rows made paid lanes selectable); the guard passes the
  withdrawn catalogue too.

Measured, on the live code (scripts kept beside the run, not in the repo):

- Preamble bytes per candidate prompt: 56,928 (473 law lines, the old
  whole-registry construction) -> 12,334 (109 law lines at the shipped
  12,288-character budget). 78.3% of the prompt's law guidance is gone, about
  130.6 KB per 3-candidate generation stage, and a truncated preamble names
  itself ("law guidance continues in data/laws.yml").
- Candidate generation wall time, 3 candidates whose lane call sleeps 0.8 s:
  2.40 s sequential (`MASTER_FIX_PARALLEL_CANDIDATES=0`) vs 0.80 s parallel -
  3.0x, candidate order preserved. At a realistic 8 s lane call that is
  roughly 24 s -> 8 s per generation stage.
- A real run: `bin/fix-here MASTER --model none --no-probe --no-publish` on
  this machine booted, passed the parse sweep, scanned, and ran the ratchet
  stage through its pass loop with zero tokens (no lane configured, which is
  the honest degradation for an operator with no keys). The remaining gate is
  a run with a live lane and the full `bin/check`.
