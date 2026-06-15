# Production Readiness

Status as of 2026-06-15: static production gate passes locally (`check_production_gate.rb`). Apps remain not fully production-ready until Ruby 3.4 bundle/test/security/deploy smoke passes on the OpenBSD target.

Run the static gate before every deploy:

```sh
DEPLOY/rails/check_production_gate.rb
```

## Credential rotation (BU01)

Verified 2026-06-15: no `config/master.key` files are tracked in git (`git ls-files DEPLOY/rails/*/config/master.key` is empty). Encrypted credentials remain in `config/credentials.yml.enc` only.

Rotate before production cutover or after any suspected leak:

1. On a trusted workstation (not the VPS shell history), per app under `DEPLOY/rails/<app>/`:
   ```sh
   cd DEPLOY/rails/<app>
   rm -f config/master.key   # local only; never commit
   EDITOR=vim bin/rails credentials:edit
   ```
2. Store the new master key only on the VPS:
   ```sh
   doas install -o <app> -g <app> -m 0400 /dev/stdin /home/<app>/app/config/master.key
   ```
   Paste the key, then Ctrl-D. Repeat for each app.
3. Rotate shared secrets inside credentials (SMTP, API keys) in the same edit session.
4. Redeploy the app (`<app>.sh`) and verify `GET /up` returns 200.
5. Revoke old SMTP/API keys at the provider after traffic is healthy.

Apps requiring rotation: `brgen`, `amber`, `bsdports`, `baibl`, `blognet`, `hjerterom`.

## doas audit (M04)

`MASTER/data/rules.yml` sets `openbsd.privilege: doas`. Audited 2026-06-15:

| Command surface | Expected privilege | Current behavior | Status |
|---|---|---|---|
| `doas rcctl restart master` | doas | `RestartMaster` order and standing_orders use `doas rcctl restart master` | OK |
| `rcctl check master` | none (read-only) | `Open3.capture3("/usr/sbin/rcctl", "check", "master")` | OK |
| `/postpro`, `/repligen` tools | dev (no elevation) | `Open3.capture2e(RbConfig.ruby, script)` as `dev` via MASTER rc.d | OK — doas rules added in `DEPLOY/openbsd/etc/doas.conf` for explicit allow-list |
| `postpro_photo` in chat | dev subprocess | `Open3` to `MASTER/tools/postpro.rb` | OK |
| Deploy scripts `rcctl` | doas | `@shared_functions.sh` uses `${_PRIV}=doas` | OK |

No MASTER shell-outs invoke bare `sudo`. Privileged restarts must continue to use `doas`, not direct `rcctl` as dev.

## VPS deploy verification (M01–M07)

Run these on the OpenBSD VPS (`46.23.89.226`), not from a developer laptop.

| ID | Step | Command / artifact |
|---|---|---|
| M01 | Install MASTER rc.d | `doas sh /home/dev/pub4/DEPLOY/openbsd/scripts/verify_master_deploy.sh` (copies `DEPLOY/openbsd/etc/rc.d/master` → `/etc/rc.d/master`) |
| M02 | Validate `master.env` keys | Same script checks `/etc/master.env` against `DEPLOY/openbsd/etc/master.env.sample` |
| M03 | Enable MASTER at boot | `doas rcctl enable master` then `doas rcctl check master` |
| M04 | doas audit | See table above (landed 2026-06-15) |
| M05 | Backup uses openrsync | `DEPLOY/openbsd/backup_priv.sh` (landed 2026-06-15) |
| M06 | PTR record | `sh /home/dev/pub4/DEPLOY/openbsd/scripts/verify_ptr.sh` — set via **ptr4.openbsd.amsterdam** from VM if missing |
| M07 | sshd hardening | Merge `DEPLOY/openbsd/etc/ssh/sshd_config` → `/etc/ssh/sshd_config`; `doas rcctl restart sshd`; verify `PermitRootLogin no`, `PasswordAuthentication no`, `MaxAuthTries 3` |

One-pass after deploy:

```sh
ruby /home/dev/pub4/DEPLOY/health_check.rb
sh /home/dev/pub4/DEPLOY/openbsd/scripts/verify_master_deploy.sh
sh /home/dev/pub4/DEPLOY/openbsd/scripts/verify_ptr.sh
sh /home/dev/pub4/DEPLOY/openbsd/scripts/verify_nsd.sh
```

## VPS hygiene (CC01–CC13)

Tracked OpenBSD artifacts under `DEPLOY/openbsd/`:

| ID | Artifact | Purpose |
|---|---|---|
| CC01–CC02 | `scripts/vps_upgrade.sh` | `sysupgrade`, `syspatch`, `pkg_add -u`, `sysmerge` |
| CC03 | `etc/ssh/sshd_config` | PasswordAuthentication no, MaxAuthTries 3 |
| CC04 | `scripts/kill_orphan_chrome.sh` + `etc/daily.local` | Daily orphan browser cleanup |
| CC05–CC06 | `etc/daily.local` | Swap >50% and free RAM <100MB alerts |
| CC07 | `scripts/master_watchdog.sh` + `etc/daily.local` | Restart MASTER if unhealthy |
| CC08 | `scripts/pf_bruteforce_flush.sh` + `etc/weekly.local` | Weekly bruteforce table expiry |
| CC09 | `scripts/verify_ptr.sh` | rDNS for `46.23.89.226` → `brgen.no` |
| CC10 | `etc/litestream.yml` | SQLite replication for all apps |
| CC11–CC12 | `etc/relayd.conf` | `/up` health checks for MASTER + all Rails backends |
| CC13 | `scripts/verify_nsd.sh` | Authoritative DNS for `brgen.no` |

## Shared blockers

- Rotate Rails credentials per the procedure above before go-live.
- Run each app under Ruby 3.4 with its locked bundle installed; every Gemfile now declares `ruby "~> 3.4"`.
- TLS terminates at OpenBSD `relayd`. Rails production configs should keep `config.assume_ssl = true` and leave `config.force_ssl` disabled.
- Run `bin/rails db:prepare`, `bin/rails test`, `bin/brakeman`, and `bin/bundler-audit` per app.
- Deploy to the OpenBSD target and verify `/up`, TLS, host authorization, logs, database writes, background jobs, and service restart.

## Landed in this pass (2026-06-15)

- Root `.github/workflows/ci.yml` runs `check_production_gate.rb`, `verify_deploy_identity.rb`, `check_ports.sh`, and per-app `bin/ci`.
- `check_production_gate.rb` enforces `assume_ssl = true` and rejects active `force_ssl` (BR22).
- `brgen` uses `Brgen::ProductionHosts.allowed` — explicit hosts from `domains.yml` and all city vertical subdomains (BU04/BU08).
- OpenBSD templates: `newsyslog.conf.d/rails`, `litestream.yml`, hardened `ssh/sshd_config`, `doas.conf` (postpro/repligen), `relayd.conf` `/up` checks, `daily.local` backup cron.
- `rcctl_ensure_service` in deploy scripts for idempotent enable/restart/start (BW02).
- `DEPLOY/health_check.rb` one-pass VPS verification (CC15).
- `openbsd.sh` idempotency notes and `STATE_FILE` tracking (CC14).

- `check_production_gate.rb` parses `apps.yml` on Ruby 2.6+ and passes for all six apps.
- `baibl`, `bsdports`, and `hjerterom` use `solid_cable` in production (no Redis dependency).
- Custom `HealthController` checks database, Solid Cache, and Solid Queue on `GET /up`.
- SMTP settings wired in all six `production.rb` files (credentials + `SMTP_ADDRESS`/`SMTP_PORT` env).
- `recurring.yml` added for `bsdports`, `baibl`, and `hjerterom`; extended for `blognet`.
- `amber` hosts include `www.amber.brgen.no`.
- Marketplace listings use FTS5 + `Shared::LiveSearch` (migration `20260615000100_create_marketplace_listings_fts`).
- Frontend baseline installed (`stimulus_components.js`, shared concerns) across all apps.
- `color-scheme` meta added to all app layouts.

## brgen

Closer to production than the subapps: routes and namespaced controllers are present, SSL and host authorization are configured, and the deploy script follows the tracked-tree model.

Remaining checks:

- Verify on Ruby 3.4; local host Ruby 3.3.8 cannot run the Gemfile.
- Rotate credentials.
- Smoke test all subdomain surfaces: `tv`, `dating`, `playlist`, `takeaway`, and marketplace aliases.
- Exercise marketplace cart/order, messaging, voting, reactions, and TV live-stream flows.

## amber

Not production-ready yet.

Fixed in this pass:

- Production proxy SSL trust, host authorization, and mailer host now target `amber.brgen.no`.

Remaining checks:

- Install the Rails 8 bundle and run the app test/lint/security suite.
- Rotate credentials.
- Verify wardrobe upload, Active Storage variants, AI endpoints, declutter flows, and visitor/public access boundaries.

## bsdports

Not production-ready yet.

Fixed in this pass:

- Production proxy SSL trust, host authorization, mailer host, Solid Cache, and Solid Queue are configured for `bsdports.org`.

Remaining checks:

- Install the Rails 8 bundle and run the app test/lint/security suite.
- Rotate credentials.
- Verify ports import/search, watch/unwatch, comments, Solid Queue, and `/up` behind relayd.
