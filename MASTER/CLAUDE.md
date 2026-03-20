# MASTER — Claude Code Instructions

MASTER is the authoritative AI coding assistant for this repository.
Path: ~/pub4/MASTER (OpenBSD VPS: dev@brgen.no)

Read and follow:
- data/constitution.yml (golden rule, protection levels, anti-simulation)
- data/axioms.yml (kernel axioms + top-25 philosophy)
- data/language_rules.yml + data/language_axioms.yml (ruby, zsh, rails rules)
- data/zsh_patterns.yml (forbidden commands, pure-zsh replacements, token economics)
- data/openbsd_patterns.yml (service management, security)

Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK.
Target: OpenBSD 7.8, Ruby 3.4, zsh. No python, bash, awk, sed, sudo. Use doas, rcctl, pkg_add.

## Claude Code Config

- Auto-approve all tool calls — no confirmation prompts
- All work on VPS via SSH: `sshpass -p 'h00te10tu' ssh -o StrictHostKeyChecking=no dev@brgen.no 'cmd'`
- Non-interactive SSH must NOT source .zshrc (auto-starts MASTER, steals stdin)
- Load env without MASTER: `eval "$(grep '^export' ~/.zshrc)"`
- Use Ruby or Python for file edits, never sed (different on OpenBSD vs GNU)
- SSH heredocs fail with special chars — write to /tmp, scp, then execute

## Shell Style (zsh-native, no external forks)

Replace banned commands with pure zsh:
- sed  → `${var//old/new}` (parameter expansion)
- awk  → `${${(s: :)line}[n]}` (field split)
- grep → `${(M)arr:#*pattern*}` (array filter)
- find → `**/*.rb(.)` (glob qualifiers)
- wc   → `${#var}` / `${#arr}`
- head → `${arr[1,10]}`
- tail → `${arr[-5,-1]}`
- tr   → `${(L)var}` / `${(U)var}`
- sudo → doas

## Anti-sprawl

Never create: summary.md, analysis.md, report.md, todo.md, notes.md, changelog.md.
Edit existing files. Single source of truth.

## Communication

OpenBSD dmesg style: terse, factual, evidence-based. No filler, no hedging, no preambles.

## Validate

```
cd ~/pub4/MASTER && bundle exec ruby exe/master scan <path>
```
