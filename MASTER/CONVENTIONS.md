# Conventions

This document orients external LLMs to how MASTER is written and operated. The full rule index is in `data/CANON.md`; inviolable law is in `data/soul.yml` and `data/rules.yml`.

MASTER is a constitutional AI agent in Ruby 3.4+ on OpenBSD. It is general-purpose, and every change must leave the system deployable. The golden rule is `PRESERVE_THEN_IMPROVE_NEVER_BREAK`: read before write and patch minimally.

Evidence is mandatory. Do not claim intent without proof. Ban hedges such as `will`, `would`, `could`, and `might` unless backed by command output, a diff, or a file hash.

Voice splits by audience. Log and boot lines are terse, lowercase, and kernel-ish. Operator replies use plain English, proper casing, and outcome-first sentences. Commits are active, concrete, and Strunk-tight. No banner art—no `===` or `---` dividers in prose, no `[ok]` brackets. Use `ok:`, `err:`, and `warn:` instead.

Ruby style requires `# frozen_string_literal: true`, double-quoted strings, and no bare `rescue`. Prefer guard clauses, command-query separation, and the `Result` monad between pipeline stages. Named constants and thresholds belong in `data/rules.yml`. Do not abbreviate (`index`, not `idx`). Keep files at or below three hundred lines, methods at or below ten lines, and nesting at or below two levels.

Rails views should prefer `tag.*` and `t()` for dynamic markup, semantic HTML and tag selectors over class soup, and helpers for CSRF, Turbo, and escaping rather than hand-rolled forms.

Shell discipline on zsh and SSH bans `sed`, `awk`, `grep`, `find`, `head`, `tail`, `wc`, `sudo`, and Python. Use Ruby, `doas`, and zsh builtins. Read whole files with `cat`.

Architecture follows the pipeline from Intake through Render, with Council and Lint running in parallel under thirty seconds. Rules auto-register from `judge/scan/rules/`. Scan before structural edits.

On the VPS, connect as `dev@46.23.89.226` with `ruby34` and `bundle34`. After deploying changes under `MASTER/web/`, run `doas rcctl restart master`. Operator detail is in `DEPLOY/OPERATOR.md`.

Documentation in MASTER markdown follows GitHub-style prose: a short introductory paragraph, one or two follow-up paragraphs, no fenced code blocks, and no bullet or numbered lists. Skills, tool READMEs, principles, and operator docs should read as one voice. Put the operative rule in the opening paragraph; use the second paragraph for context and exceptions only.