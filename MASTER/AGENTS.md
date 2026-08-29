# Agents

Task-scoped entry for coding agents (Cursor, Codex, Grok, Claude Code). Full contract: `START_HERE.md`.

**Read the repo-root `CLAUDE.md` first.** It is the authority above this file —
the order is `MASTER/data/soul.yml` > `MASTER/data/rules.yml` > `CLAUDE.md` >
the per-tree contract — and it carries the five traps that cost the most time
here. This file routes; it does not restate, because a second copy drifts and
the copy is always the one being read.

## Working alone in this repo

An agent arrives with none of the session context that makes the tree
navigable, so these are the facts that are not deducible from the code and
that a fresh agent gets wrong on its first attempt.

**Ruby is pinned to 3.4.9.** Run everything as
`RBENV_VERSION=3.4.9 rbenv exec ruby ...`. Bare `ruby` picks up whatever is on
PATH; `RAILS/gates/runner.rb` prints a one-line warning about it and carries on,
so app-bundle gates then fail for the interpreter rather than for a finding.

**The checkout is shared and usually dirty.** Never `git add -A`. Commit
path-scoped: `git commit -- <paths>`. When the pre-commit hook refuses over
untracked files that are not yours, `PUB4_UNTRACKED=1 git commit -- <paths>`
says so explicitly.

**Never read-modify-write a file another session may hold.** Read, edit and
write is three moments; a commit landing between the read and the write is
silently reverted by your write. To publish safely: `git fetch origin`,
`git worktree add -q ../pub4-<name> origin/main --detach`, apply there, commit,
`PUB4_PUSH_ALL=1 git push origin HEAD:main`, then `git worktree remove --force`
and `git worktree prune`. Delete the worktree in the same session that made it.

**Verify the instrument before the finding.** Measurement code here is wrong
about the code more often than the code is wrong about the world. Check a probe
against a case whose answer is already known before believing what it reports,
and never report a check as done without its output.

**Comments state the present-tense reason.** Dates and "used to be" belong in
git — `NO_CHANGELOG_COMMENT` in `law/universal.rb` enforces it.

**The RAILS apps default to Norwegian.** Assert through I18n keys, never
English literals; a hardcoded English string is a defect, not a placeholder.

**Renders are irreplaceable.** dilla and postpro write real output with
rotating seeds. Never render over a take that matters, and never change a
rendered-sound or graded-look default on your own judgement.

## Judging your own work

The task as given is the deliverable, but it is not the whole job. Reason about
what the change is actually for, and say what you find.

A finding is a hypothesis. Several entries in `TODO.md` were stale within a day
of being written — the price-drop alerts, the takeaway push and three map layers
were all built while the file still called them open. Re-measure before working
from one, and prefer a small measurement over a long argument.

If the task as specified is wrong, or rests on a premise the tree contradicts,
say so in a sentence or two and then deliver the rest under a stated assumption.
Do not silently narrow the scope, and do not stop with nothing delivered because
one part was doubtful. Scaling the work down is the operator's call.

Report what happened rather than what was hoped for. If a check was skipped, say
which. If a gate reported a pass having measured nothing — several here do when
the triangle is down — that is not a pass, and calling it one is worse than
failing.

## When it goes wrong

Nothing in this repo is so urgent that it is worth destroying someone else's
work, and the failure modes below have all actually happened.

**Before anything destructive, keep the bytes.** Copy the file somewhere outside
the tree first. A hash proves a change occurred; only the bytes let you put it
back.

**If you overwrote another session's work**, their commits are safe on
`origin/main` — the damage is only in the working tree. `git checkout -- <path>`
restores from HEAD. Say what you did rather than hoping it is unnoticed.

**Before any push**, `git log --oneline origin/main..HEAD`. A push publishes
every commit beneath yours, including other people's. Name in your report what
went with you.

**`/fix` mutates the tree** and has broken dilla, postpro and MASTER's own chat
path. Read the printed diff before committing, and never commit rewrites of
generated caches — the scanner descends into them.

**A red gate that names no finding is usually a gate that cannot load.**
`rails_runtime` failed at `require` time for months and read as a normal
failure. Check the gate before chasing its verdict.

**When you cannot verify, stop and say so.** An unverified claim costs more than
an unfinished task, because the next reader builds on it.

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
