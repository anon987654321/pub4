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

## The words that mean something specific here

Not general vocabulary. Each of these means one thing in this tree and something
else everywhere else, and each has a file behind it, so a claim about one can be
checked rather than believed.

**Law** and **rule** are not synonyms. A *law* is an executable detector in
`law/*.rb` that carries a `bad` and a `good` fixture and proves itself against
both before it is allowed to judge anything — 122 of them, reaching the scanner
through `LawBridgeRule`. A *rule* is a row in `data/rules.yml` or a class in
`lib/review/scan/rules/`, and neither has to prove anything to load. Where an id
exists in both, the law wins: `YamlDeclarativeRule` rejects the row before
reading it.

**Conduct** is what `Law.conduct` does to a law file before laws judge `law/`.
A law necessarily contains the pattern it forbids — in its detector, its fix
line and its bad fixture — so those are blanked, newlines kept, and the file is
read as declaration rather than as the thing it declares.

**Twin.** One rule id implemented in two places. Every silent drift the
2026-08-21 campaign found was a twin: two implementations under one name, one of
them quietly wrong. Retiring a twin means deleting the copy and leaving a note
where it stood.

**Intentional marker.** A line carrying `scan: intentional` opts that line out
of every law and of every registry rule that scans through `Rule#scan_lines`,
and must carry the reason beside it. It is the sanctioned way to
say "this finding is correct and the code is right anyway". A marker that
suppresses nothing is worse than none: it is a standing exemption for whatever
real finding lands on that line next.

**The fold** and **the spine** are `lib/core/` — the small set of files the
runtime is built out of, where a new top-level concept is a design change rather
than a line-count question. `data/spine.yml` holds both invariants, and
`rake lint:spine` fails when either moves.

**Ratchet** and **census**. A *census* counts a property over the tree —
duplicate files, unread data keys, findings, readers per file. A *ratchet* is a
census with a recorded ceiling that only ever falls, so the next regression
cannot arrive silently. Every census here records its members beside the count,
because a ceiling that says "over by two" and cannot name the two leaves the
next reader deriving the pair by hand.

**Inconclusive** is the third gate state, and the one that matters. A gate that
could not measure — no Chrome, no booted app, no deploy stamps — is neither a
pass nor a failure, and reporting it as a pass is the worst failure this suite
has: it claims the code was reviewed when nothing was read. In-process gates say
it with `GateResult#inconclusive!`, subprocesses with exit 3.

**Verdict.** What the constitution answers a proposed effect with, and there are
four: `Block` refuses with a reason, `Request` stops to ask a person, `Revise`
hands back an amended effect, `Allow` applies it against a checkpoint. Nothing
touches disk on any other path.

**Tier.** Two meanings, both live. `bin/gate` runs a *lexical* tier (law and the
scan registry, deterministic, no model) and a *semantic* tier (`/critique` and
`/review`, which reach a provider); the semantic one is currently unreachable
and reports as skipped rather than clean. On a `rules.yml` row, `tier:` is the
rule's category — `clean_code`, `style`, `safety` — and is what resolves a
conflict between two rules firing on one line.

**The triangle** is `RAILS/bin/triangle`: brgen, amber, bsdports and the MASTER
face, booted locally on the ports every gate probes. Without it the live half of
the suite passes having measured nothing.

**Vertical.** One of brgen's mounted Rails engines — `RAILS/brgen/engines/`
holds tv, dating, takeaway, playlist, marketplace and maps. Each is a named app on its own subdomain, not a section
of brgen, and "brgen" alone means the main city app only.

**The face** is MASTER's WebGL front end at `ai.brgen.no`. Its runtime is
generated: `web/public/face.part*.txt` are the sources and
`web/public/face.runtime.js` is the build, which says in its own first line not
to edit it by hand. Editing the build is a fix that survives until the next
`assets:build_face_runtime` and then vanishes.

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
