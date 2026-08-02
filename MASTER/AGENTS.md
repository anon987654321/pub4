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

## Concurrent agents — take your own worktree

If more than one agent works this repo at once, each one takes an isolated git
worktree first: `sh OPENBSD/dev/agent_worktree.sh <your-name>` → work in
`../pub4-<name>` → push your branch → integrate to `main` by fast-forward/PR. The
default shared checkout has ONE git index, so concurrent edits collide: a
`git commit -a` sweeps another agent's half-finished work into your commit, an
autofix rewrites a file another agent is mid-edit on, and interleaved writes have
produced silently corrupt files (a `CONTROL_CHARS` scan rule now catches that).
Path-scoped commits (`git commit -- <paths>`) are the minimum if you must share a
tree; a worktree removes the whole hazard.

## Patch closeout

Match `EXAMPLES.md`: what changed, exact checks run, known debt called out explicitly.
