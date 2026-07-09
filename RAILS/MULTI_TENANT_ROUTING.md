# Multi-tenant routing

Subdomain constraints live in `brgen/config/routes.rb` via `Brgen::DomainRegistry`.

## brgen verticals

| Subdomain | Module |
|-----------|--------|
| markedsplass / marketplace aliases | marketplace |
| playlist / spilleliste | playlist |
| takeaway | takeaway |
| tv | tv |
| maps | maps |
| messenger | conversations |
| dating | dating |
| ai | MASTER relay → :53187 |

## Standalone apps

| App | Domain | Port |
|-----|--------|------|
| amber | amber.brgen.no | 61352 |
| hjerterom | hjerterom.brgen.no | 38891 |
| bsdports | bsdports.org | 47312 |

## Operator UI

- MASTER domain bar: `MASTER/web/public/domain_cluster.js`
- Matrix console: `MASTER/tools/public/index.html`
- CLI: `/domain <name>` via `SubdomainOrchestrator`

## Gate

```bash
ruby DEPLOY/rails/domain_alignment_gate.rb
```
