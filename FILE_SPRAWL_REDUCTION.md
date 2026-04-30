# File Sprawl Reduction Plan

## Current Snapshot

- Total tracked files (via `rg --files`): **4,825**.
- Most files live under three top-level directories:
  - `study/` (~2,150 files)
  - `MASTER/` (~2,137 files)
  - `__predecessors/` (~419 files)
- Path depth is high for many files (hundreds at 8+ folder levels), which increases navigation and duplication risk.

## Goals

1. Make ownership clear by top-level directory.
2. Reduce duplicate content across `MASTER/`, `study/`, and `__predecessors/`.
3. Keep active code shallow and archives explicit.

## Recommended Target Structure

- `apps/` — runnable projects and deployable code only.
- `knowledge/` — curated reference material you actually use.
- `archive/` — frozen legacy snapshots and predecessor trees.
- `scripts/` — operational scripts at stable, documented paths.
- `docs/` — project docs, plans, and architecture notes.

## Practical Reduction Moves

### 1) Archive low-churn trees

Move historical and snapshot-heavy folders into a single `archive/` namespace:

- `__predecessors/` -> `archive/predecessors/`
- Any one-off snapshots from `MASTER/` -> `archive/master-snapshots/`

Why: keeps working surface small without deleting history.

### 2) De-duplicate mirrored “awesome” content

There are mirrored trees under both `study/awesome-llm-apps` and `MASTER/knowledge/awesome/awesome-llm-apps`.

Pick one canonical location (recommended: `knowledge/awesome/awesome-llm-apps`) and:

- keep only canonical files there,
- replace duplicates with links/references,
- add a short migration map for old paths.

### 3) Split active vs reference inside `MASTER/`

`MASTER/` currently mixes executable code, deploy configs, docs, data, and knowledge.

Refactor by intent:

- `MASTER/lib`, `MASTER/exe`, `MASTER/web` -> `apps/master/`
- `MASTER/DEPLOY` -> `apps/master/deploy/`
- `MASTER/docs` -> `docs/master/`
- `MASTER/knowledge` -> `knowledge/master/`

### 4) Set a max path depth policy for new files

Adopt a lightweight rule in contributor docs:

- default max depth: 5 levels below repo root,
- deeper paths require a reason in PR description.

This prevents future nested sprawl.

### 5) Add “placement rules” in one page

Create a short `docs/repo-layout.md` defining:

- what belongs in each top-level directory,
- where generated files go,
- where experiments go,
- what must be archived vs deleted.

## 2-Week Low-Risk Rollout

### Week 1

1. Create target top-level folders (`apps`, `knowledge`, `archive`, `docs`, `scripts`).
2. Move `__predecessors` to `archive/predecessors`.
3. Add path migration notes and shell aliases/symlinks if needed.

### Week 2

1. Choose canonical “awesome” tree and remove duplicates.
2. Move `MASTER/docs` and `MASTER/knowledge` into new homes.
3. Enforce placement/depth checks in CI (warning-only first).

## Success Metrics

- 25-40% fewer files in the active working set (`apps + scripts + docs`).
- >80% reduction in duplicate files across `study/` and `MASTER/knowledge/`.
- Median path depth reduced by at least 1 level.

