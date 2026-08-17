# Amazon Associates — go-live for brgen.no

You already have Associates approval in **Sweden, Netherlands, France** (and others).  
PA-API is dead; we use **tags now** + **Creators API** once you have 10 qualifying sales / 30 days.

## 1. ENV (VPS `/etc/brgen.env` or equivalent)

### Required for tagging (do this first)

```bash
# One tag per marketplace you are approved in. NO global fallback.
AMAZON_ASSOCIATE_TAG_SE=your-se-tag-21
AMAZON_ASSOCIATE_TAG_NL=your-nl-tag-21
AMAZON_ASSOCIATE_TAG_FR=your-fr-tag-21
AMAZON_ASSOCIATE_TAG_DE=your-de-tag-21   # optional but useful for NO readers

# Default market for imports / Nordic surface (SE is a real storefront)
AMAZON_MARKET=SE
```

### Creators API (after 10 sales)

```bash
AMAZON_CREATORS_CLIENT_ID=amzn1.application-oa2-client.…
AMAZON_CREATORS_CLIENT_SECRET=amzn1.oa2-cs.v1.…
AMAZON_CREATORS_VERSION=3.2          # EU credentials
```

Legacy aliases still accepted: `AMAZON_ACCESS_KEY` / `AMAZON_SECRET_KEY` map to client id/secret.

## 2. Install the adapter

Replace:

- `RAILS/shared/app/services/shared/amazon_associates.rb` ← new file in this folder  
- Add `RAILS/brgen/lib/tasks/affiliate_amazon.rake` ← new rake tasks  

`Shared::AmazonMarketplace` already has SE/NL/FR/DE — no change required unless you want different SERVED_BY defaults.

## 3. Phase 1 — earn with tags only (no API)

```bash
cd /home/brgen/app   # or your deploy path
bin/rails affiliate:amazon_status

# Seed real ASINs (you choose products that fit brgen)
AMAZON_SEED_ASINS=B0xxxxx,B0yyyyy bin/rails affiliate:amazon_seed[SE]

bin/rails affiliate:health
```

Or in console:

```ruby
AmazonAssociates.seed_asins!([
  { asin: "B0XXXX", title: "Concrete product name", market: "SE", category: "electronics" },
  { asin: "B0YYYY", title: "Another product", market: "NL", category: "home" },
])
```

Links are built via `Shared::AmazonMarketplace.product_url` with the correct tag.  
They appear through the existing `Affiliate.deals` → sidebar like TradeDoubler.

Drive traffic → get **10 qualifying sales in 30 days** → Creators API unlocks.

## 4. Phase 2 — catalog import

Once Creators credentials exist and eligibility is green:

```bash
bin/rails affiliate:amazon_status   # configured? should be true
bin/rails affiliate:import          # pulls Amazon + TradeDoubler
```

`AmazonAssociates.import!` uses SearchItems; `deals` falls back to live search only if the table is empty.

## 5. Norway readers

- No `amazon.no`.  
- `Shared::AmazonMarketplace` maps `NO → DE` by default.  
- If you prefer SE for Nordic users, set `AMAZON_MARKET=SE` and ensure `AMAZON_ASSOCIATE_TAG_SE` is set (you have SE approval).

## 6. Checklist

- [ ] Set `AMAZON_ASSOCIATE_TAG_SE` / `_NL` / `_FR` (and DE if approved)  
- [ ] `bin/rails affiliate:amazon_status` shows tags  
- [ ] Seed a small set of high-intent ASINs  
- [ ] Confirm sidebar shows non-placeholder Amazon rows  
- [ ] Confirm a test click lands on the right storefront with `?tag=`  
- [ ] After 10 sales: create Creators API credential (EU / 3.2)  
- [ ] Set Creators ENV → `affiliate:import`  

## Files in this package

| File | Action |
|------|--------|
| `amazon_associates.rb` | Replace `RAILS/shared/app/services/shared/amazon_associates.rb` |
| `affiliate_amazon.rake` | Add as `RAILS/brgen/lib/tasks/affiliate_amazon.rake` |
| `SETUP.md` | This guide |
