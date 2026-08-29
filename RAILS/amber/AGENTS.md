# amber — agent notes

- **Domain:** amber.brgen.no. **Port:** 61352. **Deploy root:** `RAILS/amber`.
- **Shared engine:** `RAILS/shared`.
- **Inventory:** `apps.yml` (active); wardrobe horizon items in
  `apps.horizon.yml` (ignore).
- **Heir ops:** `HEIR.md` (low-ops handoff).
- **Golden checks:** `OPENBSD/bin/check-rails --profile=contributor`.
- **VPS:** `MASTER/bin/pub4 vps deploy amber --remote`.
- **Honesty:** photo polish ≠ ML segment/matting; fingerprint ≠ embedding; tips
  = rules; live_streams = style sessions (no video).
- **AI:** `OPENROUTER_API_KEY` for LLM; otherwise heuristics. MASTER photos only
  if `AMBER_ENABLE_MASTER_PHOTO=1`.
- **Hygiene:** `DeclutterHygieneJob` daily (challenges + 30d box); see
  `config/recurring.yml`.
