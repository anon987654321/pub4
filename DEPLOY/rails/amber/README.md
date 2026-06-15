# amber

Wardrobe intelligence — garments, outfits, style timeline, recommendations.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · Active Storage · OpenBSD relayd

## Deploy

```zsh
doas zsh DEPLOY/rails/amber/amber.sh
curl -fsS http://127.0.0.1:61352/up
```

## Integration

Inherit shared visual tokens and concerns from `DEPLOY/rails/shared/WIRING_NOTES.md`. Emit wardrobe events to the activity graph where useful.

## Status

Feature matrix: `apps.yml` → `amber`. Production gate + target-host `bin/ci` still required before calling it production-ready.