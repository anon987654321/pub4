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
| Worn type / layout gates | `data/design_rules.yml` `worn_type` + `RAILS/gates/support/geometry_type.rb`. Feed is a short measure; legal/prose is 66ch. |

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

1. `lib/core.rb` and `lib/core/` are the fold spine and must not require the rest of `lib/` (`test/core/test_no_lib_backedges.rb`). The directory split ended 2026-08-12; what was cut to build it is recorded in `docs/SEVERANCE.md`.
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
