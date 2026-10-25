# MASTER hardening review follow-through

Updated: 2026-10-26 (Europe/Oslo; GitHub commit timestamps are UTC)  
Reviewed base: `1ef67fe10` (external review snapshot)  
Integration base: `0b59844318f2e5527b5d5d54328a44f433438c3c`  
Integrated head at writing: `73a45cc7a9800808fb7658e95dc3dceacf73bd67`

## Follow-on manual four-tree source pass (2026-10-25)

A manual source-only pass subsequently touched MASTER, the shared check runner used by RAILS, OPENBSD, and STUDIO. The work was committed directly to `main`; it was not an actual `/fix` execution. No app, suite, syntax check or live service was run in this environment.

- MASTER: `lib/boot/stale_bundle_sweep.rb` adds a 30-day, quarantine-timestamp-based cleanup for renamed stale Bundler stores. It is dry-run by default and is wired into `bin/cleanup`; `--apply` is required to remove eligible directories. Regression tests cover TTL age, dry-run, explicit pruning and symlink refusal.
- MASTER: the asynchronous builder self-test now uses `watched_thread`, and invalid check registry roots/headless rows are refused before the runner executes any checks. A static read found all 64 current rows in `MASTER/checks/checks.yml` have `class:` or `script:`; this census is source evidence, not a runtime pass.
- MASTER: LoopOwner preserves a live process claim when PID or timestamp metadata is malformed, logging the invalid metadata instead of deleting the claim. Tests added, not run.
- RAILS: the runner is shared; the invalid-registry guard is relevant to its declared checks. No Rails app, migration, HTTP or browser tests were run.
- OPENBSD: `vps-state` validates deploy-status PIDs through `Deploy::PidProbe`. Tests added, not run. No OpenBSD-specific execution, vm23 health check or deployment was attempted.
- STUDIO: Replicate schema audit/snapshot tasks without credentials now report inconclusive and exit 3. Tests added, not run; no provider call was attempted.

All related tests remain unexecuted. The one cross-tree backlog, `TODO.md`, records the precise verification commands and per-tree inconclusive states. Do not infer PASS from a commit, a test file, static census or a CI badge. The previously observed Vercel `build-rate-limit` status is not a Ruby test result and was not retried.

## Follow-on provider and deploy-status pass

A further code trace found two provider-health issues and one OpenBSD visibility issue:

- Provider quarantine now respects the latest append-only event, so `clear` actually releases a model even if quarantine and clear timestamps fall in the same second. Quarantine log caching keys on inode, size and mtime, so appends invalidate a cached view even when filesystem timestamp granularity is coarse.
- Provider canary outcomes now pass through `ModelRouter#record_provider_outcome` where available; this connects actual canary results to the existing health/quarantine path. Success and exception outcomes both enter telemetry, and `canary_failure` reduces health score. Focused tests cover clear, re-quarantine, stable-mtime append, success, provider exception, and router routing.
- The progress directory `/var/db/pub4/deploy_status` remains root-only. `pub4-admin deploy-status-read <app>` exposes one allowlisted, validated record, and `vps-state` uses it on vm23 rather than treating direct permission denial as no active deploy. Corrupt records are reported as corrupt. Tests cover the broker method, caller contract and damaged status data.

All newly added and modified tests remain unexecuted. No runtime PASS is claimed; the exact focused test list and per-tree INCONCLUSIVE state are recorded in root `TODO.md`. No deployment, Vercel retry, or OpenBSD host action was performed.

## Follow-on trajectory telemetry hardening

The opt-in trajectory writer now derives its 25 MiB ceiling from the existing trace-event log contract, serializes rotation and append through a private sidecar lock, reserves space for each complete record, rejects oversized records, enforces private file/directory modes, and refuses symlink destinations. This is important because the recorded task can contain the user's prompt. Added coverage for rotation, size limits, permissions and symlink refusal in `MASTER/test/test_ai_trajectory.rb`.

The new trajectory tests, like all other new tests in this continuation, remain unexecuted. See root `TODO.md` for the consolidated focused test sequence and the still-INCONCLUSIVE proof state. No full /fix run or live verification is claimed.

## State of the P01–P11 tranche

The patch tranche and follow-up corrections are committed directly to `main` in 15 commits, touching 24 files. The branch is 15 commits ahead of the integration base and zero behind it. This is direct-to-main integration, not a pull-request merge.

- **P01 — sacred paths:** the fail-closed implementation was already present on the integration base; it was retained rather than replayed.
- **P02 — secret veto:** covers write/note/exec/git effect inputs and refuses when the configured secret pattern is absent.
- **P03/P04 — monitors:** per-iteration watchdog and watcher recovery, including a follow-up protecting the watcher from a failed error-event publish.
- **P05 — stranded transaction:** transaction recovery is attempted before returning an expired-budget result.
- **P06 — provider quarantine wiring:** model outcomes are routed through the diagnostics/quarantine path.
- **P07 — web secrets:** config directories/files use private permissions, including existing config files.
- **P08 — TTS daemon probe:** accepts the daemon's versioned health response; the executable bit on `bin/tts-worker` was restored in a follow-up commit.
- **P09 — dependency boot:** subprocess capture and lock acquisition are bounded; gem-store destruction is replaced by a conservative stale-store rename; private bundle environment preserves frozen mode. Pipe draining was bounded in a follow-up.
- **P10 — law parity:** raises the audited priority ceiling and adds `tools/law_parity_check.rb` plus `rake lint:law_parity`. The `RENDERED_VALUES` gap is intentionally surfaced as a real gap; it must not be silenced without a detector or an authorized deferral.
- **P11 — constitutional self-test:** unreadable inputs and malformed YAML become findings; release manifest loading uses safe YAML.
- **Additional hardening:** parity loader errors are logged and re-raised, parity is not run twice by the lint entrypoint, and generic YAML duplicate census remains outside the constitutional self-test's stated boundary.

The review's exact snapshot and the integration base differed. Review line numbers and patch contexts must not be treated as proof of the current line layout; read current source and tests before extending a patch.

## Verification status — do not overstate

Regression tests were added or extended in these areas: constitution, dependency manager, fix convergence/run budget, law parity, provider-quarantine wiring, self-test, watcher, web server, and TTS worker contract.

**The Ruby suite, focused tests, syntax checks, and the requested live boot have not been run in this integration environment.** Source changes and tests existing in GitHub are not evidence that they pass. Do not mark this tranche verified until commands produce captured output on a compatible checkout/interpreter.

The latest combined commit status observed for `08c095f97cd3495269d6643bf3bc8918016bbf8d` shows the Vercel context failing with a `build-rate-limit` target. That signal is neither a Ruby test result nor proof of a code defect, and no Vercel rerun is requested here.

## Required next verification

1. On the dev Mac with the repository's supported Ruby, run focused tests for constitution, dependency manager, fix convergence/run budget, law parity, provider quarantine, self-test, watcher, web server, and TTS worker contract. Capture the actual exit status and output.
2. Run the repository's prescribed `bin/check --profile=agent` and the full `rake test` ladder when the supported toolchain and dependencies are available. Distinguish PASS, FAIL, INCONCLUSIVE, BLOCKED, and timeout; do not convert a toolchain or network failure into a pass.
3. Run `rake lint:law_parity`. An explicit `RENDERED_VALUES` gap is currently expected until an operator authorizes a sacred-overlay deferral or a tagged detector is implemented.
4. Test dependency-manager behavior using an offline/non-ABI failure and an ABI mismatch. Check the dev Mac boot log for the real `deps0` lines.
5. Verify the TTS worker's executable mode and health-probe behavior from two processes; check the socket inode as described in the review.
6. Run `test/test_stale_bundle_sweep.rb`; verify `bin/cleanup` lists eligible stale stores in dry-run mode and removes only stores older than 30 days with `--apply`.

## Outstanding review findings — not closed by P01–P11

These items were identified in the review but are **not** claimed as repaired by this tranche:

- **Law/register truth:** re-baseline stale `data/self_findings.yml` SILENT_RESCUE members and add a stale-member regression test (L4); prove the INTER_MODEL_CONTRACT detector catches the council's heredoc/keyword call sites (L5); reconcile the nine runtime self-test checks with the declarative `self_test` contract (L7); make headless check-registry rows fail at parse time and decide the deploy default for strict check errors (L8).
- **Resource bounds:** an age-bounded stale-store sweep is now implemented in `lib/boot/stale_bundle_sweep.rb` and wired into `bin/cleanup`. It is dry-run by default, targets only `gems.stale-*` directories at the expected store depth, skips symlinks, and requires an age of 30 days before deletion. Its new test file is present but has not been run. Still open: census and rotate the remaining append-only writers, bound provider-health history reads, and remove the kernel log's full-history append verification (R3/R10).
- **Fix lifecycle:** bring DesignRun commits inside transaction/recovery semantics (R8); make the abort-on-stall setting, durable partial outcomes, and skippable-stage timeouts truthful (R9); make undo-journal pruning atomic and reclaim only safely unreferenced transaction/autofix artifacts (R10); audit load-bearing silent rescues without swallowing fatal exceptions (R11).
- **Providers and I/O:** add a success/recovery path and recent-event window for provider health; address Replicate poll authentication/SSRF/timeouts, retry jitter, process-group probe termination, error redaction, and Gemini key transport (R12/R13/H5).
- **Boot, device, and browser edges:** resolve the remaining R4 boot diagnostics and loop-claim recovery; pairing's claim race, unscoped process termination, pending-utterance TTL, wake-word timeout, bare device `system()` calls, and CDP handshake/nested-budget issues remain open (R4/R16/R17).
- **Security boundaries:** tool-hook fail-open behavior, MCP HTTP SSRF/package pinning, environment-file permissions, and scoped port/media kills remain open (H2/H3/H6/H7). The RAILS-side token timing, CSRF, and persistent ingress rate limiting remain **inconclusive**, because they were outside the review snapshot (H8).

The review roadmap remains the triage reference. Work on remaining items in small, path-scoped changes with a regression instrument for each. No item is closed by documentation alone, and no test is called green until its output exists.
