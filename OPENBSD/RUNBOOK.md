# Operator

Production runbook for pub4. Read `START_HERE.md` and this file before live work. Read
`MASTER/START_HERE.md` for the agent runtime; this file covers the VPS and deploy surface,
the agent contract, and live-operation safety in one place.

## Repo layout

`MASTER/`, `RAILS/`, `OPENBSD/`, `OPENBSD/` at the repo root, plus dotfolders. Canonical
inventories: `RAILS/apps.yml`, `OPENBSD/deploy_inventory.json`. Deploy gates (`integrity_gate.rb`,
`verify_deploy_identity.rb`, `deploy_inventory.json`) and recovery pens (`archive/`, `quarantine/`) live
at `OPENBSD/` top level.

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

Runtime contract: TLS terminates at relayd; apps listen on loopback-only ports; Rails uses
SQLite plus Solid Queue/Cache; secrets live in `/etc/*.env`; source of truth on the VPS is
`/home/dev/pub4`; long deploys run under tmux.

Gate flow — local: `OPENBSD/bin/check` → `verify_deploy_identity` → Rails production/domain/
phantom/frontend gates → OpenBSD deploy smoke. Operator: `git pull --ff-only` on vm23 →
`vps_ci.sh <app>` → `OPERATOR.sh` or per-app deploy → `rcctl restart` affected services →
`health_check --public --all-ready-apps`.

## SSH

One session at a time. Rapid reconnects trip pf bruteforce.

| Target | Command |
|--------|---------|
| VM (apps) | `ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226` or `ssh brgen` |
| VMM host | `ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam` |
| Console | `vmctl console vm23` then `doas pfctl -t bruteforce -T flush` |

Full aliases and GitHub keys: `OPENBSD/SSH_ACCESS.md`. Network table: `OPENBSD/README.md`.

## Domains

| Service | URL |
|---------|-----|
| MASTER | `https://ai.brgen.no` |
| brgen | `https://brgen.no` |
| brgen · marketplace | `https://markedsplass.brgen.no` |
| brgen · dating | `https://dating.brgen.no` |
| brgen · playlist | `https://playlist.brgen.no` |
| brgen · takeaway | `https://takeaway.brgen.no` |
| brgen · tv | `https://tv.brgen.no` |
| brgen · messenger | `https://messenger.brgen.no` |
| amber | `https://amber.brgen.no` |
| bsdports | `https://bsdports.org` |

The brgen verticals (marketplace/dating/playlist/takeaway/tv/messenger + `maps`) are one Rails
app served under subdomains via `<brgen>`; relayd already routes them all (`etc/relayd.conf`).

### Bringing a city domain up

Seven city domains serve brgen, each scoped to its own city: `brgen.no`,
`oshlo.no`, `trndheim.no`, `stvanger.no`, `cardff.uk`, `edinbrgh.uk`,
`frankfrt.de`. Six more are registered, in `ALL_DOMAINS`, hold a zone that nsd
serves and an `acme-client.conf` block, and are waiting on one thing each:
`brmingham.uk`, `brssels.be`, `dnver.us`, `glasgw.uk`, `lverpool.uk`,
`mnchester.uk`. None of them has an NS record at its registrar, so nothing asks
our nameserver for them.

The order below is not a preference. Each step needs the one above it, and the
last step is the one that bites: relayd refuses to start when a `tls keypair`
names a certificate that is not on disk, so adding the keypair early takes down
every site relayd serves, not just the new one.

1. **Delegate at the registrar** — NS to `ns.hyp.net` and `ns.brgen.no`, matching
   `oshlo.no`. This is the only step that is not on this box.
2. **Confirm it resolves to us**, or acme cannot answer its own challenge:
   `ruby -rresolv -e 'puts Resolv.getaddress("glasgw.uk")'` → `46.23.89.226`.
3. **Issue the certificate.** The `domain` block already exists in
   `/etc/acme-client.conf`; `doas /usr/local/bin/renew-certs.sh` picks it up, or
   `doas acme-client -v glasgw.uk` for one.
4. **Check the certificate is on disk** before touching relayd:
   `doas ls -l /etc/ssl/glasgw.uk.fullchain.pem`.
5. **Add `tls keypair "glasgw.uk"`** to `etc/relayd.conf` beside the other city
   keypairs, then `doas relayd -n` and only then `doas rcctl reload relayd`.
6. **Verify**: `curl -sS -o /dev/null -w '%{http_code}' https://glasgw.uk/` is
   200, and the page title names the city.

The stack serves three Rails apps (brgen, amber, bsdports) plus MASTER. `baibl`,
`blognet` and `hjerterom` are retired; on 2026-08-12 their users, home directories
(1.6 GB between them), rc.d scripts, `/etc/*.env` files, login classes, certificate
symlinks and DNS zones were removed from vm23, and their vanity/megablog domains
(`baibl.no`, `blognet.no`, `hjerterom.no`, `foodielicio.us`,
`anti{casino,gambling,betting}blog.com`) with them. Databases are kept at
`/var/backups/pub4/{hjerterom,deleted-apps}-20260812`.

Note the date against the release-history line in `DECISIONS.md` that says baibl and
blognet were removed: that was written two months earlier and was true of the repo,
not of the box. `port_inventory` now scans the config files where that kind of
residue lives, so the next one cannot be half-done quietly.

Seven city apexes serve as of 2026-08-12 (`Brgen::DomainRegistry::LIVE_DOMAINS`);
the rest of `ENTRIES` is either NXDOMAIN at the registrar or parked at Domeneshop.

TLS terminates at relayd. Rails sets `config.assume_ssl = true`; do not enable `force_ssl`.

## Agent contract

Modes: local contributor (edit repo files, run local gates, do not SSH), VPS operator (one SSH
session, one CI/deploy operation at a time, tmux for long work), recovery (human-directed
console or resource guard only to restore access or health, then document the fix).

**Hard stops — AI agents must not autonomously:**

| Action | Why |
|--------|-----|
| `vmctl console/stop/start/reboot` on server4 | Serial console sessions have caused VM reboots and site outages |
| `pkill`/`kill` of `cu`, `vmctl`, or other VMM console sessions on server4 | Disrupts other operators and can wedge vm23 |
| `vps_console*.exp` / `vps_drop_install.exp` without human approval | Gated by `I_UNDERSTAND_CONSOLE_RISK=1`; recovery-only |
| Deploy, install, or `pkill` deploy workers from the serial console | Bypasses SSH safety, tmux, and load gates |
| Target vm27 or any non-vm23 VM | Wrong tenant; production is vm23 (`dev`) |
| `OPERATOR.sh --stage-1` without `I_UNDERSTAND_DNS_WIPE=1` | Destructive DNS wipe |
| Parallel SSH deploys, parallel `bin/ci`, or broad `rcctl restart` without a named target | 1 GiB VPS; contention causes outages |

When SSH to vm23 is required, use normal paths — but note which of them takes
`doas` and which must not:

| | |
|---|---|
| `doas zsh OPERATOR.sh` | root, it installs `/etc` |
| `zsh OPENBSD/bin/vps-deploy <app>` | **dev**; it escalates per step |
| `zsh OPENBSD/vps_ci.sh <app>` | **dev** |

Under `doas`, `vps-deploy` fails at its first step with `Host key verification
failed` — root has no github host key, and giving it one would hand root a way
to fetch and run code from the network. It now refuses that invocation and says
so; this line used to name all three after the word `doas`.

**Rules:**

- Run `MASTER/bin/pub4 status` before starting work; use `OPENBSD/RECIPES.md` for copy-paste paths.
- Treat `RAILS/apps.yml` and `OPENBSD/deploy_inventory.json` as inventories, not suggestions.
- Any `/etc` change made on vm23 must be copied back to `OPENBSD/etc/`.
- Use `ruby34` and `bundle34` on OpenBSD; `zsh OPENBSD/vps_ci.sh <app>` for per-app CI.
- Keep secrets in `/etc/*.env`; never commit them.
- Keep Rails `config.assume_ssl = true`; do not enable `force_ssl` behind relayd.
- Prefer local gates first (`OPENBSD/bin/check`) before any SSH.

**Agent dmesg (verbose file operations):** external agents (Grok CLI, Claude Code, Cursor) and
MASTER should log mutations in OpenBSD dmesg style — terse, lowercase, one fact per line,
path-first, e.g.:

```
write OPENBSD/etc/rc.d/brgen 412B +12/-3
read MASTER/lib/reach/base.rb sha256=a1b2c3… 2048B
run zsh OPENBSD/bin/check-openbsd exit=0
```

Name the path on every read/write/delete; show evidence on writes (diff stat or byte size); show
command + exit code for shell, not "deployed successfully." Silence on success is fine for bulk
gates; speak up for each mutated file. MASTER: `/dmesg` or `toggle dmesg` streams bus events.

**Reporting** — good deploy closeout: exact host/environment, commands run, gates passed/skipped/
failed, services restarted, remaining manual verification. Bad: "deployed" without host/command,
public health not checked, asset precompile skipped after web changes, route/cert changes
without relayd/acme/NSD context.

## Console automation gate

Recovery-only expect scripts refuse to run unless a human operator exports
`I_UNDERSTAND_CONSOLE_RISK=1` (same pattern as `I_UNDERSTAND_DNS_WIPE=1` for `OPERATOR.sh
--stage-1`).

## doas.conf

OpenBSD rejects `/etc/doas.conf` without a trailing newline — `doas` breaks for everyone.
`OPERATOR.sh` fixes the repo copy before install, validates `su dev -c 'doas id'`, and rolls
back on failure. Cron heal paths use `OPENBSD/validate_doas.ksh` with the same validation.

## Backups (Litestream)

`etc/litestream.yml` replicates each app's SQLite to `file:///var/backups/litestream/` on the
same VPS disk. That protects against app-level corruption, not disk loss or provider failure.
Accepted RPO for full-disk loss: last manual off-host backup or git pull + redeploy. Add an
off-host Litestream replica (sftp/s3) before treating backups as disaster-recovery grade.

## OpenBSD deploy

Always use tmux.

```zsh
cd ~/pub4
tmux new-session -d -s deploy "doas zsh OPENBSD/OPERATOR.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

Default installs `OPENBSD/{etc,usr,var}`, validates pf/relayd, and restarts services. Rare: `--first-install`, `--stage-1`, `--stage-2`.

After `MASTER/web/` edits: `doas rcctl restart master`. Falcon does not hot-reload.

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
straight repo→live copy would have taken **every** site on the box down. The
two files had quietly diverged since July precisely because nobody could sync
them. `OPENBSD/sync.rb` (see *Occasional operator tools*) is the return leg
that keeps this from building up.

Note also that relayd's `match response header set` **overwrites** whatever the
backend sent, so the edge value is the only `Permissions-Policy` any browser
sees, for every app. It has to be the union of what all backends need — a
`geolocation=()` there silently killed brgen's `#nearby` while the Rails
initializer said `(self)`.

## Deploy-all disambiguation

Two “deploy everything” paths on vm23 — pick deliberately:

| Script | CI | Scope | When |
|--------|----|-------|------|
| `zsh OPENBSD/vps_ci_all.sh` | **Yes** — serial `vps_ci.sh` per app | brgen, amber, bsdports | Normal code change; tests must pass |
| `zsh OPENBSD/vps_production_push.sh` | **No** — sets `SKIP_CI=1` | master + brgen + amber | Fast hotfix; skips test gate |

`vps_production_push.sh` is the footgun under pressure: it restarts production without running CI.
Use `vps_ci_all.sh` unless you explicitly need the fast path and accept the risk.

## Occasional operator tools

Nothing in the repo calls these — they are run by hand, which is exactly why
they need to be listed somewhere. An orphan script is indistinguishable from a
dead one until it is written down.

| Script | Run from | What it is for |
|--------|----------|----------------|
| `ruby OPENBSD/sync.rb` (as `doas ruby34`) | vm23 | Mirror live `/etc` config **back into** `OPENBSD/`, with secret redaction. The repo→live direction is well travelled; this is the return leg, and skipping it is how `relayd.conf` drifted for weeks (see the warning under *OpenBSD deploy*). |
| `ruby OPENBSD/ptr_openbsd_amsterdam.rb --ip … --hostname …` | anywhere | Set the PTR record via openbsd.amsterdam's `ptr4`/`ptr6` endpoints. Needed only if the VM's IP changes; `--apply` actually writes. |
| `zsh OPENBSD/vps_run_remote.sh` | workstation | Bootstrap a *fresh* VM: copies `vps_install_all.sh` up through the server4 hypervisor jump and runs it. Not for routine deploys — use `vps-deploy`. |

## Self-healing cron (vm23)

Tracked mirror: `OPENBSD/etc/crontab.vm23` (installed idempotently by `OPERATOR.sh`). Hand-edits
on vm23 should be copied back to that file.

| Job | Schedule | Log / signal |
|-----|----------|--------------|
| `relayd-watchdog` | `*/5 * * * *` | syslog tag `relayd-watchdog` — restarts relayd when unhealthy or backend table stale; heals `doas.conf` trailing newline |
| `config-drift-check` | `*/15 * * * *` | `/var/log/config_drift.log` — relayd Host routes vs acme SANs vs NSD zones vs DNSSEC paths |
| `resource_guard.sh` | `*/5 * * * *` | load shedding when vm23 is overloaded |
| `renew-certs.sh` | `0 2 * * 1` | `/var/log/cert-renewal.log` |

`nsd-resign` is **not** in root crontab — it runs from `etc/daily.local` (daily DNSSEC re-sign +
backup pass). Failures surface in syslog (`daily.local` tag) and `/var/log/nsd-resign` if present.

## External uptime check

Off-box detection (no alerting pipeline yet):

```sh
sh OPENBSD/bin/uptime-check.sh
```

Curls `https://ai.brgen.no/up`, `https://brgen.no/up`, `https://amber.brgen.no/up`,
`https://bsdports.org/up`. Runs from a laptop or vm23; exit 0 only when all four respond.
Complements `health_check.rb` (which also checks services, certs, relayd locally on vm23).

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
See `OPENBSD/data/debt.yml` → `multi_app_ram` for the three-app memory ceiling.
Restart order when recovering: **master → brgen → amber → relayd**.

## vps_console.exp modes

Recovery-only — requires `I_UNDERSTAND_CONSOLE_RISK=1`. Thin wrappers:
`vps_console_<mode>.exp`, `vps_drop_install.exp`.

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
| `drop_install` | Base64-embed `vps_on_vm_install.sh` only (no full tree) |

Laptop SSH to vm23: `source OPENBSD/lib/ssh_vm23.sh` or `zsh OPENBSD/lib/ssh_vm23.sh <cmd>`.
Long deploys: `vm23_tmux deploy 'doas zsh OPENBSD/OPERATOR.sh …'`.

## Rails deploy

```zsh
cd /home/dev/pub4 && git pull --ff-only
cd RAILS && doas zsh deploy.sh          # brgen (default)
doas zsh deploy.sh amber                     # or: all
ruby34 OPENBSD/health_check.rb --public --all-ready-apps
```

Per-app: `doas zsh RAILS/<app>/<app>.sh`. New Propshaft assets need `rails assets:precompile` before restart.

Ruby on VPS: `ruby34`, `bundle34`. Never parallel `bin/ci` across SSH sessions.

**`gc.auto` is 0 in `/home/dev/pub4`, and that is load-bearing.** git runs
`gc --auto` after a pull and detaches it, so on 2026-08-23 the pull that set up
a deploy spawned a `pack-objects` holding 266 MB, and on a 1 GB box the Rails
suite took SIGTERM after 18 tests and the seed step after that. The deploy log
said only `bin/rails aborted!` — the killer leaves nothing in it, so read
`vmstat` and `ps auxww | sort -k5 -rn` before believing any theory about the app.
Setting it to 0 means nothing packs the repo automatically; `/etc/weekly.local`
does it instead, as dev, and if that line is ever removed the checkout grows
loose objects forever.

Run it by hand before a deploy if a pull has just landed a lot:

```zsh
cd /home/dev/pub4 && git gc --quiet && git count-objects -v
```

## Gates

```zsh
OPENBSD/bin/check                         # local static deploy gates
OPENBSD/bin/check-vps                     # vm23/live health gates; skips off-VPS
ruby OPENBSD/integrity_gate.rb              # full chain: production, phantom_fk, frontend, relayd, domain_align, crawl
ruby RAILS/tools/crawl_probe.rb           # HTTP manifest + apps.yml ↔ deploy_inventory.json sync
MASTER_CRAWL_BROWSER=1 ruby RAILS/tools/crawl_browser.rb   # Ferrum element crawl (VPS)
cd MASTER && bundle exec ruby bin/probe integrity deploy crawl crawl-browser
```

`bin/probe deploy` and `bin/probe integrity` alias the integrity gate. On macOS, `crawl-browser` skips unless `MASTER_CRAWL_BROWSER=1` or `PROBE_FORCE_BROWSER=1`. Matrix and blockers: `RAILS/README.md` ("Production readiness" section).

## Secrets

`/etc/master.env`, `/etc/<app>.env`. Never commit. Operator keys stay in the workstation environment.

## Recovery

Load shedding: `doas ksh OPENBSD/resource_guard.sh`. Full stack: `doas ksh OPENBSD/start_all_apps.sh`. Core health: `doas rcctl check master brgen relayd pf`.

SSH lockout only: `ssh server4`, then `vmctl console vm23` (manual — not agent-automated). pf
lockout from console: `doas pfctl -t bruteforce -T flush`.

Any file changed on the VPS under `OPENBSD/` must be copied back to git and committed.

## Repair playbooks

- Integrity failure: run `ruby OPENBSD/integrity_gate.rb` and fix the first failing gate.
- App CI failure: run `zsh OPENBSD/vps_ci.sh <app>` serially. If caches are root-owned,
  export the app `HOME` and `NPM_CONFIG_CACHE`.
- MASTER dead tap: precompile `MASTER/web` production assets, restart `master`, then verify
  `https://ai.brgen.no` after the primer tap.
- relayd/domain drift: run `RAILS/gates/runner.rb domain_alignment` and
  `OPENBSD/deploy_smoke_gate.rb` before restarting relayd.
- pf lockout: use the server4 console and flush the `bruteforce` table; do not keep reconnecting.
- Silent TTS: verify `edge-tts` or `espeak` exists before debugging web routes.

## Patch examples

A good operator patch updates every authority affected by a domain or port change, lists exact
checks, and reports host, commands, result, and intentional skips. A bad patch changes one app
script, says only "restarted stuff", or runs the full installer from macOS.

## Post-change

- Run `ruby34 OPENBSD/health_check.rb --public --all-ready-apps`.
- Copy any live `/etc` changes back into `OPENBSD/etc/`.
- Record persistent lessons in `OPENBSD/data/debt.yml` or `OPENBSD/DECISIONS.md`.

## Launch wipe (demo data -> cold start)

Written 2026-08-22 as the cherry-picked answer to the demo-content launch
blocker; a runbook on purpose, not a script — GUARD_EXPENSIVE_OPS exists
precisely so no bin/ file carries a fleet-wide delete. Run it BY HAND, per
app, on launch day:

1. `ruby OPENBSD/bin/dr-pull` from the Mac — a verified pre-wipe snapshot.
2. On vm23, stop the app: `doas rcctl stop <app> <app>_jobs`.
3. Move the primary aside (never delete):
   `mv /home/<app>/app/storage/production.sqlite3{,.pre-launch}`.
4. As the app user: `bundle34 exec bin/rails db:prepare` — schema, no seeds.
   brgen demo seeds are the DEMO; a launch database starts empty. If a
   curated skeleton is wanted (cities, categories, admin), seed ONLY
   `db/seeds/launch.rb` — write it that week, review it that week.
5. `doas rcctl start <app> <app>_jobs`, then the route-manifest probe.
6. The .pre-launch file stays until the first week survives; dr-pull keeps
   pulling nightly either way.

Not before the operator decides: which cities open, whether demo mode
(clearly-badged fictive content) is wanted instead of a wipe, and the
announcement noindex question. Those are product calls, not runbook steps.
