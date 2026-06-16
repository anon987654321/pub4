# Production readiness — Rails family (pub4)

Dated pass/fail matrix. **VPS target-host `/up` checks passed 2026-06-16.**

Last updated: **2026-06-16**

## Gate commands

```sh
# Local (Mac or dev checkout)
ruby DEPLOY/rails/check_production_gate.rb
cd MASTER && bin/smoke   # requires Ruby 3.4+; use VPS for authoritative smoke

# VPS (ruby34 / bundle34) — per app after git pull
cd /home/dev/pub4/DEPLOY/rails/<app>
bundle34 check
RAILS_ENV=production bundle34 exec rails db:prepare
bundle34 exec bin/ci
curl -fsS http://127.0.0.1:<port>/up

# VPS health sweep
ruby34 /home/dev/pub4/DEPLOY/openbsd/health_check.rb
```

Ports: see `DEPLOY/rails/apps.yml`.

## Summary

| App | Local gate | VPS smoke | VPS /up | HTTPS route | Notes |
|-----|------------|-----------|---------|-------------|-------|
| brgen | pass | deploy ok | 200 | `https://brgen.no` | seed skipped (faker not in prod bundle) |
| amber | pass | deploy ok | 200 | `https://amber.brgen.no` | seed skipped (faker) |
| baibl | pass | deploy ok | 200 | `https://baibl.brgen.no` | apex `baibl.no` blocked — no public DNS |
| blognet | pass | deploy ok | 200 | `https://blognet.brgen.no` | apex `blognet.no` blocked — no public DNS |
| bsdports | pass | deploy ok | 200 | `https://bsdports.org` | |
| hjerterom | pass | deploy ok | 200 | `https://hjerterom.brgen.no` | apex `hjerterom.no` blocked — no public DNS |
| master (AI face) | n/a | smoke pass | 200 | `https://ai.brgen.no` | `bin/smoke` clean on VPS 2026-06-16 |

**Local gate** = `check_production_gate.rb` (assume_ssl, hosts, Solid, ci.rb steps).

**Deploy path** = `ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226` → `git pull` → `SKIP_MASTER_SCAN=1 zsh DEPLOY/sh/vps_on_vm_install.sh`.

## Open blockers (operator)

1. **Apex DNS**: `baibl.no`, `blognet.no`, `hjerterom.no` return NXDOMAIN in public DNS — acme cannot issue apex certs. Use `*.brgen.no` subdomains until registrar NS/A records point at `ns.brgen.no` / `46.23.89.226`.
2. **bin/ci per app**: not run on VPS this pass (1GB VM, long runtime). Run when CPU headroom allows.
3. **db:seed**: brgen/amber seeds need `faker` in production bundle or guarded `require` in `db/seeds.rb`.
4. **PTR**: M06 — set via ptr4.openbsd.amsterdam from inside VM.
5. **pf.conf sync**: fixed `to $ext_if` → `to $brgen_ip` (line 17 syntax error blocked `--sync-configs`).

## Wave 1 (repo runtime — 2026-06-16 VPS verify)

- [x] AN201: `Shared::Authentication` in engine; 6 apps alias via thin concern.
- [x] Activity: `tracks_activity` macro + `Shared::ActivityEventRecorder`; brgen core models wired.
- [x] Engine: `install_an_stack.sh` no-op; bundle-only.
- [x] AN106: `Shared::Vapid` + initializer stubs (push keys in `/etc/master.env` when ready).
- [ ] VPS: `bundle34 exec bin/ci` per app; engine guest migration if pending.

## relayd alignment (2026-06-16 live)

Confirmed on vm23:

```sh
doas relayd -n -f /etc/relayd.conf   # configuration OK
grep 'check http' /etc/relayd.conf   # all backends /up code 200
```

HTTPS smoke (2026-06-16): all seven public endpoints returned HTTP 200.