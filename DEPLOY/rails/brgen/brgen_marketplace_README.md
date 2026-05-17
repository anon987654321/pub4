# brgen :: marketplace

Hyperlocal classifieds. Buy, sell, trade within your city.

- Namespace: `Marketplace::`
- Subdomain: `markedsplass.brgen.no` (Norway) — locale aliases: `markadur` (IS), `marknadsplats` (SE), `marketplace` (UK/US), `marktplaats` (NL), `marche` (FR/BE), `mercato` (IT), `mercado` (PT/ES), `markkinapaikka` (FI)
- Route prefix: `/marketplace`

## Models

| Model | Notes |
|---|---|
| `Marketplace::Category` | Top-level classification (clothing, electronics, vehicles, housing, …) |
| `Marketplace::Listing` | Individual ad: title, body, price, photos (Active Storage), location |
| `Marketplace::Order` | Buyer ↔ seller transaction; payment + delivery state machine |

## Routes

Wrapped in `constraints(subdomain: MARKETPLACE_SUBDOMAINS)` in `config/routes.rb`. Same Rails app serves every locale alias.
