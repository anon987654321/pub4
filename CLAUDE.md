# CLAUDE.md

**MASTER is Claude's #1 primary configuration and governing authority for this repository.** This file is Claude Code's entrypoint into MASTER, not a parallel policy, prompt, settings file, or competing source of truth.

## Primary configuration

Before planning or taking action, load MASTER's canonical context in this order:

1. Read `MASTER/data/soul.yml`.
2. Read `MASTER/data/laws.yml`.
3. For unfamiliar or broad work, run `ruby MASTER/tools/agent_context.rb --tree` and use its output to establish the repository's structure and relevant context.
4. Read the applicable Law entries in `MASTER/data/laws.yml`, and each Law's one `Law.define` under `MASTER/law/` or `MASTER/law/detectors/`. The catalogue entry holds the operator's decisions about a Law (severity, lifecycle, autofix permission, scope and exemptions); the `Law.define` holds what makes its detector correct (the detector, its fixtures or the test that proves it, its tags and repair transform). Neither restates the other.
5. Read `MASTER/AGENTS.md` for the repository workflow and task guidance before editing.

Shell commands obey `MASTER/data/laws.yml` `zsh.banned_commands`; the PreToolUse hook in `.claude/settings.json` refuses a command that breaks it and names the replacement.

Follow MASTER's current instructions for any additional context required by the task. Do not substitute remembered instructions, summaries, or assumptions for the live configuration and source.

## Ownership

MASTER owns the repository's primary configuration and governance. Canonical settings and policies remain in their existing authoritative sources under `MASTER/`; this file deliberately does not reproduce them.

Do not copy MASTER settings, defaults, limits, Laws, exemptions, workflow definitions, command semantics, voice preferences, visual tokens, or other configuration into this file. Do not establish alternative defaults or parallel policy here.

When a canonical setting changes, change its owning source and follow MASTER's documented process for maintaining generated contracts. Do not create a second source that must be kept in sync manually.

`MASTER/data/laws.yml` is the canonical Law catalogue. MASTER has one Law system: every Law is one catalogue entry and one `Law.define`, whose detector is a `detect` regex, a `check` block or a detector class under `MASTER/law/detectors/`. There is no compatibility directory or alias for retired Law paths. Each Law must have one canonical catalogue entry, a traceable Ruby detector or explicit semantic/visual evaluator, and coverage across lexical, semantic, and visual review.

## Task-specific context

After loading MASTER, read the relevant source files, tests, and local documentation for the requested work.

Use the applicable tree-level contract when entering a governed subtree, including `RAILS/CLAUDE.md`, `RAILS/master/CLAUDE.md`, or `OPENBSD/CLAUDE.md`. For STUDIO work, follow the relevant project README and source-level contracts.

These local documents provide scoped context; they do not establish an alternative to MASTER's governing configuration. When instructions conflict, follow MASTER's canonical authority and identify stale or contradictory documentation rather than silently creating a workaround.

## Scope

This file exists only to establish MASTER as Claude's primary configuration, direct Claude to load it before acting, and identify where task-specific context lives.

**If a substantive instruction belongs in MASTER, it does not belong here.**
