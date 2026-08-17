# `pub` recovery shelf

> Paths below were written against the pub4 layout of 2026-06-26, before
> `DEPLOY/` was split into `RAILS/`, `OPENBSD/` and `STUDIO/`. Those three
> have been repointed. `DEPLOY/bp/`, `DEPLOY/sh/` and `DEPLOY/archive/` are
> left as written because they have no successor in this tree: the business
> plan generator and vulcheck were not carried over, which is the gap this
> document exists to record rather than an error in it.


This directory is for source/provenance recovered from
`anon987654321/pub`.

It is not a live deploy tree.

## Why this exists

`pub4` is cleaner than `pub`, but a cleanup is not the same as a restore.
Old material must be either:

- restored as active source,
- ported into the new architecture,
- archived as provenance,
- or explicitly retired.

Anything else becomes silent loss.

## Priority order

1. Preserve `__OLD_BACKUPS/MEGA_ALL_APPS.md`.
2. Preserve/port standalone AI³.
3. Restore the business-plan generator/data/template source pipeline.
4. Finish Rails feature leaves already marked `missing` or `port`.
5. Preserve old framework schemas/prompts/modules/plugins before deleting.
6. Preserve old postpro/image-engine positioning.

## Do not execute legacy installers

Many old files are generated installer transcripts or scaffold scripts.
They mention outdated assumptions such as PostgreSQL/Redis defaults, old ports,
and old OpenBSD targets.

Read them as evidence. Port intent into:

- `MASTER/`
- `RAILS/apps.yml`
- tracked `RAILS/<app>/` source
- `OPENBSD/`
- `DEPLOY/bp/`
- `STUDIO/postpro/`

## Mapping

| Legacy `pub` path | `pub4` target | State |
|---|---|---|
| `__OLD_BACKUPS/MEGA_ALL_APPS.md` | `RECOVERY/pub/__OLD_BACKUPS/MEGA_ALL_APPS.md` | missing |
| `ai3/` | `RECOVERY/pub/ai3/` or `MASTER/tools/ai3_import.rb` | absorbed, not restored |
| `bplans/consolidated/` | `RECOVERY/pub/bplans/consolidated/` + `DEPLOY/bp/` | partial |
| `plugin_schema_v1.json` | `RECOVERY/pub/plugin_schema_v1.json` | archived by this patch |
| `README.md` image-engine pitch | `STUDIO/postpro/IMAGE_ENGINE_POSITIONING.md` | archived by this patch |
| `misc/vulcheck/` | `DEPLOY/sh/tools/vulcheck.rb` | ported |
| `brgen_app/` | `RAILS/brgen/` | partial |

## Restore commands for an agent with network access

Use GitHub contents fetches or a normal clone.

```zsh
mkdir -p RECOVERY/pub/__OLD_BACKUPS
git clone https://github.com/anon987654321/pub /tmp/pub-legacy
cp /tmp/pub-legacy/__OLD_BACKUPS/MEGA_ALL_APPS.md RECOVERY/pub/__OLD_BACKUPS/
cp -R /tmp/pub-legacy/ai3 RECOVERY/pub/ai3/legacy
cp -R /tmp/pub-legacy/bplans/consolidated RECOVERY/pub/bplans/consolidated
```

Then read before porting:

```zsh
grep -R "TODO\|CHECKSUM\|EOF:" RECOVERY/pub
```

Keep this directory small only after each item has a canonical target and a
documented retirement/port decision.
