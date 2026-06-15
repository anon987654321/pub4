# Production readiness — Rails family (pub4)

Dated pass/fail matrix. **No app is production-ready until VPS target-host checks pass.**

Last updated: **2026-06-15**

## Gate commands

```sh
# Local (Mac or dev checkout)
ruby DEPLOY/rails/check_production_gate.rb
cd MASTER && bin/smoke

# VPS (ruby34 / bundle34) — per app after git pull
cd /home/dev/pub4/DEPLOY/rails/<app>
bundle34 check
RAILS_ENV=production bundle34 exec rails db:prepare
bundle34 exec bin/ci
curl -fsS http://127.0.0.1:<port>/up
```

Ports: see `DEPLOY/rails/apps.yml`.

## Summary

| App | Local gate | bin/ci (local) | VPS /up | relayd route | Notes |
|-----|------------|----------------|---------|--------------|-------|
| brgen | pass | not run | pending | yes | Closest to ready; city graph + subapps |
| amber | pass | not run | pending | yes | Wardrobe core done |
| baibl | pass | not run | pending | yes | Wave 1 comparisons seeded |
| blognet | pass | not run | pending | yes | Primary host `blognet.no` |
| bsdports | pass | not run | pending | yes | FTS search live |
| hjerterom | pass | not run | pending | yes | Food-parcel core done |
| master (AI face) | smoke pending | n/a | pending | yes | `https://ai.brgen.no` — blocked until SSH/key |

**Local gate** = `check_production_gate.rb` (assume_ssl, hosts, Solid, ci.rb steps).

**VPS pending** = SSH key not yet on server4/vm23 (2026-06-15); external HTTPS times out.

## Open blockers (operator)

1. Mischa: install new SSH pubkey on hypervisor + vm23 (+ wingman1).
2. VMM console: `doas pfctl -t bruteforce -T flush` if direct SSH still blocked.
3. On VM: `git pull`, sync `relayd.conf` / `pf.conf` from repo, `doas rcctl restart relayd master`.
4. Verify `curl https://ai.brgen.no/up` and WebGL face in private window.
5. Run `bundle34 exec bin/ci` on each app on VPS; update this table with dates.

## Wave 1 (still open)

- AN201: full `rails generate authentication` + migrations (baselines copied only).
- Activity graph: mandatory `record_activity!` on all core actions.
- Engine deprecate: remove `install_an_stack.sh` copy path; bundle-only.
- AN106: VAPID keys in credentials + push wired on all apps.

## relayd alignment (2026-06-15)

Repo `DEPLOY/openbsd/etc/relayd.conf` and `openbsd.sh configure_relayd()` now agree:

- `interval 30` / `timeout 2000`
- All backends use `check http "/up" code 200`
- Backends: brgen, amber, master, bsdports, baibl, blognet, hjerterom

After deploy, confirm live `/etc/relayd.conf` matches:

```sh
doas relayd -n -f /etc/relayd.conf
grep 'check http' /etc/relayd.conf
```