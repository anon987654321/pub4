# brgen :: takeaway

Public domain: takeaway.brgen.no

Local Bergen food ordering inside Brgen Core.

- Namespace: `Takeaway::`
- Subdomain: `takeaway.brgen.no`
- Route prefix: `/takeaway`

## Core dependencies

- Brgen identity
- Brgen messaging
- Brgen media pipeline
- Brgen notifications
- Brgen moderation
- Brgen search
- Brgen feed events

## Models

| Model | Notes |
|---|---|
| `Takeaway::Restaurant` | Owner, name, address, hours, cuisine tags, photos |
| `Takeaway::MenuItem` | Restaurant menu entry: name, description, price, photo, availability |
| `Takeaway::Order` | Customer to restaurant order; status machine from placed to delivered |
| `Takeaway::OrderItem` | Line items linking order and menu item with quantity and notes |
| `Takeaway::DeliveryState` | Optional delivery progress and operational state |

## Discovery

Restaurants are filtered by Bergen locality, cuisine, availability, delivery area, and search relevance.

Live order status should use the shared notification/realtime substrate.

## Events

- RestaurantCreated
- MenuItemAdded
- OrderPlaced
- OrderUpdated
- DeliveryStateChanged

## Restore notes

Old generator logic is useful as a scaffold reference only. Normalize naming before porting: avoid mixing `total`, `total_amount`, `user`, and `customer` in the same bounded context.
