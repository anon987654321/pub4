# brgen

Hyperlocal city network — one app, many verticals per host.

## Surfaces

Posts, marketplace, dating, playlist, TV, takeaway, maps, messaging. Tenant: `acts_as_tenant` on `city_id`.

Subdomains: `tv`, `dating`, `playlist`, `takeaway`, marketplace aliases, `maps`, `messenger`. MASTER: `ai.brgen.no`.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · Solid Queue/Cache · relayd

```zsh
doas zsh RAILS/brgen/brgen.sh
curl -fsS http://127.0.0.1:38182/up
```

## Cities

`Brgen::DomainRegistry` resolves city from hostname (`oshlo.no`, `lsangeles.com`, `brgen.no`, …). Each apex is an isolated experience — no cross-city switcher. Dev defaults to Bergen.

Shared concerns via `pub4-shared`. Backlog: `apps.yml` → `brgen.features`.