# Multi-tenant subdomain routing (pub4)

Live subdomain constraints are implemented in **`brgen/config/routes.rb`** via `Brgen::DomainRegistry` — not a shared `DEPLOY/rails/config/routes.rb` boot file.

## Verticals (brgen.no family)

| Subdomain | Module | Notes |
|-----------|--------|-------|
| `markedsplass` / `marketplace` / locale aliases | `marketplace` | Per-city marketplace subdomain from `DomainRegistry` |
| `playlist`, `spilleliste` | `playlist` | Hosted tracks, sets |
| `takeaway` | `takeaway` | Restaurants, orders |
| `tv` | `tv` | Channels, live streams |
| `maps` | `maps` | Places index |
| `messenger` | root conversations | Messages surface |
| `dating` | `dating` | Matchmaking |
| `ai` | MASTER relay | `ai.brgen.no` → Falcon :53187 |

## Standalone apps (`DEPLOY/master.json`)

| App | Domain | Port |
|-----|--------|------|
| amber | amber.brgen.no | 61352 |
| hjerterom | hjerterom.brgen.no | 38891 |
| bsdports | bsdports.org | 47312 |
| blognet | blognet.brgen.no | 10002 |
| baibl | baibl.brgen.no | 10007 |

## Operator surfaces

- **MASTER chat** — domain cluster bar (`domain_cluster.js`) prefixes `[domain:…]` on directives.
- **Matrix console** — `DEPLOY/public/index.html` (SSE bridge to `/events/stream`).
- **CLI** — `/domain <name>` via `SubdomainOrchestrator` Reach tool.

## Alignment gate

```bash
ruby DEPLOY/rails/domain_alignment_gate.rb
```

Verifies DNS (`openbsd.sh`), `DomainRegistry`, and `routes.rb` stay in sync.