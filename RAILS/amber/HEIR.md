# Amber — heir / operator one-pager

Amber is a **social fashion** app (`amber.brgen.no`) — feed, follows, outfits
and a wardrobe, sharing the same social stack as brgen. Day-to-day it should run
without engineering. This page is for the person who inherits stewardship.

## What you do

1. Open https://amber.brgen.no and watch wardrobes grow.
2. Help the occasional user (password, “what is declutter?”, content concern).
3. Keep bills paid: VPS + domain.
4. If the site is down, tell a technical contact (see below).

You do **not** need to process photos, score declutter decisions, or restart
servers on a normal week.

## What runs itself

| Piece | Behaviour |
|--------|-----------|
| OpenBSD service | `rc.d/amber` starts Falcon + Solid Queue on port 61352 |
| TLS | relayd + cert renew scripts for `amber.brgen.no` |
| Photo upload | Variants, colour extract, one portrait polish, local fingerprint, sustainability score |
| Declutter hygiene | Daily job: expire overdue wear challenges; nudge 30-day box items |
| Queue cleanup | Hourly clear of finished Solid Queue jobs |
| Demo wardrobe | Seeded for guests without an admin filling the catalog |

## Health checks (tech or laptop)

```sh
curl -fsS https://amber.brgen.no/up
# or full stack:
sh OPENBSD/bin/uptime-check.sh
```

Red `/up` → technical contact restarts in order: **master → brgen → amber →
relayd**.

## Secrets that keep AI smart

| Env | Required for |
|-----|----------------|
| `SECRET_KEY_BASE` | App boot |
| `OPENROUTER_API_KEY` | LLM joy analysis, vision outfits, capsule LLM path |
| `AMBER_ENABLE_MASTER_PHOTO=1` | Optional MASTER look photography (off by default) |

Without OpenRouter, Amber still works: **heuristics and rules** (joy from wear,
rule-based outfits, local capsule). Buttons say so in the UI.

## Honesty map (so you are not sold vapor)

- **Photo polish** — yes. ML cut-out / segment — no (planned).
- **Fingerprint** — local CRC for change detection. Real embeddings / lookalike
  search — planned.
- **Analytics tips** — rule coach, not AI.
- **Style sessions** — schedule/status, not live video.
- **KonMari loop** — real: joy, challenges, last-chance outfits, box, release
  paths.

## When to call tech

- Site down more than a few minutes
- “AI analyse” broken after key rotation
- Disk full / queue stuck (rare; there is `OPENBSD/amber_queue_sweep.sh`)
- Security update or code deploy needed

## Deploy (technical)

```sh
doas zsh RAILS/amber/amber.sh
# or fleet:
doas zsh RAILS/deploy.sh amber
```

Feature matrix: `RAILS/apps.yml` → `amber`.
