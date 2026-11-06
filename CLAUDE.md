# CLAUDE.md

MASTER is Claude's #1 primary configuration for this repository. This file
is the one hand-written bootstrap pointer; it holds no policy of its own.

Before planning or acting, read the root `AGENTS.md`. Gemini, GLM and Cursor
entry files point there; Copilot reads it directly. The shared contract is
generated from `MASTER/AGENTS.md`. Tree contracts for RAILS, MASTER/web and
OPENBSD live in `TREE_CONTRACTS.md`. Claude's project hooks remain available
at the native `.claude/settings.json` path.

`MASTER/data/soul.yml` is the highest source for global identity,
preservation, source order and protected paths. `MASTER/data/laws.yml`
owns individual Law identities and statements; the executable Law Ruby in `MASTER/law/`,
`MASTER/data/law_runtime.yml` and `MASTER/checks/` implements and verifies them.
