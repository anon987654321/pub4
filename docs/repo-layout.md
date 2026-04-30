# Repository Layout Rules

This page defines **where new files should go** and how to avoid further file sprawl.

## Top-level ownership

- `apps/` — runnable applications and deployable services.
- `knowledge/` — curated references intentionally kept for active use.
- `docs/` — design docs, plans, and repository-level guidance.
- `scripts/` — operational helper scripts used by humans/CI.
- `archive/` — frozen legacy trees and historical snapshots.

## Placement rules

1. Prefer adding new work under one of the five folders above.
2. Do not create a new top-level folder without a short rationale in PR notes.
3. Experimental work should live in `apps/experiments/<topic>/` and be deleted or promoted within 30 days.
4. Generated outputs should be written to `tmp/` (or tool-specific cache dirs), not committed unless explicitly required.

## Depth policy

- Default maximum depth is **5 levels below repository root**.
- If a path must exceed 5 levels, include one sentence in PR notes explaining why.

## Duplication policy

- Keep one canonical copy of a file tree.
- If compatibility requires old paths, prefer symlinks or short forwarding notes over duplicated content.

## Migration mapping (initial)

- `__predecessors/` -> `archive/predecessors/`
- `MASTER/knowledge/awesome/awesome-llm-apps` + `study/awesome-llm-apps` -> `knowledge/awesome/awesome-llm-apps` (canonical target)

## Quick checklist for PR authors

- [ ] New files are in an allowed top-level area.
- [ ] Any deep path (>5) is justified in PR notes.
- [ ] No duplicate tree was introduced.
- [ ] Generated files are excluded or intentionally documented.
