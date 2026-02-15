# MASTER2 — Constitutional AI Code Quality System

Any LLM working in this repository must read, internalize, and follow MASTER2.

## Core files (read in order)

1. `data/constitution.yml` — golden rule, convergence, anti-sprawl, constraints, detectors
2. `data/axioms.yml` — 68 axioms across 11 categories (every code change must satisfy relevant axioms)
3. `data/language_axioms.yml` — detection rules and philosophy for ruby, rails, zsh, html, css, js
4. `data/zsh_patterns.yml` — banned commands, auto-remediation, token economics
5. `data/openbsd_patterns.yml` — service management, forbidden commands, platform mappings
6. `data/council.yml` — 12 adversarial personas (3 have veto power)
7. `data/quality_thresholds.yml` — minimum quality scores and enforcement levels

## Golden rule

PRESERVE_THEN_IMPROVE_NEVER_BREAK

Never delete working code. Never break existing behavior. Improve surgically.

## Platform

OpenBSD 7.8, Ruby 3.4, zsh. No python, no bash, no awk, no sed, no sudo, no find, no wc, no head, no tail. Use doas, rcctl, pkg_add. Pure zsh parameter expansion for all string and array operations.

## Architecture

Deploy scripts in `deploy/` contain Ruby/Rails apps embedded in zsh heredocs. This is the single source of truth. Edit in-place with atomic precision. Never extract heredoc content to separate files.

Rails apps use Hotwire, Turbo, Stimulus, Solid Queue. Monolith first. Convention over configuration.

## Banned patterns

- `rescue nil` — always rescue specific exceptions
- File sprawl — never create summary.md, analysis.md, report.md, todo.md, notes.md, changelog.md
- ASCII decoration comments (`# ====`, `# ----`, `# ****`)
- Comments that restate the code
- Files over 300 lines (split along module boundaries)
- Trailing whitespace
- More than 2 consecutive blank lines

## Communication style

OpenBSD dmesg-inspired. Terse, factual, evidence-based. No filler, no hedging, no unnecessary formatting. Show what changed and why.

## How to apply

Before modifying any file in this repository:
1. Check which axioms apply to the change
2. Check language_axioms.yml for language-specific rules
3. Verify the change preserves existing behavior
4. Verify no banned patterns are introduced
5. Keep files small, comments minimal, code self-documenting
