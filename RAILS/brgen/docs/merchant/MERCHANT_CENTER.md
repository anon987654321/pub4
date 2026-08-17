# Merchant API client + Google product taxonomy

## Files

| File | Role |
|------|------|
| `google_merchant_client.rb` | Thin Net::HTTP client for productInputs insert/patch/delete + products.get |
| `google_product_taxonomy.rb` | brgen category slug → Google taxonomy id |
| `merchant_offer_mapper.rb` | listing → productAttributes payload |
| `taxonomy-with-ids.en-US.txt` | Optional vendored official taxonomy (download separately if desired) |

Place under e.g.:

```text
RAILS/brgen/app/services/google_merchant_client.rb
RAILS/brgen/app/services/google_product_taxonomy.rb
RAILS/brgen/app/services/merchant_offer_mapper.rb
```

Or under `RAILS/shared` if Amber ever needs the same.

## ENV

```bash
GOOGLE_MERCHANT_ACCOUNT_ID=123456789
GOOGLE_MERCHANT_DATASOURCE_ID=...          # API-type primary data source
GOOGLE_MERCHANT_ACCESS_TOKEN=ya29....      # short-lived; mint via service account
GOOGLE_MERCHANT_CONTENT_LANGUAGE=nb
GOOGLE_MERCHANT_FEED_LABEL=NO
```

Create an **API** data source in Merchant Center (file feeds cannot be written via productInputs).

## Usage sketch

```ruby
attrs = MerchantOfferMapper.attributes_for(listing)
offer_id = MerchantOfferMapper.offer_id(listing)

GoogleMerchantClient.insert_product!(
  offer_id: offer_id,
  attributes: attrs
)

# price-only update
GoogleMerchantClient.patch_product!(
  offer_id: offer_id,
  attributes: { price: attrs[:price], availability: "in_stock" },
  update_paths: %w[price availability]
)

GoogleMerchantClient.get_product(offer_id)
```

## Taxonomy

`GoogleProductTaxonomy.id_for("furniture")` → `436`

Expand `MAP` / `DEEP` as real brgen category slugs settle. Prefer **excluding** unmapped categories from the Merchant feed rather than guessing.

Vendor a snapshot:

```bash
curl -sL -o data/google_product_taxonomy.txt \
  https://www.google.com/basepages/producttype/taxonomy-with-ids.en-US.txt
```

## Auth note

This client expects a ready `GOOGLE_MERCHANT_ACCESS_TOKEN`. On the VPS, mint tokens with a service account JWT (or a tiny sidecar) and refresh before expiry. Do not commit the JSON key.

Official gem alternative: `google-shopping-merchant-products-v1` — heavier dependency; this thin client matches TradeDoubler/AmazonAssociates style on a small host.

## Price micros

`amount_micros` = currency units × 1_000_000.  
If `price_cents` is øre (1 NOK = 100 øre), then micros = `price_cents * 10_000`.
