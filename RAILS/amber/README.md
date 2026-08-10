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
| Tips | Rule coach — analytics nudges plus `ClosetOrganization`'s care/storage/zoning/restraint registers, each naming its principle |
| Taste model | `TasteRanker` — declared preferences plus joy/wear/recency/life-phase. Deterministic weights, not learned |
| Daily look | `StyleAssistant` — deterministic per user and date, weather-aware, persists nothing until you save it |
| Store feeds | None. Amber has no Net-a-porter-style product feed; `ShopTheLook` serves the links you added yourself and says why the remote half is dark |
| Style sessions | Calendar/status only |

## Integration

Components and layers: **[ARCHITECTURE.md](./ARCHITECTURE.md)**. Deliberate shapes
that look like bugs: **[DECISIONS.md](./DECISIONS.md)**.
Shared tokens/concerns: `RAILS/shared/WIRING_NOTES.md`. Feature matrix: `apps.yml` → `amber`.
