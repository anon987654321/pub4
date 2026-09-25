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
| Playlist | `engines/playlist` | `radio.brgen.no` | `radio.lsangeles.com` |
| Messenger | host routes, not an engine | `messenger.brgen.no` | `messenger.lsangeles.com` |

Marketplace is the only vertical whose **subdomain word** is localized
(`markedsplass` / `marketplace` / `marktplatz` / …). Dating, tv, takeaway, maps,
messenger, playlist are the same English token on every city.

**Not a brgen subapp.** `ai.brgen.no` is MASTER (`MASTER/web`), different rc.d.
`amberapp.art` is a separate Rails app. Do not mount either here.

Recipe for engines: `README.md`. Feature inventory: `RAILS/apps.yml`. Local
verticals need `Host: dating.brgen.no` (etc.); `dating.localhost` 404s because
the registry keys off city apexes, not localhost.

## Deploy

Full Rails 8 app in this directory. `brgen.sh` copy-tree deploys to
`/home/brgen/app` on vm23. Port **38182**. Shared engine: `RAILS/shared`.

- Golden checks: `OPENBSD/bin/check-rails --profile=contributor`; scan via `cd
  MASTER && bundle exec ruby bin/cli` → `/scan RAILS/brgen`.
- VPS: `MASTER/bin/operator vps deploy brgen --remote` (serial — never parallel with
  other apps).
- Do not: enable `force_ssl` behind relayd; edit `OPENBSD/deploy_inventory.json`
  without updating `apps.yml`; add a fourth public Rails app
  (`OPENBSD/CLAUDE.md`, "Refused, and why").

## BergenDemoSeeder stays one class

`lib/brgen/bergen_demo_seeder.rb` breaches `NO_GOD_CLASS` on length (about 330
code lines against 300) and is left whole. Its literal Bergen data already lives
in `bergen_demo_data.rb`; what remains is sixteen private methods, one per
vertical, driven by one `seed!`, and splitting them makes ten files with one
caller each, which trades a god class for `FILE_SPRAWL`. The finding is accepted
here. Models that hold several subjects split the other way, into concerns in a
directory named after the model, as `Conversation` and `Takeaway::Order` do.

## The storefront nav bars stay two partials

`marketplace/_nav_bar.html.erb` and `takeaway/_nav_bar.html.erb` share their
markup skeleton and every style, from the marketplace nav bar section of
`application.scss`, so their
geometry cannot drift apart. What differs is content: marketplace carries a
cart and six sections, takeaway no cart and four different sections, and each
names its own engine's routes and search keys. One partial would take the
section list, the cart and the labels as locals, which moves two readable
templates into a table of hashes that each engine fills in. It would also have
to live outside both engines. The duplication is the cheaper shape.
