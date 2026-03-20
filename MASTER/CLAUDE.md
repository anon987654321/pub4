# MASTER — Claude Code Instructions

MASTER is the constitutional AI coding assistant for this repository.
Path: ~/pub4/MASTER (OpenBSD VPS: dev@brgen.no)

## Source of Truth

MASTER is its own primary config. Read these data files — they govern everything:

| File | Purpose |
|---|---|
| `data/constitution.yml` | Golden rule, protection levels, anti-simulation, communication style |
| `data/axioms.yml` | Kernel axioms + top-25 philosophy |
| `data/workflow.yml` | Operational rules: file reading, before-edit checklist, scan depths, autoloop config |
| `data/principles.yml` | Design principles (KISS, DRY, YAGNI, SOLID, etc.) |
| `data/language_rules.yml` + `data/language_axioms.yml` | Ruby, zsh, Rails rules |
| `data/strunk.yml` | Prune/prose patterns |
| `data/scan_depths.yml` | Which rules run at each depth |

Golden rule: `PRESERVE_THEN_IMPROVE_NEVER_BREAK` (from data/constitution.yml).
Target: OpenBSD 7.8, Ruby 3.4, zsh. Use doas, rcctl, pkg_add. No python, bash, awk, sed, sudo.

## SSH Access

All work on VPS via SSH:
```sh
sshpass -p 'h00te10tu' ssh -o StrictHostKeyChecking=no dev@brgen.no 'cmd'
```
Non-interactive SSH must NOT source .zshrc (auto-starts MASTER, steals stdin).
Load env without MASTER: `eval "$(grep '^export' ~/.zshrc | grep -v '\!')"`

## Quick Rules (see data/workflow.yml for full detail)

- Read complete files — never grep/head/tail to understand code
- Read every affected file before editing any file
- Write fixes to /tmp and scp — never use SSH heredoc for multi-line Ruby
- `ruby -c <file>` after every write; `ruby -e "require_relative 'lib/master'"` after every commit
- No hardcoded constants — prose/patterns/config → data/*.yml
- Result monad: `respond_to?(:ok?)` not `is_a?(Result)` for duck-typing
- Autoloop scans at :standard depth (fast); sweep uses :deep per-file with full context

## Validate

```sh
cd ~/pub4/MASTER
ruby -c lib/master/FILE.rb
ruby -e "require_relative 'lib/master'; puts 'ok'"
bundle exec ruby exe/master scan lib/master/FILE.rb
```
