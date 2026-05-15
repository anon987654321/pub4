# Rails deployment portfolio

`DEPLOY/rails` is the active production surface for pub4 Rails apps.

The generated Rails trees are deployment artifacts. The important source of truth is the tracked app tree plus its app-specific deploy script. Older one-shot Zsh generators in `study/` and `pub/__OLD_BACKUPS` are design lineage, not the current production contract.

## Active apps

| App | Script | Domain | Role |
|---|---|---|---|
| `brgen` | `brgen/brgen.sh` | `brgen.no` plus city/domain aliases | Hyperlocal social platform with marketplace, dating, playlist, tv, takeaway, maps, ai |
| `amber` | `amber/amber.sh` | `amber.brgen.no` | Fashion / wardrobe / recommendation app |
| `bsdports` | `bsdports/bsdports.sh` | `bsdports.org` | OpenBSD ports search/index app |
| `baibl` | `baibl/baibl.sh` | `baibl.no` | Bible / reading / content service |
| `blognet` | `blognet/blognet.sh` | app-specific | Blog/content network utility |
| `hjerterom` | `hjerterom/hjerterom.sh` | app-specific | Food donation / pickup lineage from old backups |
| `privcam` | `privcam/privcam.sh` | app-specific | Subscription/video platform lineage from old backups |

## Production contract

Each app deploy script should:

1. copy the tracked `app/` tree into `/home/<app>/app`
2. run Bundler in deployment mode
3. run `RAILS_ENV=production bin/rails db:create db:migrate`
4. seed only when `db/seeds.rb` exists
5. install or update rc.d service
6. register relayd backend
7. restart service
8. verify local `/up`
9. verify relayd route if the public hostname is configured
10. leave logs in `/var/log/<app>.log` or the app-specific rc.d target

## Hard requirements

- No production app should expose raw Rails/Falcon ports publicly.
- Public ingress goes through relayd/httpd/acme only.
- Secrets live outside Git in `/etc/<app>.env` or `/etc/rails/<app>.env`.
- App deploy scripts are idempotent.
- Database migrations must be safe to re-run.
- Background queue/cache services must be Solid Queue/Solid Cache or explicitly documented.
- Every app must have a `/up` health endpoint.
- Every app must have an rc.d restart smoke check.

## Backup-era lineage

`pub/__OLD_BACKUPS/MEGA_ALL_APPS.md` describes the original app family:

- `brgen`
- `amber`
- `privcam`
- `bsdports`
- `hjerterom`

That document used older assumptions: PostgreSQL, Redis, Devise, `devise-guests`, OmniAuth Vipps, StimulusReflex, PWA scaffolding, and generated-from-scratch app scripts.

pub4 intentionally converges this into a simpler production shape:

- tracked app source trees
- SQLite or external DB instead of mandatory PostgreSQL
- Solid Queue / Solid Cache instead of mandatory Redis
- OpenBSD rc.d services
- relayd SNI routing
- app-specific deploy scripts

## Production hardening checklist

For every app:

- [ ] `/up` responds locally
- [ ] rc.d service starts cleanly
- [ ] relayd backend is configured
- [ ] no raw app port is open in pf
- [ ] database migrations run cleanly
- [ ] credentials are not committed
- [ ] user identity does not leak email-derived names
- [ ] uniqueness constraints exist for join tables
- [ ] upload/content paths are bounded
- [ ] background jobs are observable
- [ ] service restart is verified after deploy

## Directory map

```text
rails/
├─ amber/
├─ baibl/
├─ blognet/
├─ brgen/
├─ bsdports/
├─ hjerterom/
├─ privcam/
├─ __shared/
├─ check_ports.sh
├─ modernize_zsh.sh
├─ rich_editor_system.sh
└─ voting_system.sh
```
