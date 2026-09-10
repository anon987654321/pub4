# Decisions

Deploy and VPS policy. Agent/runtime policy lives in `MASTER/DECISIONS.md`.

## No Fourth Public App Until brgen Boundaries Hold (2026-07)

**Status:** accepted **Context:** brgen already hosts many verticals (social,
marketplace, dating, playlist, takeaway, TV, maps, live, messenger) in one
deployable Rails app. Historical restarts (aight → ai3 → pub2 → pub3 → pub4)
repeatedly expanded surface before isolation and shared contracts were boring.

**Decision:** Do not add a **fourth public Rails app** (beyond brgen, amber,
bsdports) until:

1. High-churn brgen verticals (marketplace, dating, takeaway at minimum) are
   **namespaced engines** with their own migrations and test boundaries (still
   one `rc.d` service is fine).
2. Cross-cutting money (**øre/cents**) and **trust/identity** primitives live in
   `RAILS/shared` with unit tests consumed by more than one app.
3. CI runs **layout_suite** (design craft) plus **/up smoke** for all three
   inventory apps on every relevant change.

**Consequences:** New product energy goes into Bergen density (seed, guest demo
path Live → listing → message) and engine extraction, not
`hjerterom`/`blognet`-class launches. Horizon ideas stay in
`RAILS/apps.horizon.yml` with `agent: ignore` until the three gates above are
green.

## Repo Layout (2026-07)

- `RAILS/` — Rails apps + shared engine (was `DEPLOY/rails`)
- `OPENBSD/` — VPS config backup (`etc/`, `usr/`, `var/`) plus deploy tooling
  (`bin/`, `lib/`, `sh/`, gates)
- The `DEPLOY → OPERATOR → OPENBSD` renames completed 2026-07-14; legacy path
  strings still resolve, through `RAILS/shared/lib/pub4/deploy_paths.rb`, which
  is what `Pub4::DeployPaths` is

## OpenBSD First

OPENBSD targets vm23. macOS local checks are useful, but OpenBSD behavior wins
for package names, service management, relayd, pf, NSD, and Ruby command names.

## The Nameserver Owns The Zones, Not The Repo (2026-08-02)

We run our own authoritative nsd with a lot of domains — 61 zones in
`/var/nsd/zones/master`, none of them in git, and that is deliberate. The signed
artifacts (`*.zone.signed`, `K*.key`, `K*.ds`) are regenerated on every re-sign,
so mirroring zone data would put a churning copy of the DNS into every diff
while the nameserver stays the real source of truth.

`OPENBSD/sync.rb` used to glob all four zone patterns. It had never actually
been run, which is the only reason the repo is clean of them; the globs are now
removed so the first person to run it does not import 61 zones by accident.
`nsd.conf` is still mirrored — that is server configuration, not zone data.

An audit that reports "61 zone files missing from the repo" is describing this
decision, not a gap. Do not close it.

## `OPENBSD/lib/` Owns The Gate Kernel, On Purpose (2026-08-13)

**Status:** accepted

**Context:** `Deploy::GateResult` lives in `OPENBSD/lib/` and RAILS requires it
at 53 sites — with `deploy_inventory` (16) and `utf8` (5), 74 requires across
the tree boundary. RAILS's whole 59-file gate framework is built on a type owned
by the deploy tree, and the directory names say the opposite. The operator debt
register (`gate_result_is_a_shared_kernel_filed_under_deploy`) measured that in
2026-08 and named the two ways out: extract a repo-level shared kernel, or write
this entry. It stayed unwritten, and 2026-08-13 added `gate_ledger.rb` beside
`gate_result.rb` — so the choice was being made by accretion instead.

**Decision:** the deploy tree owns the gate kernel. `OPENBSD/lib/` holds the
types every gate returns and the state every gate reads; RAILS, MASTER and
STUDIO consume them by `require_relative` across the boundary and add nothing to
them.

**Why not a repo-level `lib/`:** a fourth top-level tree whose only content is
three files, and the dependency it would remove is one RAILS already has and
does not suffer from. The real asymmetry is the other way and worth keeping:
**MASTER requires nothing from either tree** — it reads their data (`apps.yml`,
`TODO.md`) and shells out to their scripts, but no `require_relative` crosses
into it. That independence is what a shared kernel would quietly erode, because
a kernel is exactly the thing everything ends up requiring.

**Consequences:**

- A gate anywhere returns `Deploy::GateResult`. Adding an outcome to it is a
  deploy-tree change with four consumers (`RAILS/gates/runner.rb`,
  `OPENBSD/bin/check-*`, `STUDIO/gate.rb`, `OPENBSD/lib/gate_environment.rb`),
  not a local one.
- MASTER reaches STUDIO's gate by subprocess (`rake studio` shells out) rather
  than by require, specifically so `MASTER/Gemfile` and `MASTER/lib` stay clear
  of `OPENBSD/lib`. That is the rule this entry exists to keep visible.
- If a fourth tree ever needs the kernel and cannot take a subprocess, revisit —
  three consumers is a convention, five is a library.

## relayd Owns TLS

TLS terminates at relayd. Rails apps must use `config.assume_ssl = true` and
must not force SSL themselves.

## Loopback App Ports

App ports are internal implementation details. Public ingress is 22, 25, 80, and
443; app ports stay behind relayd.

## `rails/apps.yml` Is Canonical

App status, domains, ports, and deploy scripts live in `RAILS/apps.yml`.
`OPENBSD/deploy_inventory.json`, relayd, acme, NSD, and docs should agree with
it.

## Copy-Tree Deploy

Rails app trees are copied to `/home/<app>/app`; shared code is copied to
`/home/<app>/shared`. Do not assume symlinked repo layout on the VPS.

## MASTER Web Assets Must Be Explicit

Falcon does not hot-reload production assets. MASTER web changes require `rails
assets:precompile` and `doas rcctl restart master`.

## Falcon Only (No Puma)

Production app servers on vm23 are Falcon (`falcon serve` in `/etc/rc.d/*`). Do
not add Puma or run `bin/rails server` with Puma in production.

**Corrected 2026-08-13. Falcon does not honour `SOLID_QUEUE_IN_PUMA`, and this
paragraph saying it did is why nobody looked.** The variable is not a Rails-wide
switch: it is read by Solid Queue's *Puma plugin*, activated by `plugin
:solid_queue` in `config/puma.rb`. None of the three apps has a `config/puma.rb`
at all, so no plugin ever loaded and the variable was read by nothing.

Measured on vm23 that day: brgen had 1670 jobs enqueued, 0 finished, 0
registered processes and 0 recurring tasks; amber 103 and 0. No background job
had ever run — including 150 `MessageExpirationJob`, so disappearing messages
had never disappeared, and `PruneGuestUsersJob`, so 143,000 stale guest rows had
never been pruned.

The variable is gone from all three `rc.d` files and the template. A Solid Queue
worker under Falcon needs its own process: `etc/rc.d/<app>_jobs` exists for each
app and is deliberately not enabled — read its footer, because vm23 is 1 GB and
already cannot hold what it runs. `health_check.rb` fails when a queue has
unfinished work and no registered process, so whichever way that goes it is
visible.

**And the deploy was deleting the queue (2026-08-13).**
`rails_prepare_secondary_dbs_as_app` in `RAILS/_database.sh` ran
`db:schema:load:{cache,queue,cable}` on *every* deploy. Rails schema files
declare `create_table … force: :cascade`, so a schema load drops each table and
recreates it empty. Every deploy discarded every enqueued job. brgen's 1670
pending jobs were gone within the hour of the 2026-08-13 deploy — deleted, not
run.

Secondary schemas are now loaded **once**, when the database does not already
carry its tables. `rails db:prepare` on the preceding line already creates and
migrates every configured database (`DatabaseTasks.prepare_all` walks
`each_current_configuration`, not just primary); the explicit loop stays as a
backstop, guarded. Pinned by
`test_secondary_schema_load_is_guarded_by_an_initialisation_check`.

This mattered less than it looks like it should have, because nothing was ever
going to run those jobs — and that is exactly why it needed fixing before the
worker question is settled rather than after. A deploy that discards the
password-reset emails enqueued while it was running is a worse bug than no
worker at all.

## A Foreign Key To `users` Needs A `has_many` On `User` (2026-08-13)

Any table with an FK to `users` must have a matching association on `User` with
an explicit `dependent:`. Without one, `User#destroy` raises
`SQLite3::ConstraintException: FOREIGN KEY constraint failed` — from the
database, not from Rails, with nothing in the model to explain it.

`message_receipts` and `typing_indicators` were declared only on `Message` and
`Conversation`. The consequence was not theoretical: account deletion was
impossible for any user who had ever been in a conversation, which is precisely
what the `deletion_scheduled_at` and `deleted_at` columns exist for, and
`PruneGuestUsersJob` had never removed a row.

Two related traps found the same day:

- `db:migrate:status` cannot see a migration that ran and created nothing.
  `20260514120000_create_identity_and_trust_primitives` was recorded as applied
  with none of its seven tables present, and the migration system reported 0
  pending. Compare `schema.rb`'s `create_table` list against the live tables
  instead.
- `in_batches(of: N, &:destroy_all)` over a relation carrying a JOIN does not
  survive deleting from that relation. It removed 3,832 of 143,339 eligible rows
  and returned success. Pluck ids, delete by id, re-query.

## Deploy Script Names

- `OPENBSD/OPERATOR.sh` — full vm23 OpenBSD installer (etc/usr/var, relayd,
  services)
- `RAILS/deploy.sh` — Rails app copy-tree deploy only (brgen, amber, bsdports)

## `/etc/doas.conf` Installs Only On A Deliberate Root Run (2026-08-02)

**Status:** accepted. Moved here from the old OPENBSD/data/debt.yml register,
where it was the tail of a closed entry — it is policy, not debt.

dev's rule is a five-variable `setenv` allowlist (`I_UNDERSTAND_DNS_WIPE`,
`I_UNDERSTAND_CONSOLE_RISK`, `RUN_PRODUCTION_SEEDS`, `SKIP_MASTER_SCAN`,
`MAIL_IMG_FMT`) — measured, not guessed: those are the variables that scripts
invoked under doas read and never assign themselves. `keepenv` was removed from
it because it preserves `RUBYOPT`/`RUBYLIB`/`GEM_HOME` across the privilege
boundary, which is arbitrary code execution as root by construction. It stays on
the root→root rule deliberately: it grants an attacker nothing they do not
already have, and stripping it would remove the environment the outer dev→root
hop just established from under the inner one.

Command scoping is **not** available as a hardening step here. The deploy
pipeline invokes `doas zsh` 27×, `doas sh` 8×, `doas ksh` 6× and `doas su` 2×,
and a root shell is equivalent to blanket root.

The file is installed by `OPERATOR.sh` or an explicit `doas ksh
validate_doas.ksh install <file> <reason>` — **never by a cron tick.** The
auto-heal that used to install it (`relayd-watchdog`, `config-drift-check`) was
root executing a dev-owned checkout, so it was removed; the consequence is that
a repo edit here does not reach the box by itself. A hardened `doas.conf` sat in
the repo for a day while production still ran the unhardened one, because the
installer everyone assumed existed did not work. Verify live with `doas cat
/etc/doas.conf`, not with the repo file. `vps_safety_gate.rb` pins the repo
copy.

## Release history (from RELEASE.md, merged 2026-07-10)

- **Gate chain restored** — repointed `require_relative "utf8"` refs after the
  `tools/` reorg; every gate had been crashing with `LoadError`.
- **CLI + probe bugs** — `Master::CommandRegistry.tree_lines` →
  `Master::Now::CommandRegistry.dispatch_tree`; nsaudit eager-loads + skips the
  kernel spine; smoke-web no longer crashes on a refused connection and skips
  cleanly off-VPS; asset drift regenerated.
- **baibl + blognet removed** — apps, relayd, acme, nsd (zones + DNSSEC keys),
  litestream, rc.d, inventories (`deploy_inventory.json`, `apps.yml`), gates,
  tests, and their vanity/megablog domains.
- **Web "tap to start" hardening** — platform-level guard in
  `chat/index.html.erb` blocks WebGL until primer tap.

## Open decisions (2026-07-10)

- **No staging environment.** vm23 is the only environment; a full staging copy
  would worsen 1-vCPU/1GB pressure (see `OPENBSD/resource_guard.sh`).
- **Auto-commit atomicity.** Unrelated automated commits to `main` sometimes
  bundle unrelated changes; scope commits to one concern each.

## Every gate carries its known-bad fixture — 2026-08-22

From arXiv 2608.04066 via the precision-ledger debt entry: a gate that has never
been run against an input it MUST flag is a claim, not an instrument — the
campaign's own instruments were wrong four times in two days and each time only
production or accident caught it. Doctrine, adopt-forward: a NEW gate ships with
the shape it must flag and the shape it must not (tap_target_probe and
focus_walk_probe are the exemplars; layout_search's detector test is the
retrofit shape); an EXISTING gate gets its pair when next touched. Not a
big-bang retrofit of 47 gates — the same enforce-forward choice as FILE_SPRAWL.

## rcctl owns rc.conf.local, and litestream is off the boot list — 2026-08-25

**`/etc/rc.conf.local` cannot hold prose.** `rcctl enable/disable` rewrites the
file and re-sorts every line alphabetically. A fourteen-line rationale installed
at the top came back interleaved into nonsense on the next `rcctl disable` —
sentences from three paragraphs alternating, because each line sorted
independently. One comment line survives (`#` sorts to the top); anything longer
does not. The mirror in `OPENBSD/etc/rc.conf.local` carries exactly one line,
which says this, and points here.

It does not show up immediately: the scrambling happens on the next rcctl write,
not on install, so a drift check run straight after installing passes.

**litestream is removed from `pkg_scripts` and `rcctl disable`d.** It has never
replicated anything and cannot — litestream is not in OpenBSD ports, so there is
no package to add and no port to build. Left enabled it failed at every boot and
sat permanently in `rcctl ls failed`, which is the list `daily.out` prints under
"services that should be running but aren't". A list whose only entry can never
be fixed teaches everyone to skim it, and that list is how a real outage is
supposed to announce itself. It is empty now.

This is not a decision to go without off-host backups. `OPENBSD/bin/dr-pull`
runs nightly from the operator Mac under launchd, snapshots every
`production*.sqlite3` with `VACUUM INTO`, verifies `PRAGMA integrity_check` on
arrival and keeps the last 14. Verified 2026-08-25 by an actual restore drill:
posts and listings in the 24th's brgen snapshot matched live exactly. If
litestream is ever wanted, it needs a Go build on the box, which is a separate
decision with its own maintenance cost.

## dev keeps passwordless root, and here is the exposure — 2026-09-10

**Status:** accepted, with a review trigger. This closes a question that had sat
open for weeks as "the operator's to schedule", which is not a posture — it is an
absence of one. The rule stays. What follows is what it costs, what already
limits it, and the one narrowing someone could actually walk.

**The rule.** `/etc/doas.conf:39` reads `permit nopass setenv { … } dev as root`.
`doas -C /etc/doas.conf id` prints `permit nopass` on the box. Check it with that
form and not with `-u dev`: `-u` names the target user and defaults to root
(doas(1)), so `-u dev` asks whether dev may run a command as dev, which no rule
permits. It printed `deny` against `permit nopass` for the plain form in the same
minute, and this row read as closed for weeks on that backwards measurement.

**The exposure, stated plainly.** Anything that executes as dev is root. Not "can
become root with effort" — root on the next line, with no password and no prompt.
dev is the account ssh lands on, the account `bin/vps-deploy` runs as, the account
`MASTER/bin/master` runs as from a terminal, and the owner of `/home/dev/pub4`, a
checkout several agent sessions write to every day. So the trust boundary is not
the doas rule; it is every commit that reaches that directory. The four daemons
are not in it: brgen, amber, bsdports and master each run under their own account,
none is in `wheel`, and none has a doas rule, so an application bug does not reach
root through this file. dev and root are the only members of `wheel`, and sshd
carries `PermitRootLogin no` and `PasswordAuthentication no`, so the reachable
door is a dev key.

**Why command scoping cannot narrow it.** doas.conf(5) matches `cmd command
[args argument ...]`, and the arguments a user supplies must match those
specified. Measured 2026-09-10 over tracked executable files, ignoring comments,
documentation and tests: 123 `doas` call sites, 103 of them in `OPENBSD/` across
20 files and 20 in `RAILS/_deploy.sh` and `RAILS/deploy.sh`. Twenty-one are a
shell — 11 `doas zsh`, 6 `doas sh`, 3 `doas su`, 1 `doas ksh` — and a root shell
is blanket root, so no allowlist containing one is narrower than the rule it
replaces. The 39 `doas rcctl` sites are not the safe remainder either: `rcctl set
<svc> flags` writes `/etc/rc.conf.local` and root executes those flags at the next
boot, and the deploy passes the service name as a variable, so pinning `args` is
not open to it. Scoping this file is arithmetic that does not come out.

**Why dropping `nopass` cannot work either.** Every escalation here is
non-interactive: cron ticks, an ssh one-shot, and `bin/vps-deploy:6`, which runs
as dev and escalates per step by design. `persist` does not help — it suppresses
the *second* prompt after a successful authentication, and these callers have no
terminal to answer the first. Drop `nopass` and every deploy path stops at its
first `doas rcctl`.

**What is already spent, and must not be given back.** `keepenv` came off the dev
rule and was replaced by a measured five-variable `setenv` allowlist, because
`keepenv` carries `RUBYOPT`/`RUBYLIB`/`GEM_HOME` across the boundary and that is
arbitrary code execution as root by construction. No cron path installs
`doas.conf` any more. Root cron execs no file inside the checkout: `uptime-check`
and `config_drift_gate.rb` are installed copies, and `vps_weekly_integrity.sh` now
drops to dev before it reads a line of `/home/dev/pub4`. `validate_doas.ksh`
installs from a timestamped backup and rolls back when the post-install check
fails. Those four are the mitigation; the rule is survivable because of them.

**The one narrowing someone could walk.** Collapse the escalation into a single
root-owned entry point. Install one script — call it `/usr/local/sbin/pub4-deploy`
— holding every step `bin/vps-deploy` currently escalates for, and reduce dev's
rule to `permit nopass dev as root cmd /usr/local/sbin/pub4-deploy`. It works for
the reason scoping otherwise fails: `cmd` matches what doas executes, so moving
the body out of the dev-writable checkout into a file only a deliberate root
`install` can replace makes the boundary the install rather than the pull. The
price is real and is why it is not being taken today. It inverts the bootstrap —
the box could no longer deploy a checkout it had not already installed from, so a
hotfix would need a root run first — and it turns 103 call sites into one script
whose failure modes are all new. Do it as a scheduled rebuild of the deploy, with
`OPERATOR.sh` as the installer, or do not start it.

**Two smaller things worth doing before that, and neither is this tree's.**
MASTER's shell effect is not gated against escalation: `zsh.forbidden_commands` in
`MASTER/data/rules.yml` is a style list of GNU tools and it names `doas` as the
recommended replacement for `sudo`, so nothing stops a shell effect from calling
it. Adding `doas` and `su` to what that effect refuses would remove the largest
everyday path from a language model to this rule, and it is a MASTER change.
Second, dev is in `wheel` as well as in `doas.conf`; that is redundant while the
doas rule stands and worth removing in the same pass as the rebuild, not before.

**Review trigger.** Reopen this when the deploy is rebuilt, when a fourth account
needs root, or when anything other than a deliberate operator action starts
running as dev on the box.

## The three unrun deploy scripts stay, as recovery paths — 2026-09-10

**Status:** accepted. `deploy_all.sh`, `vps_run_remote.sh` and
`manual_master_deploy.ksh` are named by `RUNBOOK.md` and by nothing that runs,
which reads as sprawl every time someone counts files. They are kept, and this is
the record so the count stops reopening the question.

Each covers a case `bin/vps-deploy` does not. `deploy_all.sh` re-applies box
config after drift, which the deploy assumes is already right. `vps_run_remote.sh`
bootstraps a fresh VM through the hypervisor console jump, which is the only path
that exists before ssh works. `manual_master_deploy.ksh` recovers a stalled master
deploy under tmux, and it is the one of the three that records `_fail=1` and exits
1 rather than swallowing the face build. Deleting them removes three recovery
paths and duplicates nothing.

The reason they are unrun is the reason to keep them: each is for a day the normal
path is unavailable. That also means none of them is exercised, so treat all three
as untested on the day you need one, and read before running. If a future session
wants them gone, the argument to beat is not "nothing calls them" — nothing is
supposed to — it is "this capability is not wanted", and that is the operator's
sentence to write.

