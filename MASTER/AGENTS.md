# Agents

Task-scoped entry for coding agents (Cursor, Codex, Grok, Claude Code). Full contract: `START_HERE.md`.

## Pick your topic

| Task | Read |
|------|------|
| Face boot / WebGL / primer | `data/agent_map.yml` → `topics.face_boot` |
| TTS / speech / visemes | `topics.tts` |
| Deploy / VPS / rc.d | `topics.deploy` |
| Persona / voice policy | `topics.persona` |
| Law / scanners / loop | `START_HERE.md` → Data File Budget; all scanner law is `data/rules.yml` |
| Extend runtime behavior | `DECISIONS.md` → One Spine. New ability in the fold = one Effect verb in `lib/core/world.rb`; new constraint = one rule in `lib/core/constitution.rb`; anything else is ordinary `lib/` and must not grow it (`rake lint:spine`) |
| Worn type / layout gates | `data/rules.yml` `design_rules.worn_type` + `RAILS/gates/support/geometry_type.rb`. Feed is a short measure; legal/prose is 66ch. |
| brgen city network / verticals | `RAILS/brgen/AGENTS.md` — one process, city apex + subdomain engines |

Touch-map: `data/agent_map.yml`. Law sections live in `data/rules.yml`. Work is a sentence, or `/through [path]`. Slash set: `/through` `/status` `/undo` `/commit` `/model` `/pair` `/doctor` `/help` `/clear`.

## Checks

Run the smallest proof in `START_HERE.md` "Checks by change type". On failure: `bin/check --profile=agent --format=brief`.

`--profile=agent` may fail on known debt tagged `agent-ignore` in the repo-root `TODO.md`. Do not chase scan noise on unrelated patches.

## Do not touch

`START_HERE.md` "Do Not Touch". Isolated checkout if more than one agent is in the repo: `MASTER/bin/pub4 worktree <name>` → work in `../pub4-<name>`. The shared tree has one git index; `git commit -a` sweeps other sessions into your commit. Path-scoped commits (`git commit -- <paths>`) are the minimum if you must share a tree.

## Patch closeout

Match `EXAMPLES.md`: what changed, exact checks run, known debt called out explicitly.
