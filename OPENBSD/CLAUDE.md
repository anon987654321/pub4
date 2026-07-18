# OPENBSD deploy pipeline — gotchas for agents

Operator-facing docs live in `README.md`/`RUNBOOK.md`/`RECIPES.md`. This file
is specifically the sharp edges that have burned agents in this repo — read it
before touching the deploy pipeline, not after.

## `SKIP_CI=1` does not mean "skip CI"

`bin/vps-deploy <app>` branches in two ways (see `bin/vps-deploy` ~line 40):

- **Default** (`SKIP_CI` unset): runs `vps_ci.sh <app>`, which syncs the repo
  to the app's copy-tree and runs the full `bin/ci` gate (see below) against a
  throwaway test DB.
- **`SKIP_CI=1`** (used by `vps_production_push.sh` for fast hotfixes): skips
  `vps_ci.sh` entirely and instead runs `RAILS/<app>/<app>.sh` directly, which
  calls `deploy_tracked_app` → `rails_runtime_gate`.

The name suggests "no gate runs at all." That's false — `rails_runtime_gate`
is still a real gate, it's just a *different, narrower* one than `bin/ci`
(no RuboCop, no Brakeman, no `bin/rails test`). If a hotfix broke something
`bin/ci` would have caught, `SKIP_CI=1` is why it slipped through, not a
tooling bug.

## `bin/ci`'s `Setup` step behaves differently locally vs. on the VPS

`RAILS/shared/config/ci.rb` gates several steps on `vps_host` (true when
`PUB4_CI_GUARD=1`, `/var/db/pub4_vps` exists, or `/etc/relayd.conf` exists):

- `Security: Importmap audit`, `Style: Ruby` (RuboCop), `Tests: System (a11y)`
  — **skipped on the VPS**, required locally. A local `bin/ci` failure here is
  real; it does not mean the VPS run will also fail.
- `Tests: Seeds` — runs with `SKIP_BERGEN_DEMO=1` on the VPS, without it
  locally. A local seed failure about a duplicate Bergen demo email is a
  local-DB-state artifact, not a real blocker — don't chase it.
- `Setup` (`bin/setup --skip-server`, includes `db:prepare`) replays the full
  migration history. A stale local dev DB can hit a legacy FK-naming mismatch
  that only existed mid-history and was never a bug in current schema.rb.
  Confirm against a fresh DB (or the VPS run) before treating this as real.

**Rule of thumb:** a local `bin/ci` failure is only actionable if you can
name which of the above buckets it's *not* in. When in doubt, read
`RAILS/shared/config/ci.rb` directly rather than assuming.

## Copy-tree sync used to be additive-only (fixed, but know why)

`vps_ci.sh`'s `sync_from_repo()`/`sync_ci_rails_root()` sync the repo to each
app's copy-tree via `tar` extraction. Tar extraction only *overlays* — it
never deletes destination files that are absent from the source. A file
deleted from git therefore survived indefinitely on the VPS's copy-tree
checkout, invisibly, until something referenced it and broke at runtime.

This was fixed by adding `doas rm -rf` before each `tar xf -` extraction
(both in `sync_from_repo()`'s per-directory loop and in
`sync_ci_rails_root()`). If you're debugging a VPS-only failure where a file
"shouldn't exist anymore" but the error implies it does, first check whether
your local `vps_ci.sh` is current — this exact bug reappearing (e.g. via a
revert) would look like ghost files coming back from the dead.

## `rcctl check` can report "failed" while the service is still booting

Falcon takes ~30-40s to fully boot under VPS load (1 vCPU, shared with other
apps). `doas rcctl check <app>` polled a few seconds after `rcctl restart`
can report `failed` even though the process is healthy and mid-startup — this
is not a crash. Before treating a post-deploy `rcctl check` failure as real:

- `tail /var/log/daemon` for the app — look for a normal "Waiting for
  startup..." progression vs. an actual stack trace/exit.
- `ps ax | grep <app>` — is the Falcon process actually running?
- Retry `rcctl check` after ~30s before escalating.

A "completed (exit code 0)" notification from a background deploy command is
**not** proof the deploy succeeded either — it reflects the SSH wrapper's
exit, not the deployed script's outcome. Always verify independently via:

1. The deploy stamp: `/var/db/pub4/last_deploy_<app>.json` (`status: "ok"`
   and the expected SHA).
2. `doas rcctl check <app>`.
3. A live `curl` against the app's actual URL, not just `/up`.

## `resource_guard.sh` shedding amber/bsdports is expected, not a bug

Under load, the VPS's `resource_guard.sh` cron sheds `amber`/`bsdports`
(tracked in `/var/db/resource_guard_shed`). Seeing these oscillate between
`rcctl(ok)` and `rcctl(failed)` on a loaded VPS is self-recovering behavior,
not something to fix — check `/var/db/resource_guard_shed` to confirm it's
the guard and not a real crash before investigating further.
