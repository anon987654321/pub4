# brgen takeaway

Food ordering subapp for brgen.no. Rails 8. PostgreSQL.

## Models

- `Restaurant` — dining location with geocoding
- `MenuItem` — menu item with availability states and monetized price
- `Order` — lifecycle: placed → accepted → preparing → dispatched → delivered / canceled

## Deploy

```zsh
doas zsh brgen_takeaway.sh
```
