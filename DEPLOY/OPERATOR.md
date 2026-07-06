# Operator

Production runbook for pub4. Read `MASTER/QUICKSTART.md` for the agent runtime; this file covers the VPS and deploy surface.

## Repo layout

Only `MASTER/` and `DEPLOY/` at the repo root, plus dotfolders. Canonical inventories: `DEPLOY/rails/apps.yml`, `DEPLOY/master.json`.

## SSH

One session at a time. Rapid reconnects trip pf bruteforce.

| Target | Command |
|--------|---------|
| VM (apps) | `ssh -i ~/.ssh/id_ed25519_brgen dev@46.23.89.226` or `ssh brgen` |
| VMM host | `ssh -p 31415 -i ~/.ssh/id_ed25519_brgen dev@server4.openbsd.amsterdam` |
| Console | `vmctl console vm23` then `doas pfctl -t bruteforce -T flush` |

Full aliases and GitHub keys: `DEPLOY/openbsd/SSH_ACCESS.md`. Network table: `DEPLOY/openbsd/README.md`.

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
| amber | `https://amberapp.com` |
| bsdports | `https://bsdports.org` |

The brgen verticals (marketplace/dating/playlist/takeaway/tv/messenger + `maps`) are one Rails
app served under subdomains via `<brgen>`; relayd already routes them all (`etc/relayd.conf`).

`amberapp.com` is amber's intended public apex, but the committed stack still serves amber at
`amber.brgen.no` (relayd, `etc/acme-client.conf`, `openbsd.sh` ALL_DOMAINS, `master.json`,
`rails/apps.yml`). Switching to `amberapp.com` is a one-time operator step — see `RELEASE.md` —
and requires `amberapp.com` to delegate DNS to the VPS nsd (as `bsdports.org` does) before the
next `openbsd.sh` run, or acme cert issuance for it will fail.

Baibl, blognet, and hjerterom remain wired at `*.brgen.no` but are outside this release's public
launch set. City vanity apex domains (`oshlo.no`, `lsangeles.com`, …) need stage-1 certs from `openbsd.sh`.

TLS terminates at relayd. Rails sets `config.assume_ssl = true`; do not enable `force_ssl`.

## OpenBSD deploy

Always use tmux.

```zsh
cd ~/pub4/DEPLOY/openbsd
tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

| Flag | Use |
|------|-----|
| `--sync-configs` | Mirror `etc/` to `/etc`, restart services |

Stage 1: NSD, DNSSEC, acme certs, httpd ACME, pf. Stage 2: Rails trees, relayd SNI, smtpd, rc.d, health check.

After `MASTER/web/` edits: `doas rcctl restart master`. Falcon does not hot-reload.

## Rails deploy

```zsh
cd /home/dev/pub4 && git pull --ff-only
zsh DEPLOY/openbsd/sh/vps_ci.sh <app>          # one app, mutex-gated
SKIP_MASTER_SCAN=1 zsh DEPLOY/openbsd/sh/vps_on_vm_install.sh   # full stack
doas rcctl restart relayd              # after route/table changes
ruby34 DEPLOY/openbsd/health_check.rb --public --all-ready-apps
```

Per-app script: `doas zsh DEPLOY/rails/<app>/<app>.sh`. New Propshaft assets need `rails assets:precompile` before restart.

Ruby on VPS: `ruby34`, `bundle34`. Never parallel `bin/ci` across SSH sessions.

## Gates

```zsh
ruby DEPLOY/integrity_gate.rb              # full chain: production, phantom_fk, frontend, relayd, domain_align, crawl
ruby DEPLOY/rails/crawl_probe.rb           # HTTP manifest + apps.yml ↔ master.json sync
MASTER_CRAWL_BROWSER=1 ruby DEPLOY/rails/crawl_browser.rb   # Ferrum element crawl (VPS)
cd MASTER && bundle exec ruby bin/probe integrity deploy crawl crawl-browser
```

`bin/probe deploy` and `bin/probe integrity` alias the integrity gate. On macOS, `crawl-browser` skips unless `MASTER_CRAWL_BROWSER=1` or `PROBE_FORCE_BROWSER=1`. Matrix and blockers: `DEPLOY/rails/PRODUCTION_READINESS.md`.

## Secrets

`/etc/master.env`, `/etc/<app>.env`. Never commit. Operator keys stay in the workstation environment.

## Recovery

Load shedding: `doas ksh DEPLOY/openbsd/resource_guard.sh`. Full stack: `doas ksh DEPLOY/openbsd/start_all_apps.sh`. Core health: `doas rcctl check master brgen`.

Any file changed on the VPS under `DEPLOY/openbsd/` must be copied back to git and committed.