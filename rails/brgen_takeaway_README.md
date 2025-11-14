# BRGEN Takeaway — Hyperlocal Food Delivery Platform
## Overview

BRGEN Takeaway is a Rails 8 application in the BRGEN suite for restaurant listings, menu management, ordering, and courier dispatch with real‑time status updates. It integrates with the shared BRGEN infrastructure (PostgreSQL, Redis, Falcon, Hotwire) and follows the project’s master.json principles: simplicity, idempotency, observability, reversibility, least‑privilege.
## Features

- Restaurants: profiles, hours, delivery zones

- Menus: categories, items, options/modifiers
- Orders: cart → checkout → payment → dispatch → delivery

- Realtime: Turbo Streams for order status, driver location updates
- Payments: Stripe (card), optional Vipps
- Search: cuisine/tags, distance filters
- Multi‑tenant: city/region isolation (ActsAsTenant)
## Data model (sketch)
```ruby
class Restaurant < ApplicationRecord
  has_many :menu_items, dependent: :destroy

  has_many :orders,     dependent: :nullify
  validates :name, :address, presence: true
  geocoded_by :address; after_validation :geocode, if: :will_save_change_to_address?
end
class MenuItem < ApplicationRecord
  belongs_to :restaurant
  enum availability: { available: 0, sold_out: 1 }
  monetize :price_cents

end
class Order < ApplicationRecord
  belongs_to :restaurant
  belongs_to :user
  enum status: { placed: 0, accepted: 1, preparing: 2, dispatched: 3, delivered: 4, canceled: 5 }

end
```
## Controller notes
- OrdersController: create/advance/cancel with state checks; broadcast status via Turbo
- RestaurantsController: index/search (nearby, cuisine), show
- Webhooks: Stripe payment_intents.succeeded → advance to accepted

## Install & run
```bash
# run app scaffold
./rails/brgen_takeaway.sh

# deps
bundle install && yarn install
# db
bin/rails db:migrate db:seed

# start
bin/rails server

```
## Configuration

```bash
STRIPE_PUBLIC_KEY=pk_live_...
STRIPE_SECRET_KEY=sk_live_...

MAPBOX_ACCESS_TOKEN=...
DEFAULT_DELIVERY_RADIUS_KM=8
```
## API
- GET  /takeaway/restaurants        # list/search
- GET  /takeaway/restaurants/:id    # details + menu
- POST /takeaway/orders             # create order

- GET  /takeaway/orders/:id         # order status (Turbo stream or JSON)
## Operations
- Idempotent webhooks; signed Stripe events only
- Structured logs: order_id, user_id, restaurant_id, status, latency
- Health: /up, DB/Redis checks via ActiveSupport::HealthCheck

## Security
- PII minimization; tokens via env; least‑privilege API keys
- Rate limits on ordering and search endpoints
—
Built to run for years: minimal moving parts, easy rollbacks, observable state.

