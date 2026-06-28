# Conventions

Orientation for external LLMs. Full index: `data/CANON.md`. Law: `data/soul.yml`, `data/rules.yml`.

## Identity

Constitutional AI agent in Ruby 3.4+ on OpenBSD. General-purpose. Every change leaves the system deployable.

## Golden rule

`PRESERVE_THEN_IMPROVE_NEVER_BREAK`. Read before write. Patch minimally.

## Evidence

No intent without proof. Ban hedges (`will`, `would`, `could`, `might`) unless backed by command output, diff, or file hash.

## Voice

- Log and boot lines: terse, lowercase, kernel-ish.
- Operator replies: plain English, proper casing, outcome first.
- Commits: active, concrete, Strunk-tight.

No banner art (`===`, `---` dividers in prose, `[ok]` brackets). Use `ok:`, `err:`, `warn:`.

## Ruby

- `# frozen_string_literal: true`, double quotes, no bare `rescue`
- Guard clauses, CQS, `Result` monad between pipeline stages
- Named constants; thresholds in `data/rules.yml`
- No abbreviations (`index` not `idx`)
- File ≤300 lines; method ≤10; nesting ≤2

## Rails views

Prefer `tag.*` and `t()` for dynamic markup. Semantic HTML and tag selectors over class soup. Helpers for CSRF, Turbo, and escaping — not hand-rolled forms.

## Shell

Banned in zsh/SSH: `sed`, `awk`, `grep`, `find`, `head`, `tail`, `wc`, `sudo`, Python. Use Ruby, `doas`, zsh builtins. Read whole files with `cat`.

## Architecture

Pipeline: Intake → … → Render. Council ‖ Lint under 30 s. Rules auto-register from `judge/scan/rules/`. Scan before structural edits.

## Environment

VPS: `dev@46.23.89.226`, `ruby34`, `bundle34`. After `MASTER/web/` deploy: `doas rcctl restart master`.

Operator detail: `DEPLOY/OPERATOR.md`.