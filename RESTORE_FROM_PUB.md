# Restore audit: `pub` → `pub4`

> Paths below were written against the pub4 layout of 2026-06-26, before
> `DEPLOY/` was split into `RAILS/`, `OPENBSD/` and `STUDIO/`. Those three
> have been repointed. `DEPLOY/bp/`, `DEPLOY/sh/` and `DEPLOY/archive/` are
> left as written because they have no successor in this tree: the business
> plan generator and vulcheck were not carried over, which is the gap this
> document exists to record rather than an error in it.


Source repositories:

- Legacy source: `https://github.com/anon987654321/pub`
- Successor target: `https://github.com/anon987654321/pub4`

Date: 2026-06-26.

This file records what `pub4` still forgot to restore from `pub`.
It is intentionally placed at the root so future agents see it before they scan
`MASTER/` or `DEPLOY/`.

## Verdict

`pub4` restored the major runtime direction:

- `MASTER/` replaced the old loose `master.json`/prompt/plugin framework.
- `OPENBSD/` replaced the old OpenBSD script island.
- `RAILS/` replaced loose Rails scaffolds with tracked Rails 8 apps.
- `STUDIO/postpro/`, `STUDIO/dilla/`, `DEPLOY/bp/`, and `DEPLOY/sh/` restored
  major lab/deploy surfaces.

But it did not restore the old repository as a provenance-preserving recovery
archive. The missing pieces are mostly source ledgers, generation pipelines, and
feature leaves that were marked `port` or `missing` rather than finished.

## Hard missing / under-restored items

### 1. `__OLD_BACKUPS/MEGA_ALL_APPS.md`

Legacy path:

```text
pub/__OLD_BACKUPS/MEGA_ALL_APPS.md
```

Why it matters:

- It is the broadest old app ledger.
- It records the original Rails/OpenBSD intent before `pub4` reorganized it.
- It contains generated installer payloads/checksums for:
  - shared Rails setup
  - `brgen`
  - `amber`
  - `privcam`
  - `bsdports`
  - `hjerterom`
  - `blognet`
- It also records old assumptions that were later changed:
  - PostgreSQL/Redis baseline
  - StimulusReflex
  - Devise + `devise-guests`
  - Vipps/BankID-style auth
  - PWA/offline service workers
  - OpenBSD 7.7 DNSSEC + relayd + httpd/acme-client

Current `pub4` state:

- `RAILS/apps.yml` is a good status matrix.
- `DEPLOY/archive/recovery/manifest.json` records some archived systems.
- But the full old mega-ledger is not kept in-tree.

Restore action:

- Preserve a local provenance pointer in `RECOVERY/pub/LEGACY_MANIFEST.yml`.
- If full archival restore is desired, copy the legacy file to:

```text
RECOVERY/pub/__OLD_BACKUPS/MEGA_ALL_APPS.md
```

Do not use the old scripts directly on production. Treat them as recovery
evidence and port intent into tracked Rails trees.

### 2. Standalone AI³ CLI

Legacy path:

```text
pub/ai3/
```

Legacy identity:

- Ruby CLI launched with `ruby ai3.rb`
- LangChain.rb integration
- multi-LLM support: Grok, Claude, OpenAI, Ollama
- Weaviate RAG
- role-specific assistants
- Ferrum `UniversalScraper`
- Replicate multimedia support
- OpenBSD `pledge`/`unveil`
- encrypted sessions
- `install.sh` and `install_ass.sh`

Current `pub4` state:

- `MASTER/` says the constitutional runtime replaces old external CLI tooling.
- `DEPLOY/archive/recovery/manifest.json` says `ai3_assistants` were absorbed.

Gap:

- Absorption is not restoration.
- The old assistant CLI shape, config layout, installer story, and role inventory
  are not preserved as a runnable or even complete reference.

Restore action:

- Add `RECOVERY/pub/ai3/README.md` as a recovery note.
- Later either:
  - import the old source into `RECOVERY/pub/ai3/legacy/`, or
  - create `MASTER/tools/ai3_import.rb` that maps each assistant into the
    `MASTER` plugin/council system.

### 3. Business-plan source pipeline

Legacy paths:

```text
pub/bplans/consolidated/
pub/bplans/technology/rails-ecosystem-overview.md
pub/bplans/__letters/
```

`pub4` state:

- `DEPLOY/bp/` contains static pages.
- `DEPLOY/bp/README.md` says pages are hand-maintained and there is no generator.
- `DEPLOY/bp/IMPLEMENTATION_SUMMARY.md` still describes a generator/data/template
  structure that no longer exists:
  - `__shared/template.html.erb`
  - `data/*.json`
  - `generate.rb`
  - `generated/*.html`

Gap:

- The visible sites survived better than the source-of-truth pipeline.
- This breaks repeatability, funding-application iteration, and agent handoff.

Restore action:

- Keep `DEPLOY/bp/RESTORE_SOURCE_PIPELINE.md`.
- Rebuild `generate.rb`, `__shared/template.html.erb`, and structured source data
  before making large BP edits.

### 4. Rails feature leaves still not ported

`RAILS/apps.yml` already admits these gaps. They need to be treated as
inherited restore debt, not new feature ideas.

#### Brgen

- proximity/geolocation filtering
- moderation tools
- media pipeline / Active Storage variants
- TV shows and episodes
- TV upload and publish/schedule events
- dating radius, photos, match-to-message handoff
- marketplace geo-localized listings
- marketplace locale subdomain routing
- playlist listens
- Spotify/YouTube/SoundCloud import
- playlist city trending and track expiry
- takeaway restaurant/geocoding
- takeaway menu availability state machine
- takeaway full order state machine

#### Amber

- wardrobe upload UI
- garment segmentation / background removal
- outfit generation by weather/season/event
- style evolution timeline
- underused item surfacing
- analytics dashboard port completion
- AI closet organization tips

#### Blognet / Foodielicious

- author profile
- RSS / Atom
- semantic search
- membership/subscription/paywall
- AI narration / TTS article
- citations
- editorial workflow
- recipe model
- ingredient model
- cooking flow
- media gallery
- food clips
- locality-aware restaurant references
- seasonal food guides
- article-to-podcast/summary/video/thread pipeline

#### Bsdports

- dependency-tree visualization
- scheduled ports-tree re-import job
- WCAG AAA pass
- AI exploration assistant

#### Hjerterom

- clothing/toy/book reuse tracking
- distribution route optimization

### 5. `privcam` demoted from production app to archive

Legacy state:

- `privcam` was part of the old app set.

Current `pub4` state:

- active Rails README lists six production apps:
  - `brgen`
  - `amber`
  - `bsdports`
  - `baibl`
  - `blognet`
  - `hjerterom`
- `privcam` exists only as archived/recovery/port material.

Restore action:

- Decide explicitly:
  - restore `privcam` as a seventh tracked Rails app, or
  - keep it retired and mark the retirement as intentional.

### 6. Legacy framework/plugin/provenance corpus

Legacy paths:

```text
pub/master.json
pub/plugin_schema_v1.json
pub/prompts*.json
pub/validation*.rb
pub/modules/
pub/plugins/
pub/pull_requests/
```

Current `pub4` state:

- `MASTER/` is stronger and cleaner.
- But not all old schemas and prompt/provenance traces are archived.

Restore action:

- Preserve `plugin_schema_v1.json` under `RECOVERY/pub/`.
- Add a manifest entry for old prompts/modules/plugins/pull-request artifacts.
- Port useful rules into `MASTER/data/rules.yml` only after reading them.

### 7. Image-processing / analog-engine positioning

Legacy path:

```text
pub/README.md
```

Legacy identity:

- “Superior Image Processing Library”
- “Revolutionary Analog Engine”
- HDR, noise reduction, color profiles, professional camera positioning

Current `pub4` state:

- `STUDIO/postpro/` restores image-processing tools.
- The old product/positioning doctrine is not visible.

Restore action:

- Preserve it in `STUDIO/postpro/IMAGE_ENGINE_POSITIONING.md`.
- Later decide whether it becomes marketing copy, technical requirements, or
  retired hype.

## Rule for future agents

Never mark a restore complete because a concept was renamed.

Use these states:

- `restored`: source and behavior are present in `pub4`
- `ported`: behavior is reimplemented in new architecture
- `absorbed`: concept exists, old source/provenance still missing
- `archived`: source kept but not active
- `missing`: neither active nor archived
- `retired`: explicitly rejected with reason

Anything merely “absorbed” still needs provenance.
