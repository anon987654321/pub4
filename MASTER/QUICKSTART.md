# Quickstart

Primary entry for LLMs and agents. Read this first; consult `data/soul.yml` and `data/rules.yml` when you need precision.

Operator friction (relayd, VPS, Rails): `bin/playbook` or `data/operator_playbook.yml`.

## Model

Propose → validate against constitution → execute with evidence → learn.

Layers: constitution (`data/*.yml`) → pipeline (`now/`) → judge → loop → ground/reach/trace. The particle web face reflects live state.

## Work pattern

1. Reconnaissance with any tool.
2. Before editing: read full target files and callers.
3. Production changes: minimal patch, evidence — scan/fix often run without you naming them.

After writes, MASTER records paths, lints them in Review, and standing orders audit `lib/` (constitution drift) plus autocommit. Say "check my edits", "fix this file", or "run through master" instead of chaining `/scan` `/fix` by hand.

Golden rule: `PRESERVE_THEN_IMPROVE_NEVER_BREAK`. No hedging without proof.

## Commands

Prefer `/run <task>` for natural-language work. Explicit: `/scan`, `/fix`, `/review`, `/why`, `/snapshot`, `/video`.

```sh
bin/probe          # smoke + namespace + Rails gate
bin/probe all      # full readiness
bin/probe dogfood  # CLI self-proof
```

OpenBSD: `ruby34`, `bundle34` under `/home/dev/pub4/MASTER`.

## Media

`REPLICATE_API_TOKEN` in `/etc/master.env`. `/photograph`, `/video`, `/motion-dataset`, `/prompt`. CLI: `bundle exec ruby bin/video help`.

## Friction

- Strict read-before-write on production paths.
- 1-vCPU VPS scans serially — prefer targeted `/scan` over whole-tree passes.
- Web face needs `rcctl restart master` after `web/` edits.

See `data/limits.yml` → `llm_ergonomics`. Next: `/orient` or `data/CANON.md` for full doctrine.