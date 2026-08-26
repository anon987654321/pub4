# OPENBSD deploy pipeline — gotchas for agents

Operator-facing docs live in `README.md`/`RUNBOOK.md`/`RECIPES.md`. This file
is specifically the sharp edges that have burned agents in this repo — read it
before touching the deploy pipeline, not after.

## The fleet is four, and master is the one that gets dropped

`bin/vps-deploy all` deploys `master brgen amber bsdports`, in that order,
halting the pass on the first failure. Prefer it over four hand-typed runs.

Until it existed there was no way to say "deploy everything", so the set lived
in whoever was typing — and master is not under `/home/*/app`, so an operator
enumerating the Rails apps does not see it and leaves it behind. A pull moves
the checkout for everything; only a deploy makes any of it live.

The order is load-bearing, not alphabetical. Every deploy sheds amber and
bsdports: they land in `rcctl failed` with ports 61352/47312 closed while relayd
keeps answering TLS, so the outage reads as a hang rather than a 5xx and nothing
reports it. Deploying those two last folds the restore into the same pass.

Related, and worth knowing before you diagnose a deploy: **a shed and a relayd
failure look nothing alike once you check.** A shed leaves 443 answering with the
app port closed. If **443** refuses in ~30 ms while sshd is up and the app
answers on its own port from the box, the front door is down, not a backend — and
if something you did not deploy (ai.brgen.no) is down too, that is the diagnosis
rather than collateral.

Do not read port 80 as part of that test, but not for the reason this file gave
until 2026-08-25. It said port 80 "always refuses", that `relayd.conf` declares
the only listener, and that "there is no HTTP listener to lose". That is wrong:
`httpd` runs as `www` and holds `*.80`, and `fstat` on vm23 shows three of its
processes there. relayd does declare exactly one relay — `listen on 0.0.0.0
port 443 tls` — but relayd is not the only daemon on the box.

What port 80 answers is a 301 to HTTPS, plus ACME HTTP-01 challenges out of
`/acme`; `/etc/httpd.conf` is twelve lines and says so. So a request to 80
returns 301 whether or not a single Rails app is running, which is why it
carries no information about a shed or a relayd failure — the same conclusion
the old paragraph reached from a false premise, and it is worth keeping the
distinction because the premise has a consequence the conclusion does not: if
port 80 ever *does* refuse, that is a real finding. Certificate renewal goes
through it, so httpd being down means the certs stop renewing silently and the
site fails ~90 days later for a reason nothing will connect to this.

The original note is still true of the mistake that produced it: `curl
http://brgen.no:443/up` speaks plain HTTP at a TLS port and returns 000, so a
check written that way reports both ports refusing and looks exactly like the
outage it is inventing.

`httpd.conf`'s second server block listens on `* port 6666` and serves
`/postpro` — personal photographs — with no TLS and no auth. It is unreachable
from outside only because `pf.conf` line 14 is `block log all` and the pass
rules name 22, 53, 80 and 443 and nothing else; verified 000 from off-box on
2026-08-25. One daemon's config is relying on another's to not be an exposure,
so treat any pf change as touching that too.

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

- `Security: Importmap audit` and `Tests: System (a11y)` — **skipped on the
  VPS**, required locally. A local `bin/ci` failure in those two is real; it
  does not mean the VPS run will also fail. Both need something the box does
  not have on hand (a booted environment, a browser).
- `Style: Ruby` (RuboCop) — **runs on the VPS too**, and this list said
  otherwise until 2026-08-25. `ci.rb` carries the reason next to the step: vm23
  is where the deploy gate actually runs, so skipping it there left enforcement
  to a local `bin/ci` that nothing runs automatically. It is a source-text check
  needing no browser and no database, so the reasons the other two are skipped
  do not apply. A RuboCop failure on the box is a real deploy blocker — do not
  read it as a local-only bucket, which is exactly what this file used to say.
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

## Copy-tree sync must delete before it extracts

`vps_ci.sh`'s `sync_from_repo()`/`sync_ci_rails_root()` sync the repo to each
app's copy-tree via `tar` extraction. Tar extraction only *overlays* — it
never deletes destination files that are absent from the source. A file
deleted from git therefore survived indefinitely on the VPS's copy-tree
checkout, invisibly, until something referenced it and broke at runtime.

Adding `doas rm -rf` before each `tar xf -` extraction fixed this
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

## `resource_guard.sh` shedding amber/bsdports — check it actually recovers

Under load, the VPS's `resource_guard.sh` cron sheds `amber`/`bsdports`
(tracked in `/var/db/resource_guard_shed`). Check that file first to confirm
a down app is the guard and not a real crash.

But do not stop there and call it self-recovering, which is what this section
used to say. Shed and restore are separate gates and they can drift one way.
Measured on 2026-07-29 over 916 ticks: shedding fired on 48% of ticks while
the restore gate opened on 19%, and restore only releases one service per
tick — so amber and bsdports had been down for days, not oscillating.
`MEM_RESTORE` was 20% against a median availability of 13%, i.e. the window
sat outside the box's operating range; thresholds are now 8/14 and
`LOAD_RESTORE` 2.0.

The check that distinguishes the two cases is
`/var/log/resource_guard_history.log`, which records `load=`, `mem_avail=` and
`shed=` per tick. If shed ticks vastly outnumber ticks that satisfy
`shed=0 && mem_avail >= MEM_RESTORE && load < LOAD_RESTORE`, the guard is
parking those apps, not cycling them, and the thresholds need recalibrating
against that log rather than against a guess.
