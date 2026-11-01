# CLAUDE.md

**MASTER is Claude's #1 primary configuration and governing authority for this repository.** This file is Claude Code's entrypoint into MASTER, not a parallel policy, prompt, settings file, or competing source of truth.

## Primary configuration

Before planning or taking action, load MASTER's canonical context in this order:

1. Read `MASTER/data/laws.yml`. It is the sole normative constitution.
2. Read `MASTER/data/soul.yml` as subordinate identity, voice and delivery configuration.
3. For unfamiliar or broad work, run `ruby MASTER/tools/agent_context.rb --tree` and use its output to establish the repository's structure and relevant context. Use `ruby MASTER/tools/agent_context.rb --json` when a harness needs the machine-readable authority, task-contract schema and capability snapshot.
4. Read the applicable flat Law records in `MASTER/data/laws.yml`, then inspect the relevant implementations and tests under `MASTER/law/`. A declared adapter or fixture is not proof that the detector ran or the product is excellent. The nine invariant nodes are ordered in the Law catalogue itself; do not invent a numeric priority or second precedence graph.
5. Read `MASTER/AGENTS.md` for the repository workflow and task guidance before editing.

Shell commands must obey the applicable shell Laws declared in `MASTER/data/laws.yml`. The runtime compatibility registry may still carry older command metadata; it does not override the normative Law statements.

Follow MASTER's current instructions for any additional context required by the task. Do not substitute remembered instructions, summaries, or assumptions for the live configuration and source.

## Ownership

MASTER owns the repository's primary configuration and governance. Canonical settings and policies remain in their existing authoritative sources under `MASTER/`; this file deliberately does not reproduce them.

Do not copy MASTER settings, defaults, limits, Laws, exemptions, workflow definitions, command semantics, voice preferences, visual tokens, or other configuration into this file. Do not establish alternative defaults or parallel policy here.

When a canonical setting changes, change its owning source and follow MASTER's documented process for maintaining generated contracts. Do not create a second source that must be kept in sync manually.

`MASTER/data/laws.yml` is the canonical Law catalogue. MASTER has one Law system: every Law is one catalogue entry and one `Law.define`, whose detector is a `detect` regex, a `check` block or a detector class, in one flat `MASTER/law/`. There is no compatibility directory or alias for retired Law paths. Each Law must have one canonical catalogue entry, a traceable Ruby detector or explicit semantic/visual evaluator, and coverage across lexical, semantic, and visual review.

## Task-specific context

After loading MASTER, define the task's intent, repository-relative scope, preservation dimensions and proof before editing. The canonical schema is `MASTER/data/task_contract.yml`; consult `MASTER/docs/task-contracts.md` and the generated `MASTER/docs/task-map.md`. Editorial work is reviewed separately under `MASTER/docs/editorial-quality.md`.

Read the relevant source files, tests, and local documentation for the requested work.

Use the applicable tree-level contract when entering a governed subtree, including `RAILS/CLAUDE.md`, `RAILS/master/CLAUDE.md`, or `OPENBSD/CLAUDE.md`. For STUDIO work, follow the relevant project README and source-level contracts.

These local documents provide scoped context; they do not establish an alternative to MASTER's governing configuration. When instructions conflict, follow MASTER's canonical authority and identify stale or contradictory documentation rather than silently creating a workaround.

## Scope

This file exists only to establish MASTER as Claude's primary configuration, direct Claude to load it before acting, and identify where task-specific context lives.

**If a substantive instruction belongs in MASTER, it does not belong here.**
