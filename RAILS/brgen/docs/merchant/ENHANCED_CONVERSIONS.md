# Server-side enhanced conversions (Google Ads)

## Why Data Manager API

From **15 June 2026**, new adopters of offline / enhanced click conversion upload via Google Ads API `ConversionUploadService` are blocked (`CUSTOMER_NOT_ALLOWLISTED_FOR_THIS_FEATURE`).

**Data Manager API** `events:ingest` is the supported path:

```http
POST https://datamanager.googleapis.com/v1/events:ingest
```

## Files

| File | Role |
|------|------|
| `google_enhanced_conversions.rb` | Hashing + event build + ingest |
| `google_enhanced_conversions_job.rb` | Async job on order paid |

## Google Ads setup

1. Create a conversion action:
   - Type / source: **Website (Import from clicks)** / `UPLOAD_CLICKS`
   - Count: One
   - Value: Use different values
2. Note the **conversion action id** and **customer id** (10 digits).
3. OAuth token (or service account) with permission to ingest events for that Ads account.
4. Turn on enhanced conversions in the Ads UI (unified toggle).

## ENV

```bash
GOOGLE_ENHANCED_CONVERSIONS=1
GOOGLE_ADS_CUSTOMER_ID=1234567890
GOOGLE_ADS_CONVERSION_ACTION_ID=9876543210
GOOGLE_ADS_ACCESS_TOKEN=ya29....
# optional MCC:
# GOOGLE_ADS_LOGIN_CUSTOMER_ID=...
```

## Wire-up

On payment success (after `paid_at` / `payment_status=paid`):

```ruby
GoogleEnhancedConversionsJob.perform_later(order.id)
```

Order should expose when possible:

- `id` → `transactionId` (dedupe key)
- `paid_at`
- `total_cents` or `total`
- `currency` (default NOK)
- `gclid` (from session/cookie at landing or checkout)
- `email` / `phone` (hashed; never sent raw)
- `ad_user_data_consent` (true/false if known)
- line items with `offer_id` like `brgen-123` (matches Merchant feed)

Optional DB column:

```ruby
add_column :marketplace_orders, :google_conversion_uploaded_at, :datetime
add_column :marketplace_orders, :gclid, :string
```

## Hashing rules

- Email: lowercase, trim; for `@gmail.com` / `@googlemail.com` strip `.` in local part; SHA-256 hex
- Phone: normalize to digits (prefer E.164 from your app); SHA-256 hex
- Encoding declared as `HEX` on the ingest request

## Consent

Only send `consent.adUserData` when you know the answer.
Do not default to `CONSENT_GRANTED`.

## Validate

```ruby
GoogleEnhancedConversions.upload_purchase!(order, validate_only: true)
```

## Relation to browser tag

- Browser gtag can still fire Purchase on the success page.
- Server upload uses the same `transactionId` (order id) so Google can dedupe.
- Server path is the source of truth for paid state (webhook), not thank-you JS.

## Do not

- Upload unpaid orders
- Send plain-text email/phone
- Reuse `transactionId` across different orders
- Call legacy `UploadClickConversions` as a new adopter without allowlist

## Install path

```text
RAILS/brgen/app/services/google_enhanced_conversions.rb
RAILS/brgen/app/jobs/google_enhanced_conversions_job.rb
```
