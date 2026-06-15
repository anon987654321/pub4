# brgen

Hyperlocal city network — one Rails app, many verticals scoped by host/subdomain.

## Surfaces

Posts, communities, marketplace, dating, playlist, TV, takeaway, maps, messaging, notifications. City tenant via `acts_as_tenant`; per-city SQLite at `db/cities/<slug>.sqlite3`.

Subdomains: `tv`, `dating`, `playlist`, `takeaway`, `markedsplass` (+ localized marketplace aliases), `maps`, `ai`.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · Solid Queue/Cache/Cable · Active Storage · OpenBSD relayd

## Deploy

```zsh
doas zsh DEPLOY/rails/brgen/brgen.sh
doas rcctl check brgen_rails
curl -fsS http://127.0.0.1:38182/up
```

## Shared

Uses `pub4-shared` concerns (`Votable`, `Commentable`, `Taggable`, `ActivityTrackable`, `GeoLocatable`, `Notifiable`). Activity graph via `Shared::EventEmitter` — wire more actions over time.

## Open items

See `apps.yml` → `brgen.features` for port/missing/planned matrix. Priority: marketplace order chat reuse, playlist set routes, dating match → DM handoff, city switcher audit.