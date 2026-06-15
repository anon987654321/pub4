# DEPLOY

OpenBSD production scripts for pub4.

## Layout

```
DEPLOY/
  openbsd/     pf, relayd, nsd, acme, rc.d, openbsd.sh
  rails/       six Rails 8 apps + shared engine (see apps.yml)
  dilla/       audio lab
  bp/          static business-plan sites
  postpro/     libvips image pipeline
  sh/          cross-cutting shell helpers
  quarantine/  inert malware samples (text only)
```

## OpenBSD

Run from tmux — rapid SSH reconnects trip pf bruteforce rules (see openbsd/README.md + unban_pf.sh for host console + `pfctl -t bruteforce -T flush` via vmctl).

```zsh
cd ~/pub4/DEPLOY/openbsd
tmux new-session -d -s deploy "doas zsh openbsd.sh 2>&1 | tee /tmp/deploy.log"
tmux attach -t deploy
```

Config-only sync (backs up `/etc` first):

```zsh
doas zsh ~/pub4/DEPLOY/openbsd/openbsd.sh --sync-configs
```

Resume interrupted full deploy: `doas zsh openbsd.sh --resume`

## Rails

Canonical inventory: **`DEPLOY/rails/apps.yml`** (domains, ports, feature status).

| App | Script | Domain |
|-----|--------|--------|
| brgen | `rails/brgen/brgen.sh` | brgen.no |
| amber | `rails/amber/amber.sh` | amber.brgen.no |
| bsdports | `rails/bsdports/bsdports.sh` | bsdports.org |
| baibl | `rails/baibl/baibl.sh` | baibl.no |
| blognet | `rails/blognet/blognet.sh` | blognet |
| hjerterom | `rails/hjerterom/hjerterom.sh` | hjerterom.no |

Each script: copy tracked tree → `bundle install` → migrate → rc.d → relayd backend → `/up` smoke.

Shared engine: `DEPLOY/rails/shared` (`pub4-shared` gem path in each Gemfile).

## Checks

```zsh
ruby DEPLOY/rails/check_production_gate.rb   # local/static gates
bin/probe repo                                # repo-level probe
bin/probe openbsd                             # on VPS: rcctl + health
```