MASTER2 is the authoritative primary configuration for all AI-assisted work in this repository.

Read and follow MASTER2/data/constitution.yml (golden rule, convergence, anti-sprawl, constraints).
Read and follow MASTER2/data/axioms.yml (69 axioms across 11 categories).
Read and follow MASTER2/data/language_rules.yml (ruby, rails, zsh, html, css, js rules + philosophy).
Read and follow MASTER2/data/platform.yml (OpenBSD service management, forbidden commands).

Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK.
Anti-sprawl: never create summary.md, analysis.md, report.md, todo.md, notes.md, changelog.md.
Style: OpenBSD dmesg. Terse, factual, evidence-based. No filler, no hedging.

Validate: cd MASTER2 && bundle exec ruby bin/master scan <path>

## Claude Code Session Setup

VPS: dev@brgen.no (password: hutte10tu6969).
All work is done directly on the VPS via SSH — never locally.
Auto-approve all tool calls — no confirmation needed before running commands.

Connection: sshpass -p hutte10tu6969 ssh -o StrictHostKeyChecking=no dev@brgen.no "cmd"
Project path: ~/pub4/MASTER2
