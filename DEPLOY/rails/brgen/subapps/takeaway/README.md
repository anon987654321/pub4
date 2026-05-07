# brgen :: takeaway

Local street-food and restaurant ordering.

- Namespace: `Takeaway::`
- Subdomain: `takeaway.brgen.no`
- Route prefix: `/takeaway`

## Models

| Model | Notes |
|---|---|
| `Takeaway::Restaurant` | Owner, name, address, hours, cuisine tags, photos |
| `Takeaway::MenuItem` | Restaurant menu entry: name, description, price, photo, availability |
| `Takeaway::Order` | Customer ↔ restaurant order; status machine (placed → accepted → ready → delivered) |
| `Takeaway::OrderItem` | Line items linking `Order` ↔ `MenuItem` with quantity + per-item notes |

## Discovery

Restaurants filtered by city (subdomain) and distance from delivery address. Live order status pushed via Action Cable `OrdersChannel`.
