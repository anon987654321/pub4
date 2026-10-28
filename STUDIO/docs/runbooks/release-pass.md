# Runbook: bounded release pass

Run against the exact commit intended for deployment. Run each command
independently so one failure does not suppress the remaining diagnostic evidence.

## 1. Four-tree tests and checks

From the repository root, run each command as written:

    ruby OPENBSD/bin/evidence release-master -- sh -c 'cd MASTER && rake test'
    ruby OPENBSD/bin/evidence release-rails-contracts -- ruby RAILS/test/run_all.rb
    ruby OPENBSD/bin/evidence release-openbsd-contracts -- ruby OPENBSD/test/run_all.rb
    ruby OPENBSD/bin/evidence release-check-full -- OPENBSD/bin/check --profile=full
    ruby OPENBSD/bin/evidence release-studio -- sh -c 'cd STUDIO && rake test'

Then run the repository’s own operator instruments:

    ruby OPENBSD/bin/evidence operator-triangle-up -- MASTER/bin/operator triangle up
    ruby OPENBSD/bin/evidence operator-rails-check -- MASTER/bin/operator check --scan-only --tree=RAILS

Read the complete artifact output, not only the final exit status. A source-only
check cannot replace a live browser or app test; an unavailable dependency is
not a pass. Record FAIL, TIMEOUT, BLOCKED and INCONCLUSIVE outcomes separately.

## 2. Existing 400-case interaction campaign

The canonical case inventory is RAILS/test/interaction_campaign_400.json.
The runner is RAILS/test/run_interaction_campaign.rb; do not create another
scenario manifest.

First inspect mappings, without running cases:

    ruby OPENBSD/bin/evidence campaign-list -- ruby RAILS/test/run_interaction_campaign.rb --list

Then execute the mapped cases:

    ruby OPENBSD/bin/evidence campaign-mapped -- ruby RAILS/test/run_interaction_campaign.rb
    ruby OPENBSD/bin/evidence campaign-all -- ruby RAILS/test/run_interaction_campaign.rb --all

The default run selects only cases with exact registered runtime adapters.
--all records unmapped cases as SKIPPED; the runner exits non-zero if any
case is blocked or skipped. This is intentional. Do not reinterpret that
aggregate result as PASS. Inspect the run-scoped
.master/interaction_campaign_runs/*/results.json, compare the PASS/FAIL/
BLOCKED/SKIPPED tally to all 400 IDs, and keep unexecuted cases open.

Static expectations, mocks, and a manifest containing 400 rows are not 400
observed user journeys. Real browser/HTTP/CLI interactions must be exercised
where the case contract requires them. Do not use production customer data or
live payment endpoints for the campaign.

## 3. CLI/web surface parity

Use runbooks/cli-web-ux.md for real /connect, /join, /msg, reconnect,
history and interruption checks. A passing source suite does not demonstrate
the same behavior in the browser.

## 4. /fix terminal-state and failure-safety proof

Bare /fix is write-enabled. Do not use it as a supposedly read-only smoke
test, and do not run destructive trials against a production checkout. Follow
the current MASTER agent contract and the transaction-safety section of the
root TODO. Run controlled tests in a disposable copy for dirty-tree
preservation, interrupted writes, disk exhaustion, retry convergence,
rollback/undo and the terminal states DONE, PLATEAU, HUMAN_DECISION, BLOCKED,
VALIDATION_FAILED, DELIVERY_FAILED and TIMEOUT.

A pre-repair baseline is not a dry-run guarantee. Include the exact starting
SHA, Law digest, toolchain identity, before/after tree status, run report and
rejection/rollback evidence. Do not test by manually triggering each state
unless the corresponding preconditions are safely reproducible.

## 5. OpenBSD Operator surface

On an actual supported OpenBSD host, validate MASTER/bin/operator --help
and the interactive /help against the dmesg-style contract and the current
checkout-relative path. Preserve useful scrollback and confirm ASCII art does
not appear outside the face. This is host evidence; a macOS test is not a
substitute.
