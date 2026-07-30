# Agents

Task-scoped entry for coding agents (Cursor, Codex, Grok, Claude Code). Full contract: `START_HERE.md`.

## Pick your topic

| Task | Read |
|------|------|
| Face boot / WebGL / primer | `data/agent_map.yml` → `topics.face_boot` |
| TTS / speech / visemes | `topics.tts` |
| Deploy / VPS / rc.d | `topics.deploy` |
| Persona / voice policy | `topics.persona` |
| Law / scanners / loop | `START_HERE.md` → Data File Budget; do not merge `data/rules/*.yml` |
| Extend runtime behavior | `DECISIONS.md` → Two Master Spines. New ability inside `core/` = one Effect verb in `core/world.rb`; new constraint = one rule in `core/constitution.rb`; anything else is `lib/` and must not grow it (`rake lint:spine`) |

CLI dump: `/orient agent_map` · per-file brief: `/orient patch <path>` (e.g. `/orient patch web/public/face.js`).

## Checks (run the smallest proof)

| Change | Command |
|--------|---------|
| Ordinary code | `bin/check` |
| Law / scanners / loop | `bin/check --profile=agent` |
| Web face / assets | `bin/check --profile=web` |
| Loader / release | `bin/check --profile=full` |

On failure, use structured hints: `bin/check --profile=agent --format=brief`

`--profile=agent` may fail on **known debt** (`rake selftest`) — tag `agent-ignore` in `DEBT.md`. Do not chase scan noise on unrelated patches.

## Do not touch (unless the task requires it)

1. Do not merge `lib/` and `core/`. The two spines are permanent — see `DECISIONS.md`; what was cut to build `core/`, and what survived the attempt, is recorded in `core/SEVERANCE.md`.
2. Do not fold `data/rules/*.yml` into `rules.yml` without retuning scanners.
3. Do not commit `knowledge/`, `output/`, `.master/`.
4. No WebGL before primer tap (`web/app/views/chat/index.html.erb`).
5. `tools.yml` lists Repligen/Postpro for slash commands — not LLM-native tools; media routes via `Io::MediaIntent`.

## Patch closeout

Match `EXAMPLES.md`: what changed, exact checks run, known debt called out explicitly.
