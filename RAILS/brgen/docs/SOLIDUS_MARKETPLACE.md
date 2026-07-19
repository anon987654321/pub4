# Brgen marketplace → Solidus (Amazon-parity)

## Goal

Markedsplass (`marketplace.*` / `markedsplass.brgen.no`) should run on **Solidus**
with storefront + multi-vendor marketplace capabilities that track core Amazon.com
flows, while keeping city multi-tenancy (DomainRegistry / acts_as_tenant).

## Gems

| Gem | Role | Note |
|-----|------|------|
| `solidus` (~> 4.7) | Core commerce (catalog, cart, checkout, admin) | Official |
| `solidus_starter_frontend` | Customer storefront (cart, product, checkout UI) | Official Nebulab starter |
| `solidus_marketplace` (0.1.0) | Multi-seller / supplier split | **Legacy** (Boomer Digital); evaluate before prod |
| `solidus_multi_domain` (optional) | Multi-store / multi-domain | Aligns with city apexes |

Native `Marketplace::*` models stay as the **fallback / migration bridge** until
Solidus tables are populated and cut over on the marketplace subdomain only.

## Amazon.com feature map

| Amazon surface | Solidus target | Status |
|----------------|----------------|--------|
| Product detail page (title, images, price, variants) | Spree::Product / Variants + starter frontend PDP | planned |
| Search + facets (category, brand, price) | Solidus search + taxons; FTS bridge from live_search | planned |
| Cart + checkout + payment | Solidus order state machine + payment methods | planned |
| Seller / marketplace (1P + 3P) | solidus_marketplace suppliers **or** custom Seller model | planned |
| Reviews + ratings | Spree reviews extension or keep Marketplace::Review | planned |
| Order tracking / history | Spree::Order customer account | planned |
| Wishlists / saved | Favorites → Solidus wishlist or keep listing_favorites | planned |
| Recommendations | later (AI) | planned |
| City geo scoping | City tenant on Spree::Store / multi_domain | planned |

## Mount plan (no big-bang)

1. Add gems (feature flag `SOLIDUS_MARKETPLACE=1`).
2. `bin/rails g solidus:install` offline / staging only (creates spree_* tables).
3. Mount engines **only** under marketplace subdomain constraints.
4. Keep native listings controllers until cutover; dual-write optional.
5. Wire solidus_starter_frontend routes for storefront.
6. Multi-vendor: prefer modern Solidus multi-seller approach if marketplace 0.1.0
   fails on Solidus 4.7; otherwise implement Seller → Spree::Product ownership.

## Staging enable (safe path)

Gems are **already declared** in `Gemfile` behind `SOLIDUS_MARKETPLACE=1`.
Initializer: `config/initializers/solidus_marketplace.rb` (`Brgen::SolidusMarketplace`).
Routes mount `Spree::Core::Engine` at `/solidus` under marketplace subdomains only
when `Brgen::SolidusMarketplace.mountable?` (flag + gems loaded).

```bash
cd RAILS/brgen
export SOLIDUS_MARKETPLACE=1
bundle install
# Staging host only — not on hot 1GB vm23 with all apps up:
bin/rails g solidus:install
# Commit spree_* migrations; dual-run native listings until cutover.
```

Contract: `ruby RAILS/test/solidus_staging_contract_test.rb` (no gems required).

## Production caution

1 GB OpenBSD VPS cannot run Solidus install/migrate while master+brgen+amber are
hot. Do Solidus schema work on a larger host or during a maintenance window with
amber stopped (`ALLOW_AMBER_DOWN=1 sh OPENBSD/bin/deploy-smoke.sh` after).
