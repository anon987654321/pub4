# CLAUDE.md

One screen. Everything else is reference, reached from here.

Authority order: `MASTER/data/soul.yml` > `MASTER/data/rules.yml` > this file >
the per-tree contract. Feature truth is `RAILS/apps.yml`.

This file points; it does not copy. Every subsystem keeps its own contract and
those files are maintained, so restating them here produces a second source that
drifts. The previous version was deleted at `6cdd2cb97` after exactly that — it
still described a `DEPLOY/` tree and `lib/now,judge,loop` modules that had been
renamed.

## The four trees

| | what it is | entry point |
|---|---|---|
| `MASTER/` | A constitutional AI runtime in pure Ruby. The primary product. | `MASTER/bin/master "<instruction>"` |
| `RAILS/` | Three Rails 8 apps: **brgen** (a city social network; its verticals are mounted engines), **amber** (wardrobe), **bsdports**. | `RAILS/bin/triangle up` |
| `OPENBSD/` | The deploy pipeline and the VPS runbook. Production is one box, `vm23`. | `MASTER/bin/pub4 vps state` |
| `STUDIO/` | Media tools. **dilla** makes beats, **postpro** grades images, **repligen**/**lora** generate. | `ruby STUDIO/dilla/dilla.rb` |

Nothing else sits at the repo root but this file and `TODO.md`, the single
repo-wide backlog (every per-tree debt/TODO/blocker list was folded into it).

## Commands

```zsh
MASTER/bin/pub4 gate                 # every gate in the repo, fixing as it goes
MASTER/bin/pub4 gate --explain       # the ladder, without running it
MASTER/bin/pub4 gate --scan-only     # the same ladder, writing nothing
MASTER/bin/pub4 status               # what is dirty, per tree
MASTER/bin/pub4 test                 # the suites
MASTER/bin/pub4 measure              # every ratchet, current vs ceiling
MASTER/bin/pub4 worktree <name>      # your own checkout — see the first trap
MASTER/bin/pub4 vps state | deploy   # the box

cd MASTER && bin/check               # ordinary code
cd MASTER && bin/check --profile=agent   # law, scanners, fix loop
cd MASTER && bin/check --profile=web     # the face
cd MASTER && bin/check --profile=full    # release gate
ruby RAILS/gates/runner.rb --all     # every RAILS gate
```

Run the smallest check that proves the work, and do not report done without its
output. `--profile=agent` may fail on known debt tagged `agent-ignore`; do not
chase scan noise on unrelated patches.

`bin/pub4 gate` is the whole ladder in one command: the scanner over all four
trees with autofix on, every RAILS gate, every suite, the ratchets, the sprawl
census, and last the council. It writes by default and says which files each
stage changed, under that stage's name, so a bad fix is attributable to the
stage that made it. Everything already modified when it starts is listed first
and excluded, because this checkout is shared. A tier it could not reach —
today the council, whose provider answers "Insufficient credits" — is reported
as skipped and exits 3 rather than counting as a pass.

`MASTER/bin/master "<instruction>"` is the repo-wide instruction surface — the
runtime booted so `data/soul.yml` and the sibling trees all resolve. Bare
`MASTER/bin/master` opens a session, and slash commands work as in
`MASTER/bin/cli` because it is that runtime. `MASTER/bin/pub4` is the operator
surface. Two surfaces, no third.

## Five traps, in the order they will bite you

1. **The checkout is shared, so take a worktree by default.** Several agents edit
   this tree at once. `git commit -a` sweeps up someone else's half-finished work,
   and `git push` publishes every commit beneath yours. Prefer `MASTER/bin/pub4
   worktree <name>` for any change past a trivial one-file edit — a clean tree with
   no other session's dirt is worth the setup, and it is how this file was last
   edited. Merge it back and delete the worktree and its branch in the same
   session; a lingering worktree is its own hazard. Writing straight to main is the
   exception now — and when you do, commit path-scoped: `git commit -- <paths>`
   with no prior `git add`.
2. **Strict loading is on in every environment.** Reading a lazy association off a
   record fetched by id raises, in test and production both. Associations carrying
   a `:destroy` cascade are exempt (`Shared::CascadingAssociationsLoad`), which is
   easy to get backwards either way. Check before you claim a 500.
3. **A deploy sheds amber and bsdports**, and relayd keeps answering TLS with their
   ports closed — so the outage looks like a hang, not a 5xx. `vps-deploy` restores
   them; deploying by hand, check ports 61352 and 47312.
4. **The apps default to Norwegian.** Tests assert through I18n keys, never English
   literals, and a hardcoded English string is a defect rather than a placeholder.
5. **Renders are irreplaceable.** dilla and postpro write real output with rotating
   seeds. Never render over a take that matters, and never change a rendered-sound
   or graded-look default on your own judgement.

## Working in a shared index

`MASTER/bin/pub4 hooks` installs two guards. `pre-commit` refuses a commit
spanning more than one top-level tree — the `git commit -a` signature — unless
`PUB4_CROSS_TREE=1`, and prints everything it leaves behind. `pre-push` refuses
to publish more than one commit unless `PUB4_PUSH_ALL=1`, listing each with its
author and age.

Neither can tell sessions apart; nothing in git can. Path scoping bounds the
commit, not the push — `git push` sends every commit beneath yours, and on
2026-08-10 one push carried four commits another session had told its user were
still local. Run `git log --oneline origin/main..HEAD` before pushing and say in
your report what went with you. There is no per-commit push; the only real fix is
a worktree.

Paths do not identify sessions either. Everything commits as the same author, and
inferring "this is my tree, so this is my commit" was wrong twice on 2026-08-10,
when three sessions were in `RAILS/` at once. Read the commit body before
claiming or disclaiming one.

## Two habits this repo learned the hard way

**Verify the instrument before the finding.** Naive pattern-matching over this
tree produces mostly false positives — five candidate findings died on
verification in one week, one report had to be retracted after the test written
to prove it passed with the fix reverted, and a dead-file census was wrong forty
times out of forty because it searched for `context_provider` while every caller
wrote `Master::Ground::ContextProvider`. Before calling config inert, find the
reader. Before calling code wrong, check what your scan measured.

**A comment states the present-tense reason.** Not what the code used to do —
that is what `git log` and the decision records are for.

## House rules

**Every README carries one voice.** It opens with a bold, visionary paragraph, then
plain Strunk & White prose a regular person follows — no code blocks, no lists, no
tables — and it passes `bin/pub4 lint` — the `README_PROSE` rule in `MASTER/lib/review/scan/rules/cosmetic_rules.rb` enforces it, because a convention is a rule, not a paragraph an agent skims. Redo a folder's
README before you push that folder, so the door to it is never stale. `MASTER/README.md`
is the reference.

**Ruby and zsh, not GNU text tools.** `sed`, `awk`, `find`, `head`, `tail`, `wc`,
`perl` and `python` are banned in agent shell calls and committed scripts: BSD
variants break GNU idioms and this repo deploys to OpenBSD. Use `ruby -e`, zsh
globs and builtins, or the dedicated file tools.

**Read the man page before touching OpenBSD config.** For any `OPENBSD/` or vm23
change, read the full man page for the file *and* its daemon first, from the VPS.

**Never commit** `MASTER/knowledge/`, `MASTER/output/`, `.master/`, secrets, or
generated assets. Keys live in `/etc/*.env` on the VPS.

**Production is vm23 only** (`dev@brgen.no`). One app CI/deploy at a time. After
`git pull` on the box, run `vps-deploy` before expecting live health.

## Where the rest lives

| Working on | Read |
|---|---|
| Anything in MASTER | `MASTER/START_HERE.md`, then `MASTER/AGENTS.md` |
| The web face, WebGL, TTS | `MASTER/web/CLAUDE.md` |
| Deploy, the VPS, rc.d, relayd | `OPENBSD/CLAUDE.md`, then `OPENBSD/RUNBOOK.md` |
| RAILS CSS or visual work | `RAILS/shared/WIRING_NOTES.md`, then `RAILS/shared/LAYOUT.md` |
| brgen's city hosts and verticals | `RAILS/brgen/AGENTS.md` |
| Why something odd is deliberate | `MASTER/DECISIONS.md`, `OPENBSD/DECISIONS.md` |
| The backlog: parity gaps, blockers, debt, what not to chase | `TODO.md` (repo root) |
