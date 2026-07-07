# amber — agent notes

- **Domain:** amber.brgen.no. **Port:** 61352. **Deploy root:** `DEPLOY/rails/amber`.
- **Shared engine:** `DEPLOY/rails/shared`.
- **Inventory:** `apps.yml` (active); wardrobe horizon items in `apps.horizon.yml` (ignore).
- **Golden checks:** `DEPLOY/bin/check-rails --profile=contributor`.
- **VPS:** `bin/pub4 vps deploy amber --remote`.
- **Recent landed:** style evolution timeline (`StyleEvolutionService`, `wardrobe_items#timeline`).