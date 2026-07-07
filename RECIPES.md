# pub4 Recipes

Copy-paste operator paths. Read `DEPLOY/VPS_SAFETY.md` before live VPS work.

| I want to… | Run this | Expect | If it fails… |
|------------|----------|--------|--------------|
| See where I am | `bin/pub4 status` | mode, ruby, ports, next command | `DEPLOY/START_HERE.md` |
| Fast local contributor check | `DEPLOY/bin/check --profile=contributor` && `cd MASTER && bin/check --profile=contributor` | static gates ok | `DEPLOY/REPAIR_PLAYBOOKS.md` |
| Full local deploy gates | `DEPLOY/bin/check-full` | integrity clean off-VPS | first failing gate name in output |
| Check Rails source gates (no runtime) | `DEPLOY/bin/check-rails --profile=contributor` | walkthrough + schema ok | `DEPLOY/REPAIR_PLAYBOOKS.md` §integrity |
| Use correct Ruby locally | `bin/ruby -v` | 3.4.x | install ruby34 or rbenv with `.ruby-version` |
| After `git pull` on vm23 | `DEPLOY/bin/post-pull-checklist` | follow-up list | run `vps-deploy` per app |
| See dev vs deployed drift on VPS | `bin/pub4 vps state --remote` | SHA + service table | `zsh DEPLOY/bin/vps-deploy <app>` |
| Deploy one Rails app on VPS | `bin/pub4 vps deploy brgen --remote` | CI + restart + /up | `bin/pub4 vps logs brgen --remote` |
| Deploy MASTER web on VPS | `bin/pub4 vps deploy master --remote` | assets + restart | `DEPLOY/REPAIR_PLAYBOOKS.md` §tap |
| Full integrity on VPS | `ssh brgen 'cd /home/dev/pub4 && ruby34 DEPLOY/integrity_gate.rb'` | integrity clean | vps-state + redeploy apps |
| Public health on VPS | `ruby34 DEPLOY/openbsd/health_check.rb --public --all-ready-apps --json` | `"ok":true` | `doas rcctl check <app>` |
| Agent handoff snapshot | `cd MASTER && bin/handoff` | git + backlog + ports | — |

## Modes

- **Contributor** (macOS / local): edit repo, run `--profile=contributor`, do not SSH.
- **VPS operator**: one SSH session, one app at a time, `vps-deploy` not parallel CI.
- **Recovery**: `doas ksh DEPLOY/openbsd/resource_guard.sh`, console per `VPS_SAFETY.md`.

## Do not implement by default

`DEPLOY/rails/apps.horizon.yml` — all items are `agent: ignore`.