# hjerterom — agent notes

- **Domain:** hjerterom.brgen.no. **Port:** 38891. **Deploy root:** `DEPLOY/rails/hjerterom`.
- **Operator UI:** `/operator` (`OperatorController#index`).
- **Jobs:** `ShiftReminderJob`; reuse tracking on `FoodItem`; routes via `DeliveryRoute`/`RoutePlanner`.
- **Golden checks:** `DEPLOY/bin/check-rails --profile=contributor`.
- **VPS:** `bin/pub4 vps deploy hjerterom --remote`.