# amber

Wardrobe intelligence — garments, outfits, the KonMari declutter loop, a style
timeline, and recommendations that can explain themselves.

Regenerated 2026-08-11 against the tree rather than against the last README:
21 services, 8 jobs, 30 controllers, 31 models, 35 test files.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · Active Storage · OpenBSD relayd · port 61352

## Deploy

```zsh
doas zsh RAILS/amber/amber.sh
curl -fsS http://127.0.0.1:61352/up
```

Every deploy of any app sheds amber, and relayd keeps answering TLS while it is
down — so the failure looks like `curl 000`, not a 5xx. Check the port directly.
`ALLOW_AMBER_DOWN=1` waives it in `deploy-smoke.sh` when that is the policy.

## Heir / low-ops

See **[HEIR.md](./HEIR.md)** — what runs alone, health checks, env keys, honesty map.

## Language

`default_locale` is `:nb`, with `:en` available and a switcher in the footer. Chrome,
empty states and — since 2026-08-11 — every controller flash go through I18n; the
app's own copy lives in `config/locales/{nb,en}.yml` under `flash:`, and the
sentences the engine owns (`not_authorized`, `rate_limited`) come from
`shared.flash.*`. `config.i18n.raise_on_missing_translations` is on in test, so a
key that does not resolve is a failure rather than a span nobody reads.

## Honesty

The point of this table is that each row names the mechanism, so a claim cannot
quietly outgrow it.

| Claim | Reality |
|---|---|
| Joy + declutter | Full loop — score, challenges, last-chance outfits, and a 30-day box in `DeclutterHygieneJob` |
| Photo pipeline | `WardrobeMediaJob`: variants, portrait polish, colour. Not ML cut-out |
| `RemoveBackgroundJob`, `SegmentGarmentImageJob` | **Deprecated shells.** They remove nothing and segment nothing; they mark an honest status and no-op. Kept only for in-flight queues |
| `EmbedGarmentJob` | An alias of `FingerprintGarmentJob`. There are no embeddings |
| Fingerprint | Local CRC over the image bytes (`zlib`). Not a semantic embedding, so it finds re-uploads, not lookalikes |
| Duplicates | `DuplicateDetector` groups on an exact `duplicate_key`. Two similar shirts are not duplicates to it |
| AI | OpenRouter (`google/gemini-2.0-flash-001`) when `OPENROUTER_API_KEY` is set; deterministic heuristics otherwise, and the UI says which |
| Taste model | `TasteRanker` — declared `StylePreference` rows plus joy, wear count, recency and life phase. Fixed weights, not learned |
| Daily look | `StyleAssistant` — deterministic per user and date, weather-aware, persists nothing until you save it |
| Weather | open-meteo for Bergen only (lat/lng are constants), 15-minute cache with negative caching, 2s connect / 3s read. It is in front of the dashboard, so it is bounded on purpose |
| Wardrobe gaps | `WardrobeGap` compares against fixed essentials counts per category. A target, not a judgement about you |
| Sustainability score | A heuristic: wear count scaled and capped, plus a bonus for sparking joy. Not a lifecycle assessment |
| Tips | `WardrobeAnalytics` nudges plus `ClosetOrganization`'s care/storage/zoning/restraint registers, each naming its principle |
| Store feeds | None. Amber imports no product feed; `ShopTheLook` ranks the affiliate links you added, and needs `TRADEDOUBLER_TOKEN` (which lives on brgen) for the remote half — it says when that half is dark |
| Style sessions | Calendar and status only |

## Guests

`User` has a `guest` column, so anonymous visitors get a soft `Current.user` and can
use the product without signing up. Two consequences worth knowing:
`allow_unauthenticated_access` is a **no-op here** — it logs that in development and
test — and `require_real_user` is the actual identity gate. Guest rows are pruned
nightly by `Shared::PruneGuestUsersJob`.

## Where it is fragile

- **One box, 1 GB.** amber shares vm23 with brgen, bsdports and MASTER. It needs
  about twenty seconds to signal ready, and Falcon kills the worker if that misses
  its health-check window under load — which reads as a broken app and is not one.
- **Litestream replicas are same-disk.** There is no off-host copy of the database
  yet. That is tracked, not solved.

## Integration

Components and layers: **[ARCHITECTURE.md](./ARCHITECTURE.md)**. Shapes that look
like bugs and are not: **[DECISIONS.md](./DECISIONS.md)**. Shared tokens and
concerns: `RAILS/shared/WIRING_NOTES.md`. Feature matrix: `RAILS/apps.yml` → `amber`.
