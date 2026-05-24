# Amber Stimulus / Rails 8 rollout

Amber is the best first product to receive the shared frontend baseline because the app matrix already marks Item, Outfit, Item photos, broadcasts, and item/outfit views as done.

## Implement first

1. Copy `DEPLOY/rails/shared/frontend/stimulus_components.js` into the app frontend entrypoint.
2. Add Lightbox to item photo galleries.
3. Add Sortable to outfit item ordering.
4. Add Notification to wear/save/upload actions.
5. Add Timeago to item/outfit cards.
6. Add Clipboard to item/outfit share links.
7. Add Dropdown + Auto Submit to wardrobe filters: category, color, mood, occasion, life phase.
8. Add Content Loader to underused/never-worn item panels.

## Rails 8 work

- Move wardrobe image processing to Solid Queue.
- Use Active Storage variants for thumbnails.
- Cache wardrobe cards with Solid Cache.
- Broadcast outfit/item changes with Turbo Streams.
- Emit structured events:
  - `amber.item.viewed`
  - `amber.item.worn`
  - `amber.outfit.created`
  - `amber.photo.uploaded`

## Acceptance

- Items remain navigable without JavaScript.
- Lightbox is enhancement only.
- Outfit ordering persists server-side.
- Upload/wear actions produce visible notifications.
- Underused item panel has empty/loading/error states.
