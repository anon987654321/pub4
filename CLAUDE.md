# CLAUDE.md

One screen. Everything else is reference, reached from here.

Authority order: `MASTER/data/soul.yml` > `MASTER/data/laws.yml` >
executable law (`MASTER/law/*.rb` and `MASTER/lib/review/scan/laws/*.rb`) >
this file > the per-tree contract. Feature truth is `RAILS/apps.yml`.

**MASTER is the primary configuration; this file is secondary.** Claude Code reads
`CLAUDE.md` directly. `AGENTS.md`, `GEMINI.md`, `.cursorlaws` and
`.github/copilot-instructions.md` are generated from one marked block in
`MASTER/AGENTS.md` by `cd MASTER && rake docs:agent_contracts`, with
`rake lint:agent_contracts` failing when one drifts. Whichever door an agent
comes through, it is pointed at `MASTER/data/soul.yml` and
`MASTER/data/laws.yml` before it writes. Change the law there, never in a
harness file. The glossary at `MASTER/docs/synonyms.yml` is vocabulary-only and cannot change policy.

This file points; it does not copy. Every subsystem keeps its own contract and
those files are maintained, so restating them here produces a second source that
drifts. The previous version was deleted at `6cdd2cb97` after exactly that — it
still described a `DEPLOY/` tree and `lib/now,judge,loop` modules that had been
renamed.

## The four governed trees

| | what it is | entry point |
|---|---|---|
| `MASTER/` | A constitutional AI runtime in pure Ruby. The primary product. | `MASTER/bin/master "<instruction>"` |
| `RAILS/` | Three Rails 8 apps: **brgen** (a city social network; its verticals are mounted engines), **amber** (wardrobe), **bsdports**. | `MASTER/bin/operator triangle up` |
| `OPENBSD/` | The deploy pipeline and the VPS runbook. Production is one box, `vm23`. | `MASTER/bin/operator vps state` |
| `STUDIO/` | Media production: dilla, postpro, replicate and lora. | `STUDIO/*/<tool>.rb` |

The repo root holds the four governed trees plus a small set of repository
contracts/configuration: `README.md`, `CLAUDE.md`, generated agent harnesses
and `VERSION`. Design constraints belong in `MASTER/data/laws.yml`;
each tree or project README is its human entry point. A separate architecture
document would duplicate the design authority and is not maintained. `.claude/`
is committed Claude tooling configuration, and `RECOVERY/` is historical restore
evidence; neither is a governed product tree. There is no `TREE.md` on current
main; the tree contracts and `RAILS/README.md` are the map. `STUDIO/` is the canonical media
tool plane; `MASTER/tools/` keeps compatibility symlinks. The backlog file is gone: operator-only
work lives in `MASTER/data/operator_seams.yml`, decisions beside the thing they decide.
Build output
never sits at the root whatever the tool's default: a renderer that writes to
`$PWD` once left a session's renders at the root for weeks. Renders belong outside
the repo, under `${XDG_DATA_HOME:-~/Downloads}/dilla-renders/<date>`, which is where
/play puts them; postpro writes beside the source photograph (the dated directory when
the source sits inside the repo), and `dilla.rb` replaces `dilla.wav` and `dilla.mp4`
beside itself, unless `--out` says otherwise.

## Commands

```zsh
MASTER/bin/operator check                 # every declared check in the repo, fixing as it goes
MASTER/bin/operator check --explain       # the ladder, without running it
MASTER/bin/operator check --scan-only     # the same ladder, writing nothing
MASTER/bin/operator status               # what is dirty, per tree
MASTER/bin/operator test                 # the suites
MASTER/bin/operator measure              # every ratchet, current vs ceiling
MASTER/bin/operator land -m <msg> <path>...  # commit those paths, re-check, push main
MASTER/bin/operator vps state | deploy   # the box

cd MASTER && bin/check               # ordinary code
cd MASTER && bin/check --profile=agent   # law, scanners, fix loop
cd MASTER && bin/check --profile=web     # the face
cd MASTER && bin/check --profile=full    # release check
ruby MASTER/checks/runner.rb --all     # every RAILS check
```

Run the smallest check that proves the work, and do not report done without its
output. `--profile=agent` may fail on known debt tagged `agent-ignore`; do not
chase scan noise on unrelated patches.

`bin/operator check` is the whole ladder in one command: the scanner over all four
governed trees with autofix on, every RAILS check, every suite, the ratchets, the sprawl
census, and last the council. It writes by default and says which files each
stage changed, under that stage's name, so a bad fix is attributable to the
stage that made it. Everything already modified when it starts is listed first
and excluded, because this checkout is shared. A tier it could not reach —
today the council, whose provider answers "Insufficient credits" — is reported
as skipped and exits 3 rather than counting as a pass.

`MASTER/bin/master "<instruction>"` is the repo-wide instruction surface — the
runtime booted so `data/soul.yml` and the sibling trees all resolve. Bare
`MASTER/bin/master` opens a session, and slash commands work as in
`MASTER/bin/cli` because it is that runtime. `MASTER/bin/operator` is the operator
surface. Two runtime surfaces; STUDIO is a governed production tree.

## Five traps, in the order they will bite you

1. **Write straight to main. No worktrees, no branches, no pull requests.** The
   checkout is shared and several agents edit it at once, so commit path-scoped:
   `git commit -- <paths>` with no prior `git add` (a new file needs `git add --
   <that path>` and nothing else). Never `git commit -a`, which sweeps up someone
   else's half-finished work. A hook (`MASTER/tools/block_branching.rb`) refuses
   creating a worktree or branch, opening or merging a PR, and pushing any ref but
   main; `bin/operator worktree` refuses too. Removing a leftover worktree or
   branch stays allowed. `MASTER/bin/operator land -m <msg> <path>...` is the
   whole landing: commit those paths, re-check, push main.
2. **Strict loading is on in every environment.** Reading a lazy association off a
   record fetched by id raises, in test and production both. Associations carrying
   a `:destroy` cascade are exempt (`Shared::CascadingAssociationsLoad`), which is
   easy to get backwards either way. Check before you claim a 500.
3. **A deploy sheds amber and bsdports**, and relayd keeps answering TLS with their
   ports closed — so the outage looks like a hang, not a 5xx. `vps-deploy` restores
   them; deploying by hand, check ports 61352 and 47312.
4. **The apps default to Norwegian.** Tests assert through I18n keys, never English
   literals, and a hardcoded English string is a defect rather than a placeholder.
5. **MASTER speaks, and the settings are data.** `MASTER/data/voice.yml` carries
the whole of it: `rotation` (the voices, chosen per utterance), `post_chain`
(the ffmpeg chain applied after synthesis) and `dilla_fx` (the effects rack, which
borrows the vocabulary of the old Dilla engine and is now its own single source).
`Voice::Policy` reads them, `Speech#shaped` applies the chain, `browser_payload`
hands them to the face so it sounds like the server.

**Renders are replaceable.** dilla and postpro write output that a new run may delete and
   replace; postpro removes a source's earlier takes before it renders a new family. The
   `RELEASE*.mp3` masters are compilations, not renders. Never change a rendered-sound or
   graded-look default on your own judgement.

## Working in a shared index

`MASTER/bin/operator hooks` installs two guards. `pre-commit` refuses a commit
spanning more than one top-level tree — the `git commit -a` signature — unless
`PUB4_CROSS_TREE=1`, and prints everything it leaves behind. `pre-push` refuses
to publish more than one commit unless `PUB4_PUSH_ALL=1`, listing each with its
author and age.

Neither can tell sessions apart; nothing in git can. Path scoping bounds the
commit, not the push — `git push` sends every commit beneath yours, and on
2026-08-10 one push carried four commits another session had told its user were
still local. Run `git log --oneline origin/main..HEAD` before pushing and say in
your report what went with you. There is no per-commit push, so land small and
often: the fewer commits sit unpushed, the fewer ride along.

Paths do not identify sessions either. Everything commits as the same author, and
inferring "this is my tree, so this is my commit" was wrong twice on 2026-08-10,
when three sessions were in `RAILS/` at once. Read the commit body before
claiming or disclaiming one.

## Mirror MASTER: hold its law before you write under it

MASTER judges every effect against a constitution. You write in the same tree,
so you are held to the same one, and the only way to be held to a Law is to
know it. Skimming the file is not knowing it.

**Read the law once per session, one Law at a time, before the first edit.**
Sequentially, each Law on its own — id, what it forbids, the fix it names, and
the exemption it carries. The exemption is the half that gets skipped and the
half that was earned against a measured false positive. Stop on each and hold
it before moving to the next.

The order is the authority order, and it is not long:

1. `MASTER/data/soul.yml` — the kernel. Absolutes, work rules, anti-simulation.
   It outranks everything below, including this file.
2. `MASTER/data/laws.yml` — the canonical declared Law catalogue and execution
policy. Priority-ranked entries are flat at the top level; there is no canonical
`rules:` subtree.
3. `MASTER/law/*.rb` — executable Law definitions with their positive and
negative fixtures.
4. `MASTER/lib/review/scan/` — detector implementations and scanner registration.
   These implement enforcement; they do not define another policy catalogue.
   Use `LawRegistryAudit` to reconcile catalogue entries, executable definitions
   and registered detectors; do not assume a one-to-one mapping.

Do not hand-parse the catalogue with an assumed YAML shape. Run
`ruby MASTER/tools/agent_context.rb --tree`; it is the bounded operator-facing
view of the live law contract and its enforcement surfaces.

You have it when you can name the Law that governs a line you are about to
write without opening the file. Until then, open the file.

**A Law you cannot state is a Law you will break**, and the breakage is
usually the exemption rather than the rule — every scan noise entry
is somebody who knew the rule and not what it spares.

Two cautions from the tree itself. `data/laws.yml` and `data/soul.yml` are
`paths.immutable`: read them, never let an effect write them. Catalogue entries
and executable detectors are not a one-to-one population, and the audit currently
tracks unresolved mapping and coverage gaps. Use `LawRegistryAudit` and its named
populations; do not infer complete enforcement from a total count or a single
registry.

## Every agent mirrors MASTER

MASTER is the configuration; Claude, Grok, Codex, DeepSeek and GLM are tools
that follow it. Run `MASTER/bin/operator brief` before the first edit: it
prints the authority chain, the mechanical guards and the top-ranked laws as
they are now. Commits take MASTER's own shape, defined once in
`MASTER/data/commit_format.yml` and enforced for every author by the
`commit-msg` hook: a capitalised subject of at most 72 characters with no
`feat:` prefix and no full stop, a blank line, the body, a blank line, and a
`Co-authored-by:` trailer.

## Two habits this repo learned the hard way

**Verify the instrument before the finding.** Naive pattern-matching over this
tree produces mostly false positives — five candidate findings died on
verification in one week, one report had to be retracted after the test written
to prove it passed with the fix reverted, and a dead-file census was wrong forty
times out of forty because it searched for `context_provider` while every caller
wrote `Master::Ground::ContextProvider`. Before calling config inert, find the
reader. Before calling code wrong, check what your scan measured.

**A comment states the present-tense reason.** Not what the code used to do —
that is what `git log` is for. A standing refusal with no code to sit beside
goes under "Refused, and why" in `MASTER/AGENTS.md` or `OPENBSD/CLAUDE.md`.

## House Laws

**Every README carries one voice.** It opens with a bold, visionary paragraph, then
plain Strunk & White prose a regular person follows — no code blocks, no lists, no
tables — and it passes `bin/operator lint` — the `README_PROSE` rule in `MASTER/lib/review/scan/laws/cosmetic_laws.rb` enforces it, because a convention does not become a second Law in prose an agent skims. Redo a folder's
README before you push that folder, so the door to it is never stale. `MASTER/README.md`
is the reference.

**Ruby and zsh, not GNU text tools.** `sed`, `awk`, `find`, `head`, `tail`, `wc`,
Before targeted reading on an unfamiliar or broad task, run `ruby MASTER/tools/agent_context.rb --tree`. Treat the result as the map; then read relevant source systematically rather than sampling arbitrary files.
Search with `git grep`: zsh aborts a command whose glob matches nothing, and `--include=*.rb` is one.
Keep shell commands readable: prefer zsh globs and builtins, one meaningful operation per line, and `&&` only for a real dependency. In Ruby, use argv execution through `Master::Io::Exec` rather than backticks or interpolated shell strings.
`perl` and `python` are banned in agent shell calls and committed scripts: BSD
variants break GNU idioms and this repo deploys to OpenBSD. Use `ruby -e`, zsh
globs and builtins, or the dedicated file tools.

**Read the man page before touching OpenBSD config.** For any `OPENBSD/` or vm23
change, read the full man page for the file *and* its daemon first, from the VPS.

**Never commit** `MASTER/knowledge/`, `MASTER/output/`, `.master/`, secrets, or
generated assets. Keys live in `/etc/*.env` on the VPS.

**Production is vm23 only** (`dev@brgen.no`). One app CI/deploy at a time. After
`git pull` on the box, run `vps-deploy` before expecting live health.

## Response style

Every character earns its place. Answer in one or two sentences; three is a
long reply. Lead with the outcome. Cut preamble, summary, restatement and any
sentence the reader could have written themselves.

Say what changed and what it cost. Numbers belong in the commit message, not
here. Name a file only when the reader must open it. Bullets for files,
commands and lists — never for prose.

Detail is on request, not by default. A finding gets one sentence and a
pointer; the reasoning lives in the commit. When something is
uncertain, say so in a clause, not a paragraph.

## Writing style

**Strunk & White — The Elements of Style.** Plain prose, no filler. Lead with
the outcome. Use active voice. Use definite, specific, concrete language. Omit
needless words. Put emphatic words at the end. Keep related words together.
Avoid fancy words. Revise and rewrite. Do not overwrite. Do not overstate. Do
not explain too much. Use figures of speech sparingly. Prefer the standard to
the offbeat. Make sure the reader knows who is speaking. Use orthodox spelling.

## You decide, and you close

You have decision authority over open work. It closes when you do it, or when
you decide against it and write the argument into the file that owns the
decision. There is no backlog file to keep: a record of finished work is closed
by not writing it. The authority stops at anything that changes a rendered value (a
colour, a font, a sound, a graded look) and anything needing money, a registrar
login, or a console on vm23: name the seam in `MASTER/data/operator_seams.yml` and leave it.

The bounds are in `MASTER/AGENTS.md`, under the same heading, and they are the
three this repo keeps relearning — verify the instrument before the finding,
never move a ratchet to absorb your own growth, and fix a check that measures a
spelling rather than restoring the spelling. Read them there; this is a
pointer.

## Where the rest lives

| Working on | Read |
|---|---|
| Anything in MASTER | `MASTER/README.md`, then `MASTER/AGENTS.md` |
| The web face, WebGL, TTS | `RAILS/master/CLAUDE.md` |
| Deploy, the VPS, rc.d, relayd | `OPENBSD/CLAUDE.md`, then `OPENBSD/RUNBOOK.md` |
| RAILS CSS or visual work | `RAILS/__shared/README.md` |
| brgen's city hosts and verticals | `RAILS/brgen/AGENTS.md` |
| Why something odd is deliberate | the comment beside it; standing refusals in `MASTER/AGENTS.md` and `OPENBSD/CLAUDE.md`, "Refused, and why" |
| Operator-only work and the evidence that closes it | `MASTER/data/operator_seams.yml` |
