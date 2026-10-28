# Operator

Production runbook for pub4. Read this file before live work. Read `MASTER/README.md` for the agent runtime; this file covers the
VPS and deploy surface, the agent contract, and live-operation safety in one
place.

## Redeploy (one command)

From a clean workstation checkout on `origin/main`:

```zsh
./bin/redeploy
```

Hands-off: local preflight → pin SHA → `tmux` session `pub4-deploy` on vm23 →
`vps-deploy` as **root** (git still as `dev`) → streams the log until finished →
`vps-state` + public canary. Survives SSH disconnect. Log: `/home/dev/vps-deploy.log`.
Attach: `tmux attach -t pub4-deploy`.

Already on the box: `zsh OPENBSD/bin/redeploy`.

## Repo layout

`MASTER/`, `RAILS/`, `OPENBSD/`, `STUDIO/` at the repo root, plus dotfolders. `MASTER/tools/` is inside MASTER and keeps compatibility entrypoints.
Canonical inventories: `RAILS/apps.yml`, `OPENBSD/deploy_inventory.json`. The
JSON is generated from `apps.yml` by `ruby OPENBSD/bin/sync_deploy_inventory.rb`,
and the `domain_alignment` check fails when the two disagree. Deploy
checks (`integrity_check.rb`, `verify_deploy_identity.rb`,
`deploy_inventory.json`) live at `OPENBSD/` top level, and so does
Old quarantine samples were deliberately removed from the tracked tree. It is not a recovery path:
`bin/dr-pull` recovers the databases and `manual_master_deploy.ksh` a stalled
master deploy. There is no `archive/`; git history holds the old installers.

## Deployment map

```text
Internet
  -> pf
  -> relayd TLS/SNI
  -> loopback app ports
      -> MASTER Falcon on ai.brgen.no
      -> brgen Rails app and vertical subdomains
      -> amber Rails app
      -> bsdports Rails app
  -> NSD/acme/httpd for DNS and certificate plumbing
```

Runtime contract: TLS terminates at relayd; apps listen on loopback-only ports;
Rails uses SQLite plus Solid Queue/Cache; secrets live in `/etc/*.env`; source
of truth on the VPS is `/home/dev/pub4`; long deploys run under tmux.

Check flow — local: `OPENBSD/bin/check` → `verify_deploy_identity` → Rails
production/domain/ phantom/frontend checks → OpenBSD deploy smoke. Operator: `git
pull --ff-only` on vm23 → `vps_ci.sh <app>` → `OPERATOR.sh` or per-app deploy →
`rcctl restart` affected services → `health_check --public --all-ready-apps`.

## Privileged deploy broker

The staged root boundary is `/usr/local/sbin/pub4-admin`, mirrored at
`OPENBSD/usr/local/sbin/pub4-admin`. A deliberate `OPERATOR.sh` sync installs
it as `root:wheel`, mode `0555`, and installs the fixed CI preparation/sync/runner
plus Rails task and Rails tree-sync helpers under `/usr/local/libexec/`; the Solid Queue proof
is installed under `/usr/local/libexec/pub4/`.

The broker exposes allowlisted service actions, validated deploy receipts, fixed
CI lock/preparation operations, and trusted helper verbs. CI and production Rails
tree mutations run with the selected app's UID, primary GID and only the required
`_pub4ci` supplementary group. Production sync stages tracked `HEAD` paths from a
Git archive, not ignored files from the mutable working tree. The CI runner has a real wall-clock deadline and terminates
its full process group, including `bundle install`. Rails tasks use a closed
task vocabulary; `SECRET_KEY_BASE` crosses only in the child environment, never
in the shell command text. Bundle directories and initial cache seeding are created
by the target app user. The shared Bundler CAS has a fixed Ruby-version namespace;
root accepts only app-owned `.gem` inputs, stores SHA-256-addressed read-only copies,
and the app copies objects back without hard links.

The MASTER web deploy has two argument-free broker verbs for the fixed
`/home/dev/pub4/RAILS/master` tree: `master-web-assets-reset` and
`master-web-runtime-dirs`. `vps_deploy_master.sh` refuses a `ROOT` override and
compares the tracked `rc.d/master` with the installed root-owned service file;
a mismatch requires a deliberate `OPERATOR.sh` sync instead of copying checkout
code into `/etc` as root. `deploy-smoke` uses brokered service checks too.

`vps_install_all.sh` is a fresh-box bootstrap: its service-control helper uses
the broker when present, with a documented direct-`rcctl` fallback only before
the broker has been installed. That exception must be removed or formally
confined before the `dev` doas rule or wheel membership can be narrowed.
`relayd-check` is read-only: it verifies the root-owned relay configuration's
TLS keypair, Host route and app backend/port. It refuses unapproved routes rather
than letting a deploy caller rewrite public routing policy. New hostnames must be
added to `OPENBSD/etc/relayd.conf` in a deliberate `OPERATOR.sh` change first.
The loopback health probe runs as the deploy user and needs no privilege.

`vps-deploy`, CI receipt writes, CI lock setup, CI preparation/sync/execution,
production Rails tree sync, Rails runtime tasks and relay route verification use the broker when
the installed copy exists. It creates the canonical `/var/db/pub4/ci.lock`; keep
`PUB4_CI_LOCK` unset on vm23 until the legacy override seam is removed.
Both `vps_ci.sh` and `vps-deploy` now refuse to run until the reviewed broker is installed. Those entrypoints no longer contain root-copy/root-shell fallback, direct `rcctl` fallback, direct receipt writes, checkout-sourced resource-guard execution, or direct Solid Queue proof execution. The Rails deploy adapter also refuses service control without the broker. The broader recovery and operator scripts still need a complete privilege audit before narrowing `doas.conf`.

This is **not yet the complete privilege migration**: recovery, operator and a few ancillary install scripts still require a direct-`doas` audit. Keep the current `doas.conf` and wheel membership
unchanged until those paths are migrated, the broker is installed, and the focused
and full OpenBSD contract suites pass. Then narrow the `dev` rule and remove wheel
membership in one planned rollout, with an authenticated operator recovery path
established first.

## Command selection and diagnosis

The target host determines command semantics. Begin with bounded, read-only facts:
`uname -srm`, `uname -v`, `id`, `pwd`, and `command -v <utility>`. Record
the release and relevant PATH entries; do not dump the full environment, which
may contain secrets. Use `man <utility>` and `man -k <topic>` on the target.
If a local manual is unavailable, consult the explicit release path
at `https://man.openbsd.org/OpenBSD-<release>/<page>` and cite the release actually
observed; current-manual pages are not proof for an older host. Never assume
Linux `/proc`, GNU-only flags, or an optional package exists on the host.

For a daemon incident, distinguish configured, enabled, running, locally healthy,
and publicly reachable. Check the relevant `rcctl configtest` and `rcctl check`,
then inspect the process, listening socket, and service logs. For a public outage,
trace DNS and TLS, PF and relayd/httpd, the loopback listener, and the application
in that order. A healthy TLS endpoint alone does not prove the backend is up;
a failed immediate service check during startup does not by itself prove a crash.
Verify independently with a service signal, an application-level request, and
the actual public route where relevant.

For patch state, `syspatch -c` lists available base patches and
`syspatch -l` lists installed patches. Neither alone decides a release upgrade.
Read the target release's upgrade instructions, establish a usable backup and
console/recovery path, and assess service and package compatibility before
proposing an upgrade.
OpenBSD supports upgrades only to the immediately following release. If the host
is more than one release behind the target, plan and verify each supported
transition in sequence; never assume a direct jump is supported.

Before any mutation, preserve the observed state and establish a recovery route.
Validate configuration with the service's supported test (for example,
`rcctl configtest` or `pfctl -nf /etc/pf.conf`), make one scoped change, and
verify its effect independently. Do not infer success from a wrapper's exit code
when the underlying operation has its own receipt or health check.

## SSH

One session at a time. Rapid reconnects trip pf bruteforce.

| Target | Command |
|--------|---------|
| VM (apps) | `ssh -i ~/.ssh/id_ed25519_brgen dev@brgen.no` or `ssh brgen` |
| VMM host | `ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam` |
| Console | `vmctl console vm23` then `doas pfctl -t bruteforce -T flush` |

SSH aliases, host topology and provider access are kept in this runbook so live-operation guidance has one source.

## Domains

| Service | URL |
|---------|-----|
| MASTER | `https://ai.brgen.no` |
| brgen | `https://brgen.no` |
| brgen · marketplace | `https://markedsplass.brgen.no` |
| brgen · dating | `https://dating.brgen.no` |
| brgen · playlist | `https://radio.brgen.no` |
| brgen · takeaway | `https://takeaway.brgen.no` |
| brgen · tv | `https://tv.brgen.no` |
| brgen · messenger | `https://messenger.brgen.no` |
| amber | `https://amberapp.art` |
| bsdports | `https://bsdports.org` |

The brgen verticals (marketplace/dating/playlist/takeaway/tv/messenger + `maps`)
are one Rails app served under subdomains via `<brgen>`; relayd already routes
them all (`etc/relayd.conf`).

### Bringing a domain up

Seven city domains serve brgen, each scoped to its own city: `brgen.no`,
`oshlo.no`, `trndheim.no`, `stvanger.no`, `cardff.uk`, `edinbrgh.uk`,
`frankfrt.de`. Six more hold a zone that nsd serves and an `acme-client.conf` block, and
none has an NS record at its registrar, so nothing asks our nameserver for
them. Registry lookups on 2026-10-12 found only `brssels.be` registered.
`brmingham.uk`, `glasgw.uk`, `lverpool.uk` and `mnchester.uk` (Nominet,
"This domain name has not been registered", after "Renewal required" in
June) and `dnver.us` are unregistered: the .uk names lapsed on 24 and 25 June
2026 and anyone may now register them. Bringing one up starts with buying it
back, which is a registrar login, or with deleting its zone and
`acme-client.conf` block if the city is dropped (record that in
`data/domain_released.yml`). `ruby OPENBSD/bin/domain_watch.rb` is the check.

The order below is not a preference. Each step needs the one above it, and the
last step is the one that bites: relayd refuses to start when a `tls keypair`
names a certificate that is not on disk, so adding the keypair early takes down
every site relayd serves, not just the new one.

1. **Delegate at the registrar** — NS to `ns.hyp.net` and `ns.brgen.no`,
   matching `oshlo.no`. This is the only step that is not on this box.
2. **Confirm it resolves to us**, or acme cannot answer its own challenge: `ruby
   -rresolv -e 'puts Resolv.getaddress("glasgw.uk")'` → `46.23.89.226`.
3. **Issue the certificate.** The `domain` block already exists in
   `/etc/acme-client.conf`; `doas /usr/local/bin/renew-certs.sh` picks it up, or
   `doas acme-client -v glasgw.uk` for one.
4. **Check the certificate is on disk** before touching relayd: `doas ls -l
   /etc/ssl/glasgw.uk.fullchain.pem`.
5. **Add `tls keypair "glasgw.uk"`** to `etc/relayd.conf` beside the other city
   keypairs, then `doas relayd -n` and only then `doas rcctl reload relayd`.
6. **Verify**: `curl -sS -o /dev/null -w '%{http_code}' https://glasgw.uk/` is
   200, and the page title names the city.

The stack serves three Rails apps (brgen, amber, bsdports) plus MASTER. `baibl`,
`blognet` and `hjerterom` are retired; on 2026-08-12 their users, home
directories (1.6 GB between them), rc.d scripts, `/etc/*.env` files, login
classes, certificate symlinks and DNS zones were removed from vm23, and their
own domains (`baibl.no`, `blognet.no`, `hjerterom.no`) with them. Databases are
kept at `/var/backups/pub4/{hjerterom,deleted-apps}-20260812`. `foodielicio.us`
and the `anti{casino,gambling,betting}blog.com` trio were not removed: they stay
in `data/dns.yml`'s `extra_zones`, and nsd still serves them.

The repo recorded baibl and blognet as removed two months before the box lost
them, which is why `port_inventory` scans the config files where that kind of
residue lives, so the next removal cannot be half-done quietly.

Seven city apexes serve as of 2026-08-12
(`Brgen::DomainRegistry::LIVE_DOMAINS`); the rest of `ENTRIES` is either
NXDOMAIN at the registrar or parked at Domeneshop.

TLS terminates at relayd. Rails sets `config.assume_ssl = true`; do not enable
`force_ssl`.

## Agent contract

Modes: local contributor (edit repo files, run local checks, do not SSH), VPS
operator (one SSH session, one CI/deploy operation at a time, tmux for long
work), recovery (human-directed console or resource guard only to restore access
or health, then document the fix).

**Hard stops — AI agents must not autonomously:**

| Action | Why |
|--------|-----|
| `vmctl console/stop/start/reboot` on server4 | Serial console sessions have caused VM reboots and site outages |
| `pkill`/`kill` of `cu`, `vmctl`, or other VMM console sessions on server4 | Disrupts other operators and can wedge vm23 |
| `vps_console.exp` without human approval | Gated by `I_UNDERSTAND_CONSOLE_RISK=1`; recovery-only |
| Deploy, install, or `pkill` deploy workers from the serial console | Bypasses SSH safety, tmux, and load checks |
| Target vm27 or any non-vm23 VM | Wrong tenant; production is vm23 (`dev`) |
| `OPERATOR.sh --stage-1` without `I_UNDERSTAND_DNS_WIPE=1` | Destructive DNS wipe |
| Parallel SSH deploys, parallel `bin/ci`, or broad `rcctl restart` without a named target | 1 GiB VPS; contention causes outages |

When SSH to vm23 is required, use normal paths — but note which of them takes
`doas` and which must not:

| | |
|---|---|
| `doas zsh OPERATOR.sh` | root, it installs `/etc` |
| `zsh OPENBSD/bin/vps-deploy <app>` | **root** (or `dev` via passwordless doas re-exec) |
| `zsh OPENBSD/bin/vps_ci.sh <app>` | **dev** |

`vps-deploy` runs as root. Git fetch/checkout still run as `dev` so the
`/home/dev/pub4` tree and GitHub deploy key are never used by root. Typing the
command as `dev` is fine: passwordless doas re-executes it as root.

**Laws:**

- Run `MASTER/bin/operator status` before starting work; the copy-paste paths
  are in `OPENBSD/data/operator.yml`.
- Treat `RAILS/apps.yml` and `OPENBSD/deploy_inventory.json` as inventories, not
  suggestions.
- Any `/etc` change made on vm23 must be copied back to `OPENBSD/etc/`.
- Use the available Ruby on OpenBSD (ruby40, ruby34 … resolved by `OPENBSD/lib/ruby_select.sh`, which sets `$RUBY` and `$BUNDLE`); `zsh OPENBSD/bin/vps_ci.sh <app>` for
  per-app CI.
- Keep secrets in `/etc/*.env`; never commit them.
- Keep Rails `config.assume_ssl = true`; do not enable `force_ssl` behind
  relayd.
- Prefer local checks first (`OPENBSD/bin/check`) before any SSH.

**Agent dmesg (verbose file operations):** external agents (Grok CLI, Claude
Code, Cursor) and MASTER should log mutations in OpenBSD dmesg style — terse,
lowercase, one fact per line, path-first, e.g.:

```
write OPENBSD/etc/rc.d/brgen 412B +12/-3
read MASTER/lib/reach/base.rb sha256=a1b2c3… 2048B
run zsh OPENBSD/bin/check-openbsd exit=0
```

Name the path on every read/write/delete; show evidence on writes (diff stat or
byte size); show command + exit code for shell, not "deployed successfully."
Silence on success is fine for bulk checks; speak up for each mutated file.
MASTER: `/dmesg` or `toggle dmesg` streams bus events.

**Reporting** — good deploy closeout: exact host/environment, commands run,
checks passed/skipped/ failed, services restarted, remaining manual verification.
Bad: "deployed" without host/command, public health not checked, asset
precompile skipped after web changes, route/cert changes without relayd/acme/NSD
context.

## Console automation check

Recovery-only expect scripts refuse to run unless a human operator exports
`I_UNDERSTAND_CONSOLE_RISK=1` (same pattern as `I_UNDERSTAND_DNS_WIPE=1` for
`OPERATOR.sh --stage-1`).

## doas.conf

OpenBSD rejects `/etc/doas.conf` without a trailing newline — `doas` breaks for
everyone. `OPERATOR.sh` fixes the repo copy before install, validates `su dev -c
'doas id'`, and rolls back on failure. No cron job installs it: the only other
path is a deliberate `doas ksh OPENBSD/bin/validate_doas.ksh install <file> <reason>`,
which validates the same way. The comment atop `etc/doas.conf` says what dev's
passwordless rule exposes and why neither command scoping nor a password can
narrow it.

## Backups

`OPENBSD/bin/dr-pull` is the backup. It runs nightly on the operator Mac under
launchd, writes a `VACUUM INTO` snapshot of every production database on vm23,
streams them back in one tar, checks `PRAGMA integrity_check` on arrival and
rotates the last fourteen. `ruby OPENBSD/bin/dr-pull --check` reports the newest
pull and its age, and fails when the newest is stale — read that rather than the
launchd exit status, because a snapshot that has stopped working exits 0.

Each pull also records `SHA256SUMS`, taken from vm23's own `sha256` before the
stream and compared on arrival, and copies the newest Active Storage blobs (the
two-character directories beside the databases) to `~/pub4-dr/blobs/<app>`.
`ruby OPENBSD/bin/dr-pull --drill` is the restore test: it copies the newest pull
to a scratch directory, checks the bytes against `SHA256SUMS`, runs
`integrity_check` on the copy, reads the migration version, table count and user
count, prints the seconds, and removes the scratch. Run on 2026-10-12 against
pull `20261011-0330` it restored and read back all three databases in 1.3 s
(amber 303 users, brgen 11316, bsdports 0; integrity ok; the pull predates
`SHA256SUMS`, so that run checked integrity only). The 11 pulls from 1 to 11
October sit on the operator Mac under launchd job `no.brgen.pub4-dr`, which
makes the Mac the only copy off vm23.

**Restored separately.** `dr-pull` holds databases and uploads, nothing else, and
no script in this repository copies the following off the box. After a rebuild
they come from the operator's own records: `/etc/master.env` and
`/etc/<app>.env` for brgen, amber and bsdports; the DNSSEC keys
`K<zone>.+013+ksk.*` and `K<zone>.+013+zsk.*` in `/var/nsd/zones/master` (no DS is published at any registry today,
so the signatures validate nothing yet; once DS records are published, losing
the KSK makes every signed zone fail validation); the DKIM key `/etc/mail/dkim/private.rsa.key`; the
ssh host keys; and the acme-client account key. Certificates and their domain
keys under `/etc/ssl` are reissued by `acme-client`, once DNS answers.

**Litestream replicates nothing and never has.** It is not in OpenBSD ports, so
`pkg_add litestream` cannot install it, `/usr/local/bin/litestream` does not
exist, and `/var/backups/litestream/` has been empty since the day it was
created. It is out of `pkg_scripts` and has no `rc.d` script, so it no longer
keeps `rcctl ls failed` permanently non-empty. `OPENBSD/etc/litestream.yml` is
kept because the config is correct for the day someone builds the binary from Go
and adds an off-host bucket; its header says why the service stays off the boot
list.

Nothing on the box is a disaster-recovery replica: dr-pull's copies live on the
Mac, which is one other disk, not a bucket. An off-host object store is the
remaining gap and it needs an account.

## OpenBSD deploy

Always use tmux. `OPERATOR.sh` runs under `doas` because it installs `/etc`.
`vps-deploy` runs as root (or re-execs via passwordless doas from `dev`); git
still runs as `dev` (see *Agent contract*). Prefer `./bin/redeploy` from a
workstation.

```zsh
cd ~/pub4
# config sync (installs /etc) — explicit doas:
tmux new-session -d -s opsync "doas zsh OPENBSD/OPERATOR.sh 2>&1 | tee /tmp/opsync.log"
# routine app deploy — script becomes root itself:
tmux new-session -d -s deploy "zsh OPENBSD/bin/vps-deploy all 2>&1 | tee /home/dev/vps-deploy.log"
tmux attach -t deploy
```

Default installs `OPENBSD/{etc,usr,var}`, validates pf/relayd, and restarts
services. Rare: `--first-install`, `--stage-1`, `--stage-2`. `--stage-1`
installs `etc/pf.stage1.conf`, which passes only 22, 53 and 80: HTTPS and SMTP
stay blocked until the full `pf.conf` goes in.

`etc/acme-client.conf` is generated by `bin/render_dns.rb` and compared by the
`dns_zones` check's `--check`, so do not byte-compare it by hand.

After `RAILS/master/` edits: `doas rcctl restart master`. Falcon does not
hot-reload.

**`OPENBSD/etc/` is canonical in intent, not in verified-deployability.** Diff
before you install, every time:

```zsh
diff -u /etc/relayd.conf OPENBSD/etc/relayd.conf   # read every hunk
doas cp -p /etc/relayd.conf /etc/relayd.conf.bak-$(date +%Y%m%d-%H%M%S)
doas install -o root -g wheel -m 644 OPENBSD/etc/relayd.conf /etc/relayd.conf
doas relayd -n -f /etc/relayd.conf                 # must print "configuration OK"
doas rcctl restart relayd
```

On 2026-08-02 the repo copy carried `tls keypair "bplan.pub.healthcare"` for a
cert that does not exist. relayd refuses to load an absent keypair, so a
straight repo→live copy would have taken **every** site on the box down. The two
files had quietly diverged since July precisely because nobody could sync them.
`OPENBSD/sync.rb` (see *Occasional operator tools*) is the return leg that keeps
this from building up.

Note also that relayd's `match response header set` **overwrites** whatever the
backend sent, so the edge value is the only `Permissions-Policy` any browser
sees, for every app. It has to be the union of what all backends need — a
`geolocation=()` there silently killed brgen's `#nearby` while the Rails
initializer said `(self)`.

When `bin/vps-deploy` fails it says where. Whatever the stage (pull, ci+sync,
migrate, precompile, restart, health, checks), an exit trap stamps
`last_deploy_<app>.json` failed, prints `FAILED at stage "<stage>"`, says
whether the app was stopped for the deploy and so is down (the next command is
`doas /usr/local/sbin/pub4-admin service start <app>` or a rerun), lists amber or bsdports if they are down,
releases the lock and the deploy flag, and appends `finished ... exit=N
stage=...` to `/home/dev/vps-deploy.log` directly, so a dropped ssh session still leaves
the verdict. A kill or hangup counts as a failure with the stage it interrupted.

### The deploy sequence and its recovery

`bin/vps-deploy all` (or one app) now does this, in order, and stops at the first
failure. Nothing is stopped before step 4.

1. Take the lock and start the log. Print nothing about services yet.
2. Pin one commit. The target is `VPS_DEPLOY_SHA`, or `origin/main` fetched once
   here, and the run prints `pinned <sha> (box HEAD was <sha>)`. It must be a
   fast-forward of the box. No later step pulls; each checks `HEAD` against the pin.
3. Prove the commit boots. `bin/operator vps deploy <app> --remote` runs
   `Operator::DeployPreflight` (`MASTER/lib/operator/canary.rb`) on your machine (Ruby syntax sweep of
   `MASTER/lib`, `MASTER/law` and `RAILS/*/app`; `test_law_files_load.rb`;
   `MASTER/tools/boot_smoke.rb`; `OPENBSD/bin/rehearse`) and sends the box the SHA
   with `VPS_DEPLOY_PREFLIGHT_SHA`. A run typed on the box has no such word and
   runs the first three itself, on the pinned commit, detached; a failure puts the
   checkout back where it was. Break-glass is `VPS_DEPLOY_SKIP_PREFLIGHT=1` and,
   like the runtime-check skip, only with `I_UNDERSTAND_FAST_DEPLOY=1`.
4. Record `doas rcctl ls started`. This is what the exit trap restores.
5. Choose the order. `master` leads only when every app that was started answers
   `/up` and the last `resource_guard` tick shows `mem_avail` at or above
   `VPS_DEPLOY_MASTER_MIN_AVAIL` (10). Otherwise: brgen, amber, bsdports, master.
6. For each target: wait until every running app answers `/up` (no CI, bundle or
   precompile on top of a Falcon boot); disk and load preflight; CI and sync;
   migrate; precompile (again after settling); restart; `/up`; stylesheet;
   solid_queue proof; restore anything shed, one service at a time, each waiting for
   its `/up`; the loopback checks; the flow journeys for that app only
   (`FLOW_APP=<app>`, HTTP only, one pass or fail line per flow).
7. On any failure the exit trap of the top-level run restores every service from
   the step 4 list that is not running, in serving order (brgen, amber, bsdports,
   master, then the rest), one at a time, each waiting up to
   `VPS_DEPLOY_RESTORE_WAIT` (240) seconds for `/up`. Each line says whether the
   deploy stopped it, `resource_guard` shed it, or it went down for another reason.
   The exit status stays the failure's, and the trap names the stage.

Recovery by hand, one app at a time, waiting for each port before the next. Falcon
needs 30 to 40 seconds under load, and two booting together is how the apps got
shed. Use `restart`, not `start`: `rc.d/master` runs its relayd restart, TTS warmup
and deploy-flag removal only on restart.

```zsh
doas rcctl restart brgen
until curl -fsS http://127.0.0.1:38182/up >/dev/null; do sleep 3; done
doas rcctl restart amber
until curl -fsS http://127.0.0.1:61352/up >/dev/null; do sleep 3; done
doas rcctl restart bsdports
until curl -fsS http://127.0.0.1:47312/up >/dev/null; do sleep 3; done
doas rcctl restart master
until curl -fsS http://127.0.0.1:53187/up >/dev/null; do sleep 3; done
OPENBSD/bin/canary --local        # ports, rcctl, every public route, then each flow journey
```

`rcctl restart master` may print `kill: <pid>: No such process`. That was rc.subr's
own wait-for-start timer, not a stale pid (the service has no pidfile); the rc.d now
silences that one signal. The stop path exits 0 when the process is already gone,
kills the process group if one is left, and `rc_post` fails the stop if `:53187` is
still held, so a start never races a survivor. The ports above are the ones in `RAILS/apps.yml`; read them there if they change.

To deploy an exact commit, not the tip: `VPS_DEPLOY_SHA=<sha> zsh OPENBSD/bin/vps-deploy all`
on the box, or push it and use `bin/operator vps deploy all --remote` from a clean
worktree at that commit. A stale `/home/dev/.pub4-vps-deploy.lock` is reaped by the next run
when its pid is gone; every exit, including a halted `all`, releases it.

## Deploy-all disambiguation

Four scripts read as “do everything”, and they do four different things. Pick
deliberately:

| Script | CI | Scope | When |
|--------|----|-------|------|
| `zsh OPENBSD/bin/vps_ci_all.sh` | **Yes** — serial `vps_ci.sh` per app | brgen, amber, bsdports | Normal code change; tests must pass |
| `I_UNDERSTAND_FAST_DEPLOY=1 zsh OPENBSD/bin/vps_production_push.sh` | **No** — `SKIP_CI=1 SKIP_RUNTIME_CHECK=1 bin/vps-deploy all`; only the post-restart checks run, and the runtime skip requires that exact acknowledgement. | master + every app, in vps-deploy's order; `DEMO_SEED_ON_DEPLOY=1` adds brgen's demo seed | Fast hotfix; skips test check |
| `zsh OPENBSD/bin/deploy_all.sh` | **No** | Runs from a workstation: syncs pub4 to vm23 and runs `OPERATOR.sh`, so it reapplies `/etc`, relayd and the services, not just app code. `--per-app` also runs each `RAILS/<app>/<app>.sh` | The box's config has drifted or a fresh install needs redoing — not for shipping a code change |
| `ksh OPENBSD/bin/start_all_apps.sh` as `dev` | **No** — recovery only | Calls the fixed `pub4-admin start-all-apps` broker verb; checks all services and pins them against `resource_guard.sh` shedding | Recovery after a deliberate decision to keep every app running despite load |

`vps_production_push.sh` is the footgun under pressure: it restarts production
without running CI. Use `vps_ci_all.sh` unless you explicitly need the fast path
and accept the risk. `deploy_all.sh` is the wider footgun — it rewrites box
config on the way past, so reach for it only when that is the thing you want.

## Occasional operator tools

Nothing in the repo calls these — they are run by hand, which is exactly why
they need to be listed somewhere. An orphan script is indistinguishable from a
dead one until it is written down.

| Script | Run from | What it is for |
|--------|----------|----------------|
| `ruby OPENBSD/sync.rb` (as `doas ruby`) | vm23 | Mirror live `/etc` config **back into** `OPENBSD/`, with secret redaction. The repo→live direction is well travelled; this is the return leg, and skipping it is how `relayd.conf` drifted for weeks (see the warning under *OpenBSD deploy*). |
| `ruby OPENBSD/ptr_openbsd_amsterdam.rb --ipv4 … --hostname …` | anywhere | Set the PTR record via openbsd.amsterdam's `ptr4`/`ptr6` endpoints; `--ipv6` sets the v6 record. Needed only if the VM's IP changes. It prints the request as a dry run unless `APPLY_PTR=1` is set. |
| `zsh OPENBSD/bin/vps_run_remote.sh` | workstation | Bootstrap a *fresh* VM: copies `vps_install_all.sh` up through the server4 hypervisor jump and runs it. Not for routine deploys — use `vps-deploy`. |
| `ksh OPENBSD/bin/manual_master_deploy.ksh` | vm23, under tmux | Fallback when `vps_deploy_master.sh` stalls. It pkills the stuck deploy and its precompile, then precompiles MASTER web, runs the `master_web_assets` check, restarts master and relayd, and probes `/up`. Output goes to `/tmp/master_manual.log`, not the terminal — `tail -f` it. |
| `sh OPENBSD/bin/amber_queue_sweep.sh [APP]` | vm23 | **Deletes** finished jobs, orphaned executions, unfinished Turbo broadcasts and duplicate media jobs from a Solid Queue backlog (amber by default); drain-jobs.sh runs due jobs, this removes what should never run. Named in `RAILS/amber/README.md` |
| `zsh OPENBSD/bin/deploy-diff.sh` | workstation | Read-only: runs `config_drift_check.rb --remote`, then diffs `relayd.conf` (which the check excludes) and prints `rcctl check`. It changes nothing in either direction; `sync.rb` above is what pulls the live side back into the repo. |
| `sh OPENBSD/bin/amber_queue_sweep.sh [APP]` | vm23 | Delete a stale Solid Queue backlog (finished jobs, orphaned executions, unfinished Turbo broadcasts, duplicate media jobs) with sqlite3, no Rails boot. `drain-jobs.sh` runs due jobs hourly; this removes what should never run. |

## Self-healing cron (vm23)

Tracked mirror: `OPENBSD/etc/crontab.vm23` (installed idempotently by
`OPERATOR.sh`). Hand-edits on vm23 should be copied back to that file.

| Job | Schedule | Log / signal |
|-----|----------|--------------|
| `relayd-watchdog` | `*/5 * * * *` | syslog tag `relayd-watchdog` — restarts relayd when unhealthy or backend table stale. It does **not** heal `doas.conf`: that step ran `validate_doas.ksh` from a dev-owned checkout as root every five minutes and was removed, with the reason in the script's own header |
| `config-drift-check` | `*/15 * * * *` | `/var/log/config_drift.log` — relayd Host routes vs acme SANs vs NSD zones vs DNSSEC paths |
| `resource_guard.sh` | `*/5 * * * *` | sheds bsdports then amber under sustained pressure; `/var/log/resource_guard_history.log` |
| `uptime-check.sh` | `*/5 * * * *` | `/var/log/uptime-check.log`, with `ALLOW_BSDPORTS_DOWN=1` |
| `pub4-alert watch` | `*/15 * * * *` | `/var/log/pub4-alerts.log`, shown by `vps-state` — disk 90%, swap 92%, any `rcctl ls failed` service except `brgen_jobs`, no `dr-pull` report in 48 h. Each key alerts once per six hours |
| `drain-jobs.sh` | `5 * * * *` | `/var/log/drain-jobs.log` |
| `core-reclaim.sh` | `40 * * * *` | `/var/log/core-reclaim.log` — returns a core app's grown resident set |
| `keep-warm.sh` | `*/10 * * * *` | `/var/log/keep-warm.log` — brgen and amber only |
| `prune-guests.sh` | `20 4 * * *` | `/var/log/prune-guests.log` |
| `renew-certs.sh` | `0 2 * * 1` | `/var/log/cert-renewal.log` |
| `vps_weekly_integrity.sh` | `30 3 * * 0` | **tracked and never installed** — absent from root's live crontab and from `/usr/local/bin`, measured 2026-09-12. See TODO 1060. |

Eleven rows because `etc/crontab.vm23` schedules eleven jobs. This table listed four
for long enough that six self-healing jobs existed only in the file nobody
reads next to the one they do.

A healer that works hides the fault that makes it run. `relayd-watchdog` stamps
each restart in `/var/db/pub4/relayd-watchdog.restarts` and raises a
`relayd-restarts` alert on the third inside an hour; `uptime-check.sh` raises
`uptime-down` when an endpoint is down for three ticks running (fifteen minutes,
longer than a deploy restart); `pub4-alert show` and `vps-state` print the
record. The dr-pull job reports to the box by writing `~dev/.dr_pull_ok` after
each pull, which is what the stale-backup alert reads.

`nsd-resign` is **not** in root crontab — it runs from `etc/daily.local` (daily
DNSSEC re-sign + backup pass). Failures surface in syslog (`daily.local` tag)
and `/var/log/nsd-resign` if present.

## External uptime check

Off-box detection (no alerting pipeline yet):

```sh
sh OPENBSD/bin/uptime-check.sh
```

A wrapper with no URL list of its own: it execs `health_check.rb --public-only
--all-ready-apps`, which derives the fleet from `RAILS/apps.yml` and the deploy
inventory. A second list here is how the paragraph came to name four hosts after
the wrapper had stopped naming any. Runs from a laptop or vm23, and `--public-only`
means it asks the internet and checks nothing on the box — the service, certificate
and relayd checks are the same script without that flag.

## Post-deploy smoke (one page)

After `vps-deploy` / rcctl restarts, run:

```sh
# on vm23 — local ports + public + brgen HTML checks (no splash, nav tablist)
sh OPENBSD/bin/deploy-smoke.sh

# laptop / public only
sh OPENBSD/bin/deploy-smoke.sh --public

# policy: amber optional on 1GB hosts
ALLOW_AMBER_DOWN=1 sh OPENBSD/bin/deploy-smoke.sh
```

Checks `rcctl` (when present), localhost `/up` ports (master 53187, brgen 38182,
amber 61352), public HTTPS, free-RAM warning, and brgen homepage regressions.
vm23 has 1 GB, so three apps leave little headroom. Restart order when recovering: **master → brgen → amber → relayd**.

## vps_console.exp modes

Recovery-only — requires `I_UNDERSTAND_CONSOLE_RISK=1`. One script, the mode
as its first argument: `expect -f OPENBSD/bin/vps_console.exp <mode>`.

| Mode | Purpose |
|------|---------|
| `short [cmd]` | One console command (default `uptime`); 15s timeout |
| `status` | Tail install log + `rcctl check` master/brgen/amber/bsdports |
| `probe` | Raw console banner/login probe (debug connectivity) |
| `fix_key` | Install vm23 `authorized_keys` + flush pf `bruteforce` |
| `start_install` | `nohup /tmp/vps_on_vm_install.sh` from console |
| `poll_install` | Tail on-vm install log + process/rcctl snapshot |
| `install` | Full MASTER bundle + per-app deploy from console (long) |
| `sync_and_install` | Base64 tarball sync to `/home/dev/pub4` then on-vm install |
| `drop_install` | Base64-embed `vps_on_vm_install.sh` only; it execs `vps_install_all.sh`, so the tree must already be at `/home/dev/pub4` |

Laptop SSH to vm23: `source OPENBSD/lib/ssh_vm23.sh` or `zsh
OPENBSD/lib/ssh_vm23.sh <cmd>`. Long deploys: `vm23_tmux deploy 'doas zsh
OPENBSD/OPERATOR.sh …'`.

## Rails deploy

Rehearse first, from the checkout you are about to ship: `ruby OPENBSD/bin/rehearse`
runs in seconds and covers what the box's CI would otherwise tell you forty
minutes in. It runs the CI lints and the dialect check, and the static contracts
that tie the deploy scripts to the tree: every repo path a script names exists,
the CI mirror carries what the tools require, the copy-tree layout matches the
Gemfiles, and no test file leaves a test call outside its class. It does not boot
Rails; `rails_test` on the box is where the remaining failures live.

```zsh
cd /home/dev/pub4 && git pull --ff-only
zsh OPENBSD/bin/vps-deploy brgen       # canonical serial deploy
zsh OPENBSD/bin/vps-deploy amber       # or: all
ruby OPENBSD/checks/health_check.rb --public --all-ready-apps
```

Use only `zsh OPENBSD/bin/vps-deploy <app|all>` for production deploys (runs as root; re-exec via doas from dev).
The compatibility `zsh RAILS/deploy.sh` delegates to it and refuses UID 0.
The individual `RAILS/<app>/<app>.sh` entrypoints also refuse root because they
source code from the dev-writable checkout. Do not run them with `doas`.
The supervisor handles asset precompile before restart.

```zsh
cd /home/dev/pub4 && git gc --quiet && git count-objects -v
```

## Checks

```zsh
OPENBSD/bin/check                         # local static deploy checks
OPENBSD/bin/check-vps                     # vm23/live health checks; skips off-VPS
ruby OPENBSD/checks/integrity_check.rb              # full chain: production, phantom_fk, frontend, relayd, domain_align, crawl
ruby MASTER/tools/rails/crawl_probe.rb           # HTTP manifest + apps.yml ↔ deploy_inventory.json sync
MASTER_CRAWL_BROWSER=1 ruby MASTER/tools/rails/crawl_browser.rb   # Ferrum element crawl (VPS)
cd MASTER && bundle exec ruby bin/probe integrity deploy crawl crawl-browser
```

`bin/probe deploy` and `bin/probe integrity` alias the integrity check. On macOS,
`crawl-browser` skips unless `MASTER_CRAWL_BROWSER=1` or
`PROBE_FORCE_BROWSER=1`. Matrix and blockers: `RAILS/README.md` ("Production
readiness" section).

## Secrets

`/etc/master.env`, `/etc/<app>.env`. Never commit. Operator keys stay in the
workstation environment.

## Recovery

Load shedding: `ksh OPENBSD/bin/resource_guard.sh` as `dev`; the wrapper refuses root and delegates to the installed root-owned runner. Full stack: `ksh OPENBSD/bin/start_all_apps.sh` (as dev; only the fixed broker runs as root). Core health: `doas /usr/local/sbin/pub4-admin service check master` (repeat for brgen/relayd)
pf`.

SSH lockout only: `ssh server4`, then `vmctl console vm23` (manual — not
agent-automated). pf lockout from console: `doas pfctl -t bruteforce -T flush`.

Any file changed on the VPS under `OPENBSD/` must be copied back to git and
committed.

## A daemon that answers ok and does nothing

`rcctl check` asks whether a process exists. Three things on vm23 were dead
behind a green answer, found 2026-09-11, and they are one class rather than
three incidents: the evidence of work and the evidence of life were the same
signal, so silence meant both.

**pflogd, suspended for 34 days.** `rcctl check pflogd` said ok; the process
title said `pflogd: [suspended]`. It had been handed a `/var/log/pflog` written
with a different snaplen than its own `-s 160`, and `pflogd(8)` is explicit
about what happens next: an invalid or incompatible file suspends logging until
a SIGHUP or SIGALRM. It retried on every 60-second flush and wrote
"Invalid/incompatible log file, move it away" into `/var/log/messages` each
time, which nothing reads. Packet filter logging was off from 8 August.

    doas pflogd -x -f /var/log/pflog        # integrity, without touching it
    doas mv /var/log/pflog /var/log/pflog.incompatible-$(date +%Y%m%d)
    doas rcctl restart pflogd
    ps -axo command | grep pflogd           # must read [running], not [suspended]

**brgen_jobs, failed.** The Solid Queue worker is not in `apps.yml`, so
`health_check.rb` — which walks the apps and the core services — could not see
it. `rcctl ls failed` names it. Nothing ran a background job for as long as it
was down.

**core-reclaim, inert since 30 August.** Its trigger was `rss_mb >= 320`, and
brgen resident reads 199M while its address space is 877M and swap sits at 76%.
The script's own header says RSS understates a swapped process; it then used
RSS as its only signal. So the reclaim never fired under exactly the pressure
it exists for, and the kernel did the work instead — `UVM: killed: out of swap`
21 times for brgen in one dmesg buffer, plus relayd once and three root shells.
It reads swap pressure as well as RSS now, and writes `/var/db/core_reclaim_seen`
on every run so "nothing to do" and "never ran" stop being the same silence.

`health_check.rb` asserts all three: the suspended title, `rcctl ls failed`, and
the heartbeat's age.

## Updates: syspatch, packages, release upgrades

There is no staging box (CLAUDE.md, "Refused, and why"), so staging an update
means recording the box's state and a way back before touching it. Observed on
vm23 on 2026-10-12: OpenBSD 7.8 GENERIC#54, `syspatch -c` lists 69 patches
(`002_xserver` to `070_wsdisplay`) and `/var/syspatch` holds only `78-001_syspatch`,
so none is applied. Among the 69 are services this box runs: `004_libssl` and
`060_libressl`, `005_smtpd`, `026_smtpd`, `038_smtpd`, `051_smtpd`, `013_httpd`,
`058_nsd`, `010_unbound`, `059_unbound`, `057_ldapd`, and kernel patches
(`040_elf`, `048_kernproc`, `049_ttyioctl`, `054_shmat`, `061_procargs`) that
take effect only after a reboot. `pkg_add -un` reports only `quirks`, so packages
(ruby 3.4.9p0, sqlite3 3.50.7p0, openssl 3.5.6v0, ffmpeg 6.1.3p0v1) are current
for the 7.8 package set. `/bsd.upgrade` and `/home/_sysupgrade` do not exist, so
no release upgrade is armed.

Patches are cumulative; `syspatch` applies all of them and cannot apply a subset.
The way back is `doas syspatch -r`, which reverts only the newest patch from
`/var/syspatch/<patch>/rollback.tgz`, so reverting a bad run is one patch at a
time and kernel patches need another reboot. Plan the window as a reboot.

Before the window:

1. `ruby OPENBSD/bin/dr-pull` on the Mac and `ruby OPENBSD/bin/dr-pull --drill`;
   a patched box is one failed boot from needing the pull.
2. `zsh OPENBSD/bin/deploy-diff.sh` and `ruby OPENBSD/bin/domain_watch.rb --tls`,
   saved, as the "before" for relayd, certificates and ports.
3. Note libvips: vm23 runs a locally built libvips (daily.local explains why
   `pkg_add -u` would replace it with a build that has no SVG loader); do not run
   `pkg_add -u` in the same window, and keep the console reachable.
4. Have the `server4` console session ready (`vmctl console vm23`, manual).

In the window: `ruby OPENBSD/bin/vps-admin updates apply` (`doas syspatch`), then
`doas reboot`. After a reboot the apps cold-boot together and starve each other on
one vCPU (the 2026-08-24 boot storm): start them one at a time, master and
`brgen_jobs` last, and wait for each to answer on its own port before the next.
Then `ruby OPENBSD/bin/domain_watch.rb --tls` against the saved "before". No
deploy is needed afterwards, because syspatch does not touch `/home`.

`vps-admin upgrade check` only reads the running release and the mirror. Do not
call `sysupgrade -n` a check: it downloads the sets and creates `/bsd.upgrade`,
which the bootloader runs at the next boot, whatever the reason for that boot.
Release upgrades go through `vps-admin upgrade stage` in a console-attended
window of their own, after 7.9 is out and the Ruby, Chromium and ffmpeg packages
exist for it.

## Repair playbooks

- Integrity failure: run `ruby OPENBSD/checks/integrity_check.rb` and fix the first
  failing check.
- App CI failure: run `zsh OPENBSD/bin/vps_ci.sh <app>` serially. If caches are
  root-owned, export the app `HOME` and `NPM_CONFIG_CACHE`.
- MASTER dead tap: precompile `RAILS/master` production assets, restart `master`,
  then verify `https://ai.brgen.no` after the primer tap.
- relayd/domain drift: run `MASTER/checks/runner.rb domain_alignment` and
  `OPENBSD/checks/deploy_smoke_check.rb` before restarting relayd.
- pf lockout: use the server4 console and flush the `bruteforce` table; do not
  keep reconnecting.
- Silent TTS: `checks.tts` on `https://ai.brgen.no/health` is the authority, and
  it already checks the deploy — `health_check.rb` fails on `checks.tts false`,
  `RAILS/master`'s health controller 503s the whole endpoint on it, and
  `bin/check-vps` runs both. On the source side `MASTER/checks/runner.rb
  production` runs `MasterTtsCheck`, which pins the worker, the supervisor's
  bundle isolation and `rc.d/master`'s `ensure_daemon!`, and probes for a host
  backend when `MASTER_TTS_REQUIRE_HOST_BACKEND=1`. It is a capability check
  (`MASTER/bin/tts-worker` executable *and* EventMachine built with SSL, or
  espeak at `/usr/bin/espeak` or `/usr/local/bin/espeak`), not socket liveness —
  the daemon socket is spun up per synthesis. So `checks.tts true` with a silent
  tap is a web-route or audio-graph problem, not a missing binary. Do not go
  hunting for an `edge-tts` CLI: `Speech.edge_tts_available?` never consults one
  — edge TTS is the `rb-edge-tts` gem, reached only through the worker.
  `OPERATOR.sh` `pkg_add`s espeak, which is the fallback path.

## Patch examples

A good operator patch updates every authority affected by a domain or port
change, lists exact checks, and reports host, commands, result, and intentional
skips. A bad patch changes one app script, says only "restarted stuff", or runs
the full installer from macOS.

## Post-change

- Run `ruby OPENBSD/checks/health_check.rb --public --all-ready-apps`.
- Copy any live `/etc` changes back into `OPENBSD/etc/`.
- Put a lasting reason in a comment beside the config or script it explains, a
  standing refusal in `OPENBSD/CLAUDE.md`, and operator-only work in
  `MASTER/data/operator_seams.yml`.

## Launch wipe (demo data -> cold start)

Written 2026-08-22 as the cherry-picked answer to the demo-content launch
blocker; a runbook on purpose, not a script — GUARD_EXPENSIVE_OPS exists
precisely so no bin/ file carries a fleet-wide delete. Run it BY HAND, per app,
on launch day:

1. `ruby OPENBSD/bin/dr-pull` from the Mac — a verified pre-wipe snapshot.
2. On vm23, stop the app and its optional job worker: `doas /usr/local/sbin/pub4-admin service stop <app>` and, if configured, `doas /usr/local/sbin/pub4-admin service stop <app>_jobs`.
3. Move the primary aside (never delete): `mv
   /home/<app>/app/storage/production.sqlite3{,.pre-launch}`.
4. As the app user: `bundle exec bin/rails db:prepare` — schema, no seeds.
   brgen demo seeds are the DEMO; a launch database starts empty. If a curated
   skeleton is wanted (cities, categories, admin), seed ONLY
   `db/seeds/launch.rb` — write it that week, review it that week.
5. Start the app with `doas /usr/local/sbin/pub4-admin service start <app>` and, if configured, start its job worker with `doas /usr/local/sbin/pub4-admin service start <app>_jobs`; then run the route-manifest probe.
6. The .pre-launch file stays until the first week survives; dr-pull keeps
   pulling nightly either way.

Not before the operator decides: which cities open, whether demo mode
(clearly-badged fictive content) is wanted instead of a wipe, and the
announcement noindex question. Those are product calls, not runbook steps.


## Source-level PF policy guard

Run `ruby OPENBSD/checks/pf_policy_check.rb` for the tracked `OPENBSD/etc/pf.conf` policy invariants, and `ruby OPENBSD/test/test_pf_policy_check.rb` for positive and negative fixtures. The guard checks that a default-deny rule precedes pass rules, inbound passes are scoped to `$ext_if`, and the explicit SSH exception precedes the quick `<bruteforce>` block. It rejects pass rules without explicit `$ext_if` scope, including protocol-specific passes such as `pass inet proto tcp all`. The only unscoped exception is the current explicit ICMP type allowlist (`echoreq`, `unreach`, `timex`), whose scope is retained as a deliberate tracked-policy exception.

This is a deliberately narrow policy check, not a replacement for OpenBSD's parser. Validate syntax on the target host with `pfctl -nf /etc/pf.conf` before applying a change. PF evaluates rules in order and the last matching pass/block rule decides the action unless `quick` terminates evaluation, so a terminal catch-all block is not a required policy invariant ([OpenBSD pf.conf(5)](https://man.openbsd.org/pf.conf)).
