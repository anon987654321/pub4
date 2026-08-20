# CLAUDE.md

Guidance for Claude Code across the pub4 repo. Authority order:
`MASTER/data/soul.yml` > `MASTER/data/rules.yml` > this file.

This file is a pointer, not a copy. Every subsystem keeps its own contract, and
those files are maintained; duplicating them here produces a second source that
drifts. The previous version of this file was deleted at `6cdd2cb97` after
exactly that — it still described a `DEPLOY/` tree and `lib/now,judge,loop`
modules that had been renamed.

## Layout

```
MASTER/    constitutional AI runtime in Ruby — the primary product
RAILS/     Rails 8 apps: brgen (one process: city apex + subdomain engines), amber, bsdports
OPENBSD/   deploy pipeline, VPS runbook, operator debt
STUDIO/    media tools — dilla (beats), lora, postpro (grading), repligen (images)
bin/       repo-level entry points: master, cli, pub4, ruby
dotfiles/  shell and editor config
```

## Where the contract lives

| Working on | Read first |
|---|---|
| Anything in MASTER | `MASTER/START_HERE.md` (full contract), `MASTER/AGENTS.md` (task-scoped) |
| MASTER law, scanners, fix loop | `MASTER/START_HERE.md` "Data File Budget"; all scanner law is `data/rules.yml` |
| The web face / WebGL / primer tap | `MASTER/web/CLAUDE.md` |
| Deploy, VPS, rc.d, relayd | `OPENBSD/CLAUDE.md`, then `OPENBSD/RUNBOOK.md` |
| RAILS app CSS or visual work | `RAILS/shared/WIRING_NOTES.md` "Visual design system" |
| brgen city hosts / verticals | `RAILS/brgen/AGENTS.md` (apex vs subdomain engines; not a fourth app) |
| Why something odd-looking is deliberate | `MASTER/DECISIONS.md`, `OPENBSD/DECISIONS.md` |
| Known debt, and what not to chase | `MASTER/DEBT.md`, `OPENBSD/data/debt.yml` |

Feature truth is `RAILS/apps.yml`. Operator debt is `OPENBSD/data/debt.yml`.

## Instructing MASTER

`bin/master "<instruction>"` is the repo-wide instruction surface — the MASTER
runtime booted from `MASTER/` so `data/soul.yml` and the sibling `RAILS`,
`OPENBSD` and `STUDIO` trees all resolve. Bare `bin/master` opens a session;
slash commands work as in `MASTER/bin/cli`, because it is that runtime.

`bin/pub4` stays the *operator* surface (`status`, `vps state|deploy|logs`,
`post-pull`). Two surfaces, no third: `bin/cli` was a compat shim forwarding to
`bin/pub4` for legacy callers that no longer exist, and was deleted rather than
kept — every `bin/cli` in this tree means `MASTER/bin/cli`.

## Checks

Run the smallest check that proves the work; do not report done without its
output.

```zsh
cd MASTER && bin/check                    # ordinary code
cd MASTER && bin/check --profile=agent    # law, scanners, fix loop
cd MASTER && bin/check --profile=web      # the face
cd MASTER && bin/check --profile=full     # release gate: bin/ci + bin/probe all + rake audit
bin/pub4 status                           # repo-level status
```

`--profile=agent` may fail on known debt tagged `agent-ignore` in
`MASTER/DEBT.md`. Do not chase scan noise on unrelated patches.

## Repo-wide rules that catch agents

**One git index, many agents.** The default checkout is shared. `git commit -a`
sweeps another agent's half-finished work into your commit, and interleaved
writes have produced silently corrupt files.

```zsh
bin/pub4 worktree <name>   # your own checkout + branch — the actual fix
bin/pub4 hooks             # refuse cross-tree commits in the shared tree
```

Take the worktree if more than one agent is active. This paragraph asked for
that in prose for months while the worktree cost a remembered path to a shell
script and the shared tree cost nothing, so sessions kept choosing nothing —
and on 2026-08-12 one session's debt write-up was committed by another under a
message about something else. It is one command now.

In the shared tree, commit path-scoped at minimum (`git commit -- <paths>`, no
prior `git add`). `bin/pub4 hooks` installs two guards:

- **`pre-commit`** refuses a commit spanning more than one top-level tree — the
  `git commit -a` signature — unless you set `PUB4_CROSS_TREE=1`, and prints
  everything it is leaving behind, so other sessions' work in your tree is
  visible at the moment you commit.
- **`pre-push`** refuses to publish more than one commit unless you set
  `PUB4_PUSH_ALL=1`, listing each with its author and age first. On a single
  commit it prints what is going rather than assuming it is yours.

Neither can tell sessions apart; nothing in git can. Path scoping bounds the
commit, not the push: `git push` sends every commit beneath yours. Run
`git log --oneline origin/main..HEAD` before pushing and say in your report what
went with you.

Path scoping bounds the commit, not the push. `git push` sends every commit
beneath yours, so pushing one path-scoped commit publishes whatever anyone else
committed and had not sent yet — on 2026-08-10 one push carried four commits
another session had told its user were still local. Run `git log --oneline
origin/main..HEAD` before pushing and say in your report what went with you.
There is no per-commit push; the only real fix is a worktree.

Paths do not identify sessions either. Everything commits as the same author, and
inferring "this is my tree, so this is my commit" was wrong twice on 2026-08-10 —
three sessions were in `RAILS/` at once. Read the commit body before claiming or
disclaiming one.

**Ruby and zsh, not GNU text tools.** `sed`, `awk`, `find`, `head`, `tail`, `wc`,
`perl` and `python` are banned in agent shell calls and committed scripts — BSD
variants break GNU idioms and this repo deploys to OpenBSD. Use `ruby -e`, zsh
globs and builtins, or the dedicated file tools.

**Read the man page before touching OpenBSD config.** For any `OPENBSD/` or vm23
change, read the full man page for the file *and* its daemon first, from the VPS.

**Never commit** `MASTER/knowledge/`, `MASTER/output/`, `.master/`, secrets, or
generated assets. Keys live in `/etc/*.env` on the VPS.

**Production is vm23 only** (`dev@brgen.no`). One app CI/deploy at a time. After
`git pull` on the box, run `vps-deploy` before expecting live health.
