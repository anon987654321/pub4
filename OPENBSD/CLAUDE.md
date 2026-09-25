# OPENBSD deploy pipeline — gotchas for agents

Operator-facing docs live in `README.md` and `RUNBOOK.md`, and the recipes in
`data/operator.yml`. This file is
specifically the sharp edges that have burned agents in this repo — read it
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
failure look nothing alike once you check.** A shed leaves 443 answering with
the app port closed. If **443** refuses in ~30 ms while sshd is up and the app
answers on its own port from the box, the front door is down, not a backend —
and if something you did not deploy (ai.brgen.no) is down too, that is the
diagnosis rather than collateral.

Do not read port 80 as part of that test, but not for the reason this file gave
until 2026-08-25. It said port 80 "always refuses", that `relayd.conf` declares
the only listener, and that "there is no HTTP listener to lose". That is wrong:
`httpd` runs as `www` and holds `*.80`, and `fstat` on vm23 shows three of its
processes there. relayd does declare exactly one relay — `listen on 0.0.0.0 port
443 tls` — but relayd is not the only daemon on the box.

What port 80 answers is a 301 to HTTPS, plus ACME HTTP-01 challenges out of
`/acme`; the first server block in `/etc/httpd.conf` says so. So a request to 80
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

`httpd.conf`'s second server block serves `/postpro` — personal photographs —
with no TLS and no auth, on `127.0.0.1 port 6666`. Reach it over an ssh tunnel.
It listened on `*` until pf's default deny was the only thing keeping it private;
if anyone widens that listener again, pf becomes the exposure's only guard.

## `SKIP_CI=1` does not mean "skip CI"

`bin/vps-deploy <app>` takes one of two branches:

- **Default** (`SKIP_CI` unset): `vps_ci.sh <app>` syncs the repo into a CI
  mirror and runs `bin/ci` (see below) against a throwaway test DB.
- **`SKIP_CI=1`**: skips `vps_ci.sh` and runs `RAILS/<app>/<app>.sh`, which
  calls `deploy_tracked_app` → `rails_runtime_gate`. That gate bundles,
  prepares the databases, precompiles assets and runs `bin/ci` inside the
  deployed `/home/<app>/app` tree. CI still runs, in a different place.

The flag that skips CI is `SKIP_RUNTIME_GATE=1`, which returns from
`rails_runtime_gate` before any of that. `vps_production_push.sh` sets both, so
the hotfix path runs no `bin/ci` at all, only the loopback gates `vps-deploy`
runs after every restart. When a hotfix ships a break `bin/ci` catches, that
pair of flags is why, not a tooling bug.

## `bin/ci`'s `Setup` step behaves differently locally vs. on the VPS

`RAILS/shared/config/ci.rb` gates several steps on `vps_host` (true when
`PUB4_CI_GUARD=1`, `/var/db/pub4_vps` exists, or `/etc/relayd.conf` exists):

- `Security: Importmap audit` and `Tests: System (a11y)` — **skipped on the
  VPS**, required locally. A local `bin/ci` failure in those two is real; it
  does not mean the VPS run will also fail. Both need something the box does not
  have on hand (a booted environment, a browser).
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

**Rule of thumb:** a local `bin/ci` failure is only actionable if you can name
which of the above buckets it's *not* in. When in doubt, read
`RAILS/shared/config/ci.rb` directly rather than assuming.

## Copy-tree sync must delete before it extracts

`vps_ci.sh`'s `sync_from_repo()`/`sync_ci_rails_root()` sync the repo to each
app's copy-tree via `tar` extraction. Tar extraction only *overlays* — it never
deletes destination files that are absent from the source. A file deleted from
git therefore survived indefinitely on the VPS's copy-tree checkout, invisibly,
until something referenced it and broke at runtime.

Adding `doas rm -rf` before each `tar xf -` extraction fixed this (both in
`sync_from_repo()`'s per-directory loop and in `sync_ci_rails_root()`). If
you're debugging a VPS-only failure where a file "shouldn't exist anymore" but
the error implies it does, first check whether your local `vps_ci.sh` is current
— this exact bug reappearing (e.g. via a revert) would look like ghost files
coming back from the dead.

## `rcctl check` can report "failed" while the service is still booting

Falcon takes ~30-40s to fully boot under VPS load (1 vCPU, shared with other
apps). `doas rcctl check <app>` polled a few seconds after `rcctl restart` can
report `failed` even though the process is healthy and mid-startup — this is not
a crash. Before treating a post-deploy `rcctl check` failure as real:

- `tail /var/log/daemon` for the app — look for a normal "Waiting for
  startup..." progression vs. an actual stack trace/exit.
- `ps ax | grep <app>` — is the Falcon process actually running?
- Retry `rcctl check` after ~30s before escalating.

A "completed (exit code 0)" notification from a background deploy command is
**not** proof the deploy succeeded either — it reflects the SSH wrapper's exit,
not the deployed script's outcome. Always verify independently via:

1. The deploy stamp: `/var/db/pub4/last_deploy_<app>.json` (`status: "ok"` and
   the expected SHA).
2. `doas rcctl check <app>`.
3. A live `curl` against the app's actual URL, not just `/up`.

## `resource_guard.sh` shedding amber/bsdports — check it actually recovers

Under load, the VPS's `resource_guard.sh` cron sheds `amber`/`bsdports` (tracked
in `/var/db/resource_guard_shed`). Check that file first to confirm a down app
is the guard and not a real crash.

But do not stop there and call it self-recovering, which is what this section
used to say. Shed and restore are separate gates and they can drift one way.
Measured on 2026-07-29 over 916 ticks: shedding fired on 48% of ticks while the
restore gate opened on 19%, and restore only releases one service per tick — so
amber and bsdports had been down for days, not oscillating. `MEM_RESTORE` was
20% against a median availability of 13%, i.e. the window sat outside the box's
operating range, so that pass set 8/14 and `LOAD_RESTORE` 2.0.

It has been recalibrated once more since, and this paragraph said 8/14 for a
month after it stopped being true. `MEM_RESTORE` is **10**, set on 2026-08-14
from 1550 ticks: availability had moved from p50 13 to p50 9, so 14 had drifted
back above p75 — the same condition the 2026-07-29 pass existed to fix, arriving
a second time from the other direction. `MEM_WARN` is 8 and `LOAD_RESTORE` 2.0.

Read the numbers from `resource_guard.sh`, which carries each recalibration with
the dataset that justified it. A threshold copied into prose is a threshold that
goes stale the next time the box changes.

The check that distinguishes the two cases is
`/var/log/resource_guard_history.log`, which records `load=`, `mem_avail=` and
`shed=` per tick. If shed ticks vastly outnumber ticks that satisfy `shed=0 &&
mem_avail >= MEM_RESTORE && load < LOAD_RESTORE`, the guard is parking those
apps, not cycling them, and the thresholds need recalibrating against that log
rather than against a guess.

## Refused, and why

Each of these was proposed and measured against the tree. A reason tied to one
file sits in a comment on that file; these have no single file to sit on.

- **No fourth public Rails app** beyond brgen, amber and bsdports until brgen's
  high-churn verticals are engines with their own migrations and tests, money and
  identity primitives live in `RAILS/shared` with more than one consumer, and CI
  runs the layout suite and `/up` smoke for all three apps. Every restart before
  pub4 grew surface before its boundaries held; horizon ideas wait in
  `RAILS/apps.horizon.yml`.
- **No staging environment.** vm23 is one vCPU and 1 GB and already sheds apps
  under load. A staging copy arrives with a second box, not as a second set of
  services on this one.
- **No second reference platform.** OpenBSD's behaviour wins over the Mac's for
  package names, services, relayd, pf, nsd and Ruby command names. Production is
  one host family with one Ruby pin, so a platform matrix or a Linux runner
  cannot reproduce what differs: the Mac and box locks disagree because
  `rb-kqueue` resolves only on BSD, and the fix is the `install_if` entry in
  `TODO.md`.
- **No repair-plan command, no dry run on every mutating command, and no deploy
  that fails closed on revision drift.** A deploy is the only mutation and halts
  on its first failure. Revisions disagree between deploys by design, which is
  why `health_check.rb` warns on commits behind, and failing closed blocks the
  deploy that fixes the drift. A planning surface beside `vps-deploy` is a third
  surface where the root contract allows two.
- **No automated rollback.** Rolling back is deploying the previous SHA through
  `vps-deploy`. A second path that runs once a year is untested on the day it is
  needed, the same argument the three unrun recovery scripts carry in their
  headers.
- **No pledge or unveil for the Rails daemons.** A Ruby interpreter that loads
  native extensions and forks workers cannot name a useful promise set. MASTER's
  `Ground::Pledge` covers the one process that can, and each app runs as its own
  user with its env file and storage closed to others, which `health_check.rb`
  checks.
- **No speed work on deploy or health tooling without a symptom.** The box's
  measured problem is memory, which is why `core-reclaim.sh` and `keep-warm.sh`
  exist, not the cost of a gate's system calls. A health check made faster by
  proving less is a regression. Latency work starts from a symptom a visitor or a
  log names, and is measured on vm23.
- **No idempotency keys, cart expiry, stuck-order alarms or edit locks for
  takeaway and marketplace while no vendor is live.** Turbo disables a submit in
  flight and the order state machine refuses illegal transitions under test. The
  first duplicate order from a real kitchen is the measurement they wait for.
- **No per-component screenshot baselines, density tests or control-distance
  rules.** `layout_snapshot` commits reviewable geometry for the surfaces, and how
  dense a screen is stays the operator's call about how it looks.
- **No sweep of `|| true`.** Most are idempotence on `rcctl`, `pkill`, `chmod`,
  `install` and `rm -f`. Read the exit path before removing one.
