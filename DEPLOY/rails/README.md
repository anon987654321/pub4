# Rails apps

Six production Rails 8.1 apps under one shared engine. **Source of truth: `apps.yml`.**

## Apps

| App | Domain | Port | Role |
|-----|--------|------|------|
| brgen | brgen.no | 38182 | City social + marketplace, dating, TV, takeaway, playlist |
| amber | amber.brgen.no | 61352 | Wardrobe / outfit intelligence |
| bsdports | bsdports.org | 47312 | Ports search and advisories |
| baibl | baibl.no | — | Scripture study graph |
| blognet | — | — | Editorial / recipe publishing |
| hjerterom | hjerterom.no | 38891 | Food rescue and volunteer ops |

Deploy: `doas zsh DEPLOY/rails/<app>/<app>.sh`

## Contract

1. Tracked tree at `DEPLOY/rails/<app>/` copied to `/home/<app>/app`
2. `pub4-shared` via `path: '../shared'` in Gemfile
3. Ruby 3.4, `RAILS_ENV=production`, Falcon behind relayd
4. `config.assume_ssl = true` — no `force_ssl`
5. Health at `/up`; rc.d service per app in `DEPLOY/openbsd/etc/rc.d/`
6. Secrets in `/etc/<app>.env` on VPS — no `config/master.key` in git

## Shared

`DEPLOY/rails/shared/` — engine gem, concerns, Stimulus baseline, `WIRING_NOTES.md`

Copy-tree deploy mirrors shared at `/home/<app>/shared` (sibling of `app/`, not inside it). CI and jobs resolve DEPLOY tools via `Pub4::DeployPaths` (`shared/lib/pub4/deploy_paths.rb`) using `PUB4_RAILS_ROOT` or `/home/dev/pub4/DEPLOY/…` on vm23.

```ruby
include Shared.concern(:Votable)   # Notifiable, ActivityTrackable, GeoLocatable, …
```

## Gates

```zsh
ruby DEPLOY/rails/check_production_gate.rb
cd DEPLOY/rails/<app> && bin/ci    # per-app RuboCop, Brakeman, bundler-audit, test
MASTER/bin/probe rails
```

On OpenBSD, use the package-qualified Ruby 3.4 commands:

```zsh
cd /home/dev/pub4/DEPLOY/rails/<app>
bundle34 check
zsh DEPLOY/sh/vps_ci.sh brgen   # vm23: mutex + load gate
bundle34 exec bin/ci            # direct (auto-guarded on VPS via Pub4::CiGuard)
```

## PWA Workbox Build

All six apps serve generated Workbox workers through their stable
`/service-worker` Rails route. Rebuild and verify them from this directory:

```zsh
npm ci
npm run build:pwa
npm run test:pwa
```

The shared source is `shared/pwa/service_worker.js`; generated app workers are
committed so production deploys do not require Node. They provide precaching,
offline navigation, bounded runtime caches, POST replay, periodic refresh, and
push notification handling.

Legacy `@*.sh` generators and `study/` trees are removed. Do not reintroduce one-shot scaffold deploys.
