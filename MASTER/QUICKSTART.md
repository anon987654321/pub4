# Quickstart

This is the primary entry for LLMs and agents. Read it first; consult `data/soul.yml` and `data/rules.yml` when you need precision. Operator friction around relayd, the VPS, and Rails is covered in `bin/playbook` and `data/operator_playbook.yml`.

The mental model is propose, validate against the constitution, execute with evidence, then learn. Layers stack from constitution in `data/*.yml` through the pipeline in `now/`, then judge, loop, and ground/reach/trace. The particle web face reflects live state.

Work in a reconnaissance-then-edit pattern. Use any tool to understand context. Before editing, read full target files and their callers. Production changes should be minimal patches backed by evidence—scan and fix often run without you naming them. After writes, MASTER records paths, lints them in Review, and standing orders audit `lib/` for constitution drift plus autocommit. Say "check my edits", "fix this file", or "run through master" instead of chaining `/scan` and `/fix` by hand. The golden rule is `PRESERVE_THEN_IMPROVE_NEVER_BREAK`. Do not hedge without proof.

Prefer `/run <task>` for natural-language work. Explicit commands include `/scan`, `/fix`, `/review`, `/why`, `/snapshot`, and `/video`. Smoke and namespace checks use `bin/probe`; full readiness is `bin/probe all`; CLI self-proof is `bin/probe dogfood`. On OpenBSD use `ruby34` and `bundle34` under `/home/dev/pub4/MASTER`.

Media generation needs `REPLICATE_API_TOKEN` in `/etc/master.env`. Use `/photograph`, `/video`, `/motion-dataset`, and `/prompt`, or `bundle exec ruby bin/video help` for CLI detail.

Expect strict read-before-write on production paths, serial scans on a one-vCPU VPS—prefer targeted `/scan` over whole-tree passes—and `rcctl restart master` after `web/` edits. See `data/limits.yml` → `llm_ergonomics`. For full doctrine, use `/orient` or `data/CANON.md`.