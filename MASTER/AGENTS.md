# Agents

Task-scoped entry for coding agents (Cursor, Codex, Grok, Claude Code). Full contract: `START_HERE.md`.

**Read the repo-root `CLAUDE.md` first.** It is the authority above this file —
the order is `MASTER/data/soul.yml` > `MASTER/data/rules.yml` > `CLAUDE.md` >
the per-tree contract — and it carries the five traps that cost the most time
here. This file routes; it does not restate, because a second copy drifts and
the copy is always the one being read.

The block below is the source every other agent's entry file is generated from
— root `AGENTS.md`, `GEMINI.md`, `.cursorrules` and
`.github/copilot-instructions.md`. Edit it here and run
`cd MASTER && rake docs:agent_contracts`; `rake lint:agent_contracts` fails when
a generated file drifts from it. One source, four harnesses, no second copy to
rot.

## The contract every agent gets

<!-- agent-contract:begin -->
pub4 is governed by MASTER, and MASTER's law is data, not prose. Read it before
you write:

1. `MASTER/data/soul.yml` — the kernel. Absolutes, work rules, anti-simulation.
2. `MASTER/data/rules.yml` — the declared rule catalogue, in four scopes.
3. `MASTER/law/*.rb` — the domain law, each rule carrying the example it must
   flag and the one it must not. Those two examples are the rule.
4. `MASTER/lib/review/scan/rules/*.rb` — the registry, the rest of the detectors.

That order is the authority order, and it outranks every per-agent instruction
file including this one. A harness file (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`,
`.cursorrules`, `.github/copilot-instructions.md`) is a pointer at the law, never
a second copy of it: the copy is always the one being read, and it is always the
one that drifted.

The four trees, and how each is entered:

- `MASTER/` — a constitutional AI runtime in pure Ruby. `MASTER/bin/master "<instruction>"`.
- `RAILS/` — brgen (a city social network, verticals as mounted engines), amber, bsdports. `RAILS/bin/triangle up`.
- `OPENBSD/` — the deploy pipeline and the VPS runbook. Production is one box, vm23.
- `STUDIO/` — dilla makes beats, postpro grades images, repligen and lora generate.

Two commands cover most work. `MASTER/bin/operator gate` runs the whole ladder over
all four trees; `MASTER/bin/operator measure` prints every ratchet with its ceiling.
Run the smallest check that proves the work, and never report done without its
output.

Inside the runtime there is one verb: `/through [path]` — scan, critique,
principle map. `--only <stage>` runs one of them, and `/scan`, `/fix`,
`/critique` and `/council` are those stages by name. **The scan stage fixes what
it finds, on the spot**, so a scan writes to the tree unless `--no-autofix` or
`--dry-run` holds it back.

Five things that will bite you, in order:

1. The checkout is shared. Commit path-scoped with `git commit -- <paths>`, and
   take a worktree for anything past a one-file edit.
2. Strict loading is on in every Rails environment, test and production alike.
3. A deploy sheds amber and bsdports while relayd keeps answering TLS, so the
   outage looks like a hang rather than a 5xx.
4. The apps default to Norwegian. Assert through I18n keys, never English
   literals.
5. dilla and postpro renders are irreplaceable. Never render over a take, and
   never change a rendered-sound default on your own judgement.

Two habits this repo learned the hard way. **Verify the instrument before the
finding** — naive pattern-matching over this tree produces mostly false
positives, and a census that is wrong is worse than no census. **A comment
states the present-tense reason**, not what the code used to do; git holds that.

`ruby MASTER/tools/agent_context.rb` prints the law in force in six kilobytes:
the 47 conduct rules a detector cannot describe, the rules that can refuse a
write, and how many run without a model. Read it when the full catalogue will
not fit.

Ruby is pinned to 3.4.9: run `RBENV_VERSION=3.4.9 rbenv exec ruby ...`.

## Ruby and zsh, never the GNU text tools

`sed`, `awk`, `tr`, `cut`, `find`, `head`, `tail`, `wc`, `perl`, `python` and
`bash` are banned — in what you type and in what you commit. This repo deploys to
OpenBSD, where those tools are the BSD variants and every GNU idiom written
against them breaks: `sed -i` takes an argument there, `head -n` differs, and a
script that worked on the laptop fails on the box in a way whose error names the
wrong thing.

Reach for one of two things instead.

**Ruby**, for anything that reads, parses or rewrites a file. `ruby -e` is
available everywhere here and the repo is Ruby; a ten-line script that parses
what it edits beats a regex that cannot see structure.

**Modern zsh**, for shell work — and the forms are already in the law, at
`zsh.native_patterns` in `MASTER/data/rules.yml`. They replace exactly what the
ban takes away:

    ${var//find/replace}     instead of sed s///g
    ${(L)var} ${(U)var}      instead of tr a-z A-Z
    ${(s:,:)var}             instead of cut -d, / awk -F,
    ${(j:,:)arr}             instead of paste / awk OFS
    ${(u)arr} ${(o)arr}      instead of sort -u / sort
    ${(M)arr:#*pattern*}     instead of grep over a list
    ${arr:#*pattern*}        instead of grep -v over a list

`grep` itself stays: it reads and does not rewrite, and its BSD form is close
enough. Zsh globs — `**/*.rb`, `*(.)`, `*(/)`, `*(om[1])` — replace `find`
outright, and `setopt extended_glob nullglob` is what makes them safe.

The scanner enforces the ban on committed scripts. Nothing enforces it on what
you type, which is why it is written here.

## You decide, and you close

You have decision authority over anything in `TODO.md`, and the backlog is
worked by closing entries rather than by annotating them. An entry closes two
ways: you do it, or you decide against it and write the argument into the file
that owns the decision — `MASTER/DECISIONS.md`, `OPENBSD/DECISIONS.md`, or the
comment beside the code the decision is about. Then delete the entry. A record
of finished work is closed by deleting it; git holds the why, and a backlog
that keeps its own history stops being a backlog.

What that authority does not extend to: anything that changes a rendered value
— a colour, a font, a sound, a graded look — and anything that needs money, a
registrar login, or a console on vm23. Name the seam and leave it. The operator
is a trained architect, so restore or ask; never invent a layout fix.

Three rules bound the work itself.

**Verify the instrument before the finding.** A census here has been wrong more
often than the reasoning it fed: a dead-file sweep was wrong forty times out of
forty because it searched for `context_provider` while every caller wrote
`Master::Ground::ContextProvider`. Before calling config inert, find the reader.
Before calling code dead, prove the scan on a case you already know the answer
to. An entry whose premise turns out to be false is the most valuable thing you
can bring back — say so plainly rather than working around it.

**Never move a ratchet to absorb your own growth.** `MASTER/bin/operator
measure` must end where it started, and slack is the same defect as debt: a
fall must be recorded, with a comment naming what paid for it. `spine.yml`'s
budgets may be raised only in a commit that names what the lines buy, and
`consecutive_raises_allowed` caps how many raises may stand before a deletion
is owed. A good reason is always available, which is why the number needs
teeth.

**A check that reads source text measures a spelling.** Many gates and specs
here assert on how code is written rather than on what it does, so a rename
breaks them while the behaviour is correct. When that happens, fix the check to
measure behaviour — run the tool's own `--explain` and read its answer, or
split one regex into the separate facts it was conflating. Restoring the old
spelling to appease a grep is how the check stops meaning anything, and
`MASTER/test/test_source_assertions.rb` ratchets the habit down.

Take a worktree, verify with the whole suite rather than a subset, and report
what you decided against as carefully as what you built.
<!-- agent-contract:end -->

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

**Scanner findings are hashes with a path, not Finding objects.**
`Scanner#findings(paths)` is the flat API. `scan_dir` returns Result wrapping
`[path, Result]` pairs whose inner values are hashes: `h[:rule]` works,
`f.rule` raises. `tools/example_scan.rb` is the worked example.

**`bundler/setup` rewrites Gemfile.lock.** A mtime-keyed cache built around
the lock is poisoned on every boot, even when the resolution is unchanged.
`BUNDLE_FROZEN=true` is what the daemon uses.

**A class in a multi-class rule file is invisible to Zeitwerk until the
file loads.** `Rules::AstOmissionRule` raises NameError cold. `require
"review/scan/rule_dsl"` is the load that defines them.

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

**One verb, named stages.** `/through [path]` runs every stage: scan, critique,
principle map. `--only <stage>` runs one, and `/scan`, `/fix`, `/critique` and
`/council` are those stages by name — `/scan` is `/through --only scan`. The
scan stage fixes what it finds as it finds it, so `/scan` and `/fix` name the
same stage; a finding is cheapest to repair at the moment it is found.

**That means a scan mutates the tree** — it has broken dilla, postpro and
MASTER's own chat path. `--no-autofix` and `--dry-run` hold it back. Read the
printed diff before committing, and never commit rewrites of generated caches:
the scanner descends into them.

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
scan registry, deterministic, no model) and a *semantic* tier (the critique
stage, `/through --only critique`, which reaches a provider); the semantic one is
currently unreachable
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

`START_HERE.md` "Do Not Touch". Isolated checkout if more than one agent is in the repo: `MASTER/bin/operator worktree <name>` → work in `../pub4-<name>`. The shared tree has one git index; `git commit -a` sweeps other sessions into your commit. Path-scoped commits (`git commit -- <paths>`) are the minimum if you must share a tree.

## Patch closeout

Match `EXAMPLES.md`: what changed, exact checks run, known debt called out explicitly.
