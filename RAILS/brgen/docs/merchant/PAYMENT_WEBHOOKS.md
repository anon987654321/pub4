# Payment webhooks (Stripe + Vipps)

## Routes

In `config/routes.rb` (alongside TradeDoubler):

```ruby
post "webhooks/tradedoubler" => "webhooks/tradedoubler#create", as: :webhooks_tradedoubler
post "webhooks/stripe" => "webhooks/stripe#create",       as: :webhooks_stripe
post "webhooks/vipps" => "webhooks/vipps#create",        as: :webhooks_vipps
```

## Stripe

| Item | Value |
|------|--------|
| URL | `https://<host>/webhooks/stripe` |
| Events | `checkout.session.completed`, `checkout.session.async_payment_succeeded` |
| Secret | `STRIPE_WEBHOOK_SECRET` (`whsec_…`) |

Verification:

1. Parse `Stripe-Signature` → `t` + one or more `v1`
2. Reject if `|now - t| > 300s`
3. `HMAC_SHA256(secret, "#{t}.#{raw_body}")` hex vs any `v1` (constant-time)
4. Multiple `v1` supported (key rotation)

Order resolution: `client_reference_id` (`order_id:` / `checkout_id:`) or `metadata`.

## Vipps

| Item | Value |
|------|--------|
| URL | `https://<host>/webhooks/vipps` |
| Events | at least `epayments.payment.authorized.v1`, `epayments.payment.captured.v1` |
| Secret | `VIPPS_WEBHOOK_SECRET` (base64 from registration response) |

Register once:

```bash
curl -X POST https://api.vipps.no/webhooks/v1/webhooks \
  -H "Authorization: Bearer $TOKEN" \
  -H "Ocp-Apim-Subscription-Key: $VIPPS_SUBSCRIPTION_KEY" \
  -H "Merchant-Serial-Number: $VIPPS_MSN" \
  --data '{"url":"https://HOST/webhooks/vipps","events":["epayments.payment.authorized.v1","epayments.payment.captured.v1"]}'
```

Save returned `secret` → `VIPPS_WEBHOOK_SECRET`.

Verification (Vipps docs):

1. `x-ms-content-sha256` == base64(SHA256(raw_body))
2. String to sign: `POST\n{pathAndQuery}\n{x-ms-date};{host};{content-hash}`
3. HMAC-SHA256 with decoded webhook secret → base64 → match `Authorization` Signature=

Paid events: `AUTHORIZED`, `CAPTURED` with `success: true`.

Order resolution: reference `brgen-order-{id}-…` set by `VippsCheckout.start!`.

## After paid (both)

1. `mark_paid!` / payment_status fields (idempotent)
2. Optional `gclid` from Stripe metadata
3. `GoogleEnhancedConversionsJob` if `GOOGLE_ENHANCED_CONVERSIONS=1` and Ads ENV set

## Shared helper

`Webhooks::PaymentPaid` — used by both controllers so mark-paid + conversion enqueue stay in one place.
