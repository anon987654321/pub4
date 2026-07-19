# amber

Wardrobe intelligence — garments, outfits, KonMari declutter loop, style timeline, recommendations.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · Active Storage · OpenBSD relayd

## Deploy

```zsh
doas zsh RAILS/amber/amber.sh
curl -fsS http://127.0.0.1:61352/up
```

## Heir / low-ops

See **[HEIR.md](./HEIR.md)** — what runs alone, health checks, env keys, honesty map.

## Honesty (quick)

| Claim | Reality |
|--------|---------|
| Joy + declutter | Full loop (score, challenges, last-chance outfits, 30d box job) |
| Photo pipeline | Variants + portrait polish + colour — not ML cut-out |
| Fingerprint | Local CRC — not semantic embeddings |
| AI | OpenRouter when `OPENROUTER_API_KEY` set; heuristics otherwise |
| Tips | Rule coach |
| Style sessions | Calendar/status only |

## Integration

Shared tokens/concerns: `RAILS/shared/WIRING_NOTES.md`. Feature matrix: `apps.yml` → `amber`.
