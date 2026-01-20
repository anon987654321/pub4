# Copilot Instructions

You are working on the Convergence project. Always read and follow `master.yml` in the repository root.

## Golden Rule

**preserve_then_improve_never_break**

## Banned Tools (use alternatives)

| Banned | Use Instead |
|--------|-------------|
| python | ruby |
| bash | zsh or /bin/sh |
| sed | `${var//pattern/replacement}` |
| awk | `ruby -e` or zsh parameter expansion |
| grep | `${(M)lines:#*pattern*}` |
| wc | `${#var}` or `${(w)#var}` |
| head | `${lines[1,5]}` |
| tail | `${lines[-5,-1]}` |
| sort | `${(o)arr}` |
| find | `**/*` glob patterns |
| sudo | `doas` |

## Anti-Truncation (NEVER output these)

- `...`
- `rest_of_code`
- `[truncated]`
- `TODO:`
- `FIXME:`
- `XXX:`
- `HACK:`

If content is too long, chunk it across multiple responses. Never truncate.

## Thresholds

- Function: ≤20 lines
- Class: ≤250 lines
- File: ≤400 lines
- Nesting: ≤3 levels
- Cyclomatic complexity: ≤10
- Parameters: ≤3

## Code Style

- Ruby: double quotes, 2-space indent, guard clauses
- Shell: `set -euo pipefail`, zsh native patterns
- YAML: 2-space indent, max 3 nesting levels
- OpenBSD: doas, rcctl, pledge/unveil compatible

## Evidence Required

- File reads: include SHA256 hash prefix
- Modifications: show unified diff
- Completions: provide output with evidence

## Workflow Phases

1. **Discover** - understand the problem
2. **Analyze** - make implicit explicit
3. **Constrain** - map boundaries
4. **Ideate** - generate 15 alternatives
5. **Evaluate** - select with evidence
6. **Design** - plan before implementing
7. **Validate** - prove it works
8. **Deliver** - ship and learn

## Rails Stack

- Rails 8 with Hotwire (Turbo + Stimulus)
- Solid Queue, Solid Cache, Solid Cable
- Kamal for deployment
- PostgreSQL

## OpenBSD Conventions

- Use `/usr/local/` paths
- Use `doas` not `sudo`
- Use `rcctl` for services
- Prefer `pledge` and `unveil` compatible code
- Use `arc4random`, `strlcpy`, `reallocarray`

## Communication Style

- Terse, OpenBSD dmesg-like output
- Results first, silent success, loud failure
- No timestamps, no excessive emoji
- No preamble or filler words
