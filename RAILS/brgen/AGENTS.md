# brgen — agent notes

One Rails process, one `rc.d/brgen`, one SQLite. **Not one website.**

A **city** is an apex host. **Every** city in `Brgen::DomainRegistry::ENTRIES`
gets the same shape: main feed at the apex, namespaced subapps on subdomains.
Bergen and Los Angeles below are two worked examples, not the whole network.
`oshlo.no`, `lndon.uk`, `chcago.us`, `kbenhvn.dk` — same process, same engines,
same `<subapp>.<apex>` rule.

Apex names are the city with a vowel dropped (or similar): Bergen → `brgen.no`,
Oslo → `oshlo.no`, Los Angeles → `lsangeles.com`, London → `lndon.uk`. Do not
invent a host; the list is only `ENTRIES`. Linking a row that has no TLS is
`LIVE_DOMAINS` in that file, not a product decision here.

The Host header picks both the city (`acts_as_tenant`) and the vertical. Same
users, same session, same deploy.

```
<substack>.<city-apex>
dating.brgen.no          dating.lsangeles.com          dating.oshlo.no
markedsplass.brgen.no    marketplace.lsangeles.com     markedsplass.oshlo.no
```

## Hosts (two cities as the pattern; every `ENTRIES` row works like this)

| What | Engine / code | Bergen | Los Angeles |
|---|---|---|---|
| Main feed (posts, communities, events, stories, DMs) | host `app/` | `brgen.no` | `lsangeles.com` |
| Marketplace | `engines/marketplace` | `markedsplass.brgen.no` | `marketplace.lsangeles.com` |
| Dating | `engines/dating` | `dating.brgen.no` | `dating.lsangeles.com` |
| Takeaway | `engines/takeaway` | `takeaway.brgen.no` | `takeaway.lsangeles.com` |
| TV | `engines/tv` | `tv.brgen.no` | `tv.lsangeles.com` |
| Maps | `engines/maps` | `maps.brgen.no` | `maps.lsangeles.com` |
| Playlist | `engines/playlist` | `playlist.brgen.no` | `playlist.lsangeles.com` |
| Messenger | host routes, not an engine | `messenger.brgen.no` | `messenger.lsangeles.com` |

Marketplace is the only vertical whose **subdomain word** is localized
(`markedsplass` / `marketplace` / `marktplatz` / …). Dating, tv, takeaway, maps,
messenger, playlist are the same English token on every city.

**Not a brgen subapp.** `ai.brgen.no` is MASTER (`MASTER/web`), different rc.d.
`amber.brgen.no` is a separate Rails app. Do not mount either here.

Recipe for engines: `ENGINES.md`. Feature inventory: `RAILS/apps.yml`.
Local verticals need `Host: dating.brgen.no` (etc.); `dating.localhost` 404s
because the registry keys off city apexes, not localhost.

## Deploy

Full Rails 8 app in this directory. `brgen.sh` copy-tree deploys to
`/home/brgen/app` on vm23. Port **38182**. Shared engine: `RAILS/shared`.

- Golden checks: `OPENBSD/bin/check-rails --profile=contributor`; scan via
  `cd MASTER && bundle exec ruby bin/cli` → `/scan RAILS/brgen`.
- VPS: `bin/pub4 vps deploy brgen --remote` (serial — never parallel with other apps).
- Do not: enable `force_ssl` behind relayd; edit `OPENBSD/deploy_inventory.json`
  without updating `apps.yml`; add a fourth public Rails app
  (`OPENBSD/DECISIONS.md`).
