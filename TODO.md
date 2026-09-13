# pub4 backlog

The single backlog for the whole repo. One file, at the root, replacing the
per-tree lists that used to drift out of sight of one another: `MASTER/DEBT.md`,
`RAILS/TODO.md`, `RAILS/BLOCKERS.md`, and the `OPENBSD/data/debt.yml` register.

Authority order is unchanged: `MASTER/data/soul.yml` > `MASTER/data/rules.yml` >
the root `CLAUDE.md` > the per-tree contract. Feature truth is still
`RAILS/apps.yml`; horizon (aspirational, agent: ignore) is still
`RAILS/apps.horizon.yml`. The decision records — `MASTER/DECISIONS.md` and
`OPENBSD/DECISIONS.md` — are rationale, not backlog, and stay where they are.

How to read this file. Each tree has its own top-level section, and everything
in it is open. **A record is deleted when it closes** — `git log` holds the
history, and a backlog that keeps every item it ever had teaches the reader to
skim. What survives a close is the false positive worth not re-discovering:
those live under "Debt — resolved records" and are guards, not history.

One habit this repo learned the hard way, and it governs every finding below:
**a finding is a hypothesis; re-measure before working from one.** Naive
pattern-matching over this tree produces mostly false positives, and several of
the entries here were themselves stale when written. Verify the instrument
before the finding.

An item leaves this file when a check proves it, not when it stops being
mentioned.

**645 of these items were verified against the tree on 2026-09-12, and 297 of
them were not work.** 255 ALREADY BUILT, 42 FALSE, 337 real, 12 needing vm23,
3 fenced by the intake's own preface. **Forty-six percent evaporated on contact
with the code.**

Six read-only passes covered: both performance intakes, both halves of
"ChatGPT proposed forward work", "pub4 subtraction and entropy", the layout
and typography passes, and the first 81 of the refinement inventory.

**Where the intake is most wrong, by density of already-built:** the shared
design system (214–233), Brgen (238–256), marketplace (258–295), security and
privacy (352–373), cross-tree governance (438–468). Whole ranges of it
describe a tree that already exists.

**Where it is most right:** browser coverage of the Turbo, modal and focus
lifecycle (195–207), messenger resilience under reconnect and long threads
(300–320), OpenBSD ownership, unveil and stale-resource audits (382–397), and
CI workflow integrity (431–437).

**And one distinction that changes what the real items cost.** The intake
repeatedly asks for a *gate* over something the tree already has as a
*mechanism* — confirmations, loading states, CSRF tokens, empty states all
exist and are unwatched. Those are honestly REAL, but the work is a detector,
not a feature, and that is a much smaller day than the wording suggests.

**What the already-built ones have in common is that the tree does not spell
them the way the intake does.** The RAILS database work is `QueryBudgetTest`,
`Bullet.raise`, `strict_loading_by_default`, `counter_cache` and
`CurrentAttributes` — none of which contain the word performance. MASTER's is
Zeitwerk autoloading, `Gemfile` `require: false`, `language_for`,
`reader_singularity`, `CodeIndex#incremental_build`, `dup_census`,
`code_reach`, `method_graph`. A grep for the proposal's own vocabulary reports
every one of them open.

**Two warnings for whoever reads a verdict table below.**

A verifier is an instrument and fails the same way its subject does. One pass
reported `MASTER_SCAN_ONLY` as set by nobody, having searched only `MASTER/`;
four callers set it, in `RAILS/` and `OPENBSD/`. Another was asked for the
deletion list and came back with its four strongest "the intake is wrong"
calls *and* eight findings it was not confident about, including its own best
deletion candidate — three gems it could find no caller for, declared in two
Gemfiles, which it flagged as looking exactly like the `context_provider`
census that was wrong forty times out of forty. **Read the not-confident list
before acting on the confident one.**

And a FALSE verdict is worth more than a REAL one here. The fifteen false
items in the RAILS performance table name duplicated initializers that are
not duplicated, `eager_load_paths` that are commented out, and `.preload(`
call sites that number zero — each one a morning spent proving a negative.


**The layout pass measured its own subject, and the number is the one this
repo already knew.** Of 73 items: 15 false outright, and 12 more where the
finding is right and the file, line or figure is wrong — a legal padding
quoted as one thing and written as another, a tracking value already paired,
a scale counted as 9 steps when the ladder has 8. **37% defective**, against
the 596-of-981 this repo measured on its last design backlog. Treat every
citation in a layout item as a hypothesis about a line number too.

**And a large part of that section is not ours at all.** The pass separated
out everything that moves a rendered value — mailer type scale and tracking,
the pen shadow, playlist's 720px, the marketplace hero clamp, which token is
H1 on five surfaces, the dating gradient, paragraph leading, and the whole of
blocks 29–55, 65–74, 97–123, 139–169 and 202–221, which are about how a
surface *looks* rather than which token it applies. Those are the operator's,
and an agent sweeping them would be redesigning the product by grep.

**The verification pass's single best deletion candidate was wrong, and it said
so itself before anyone checked.** It reported `wisper`, `tty-reader` and
`flay` as declared in the Gemfiles and referenced by no code in any tree —
true, as far as a grep for their constants goes — and then flagged the finding
as low-confidence on the grounds that "a gem nobody uses does not usually get
added twice".

It was right to doubt it. `Gemfile.lock:222-227` has `tty-prompt` requiring
`tty-reader`, and `tty-reader` requiring `wisper`; `tty-prompt` is used at
`MASTER/lib/cli/session.rb:14` and `MASTER/lib/fix/governor.rb:3`. Removing
either gem line would change nothing but the Gemfile's honesty, and removing
the lock entries with them would stop the daemon booting under
`BUNDLE_FROZEN=true` (`OPENBSD/etc/rc.d/master:34`).

Only `flay` (`MASTER/Gemfile:30`, `require: false`, no lock dependents, no
caller) is genuinely unreferenced — and taking it out is still a lockfile
change, which this repo records as structurally hazardous from a Mac because
`rb-kqueue` is BSD-only and resolves differently here. It wants doing on the
box.

**The transferable rule: a gem's callers are not only in the code.** Check the
lock's dependency tree before calling one unused, the same way you check every
tree before calling a constant unreached.

**And a third, for the reason this file already documents.** `canvas:*` and
`:canvas_state` were reported as published with no subscriber —
`MASTER/web/app/controllers/canvas_controller.rb:63` and
`app/services/chat_service.rb:189` publish, and no file names them in a
`subscribe`. True, and not the question. `cable_bridge.rb:18` subscribes
`"*"` and broadcasts every bus event to the browser over ActionCable, so
every published topic has a consumer by construction.

This file's own "Declared and never wired" section states it outright:
published-never-subscribed is 238 of 285 and **every row is noise, because the
wildcard subscribers consume the lot**. The direction worth running is the
other one — subscribed-never-published was 4, two were wildcards, and both of
the remaining two were real defects.

**So an agent asked to find dead events will find hundreds, and be wrong about
all of them.** Three of the three event findings checked today were false for
this reason. Give it the subscriber list, not the publisher list.

**Two more event-drift findings died on verification, and both died the same
way: the census looked at one end of the wire.**

`Trace::Metrics` subscribes `llm:response` and `LlmDispatcher::RubyLlmSender`
publishes `llm:call_complete`, which reads as drift until you look for the
other publisher and the other subscriber. `llm:response` is published at
`MASTER/lib/review/agent/fallback_chain.rb:152`; `llm:call_complete` is
subscribed at `MASTER/lib/trace/ledger.rb:21`. Two events, two producers, two
consumers, all four wired. Nothing is drifting.

The lesson generalises past events: **a name that appears once as a subscriber
and once as a publisher, in two different files, is not evidence of anything
until both lists are complete.** The one-directional census that found the
real `swallow:error` defect worked precisely because it compared the whole
published set against the whole subscribed set — a pair of greps for two
strings does not.

**This file's own dominant defect is the duplicate, not the stale entry.**
Fifty-one subjects are named in four or more different top-level sections —
`apps.yml` in ten, `rules.yml` in eight, `dilla.rb` and `/health` in seven,
`bin/crate` and `soul.yml` in six. Each section opened its subject
independently, so closing one leaves the others open and the next pass opens
one more. That is most of why a backlog is twelve thousand lines.
`dilla_principles.yml` was nine and is seven after the fold below.

Measure it before adding a section, with the file as its own input:

```zsh
ruby -e 'ls=File.readlines("TODO.md"); s=[]; ls.each_with_index{|l,i| s<<[i,l.chomp.sub("## ","")] if l.start_with?("## ")}; o=Array.new(ls.size); s.each_with_index{|(i,t),n| (i...(s[n+1]?s[n+1][0]:ls.size)).each{|k| o[k]=t}}; h=Hash.new{|x,k| x[k]=[]}; ls.each_with_index{|l,i| l.scan(/`([A-Za-z0-9_\/.:-]{6,})`/).flatten.each{|t| h[t]<<o[i] if t=~%r{[/._]}}}; h.map{|t,v| [t,v.compact.uniq]}.select{|_,v| v.size>=4}.sort_by{|_,v| -v.size}.each{|t,v| puts "#{v.size}  #{t}"}'
```

**So search this file for the subject before writing an entry about it, and
fold rather than append.** The `dilla_principles.yml` consolidation of
2026-09-12 is the worked example: eight entries, one measured answer, and not
one of the eight had run `git grep` for the reader.

**Forward work is the last section of this file**, merged from `WISHLIST.md` on
2026-09-06.
---

## MASTER

### Audit findings — 2026-09-12

- `MASTER/bin/check --profile=agent --format=brief` fails the self-test because
  `MASTER/lib/review/llm_dispatcher/ollama_sender.rb:63` has a 24-line
  `ollama_post` method against the 20-line density ceiling. The check labels
  this `agent-ignore` known debt; extract helpers and rerun the profile.
  **Claimed 2026-09-12 by Copilot in `pub4-todo-ollama`.**
- **The Ruby 4.0.5 line is not a repo defect and closes here.**
  `Operator::Environment#ruby_mismatch_message` reads it correctly, prints
  `MISMATCH` beside the path, and `next:` already routes to `MASTER/bin/ruby`,
  which resolves 3.4. What is actually wrong is on the machine: rbenv's shims
  are not on PATH and `rbenv global` is `system`, so a bare `ruby` gets
  Homebrew's 4.0.5 while `RBENV_VERSION=3.4.9` sits in the environment doing
  nothing. That is a line in a shell profile, not a change any tree owns. Left
  here only because the next reader will measure it again and reach for the
  code.

Everything here was checked against the tree on 2026-09-10 and carries the number
it read that day. Closed records are deleted rather than marked; `git log` holds
them. What stays is forward work, the operator decisions, and the false positives
worth not re-discovering — those last are guards, not history.

**Three entries closed on 2026-09-10 by being wrong rather than by being fixed**, and
the pattern is worth holding above the list. `lint:principle_trace` was recorded as
twenty under its low and reads at its ceiling. The 39 silent rules were said to be
silent for two reasons and are silent for one, because `rule_audit` only measures rules
that have a detector. The 86 rules "with no detector field" were 92, because 86 was a
subtraction that assumed two keys are disjoint and six rules carry both. Every one is
this file's own standing warning — verify the instrument before the finding — applied to
the file itself.

### The tree should explain MASTER — 2026-09-09

The operator's standard: a reader should be able to infer what MASTER is from the
shape of its directories. Every directory declares its purpose in
`MASTER/PATH_OWNERSHIP.yml`, and the work is to put each file under the purpose that
matches it. Twenty-two files have left `lib/ground` for that reason and the charter
now covers what remains.

**The question this campaign kept re-opening is settled and written down.** A typed
reader over a declarative table belongs to `ground` under the schema clause when what
the table declares is MASTER's own constitution, configuration, policy or memory,
whether that table sits in `data/` or in a frozen constant in the file. It does not
when the table's subject is another directory's declared purpose, and it is not a
schema at all when the file writes the table rather than reading it. The clause is in
`PATH_OWNERSHIP.yml` and the worked cases are in `lib/ground/README.md`.

**Nothing under `lib/ground` is open on placement now.** The one file this entry
carried, `ground/unified_diff_editor.rb`, is deleted — the question that moved it was
not where it belonged but what it duplicated, and the answer was three live mechanisms
in other directories.

Three cautions for whoever moves the next file. A move is a constant rename, so check
for callers that write the bare name inside the same module first — `PressureEngine`
looked dead to a qualified-name census and is constructed at `MASTER/lib/builder.rb:165`
on every full boot, though not under `Builder.build_fast`. And re-base the source and
destination `loc_body_budgets` keys in the same commit, by the body lines that moved
and no more: the sum has to be zero, because a move pays nothing toward a breach. And
`lib/builder.rb` and `lib/core.rb` have their own keys separate from `lib/builder` and
`lib/core`, so a change to the namespace file does not show up in the directory's row —
`loc_budget` caught two body lines there that every directory reading had missed.

### What is still the operator's, after the delegation of 2026-09-10

The operator delegated every judgement call in this section — a name, a default, a
structure, a threshold, a ceiling — and asked for the reasoning to be written where the
next reader will look. What is left below is what delegation cannot settle: money,
credentials, a look somebody has to see, and another tree's ratchet.

- **The face reads as a shadow at its own defaults, and the README take does not. The
  principle is settled; the number is not.** `RAILS/gates/probes/face_loop_record.rb`
  records it with `uColor` pinned to 3.4 and `uExposure` to 2.8, because a 360-pixel
  README embed of dim grey dots on black reads as nothing at all. Receding points sit at
  `shade = mix(0.14, 1.0, depth)` in `face.part2.txt:164`, so most of the face is
  painted at a seventh of full brightness before alpha. **Two faces, and the README's is
  the one people see first, so the live face is the one that should move** — that much
  is a one-source question rather than taste, and recording the take at the live
  defaults instead would make the README embed useless. The honest fix is the shader's
  floor rather than a uniform the recorder happens to hold. What cannot be decided from
  a terminal is the floor's value: `design_tokens.yml`'s `face_root.anchors` is pinned
  by a production gate, and matching the take's apparent brightness is a thing you judge
  by eye against a render, once.
- **One colour decides `contrast_below_aa`, and it is a hover fill.** The
  marketplace search submit keeps `color: var(--accent-ink)` through its hover
  and swaps the background to `vertical_accents.marketplace.hover` — so the
  vertical ink `#110f19` lands on `#6f6149` and measures **3.15:1**, under the
  4.5 floor `_vertical_shell.scss`'s own comment claims. The ink was verified
  against the accent and light columns; the hover column was never measured, in
  either file. tv (3.34) and maps (4.31) fail the same way and reach no pixel
  yet, because only marketplace wires its hover — they land the day another
  vertical does. `design_metrics` reports the one that is drawn and the ceiling
  stays 0, so `layout_suite` is red until a colour moves. Lightening
  `marketplace.hover` is the obvious direction — it is currently *darker* than
  the accent it replaces, which is backwards for a dark ink — but which value
  is a thing you judge by eye. The gate was reporting two different pairs here
  until 2026-09-12, both of them text that is never drawn; that instrument is
  fixed and this is what was underneath it.
- **Whether the one scheme keeps an accent.** `magic_hex` is ratcheted at 77 and
  `contrast_below_aaa` at 37, of which the bulk are `--danger`, deliberately the one
  non-grey. `vertical_accents` still gives marketplace, tv, dating and the rest their
  own ink. The decision is whether one accent survives for interactive affordance — a
  link with no colour needs an underline instead. Both ratchets count RAILS, so this
  belongs beside the RAILS section rather than here.
- **The deploy.** See the box state below; nothing is blocking it.
- **`dilla_principles.yml` gets a reader or gets deleted, and either is a
  rendered-sound decision.** 3.9KB of draft research spec, `status: draft`,
  and `git grep dilla_principles` over `STUDIO/` returns one line: the file's
  own first. Wiring it into `groove_engine` changes what dilla generates, so
  it is not an outsider's to take — and deleting research the operator
  restored from `Downloads/dilla.yml` is not either.
  It is recorded once here because it was recorded eight times. Five entries
  across five sections asked "load it or delete it" as if it were open, in
  `Restructure`, `Measured subtraction candidates`, `Questions that expose
  weakness` and twice in `Bach, Dilla, Aydın Esen`; two more cited it while
  making a different point. Every one predates the measurement, none had
  looked for the reader, and the answer was the same for all eight.

- **`SILENT_RESCUE` 26 belongs to dilla's owner.** Every one is in STUDIO and nineteen
  are in dilla, where a `rescue StandardError` around an optional gem call is
  load-bearing for a render. Narrowing one on an outsider's judgement is the change this
  repo's own rules say not to make.
- **`STUDIO/dilla/live/` is eight files and reads like one subject** — `rack.rb`,
  `recall.rb`, `dig_crate.rb`, `dig_crate.sh`, `broadcast.sh` and three `*.als.rb`
  Ableton writers. Folding it is the obvious win and it is not an outsider's to take:
  these render real audio.
- **`growth.rails` taxes a test at the rate it taxes sprawl, and the fix is decided
  but cannot be landed from one tree.** The row cannot tell a new test from a new god
  class, so coverage and sprawl spend the same allowance. Two rows per tree, `source`
  and `test`, keyed off whether the path is under `test/` or `spec/`: sprawl stays
  resisted and coverage is free to grow. What blocks it is not the judgement. Splitting
  re-bases eight ceilings across four trees at once, and a low recorded while another
  session has uncommitted work in that tree is not the recording session's to hold —
  the mistake this file records twice. It wants a sitting when all four trees are
  settled.

### Two repairs live only on the box — 2026-09-10

Both were made by hand to get master deployed and neither is in git, so both
come back the moment something restores what they changed. Recorded here
because an undocumented production edit is the same defect as an inert
declaration, wearing the other coat.

**1. `MASTER/Gemfile.lock` on the box has had its `CHECKSUMS` section deleted.**
Backup at `/tmp/Gemfile.lock.bak`, which the next reboot removes. The committed
lock carries 26 empty `CHECKSUMS` entries; `BUNDLE_FROZEN=true` exists to stop
the daemon writing its own lockfile, so Bundler could see the problem and was
forbidden from repairing it. The TTS worker died on it at every boot —
`/health` read `status: unavailable`, `checks.tts: false` — and the deploy's
smoke step correctly refused. `rc.d/master:79` already carries a comment about
this exact failure.

Restoring the box's lock from git undoes the repair and takes TTS down again.

*The root cause is upstream of the lock, and the fix is written down here because
it cannot be landed without a deploy window.* `MASTER/Gemfile:47` guards
`rb-kqueue` behind a runtime `if RUBY_PLATFORM =~ /bsd/` rather than an
`install_if` block, so the lockfile is host-dependent by construction: a Mac
evaluating that Gemfile never declares the gem, and no
`bundle lock --add-platform x86_64-openbsd` can add it. `install_if -> {
RUBY_PLATFORM =~ /bsd|dragonfly/i } do … end` is the shape that fixes it —
Bundler resolves and records the gem on every host and installs it only where the
lambda holds, so one lock serves the Mac and the box.

**What stops it being a two-line change is that the halves cannot be split.**
Under `BUNDLE_FROZEN=true` a Gemfile that declares a dependency the lock does not
carry fails at `Bundler.setup`, so the Gemfile edit forces a lock regeneration in
the same commit — and the moment a commit touches `MASTER/Gemfile.lock`, the box's
`git pull --ff-only` conflicts with the hand-repaired copy that is currently
keeping TTS alive. It also does not by itself fix the 26 empty `CHECKSUMS`
entries, which are a second fault of the same file. So this is one change, applied
during a deploy the operator is watching, verified by `rcctl restart master` and a
`/health` reading `tts_socket: true` — not a repo edit that can be made and left.

**2. `.master/tts-worker-0.log` and `-1.log` were `root:master`, and the daemon
runs as `master`.** It could not write its own log and died with `EACCES`
before opening a socket, so `checks.tts` went true while `tts_socket` stayed
false. `chown master:master` and both sockets came up. Whatever created them as
root will do it again on the next restart that recreates them — that writer is
unidentified and is the thing to find.

A cheap guard for both: `/health` already reports `tts_socket`, and
`bin/operator vps state --remote` does not. Surfacing it there would have named
this in one command instead of four deploy passes.

### The box, verified 2026-09-09

`MASTER/bin/operator vps state --remote` is the only honest way to answer this and it is
cheap:

    dev: /home/dev/pub4 @ 5084461dc
    master                             service=ok  :53187 listening
    brgen     deployed=4219192a0 DRIFT  svc=ok     :38182  2026-09-08
    amber     deployed=54fb1d990 DRIFT  svc=ok     :61352  2026-08-29
    bsdports  deployed=480239f89 DRIFT  svc=ok     :47312  2026-08-22

All four are up and the drift is real. The box's checkout is nine commits behind
this branch. What remains is a deploy, which is an operator action rather than a
blocker.

**Two deploy hazards, both paid for once already.**

Stashing vm23's `Gemfile.lock` to fast-forward the checkout is what broke master.
The Mac-committed lock carries an empty `CHECKSUMS` entry for `ffi`, and
`BUNDLE_FROZEN=true` — which exists to stop the daemon writing its own lockfile —
means Bundler cannot repair it, so the boot dies in `Bundler.setup` and
`vps-deploy all` halts the whole pass. **Do not stash the box's locks.** A plain
`git pull --ff-only` succeeds with them dirty, because no commit here touches them.
Recovery is `git checkout stash@{0} -- MASTER/Gemfile.lock MASTER/web/Gemfile.lock`.

And a deploy can take relayd down. Mid-pass it died with `rsae_send_imsg:
imsgbuf_flush: Broken pipe` → `relay: pipe closed` → `parent terminating`, while
every app port stayed open. All four hosts read `curl 000`, including `ai.brgen.no`,
which nothing had deployed — the shape `OPENBSD/CLAUDE.md` describes as the front
door rather than a backend. `relayd -n` validated, and `doas rcctl restart relayd`
restored it. Check `rcctl check relayd` after any deploy that restarts master.

**MASTER's voice is `en-US-JennyNeural`** (`data/voice.yml`), and vm23 speaks
with whatever it booted on: the daemon reads that file at boot, so the change is live
only after a deploy and `rcctl restart master`. The browser half comes from
`Policy.browser_payload` in the page, so a stale `face.runtime.js` on the box would
keep the old fallback for anyone whose payload fails to load.

### The ratchets, and the two budgets that had stopped measuring — settled 2026-09-10

Every row `MASTER/bin/operator measure` prints is green or is another tree's. Read the
live figures there; this list goes stale in a day and has done so repeatedly.

**`spine.lib_body_ceiling` is sponsored at 38,148 and the argument is in
`data/spine.yml` under `raised`.** The previous entry here said the raise could not be
made because "nobody who did not write them can say" what the lines buy. That was
answerable: `git log` the directories that grew, and every commit names its purchase in
its own subject line. The 684 lines are six subsystems rather than one drift, more than
half of it `lib/review` learning to decide deterministically what it used to send to a
model. `consecutive_raises_allowed` is 2 and both now stand, so **the next breach
cannot be raised** — it has to be paid out of `lib/`, or the allowance itself has to be
re-argued.

**`loc_body_budgets` changed its rule and not only its numbers, and that is the part
worth carrying forward.** Its header said budgets only ever decrease and a breach is
paid by extraction or deletion, never a bigger number. Held to the letter, that
sentence has a consequence nobody chose: an over-budget row detects nothing. Once a
subsystem is past its ceiling, every further line it grows is invisible, because the
row already reads OVER and cannot read more so. Eight of twenty-four had stopped
measuring, and `rake audit` failed on `loc_budget` on every pass regardless of what the
pass changed — which is how a gate becomes noise, and this table's own history is that
it spent its whole life uncalled for that kind of reason. The rule is `data/spine.yml`'s
now, stated in the same words so the two ratchets say one thing, and each of the eight
raises names its purchase in the file.

Three things the deletion question settled, kept because they are the reason not to
re-open it. **Nothing in `lib/` is dead** — `tools/code_reach.rb` reads 0 of 405 and the
ratchet row exists to hold it there. **Extraction moves the number the wrong way**,
because the counter is body lines across `lib/**/*.rb` minus the Zeitwerk wrappers, so
splitting a file adds a `def` and an `end`. **De-duplication is worth about thirty
lines** against an overage in the hundreds; `CrossFileAnalysis` names six DRY pairs and
three were collapsed for 31.

**What did pay was a deletion nobody had found, and the way it was found is the
method.** `ground/unified_diff_editor.rb` was 133 body lines. It had been read as
"unwired" and recorded here more than once. The question that finally moved it was not
"does anything call this" but "what is this a second copy of", and the answer was three
live mechanisms: `Io::PathGuard`, `DiffStager::Entry#diff_stats` and `Diffy::Diff`. Ask
that of the next orphan before recording it again.

**The census was wrong twice before it was right, and both were the same family of
mistake.** The first version whitelisted file extensions, so `bin/cli` and the
`Rakefile` were invisible and two live files read as dead. The second excluded `:` from
its lookbehind, so every caller writing `Ground::BootChecks` was invisible and it
reported thirteen files — 975 lines, against a 977-line overage at the time, which is
exactly the kind of coincidence that should stop you. The tree was quarantined to test
it and the runtime refused to boot on `Ground::BootChecks.run(root:)`, a call the
census had just declared absent. A `\b` after a `?`, a lookbehind excluding `.`, a
lookbehind excluding `:` — three now, all the same shape. Both traps are fixtures in
`test_code_reach.rb` and both go red under mutation.

**Every readable row now reads `at`: 52 of 52, none over and none slack.** The eleven
that read `unreadable` are `--deep` CSS budgets and the two ratchets whose own tests
fail in both directions; they need a browser run rather than a decision. The rows this
section used to list as slack — `growth.studio` at 146/153, `self_findings.law` at
279/287 — were prose quoted from a previous entry rather than read from the task, and
both are at their ceilings. **Read `bin/operator measure`. Do not quote this paragraph.**

### How the spine ratchet must be used

The number, its raise log and the reasoning behind every move live in
`data/spine.yml`, which is the file `rake lint:spine` reads. This section held a copy
and the copy drifted, which is the two-source failure this register warns about
elsewhere in its own words. What belongs here is the rule the ratchet taught, because
it is not in the mechanism.

**Ratchet once, at the end of a session, on a settled tree.** An intermediate ratchet
has already locked in a state that was not clean and blocked the work that would have
made it so (2026-08-03). And on 2026-08-12 a ratchet taken while three other sessions
had uncommitted `lib/` edits recorded a low that was not the ratcheting session's to
hold — in a shared checkout the honest moment is after the tree stops moving, not
after your own part of it does.

**A breach is paid out of `lib/`, not out of this file.** Three of the four breaches so
far were closed by deleting code nothing referenced; the fourth was a raise, and it
needed the operator to sponsor it because the orphan account was empty. That sequence
is the mechanism working. `rake lint:spine RATCHET=1` clears the raise log when `lib/`
genuinely falls, which is what makes the allowance a budget and not a countdown.

**Measure in a clean worktree, never in the shared checkout.** On 2026-08-14 the same
change read `39251/39258` locally and `39298/39295` at `origin/main` — 47 lines of
skew, entirely other sessions' uncommitted `lib/` edits. The shared-tree number is not
wrong about that tree; it is a reading of a tree nobody is going to commit.
`git worktree add --detach <path> origin/main` and run the task there.

**The orphan account is empty, and it has read empty at every audit since
2026-08-12.** Zero dead private methods across `lib/`, zero unreferenced constants,
and the classes a conservative sweep flags are false positives — scanner rules reached
through `RuleDSL`, `RubyRunner` called from `RAILS`. So "make `lib/` fall back first"
no longer names a cleanup anybody can do on the way past. Expect every feature to
arrive as a raise, and read a green `lint:spine` as "the ceiling was moved to meet it"
rather than as "the spine held".

### Declared and never wired

The repo's own dominant defect at method level: a check that was built and never
hooked up. Deleting one destroys the evidence, so they are recorded.

**All three that were open on 2026-09-10 are closed, and they closed three different
ways — which is the finding.** One was wired, one was deleted, and one was deleted for
a reason that had nothing to do with being unwired. "Wire or delete" is the rule and it
is not a coin toss: what decides it is what the thing would be a second copy of.

**The instrument that finds the next one is the event bus, in one direction only.**
Comparing published topic names against subscribed ones over `lib/`, `bin/`, `tools/`
and `web/app`: published-never-subscribed is 238 of 285 and every row is noise, because
`*` and `**` wildcard subscribers consume the lot. Subscribed-never-published is 4, two
of them those wildcards, and **both of the remaining two were real**.
`Trace::Ledger::Swallow` subscribed to `swallow:error` while `Ground::Swallow.log`
publishes `error:swallowed` — the same two words the other way round — so the ledger
that exists to make a swallowed error visible had never counted one, and its test
published the subscriber's spelling on a fake bus, so both halves agreed with each
other and neither with the producer. It now goes through `Ground::Swallow.log`, and a
rename on either side fails. The second is the face's mood channel, recorded below
because it is an operator decision rather than a defect. **One direction of a census
being 100% noise does not make the other direction worthless; run both and read the
smaller list.**

**`unified_diff_editor.rb` went, and the reason is worth keeping: it was not merely
unwired, it was a second source for three live mechanisms.** `applyable?`'s
immutability and traversal checks are `Io::PathGuard` and `Fix::DiffStager#stage`;
`summary`'s add/delete counting is `DiffStager::Entry#diff_stats`; `build_single_file`
is a hand-rolled `Diffy::Diff`. Nothing was ever meant to apply a diff through it —
`Fix::PatchApplier` applies one, to a temp copy of a single source, through `patch(1)`.

**What the deletion found on the way past is real and is fixed.** `patch(1)` handed a
diff naming two files applies the first file's hunks to the source it was given, then
prompts `File to patch:` for the second and reads the answer off the diff on stdin,
leaving a `.rej` in whatever directory the process is in. Measured: the temp file came
back half-edited and an `Oops.rej` was written to the working directory.
`PatchApplier.apply` refuses a second `---` header before the shell now, and
`test_fix_patch_applier.rb` pins it.

**`maturity_scorecard.rb` was wired rather than deleted, and its first honest reading
was eight rows of debt.** `bin/doctor` prints `summary_line` under the boot receipt —
the receipt says what booted, the scorecard says what has been proven and when — and it
names how many rows are past `EVIDENCE_SHELF_LIFE_DAYS`, set to 30 because a `verified`
taken off month-old evidence is a claim again. All eight were re-verified on 2026-09-10
and each row carries what was read, so the count is 0 of 8. **The re-verification is
cheap and the shelf life is thirty days: expect this to read 8 of 8 again in a month,
and re-read the predicate rather than re-dating the row.**

**The posture, settled 2026-09-10, is warn — and the funnel already had one.**
`Voice::OutputGuard#validate` runs in `CLI::Stages::Render`, beside
`Review::OutputCheck`, and its issues arrive as findings in the same list, are
published on the same bus and annotate the reply the same way. Refusing was
rejected: `render` is the last stage before the operator sees anything, so a
refusal drops MASTER's answer to punish its phrasing and reads as a hang.
`Ground::Tool::Protocol`'s two predicates reach a caller through the check
written for its third requirement — a fenced shell block plus a past-tense claim
and no prompt or exit code beside it. Measured before wiring, on the harshest
corpus available: 13 of 222 paragraphs of MASTER's own documentation trip
`validate` at `:routine`, which is the rate a warn can carry. **If it turns out
noisier in a session than in the docs, scope the context rather than delete the
check** — the two claim regexes are ordinary English verbs and `:routine` is
where a fabricated claim actually lands.

What this entry used to claim, corrected because a stale orphan list sends the next
reader hunting callers for methods that have them or do not exist:

- `review/security.rb`'s `safe?` (`:89`) and `clean!` (`:91`) are called from
  `MASTER/lib/io/web_fetch.rb:108` and `:111`.
- `provider_quarantine.rb`'s `record_and_assess` (`:44`) is called from
  `model_router/diagnostics.rb:42`; `escalation.rb`'s `next_escalation_tier` (`:58`) is
  called at `:34` and pinned by `test_provider_quarantine_wiring.rb`.
- `ground/policy/workflow.rb` has no `autofix?` and no `confirm?` — its methods are
  `phase`, `workflow`, `gates` and `brief`, and neither word appears in the file.
- `provider_quarantine.rb` has no `route?`. Its predicate is `quarantined?`.

### The rule corpus

Live figures from `bin/operator measure`, `rake lint:rule_reach` and `rake lint:rule_audit`
on 2026-09-10. `data/rules.yml` declares **242** rules, of which 141 carry
`detect_semantic`, 15 `detect_structural`, **0 `detect_lexical`**, and **92** carry no
detector field and resolve through `law/` or a `folded_into`. `law/` holds 118
`Law.define` blocks and the registry builds 147. `rule_reach` is 70 of 70: 115 rules
run without a model, 74 need one, 70 are dropped by the info filter.

**92, not 86, and the correction is the instrument again.** 86 was `242 - 141 - 15`,
which assumes the two detector keys are disjoint. Six rules carry both. Count the rules
that carry neither rather than subtracting the ones that carry either.

Still open, and each is a decision rather than a sweep:

- **136 registry rules sit outside `rule_deps`**, floor 136 and down only. A rule
  outside the graph is one `RuleOrder` cannot sequence.

Closed on 2026-09-10, with the argument, because each was open on a wrong reading:

- **The five mechanical transforms are four impossibilities and one that is not worth
  it.** `WHITESPACE_PUNCTUATION` is `folded_into: SQUINT_TEST` and has no detector of
  its own to hang a transform on. `NO_UPDATE_ATTRIBUTE`'s whole subject is that
  `update_attribute` skips validations and `update!` does not, so a blind rewrite
  changes behaviour at every call site — deciding whether the record still validates is
  the work. `QUOTE_VARIABLES` and `DOUBLE_BRACKET` both change word splitting, and
  OPENBSD carries `/bin/sh` scripts where `[[` does not exist. `EN_DASH_RANGE` is the
  only value-preserving one, and after its narrowing it has five real subjects in the
  whole repo, two of them in this file. All five stay `autofix: false`, which is what
  they already honestly said.
- **The 39 silent rules are silent for one reason, not two.** `rule_audit` measures
  `law.values.select(&:scannable?)` — rules that have a detector — so a rule cannot be
  in that list for want of one. `FROZEN_STRING_LITERAL` is defined in `law/ruby.rb`,
  `MEANINGFUL_NAMES` and `WHY_NOT_WHAT` in `law/universal.rb`. "No `detect_*` key in
  `data/rules.yml`" and "no detector" are different claims, and the entry that asked to
  separate them had conflated them.
- **`lint:principle_trace` reads 81 of 81.** It is at its ceiling, not twenty under
  it. The green-gate list in this file had it right and this entry had it wrong.
- **Two learned smells are gone**, and they failed a second test rather than the
  uniqueness test. `frozen_string` scored five over `lib/` and `law/` and all five were
  other rules' worked examples; its premise is wrong besides, since a percent literal
  in a `frozen_string_literal` file is frozen and `String.new` is how you deliberately
  ask for a mutable one. `future_tense` scored twelve and not one was a hedge: six were
  a detector's own text and the rest were refusal messages naming a consequence in
  correct English. The list is three now, and `data/rules.yml` records both the test
  they failed and how it differs from the one the earlier four failed.
- **`rule_hygiene.statement_conflicts` is 0.** `BE_CONCISE`, `PRESERVE_FIRST` and
  `SIMPLEST_WORKS` resolved the opposite way round from the eleven before them: a
  `practice` cannot fire on a line, so for those three the detector is the catalogue's
  and `law/practice.rb` holds the conduct. The practice takes `data/rules.yml`'s `fix`
  and `severity` verbatim. `SIMPLEST_WORKS`' practice had been about god classes, which
  is `NO_GOD_CLASS`' subject and has a structural detector, so that clause went rather
  than being reworded.

### Rule and AST-detector backlog

Deterministic detectors in `MASTER/lib/review/scan/rules/`, following the
`MiddleManRule` / `NOISE_NAME` pattern. Already built — do not re-list these as todo:
`BOOLEAN_TRAP`, `DATA_CLUMPS`, `TYPE_IN_NAME`, `NUMBERED_NAME`,
`LONG_PARAMETER_LIST`, `PRIMITIVE_OBSESSION`, `FEATURE_ENVY`, `COUPLER_SMELLS`,
`LAZY_CLASS`, `SPECULATIVE_GENERALITY`, `NO_SHOTGUN_SURGERY`, `TEMPORAL_COUPLING`.

**`LAYER_CAKE` and `DEAD_ABSTRACTION` are decided against**, with the measurement, at
`MASTER/DECISIONS.md`. Neither was blocked on the cross-file index. `DEAD_ABSTRACTION`'s
class half was recorded here as one finding and there are **none**: a Prism walk for
classes whose every method raises `NotImplementedError`, proved against a planted file
first, reads zero over `lib/`, and the three abstract declarations the tree holds carry
six implementers apiece or are `Scan::Rule#check`. Reopen either only with a finding in
hand.

#### Larger AST work — closed 2026-09-10, four against and one already built

The five that stood here were a wish list with no measurement under any of them. Each
was measured; the arguments are in `MASTER/DECISIONS.md` and none is open.

The **cross-file symbol index** has no consumer left and is mostly built besides:
`tools/method_graph.rb` is a name-based call graph over all of `lib/`, and thirty lines
of Prism answered "who implements this" for `DEAD_ABSTRACTION` above. The
**incremental scan cache** wants a bottleneck it does not have — a full `lib/` scan is
13.0s over 410 files, about 32ms a file, and the minutes a `/through` pass takes are
the council. **tree-sitter** buys real JS and SCSS parse trees at the price of a native
extension, in the tree whose first sentence is that it is pure Ruby and which deploys
to OpenBSD. The **clone-to-extract autofix** has three subjects in all of `lib/`, one
of them already judged not worth extracting, and rewriting method boundaries is the
riskiest transform available to a pass that has mangled one file in three. The
**prose and CSS detector** idea is `law/prose.rb` and `law/css.rb`, both live; the
audio half is dilla's owner's.

### `rake test` is green — 2026-09-10

**This section once said `rake test` "cannot complete on a dev Mac at all", aborting
on `cannot load such file -- rack/test`. That has not been true for some time:
`rack-test` resolves here (`MASTER/Gemfile:32`, lock 2.2.0) and the task runs to the
end.** Believing it is why three dead test files went unnoticed once.

    2236 runs, 6789 assertions, 0 failures, 0 errors, 17 skips   (174s)

Measured in a clean worktree with `spine.lib_body_ceiling` sponsored. The last red
was `TestRatchets#test_no_ratchet_is_over_its_ceiling`, and it went green when the
ceiling was argued rather than when anything was hidden.

`test_no_ratchet_is_slack` skips rather than fails whenever the measured trees are
dirty, which in a shared checkout is most of the time; read it in a clean worktree
before believing it green. The skip count moves with host capability too — 12 and 17
have both been recorded the same week — so a change in it is not by itself evidence
that something stopped measuring.

**`docs/SEVERANCE.md` does not exist, and both documents that name it now say so.**
`MASTER/DECISIONS.md:126` records the rename and the deletion, and
`MASTER/START_HERE.md:89` writes "the record of it went with `docs/`". The standing
policy on media-generation severance survives only as `DECISIONS.md:124-128`, and that
is where to read it. Do not restore `io/lora_pipeline.rb` or `video_chain.rb`; if the
LoRA training loop needs generation capability again, express it as
`lib/core/world.rb` handlers.

**`TODO.md` is deliberately not in `test_doc_paths`' `DOCS` list, and that half of the
gate is closed as a decision rather than left open.** It cites 428 repo paths and 34 of
them name subjects that are gone on purpose — `MASTER/DEBT.md`, `docs/SEVERANCE.md`, the
deleted `io/lora_pipeline.rb` — because a register that records what was removed has to
be able to say what it was. A 34-row baseline breaks the week somebody records another
deletion, which turns this file's own function into a red gate. The argument sits beside
the list in `test_doc_paths.rb`. `TREE.md` went in instead, at zero missing paths: it is
the map, and a stale map is exactly what the gate is for. The checker also strips a
trailing line number now, so `file.rb:165` cites `file.rb` — the commonest citation
shape in this repo's documents had been falling outside the gate written to check
citations.

### One principle has no scanner rule, not three

Re-read from `data/principle_map.yml` on 2026-09-09. `pledge_unveil` now carries
`PLEDGE_STAGED` and `audit_logging` carries `AUDIT_APPEND_ONLY`; both read `covered`.
**`secrets_rotation` is the one left**, `rule_ids: []` and `status: gap`, and the
reason is honest: there is no rotator. Keys live in `/etc/*.env` on vm23.
`test/test_principle_evidence.rb` pins that, and pointing `rule_ids` at
`LEAST_PRIVILEGE` or `SECRET_PROXIMITY` would close the map gap without measuring the
thing the row names. **A registered rule that detects a credential which never expires
is still the gap. Do not point `rule_ids` at a neighbour.**

Worth reading beside it: the map holds 272 principles of which 176 carry empty
`rule_ids` and 175 read `gap`. Three named rows were never the shape of that debt.

### Test coverage

**69 of 404 `lib/` files have no test or spec naming any constant they declare**,
measured 2026-09-10. **The definition is most of the number and the entry that quoted
119 did not carry one.** Read as "the innermost class or module", meaning the last
constant a walk sees, the count is 128 — and it calls `review/scan/self_test.rb`
untested under the name `DeployChecks`, its last helper module, while `SelfTest` has a
suite. Read as "any constant, namespace segments included", the count is 1, because
every test naming `Review` vouches for every file under it. 69 is the honest middle:
a file is untested when no leaf constant it declares is named anywhere in `test/` or
`spec/`. **Quote the definition with the number or the next reader re-derives a
different one.**

The argument for closing the gap is what happens when a file gets its first reading.
Three defects fell out of the 2026-09-10 pass through this list, all in the same
sentence — a `git worktree` checkout keeps `.git` as a file and seven readers tested
for a directory, so rollback after a failed fix went off, the boot receipt reported
`commit: unknown` and `git` missing while running inside git, and every snapshot taken
in a checkout was written to `~/Downloads`. `MASTER/DECISIONS.md` carries the list.
**The tell was not the missing test; it was that the two tests which did exist both set
`MASTER_SNAPSHOT_DIR`, so the branch that was wrong had never run.** Look for the
branch no test reaches before looking for the file no test names.

Four more fell out when eight named constants got their first tests on 2026-08-01, all
in code that looked fine.

- `io/ssrf_guard.rb` never required `uri`. `safe_uri?` does `uri.is_a?(URI::HTTP)`
  inside a blanket rescue, so in any process that had not already loaded `uri` the
  NameError was swallowed and the guard answered false for every URL — web_fetch
  silently disabled, one `Swallow.log` line, no other symptom.
- `Permissions.blocked?` matched its blocklist with bare `include?`, so "sudo" inside
  "pseudo" and "halt" inside "shalt" made `grep -rn pseudocode lib` refuse as
  dangerous.
- `PatchApplier` kept only stderr, but `patch(1)` reports a failed hunk on stdout, so
  the most common real failure produced an empty reason.
- `GitOperations#dirty_count` counts status *lines*, not files — git collapses a wholly
  untracked directory to one `?? lib/` line.

`rake test:subsystems` runs in the `operator` and `contributor` profiles, so
`test/{cli,io,fix,lib}/` is no longer skipped by the gate `START_HERE.md` sends
contributors to.

### The face's mood, and TTS on the box — operator-owned

- **The face's `mood` tint has a listener and no producer.** Nothing publishes
  `agent:mood`, so `face.part5.txt`'s tint never fires. Decide: wire a producer
  from `voice/emotion.rb`'s state (the face starts changing colour on its own)
  or delete the listener. The seam is recorded in `MASTER/web/CLAUDE.md`.
- **vm23, after the next deploy:** re-probe the one-shot Edge fallback
  (`synthesize_edge_oneshot`) with a real MP3 write, and `test -S
  .master/tts.sock`; `/health` alone is a capability check.

### Tag legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise,
  horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## RAILS

### Audit findings — 2026-09-12

- **`constitutional_scan` is over two ceilings, and every finding is a design
  value.** Re-measured 2026-09-13 on the aesthetic profile the budget counts:
  bsdports 5 against 3 (`EIGHT_PX_RHYTHM` ×3, `CHOICE_OVERLOAD`,
  `SIGNAL_NOISE`) and shared 15 against 8 (`EIGHT_PX_RHYTHM` ×6, `MAGIC_COLOR`
  ×3, and one each of `NO_DECORATIVE_FX`, `TOUCH_TARGET_MIN`,
  `CONTRAST_TOKENS`, `RAMS_UNOBTRUSIVE`, `REDUCED_MOTION`,
  `WHITESPACE_RHYTHM`). The operator decides: change the spacing, colour and
  motion values, or record new ceilings with a reason in
  `RAILS/gates/data/constitutional_budget.yml`.

### Instant — what the operator still decides

The "134 ways to feel instant" intake, once `RAILS/INSTANT.md`, closed on
2026-09-13. What was already built and what the tree refuses are both recorded
in `RAILS/shared/WIRING_NOTES.md` under "Speed proposals decided against". What
is left changes how a surface looks, or needs vm23.

- **Motion is a rendered value.** Cross-document view transitions (feed to post,
  the theme crossfade); Turbo's progress bar delay, set to 100 ms in
  `shared/frontend/hotwire.js` against Turbo's 500 ms default; feed skeletons
  shown only past ~200 ms; `:active` states; and `transition_normal`, 300 ms in
  `shared/design_tokens.yml`, against a proposed 200 ms ceiling.
- **Two failures a reader cannot see.** `action_controller.js#_rollback` reverts
  a rejected like or vote with no message, and nothing shows when the cable
  socket is down. Each needs a visible element and its copy.
- **The feed card paints no blurhash.** `lazy_image_tag` carries the
  placeholder; `posts/_post` renders `responsive_image_tag`, which does not.
- **Needs vm23.** A p95 server-time ceiling per route means something only when
  measured on the box, warm and cold; and whether relayd serves HTTP/2 or
  compresses anything is a man-page-then-measure question there.
- **Seller payouts need money.** One Stripe Connect account per seller and a
  platform balance; `Marketplace::Payout` fails closed and stays pending with a
  reason until then.

### Deploy blockers

What stops a RAILS deploy from being one command. A blocker leaves when its
unblock criteria are met. Operator-side debt is the OPENBSD section.

**1. City vanity TLS** — operator; registrar action. Blocks the first install
of a new city apex, not deploys of the live apps. `OPERATOR.sh` stage 1 issues a
certificate for every apex in `ALL_DOMAINS`, and relayd will not load a keypair
whose certificate is absent — a `relayd.conf` naming one downs every site on the
box. Unblocked when every apex resolves and serves its own certificate and
`relayd -n` passes against the repo copy on the box before install.
`domain_alignment` checks the four live apexes.

**2. relayd restart after route changes** — operator. Built; open until a real
deploy exercises it on vm23. On 2026-08-10 a restart killed relayd's `ca`
process and every site for nine minutes, seconds after the deploy logged
`relayd(ok)`. `relayd_confirm_live` in `RAILS/_service.sh` re-checks 443 for
20 s after the restart and names the shape: 443 refused with the app port
answering is relayd, both refused is the app.

## OPENBSD

### Operator debt — still open

Each item carries a hidden HTML-comment marker on its own line under its heading;
`MASTER/lib/operator/operator_docs.rb:55` counts those markers for the
`MASTER/bin/operator status` debt line, so keep exactly one per open item.

#### `libvips_local_build`  — tag: operator-priority

<!-- open-debt -->

vm23 runs a locally built libvips with svgload; `pkg_add -u` swaps in the stock
package, which has none, and amber's garment cut-outs quietly stop regenerating.
`/etc/daily.local:71` detects it. After any `pkg_add -u` touching graphics, run
`make reinstall` in /usr/ports/graphics/libvips and confirm `vips -l` lists four
svgload operators.

#### `off_host_dr`  — tag: operator-priority

<!-- open-debt -->

One purchase, an off-host object store, closes three gaps. `OPENBSD/bin/dr-pull`
keeps seven verified pulls, but on the operator Mac. `STUDIO/dilla/samples/`
(84 MB, 75 MB of it `own/` recordings) is gitignored and on one disk, and dr-pull
cannot help because the crate is already on that disk. `Shared::DatabaseSnapshotJob`
writes `VACUUM INTO` copies beside the database, and `restore_litestream.sh` restores from
an empty litestream directory. litestream is absent by decision (not in ports).

#### `multi_app_ram`  — tag: operator-priority

<!-- open-debt -->

A provider resize of vm23; done when `sysctl hw.physmem` reads at least
2147483648 (1056952320 on 2026-09-11). The standing decision is 1 GB with one
resident worker, brgen_jobs. Reproduce a start by hand only with
`--health-check-timeout 300`, and do not stand a job worker down before
`bin/vps-deploy`, which does it.

#### `home_partition_full_from_git_history`  — tag: operator-priority

<!-- open-debt -->

A coordinated history rewrite: strip the 80–87 MB WAV renders under the old
`DEPLOY/dilla/renders/beats/` and the key purge in one force-push, with a vm23
re-clone in the same hour and every session quiescent. Not pressure: /home was
69 percent on 2026-09-11.

#### `bsdports_org_delegated_to_parking`  — tag: operator-priority

<!-- open-debt -->

At Domeneshop, set bsdports.org's nameservers to ns.hyp.net and ns.brgen.no; the
registration is paid to 2027-08-08. The deadline is the certificate
(`notAfter=Nov 10 2026`), because acme-client's HTTP-01 needs the name to resolve
here. Done when `ruby RAILS/gates/runner.rb dns_zones` passes. `ALLOW_BSDPORTS_DOWN=1`
on the uptime-check crontab line comes off the same day; `bin/deploy-smoke.sh`
names the delegation until then.

### Waiting for the box

Each of these needs vm23: a root run, a man page read there, or a measurement
only the box can take.

- **One `doas zsh OPENBSD/OPERATOR.sh` run closes the drift.** Ask
  `SSH_HOST=dev@brgen.no ruby OPENBSD/config_drift_gate.rb --remote`, never a
  list; the repo is the newer side everywhere. `emergency_cpu.sh` (the only thing
  `resource_guard.sh`'s crisis tier runs), `vps_weekly_integrity.sh`, its root
  crontab line and `/var/log/pub4/` are absent, so the weekly integrity pass has
  never run.
- **relayd restarts five times per `vps-deploy all`.** Each rc.d script and
  `start_all_apps.sh` run `rcctl restart relayd` once an app answers `/up`,
  dropping the one TLS listener; the 2026-08-10 nine-minute outage was that.
  `relayctl table disable|enable` and `relayctl poll` do the kick without touching
  the listener. Read relayd.conf(5) and relayctl(8) on vm23 and bracket one app by
  hand first.
- **The `rails` login.conf class caps datasize at 4096M on a 1 GB box**, and
  `openfiles-cur` inherits 128. Set per-app `datasize-cur` from each app's
  steady-state RSS measured on vm23; a number guessed low kills a healthy app.

## STUDIO

Re-measured 2026-09-11 against the real crate. `samples/` is gitignored, so a
worktree shows an empty crate that is not; dilla is under active edit, so trust
symbol names over line numbers.

### The owner's calls

- **The crate holds `drums`, `dug`, `own` and `rauingar`, and no 124 racks.**
  `74d9e4c1b` cleared it on 2026-08-16 on the operator's call; only he can say
  whether he expected the racks back. `samples/dug/` is down to one record, and
  the other 160 sources cannot be re-fetched to the same bytes.
- **Which crate layout survives.** The engine reads `samples/chopped/loops.json`
  through `RadioChop.registered_loops`; `lib/crate_dig.rb` writes `samples/dug/`
  from public-domain archives; `live/dig_crate.rb` rips YouTube and warns on every
  run; `bin/crate` declares a `crate/` layout that no longer exists.
- **`ruby STUDIO/dilla/dilla.rb assets` exits 1**: three loops missing, eight files
  changed (seven re-synthesised one-shots, and the `rauingar` re-cut).
  `dilla assets record` blesses whatever is on disk, so it is the operator's.
- **Two staging directories outside the repo.** `~/dilla-crate-incoming` holds two
  source FLACs and their demucs stems from an abandoned 61-track fetch;
  `~/Music/dilla_sines/` is a running installation beside three drifted twins of
  tracked scripts. Keep, move or delete is his, never an agent's.
- **Sound that moves under a pinned seed.** Eight bare `rand` calls and one
  `.sample` in `dilla.rb` escape `render_rng`, which is why a pinned render moves
  about 0.012 dB. Routing each changes what that site renders: one site at a
  time, by ear.
- **The `HARM_VOL` bump stays a pass behind itself**: 2.4 plus 0.05 is the 2.45
  default, and raising the base is a mix value (`composition_engine.rb`).
- **Chop rows in `TRACK_PRESETS`**, when there are chops again. A slug with no row
  falls through to `:timeless`; the `sheger_*` derivation in `dilla.rb` is
  mechanical and whether it sounds right is his.

### Blocked while `dilla.rb` is under another session's edit

- **Classify dilla's default-off flags** into additive, exclusive fork and
  operational, and delete the dead ones. `lib/knobs.rb` is the instrument (727
  knobs, 286 flags, 206 default-off); the counts in `dilla.rb`'s own comments
  are stale.
- **Four hand-built RIFF headers**, at `dilla.rb` (two), `lib/devices.rb` and
  `bin/sine_stream.rb`, where `wavefile` is declared and used at
  `lib/music_gems.rb:231`. Container bytes only; prove identical output bytes
  without rendering a take.

### Guards

- The eight `sheger_*` rows are half alive: the preset rows are live and tuned,
  the bed aliases point at a cleared chop. A test pins both halves; delete
  neither.
- The monolith stays. `DILLA_SUPPORT_CEILING` (56, any depth) leaves no room for a
  destination file, so any split starts by folding support code, and 14 support
  files use `__dir__`/`__FILE__`. `dilla parts` indexes the engine.
- Not worth chasing, each measured: folding `dilla/live/` (three arrangements,
  and renames break journal replay); merging the three techno renderers (three
  sounds); blanket rescues in STUDIO (optional probes and teardown); preset reach
  in `postpro`/`lora` (selected by name from argv; `vocab_check` owns it); the 37
  stale `sample_worth.json` slugs (pruned on the next chop); the sample rate
  declared under three names (all namespaced; `sample_worth.rb`'s 11,025 is
  deliberate); the `cohesion.rb` regroups; and the three engine probes that skip
  under suite load while passing alone.

## Cross-cutting programs

- **Bringhurst: `line-height` literals do not come off `--leading-*`.**
  `css_constitution.rb:61` lists `line_height` with no reader; 87 literals across
  the fleet on 2026-09-10, seven in `face.css`. The detector is a `css_budget` row
  held at today's count; moving a literal onto a token is the operator's, because
  it changes leading.

## The layout pass — open

**Seventeen control classes paint a border beside a fill**, from `.deal-cat`
(`_marketplace.scss:48`) to `.pager-link`, which the 2026-08-04 decision traded
away (`WIRING_NOTES.md`). Whether that decision reaches controls is a rendering
call, and the operator's. The pass's doctrine lives in `WIRING_NOTES.md`.

## From the 2026-09-01 audit

- **The browser half of the gates runs nowhere unattended.** vm23 cannot host it
  (Chrome under 1 GB sheds amber and bsdports; the argument sits beside
  `PUB4_DEPLOY_BROWSER_GATES` in `vps-deploy`), so it needs a second host.
  `GATE_STRICT_ERRORS=1` can join the deploy line once someone has read one
  ledger's worth of errored gates.

---

# Forward work

Wishes and measured proposals not yet shipped; each section is dated.

## Open from the enumerations — 2026-09-09

- **`NO_GOD_CLASS`.** `bergen_demo_seeder.rb` stays at 337 against 300: sixteen
  private per-vertical methods under one `seed!`, and splitting it is ten
  one-caller files. `brgen/app/models/conversation.rb` (IRC channels, geo rooms,
  unread counting) and `takeaway/order.rb` (state machine, delivery and ETA,
  display formatters) are several subjects each and want splitting.

## From the awesome-list horizon scan — 2026-09-11

- **Autofix classifies by transform, not per rule.** `Scan::Finding` declares
  `reversibility` and `blast_radius`, `semantic_rules.rb` and `meta_rules.rb` fill
  them, and nothing under `lib/fix` reads either.

## The refinement inventory — opened 2026-09-11

`ruby MASTER/tools/refinements.rb` scans every tracked file in the four trees
and groups what it finds into batches: one rule, one kind of edit, a known file
list. `--items` prints every finding, `--tree` and `--rule` narrow it. The list
is not written down anywhere, because a written copy of a scan is stale the day
it is made. Run the tool.

It reads **22,417 findings in 3,333 files across 131 groups**, and that number
is an upper bound on an unverified instrument, not a count of defects. Thirty
were sampled and read against their source. Roughly a quarter were actionable.
The rest were the scanner misreading correct code, and the misreadings have
shapes worth naming, because each one is a rule to fix rather than a file:

- `magic_number` (4,492) counts array-slice bounds, quantifiers inside a test
  assertion's regex, and event codes. `[0, 200]` is not a constant wanting a
  name.
- `NO_PUTS` (807) counts CLI tools, rake tasks and probe scripts, where `puts`
  is the interface rather than a debug statement.
- `duplicate_code` (784) counts locale YAML values, Markdown prose and
  comments. "Text to copy" appearing twice in `en.yml` is a translation.
- `FILE_SPRAWL` (664) and `SMALL_FILES` (261) report a per-directory condition
  once per file, anchored to line 1, and count migrations — which accumulate by
  design.
- `CONFIG_HIERARCHY` (913) counts route fragments in gate flow fixtures and
  prompt template lines in `council.yml`.
- `TYPOGRAPHY_DISCIPLINE` (474) counts ASCII box drawing inside comments, which
  is `NO_ASCII_LINE_ART`'s question and cosmetic in a comment either way.

**The exemption marker trips two rules by existing.** 154 findings sit on lines
carrying `scan: intentional`, and 135 of them are `LONG_LINE` and
`TRAILING_COMMENT` — the marker is a trailing comment, and adding it pushes the
line past the length limit. Every author who exempts a line correctly buys two
new findings. Fix the two rules to skip a line whose only overage is the marker
itself, and the count falls without a single file being touched.

### The deterministic tier — 1,888 findings in 607 files

These are the ones worth working. Each is mechanical, each has one right
answer, and a wrong fix shows itself in the diff it makes. One group is one
session. Counts are findings, then files, which is the number of jobs.

- **`TRAILING_COMMAS` — 489 in 188 files.** RAILS 432. Add the comma to the
  last element of each multi-line literal. Autofixable: `add_trailing_commas`.
- **`TAB_CHARACTER` — 322 in 8 files.** OPENBSD 315. Eight files, whole-file
  conversion each.
- **`DOLLAR_PAREN` — 287 in 60 files.** Backticks to `$( )` in shell scripts.
- **`DOUBLE_BRACKET` — 181 in 8 files.** All OPENBSD. `[[ ]]` to `[ ]`, so the
  script runs under `sh`. This one matters on the box.
- **`FROZEN_STRING_LITERAL` — 176 in 176 files.** One magic comment each.
- **`NO_ASCII_LINE_ART` — 175 in 48 files.** STUDIO 94. Keep the words, delete
  the box.
- **`NO_COLUMN_ALIGN` — 143 in 31 files.** MASTER 103. Collapse aligned columns
  to single spaces.
- **`NO_GOD_CLASS` — 29 in 29 files.** RAILS 22. Not mechanical, but each one is
  a class that has outgrown a single subject and already shows the seam.
- **`SILENT_RESCUE` — 23 in 11 files.** STUDIO 22. `Ground::Swallow.log` is the
  house form.
- **`STRICT_MODE_ZSH` — 18 in 18 files.** OPENBSD 15.
- **`NO_VAR` — 15 in 7 files.** `let` or `const`.
- **`NEVER_BATCH_DELETE` — 13 in 9 files.** Read each before touching it; some
  will be correct and want the marker instead.
- **`FAIL_VISIBLY` — 5 in 5 files.** A failure reported into a return value that
  nobody reads.
- **`RATE_LIMITING_MISSING` — closed, 1 of 4 was real.** `Tv::VideosController#create`
  takes a video upload and had no throttle; it has 10 in five minutes now.
  The other three were the rule reading file scope: `shared/authentication.rb`
  and `dating/base_controller.rb` declare no actions at all, and the login and
  password paths throttle through `sessions_actions.rb` and
  `passwords_actions.rb` — 10 in three minutes, and 3 in fifteen for a magic
  link.
- **`MIGRATION_ADD_REFERENCE_NO_FK` — 1 of 2 was real, and it needs a new
  migration.** `add_reference :reactions, :reactable, polymorphic: true` cannot
  carry a foreign key, so that one is the rule misreading a polymorphic
  reference. `add_neighborhood_to_dating_profiles` could, but the migration has
  run on vm23 and an edit to a migration that has already run changes nothing —
  the fix is a new migration, and it wants a check for orphan `neighborhood_id`
  rows before the constraint goes on.
- **`NO_DEBUG` — 2, `CONTROL_CHARS` — 2, `NULL_BLINDNESS` — 2.** Three edits.

### Before working any other group

Sample five findings, open the five lines, and decide whether the rule is right
before opening the sixth. Where it is wrong, the fix is the rule and the
exemption it should carry — not the file. That is how the 981-finding design
backlog turned out to be 596 misreadings of correct markup, and it is why this
section leads with the instrument rather than the total.

## One chrome — opened 2026-09-11

Operator decision: every surface wears brgen's front page chrome — its shell,
its type, its flat light palette — and any other chrome may be discarded. That
settles three questions this repo kept reopening, and it applies to the six
verticals, to amber, and to MASTER's web face.

Measured in headless Chrome at 1440x900 against the four local surfaces, which
`RAILS/bin/triangle status` already had running. Two claims died on that
measurement and are recorded here so nobody re-derives them:

- **The verticals do not lack layouts.** All six render through brgen's
  `application.html.erb` by design — the Rails engine pattern — so they already
  carry the wordmark, the nav, the search palette, the theme and the footer.
  Counting `app/views/layouts/*.erb` per engine reads zero and means the
  opposite of what it looks like.
- **The per-vertical accent is live and correct.** tv resolves `--accent` to
  `#dc635c`, dating to `#009579`, playlist to `#0e8a94`, each the
  contrast-tuned light-mode variant. An earlier reading of `#000000` was taken
  off `documentElement`, and the accents are declared on `body` — the
  instrument, not the tree.

What is actually wrong, each seen rather than inferred:

- **The browsable verticals have no content column.** On `tv.brgen.no` the
  section intro starts at x=439, "POPULÆRE VIDEOER" at x=419, and the empty
  state is centred at 720. Three left edges on one page, where the front page
  holds a single column. This is the largest visible difference between a
  vertical and the front page, and it is a container, not a palette.
- **dating is a second chrome, and it goes.** `dating.brgen.no` renders
  full-bleed with the nav hidden, a neon heart and a 200px wordmark — the
  "immersive" variant in `_vertical_shell.scss`. Under the decision above it
  gets the nav and the column like everything else. messenger is the other
  immersive surface; same treatment.
- **marketplace 500s.** `marketplace.brgen.no` raises where tv, dating and
  playlist render. Nothing about layout can be judged there until it serves.
- **amber speaks a different language entirely.** A serif tagline against
  brgen's sans, pastel-green wordmark at roughly 1.3:1 against its own
  background, a floating "Style notes" card aligned to nothing, and a hero SVG
  whose wordmark is clipped at the left edge of its own box. Its header mark
  sat flush at y=0 — 52px of mark inside a 44px bar with no block padding —
  and that one is fixed.
- **MASTER's web face shares 13 tokens with RAILS out of 87, and all 13 are
  motion and z-index.** No colour, no type. It renders black with a particle
  face and a terminal prompt where every other surface is flat light. Under the
  decision above the face keeps its canvas and the chrome around it becomes
  brgen's. The `#primer-voice` button can go; the full-viewport `#primer`
  behind it cannot, because a browser will not start an AudioContext without a
  gesture.
- **The layout's own comment is stale.** `application.html.erb` opens with a
  long paragraph explaining that `data-theme="dark"` is load-bearing.
  `DEFAULT_SURFACE_THEME` is `"light"` and has been; the surfaces render
  `#efefef`. A comment states the present-tense reason.

Order of work: the content column first, because it is one container shared by
six verticals and it is what makes them read as one product; then amber's type
and palette; then MASTER's chrome; marketplace's 500 whenever someone is in
that engine. Screenshot before and after — this section exists because two
confident readings of the source were both wrong.

## The ad design system, and the marketplace study — opened 2026-09-11

Operator direction. marketplace and takeaway take **www.kaufland.de** as their
shell, studied against nineteen more marketplaces rather than copied from one.
Beside that, an ad design system built on photography and bold typography,
because a marketplace front page is mostly large product images and large
type — and the same system makes brgen's own ads, for the front page, the
verticals and amber. Expected to take a while and to end up automated.

The stated target is worth keeping verbatim, because it names what this is
not: **Kaufland's catalogue + bol's cleanliness + eBay's marketplace depth +
Vinted's simplicity + brgen's local and social layer** — rather than a
Norwegian Amazon. That lands on an irony the tree already recorded:
`_marketplace_nav_bar.scss` opens by saying it "was a two-row Amazon clone",
and its eleven Amazon hex literals came out on 2026-09-11.

This is a program, not an item.

### The study — twenty marketplaces, and what each is for

Research each thoroughly, and record measurements rather than impressions: a
viewport, a screenshot, the grid's column count and gutter, the type scale of
a price, the aspect ratio of a card.

- **Kaufland** — the overall shell and catalogue UX. The model for our own.
- **bol** — visual cleanliness, and the closest thing to this fleet's flat taste.
- **Allegro** — search, filtering, and handling an enormous catalogue.
- **OTTO** — merchandising and category presentation.
- **Mercado Libre** — marketplace mechanics, seller and buyer interaction.
- **eBay** — seller ecosystem and discovery depth.
- **Walmart Marketplace** — the retail and marketplace hybrid.
- **Rakuten** — marketplace ecosystem.
- **Cdiscount** — European general merchandise.
- **ManoMano** — a category-specific marketplace done extremely well; structured category expertise.
- **Etsy** — seller identity and discovery; the human half.
- **Vinted** — frictionless second-hand, and effortless listing.
- **Back Market** — condition and quality communication; trust information.
- **Shopee** — mobile-first marketplace mechanics.
- **Taobao** — catalogue depth and social commerce.
- **JD.com** — product information and logistics.
- **Temu** — discovery and conversion mechanics.
- **Zalando** — fashion marketplace and personalisation. Read this one for amber too.
- **Mercari** — extremely simple peer-to-peer selling.
- **Newegg** — electronics and product comparison.

Check every idea against the tree before calling it missing. That habit is in
this file for a measured reason: of the last external enumeration, thirty-nine
items declared themselves done and another fourteen proved already true on a
grep. A list arriving from outside is a hypothesis about this repo.

### What exists already

- **`Shared::Affiliate` is the one path over every network**, and
  `affiliate_deals_for(category:, limit:)` is its reader. A new network appears
  in every unit without editing a view.
- **`shared/_affiliate_feed_unit`** is an in-feed band: product tiles packed
  edge to edge by CSS grid with call-to-action tiles among them, a
  `parallax-tilt` Stimulus controller over it, and an `--in_grid` modifier for
  surfaces that are grids (amber's wardrobe and outfit galleries) rather than
  lists (brgen's feed). It replaced a CodePen banner that needed five CDN
  scripts, one of them GPLv3-or-paid.
- **Models**: `Shared::AffiliateProduct`, `AffiliateVoucher`,
  `AffiliateConversion`, plus amber's `AffiliateLink`. brgen has
  `AffiliateImportJob` and `Brgen::AffiliatePlaceholders`.
- **Disclosure** is its own partial, `shared/_affiliate_disclosure`, and the
  band labels itself `affiliate.sponsored`. Whatever the ad system becomes, it
  inherits that: an ad says it is one.
- **Photography has a producer.** STUDIO's repligen generates imagery and fills
  tv; lora trains on real subjects. An ad system needing product photography
  has a generator in this repo rather than a stock budget.

### What Kaufland does that markedsplass does not

Read against markedsplass.brgen.no as it renders today, and not yet verified
against the live site at a set viewport — do that first and record numbers,
because this list is a description.

- A full-bleed hero of photographic banners. markedsplass opens with a text
  headline at display size and no image at all.
- Category tiles as pictures rather than a text row. markedsplass has
  `Ting Jobb Bolig Oppdrag` as plain links.
- Offer grids with price as display type. A listing card's price here is body type.
- Image-first cards at a consistent aspect ratio, which is what makes a dense
  grid read as one surface rather than a ransom note.

### Amazon is the functional model; the visual is ours

Operator position: Amazon remains the main inspiration for how a storefront
works, and its visual execution is below this fleet's standard. So the
storefront bar keeps its Amazon structure — a search field dominating the row,
deliver-to, account, cart, and a sections row beneath — because the structure
is the part that was right. What came out on 2026-09-11 was the execution:
eleven hardcoded Amazon hex values, #131921 and #232f3e navy, #febd69 and
#f3a847 amber, #cd9042 on the cart count, in a fleet that paints from tokens
everywhere else. The bar reads --surface, --text, --text-secondary and
--accent now, so it follows the theme and carries the marketplace accent
_vertical_shell already tuned for contrast in both directions.

Kaufland and the nineteen beside it are read the same way: take the mechanism,
leave the paint.

### The external Kaufland patch, assessed 2026-09-11

A fifth log arrived proposing the catalogue redesign as one patch: replace the
storefront header with a Kaufland utility strip and an `Alle Kategorien`
control, repaint the chrome white with red, rebuild the product card, drop the
hero, and move the filters into a persistent left rail. Most of it is either
already done, already decided against, or a rendered value. Two parts are real
and are the ones worth starting from.

**Its premise was a comment rather than the code.** The patch opens by removing
Amazon's dark palette wholesale, quoting `_marketplace_nav_bar.scss` calling
itself "a faithful two-row Amazon clone". That sentence is history and the file
says so; all eleven hex literals came out earlier the same day, and `#131921`,
`#232f3e`, `#febd69`, `#f3a847` and `#cd9042` appear nowhere in RAILS source
now. The bar has read `--surface`, `--text`, `--text-secondary` and `--accent`
since. Its headline target — Kaufland's catalogue plus bol's cleanliness plus
eBay's depth plus Vinted's simplicity plus brgen's local layer — is the
operator's own sentence from the top of this section, handed back.

**And it overturns a recorded position without knowing it existed.** The
subsection above states that the storefront bar keeps Amazon's structure — a
search field dominating the row, deliver-to, account, cart, sections beneath —
because the structure was the part that was right. The patch replaces exactly
that structure. The rule for all twenty references is the same one: take the
mechanism, leave the paint.

**The DOM is the real finding, and the log names it itself.**
`shared/_live_search_index.html.erb` renders the search form — with the filter
`<details>` captured inside it — and the results turbo frame as siblings. A
persistent filter rail beside a product grid cannot be built over that shape
with CSS; the helper has to let a caller place the form and the frame
separately, or wrap both in a container it does not currently provide. That is
structural, it is testable, and it blocks the catalogue layout whoever builds
it. Do this one first.

**The second is a card contract rather than a card look.** Kaufland's density
comes from every product exposing the same fields at the same vertical
positions: image, title, rating and count, price, reference price, discount,
shipping, delivery window, seller, condition, unit price. markedsplass has the
data — listings carry variants, facets, ratings, reviews and distance — and
renders a subset in a different order per surface. A fixed ladder is a contract
a gate can hold, and `distance_km` is the field Kaufland has no answer to.

Everything else in the patch is a rendered value: the white canvas, the red
accent, `object-fit: contain` on product photography, the card's borders and
type scale, and removing the hero. Fenced, as the section below says. Build the
information architecture, measure it at a set viewport, and bring the look back
for a decision.

### Every unit is multi-city, multi-domain and multi-language

brgen is one app over roughly twenty city domains, and the marketplace
subdomain is localised per country: `markedsplass.brgen.no` in Bergen,
`marketplace.lsangeles.com` in Los Angeles, and nine more spellings in
`Brgen::DomainRegistry::SUBAPP_ALIASES` — marche, markadur, markedsplads,
markkinapaikka, marknadsplats, marktplaats, marktplatz, mercado, mercato.
`DomainRegistry.resolve(host)` is the one way to ask which city and which
vertical; never re-derive a subdomain.

That constraint already caught something. The storefront header carried a
hand-written logotype reading `markedsplass` + `.no`, and takeaway's read
`takeaway` + `.no` — hardcoded Norwegian words and a Norwegian TLD rendered on
every city, so `marketplace.lsangeles.com` said "markedsplass.no" in its own
header. Both came out with the second wordmark on 2026-09-11, which means the
fix landed as a side effect of the chrome decision rather than on its own
merits. Anything the ad system renders — a category name, a price, a call to
action, a crop with words burnt into it — carries the same exposure.

Some city domains are expired or expiring, with funding for renewal in
progress. Treat the domain list as a live set: read it, never hardcode it, and
expect a surface to be unreachable without that being a defect in the surface.

### Two search fields on one storefront, and the better-placed one is the worse one

Measured on takeaway.brgen.no and markedsplass.brgen.no at 1440x900: two
`input[type=search]` on the page with the same placeholder. The storefront
bar's sits at y=131 and is a plain `form_with method: :get` — a full page
navigation. The one in the page body sits at y=390 and is `live_search_index`,
a turbo frame with results as you type.

So the field in the right place does the worse thing, and the field doing the
right thing is below the fold. Amazon — the functional model — has one, in the
bar. The fix is to make the bar's field drive the live frame and drop the body
copy, which is a decision about where search lives on these surfaces rather
than a tidy-up, and the Kaufland pass will answer it. Left here so that pass
starts from the measurement.

### The shape to aim for

One unit vocabulary, declared once and rendered by every surface that takes
ads: hero banner, category tile, offer tile, in-feed band. Each reads
`Shared::Affiliate` or a brgen-authored equivalent through the same interface,
so a house ad and an affiliate ad differ in their source and not in their
markup. Typography comes from the existing scale rather than a second one, and
each unit fixes one aspect ratio so the grid holds.

Automation is the last step. A unit a person can fill by hand and that looks
right is the thing to automate; automating the layout first produces a
generator for a design nobody approved.

### Fenced

Every colour, typeface and crop here is a rendered value and the operator is a
trained architect. Build the structure, measure the geometry, and bring the
look back for a decision rather than choosing it.

## What the snapshot gate was really reporting — closed 2026-09-11

`rendered_suite` failed on sixty-nine surfaces, every one of them
`LayoutSnapshotGate`, against baselines last written 2026-08-17. The obvious
reading was twenty-five days of unreviewed drift. It was not: the gate was
comparing against a key format that no longer existed.

`walk.js` was extracted from a Ruby heredoc into a file read verbatim, and
three regexes came with their heredoc escaping intact. In a heredoc `\\s` is
what you write to get `\s`; in a file read as bytes it stays two characters,
and `/\\s+/` in JavaScript matches a literal backslash followed by one or
more letter s — which nothing on any page contains. Verified in Chrome rather
than argued: `"brand-mark brgen-logo-mark".split(/\\s+/)` returns the whole
string as one element, and `/rgba?\\(...\\)/.test("rgb(1, 2, 3)")` is
false.

The one that mattered was in `classSig`. The class attribute was never split,
so every element carrying more than one class keyed as
`a.brand-mark brgen-logo-mark` instead of `a.brand-mark.brgen-logo-mark`, and
`VOLATILE_CLASS` matched the whole blob or none of it — which is why
`body.vertical-marketplace` vanished from ancestor paths whenever the blob
happened to end in a volatile word. 739 removals and 965 additions across 69
surfaces, none of them a layout change. Fixing it halved the removals
immediately and moved elements into the MOVED bucket, where they belong: the
instrument now compares like with like.

The other two broke the rgba fast path, which falls through to a canvas that
answers correctly — slow rather than wrong, and invisible for exactly that
reason. `gate_requires_resolve_test` now fails on a literal `\\` in any
`.js` file under `gates/`, because the next extraction will do this again.

What remained after the fix was real and all of it attributable: the edge
grips and `#q` went with the rails and the search palette (operator,
2026-08-27), the nav swiper groups went flat (operator, 2026-08-29),
`#app-tab-bar` moved because dating and messenger left the immersive list on
2026-09-11, and `#logo` went with the storefront's second wordmark the same
day. The six content-level changes were all improvements: maps gained an `h1`
where it had none, and messenger's title went from "Bergen" to
"Meldinger — Bergen". Baselines regenerated after that review, and after the
instrument was fixed — in that order, because accepting them first would have
written the corrupted key format into all sixty-nine files permanently.

## Bottom chrome and the peel handle — opened 2026-09-11

Fixing the walk unmasked `rendered_geometry`, which had been reporting against
the same corrupted keys. Six hard findings, in two groups, and both want an
operator decision rather than a guess.

**Three occlusions, and they are a consequence of one chrome.** On
`brgen/dating` and `brgen/channels`, the `.tab-bar-peel` handle's centre pixel
is owned by a link in the page — the dating intro's trust footer, a channel
card's blurb. Fixed chrome cannot be scrolled out from under a blocker, so the
handle is dead for the life of the page. It appeared because dating and
messenger left the immersive list and got their bottom chrome back, over
content written when there was none.

The fix is a design decision that `_tab_bar.scss` has already half-stated:
"Content and bottom-pinned chrome reclaim the space via --tab-bar-h → 0". So
the intent is that content takes the space and the peel floats above it, which
is exactly the overlap the gate is reporting. Either the peel floats and this
finding is exempt, or bottom-reaching content clears it and the clearance
wants a token of its own — the peel's height is `--tap-min` and nothing
publishes it. `#install-prompt` needed the same clearance and now spells
`max(var(--tab-bar-h, 0px), var(--tap-min, 44px))` inline; if a token is
wanted, that is its first caller.

**Three contrast failures, all one shape: an accent used as ink on a light
surface.** messenger's `#6b7fd7` on white at 3.72, playlist's `#0e8a94` on the
tunnel's `#14141a` at 4.44, and the storefront cart count, which ran Amazon's
`#cd9042` at 2.74 and the marketplace accent at 3.48 before taking `--text` at
12.63 on 2026-09-11.

An accent is tuned to be legible as a fill carrying ink, which is the opposite
job from reading as small text on white. The hover slot is not the answer
either: marketplace's `#6f6149` clears at 6.03 but takeaway's `#c26a30` is
3.89, and they share one storefront bar. What the map wants is a fourth slot —
a darkened per-vertical ink for text-on-light, the way `--food-dash-ink` was
picked for takeaway's eta chip. Seven colours, and every one of them the
operator's.

## The external reassessment — assessed 2026-09-11

Four ChatGPT logs and one execution brief, read against the tree rather than
taken at their word. Three of the four logs were substantially wrong about what
`main` contains, which is the usual shape: an external reader with repository
access describes the repository it last saw. What follows is what survived being
checked, and what did not, so neither half is re-derived.

### What was wrong, and stays closed

**The visibility test is not missing.** One log opened on the claim that
`MASTER/test/test_visibility_semantics.rb` had been lost from `main` while
`data/spine.yml` still sponsored it, and proposed restoring 109 lines of it. The
file is on `main`, 140 lines, with all eight semantic cases the log listed —
`public` reopening a scope, `protected` as a visibility rather than an end,
`private` not reaching the singleton stream, `private_class_method`, retroactive
named visibility, inline modifiers, `class << self` defaults, and another
object's singleton. Nothing to restore.

**`Core::Constitution` should keep reading `rules.yml` directly.** The proposal
was to replace its `YAML.safe_load_file` with `Master.load_rules`, on the
one-source argument. The one source is real and the fix is backwards: the class
comment two lines above states the spine reaches nothing in `lib/`, and
`load_rules` lives in `lib/boot/data.rb`. Taking the suggestion would invert the
only dependency rule `core/` has, to buy a size limit on a 205 KB file, a
timeout on a local read, and permitted classes for a file that holds no `Date`.
`load_rules` performs no shard merge, so the two paths already return the same
object. Recorded in `MASTER/DECISIONS.md`; do not reopen.

**Cognition phases 3 through 8 are premature.** A log proposed eight phases —
prediction, global workspace, thought generation, consolidation, dreams, goals,
agency, beliefs, an HDC accelerator in Rust — as a staged programme over
`lib/cognition/`. Phases 2A and the tick defect below were real and are done.
The rest builds six new subsystems on a layer whose own loop had never run, and
`COLLAPSE_BEFORE_ADDING` asks for the nine moves before any of them. Revisit
when the persisted transition model has weeks of real event history in it and
something in the tree reads it.

### Open, sized, and real

**The local tier's model list is a guess.** `OllamaSender` dispatches now, but
`models.yml` names `qwen2.5-coder:7b`, `llama3.2:3b` and `phi4:mini` as the
tier-D chain and nothing checks that any of them is pulled — a missing model
reports cleanly as `ollama has no model <name>` and then the chain falls through
to a paid provider. Either pull those three on the machines that enable the tier
or have the chain read `/api/tags` and rank what is actually there. The second
is the one that cannot go stale.

**`Finding#reversibility` and `#blast_radius` still have no reader.** Both are
first-class fields on `Finding`; only `meta_rules.rb` ever sets them and nothing
in `lib/fix/` reads either. The review that raised this called it the whole of
autofix safety and was wrong about that — `Scanner#should_autofix?` and
`AstFixer::DELETING_TRANSFORMS` decide by what a transform *does*, which is the
better question, and both autofix paths consult it now. What remains is the two
unread fields: either give them a reader or delete them, because a declared
field nobody reads is this tree's most common defect and these two have been
sitting in the constructor since they were added.

**Exemptions are measured now, and the corpus is clean.** `ruby
MASTER/tools/stale_exemptions.rb` reads 143 markers in 90 files and every one of
them holds back a finding. The one that did not — `_root.scss`, a marker on the
tail line of a multi-line comment whose subject no rule flags either way — was
deleted with its rationale kept. The tool still reports `web_rules.rb:77`, which
is prose quoting the marker rather than using it, and is disclosed as a known
false positive in its own header.

Run it after a rule narrows or retires. That is when an exemption goes stale, and
nothing else will say so.

**No gate measures engine boundaries.** One intentional cross-engine constant
reference exists — `maps -> Takeaway::Order` — and zero cross-engine
associations. A source gate should detect constant references and model
associations across `RAILS/brgen/engines/`, carry that one as a named exemption,
and fail on the second unreviewed crossing. No Packwerk, no native dependency,
for one check.

**i18n has resolution checks and no hygiene checks.** The locale tests cover
duplicates, homes, naming, parity and resolution. Unused keys and
interpolation-variable parity between locales are both unmeasured. Build it on
this repo's own search machinery: six mounted engines make a generic
`i18n-tasks` configuration likely to misread the tree.

### Operator-owned, recorded not opened

Each of these needs the box, money, or a rendered decision, so they are named
rather than done.

- **relayd restart churn.** The deploy path restarts relayd whenever an
  individual app comes back healthy, which drops the single HTTPS listener for
  every other app and has already caused an outage. Read `relayd(8)`,
  `relayd.conf(5)` and `relayctl(8)` from vm23 first; the likely shape is table
  disable/enable rather than a daemon restart, with a genuine config change still
  reloading properly.
- **Per-process resource evidence.** `resource_guard.sh` sheds on aggregate box
  load, so the log never says which process took the memory. Add per-process RSS
  for the managed services, record an exited process as unavailable rather than
  zero, and change no threshold in the same patch.
- **Service resource limits.** The Rails `login.conf` class permits a datasize
  larger than the physical box. Capture steady-state and peak RSS on vm23 first,
  and open-file usage before touching `openfiles-cur`.
- **Off-host snapshots.** Backups are same-disk and the restore path points
  somewhere unusable. The destination and retention policy are the operator's;
  what is buildable is the contract, the verification, the restore drill, and
  backup freshness in `/health`.
- **TTS daemon ownership.** Worker logs and sockets can be created as root while
  the daemon runs as `master`. Find the writer before adding a periodic chown,
  expose `tts_socket` in `bin/operator vps state --remote`, and make health
  distinguish process-up from socket-usable.
- **The multi-platform Bundler lock.** vm23 carries a hand-repaired
  `MASTER/Gemfile.lock` whose checksums differ from the committed one; the cause
  is the BSD-only dependency in `MASTER/Gemfile` and the fix is `install_if`. A
  deploy-window change, in order: repair the Gemfile, regenerate on both
  platforms, verify frozen Bundler, verify TTS, deploy, restart master, verify
  `/health` and relayd, then close.
- **The face's shader brightness floor.** Probe the live face at production
  defaults against the README-sized render and change the shader, not a
  recorder-only uniform. A rendered value: bring the number back for a decision.
- **The accent question.** Render the front page, marketplace, takeaway, dating,
  TV, Amber and MASTER with and without the vertical accent, compare interactive
  affordance, and encode the winner as a token and a gate. One decision, not
  another abstract colour discussion.
- **Deep visual gates need a browser.** The measure output has CSS budget rows
  that cannot be read without one, and an unreadable row must never count as
  green. Run the deep audit only when a browser is present, keep screenshots and
  geometry as the receipt, and report unavailable as unavailable.

## Wishes, not work

Directions rather than tasks. They belong to the operator, and nobody should open
one as a ticket without asking first.

- **The face's brightness is a look, not a bug.** It renders at 0.4% of pixels
  lit, and whether that is right is the operator's eye.
- **Retire the rolling pixel baseline.** `RAILS/gates/visual_contract.rb`
  re-baselines to zero on the next run by design, so a regression reports once
  and then becomes the reference. `layout_snapshot` commits reviewable JSON —
  71 tracked files — and is the candidate for the fleet's only visual baseline.
- **repligen has no Replicate access, so the whole tool is unreachable.** Fund it
  or retire it; leaving it is the inert-wiring defect with a price tag.
- **One box per city rather than one box for every city.** brgen's verticals are
  already engines and vm23 sits at its capacity ceiling, so a cell per city is
  the shape that scales. It is a business decision before it is an architecture.
- **MASTER should judge its own edits to the constitution**, with the diff
  attached — the governor governed. The constitution should also be short enough
  to read in one sitting and complete enough that nothing outside it governs.
- **Aegis's drift model is the one buildable piece** of the section below: a pure
  function from entry position, sea state, current and elapsed time to a
  probable-position ellipse. Everything else there waits on hardware.

---

## In-depth refinement and micro-refinement opportunities — opened 2026-09-11

Measured against MASTER, RAILS, OPENBSD and STUDIO on 2026-09-11. A finding is
a hypothesis; re-measure before working. This list does not restate the scanner
inventory (`ruby MASTER/tools/refinements.rb`), the deterministic tier already
in this file, operator-priority box work, or anything decided against in
`MASTER/DECISIONS.md` / `OPENBSD/DECISIONS.md`. Rendered values, money, a
registrar login and a vm23 console are named and left.

Each item names a path and a move. Items flagged **unverified** were opened far
enough to name and not far enough to assert. Sample five, open the five lines,
and decide whether the instrument is right before opening the sixth.

Already open above and not restated: Gemfile.lock `CHECKSUMS` / `rb-kqueue`,
TTS log ownership, `tts_socket` on `vps state`, `secrets_rotation`, `rule_deps`
136, exemption-expiry detector, per-rule autofix classification, one chrome,
marketplace 500, layout_snapshot drift, crate backup / `off_host_dr`,
`libvips_local_build`, `multi_app_ram`, history rewrite, `bsdports.org` parking,
relayctl instead of relayd restart, `growth.rails` source/test split.

Fenced throughout: folding `dilla/live/`, splitting `dilla.rb`, merging techno
renderers, changing a rendered look or sound, enabling litestream, Solidus on
SQLite, pgvector, inbound ActivityPub storage, WebRTC, three sign-in methods,
`shared/lib/operator` nesting, LAYER_CAKE / DEAD_ABSTRACTION, raising a ratchet
to absorb growth, `emotion.rb#analyze`.

Numbered 1–N across the four trees.

### MASTER — dual sources and inert config

1. **Fixed 2026-09-12.** It named `lib/master/tools/`, a directory this tree has
   never had. The adapters are the classes `lib/builder.rb`'s `DEFAULT_TOOL_MAP`
   builds, which live in `lib/io/`. The one place a reader would look to answer
   "where does the behaviour live" sent them nowhere.
2. **Repligen/Postpro declared, never constructed.** `data/tools.yml:32-33` list them; `lib/builder.rb:16-53` has no factories. CLI shells STUDIO. Add factories or drop the rows.
3. **Fixed 2026-09-12, and it was nine, not one.** Every `source: docs/<name>.md`
   in `runtime.yml` — nine of them — named `MASTER/docs`, which does not exist.
   `why_explainer.rb:116` prints that value to the operator as provenance, so each
   showed a path that has never resolved for whoever read it. Not a broken link
   either: `3797afea7` is "Codify MASTER docs into runtime catalog", so those
   documents were folded INTO this file and the pointers outlived the files by
   becoming the file they pointed at. Removed rather than repointed, with the
   provenance stated once in the header.
4. **False — checked 2026-09-12.** The Pixel Field is not deleted:
   `particle_kernel.js` is live and declared at `web/config/face_assets.yml:70`,
   which is the manifest the shell loads. `topologies.yml`'s header describes what
   the tree actually renders.
5. **Palette keys contradict one chrome.** `topologies.yml:34-42` operator/review/visitor palettes. Mark canvas-only and test that chrome does not read them, or delete.
6. **`START_HERE.md` has a broken sentence.** `:142` “…`yml` (active read-modify-write…” — the filename was eaten. Restore the stem or cut the clause.
7. **`START_HERE.md` still defends deleted YAML.** `:147-150` discusses `visual_clusters.yml` / `mobile_web_opportunities.yml`. They were deleted 2026-08-11. Move the paragraph to DECISIONS.
8. **Three files, one voice string.** `soul.yml` `voice:`; `voice.yml` `neural:`; `tts.yml` for the engine. One reader (`Voice::Policy`) should own the string; the others cite it. The 2026-09-12 move to `en-US-JennyNeural` touched fourteen files to change one value, which is the cost this entry names.
9. **`limits.yml` still titled Tier 1 Law in START_HERE.** `:170`. `limits.yml:1-18` is explicit that most of it is unread `guidance:`. Retitle START_HERE to match `test_limits_split.rb`.
10. **`project_context.yml` names `MASTER/exe/tts-worker`.** `:36` — worker is `MASTER/bin/tts-worker`.
11. **`project_context.yml` still lists `visual_clusters.yml` as a fold exception.** `:27`. Remove.
12. **Already done — checked 2026-09-12.** `MASTER/data/claude/` does not exist and
    `lib/ground/memory_index.rb` no longer names it.
13. **`data_reach.yml` 28 unnamed keys.** Including `runtime.yml#cognitive_spine`, `soul.yml#evolution_log`, `topologies.yml#palettes`, `models.yml#ollama_*`, `personas.yml#british`, `providers.yml#mistral`. For each: find a reader or delete. Do not build a repo-wide unread-key gate.
14. **`reader_singularity.yml` still allows 10 readers of `rules.yml`.** Collapse remaining readers onto `Master.load_rules` / `Master.law`.
15. **Dual constitution classes.** `lib/ground/constitution.rb` vs `lib/core/constitution.rb`. Rename Ground’s to `PrincipleStore`.
16. **Dual memory search.** `lib/ground/memory_search.rb` vs `lib/ground/memory/search.rb`. Rename the index one `DocIndexSearch`.
17. **Three mood systems.** `lib/pressure_engine.rb`, `lib/trace/context_pressure.rb`, `lib/cognition/affect.rb`. Document which bus events each consumes, or fold PressureEngine into Cognition.
18. **Dual attention.** `lib/cognition/attention.rb` vs `lib/cli/attention_context.rb` vs `data/attention_context.yml`. One table of weights.
19. **`bootstrap.yml` vs `bootstrap_docs.rb`.** Both mention `/tail` `/replay`. `/tail` is not in `CommandRegistry.build`. Confirm callers.
20. **Fixed 2026-09-12.** The `planned:` block already said nothing reads it; it now
    also says what does answer — Falcon on 53187, declared in `web/` and forwarded by
    relayd — and that nothing has ever listened on 18789.
21. **`PATH_OWNERSHIP.yml` owns missing dirs.** `docs:` and `reports:` — neither exists. Delete the keys. **Fixed 2026-09-12 by Copilot.**
22. **`PATH_OWNERSHIP.yml` omits live dirs.** No entries for `lib/cognition/`, `lib/pressure_engine.rb`, `law/`, `AEGIS.md`, `COGNITION.md`, `EXAMPLES.md`. Add them. **Fixed 2026-09-12 by Copilot:** `law/` already had an entry; the remaining live paths now declare their purpose and check.
23. **`PATH_OWNERSHIP.yml` `tools/` check is a source-grep spec.** `:179` `spec/lifecycle_tools_spec.rb` asserts `bin/doctor` contains `"check_yaml"`. Point the check at a real tool test. **Fixed 2026-09-12 by Copilot:** the doctor case now runs the CLI and asserts its emitted YAML probe result.
24. **`data/tools.yml` `name:` vs `Master::Io::`.** Header says `Master::Tools`. Runtime is `Master::Io::ReadFile`. Align the namespace. **Fixed 2026-09-12 by Copilot:** both headers now name `Master::Io`.
25. **`RuntimeCatalog.load("tts_phrases")` vs `data/tts.yml`.** Confirm `tts_phrases` exists in a catalog `sections` list (`runtime_catalog.rb:20-24` already records a miss). **Closed 2026-09-12 by Copilot:** `RuntimeCatalog.sections` reads live `data/runtime.yml` keys, which include `tts_phrases`, and `test_ground_runtime_catalog.rb` asserts the section.
26. **`DATA_ALIASES` vs filenames.** Audit `lib/boot/data.rb` aliases against files on disk. **Closed 2026-09-12 by Copilot:** the aliases live in `lib/ground/rules.rb`; `workflow` resolves to `limits.yml`, `ruby_style` and `rails_stack` resolve to `rules.yml` sections, and `standing_orders` resolves to `state.yml`.
27. **Confirmed and left, 2026-09-12.** `soul.yml:65` does list `bin/cli`. That file
    is `paths.immutable` and outranks everything: an effect must not write it, and
    neither should I. The change is the operator's, and it is one line.
28. **`soul.yml` `anti_simulation.forbidden: [will, would, could, might]`.** If the detector is lexical it is noise; if unused it is inert law.
29. **`models.yml` ollama rows unnamed.** Delete or wire `QuotaGate` / router. **Closed 2026-09-12 by Copilot:** `ModelRouter` selects the env-gated rows and `LLMDispatcher` routes their `ollama:` ids to `OllamaSender`; routing tests pass.
30. **`personas.yml#british` unnamed.** Delete or add to `Personality.persona_names`. **Closed 2026-09-12 by Copilot:** `Personality.persona_names` reads the complete persona registry through `Rules#data(:personas)`; persona and web tests pass.
31. **`providers.yml#mistral` unnamed.** Row or reader, not both silent. **Closed 2026-09-12 by Copilot:** provider configuration loads the full provider registry, including Mistral; provider and web tests pass.
32. **Three lists of council words.** `council.yml` vs `HELP_TOPICS` vs `TurnRouter::MODEL_ALIASES`. One table. **Closed 2026-09-12 by Copilot:** these are different vocabularies with different contracts — council persona aliases, advertised slash commands, and model-generated pipeline aliases. `TurnRouter` documents the deliberate separation; merging them would advertise retired commands and broaden the council panel.

### MASTER — untested lib

33. **`HashDigCompat`.** `lib/boot/hash_dig_compat.rb` prepends `Hash#dig` process-wide. Prove MRI nil-short-circuit vs coltrane’s raise; prove `install_hash_dig_compat!` is idempotent. **Closed 2026-09-12 by Copilot:** `test_master_boot.rb` covers missing intermediate keys, nested lookup, and repeated installation without duplicate ancestors.
34. **`BrainOverlay`.** `lib/cli/brain_overlay.rb`. Test `core_brief` and `load_context` against a planted markdown dir, not empty `data/claude`. **Closed 2026-09-12 by Copilot:** `test_cli.rb` plants nested markdown, verifies the contextual index and matching/missing loads, and checks the Ruby-policy core brief.
35. **`ResyncService`.** `lib/cli/resync_service.rb` — `git reset --hard origin/main`. Dry-run must not reset; live path refused without a flag. **Closed 2026-09-12 by Copilot:** `call` now requires `confirm: true` for live reset, while `test_cli.rb` verifies dry-run fetch/report behavior and refusal without confirmation.
36. **`FixPreviewReport`.** `lib/cli/fix_preview_report.rb`. No test of render shape. **Closed 2026-09-12 by Copilot:** `test_cli.rb` covers clean/skipped output, violation summaries, rule/file sections, and sixty-character file-name truncation.
37. **`DeliberationPrep`.** `lib/cli/deliberation_prep.rb` — `rescue StandardError` at `:17`. No unit test. **Closed 2026-09-12 by Copilot:** `test_cli.rb` verifies ideation exceptions publish `ideation:error` and return `nil` without escaping.
38. **`CouncilCrit`.** `lib/cli/council_crit.rb`. Add focused tests for empty diffs, missing deliberation, veto/pass events, truncation, and runner wiring. **Closed 2026-09-12 by Copilot:** `test_cli.rb` covers all listed paths, including event payloads and container runner dependencies.
39. **`AstEdit`.** `lib/io/ast_edit.rb` — dangerous tool, in `DEFAULT_TOOL_MAP`. No test of Prism edit / governor.
40. **`BatchReplace`.** `lib/io/batch_replace.rb`. Same.
41. **`SearchKnowledge`.** `lib/io/search_knowledge.rb`. No test that it reads `knowledge/` and not `docs/`.
42. **`WebChat`.** `lib/io/web_chat.rb` — Ferrum path from `llm_dispatcher.rb:367`. No test.
43. **`WebSearch`.** `lib/io/web_search.rb` — only the string in `test_tool_profile.rb`. No `Io::WebSearch` call.
44. **`AskLlm`.** `lib/io/ask_llm.rb`. Same: name only in the profile test.
45. **`GitContext`.** `lib/io/git_context.rb`. No test of status/log summary.
46. **`McpCoordinator`.** `lib/io/mcp_coordinator.rb` — booted in `boot_phases.rb:72`. No test.
47. **`DynamicHttp`.** `lib/io/dynamic_http.rb` — SSRF-adjacent. `rescue StandardError` returns `Result.err` (`:37-38`). No test.
48. **`IngressRunner`.** `lib/io/ingress_runner.rb` sets `Fiber[:master_visitor]` / `elevated`. No test that ensure clears fiber keys.
49. **`Io::Clean`.** `lib/io/clean.rb` shells `OPENBSD/dev/clean.sh`. No test that `SCRIPT` exists and timeout fires.
50. **`Io::Tree`.** `lib/io/tree.rb`. No test.
51. **`Io::SymbolLookup`.** `lib/io/symbol_lookup.rb`. No test.
52. **`Io::FeedbackRecord`.** `lib/io/feedback_record.rb`. No test.
53. **`Io::BrgenBridge`.** `lib/io/brgen_bridge.rb` hits `127.0.0.1:38182` with `MASTER_INTERNAL_TOKEN`. No test of missing-token err or non-200.
54. **`Ground::MemorySearch`.** `lib/ground/memory_search.rb`. No test of scoring.
55. **`Ground::MemoryIndex`.** `lib/ground/memory_index.rb`. No test of rebuild against missing `data/claude`.
56. **`UnfinishedLedger`.** `lib/fix/unfinished_ledger.rb`. No test of add/resolve/top.
57. **`HotwireRefactorPolicy`.** `lib/rails/hotwire_refactor_policy.rb`. No test.
58. **`PwaAudit`.** `lib/rails/pwa_audit.rb` — `initialize(root: Master::ROOT)` so a RAILS audit from MASTER root is the wrong tree unless callers pass `app_path`.
59. **`MobilePwaOperator` / `MobileWebClusterCatalog` / `Rails8AppAudit` / `SwStrategy`.** `lib/rails/` — no spec/test names. Test or PATH_OWNERSHIP them as RAILS-only.
60. **`BedrockStub`.** `lib/io/bedrock_stub.rb`. No test that `RubyLLM::Providers::Bedrock` is defined before `ruby_llm` loads.
61. **`PressureEngine`.** Only constructed in `test_master_boot.rb:39`. No test of `ingest` / weather thresholds.
62. **`CLI::Stages::Route#levenshtein`.** `lib/cli/stages/route.rb:53-66` — nested ternary inside `Array.new`. No test of “did you mean”. Split the init loop.

### MASTER — declared, never wired

63. **Command tables built by nobody.** `lib/cli/command_registry/help.rb:11-15` already states it: `memory_commands`, `system_commands`, `media_commands`, `core_commands`, `domain_commands`, `reach_commands`, `agent_commands` are required and never merged into `build`. Wire or delete.
64. **`system_commands` duplicates live verbs.** `system_commands.rb:21-30` redefines `commit`, `doctor`, `pair` that `build` already has. Delete the duplicates from the dead table first.
65. **Second `/commit` is unconfirmed `git add -u`.** `system_commands.rb:51-60`. Even unwired, it is a loaded gun. If kept, require paths.
66. **`dispatch_snapshot` lowercases STUDIO.** `system_commands.rb:69` `File.expand_path("../studio", root)` — tree is `STUDIO/`.
67. **`dispatch_reload` is a stub.** `system_commands.rb:82-84` always `"reload: not supported"`. Session `run_rebuild` actually execs. Two rebuild stories.
68. **Session handlers vs registry.** `command_handlers.rb` implements `run_rebuild`, `run_context`, `run_checkpoint`, `run_verify` outside the closed slash table. `run_verify` hardcodes a 2026-era file list. Register or delete.
69. **`/fold` exists as `core_commands` only.** `TurnRouter::FOLD_SLASH` rewrites `fold`/`run` but `build` does not register `fold`.
70. **Help comment still says `through`.** `help.rb:10`. Rename was `/review`. `completions/_master:6` still completes `through`.
71. **Completions list is the old closed set.** `completions/_master:5-15` — `through`, no `review`/`rules`/`why`/`orders`/`soul`. Generate from `HELP_TOPICS` + `ALIASES`.
72. **START_HERE slash set is short.** `:11-13` lists 9 verbs; `HELP_TOPICS` has more. Add orders/soul/why/rules.
73. **`TurnRouter` still accepts ten pipeline words.** `turn_router.rb:54-70`. Completions and START_HERE should say which four are advertised.
74. **`IntentRouter::INTENTS` is a keyword soup.** `intent_router.rb:6-28`. Add tests for “why isn’t the homepage realtime?” and a plain “review this later” that must stay chat.
75. **`bin/README.md` says `pub4` is the operator surface.** `:6` — the binary is `bin/operator`.
76. **`bin/master-core` survived the two-spine merge.** Fold into `bin/master --core` or keep and give it a test.
78. **`bin/gate` vs `bin/operator gate`.** `bin/README.md` still tells people to run `gate` as if it were the chain. One sentence: do not run `bin/gate` unless debugging the scanner.
79. **Seven diagnose bins overlap.** `check` / `ci` / `audit` / `probe` / `smoke` / `dogfood` / `doctor`. Concrete: `smoke` → `check --profile=ci` subset; `audit` → `operator lint --staged`.
80. **`bin/onboard` / `cleanup` / `handoff` / `playbook` / `reset-costs` / `sync-env`.** No tests except source greps in `lifecycle_tools_spec.rb`. Real subprocess test or fold into `doctor` / `operator`.
81. **Four TTS bins.** `tts-e2e` should be `bin/check --profile=web` or a rake task.
82. **`dispatch_tools` lives in unwired `system_commands`.** `/tools` cannot list tools. Merge that one command if nothing else.

### MASTER — stale comments and names

83. **`EventsController` “Wire into routes”.** `web/app/controllers/events_controller.rb:9-14` — route exists at `routes.rb:26`. Delete the how-to.
84. **`EventsController` talks about “the orb”.** Live surface is the face. Rename in the comment; drop `autoloop:cycle` / `sweep:cycle` unless something still publishes them.
85. **`NO_PUTS` exemption still names `pub4/gate_chain.rb`.** `lib/review/scan/rules/lexical_rules.rb:39`. File is `lib/operator/gate_chain.rb`. The regex does not match.
86. **`FixLoop` “architectures #1–#15”.** `lib/fix/fix_loop.rb:18`. Architecture numbers went with `docs/`. Say what the two tiers are.
87. **`Io::Clean` comment is a changelog.** `lib/io/clean.rb:11-15`. Present-tense: script is `OPENBSD/dev/clean.sh`.
88. **Fixed 2026-09-12.** The paragraph said the guard was paused via
    `/var/db/pub4_all_apps`. That flag does not exist on vm23 and the shed list is
    empty, so the guard has been armed the whole time the doc said otherwise — two
    months of it. It now states that, and points at the script for thresholds
    instead of naming any.
89. **`help.rb` “read-only” vs scan writes.** `:18` vs `:30-32`. Pick one sentence.
90. **`MechanicalAutofix` “`/scan` and `/self`”.** `/self` is a model alias for `/review`. Say `/review --only scan`.
91. **`lib/cli/README.md` still mentions `data/claude`.** `:33`. Empty dir.
92. **Done — verified 2026-09-12.** `mask.js` and the three `mask_*` files are off
     disk and nothing loads them. The two textual matches left are a different
     thing: `visual_bridge.js` names the `papua-mask` topology and a `#mask` DOM
     id fallback, and `visual_governor_spec.rb:30` is the comment recording the
     supersession.
93. **`visual_governor.js:1` “before mask.js loads”.** mask.js does not load. “before face.js”.
94. **`cognition_ecology.js:75` “see mask.js”.** Same.
95. **`HealthController` comment block is a decision record.** Keep one line: git is not critical because dubious ownership under `master` user.
96. **`eslint.config.mjs` `face3d_*.js`.** `:52` — no such files. Dead glob.
97. **`eslint` globals `MASTERVisual`, `Face3DPreview`.** Grep and drop unused globals.
98. **`lib/cli/session/command_handlers.rb`.** Vague; it is rebuild/context/checkpoint/verify. Rename or fold into `repl_flow.rb`.
99. **`work_commands_extra.rb` / `work_commands_status.rb`.** Suffix `extra` is a junk drawer. Split by verb.
100. **`lib/unwrap_error.rb` unnamed in PATH_OWNERSHIP.** Add a key or move under `lib/result/`.
101. **`Operator::` is a foreign namespace.** `data/autoload.yml:75-76`. Collision risk with `lib/operator`. One prefix.
102. **`lib/rails/` audits RAILS from MASTER.** Consider moving to `RAILS/gates/lib` on a sitting, or expose one `/rails audit` command.
103. **Done — verified 2026-09-12.** Neither `MASTER/lib/grok/` nor `MASTER/lib/deploy/`
     exists; lib/ is boot, builder, cli, cognition, core, fix, ground, io,
     operator, rails, review, trace, voice.
104. **Done — verified 2026-09-12.** Neither `MASTER/lib/grok/` nor `MASTER/lib/deploy/`
     exists; lib/ is boot, builder, cli, cognition, core, fix, ground, io,
     operator, rails, review, trace, voice.
105. **`pressure_engine.rb` at lib root.** Not in PATH_OWNERSHIP. Move under `lib/cognition/` or `lib/trace/` and declare.
106. **`cognition/` not in PATH_OWNERSHIP.** Add; purpose is already in `COGNITION.md`.
107. **`web/script/` undeclared.** Add under `web/`.
108. **`MASTER/log/traces.log` and `MASTER/tts.wav` at tree root.** START_HERE says local/generated is `.master/`, `output/`. Gitignore or move.
109. **`MASTER/runtime/` JSONL undeclared.** Either `.master/` or declare `runtime/` as local.
110. **`loop.gif` / `loop.mp4`.** Add to PATH_OWNERSHIP as generated media, check `none`.
111. **`PATH_OWNERSHIP` `lib/providers/` check is a missing spec.** Points at `spec/providers/catalog_index_spec.rb`; file is `spec/io/catalog_index_spec.rb`.

### MASTER — tests

112. **Source-assertion ratchet is 222.** Worst: `test_web_ui.rb` (39), `spec/lifecycle_tools_spec.rb` (17), `test_cli.rb` (12). Convert lifecycle_tools tests to actually run `--help` / a dry flag.
113. **`test_agent.rb` four skips “API moved”.** `:31-54`. Port or delete.
114. **`test_suite_actually_runs.rb` skipped unless `SUITE_AUDIT=1`.** The test that the suite runs does not run. Put a cheap version in default `rake test`.
115. **`test_self_scan.rb` skipped unless `MASTER_INTEGRATION`.** Document in START_HERE which integration tests exist.
116. **`test_cli_boot_e2e.rb` needs `MASTER_CLI_E2E=1`.** Same.
117. **`test_web_http.rb` / `test_browser.rb` excluded from `rake test`.** `--profile=web` must be the only advertised path; START_HERE lists operator profile without web.
118. **`test_injection_guard_wiring.rb` uses `.allocate`.** `:50`. Construct with a fake governor.
119. **`test_io_replicate_client_train.rb` allocate.** Same pattern `:8`.
120. **`test_tool_registry_elevation.rb` allocate.** `:12`.
121. **`spec/web/visual_governor_spec.rb` greps source for `let maxFps = 24`.** Drive the function if exported, or keep as a marked manifest test.
122. **`test_web_ui.rb` asserts `File.read(visual_bridge.js)` includes `phantom:detected`.** Assert the method/event fires.
123. **Fixed 2026-09-12.** It already called `Thresholds.worn_profile`; what was left
     was a seventh assertion that `rules.yml` *contains the string*
     "Design::Thresholds.micro_typography". The six above it call that reader and
     check what it returns, which is what having a reader means — the seventh passed
     if the method were deleted and the comment stayed, and failed on a rename that
     broke nothing. Removed, and `TestSourceAssertions::BASELINE` lowered 222 -> 221
     so the gain cannot be handed back silently; that test demanded it.
124. **`test_edge_case_stub_generator.rb` asserts generated tests contain `skip`.** Generate real stubs or delete the generator.
125. **`spec/core_smoke.rb` is not `*_spec.rb`.** `rake spec` does not run it; `rake core_smoke` does. Rename.
126. **Three homes for face tests.** `web/test/`, `test/test_web_*.rb`, `spec/web/`. Pick two.
127. **`web/test/locale_contract_test.rb` vs `RAILS/test/locale_contract_test.rb`.** Extract one helper.
128. **Fixed 2026-09-12.** Removed. `rules.yml` is tracked and `paths.immutable`, so
     the skip could never fire in this repo; if it ever could, the boot test should
     say so rather than pass.
129. **`test_style_guides.rb` skips unless `OPERATOR` checked out.** OPERATOR is not a tree. Dead skip or wrong path.
130. **`test_io_key_rotator.rb` skips unless two key vars.** Fixture ENV so empty/single-key branches run.
131. **FakeConfig `send(k) rescue nil`.** `test_agent.rb:12`. Swallows everything. Stop.

### MASTER — web face

132. **Done — verified 2026-09-12.** `mask.js` and the three `mask_*` files are off
     disk and nothing loads them. The two textual matches left are a different
     thing: `visual_bridge.js` names the `papua-mask` topology and a `#mask` DOM
     id fallback, and `visual_governor_spec.rb:30` is the comment recording the
     supersession.
133. **`codebase.js` not in `face_assets.yml`.** Topology `renderer: codebase.js` (`topologies.yml:95`) but the shell never loads it. Add to a deferred group or stop naming it.
134. **`offline_memory.js` not in the manifest.** `sw.js:78` says drain lives there; the contract test only asserts the file exists.
135. **`swarm.html` / `diag.html`.** Extra HTML, `lang="en"`, scanline overlay against FLAT_UI. Route behind auth or delete.
136. **`index.html.erb` `<title>brgen</title>`.** `:17` hardcoded. `t("face.title")` in nb/en.
137. **Already done — verified 2026-09-12.** No `hello:` key and no "Hello world"
     string anywhere under RAILS or MASTER.
138. **I18N_COVERAGE already flags `index.html.erb:17` and `:348`.** Fix with keys.
139. **`BLANK_LINE_RUN` on `index.html.erb:1`.** One blank-line fix.
140. **Face copy still English-first in JS.** `config/application.rb:70` is nb. Audit primer inline script against locale keys (`primer_title`).
141. **`data-theme="dark"` + inline `#000` FOUC guard.** `index.html.erb:67-80`. When chrome moves, these three inline colour rules are the FOUC layer — change with the stylesheet, not before. Values stay the operator’s.
142. **`chat.js` + `chat_actions.js`.** CLAUDE.md says `chat_actions.js` owns POST streaming. If `chat.js` is leftover, fold.
143. **`boot_fsm.js` + two inline primer scripts.** One test that both cannot double-dismiss.
144. **`face_vision_a.js`–`d.js` + `face_vision.bundle.js`.** Manifest loads the bundle. Stop serving sources as static.
145. **`face.modules.bundle.js` vs eager `face.js` imports.** Confirm only one runs per tap.
146. **Three particle systems.** `particle_kernel.js` + `particle_worker.js` + `face_particles.js`. Name the boot order in `face_assets.yml` comments (kernel is already called out).
147. **Three ecology layers.** `cognition_ecology.js` + `_render.js` + `face_offscreen_ecology.js`. Same.
148. **`smart_turn.js` fetches 21MB ONNX.** Default must stay off; add a test that `index.html.erb` does not `<script src>` the wasm.
149. **`sw.js` cache name `brgen-`.** `:3`. MASTER face is `ai.brgen.no`. Rename to `master-`.
150. **`sw.js` precaches `/manifest.json` not the Rails `pwa#manifest` path.** Confirm both URLs 200 or the SW precache fails silently.
151. **`DYNAMIC_PREFIXES` includes `/bridge/`.** `sw.js:11`. No `bridge` route. Dead prefix.
152. **Dashboard is a second chrome.** `views/dashboard/index.html.erb`. Under one chrome: brgen shell or fold into chat.
153. **`ChatController#dmesg` shells `dmesg`.** `:32-35`. Bound it or drop; OpenBSD dmesg is not chat telemetry (`Trace::Dmesg` exists).
154. **`skip_before_action :verify_authenticity_token, only: :command`.** Add a test that a sibling-host POST is 403.
155. **Index without container still paints.** Ensure primer copy does not claim “ready”.
156. **ActionCable `/cable` + SSE `/events/stream` + `visual_bridge.js`.** Three event pipes. Document Cable’s remaining job or remove.
157. **`web/public/offline.html` BARE_DIV_WRAPPER.** One wrapper div.
158. **`probe.rake` missing frozen_string_literal.** One magic comment.
159. **NO_CHANGELOG_COMMENT on `tts_job.rb:45`, `master_container.rb:59`, `face_asset_paths.rb:6`, `face_assets_manifest_test.rb:19`.** Present-tense or delete.
160. **Ferrum in both Gemfiles.** `MASTER/Gemfile:23` and `web/Gemfile:22`. Web could use the path gem’s test group.
161. **`web/Gemfile:29-50` “must mirror root Gemfile”.** A comment is not a lock. Test that web’s runtime gems ⊇ what `lib/` requires, or a single `gemspec`.
162. **`allow_browser versions: :modern`.** Test that an old UA gets 406, not a blank face.
163. **`PwaController` has no controller test.** `pwa_master_contract_test.rb` greps the ERB and `sw.js`. Add a request test that `GET /manifest` is 200 JSON.
164. **`chat_upload.css` / `face.css` not in `face_assets.yml` groups.** Loaded from the view. Digest hole of the same class as 2026-07-10. Add a `shell_css:` group.
165. **`mic_capture_processor.js` / `whisper_mel.js` absolute `/…` URLs.** Propshaft digest will 404 if not in the manifest. Add to singletons.

### MASTER — law, boot, docs, errors

166. **`NO_PUTS` `puts\b(?!\s*\()`.** `puts("x")` is allowed, `puts "x"` is not. Detect any `puts`/`p`/`pp` in `lib/` except the exemption paths.
167. **Exemption marker vs LONG_LINE / TRAILING_COMMENT.** Already named in the refinement inventory. Fix the two rules to ignore overage that is only the marker.
168. **`lib/io/key_rotator.rb` exists; `secrets_rotation` still `rule_ids: []`.** A detector that keys in `/etc/*.env` have no `expires` is the honest gap. Do not point at a neighbour.
169. **`principle_map` 175 `gap` of 272.** Fill `rule_ids` from a name match against `Law.define` / `RuleDSL.rule`. Do not invent detectors for conduct.
170. **`scan_coverage.yml` exempts `tools/`, `bin/`, `web/`.** One glob that includes `bin/*` without claiming SelfCheck covers it.
171. **`tools/` exemption is “arguable”.** Scan tools/ with a profile that ignores `$PROGRAM_NAME` scripts’ CLI `puts`.
172. **`web/` exemption produces findings nobody acts on.** Scan `web/public/*.js` (sources only, not bundles) in SelfCheck or stop claiming FOR_OF is enforced.
173. **`TODO_FIXME` examples in `voice.yml:85`.** If the rule scans YAML, those are findings or exemptions. Confirm `applies_to`.
174. **`FILE_SPRAWL` still flags `lib/cli/propose/` one-file dir** if `candidate_sources.rb` remains alone.
175. **Two Gemfiles, two locks, two platform `if`s.** Runtime deps should come from `master.gemspec`; web Gemfile should be Rails + falcon only.
176. **`master.gemspec` exists but Gemfile lists gems directly.** `gemspec` in both Gemfiles so versions cannot drift.
177. **Dilla gems in MASTER Gemfile.** `:44-52` `group :dilla`. STUDIO resolves its own gems. Trace `test_helper.rb` before deleting the group.
178. **Zeitwerk ignores: 45.** If slash tables stay unwired, they should not be ignores forever — they are unused files Zeitwerk cannot load.
179. **`required_manually: boot` comment vs file.** Comment still says `require_relative "boot/boot"`. Verify the require in `lib/master.rb`.
180. **`Builder.build` vs `build_fast`.** `BootReceipt` should list what `build_fast` skipped.
181. **`HashDigCompat` prepends Hash globally.** Install only after `require "coltrane"`, not on every MASTER boot, if coltrane is not loaded.
182. **START_HERE `bin/check` default profile may name a renamed task.** If `lint:data_singularity` was renamed `reader_singularity`, the doc is wrong. Read `check_runner.rb`.
183. **START_HERE runtime map omits `lib/cognition/`, `lib/operator/`, `lib/rails/`, `law/`.** Add one line each.
184. **START_HERE “Do not optimize away: constitution self-scan debt”.** Selftest is 0 as of 2026-09-10. Cut or retarget.
185. **`EXAMPLES.md` still shows “Good TODO Update”.** TODO policy is delete-on-close. Rewrite EXAMPLES to match.
186. **TREE.md is the map; START_HERE still has an ASCII runtime map.** Point START_HERE at TREE.md.
187. **DECISIONS still contains superseded two-spine text.** Add a one-line “current policy is One Spine” at the top of that section.
188. **`ResyncService#call` rescues StandardError to a string.** A failed `reset --hard` looks like a chat line. `Result.err`.
189. **`TtsController#synthesize` rescue returns `e.message` to the client.** Map to a stable `"synthesis_failed"`.
190. **`ChatController#dmesg` ignores status, no timeout.** Use `Io::Exec` with timeout.
191. **`cli/scan/request.rb:182` `rescue StandardError` without `=> e`.** Swallows without log.
192. **`runtime_mode.rb:32-36` double rescue StandardError.** Empty. Log or let it raise.
193. **`fold_risk.rb:23` rescue StandardError.** No log.
194. **`voice/dilla.rb:40` rescue StandardError.** No log.
195. **`rails/routes_views_audit.rb` five StandardError rescues.** An audit that cannot read a file should Result.err, not skip.
196. **`SsrfGuard` DNS rebinding residual.** `ssrf_guard.rb:17-25` documents it. Pin IP or refuse hosts that resolve split.

### MASTER — CLI, scan, tools, security, micro

197. **No `completions/_operator`.** Add; generate from operator verbs.
198. **Five “who reaches this” tools.** `operator readers` should be the one verb; `data_reach` / `code_reach` / `method_reach` / `method_graph` are implementation.
199. **Three linters.** Document: `operator lint` = no model, `/review --only scan` = may write, `rake constitution` = self-findings budget.
200. **`operator test` “smallest complete proof for dirty files”.** Print which test files it selected.
201. **`operator land` rebase-push.** Refuse unless worktree (`git rev-parse --git-dir` is a file).
202. **Live `/commit` still `git add -u`.** Make it path-scoped, or refuse when `git status` has files outside argv.
203. **`/orders run` executes standing orders.** Test that it cannot run `git reset --hard`.
204. **`/soul approve` amends constitution.** Test absolute sections refuse.
205. **`grep_history` / `audit_changes` on CommandRegistry.** Not in `build`. Dead methods or missing `/grep` `/audit`.
206. **`dispatch_save` exists, no `/save`.** Wire or delete.
207. **`dispatch_reasoning` / `dispatch_persona`.** Not in `build`. Dead or missing commands.
208. **`EXIT_ALIASES` includes `q`.** A `/q` typo. Require `quit`/`exit`.
209. **`Pipeline::ParallelGroup` pool `nprocessors`.** On a 1-CPU VPS this still fans out. Cap at 2 in production via `HostBudget`.
210. **`MASTER_SCAN_AUTOFIX` defaults to `"1"`.** Confirm `bin/cli /review` default is dry unless `--apply`.
211. **Dual events `scan_autofix:applied` and `self_autofix:applied`.** One topic.
212. **`FixLoop` STARTUP_DELAY 90s.** `build` must not start it unless asked. Test `MASTER_BACKGROUND=0`.
213. **Four loops.** `RuleLoop` / `FixLoop` / `WatchLoop` / `Watcher`. Document which process may run which.
214. **`CrossFileAnalysis` prescan is advisory.** Change the string to “advisory, not a gate”.
215. **`EdgeCaseStubGenerator` generates skips.** Delete or make it a no-op.
216. **`DatalogEngine` / `AutonomousRepairer`.** Confirm callers. If none, they are the next unified_diff_editor.
217. **`rake constitution` budget 1500.** A number that large is not a ratchet. Lower only with a deletion of findings.
218. **`spec/dogfood_spec.rb` vs `bin/dogfood` vs `rake dogfood`.** Three dogfoods. One.
219. **`spec/lifecycle_tools_spec.rb` greps `bin/`.** Move to `test/test_bin_scripts.rb` and run processes.
220. **`spec/smoke/pipeline_e2e_spec.rb` vs `test/test_pipeline.rb`.** Merge fixtures.
221. **Flat `test/test_*.rb` outliers.** `test_aggressive_merge.rb` is not findable. Rename to `test_trace_*`.
222. **`tools/todo.rb` is a second backlog if nobody runs it.** Wire `rake lint:todo` or delete.
223. **`tools/example_scan.rb`.** No test, no rake. Delete or `rake lint:example_scan`.
224. **`tools/history_valuables.rb`.** Test the regex does not match `TODO.md`.
225. **`tools/method_graph.rb` / `method_reach.rb`.** Add `test/test_method_graph.rb` with the hook-false-positive fixtures the comments name.
226. **`tools/namespace_ratchet.rb`.** Duplicate of `data/namespace_ceilings.yml`? One.
227. **`tools/word_boundary_lint.rb`.** Add to `rake audit`.
228. **`tools/swallowed_errors.rb`.** Should flag `scan/request.rb:182`. Add to audit.
229. **`tools/dup_census.rb` / `design_baseline.rb`.** No unit test of the counter.
230. **`tools/snapshot.rb` vs `Trace::Snapshot::Publisher`.** One snapshot verb.
231. **`tools/test_naming.rb`.** Run in `rake lint:test_naming`.
232. **`script/generate_canon.rb`.** Ensure `rake docs:` is the only writer of `data/CANON.md`.
233. **`MASTERFace` leftovers in `public/`.** Grep non-bundle sources and delete.
234. **Three globals.** `window.MASTER` vs `master_namespace.js` vs `MASTER_RUNTIME`. `master_namespace.js` should be the only assigner.
235. **Three stores.** `felt_state.js` vs `face_state.js` vs `ui_presence.js`. Add a runtime test that `MASTERFeltState` exists before `visual_bridge` emits.
236. **`attention_model.js` vs ONNX `smart-turn`.** Two “attention” in the face. Rename JS to `face_attention_field.js`.
237. **TTS `Cache-Control: public, max-age=3600`.** `tts_controller.rb:44`. Body is per-user speech. `private`.
238. **`/chat/tts/phrases` unauthenticated.** If phrases are idle nudges, visitors get them. Intentional? If not, authenticate.
239. **CSP report-only unless `PUB4_CSP_ENFORCE=1`.** Production should enforce. Check `web/config/environments/production.rb`. **Unverified.**
240. **CSP `style_src :unsafe_inline`.** Needed for FOUC. Nonce style?
241. **YouTube in script_src / frame_src.** If unused, drop.
242. **`face.part*.txt` in public/.** Concatenated at build; still served. Move to a build dir.
243. **Ingress test skips if token empty.** Fixture a token so CI tests ingress auth.
244. **`planned.tools.deny_patterns` unwired.** Leave; do not restore `risk_classifier.rb` without a caller.
245. **WebFetch must not hit `127.0.0.1:38182`.** `BrgenBridge` is a dedicated client. Test SSRFGuard blocks the tool path.
246. **`DynamicHttp` + SSRFGuard.** Confirm `resolve_and_validate_uri` calls `SsrfGuard`. If not, that is the hole.
247. **`Fiber[:master_visitor]` process-wide in CLI.** Test a CLI Session does not leak into a later web request in the same Falcon process.
248. **`/up` vs `/health`.** relayd should use `/up` for liveness and `/health` for deploy smoke. Document in `web/CLAUDE.md`.
249. **`pages#radio_bergen`.** Extra surface. Auth? Content? If it is the Dilla tunnel, it belongs in playlist.
250. **`web_boot_payload` vs `_minimal`.** Test `/runtime/config` is not a `<link preload>`.
251. **Cognition `observe` on `**`.** Test a scan of 1000 events does not write 1000 YAML dumps.
252. **`/review --only scan` must not start the council.** Test `MASTER_SCAN_DETERMINISTIC`.
253. **JS `lang="en"` on swarm/diag/offline.** `lang="nb"` or generate from locale.
254. **`skip_to_content` vs `skip_to_prompt` vs `face.skip_prompt`.** Three skip links. One on the face page.
255. **Dashboard `rsi` / `rtk` untranslated.** If they stay jargon, a comment is enough.
256. **Chat rate limits vs `security.yml`.** `CHAT_RATE_LIMIT = 30` in Ruby; ingress 30 in YAML. Chat should read a limits key (`test_security_defaults` pattern). Same for TTS 30 / poll 300.
257. **Visitor must not `Shell`.** `VISITOR_ALLOWED_TOOLS` from `Tool::Profile.public_names`. Add a web controller test.
258. **`ImagePresenter` `tmp/chat_uploads`.** Ensure PathGuard / not world-readable; purge job.
259. **Two token classes.** `MasterIngressToken` / `MasterWebToken`. Name by job (ingress HMAC vs session cookie).
260. **Three logs.** `WebEventLogger` vs `Trace::Log` vs `Swallow` JSONL. One directory.
261. **Two dmesgs.** `lib/trace/dmesg.rb` vs `ChatController#dmesg`. Controller should call Trace::Dmesg or go away.
262. **`lib/ground/openbsd_config.rb` vs `data/openbsd.yml` vs `OPENBSD/`.** One reader `OpenbsdConfig`. Must not drift from the tree.
263. **`lib/ground/host_budget.rb` vs `OPENBSD/vm_resource.yml`.** Test the path; do not duplicate limits.
264. **`lib/cli/web_server.rb` vs Rails `web/`.** If unused, delete. **Unverified** callers.
265. **`lib/cli/skills.rb` vs `data/patterns.yml` skills_registry.** One skills list.
266. **`lib/ground/standing_orders.rb` vs `orders.rb`.** Two names. Fold if one is a facade.
267. **Four stores.** `lib/ground/memory.rb` vs `memory/store.rb` vs `sqlite_store.rb` vs `knowledge_store.rb`. Comment which is session vs knowledge vs sqlite.
268. **Three semantic layers.** `semantic_cache.rb` vs `semantic_index.rb` vs `Review::Embeddings`. One paragraph in `lib/io/`.
269. **Three quota objects.** Cross-link comments to `test_quota_gate.rb`.
270. **`lib/io/ruby_llm_patch.rb`.** Test that `Model::Info.new` kwargs are a subset of the gem.
271. **`lib/trace/metrics.rb` `summary` should not print zeros as if measured.**
272. **`lib/voice/speech.rb` 471 body lines.** Split I/O (worker client) from policy. Do not change sound.
273. **`lib/voice/personality_prompt_builder.rb` 386.** Split CORE_SECTIONS assembly from file IO.
274. **`diag.html` yellow-on-black debug page is public.** Gate behind authenticated `/diag` or delete from production `public/`.
275. **Static 400/404/406/422/500 English Rails defaults.** I18n or nb.
276. **`AuthTier TOKEN_BYTES = 48` vs `MIN_TOKEN_LENGTH = 43`.** Align numbers in one comment.
277. **`bin/cli` vs `bin/master`.** Two entrypoints to the same REPL. One file should exec the other.
278. **`completions/_master` `compdef master` only.** Also `bin/cli`.
279. **`HELP_TOPICS` `review` detail still says “aesthetic scan, deep scan, fix, re-scan”.** Align with `--only scan|critique|map`.
280. **`test_source_assertions` PATTERN misses `refute_includes File.read`.** Extend or `refute` will grow as a dodge.
281. **`lib/boot/data.rb` `unsafe_load` for aliases.** Test that a crafted alias cannot load a Ruby object. If unsafe is required, `permitted_classes` empty and aliases only.
282. **Four YAML loaders.** `Master.law` / `Rules#data` / `RuntimeCatalog.load` / `YAML.load_file`. Grep `YAML.load_file` in `lib/` for stragglers.
283. **Three ways to define a rule.** START_HERE should say: YAML `rules.yml` + `law/*.rb` + RuleDSL. No fourth.
284. **`data/autofix_reach.yml` dangling 0.** Do not add transform names without code.
285. **Ratchet yml without a rake task is inert.** `cohesion_census.yml` / `dup_census.yml` / `sprawl_census.yml` / `namespace_ceilings.yml` / `design_baseline.yml` / `doc_baselines.yml` / `violation_age.yml` — each needs `rake lint:*`.
286. **`data/agent_map.yml` vs `agent_taxonomy.yml`.** `/btw` uses taxonomy. Map is unused or for snapshots. One.
287. **`data/load.yml` dual with `boot_phases.rb`.** One.
288. **`data/proposals.yml`.** If unread, it is `data_reach` unnamed. Reader or delete.
289. **`data/radio_bergen_track_dossiers.yml` unnamed keys.** STUDIO/dilla data in MASTER/data. Move to STUDIO or give dilla the reader.
290. **`data/pub_archive_restore.yml` / `recovery_pub.yml`.** Keep; mark `data_reach` reasons so they stop looking like defects.
291. **`data/recovery/plugin_schema_v1.json`.** JSON in YAML-land. One schema language.
292. **`data/maturity.yml` vs scorecard.** Two maturity sources? One.
293. **`lib/ground/pledge.rb` vs OpenBSD pledge.** Name `OpenbsdPledge` if it is that; if not, do not confuse `OPENBSD/`.
294. **`lib/fix/constants.rb`.** Dumping ground? Split or name the constants’ subject.
295. **`SCAN_GLOB` vs extensionless `bin/`.** Implement include list for `bin/check`, `bin/gate`, `bin/cli`.
296. **`lib/cli/scan/request.rb` TARGET_ALIASES `face`.** Test it points at `web/public` not generated bundles.
297. **`bin/ruby` wrapper.** Test it execs 3.4.9 or prints.
298. **`InjectionGuard` vs WebFetch.** Test Boot still builds `guard:` and WebFetch uses the same object, not a new one.
299. **`BootReceipt` vs `maturity_scorecard.rb`.** Test the receipt includes rule count from the file the process loaded.
300. **`lib/io/antigravity.rb` 231 lines after fold.** Under 300. Fine; skills test exists.

### RAILS — brgen core

301. **Stale layout comment.** `RAILS/brgen/app/views/layouts/application.html.erb:1-26` still says `data-theme="dark"` is load-bearing. Rewrite to the present-tense reason, or delete it. (Amber’s layout comment is already present-tense light.)
302. **404 chrome vs live chrome.** `RAILS/brgen/public/404.html:8-11` forces `color-scheme: dark` and inline `--x-bg: #0f0f12` while the app default is light. Align static errors with `shared/public/styles/errors.css`. Look: name the seam, do not invent tokens.
303. **404 hardcodes Bergen marketplace.** `RAILS/brgen/public/404.html:34` links `https://markedsplass.brgen.no/` so Oslo/LA 404s send people to Bergen. Build the href from `Brgen::DomainRegistry`.
304. **404 English paragraph.** `RAILS/brgen/public/404.html:29`. i18n both, or drop the EN line.
305. **Same for 500/422.** One generator or shared static template.
306. **Mailer English subject.** `email_subscription_mailer.rb:10` `subject: "Confirm your Brgen subscription"`. Move to `t("mailers.email_subscription.confirm")`.
307. **Mailer from-host.** `:4` `from: "Brgen <letters@brgen.no>"` ignores city hosts. Parameterize with the requested host.
308. **No mailer tests.** No `email_subscription_mailer_test.rb`. Assert subject key, `confirm_url` token, and both html/text parts.
309. **Newsletter/queue/verification mailers untested.** One request test per `deliver_*`.
310. **`Tv::BaseController` is a stub.** `:3` “keep empty until shared vertical policy/layout lands.” Hoist vertical policy here or delete the promise.
311. **Stream chat skips the TV base.** `Tv::StreamChatsController` inherits `ApplicationController`. Inherit the base; use `Current.user` not `current_user`.
312. **Comments on TV show N+1.** `tv/videos/show.html.erb:123-128` walks `@video.comments` then `comment.user` with no `includes(:user)`.
313. **`increment!` on listing/video views.** `Marketplace::ListingsController#show:56` and `Tv::VideosController#show:24`. Counter table or `update_counters`; do not fragment-cache that field.
314. **Double view increment on TV.** `VideosController#show` increments, and `ViewEventsController#create` increments again. One writer.
315. **`Tv::VideosController#show` creates a ViewEvent per GET.** Refresh = a row. Dedup per (user, video, hour) or only create from the player beacon.
316. **Posts live search vs FTS.** `posts_controller.rb:35` `apply_live_search` on `title/content` while `posts_fts` exists. Use FTS when the table exists.
317. **Conditional GET absent.** Add `fresh_when` on `posts#show`, `events#show`, `listings#show`. Only `bsdports` `ports#show` has it.
318. **No `data-turbo-prefetch` on nav.** Turn on for the eight swiper destinations; keep `pagy.rb:17` prefetch-off on pager links.
319. **Pagy disables prefetch globally.** Scope to pager anchors, not every Pagy link extra.
320. **`data-turbo-permanent` missing on nav.** Mark the swiper + theme toggle permanent.
321. **Feed sort is a full document.** Hot/New/Following should be a turbo frame.
322. **`turbo: false` on channel join.** `channels/show.html.erb:78`. If join must full-reload, comment why; else drop it.
323. **`turbo: false` on cart PSP forms.** Document, or use `data-turbo="false"` only on those two buttons via a helper.
324. **Notifications still local.** `brgen/.../notifications_controller.rb` vs `shared/.../notifications_controller.rb`. Promote when city grouping unifies — or delete the shared stub.
325. **Votes still local.** Same for `votes_controller.rb`. The shared reflex `vote_reflex.rb` already exists.
326. **Follow schema split.** brgen `follower/followed` vs amber `follower/followee`. Until unifying, stop implying shared following in docs.
327. **WebVitals logs only.** Persist p95 or drop the POST if logs are the product.
328. **Server-Timing absent.** No middleware in `shared/config`. Cheap header for view/db/cache split.
329. **Fragment cache hit/miss not timed.** Three cached partials. Emit `Server-Timing: miss|hit`.
330. **Checkouts `allow_other_host: true`.** `Marketplace::CheckoutsController#create:56`. Allow-list host (`vipps.no`, `checkout.stripe.com`) rather than any URL `start_payment` returns.
331. **Checkouts rescue `StandardError`.** Narrow to payment errors; let programming errors 500.
332. **Flash interpolates exception.** `t("flash.marketplace.checkout_failed", message: e.message)` can leak Stripe internals. Map known errors.
333. **`NotConfigured` flashes English class message.** i18n the provider name.
334. **`hello: Hei` in nb.yml.** `brgen/config/locales/nb.yml:34`. Grep callers; delete if unused.
335. **`nav.vertical_badge_new: "nytt!"`.** Confirm a reader; if the badge never renders, delete the key.
336. **2FA inside engine.** Audit every engine `require_two_factor!` for `main_app` paths (kinds test already pinned a `UrlGenerationError`).
337. **Anonymous TV comments unthrottled.** No `rate_limit` on `Tv::CommentsController`. Add named limit like posts.
338. **Guest minting + prune.** Confirm `guest` + `created_at` index exists in all three schemas. If missing, `PruneGuestUsersJob` is a table scan.
339. **`UserPurgeJob` vs guest prune overlap.** Two daily jobs at 3:45 and 3:50. Document which rows each owns.

### RAILS — marketplace

340. **Favorite button English aria.** `listings/_favorite_button.html.erb:12,20` `"Remove from saved"` / `"Save listing"`. Keys under `marketplace.wishlist.*`.
341. **Saved-search hidden name.** `_live_search_results.html.erb:7` `value: "Marketplace search"`.
342. **“All” chip.** same file `:15` `link_to "All"`.
343. **Category label English.** `listings/new.html.erb:65` `f.label :category_id, "Category"`.
344. **Saved searches “Browse” / “Any query” / “alerts on”.** `saved_searches/index.html.erb`.
345. **Store “Partner program”.** `stores/show.html.erb:16`.
346. **`t(..., default: "Store created")`.** `stores_controller.rb:36,47`. Add nb keys and drop defaults.
347. **Deals search is LIKE, not LiveSearchable.** `deals_controller.rb:11-16`. One helper with listings/stores; FTS if a deals index exists.
348. **Deals `#show` no `includes`.** `Deal.live.includes(listing: [:user, { photos_attachments: :blob }]).find`.
349. **Stores `#show` other stores unscoped.** `:23` `limit(6)` with no city. Scope `Current.city_record`.
350. **Stores `#show` listings not `includes`.** `with_attached_photos.includes(:user, :category)`.
351. **Payouts on show, no pagination.** Frame + pagy.
352. **Questions `#create` no rate_limit.** 10/min named `ask`.
353. **Questions flash first error English.** Add `activerecord.attributes.marketplace/question`.
354. **Reviews / returns / payouts / addresses / variants / favorites / saved_searches creates** — none contain `rate_limit` (only listings does in the engine). Add per-resource burst limits; names required when two limits share a controller.
355. **Webhooks still unlimited.** `webhooks_controller.rb:15` comments the hole. `rate_limit` by IP even after signature verify.
356. **Two Stripe webhook controllers.** Engine `Marketplace::WebhooksController` and `Webhooks::StripeController` both pay orders. One entry.
357. **`views_count` nullable.** `schema.rb:738`. `increment!` on nil raises. Default 0, NOT NULL.
358. **`status` on listings nullable.** `live` scope depends on it. NOT NULL + default `"active"`.
359. **Add `(kind, category_id)` index** if facet queries filter both (they do: `listings_controller.rb:23-27`).
360. **Duplicate indexes on gig/housing/job details.** Unique AND non-unique on `listing_id`. Drop the non-unique.
361. **Checkout `#show` redirects to cart twice.** `checkouts_controller.rb:70` `checkout ? cart_path : cart_path`. Dead ternary.
362. **Facets after kind filter.** Verify job/housing facets aren’t goods leftovers. Test already in `marketplace_saved_and_facets_test.rb`.
363. **Top offers English default.** `_top_offers.html.erb:8` `default: "Picked for the city"`.
364. **Listing show “Make an offer” default EN.** `listings/show.html.erb:99`.
365. **Order status `humanize` fallback.** `orders/show.html.erb:13`. Exhaust `marketplace.order_statuses` in nb.
366. **Condition `humanize`.** `_facets.html.erb:13`.
367. **Anon fallback.** `listings/show.html.erb:39,85,141` `"anon"` instead of `t("chat.anon")`. Same in `_questions.html.erb:13`.
368. **No engine test for stores/deals/addresses/payouts.** Add request tests for owner-only payout release and guest deal index.
369. **Cart qty updates.** Turbo frame around cart lines after PSP return.
370. **`SavedSearchAlertJob` no uniqueness.** `limits_concurrency to: 1, key: "saved-search-alerts"`.
371. **`ListingExpiryJob` same.** Concurrency 1; row lock so two workers cannot both pass the read before `renewal_notice_sent_at`.
372. **Variant out-of-stock hidden in Ruby.** `listings#show` `select(&:in_stock?)`. `scope :in_stock` on the relation instead of loading all.
373. **`finish_live_search` duplicated** across listings/stores/deals/takeaway restaurants/maps places. Deals bypasses it for the query half only.
374. **Solidus still Postgres-first.** `solidus_staging_contract_test.rb` must keep failing closed when `SOLIDUS_MARKETPLACE=1` on sqlite.
375. **Two “deals” nouns.** `AffiliateProduct` vs `Marketplace::Deal`. Verify `deals#index` does not render affiliate placeholders as listings.

### RAILS — dating, takeaway, tv, playlist, maps

376. **“Make profile visible”.** `profiles/new.html.erb:52` and `edit.html.erb:65`. Add `dating.visible_label`.
377. **Show page English paragraph.** `profiles/show.html.erb:61-74` visibility copy. All keys.
378. **Edit photo alt.** `profiles/edit.html.erb:21` `alt: "Profile photo"`.
379. **Swipe card `"anon"`.** `home/_card.html.erb:1`.
380. **Already decided, and the record is in the file that owns it.** The engine's
     locale header states the rule: Rails::Engine appends config/locales/*.yml to
     I18n.load_path on its own and I18n deep-merges across load paths, so keys the
     host already carries stay reachable and are deliberately not copied. The 78
     dating keys in brgen's own locales are those. The stub exists so the next
     engine string has somewhere to go that is not a literal in the markup — which
     is the defect the header was written against. Deleting it would restore that.
381. **LOOKING_FOR / GENDERS raw.** `profiles/new.html.erb:38,44`. `t("dating.looking_for_options.#{v}")`.
382. **LikesController no rate_limit.** Burst 60/min like votes. Same for dislikes/rewinds/prompts/verifications.
383. **`User.find` on like.** `likes_controller.rb:9` not scoped to visible profiles. `Dating::Profile.visible.find_by!(user_id:)`.
384. **`save!` no validation flash.** Failed like is 500. `save` + redirect alert.
385. **Match overlay EN defaults.** `_match.html.erb:10`.
386. **Vipps gate fail-open.** `base_controller.rb:13-21` if `VIPPS_CLIENT_ID` absent, dating is ungated. Document in `dating/README.md` that production must have Vipps.
387. **`candidate_scope` plucks all like/dislike ids.** Unbounded. `NOT EXISTS` or a cap.
388. **Daily picks / verification tests exist in host, not engine.** `cd engines/dating && rake test` is not a lie if they move or duplicate.
389. **Intro JS.** `dating_intro_controller.js` — no test. If intro goes with immersive chrome, delete with the chrome.
390. **Photos purge on edit untested in engine.** Confirm `profiles#update` permits `photos` + signed blob ids only (`media_guard`).
391. **Age required in optional `<details>`.** `new.html.erb:45` `required: true` inside “optional”. Move age to essentials or drop required.
392. **Takeaway engine `nb.yml` is empty.** `takeaway: {}`. Move the takeaway namespace into the engine.
393. **Takeaway reviews / orders `#create` no rate_limit.** Orders: burst 5/10min per user (guest-capable).
394. **`#update` kitchen status from params.** `orders_controller.rb:55` `params[:status]`. Allow-list `Takeaway::Order::TRANSITIONS`.
395. **Menu items / favorite restaurants `#create` no test / no rate_limit.**
396. **Group orders token in URL.** Rate-limit `create` so a host can’t mint unbounded open tickets.
397. **Delivery drivers index `"anon"`.** `delivery_drivers/index.html.erb:13`.
398. **`status` on `takeaway_orders` nullable.** NOT NULL + default `"pending"`. Same for `quantity`/`unit_price_cents` on items.
399. **Courier layer cross-engine.** `maps/home_controller.rb:75` `Takeaway::Order` — add the gate row with that line exempted (awesome-list item already named the shape).
400. **Hours “no rows = open”.** Empty-state on restaurant show should say so if hours missing, not “closed”.
401. **Guest order push.** Test that a guest order doesn’t 500 on push (no VAPID). `WebPushJob` discard path.
402. **Nav bar partial duplication.** `takeaway/_nav_bar.html.erb` vs `marketplace/_nav_bar.html.erb`. Shared `vertical_nav` with accent var already on body.
403. **No takeaway controller tests in engine** except `order_test`. Missing: reviews, favorites, drivers, menu_items.
404. **TV “New channel”.** `channels/index.html.erb:6`.
405. **Empty search English.** `channels/_live_search_results.html.erb:10`.
406. **“Add a note” / “Timestamp (seconds)” / “Add a comment”.** `videos/show.html.erb:106,113,144`.
407. **`"anon"` on comments.** `videos/show.html.erb:126`.
408. **Live streams aria English.** `live_streams/index.html.erb:3,9` despite `t(..., default: "Live streams")`.
409. **`tv.channel_subtitle` default “Brgen TV channel”.** City-name it.
410. **Viewers interpolation default.** `live_streams/show.html.erb:23` `default: "%{count} viewers"` — EN plural on :nb.
411. **Notes/comments/stream_chats creates no rate_limit.**
412. **`StreamChatsController` `save!`.** 500 on validation. `save` + 422 turbo.
413. **`current_user` vs `Current.user`.** `stream_chats_controller.rb:9`. Always `Current.user`.
414. **Missing: `ShowsController`, `EpisodesController` request tests.**
415. **`live_streams/new` still exists.** If MediaMTX is absent, the form should say so (`apps.yml` blocker), not look like RTMP works.
416. **`tv_content.rake`.** If it seeds English titles, mark demo-only (`content_honesty`).
417. **Player Stimulus untested.** At least a request test that feed markup has `preload=none` and `100dvh`.
418. **Watch time sendBeacon.** Test the controller rejects decreasing `watch_time_seconds`.
419. **Channel tenant.** Verify comments/notes can’t POST across channels by id.
420. **Playlist “New set” / “All sets”.** `sets/index.html.erb:9`, `sets/new.html.erb:8`.
421. **`content_for :title, "Edit #{@set.name}"`.** `sets/edit.html.erb:1`. Same for hosted tracks.
422. **Dilla sketches `"anon"` / `"by "`.** `_dilla_sketches.html.erb:24`.
423. **Role select `editor/viewer`.** `_collaborators.html.erb:29` raw English values as labels.
424. **Transport `t(..., default:)`.** Add nb keys in engine; drop defaults.
425. **Imports `#create` no rate_limit.** Confirm `OutboundHttp` like link previews. Rate-limit 5/10min.
426. **Party messages / listens `#create` no rate_limit.** Listens need a high ceiling, not none.
427. **`increment! :tracks_count` / `plays_count`.** Schema NOT NULL default 0 (playlist test already hit nullable counters).
428. **Listening party test exists; collaborations/imports/hosted_tracks do not.**
429. **Embed player layout.** Verify `playlists#embed` uses a minimal layout (skip tab bar).
430. **YouTube iframe aria default.** Engine nb has `youtube_player_aria`. View must use it without `default:`.
431. **Maps engine has no `test/` directory.** Add `PlacesControllerTest` for check-in guest identity.
432. **`#index` JSON vs HTML duplicates live_search.** `places_controller.rb:17` and `:25`. One scope builder.
433. **`#check_in` no rate_limit.** GPS spam. 10/min. Length-validate the free-text param.
434. **Home map default Bergen.** `home_controller.rb:13-14` `60.3913, 5.3221` when `Current.city_record` lacks coords. If nil, don’t pretend Bergen on `lsangeles.com`.
435. **Places layer hardcoded path.** `home_controller.rb:32` `url: "/places/#{place.to_param}"`. Engine mount prefix will break. `place_path(place)`.
436. **500 places, 200 events, 200 stories** loaded for one map. Viewport bbox filter.
437. **`I18n.l(..., format: :event)`.** Depends on host `time.formats.event`. Keep host key or define in engine.
438. **OpenFreeMap style URL.** CSP must allow `tiles.openfreemap.org`; `preconnect` or self-host tiles.
439. **Engine nb only address/city/coordinates/kind/neighborhood.** Views use `maps.map`, `maps.aria_map`, `maps.hud_aria`, `maps.needs_js` — move into engine.
440. **Filter `k.humanize`.** `places/index.html.erb:18`. `t("maps.kinds.#{k}")`.

### RAILS — messenger, stories, events, amber, bsdports

441. **Conversation search `"anon"`.** `conversations/search.html.erb:25`.
442. **Voice recorder Stimulus untested.** Keep the request test; add a markup contract (`capture`/accept audio).
443. **Link previews no image.** Deliberate. UI must not show an empty `<img>`.
444. **`MessageExpirationJob` + sweep.** If both run, `expire!` must be idempotent.
445. **`messages.expires_at` unindexed.** `ExpiredMessagesSweepJob:7` `where(expires_at: ..Time.current)`. Add index (partial where not null if SQLite supports).
446. **`typing_indicators.expires_at` unindexed.** Sweep `where(expires_at: ..1.hour.ago)`. Index.
447. **Events RSVP no rate_limit** on `event_rsvps_controller.rb`.
448. **Events map horizon 7 days.** Document in the events index empty state when everything is next month.
449. **Community wiki empty keys.** Confirm views use `wiki.empty_*` in nb.
450. **Moderation queue regression.** Add a test if `moderation_audit_test` doesn’t load `reportable` after write (strict-load bug was fixed).
451. **Blocks/bookmarks/invites controllers** — no rate_limit. Bookmarks create is easy to script.
452. **Amber coverage floor 2 controllers.** `coverage_ratchet_test.rb`. Raise the floor as tests land; don’t lower.
453. **`AiController` English notices.** `"Heuristic joy analysis applied"` / `"AI joy analysis applied"`.
454. **`AiController` shells `bundle exec ruby bin/cli photograph`.** Timeout, no rate_limit, cwd `../../MASTER` — fails on copy-tree deploy. Guard with `Operator::DeployPaths`.
455. **`WardrobeMediaJob` uniqueness is a LIKE on Solid Queue args.** Racey. Use `limits_concurrency` per `item_id`.
456. **`pending_for?` rescue StandardError.** Returns false → double enqueue. Narrow rescue.
457. **Zombie `RemoveBackgroundJob` / `SegmentGarmentImageJob`.** Comments say amber queue never drained. Operator: count rows on vm23; then delete classes. Don’t enqueue.
458. **Amber jobs: no worker.** `ApplicationJob` comment: amber `perform_later` is “never” unless `run_inline!`. Either enable `rc.d/amber_jobs` (operator/RAM) or `perform_now` for media like password mail.
459. **`recurring.yml` prune + declutter assume a worker.** If none, guests accumulate. Same as 458.
460. **Creator profile form English.** `_form.html.erb:4,40,44`. Use `shared/errors`.
461. **`creator_profiles/edit.html.erb`.** `default: "Edit creator profile"`, `"Add item"`.
462. **Widgets English.** `_widgets.html.erb:27-28,35` `pluralize(..., "piece")`, `"Browse demo →"`, `"Talk to MASTER"`.
463. **Item show aria `Color #{color}`.** `items/show.html.erb:25`.
464. **Outfit aria `Items in #{name}`.** `_outfit.html.erb:11`.
465. **Home `turbo: false` Ask AI.** If `master_embed` frame works, drop.
466. **Wardrobe keys still have EN default.** Drop `default:` now that nb exists.
467. **`hello: Hei` in amber nb.** Grep; delete if unused.
468. **Connections/messages/live_streams/planned_outfits** — no dedicated request tests. Add blocked connection and message create rate.
469. **Affiliate links destroy own vs other.** Missing test.
470. **`GarmentSilhouette#png` nil must not 500 the item show.** Verify the view.
471. **UI must not say “similar items”.** Fingerprint is not embeddings. Grep `similar` in amber views.
472. **Raw `photo_polish_done` in ERB** should go through `analysis_status_label` helper.
473. **Luxury chrome vs one-chrome.** Name `_variables.scss` / Caprasimo as the seam; don’t restyle.
474. **`like!` increment likes_count.** Micro: turbo stream replace count.
475. **Declutter 30d job uniqueness missing.**
476. **Amber public 404/500 same dark+EN as brgen.** Same generator as 302.
477. **`local: true` on search form.** `_widgets.html.erb:1` disables Turbo. Remove so live search can work.
478. **ports_fts — already inventoried, and the choice is the operator's.**
     `RAILS/test/raw_schema_objects_test.rb` holds the whole finding: `schema_format
     = :ruby` cannot express an FTS5 virtual table, production runs `db:migrate` and
     has it, everything built by `db:schema:load` — CI and every developer machine —
     does not. brgen's `posts_fts` is in the same list. The test holds that inventory
     at its current size and states why it goes no further: moving an app to
     structure.sql changes what deploy loads. The feature is done on the box; the
     test skip is the schema format, not the feature.
479. **Importer swallows FTS rebuild.** `Ports::Importer#rebuild_fts` `rescue StandardError`. `Ground::Swallow.log` and fail the import run row.
480. **`semantic_search` is lexical.** Rename or UI-label “search” so the explore assistant doesn’t promise vectors.
481. **MakefileParser `+=` vs `?=`.** Add a fixture Makefile with both. `makefile_parser_test.rb` exists — add those branches if missing.
482. **`expand_vars` infinite recursion.** **Unverified** beyond line 80. If `${VAR}` can self-ref, cap depth.
483. **`permit_file_distfiles`.** Importer must not skip license. Test one restricted port.
484. **`PortsImportJob` no uniqueness.** Nightly + manual = two imports. `limits_concurrency to: 1, key: "ports-import"`.
485. **`SecurityAdvisoryRefreshJob` no uniqueness.** Timeout + cache so it doesn’t hammer NVD.
486. **`turbo: false` on JSON summary.** `ports/show.html.erb:53`. If it’s `render json`, keep false; else a frame.
487. **Comments/reactions on bsdports.** If `comments_controller` is mounted without social tables, it’s a dead surface — unmount or add tables. **Unverified** routing.
488. **PWA manifest English.** `bsdports/app/views/pwa/manifest.json.erb:37`. nb/en by locale.
489. **No system test for search empty.**
490. **Maintainers unique name.** Confirm model now validates unique index.
491. **WCAG AAA — checked 2026-09-12, no claim to withdraw.** No README claims
     AAA. The only statement of it is `apps.yml`, which already carries the
     caveat the item asks for on the same line: "not a full-site AAA audit".
     Item 231 still stands and is the forward half.
492. **Explore assistant.** Rate-limit; no LLM key should fail to a rules summary (amber pattern).
493. **bsdports nightly import vs `rc.d/bsdports_jobs`.** If no worker, the schedule is fiction.

### RAILS — shared, gates, i18n, a11y, jobs, schema, JS

494. **Locale shadowing.** Shared locales load twice and win. Stop appending shared path twice; `locale_shadowing` should fail the double load, not only key collisions.
495. **`t(..., default:)` hides missing nb.** Prefer required keys; `i18n_resolution_test` ignores defaults.
496. **Unused-key check absent.** Extend `locale_contract_test.rb` with a reference scan over ERB/`t("` — no i18n-tasks gem.
497. **Interpolation parity absent.** Assert `%{name}` sets match across nb/en.
498. **`chrome_i18n` aria baseline 172.** Translating `_favorite_button` etc. must lower the baseline in the same commit.
499. **Empty-state English still in TV channels.** Lint looks for `title: "No …"`; body literals aren’t covered. Extend a body rule or fix the two TV strings.
500. **`Shared::Errors` vs local forms.** Creator profile reimplements errors. Always `render "shared/errors"`.
501. **Sweeps can overlap.** `limits_concurrency` on bulk jobs (`retry_on` is not uniqueness).
502. **`WebPushJob` duplicated.** `brgen/app/jobs/web_push_job.rb` and `shared/app/jobs/shared/web_push_job.rb`. One class.
503. **`LiveSearchable` deals exception.** See 347.
504. **New `after_commit` notifiers must `includes` at the job.** Grep `deliver_notification` without `strict_safe` / includes.
505. **`ActivityTrackable` actor nil on failure.** Analytics drop silently. Log once per event name.
506. **`examples.html.erb` English aria.** If routed, i18n; if not, don’t mount.
507. **`_ad_slot.html.erb` inline display.** AdSense requirement; keep. Ensure consent wraps it.
508. **Affiliate disclosure.** Must render on deals and amber shop. Add a view assertion per app.
509. **`master_embed`.** Don’t double-load face JS.
510. **CSP reports controller.** `skip_forgery_protection`. Rate-limit; cap body.
511. **OmniAuth buttons still shown if provider unset.** Hide via `oauth_provider_slugs`.
512. **`examples.html` / `jox_logo_controller.js`.** Grep; if only examples, don’t ship in boot.
513. **`optimistic_send_controller.js`.** Votes don’t use it. Wire vote arrows or delete unused controller.
514. **`parallax_tilt_controller.js`.** If unused in ERB, delete (`stimulus_wiring` will tell).
515. **`stimulus_boot.js` loads full @stimulus-components fleet.** Split per layout.
516. **PWA SW `networkTimeoutSeconds: 20`.** 3–5s then offline page.
517. **SW caches status 0.** `CacheableResponsePlugin({ statuses: [0, 200] })` caches opaque failures. Drop 0.
518. **`__APP_NAME__` cache names.** Must not collide across apps on `amber.brgen.no` vs `brgen.no`.
519. **Offline page Retry.** Confirm bsdports uses shared offline, not a local copy.
520. **Legal pages city TLD.** Grep `brgen.no` in `legal.*.yml`.
521. **`VAPID_SUBJECT` default `admin@brgen.no`.** Wrong for bsdports.org. Per-app env.
522. **`schema_migration` regex.** `/create_table\s+["':](\w+)["']/` misses `create_table :posts`. Fix regex + exempt `if_not_exists` repair migrations.
523. **`css_minify_integrity` selector-loss dead.** dart-sass 1.101.0 doesn’t drop selectors. Keep compile check; skip loss half or detect sass version.
524. **Six gates load-time ROOT.** Add `root:` kwarg so tests don’t rewrite constants.
525. **`scale_ratchet` under-baseline is warning.** Fail until the number is lowered (same contract as chrome_i18n).
526. **`frontend_auditor` advisory unless `GATE_AUDITOR_STRICT`.** Document in `runner.rb --explain`.
527. **`visual_contract` without `--capture` must not print “ok”** as if pixels were measured.
528. **Authenticated personas missing.** `GATE_ADEQUACY.md` gap 1: cart checkout, dating matches, sell form, amber mutations. Add a signed-in fixture user in triangle.
529. **page_sim `:id` pages source-only.** Seed one listing/video id for live.
530. **CDP flake → green.** `--all` should not treat <3 surfaces as pass.
531. **No axe tree.** Don’t claim a11y complete. Accent_contrast is filled controls only.
532. **`gate_mutation` doesn’t plant mobile_flow/page_simulation defects.** Extend plants.
533. **Affiliate honesty.** Assert disclosure on deals index HTML fixture.
534. **`css_constitution` — confirm planted illegal `px` fails.** If it still matches comments, it’s a spelling gate — fix the detector.
535. **`coverage_ratchet` floors stale.** brgen 21/24, amber 2/10, bsdports 2/8. After new tests, raise in the same commit.
536. **Maps engine invisible to some globs.** Any new gate must include `brgen/engines/*/app`.
537. **`i18n_resolution_test` skips `default:`.** Fail on `default:` in views, or resolve with `raise_on_missing`.
538. **Engine `en.yml`/`nb.yml` headers lie.** “Keys the host already carries are NOT copied” — then views add `default:` EN. Either use host keys without default, or copy into engine.
539. **Playlist engine nb incomplete vs defaults in ERB.** Transport, add_track, sets_subtitle.
540. **`marketplace.stores.*` defaults.** edit/delete/confirm.
541. **`shared.errors` default in store form.**
542. **`profile.edit` default.** `users/edit.html.erb`, `users/show.html.erb`.
543. **`posts.add_photo` default.** `posts/new.html.erb:55,60` — aria uses `t(..., default: "Add photo")` and the button still says `Add photo`. Same on edit.
544. **`nav.show_menu` default.** `_mobile_chrome.html.erb`.
545. **`compose.*` used in dating/amber.** Keys in amber nb; brgen must have them too for dating toolbar.
546. **`legal.dating_age`.** Used in dating new. Confirm nb.
547. **Flash `full_messages.to_sentence`.** English AR. `activerecord.errors` nb.
548. **`pluralize` in amber widgets.** Always English. `t("wardrobe.demo_pieces", count:)`.
549. **PWA manifests descriptions EN** in all three apps.
550. **Mailer subjects EN** besides subscriptions: `newsletter_mailer`, `verification_mailer`, `queue_failure_mailer`.
551. **Time `distance_of_time_in_words` locale.** Deal countdown — `I18n.locale` must be nb.
552. **City copy contract.** Add dating “Bergen” literals if any.
553. **`nav.takeaway` default `"takeaway"`.** `maps/places/show.html.erb:66,69`.
554. **OAuth nested defaults.** `_oauth_links.html.erb` three layers. One key.
555. **Dating engine `bio: Bio`** while host has `about_you`. Dead key or wrong label.
556. **172 EN aria-labels.** Start with favorite button, live streams, playlist transport (visible on :nb).
557. **Error pages have no skip-link** and no `#main-content` id on `<main>`. Add both to static errors.
558. **Color swatch `title` + aria English.** amber items show.
559. **Outfit composition unlabeled list.** Should be a list of item names.
560. **Live stream `role=list` without `listitem`.**
561. **Form errors `tabindex=-1`.** Turbo 422 must move focus.
562. **Video notes timestamp field unlabeled in nb.**
563. **`lang` on `<html>`.** Verify application layouts; static errors are `lang="nb"` even for EN gloss children.
564. **Marketplace `_card_media` empty alt.** Confirm `alt: listing.title`. Same for `_top_offers`, event covers, stories, dating picks/verifications, playlist player art, dressing-room imgs. Decorative avatars next to a name may stay empty; content photos may not.
565. **Maps engine zero tests.** See 431.
566. **Dating engine missing controller tests** (host has likes/rewind/unmatch/verification).
567. **TV engine activity + view_event only** — no comments/notes/chat.
568. **Playlist engine playlist + party only.**
569. **Amber `AiController` untested** including Open3 branch.
570. **`fediverse_test.rb:40` skip if no second city.** Seed a second city in fixtures so the skip never fires in CI.
571. **`tradedoubler` skip unless table.** Migrations should make this impossible; if skip remains, schema load is incomplete.
572. **`partner_attribution_report_test` skip unless constant.** Load path bug — require the model.
573. **System tests:** no system test for dating swipe or marketplace checkout.
574. **`query_budget_test.rb`.** Extend to listings#index with facets.
575. **`attachment_preload_test.rb`.** Add TV show comments/notes and marketplace show questions.
576. **`turbo_broadcast_contract_test.rb`.** Add stream_chat broadcast explicit `partial:`.
577. **Engine `rake test` from engine dir.** Document `bin/ci` includes engines. Maps none.
578. **`infinite_scroll_reflex` TV channels.** `_live_search_results` references `ChannelsInfiniteScrollReflex` — verify class exists under tv, not host.
579. **Almost no `limits_concurrency`.** Only `RecommendOutfitsJob`. Add to: `AffiliateImportJob`, `PortsImportJob`, `NightlySearchIndexRebuildJob`, `ListingExpiryJob`, `SavedSearchAlertJob`, `ExpiredStoriesSweepJob`, `ExpiredMessagesSweepJob`, `ComposeNewsletterEditionJob`, `LinkConverterSyncJob`, `UserPurgeJob`, `DeclutterHygieneJob`.
580. **`LinkConverterSyncJob` every 5 minutes.** Can stack. Concurrency 1 + uniqueness key.
581. **`NightlySearchIndexRebuildJob` no-op without `posts_fts`.** Silent return. Log.
582. **`GenerateBlurhashJob` uniqueness per blob.**
583. **`DillaRenderJob`.** Must not overwrite takes. Assert the output lands beside `STUDIO/dilla/dilla.rb` or the brgen equivalent; never `$PWD`.
584. **`PostproJob` from listing create.** If worker busy, listing has unprocessed photos. Status column?
585. **`GoogleEnhancedConversionsJob`.** PII. Test it no-ops without env; don’t retry forever.
586. **`ChannelBotReplyJob`.** Rate; loop guard.
587. **`Fediverse::DeliveryJob` uniqueness per inbox+activity.**
588. **`NotificationDeliveryJob` double-push.** **Unverified** internals. Test like/follow once.
589. **`CableHealthJob` / `CacheHealthJob`.** If they alert, test; if not, don’t schedule.
590. **`playlist` likes_count/plays_count nullable.** NOT NULL 0.
591. **`tv_videos.views_count` nullable.** Default 0.
592. **`identity_assurances.expires_at` unindexed.** If any scope queries it, index; if nothing reads it, don’t add. **Unverified** readers.
593. **`notifications` polymorphic index.** Confirm `(notifiable_type, notifiable_id)` exists.
594. **`marketplace_orders.variant_id` indexed?** Verify if `find_by(variant_id)` in stock decrement. **Unverified.**
595. **Grep remaining `update_column` without `updated_at`.** WIRING_NOTES trap.
1061. **`.page-header` is five different elements across the verticals.** Measured at
     1440px on 2026-09-12: absent on markedsplass and playlist, 0px wide on dating,
     747.03px on takeaway (max 747.035px), 600px on tv, and absent on brgen's front
     page, which uses `.feed-header` instead. So the shared page-header contract in
     `shared/LAYOUT.md` describes an element that four of seven surfaces do not
     render and one renders at zero width. Either the contract names the wrong
     element or the verticals do — deciding which is a layout call and the
     operator's; the measurement is here so it is not made blind.

596. **The prescription is wrong, and measuring it found a smaller real thing.**
     Measured at 1440px on 2026-09-12, `.layout` max-width: brgen 600px, tv 600px,
     markedsplass / dating / playlist / takeaway all 100%. `--feed-max` is 600px on
     every one of them, so the four are opting out by rule, not missing a token —
     and each opt-out has an argument. marketplace and takeaway are storefronts:
     takeaway's own comment says the 600px column crushes the two-row #navBar and
     leaves the restaurant grid no room, and Kaufland is the model there. dating and
     playlist are immersive verticals — `_vertical_shell.scss` hides the core chrome
     on them, so there is no column for content to sit in. tv is the browsable one
     and already has the column. Applying `.app-shell`'s measure cap to all four
     would undo two deliberate decisions.

     What was real: dating and playlist each set `grid-template-areas: "main"` and
     `grid-template-columns: 1fr` on `.layout`, which is `display: flex` in
     `_shell.scss` on every surface — measured flex on brgen, dating, playlist and
     markedsplass alike. Four inert declarations, removed; max-width and display
     measured identical before and after.
597. **`_ui_refinements*` merge.** Boy Scout on next CSS touch — merge into domain partials, no visual change.
598. **`_shared_coverage_fills.scss`.** If it exists only to satisfy css_coverage_lint, that’s a spelling gate — prefer real selectors or fix the lint.
599. **`_stack_brgen.scss` vs `_stack.scss`.** Document why two.
600. **`pull_to_refresh_controller.js`.** Confirm not fighting Turbo morph.
601. **`tabs_controller.js` vs nav swiper.** Two tab patterns. Feed sort should reuse one.
602. **`countdown_controller.js` vs `Deal#ends_in`.** Deals use `distance_of_time_in_words`. If countdown JS unused on deals, don’t load globally.
603. **`share_controller.js`.** i18n toast.
604. **`form_submit_controller.js#lock`.** Attach to listing create / takeaway order.
605. **`lazy_image_controller.js` vs `responsive_image_tag`.** One path.
606. **`lightbox_controller.js` vs lightgallery vendor.** Pick one.
607. **Listing kinds `chip` vs `chip active`.** `aria-current`.
608. **Stimulus controllers without a matching test.** `countdown`, `feed_updates`, `form_submit`, `lazy_image`, `lightbox`, `map`, `pull_to_refresh`, `push`, `radio_tunnel`, `request_location`, `share`, `swipe`, `tabs`, `toggle`, `typing`, `typing_input`, `voice_recorder`, `dating_intro`, `marketplace_logo`, `playlist_player`, `tv_feed`, `tv_player`, amber `filter` / `sortable` / `wardrobe_carousel`. One Node-free contract per controller, or a source contract that each is mounted by a view (the infinite-scroll pattern).
609. **Webhook CSRF skip without rate_limit.** Engine + host Stripe/Vipps/TradeDoubler. Add IP limits.
610. **`AiController` unbounded work.** Auth + rate_limit. Argv array is OK; still a 1 GB box.
611. **`TrackImport` URLs.** SSRF like `LinkPreviewFetchJob`. Reuse `OutboundHttp`.
612. **Mass assignment kinds.** `listing_params_for_kind` — ensure `kind` not user-switchable after create to skip price.
613. **Push subscriptions controller.** Rate-limit subscribe. VAPID per app (521).
614. **Guest photo upload.** Rate-limit + size via `MediaGuard`. Confirm `MediaGuard` on messages#create.
615. **Posts new form English.** `posts/new.html.erb:13-14` `f.label :community_id, "Community"` / `include_blank: "Anywhere in Bergen"`; `:30` `"Body"`; `:60` `Add photo`; `:72` `"Post anonymously"`. All keys. City-aware blank, not Bergen on every host.
616. **`users/new.html.erb:43` “Leave this field empty”.** Honeypot label. i18n; keep off-screen.
617. **Playlist hosted tracks.** `"Replace audio file (keeps URL)"`, `"Upload track"`, `"Unknown artist"`, `"Create playlist"`, `"Only owners can invite collaborators."`
618. **Shared empty_state comment example is English.** Fine as a comment. Callers must pass `t(...)`. Audit callers that pass English string literals.
619. **Newsletter `_hero.html.erb:14` “Curated offers”.**
620. **Untested engine models.** dating: `daily_pick`, `dislike`, `like`, `prompt`, `verification`. marketplace: `address`, `category`, `checkout`, `gig_detail`, `housing_detail`, `job_detail`, `listing`, `listing_favorite`, `payout`, `question`, `return`, `review`, `saved_search`, `store`, `variant`, `variant_option`. playlist: `audio_version`, `collaboration`, `dilla_sketch`, `like`, `listen`, `party_message`, `playlist_track`, `set`, `set_track`, `timestamped_comment`, `track`. takeaway: `delivery_driver`, `favorite_restaurant`, `menu_item`, `opening_hour`, `order_item`, `restaurant`, `review`. tv: `broadcast`, `channel`, `episode`, `live_stream`, `show`, `sound`, `stream_chat`, `subscription`, `video`, `video_note`. One model test each, starting with state machines and uniqueness.

### OPENBSD — dual sources

621. **`sh/` does not exist.** `OPENBSD/README.md` claims deploy tooling lives under `bin/`, `lib/`, `sh/`. There is no `OPENBSD/sh/`. Drop `sh/` from the sentence.
622. **Same ghost path in law.** `OPENBSD/DECISIONS.md` “Repo Layout” still lists `sh/`. Align with the tree.
623. **PATH_OWNERSHIP still names `openbsd/sh/vps_ci.sh`.** File is `OPENBSD/vps_ci.sh`. Fix the key and the `zsh -n` check path.
624. **Fixed 2026-09-12.** `README.md` carries no table at all — zero table rows,
     checked. `SSH_ACCESS.md` now names its own Architecture block as the network
     map, which is what it always was, three lines under the pointer that sent the
     reader elsewhere for it.
625. **Fixed 2026-09-12.** The paragraph named four hosts; `bin/uptime-check.sh`
     execs `health_check.rb --public-only --all-ready-apps` and has no URL list of
     its own. It now says that, and says what `--public-only` costs: the service,
     certificate and relayd checks are the same script without the flag.
626. **Fixed 2026-09-12.** Four rows against ten scheduled jobs, so six self-healing
     jobs — uptime-check, drain-jobs, core-reclaim, keep-warm, prune-guests and
     weekly-integrity — existed only in `etc/crontab.vm23` and not in the table an
     operator reads. All ten are listed. The `relayd-watchdog` row credited it with
     healing `doas.conf`; that step ran `validate_doas.ksh` from a dev-owned
     checkout as root every five minutes and was deliberately removed, which its own
     header records. The weekly-integrity row carries its never-installed state
     rather than implying it runs.
627. **Fixed 2026-09-12.** `vps_production_push.sh` deploys bsdports too — its own
     first line says so and line 36 runs it. The table said master + brgen + amber,
     which understates a footgun, and understating that one is the wrong direction.
628. **httpd 6666 comment vs CLAUDE.** `CLAUDE.md` still says `httpd.conf` listens on `* port 6666`. Live file listens on `127.0.0.1 port 6666`.
629. **MEM_RESTORE drift — fixed 2026-09-12.** OPENBSD/CLAUDE.md said 8/14 for a
     month after resource_guard.sh moved MEM_RESTORE to 10 on 2026-08-14, a
     recalibration the script records with the 1550 ticks behind it. The doc
     names the current pair and points at the script;
     `test_guard_thresholds_documented` refuses prose that names a different
     number from the code.
630. **Fixed 2026-09-12.** The comment had it backwards in both directions: amber is
     in `OPTIONAL="bsdports amber"` and master is in `CORE="master brgen"`. It no
     longer reasons from the guard's sets at all — brgen and amber are simply the
     two surfaces a visitor arrives on cold, and the shed case was already handled
     six lines below by the per-target `nc -z`.
631. **Fixed 2026-09-12.** `OPTIONAL="bsdports amber"` now, matching the guard.
     litestream is doubly stale: `restore_backups.sh` records that no litestream
     binary exists on vm23 and `/var/backups/litestream/` is empty.
632. **Fixed 2026-09-12.** `data/operator.yml` is the command list and now carries
     the whole of it: the check family (check-rails, check-openbsd, check-vps,
     check-full), vps-state and tree.sh lived only in START_HERE.md's Golden
     Commands, so the stub that pointed here was the more complete of the two.
     START_HERE's Golden Commands and Source Of Truth sections are pointers now,
     and RECIPES.md is a door rather than a table. `operator_docs.rb` reads the
     yaml and `/orient deploy` prints it, so a recipe added there shows at every
     door.
633. **Fixed 2026-09-12.** `data/operator.yml` is the command list and now carries
     the whole of it: the check family (check-rails, check-openbsd, check-vps,
     check-full), vps-state and tree.sh lived only in START_HERE.md's Golden
     Commands, so the stub that pointed here was the more complete of the two.
     START_HERE's Golden Commands and Source Of Truth sections are pointers now,
     and RECIPES.md is a door rather than a table. `operator_docs.rb` reads the
     yaml and `/orient deploy` prints it, so a recipe added there shows at every
     door.
634. **Fixed 2026-09-12.** START_HERE.md's Source Of Truth section listed
     `RAILS/apps.yml` under both "App inventory" and "Feature inventory". That whole
     section is a pointer to `operator.yml`'s `single_source_of_truth:` now.
635. **DECISIONS vs unsigned zones in git.** “61 zones … none of them in git”. `var/nsd/zones/master/` holds 57 unsigned `*.zone` templates by design. Narrow the decision to signed artifacts / keys.
636. **RUNBOOK still describes a fixed deploy_all header.** Current header says there is no archive. Update RUNBOOK.
637. **deploy_all still logs archive/recovery.** `deploy_all.sh:49`. Delete the log line.
638. **tools/tree.rb still DRIFTs a missing dir.** Prints `archive/recovery` as DRIFT. Drop both.
639. **PATH_OWNERSHIP lists `archive/`.** Directory does not exist. Remove the row.
640. **Retired-apps prose vs extra_zones.** RUNBOOK says foodielicio.us went with baibl; `data/dns.yml` `extra_zones` still serves them. Pick one source.
641. **Fixed 2026-09-12.** The comment lives in `render_dns.rb`, and it was wrong
     twice: the count is four, not five, and `bsdports.net` has no zone at all —
     `bsdports.org` is the one with a zone and it is in ALL_DOMAINS, so it was never
     in that set. Computed from `city_zones` and `extra_zones`: 53 city, 13 extra,
     four outside — the anti-gambling trio and foodielicio.us. render_dns reports in
     sync across all 57 zones, so nothing rendered changed.
642. **extra_zones duplicates ALL_DOMAINS.** Keep extras only for names not in ALL_DOMAINS.
643. **doas.conf.example is a different policy.** Mark the example historical or generate it from the live file.
644. **sshd_config is a fragment.** Either track the whole file or say this is a fragment OPERATOR merges.
645. **login.conf is the OpenBSD sample.** Confirm whether app login classes still live here; if unused, stop installing it.
646. **vm_resource.yml falcon workers.** `master_falcon_workers: 2`. `etc/rc.d/master` uses `${FALCON_WORKERS:-1}` and comments “keep at 1 on 1GB”. Make the yaml match.
647. **vm_resource.yml load comment vs guard.** Guard uses 5-minute load; yaml keys are `load_avg_1m_*`. Rename keys to 5m or stop claiming they mirror.
648. **operator.yml Solid Queue vs rc.conf.local.** Add a one-line “must match pkg_scripts” note.
649. **CLAUDE vs RUNBOOK on SKIP_CI.** Make RUNBOOK a pointer at CLAUDE’s section.
650. **START_HERE “check-full chains local checks and the integrity gate”.** `bin/check-full` also runs `RAILS/test/run_all.rb`. Name that third step.
651. **PATH_OWNERSHIP RAILS paths with lowercase `rails/`.** Use real paths `RAILS/` / `OPENBSD/`.
652. **PATH_OWNERSHIP omits most of the tree.** Add rows or a glob policy for `data/`, `test/`, `gates/`, `lib/`, `dotfiles/`, `quarantine/`.
653. **PATH_OWNERSHIP `tools/` check is `MASTER/tools/verify`.** Point at `OPENBSD/bin/check-openbsd` or a local test.
654. **deploy_inventory `generated_at: 2026-07-15`.** Regenerate on apps.yml change or drop the date.
655. **sync_deploy_inventory drops `standalone_apps`.** Preserve the key.
656. **health_check public master is a literal.** `:411` `"ai.brgen.no"`. Read `deploy_inventory.json` `master_face`.
657. **Two uptime checkers, two master policies.** One function, one list.
658. **Fixed 2026-09-12.** `data/dns.yml` declares `resolvers.public`, and
     `gates/dns_zones.rb` reads it along with `nameserver.ip` instead of carrying
     its own two literals. The copies had already drifted: OPERATOR.sh led with
     8.8.8.8 while the gate used Cloudflare and Quad9 and had written down why, so
     the gate's list won and OPERATOR.sh dropped Google. `test_dns_facts_agree`
     fails if either copy moves without the other.
659. **Fixed 2026-09-12.** `data/dns.yml` declares `resolvers.public`, and
     `gates/dns_zones.rb` reads it along with `nameserver.ip` instead of carrying
     its own two literals. The copies had already drifted: OPERATOR.sh led with
     8.8.8.8 while the gate used Cloudflare and Quad9 and had written down why, so
     the gate's list won and OPERATOR.sh dropped Google. `test_dns_facts_agree`
     fails if either copy moves without the other.
660. **Held rather than moved, 2026-09-12.** They stay as shell literals: the block
     is sourced before anything runs, and making the deploy script shell out to
     ruby34 to boot would put it behind an interpreter it is itself responsible for
     installing. `test_dns_facts_agree` asserts BRGEN_IP is `nameserver.ip` and
     HYP_IP the first `xfr_peers` entry, so the duplication now costs something.
661. **relayd-watchdog BACKENDS table hardcoded four ports.** Add this file to `SMOKE_SCRIPTS` / `FLEET_INVENTORIES`.
662. **Fixed 2026-09-12.** The names come from the same read as the ports, twelve
     lines below where the frozen `%w[brgen amber bsdports]` used to sit — the file
     was already loading apps.yml for ports and keeping a second inventory for
     names, so a fourth app would have shown its port and never its row. master
     keeps its own block: it is not under /home/*/app and not in apps.yml.
663. **vps_ci_all apps hardcoded.** Same.
664. **start_all_apps SERVICES hardcoded.** Derive from inventory + master.
665. **Declined 2026-09-12, and the file now says why.** TARGETS is a curated pair,
     not a stale copy of the fleet: brgen and amber are the surfaces a visitor
     arrives on cold. Reading apps.yml would warm bsdports, a low-traffic index
     nobody waits on, and master, whose 927M of address space is correctly swapped
     out until someone opens the face. The shed case is handled per target by the
     `nc -z` below the list.
666. **Fixed 2026-09-12.** Falling back is a finding now: the built-in names are
     still checked, because knowing those four are up beats checking nothing, but
     the run exits nonzero whatever they answer and says the exit code is the
     missing list rather than them. A green uptime check measuring a fleet one
     deploy out of date is exactly what the file's own header warns about. The
     fallback names and the derived list agree today: brgen, amber, bsdports,
     master.

### OPENBSD — scripts, expect, gates

667. **vps_deploy_master.sh is a second MASTER deploy.** Keep as recovery (already decided) but have it call `vps-deploy master`.
668. **vps_production_push vs vps-deploy all.** Make push `SKIP_CI=1 vps-deploy all` plus the optional demo seed.
669. **vps_install_all vs vps_on_vm_install.** Fold into one “bootstrap on box” script; the other becomes a one-line wrapper.
670. **vps_install_all stashes the box.** `git stash push`. Root TODO records that stashing Gemfile.lock on vm23 broke master. Delete the stash; `git pull --ff-only` only.
671. **smoke-apps.sh vs deploy-smoke.sh.** Make smoke-apps a `deploy-smoke --local` alias or delete it and retarget `port_inventory` `SMOKE_SCRIPTS`.
672. **check vs check-openbsd overlap.** Document a Venn in START_HERE, or have `check` call `check-openbsd` instead of repeating identity/smoke.
673. **check-full vs integrity_gate.** Deduplicate the integrity list.
674. **check-vps ON_VPS test is a third predicate.** One helper: `Operator::Environment.on_vps?`.
675. **check-openbsd uses `RbConfig.ruby`, check uses `Operator::RubyRunner.gate_ruby`.** Use the gate runner everywhere.
676. **tree.sh header still talks about “MASTER KISS/DRY redesign”.** One-line usage.
677. **solid_queue_proof.sh is a doas trampoline.** In-line in the caller or `bin/`.
678. **amber_queue_sweep.sh vs drain-jobs.sh.** Name the pair in RUNBOOK; give sweep `--help` and an app argument (it is amber-only today).
679. **extract_legacy_installers.sh vs restore_backups.sh.** If the source is gone forever, make extract exit 2 with that sentence.
680. **extract_legacy uses `tr`.** Banned. Use zsh `${rel//\//_}` or Ruby.
681. **`_net.sh` `generate_random_port` always errors.** Delete if unused, or make unused-path fail at parse.
682. **OPERATOR tmux falcon fallback.** Starts a second falcon as **dev**. Conflicts with `daemon_user="master"`. Remove or refuse if rc.d/master is enabled.
683. **manual_master_deploy.ksh.** Add a first-line “untested recovery — read DECISIONS.md” and a `--help`. Do not fold.
684. **deploy_all.sh default `SSH_KEY=~/.ssh/id_rsa`.** Every other file uses `id_ed25519_brgen`. Change the default.
685. **deploy_all VPS_HOST is a bare IP.** Source `lib/ssh_vm23.sh` and drop the copy. Same for `vps_run_remote.sh`.
686. **post-pull-checklist is a here-doc.** Generate from `operator.yml` or delete in favour of `operator status`.
687. **deploy-diff.sh vs sync.rb vs config_drift_gate --remote.** Make deploy-diff a wrapper over the gate’s report.
688. **dev/agent_worktree.sh vs MASTER/bin/operator worktree.** Exec the operator command or delete it.
689. **dev/*.sh (backup, clean, lint, perms, replace, watch_tests).** Workstation helpers in the OpenBSD tree. Move to `dotfiles/` / `MASTER/tools/` or declare Mac-only with check `none`.
690. **ptr_openbsd_amsterdam.rb has no test.** Add a dry-run test that the request is built, not sent.
691. **relayd_prune_keypairs.rb writes /etc/relayd.conf with no dry-run.** Default to stdout/`--check`, require `--apply` to write.
692. **sync.rb FIXED_SOURCES vs config_drift VERBATIM.** Make sync’s source list = VERBATIM + EXCLUDED so a hand-edit cannot hide in a file sync never copies.
693. **vps_console.exp embeds a live pubkey.** Read `SSH_ACCESS.md` / a data file, or pass `$env(SSH_PUBKEY)`.
694. **probe mode does not use `console_open`.** Use `console_open` so host/port/key stay one place.
695. **status mode uses `head`.** `vps_console.exp:55`. Banned. Use `ruby -e` or `ps` limits.
696. **No behavioural test for console ack.** Add a dry-run that `expect -d` with `I_UNDERSTAND_CONSOLE_RISK` unset exits 1. Do not fold the nine shims.
697. **port_inventory RETIRED_ACTIVE_PATHS includes live console shims.** Rename the list; they are not retired.
698. **No `--help` on the nine shims.** Document `vps_console.exp` usage in RUNBOOK’s occasional-tools table.
699. **test_health_check.rb measures spelling.** Replace with a `--public-only` run against a stub CURL that returns 200/000.
700. **`--public-only` not in the flag test.** It is the laptop path.
701. **test_vps_safety_gate.rb is “gate passes”.** Add the shape it must flag: a doas.dev rule with `keepenv`.
702. **vps_safety_gate skips basename `litestream`.** There is no `etc/rc.d/litestream`. Delete the skip.
703. **vps_safety_gate only pins `I_UNDERSTAND_DNS_WIPE`.** Pin the other four or the whole `setenv { … }` string.
704. **verify_openbsd_idempotency.rb is source grep on OPERATOR.sh.** Add a known-bad fixture (OPERATOR snippet missing the backup).
705. **verify_deploy_identity.rb is string includes on `_deploy.sh`.** Assert the functions exist via `zsh -c 'source …; whence -w deploy_tracked_app'`.
706. **No OPENBSD test for dns_zones / domain_alignment / port_inventory / installed_targets / deploy_smoke.** Each wants a known-bad fixture (decision 2026-08-22).
707. **No test for integrity_gate.rb.** Assert skip_reason for `:vps` off-box, and that `:live_http` / `:repo` needs are actually consulted.
708. **GateEnvironment skip_reason ignores `:repo` and `:live_http`.** Wire them or drop them from the structs.
709. **test_gate_lib does not cover `GateResult#measured_nothing?`.** Add the empty-run vs checked! cases here.
710. **config_drift_gate tests only crontab.** Add a VERBATIM file mismatch and an EXCLUDED file that must *not* fail.
711. **installed_targets CONFIG_GLOBS miss usr/local.** Include `usr/local/bin/*` as referrers or document the hole.
712. **check does not run installed_targets, dns_zones, vps_safety.** Those live only in `check-openbsd`. Either include them or say contributor must run both.
713. **Fixed 2026-09-12, and wider than asked.** `OPENBSD/shell_syntax_gate.rb`
     reads each script's shebang and parses it with the interpreter that shebang
     names, so the set is the tree rather than a list somebody maintains. It covers
     43 scripts across zsh, ksh and sh — all of which parse today — and replaces the
     two hand-named lines, so check-openbsd got shorter. Recorded as OPENBSD 112 ->
     113 in spine.yml.
714. **deploy_smoke_gate check_master_rc is a string hunt.** Assert “warmup hits a public unauthed path”, not that exact `chat/message?message=ping` query.
715. **domain_watch population is nsd.conf.** Read `RenderDns.zones` so a zone not yet in nsd.conf still gets whois.
716. **test_domain_expiry `--update` needs `/usr/bin/timeout`.** Document in START_HERE: refresh on vm23; local red is not a code defect.
717. **domain_released.yml is empty while five domains fail.** Point failure output at this file so the next agent does not “fix” the test.
718. **weekly.local runs domain_watch from the checkout as dev.** PATH_OWNERSHIP does not mention `bin/domain_watch.rb`. Add it.
719. **config-drift-check cannot run as dev.** If nsd.conf unreadable, exit 2 “needs root” instead of treating empty nsd as “no zones”.
720. **daily.local comments should state the two questions** (repo-versus-live `/etc` bytes vs relayd/acme/nsd consistency) in one line each.
721. **bin/check loads all OPENBSD tests in one `-e` process.** One process per file, as check-full already does for Rails.
722. **reach.rb vs installed_targets_gate.** Wire reach into check-openbsd or fold its unique checks into installed_targets.

### OPENBSD — shell, rc.d, DNS, tests, remaining

723. **vps_weekly_integrity.sh is `#!/usr/bin/env sh` and may use `fuser`.** **Unverified on box.** If missing, use the Ruby with-ci-lock nonblock.
724. **ci_lock.sh comment still says “opened with lockf(1)” at line 20** then corrects to flock(2) at 44. Delete the first sentence.
725. **emergency_cpu.sh unquoted fallback source.** Quote `. "${GUARD_REPO}/OPENBSD/usr/local/libexec/stale_ci_cleanup.ksh"`.
726. **start_all_apps.sh: `set -e` without pipefail.** Add `set -eo pipefail`.
727. **vps_deploy_master.sh: `set -e` only, `#!/bin/sh`.** Add pipefail.
728. **amber_queue_sweep.sh: no pipefail, no usage.** Add `set -eu` and a usage line.
729. **renew-certs.sh add `--help`.**
730. **tree.sh `CDPATH= cd` vs `CDPATH='' cd --`.** Use the safer form.
731. **dev/agent_worktree.sh add `--help`.**
732. **vps_weekly_integrity re-exec.** Detect `dirname $0` = `/usr/local/bin` or refuse.
733. **rails-app.tmpl is a third rc.d.** No PATH export, `pexp="ruby.*${port}"` not `ruby34`, `daemon_timeout="60"` not 120. Either regenerate apps from a fixed tmpl or delete the tmpl and stop OPERATOR from installing it.
734. **irc_gateway has no PATH, no pexp.** Match brgen’s PATH/`bundle34 exec` shape so a go-live does not repeat the cron-PATH outage.
735. **amber vs brgen env paths.** Document which of the three paths is live; drop the others from the scripts.
736. **rc.d/master `bundle34 install` in rc_pre with `|| true`.** Fail the start if `bundle34 check` fails; do not install from rc.d.
737. **rc.d/master pkill patterns include `operator/MASTER/web`.** Stale path after OPERATOR→OPENBSD. Confirm pexp still matches; drop dead pkills.
738. **pf.stage1.conf has no 443 or 25.** RUNBOOK should say “stage-1 pf will not pass HTTPS or SMTP”.
739. **httpd listens 0.0.0.0:80.** `deploy_smoke_gate` does not check httpd.conf exists or has the ACME location. Add a one-line assert.
740. **acme-client.conf pair.** Mention in RUNBOOK that dns_zones `--check` diffs it so nobody byte-compares acme.
741. **relayd keypair list vs LIVE_DOMAINS.** Add the six “waiting” cities from RUNBOOK as an explicit not-yet list.
742. **OPERATOR.sh `EMAIL_ADDRESS="bergen@pub.attorney"`.** If unused, delete.
743. **newsyslog misses `/var/log/domain_watch.log`, `git_gc.log`, `/tmp/config-drift.out`.** Add rotation or write under `/var/log/`.
744. **rc.d/*_jobs footers are triplicated.** One `etc/rc.d/jobs.footer` comment file, or a shared tmpl with APP filled in.
745. **Run `render_dns.rb --check` in `check-openbsd` directly** so a DNS edit does not require the Rails gate registry.
746. **nsd.conf `server-count: 2` on 1 vCPU.** Put `server-count` in `data/dns.yml` (default 1 for vm23_small).
747. **False — checked 2026-09-12.** `render_dns.rb:84` reads it
     (`policy.dig("extra_hosts", domain)`) and `dns.yml:119` carries
     `brgen.no: [ns, amber]`, which is how ns.brgen.no and amber.brgen.no get their
     A records. Both halves are live.
748. **DMARC assert in `--check`.** Do not also emit `_dmarc` in zone_body for mail_domain.
749. **domain_inventory.yml `state: unknown` never alarms.** Fail or skip-with-count so “32 unknown” is visible.
750. **Nominet dates in inventory are already past.** Add `domain_watch --update` recipe in operator.yml.
751. **Argued against, and the argument is in the file.** `data/dns.yml`'s header
     states it: the domain list is deliberately not there, because ALL_DOMAINS is
     already what `domain_alignment` binds `Brgen::DomainRegistry` to, and a yaml
     copy would be a third list rather than one. The regex parse is real and is what
     that costs. Moving it means moving the binding too, which is a deploy-path
     decision and the operator's. See 32, which is the same proposal.
752. **Fixed 2026-09-12.** `OPENBSD/test/test_vps_deploy_contract.rb` — refuses uid
     0 with an exit rather than a warning, `all` expands to apps.yml plus master in
     the order the script argues for, and SKIP_CI=1 still runs `${app}.sh`, which is
     what reaches rails_runtime_gate. See 779 for the mutation check.
753. **No test for OPERATOR.sh beyond zsh -n and idempotency grep.** Add: `ALL_DOMAINS` parse round-trip against `render_dns` city_zones.
754. **resource_guard crisis path.** The test should fail if the crisis function’s path is not in `explicitly_installed`.
755. **test_restore_scripts.rb.** Add an executable dry-run with `LITESTREAM_CONFIG` pointing at a missing file, expect exit 1.
756. **test_githooks.rb.** PATH_OWNERSHIP should name `dev/githooks/` with this test as `check`.
757. **test_tracked_crontab.rb vs config_drift crontab tests.** Fold or cross-reference so a new cron line needs one fixture.
758. **No test for nsd-resign.** Fixture: a signed zone with a parseable RRSIG vs garbage. `rescue nil` on expiry parse swallows errors.
759. **No test for renew-certs.sh intersection logic.** Unit-test CONFIGURED∩HELD in zsh with tmp crt/conf dirs.
760. **No test for prune-guests.sh wait loop.** A ksh test with `PRUNE_GUESTS_LOAD_CEILING=0` should still run one tick.
761. **No test for drain-jobs.sh / keep-warm skip-if-not-listening.**
762. **health_check `--core` banner.** State that smtpd is required and master is a service not an app.
763. **“Every gate carries its known-bad fixture” (2026-08-22).** Adopt-forward: next touch of each gate adds the pair.
764. **“No staging environment” is still open.** Point `vm_resource.yml` at this entry so a “add staging” idea dies in one place.
765. **“Auto-commit atomicity” is still open.** Belongs in MASTER/dev hooks, not OPENBSD/DECISIONS. Move or delete.
766. **Deploy script names still say `RAILS/deploy.sh`.** If per-app `RAILS/<app>/<app>.sh` is the truth, fix the decision line. **Unverified** whether `RAILS/deploy.sh` exists (it does at tree root).
767. **Gate kernel decision vs PATH_OWNERSHIP.** Add `lib/` row with the decision’s check.
768. **doas install decision vs RUNBOOK.** RUNBOOK still says cron heal paths use `validate_doas.ksh`. Heals were removed.
769. **Fixed 2026-09-12, and the premise needs a correction.** It did not fail open:
     measured in an isolated checkout with no apps.yml, the old code still exited 1
     — but by way of "brgen: missing port in apps.yml", because `core_apps` hardcodes
     brgen. The right answer for the wrong reason, and only by accident of that
     hardcoding. The real cause went to stderr where the --json consumers never saw
     it. It is a first-class entry in `failures` now, so the JSON carries it.
770. **health_check `--core` still requires smtpd.** Document as required.
771. **resource_guard ALL_APPS_FLAG vs start_all_apps.** Name the flag in PATH_OWNERSHIP.
772. **Measured 2026-09-12 — the layout question is secondary to what it hides.**
     `emergency_cpu.sh` is not on vm23 at all. `resource_guard.sh:298` guards with
     `[ -x /usr/local/bin/emergency_cpu.sh ]` and otherwise logs "emergency_cpu not
     installed", so the LOAD_CRIT crisis path — the one deliberately exempted from
     the two-strike rule because a genuine crisis should not wait — has only ever
     written a log line. Installing it needs doas on the box and is the operator's.
     The repo-layout half (root vs usr/local/) still stands and is item 21's.
773. **Crisis tier on the box is missing the binary.** Confirm `explicitly_installed` scan matches `install -m 755 … emergency_cpu`. **Unverified scan.** If the install line does not match the regex, fix the regex, not the box.
774. **etc/litestream.yml header still reads as a how-to.** First lines should be: inert by decision; not in ports; do not enable; dr-pull is the backup. Keep the yaml body.
775. **OPERATOR `setup_litestream`.** Add `rcctl ls failed` must not contain litestream as a check in health_check.
776. **Fixed 2026-09-12.** `OPENBSD/restore_litestream.sh`. Three separate passes
    asked for this rename, which is what a real defect looks like from outside.
    Its first line now reads "NOT the disaster-recovery script — use
    OPENBSD/bin/dr-pull for that", and the paragraph under it says why: vm23 has
    no litestream binary and no replicas, so the old name promised recovery the
    file cannot deliver, under exactly the name somebody reaches for in an
    emergency.
777. **port_inventory RETIRED_CONFIG_PATHS includes litestream.yml.** Add a positive test: litestream.yml may exist, must not appear in pkg_scripts.
778. **vps-deploy drift gate is advisory.** Add `VPS_DEPLOY_DRIFT=fail` opt-in. Do not flip to blocking from here (box is dirty).
779. **Fixed 2026-09-12 as a test, not a derivation.** Deriving the list would lose
     the ordering argument the script writes down — master leads because it is
     independent and gets forgotten, amber and bsdports go last because every deploy
     sheds them and deploying them last folds the restore into the same pass.
     `test_vps_deploy_contract` asserts DEPLOY_ALL is apps.yml plus master and holds
     both ends of the order. Closes 752 with it: the same file covers the uid-0
     refusal and the SKIP_CI branch. Mutation-checked — dropping master fails 2,
     reordering 1, warning instead of exiting 1, gutting SKIP_CI 1, clean source 0.
780. **vps_production_push DEMO_SEED_ON_DEPLOY defaults to 1.** Production hotfix seeds the demo. Default 0; require an explicit 1.
781. **vps_deploy_master.sh `SECRET_KEY_BASE` openssl rand fallback.** Can boot master with a random key, wiping sessions. Refuse if `/etc/master.env` has no key.
782. **vps_on_vm_install `SECRET_KEY_BASE:-dummy` for assets:precompile.** Same class of footgun. Read `/etc/master.env`.
783. **`bin/vps-deploy` has usage on missing args, not `--help`.** Accept `-h`.
784. **integrity_gate post_pull_warning still says `zsh OPENBSD/vps_ci.sh`.** Canonical is `bin/vps-deploy`.
785. **deploy_inventory.json has no `standalone_apps` consumer except empty.** If unused, drop the key from the schema and the Inventory class.
786. **dotfiles/ is a Mac desktop setup.** Declare `purpose: operator Mac; not installed by OPERATOR.sh; check none` or move out of OPENBSD.
787. **fix_macos.sh references `FUN/config/`.** That tree does not exist. Point at `dotfiles/config/`.
788. **PUB4_ROOT in fix_macos is `SCRIPT_DIR/..`.** That is OPENBSD/, not repo root. `cd "${SCRIPT_DIR}/../.."`.
789. **zshrc.shared vs box `/home/dev/.zshrc`.** OPERATOR mentions `etc/.zshrc`. Find the tracked zshrc or stop syncing it. **Unverified path.**
790. **quarantine/virus_museum.** PATH_OWNERSHIP check should name `MASTER/tools/security_sweep.rb`. RUNBOOK: recovery is `bin/dr-pull` and `manual_master_deploy.ksh`; quarantine is inert samples.
791. **Missing `--help` / usage** on `bin/vps-deploy`, `vps-state`, `vps-logs`, `ds-records`, `render_dns.rb`, `domain_watch.rb`, `sync_deploy_inventory.rb`, `with-ci-lock`, `dr-pull` (**unverified**), `start_all_apps.sh`, `emergency_cpu.sh`, `amber_queue_sweep.sh`, `vps_ci.sh`, `vps_ci_all.sh`, `vps_install_all.sh`, `vps_on_vm_install.sh`, `vps_master_scan.sh`, `resource_guard.sh`, `core-reclaim.sh`, `keep-warm.sh`, `drain-jobs.sh`, `prune-guests.sh`, `tree.sh`. Pattern: `deploy-smoke.sh`.
792. **uptime-check cron redirects all output.** Failures only if someone reads the log. Print a one-line summary to stdout on failure so cron mails root. Same for config-drift-check.
793. **keep-warm has no heartbeat.** Touch `/var/db/keep_warm_seen` each run; health_check already has the pattern.
794. **vps-logs looks in `/var/log/pub4/${app}.log` first.** Probe `rcctl get ${app} logger` or document “always daemon”.
795. **OPERATOR.sh `2>/tmp/pkg_add.log`.** Use `/var/log/pub4/`.
796. **home/johann/bin/mailimg.** PATH_OWNERSHIP should list it as the executable check (`ksh -n`).
797. **stale_ci_cleanup.ksh lives under usr/local/libexec.** Include `/usr/local/libexec/` in installed_targets.
798. **gates live under OPENBSD/gates but run via RAILS/gates/runner.rb.** One paragraph in START_HERE: registered in `RAILS/gates/gates.yml`, invoked by `check-openbsd`.
1062. **`.dash-stats dl` wants auto-fit and could not be verified for it.** Amber's
     stat grid is four columns, two below md, and nothing between — a tablet gets
     the phone grid. `repeat(auto-fit, minmax(<floor>, 1fr))` computes the count and
     adds the three-column step, which is the right shape. It was written and then
     reverted on 2026-09-12: the floor has to be measured against the real dashboard
     container, that page is behind a login the CDP probe cannot reach, and a floor
     guessed wider than the column silently drops desktop from four columns to
     three. Measure the container, then set the floor.

1063. **`_root.scss:334` is the last max-width, and it is not a violation.**
     `(min-width: 768px) and (max-width: 1264px)` swaps `.compose-label` for
     `.compose-icon` in a band. MOBILE_FIRST does not flag it — the detector reads
     `@media (max-width` and this opens with min-width — and the max is the upper
     bound of an enhancement rather than a narrow-screen exception. Closing it would
     need the two elements' default display values, which have no rule anywhere in
     the tree and sit behind the same login. Left deliberately.

1064. **radio.<city> is live on vm23 — deployed 2026-09-12.** DNS, certificate and
     relayd landed together, because DNS alone would have made radio.<city> resolve
     to a box holding no certificate for it, which a browser reports as an attack.
     Order: 44 zone files copied and `nsd-resign --force` re-signed and reloaded all
     57 with the existing keys (no KSK touched, DS unchanged, NOERROR through a
     validating resolver); `acme-client.conf` installed and `renew-certs.sh`
     reissued 7 of 9 held certificates, so `brgen.no` now carries
     `DNS:radio.brgen.no` and no longer carries playlist; relayd restarted once by
     that script. Verified: `https://radio.brgen.no/up` answers 200,
     `playlist.brgen.no` resolves nowhere, and `health_check --public-only
     --all-ready-apps` reports bsdports.org as its only failure, which is the
     registrar parking already recorded.
     The zone directory was backed up to
     `/var/backups/pub4/nsd-zones-pre-radio-*.tar.gz` first, and relayd.conf and
     acme-client.conf to the same directory.

1065. **trymbot is off vm23 — done 2026-09-12.** The repo retired it on 2026-08-28
     (`spine.yml` 148 -> 145) and production ran it for two more weeks:
     `/etc/relayd.conf` held a `tls keypair` line and a Host match to `<master>`,
     and `/etc/ssl` held `trymbot.brgen.no.{crt,key}` symlinks plus a
     `brgen.no.fullchain.pem.bak-trymbot`. All removed. It had no DNS record and no
     acme SAN, so it had already stopped resolving.
     This is the case `relayd.conf repo-vs-live divergence` warns about, in its
     sharpest form: the repo was MISSING two lines the box was running, so
     installing the repo copy wholesale would have deleted a live host. The two
     files are byte-identical now, and both dropped off `config_drift --remote`.
     Two mentions stay in `spine.yml` and `dup_census.yml`; they are ratchet-fall
     justifications, and deleting them would break the rule that a fall records
     what paid for it.

1066. **A guard for listener-vs-topic drift is worth building and is not free.**
     Four dead event names in `visual_bridge.js` were found by hand on 2026-09-12
     (TODO 1 and 4). The shape of the check is: collect every `publish("ns:topic")`
     in `MASTER/{lib,core,web}/**/*.rb` — 290 of them — and every `ns:topic` token in
     the bridge, keep the tokens whose namespace the bus uses at all (37), and
     require each to prefix-match a published topic, because the bridge tests with
     regexes rather than equality.
     Two things stop that being a five-line test. Comments count as tokens, so the
     very comments explaining a removal read as the removal not having happened —
     strip comments first. And several live names are SSE or DOM events rather than
     bus topics (`council:speech`, `chat:append`, `input:focus`, `runtime:event`),
     so the check needs a named allowlist, and an allowlist nobody curates becomes
     the place dead names hide.

1067. **Four tests in `test_agent.rb` were skipped as "drifted", and were dead.**
     Removed 2026-09-12. They exercised `tool_capable?` and `cache_key_for`, and
     neither method exists anywhere in `lib/` or `core/` — nor did the behaviour
     move: there is no `supports_tools`, no `cache_key`, nothing. So they were not
     drifted pending a port, they asserted against an API that had been deleted,
     while reading as coverage from every angle except the one that counts. Five
     live tests remain in that file. MASTER's skips went 11 -> 6; of what is left,
     `test_cli_boot_e2e` and `test_self_scan` are deliberately env-gated, which is
     a different thing from a skip nobody can lift.

1068. **Radio's visualizer: the code is all here, and nothing is wired.** Archaeology
     done 2026-09-12 against the deleted root `index.html`, 144 revisions.

     The best version is **`ba752d682`** (2026-01-17, "purple/magenta VGA synthwave
     palette"), the last of sixteen revisions carrying all seven visualisers —
     `PixelTunnel`, `InfinityGridViz`, `CymaticWavesViz`, `FractalCascadeViz`,
     `VortexNestViz`, `NeuralWebViz`, `CosmicEmanationViz`, `HypergridSpiralViz` —
     together with the behaviour that was asked for, written exactly this way:

         window.vizMode = 0;                       // the tunnel, by default
         window.vizRenderers = [tunnelRenderer, new InfinityGridViz(ctx), ...];
         // on a new track:
         vizMode = (vizMode + 1) % vizRenderers.length;

     So the original visualiser IS the warp tunnel with the merged orb, it IS
     index 0, and the cycle-per-track already existed. The six others were dropped
     from index.html at `037d14ce0` (2026-01-29) in the orb/tunnel merge.

     Nothing needs recovering from git. All seven classes AND the switching —
     `vizRenderers`, `vizMode`, `vizNames`, `vizPsychedelicModes`, `lastTrackIndex`
     — are already in the tree at `brgen/app/javascript/reference/visualizers_2d_reference.js`,
     61KB, whose own header records the second half of the story: they had also
     lived in `shared/frontend/layouts/visualizer.js`, bound to a `#canvas` no view
     rendered, so they never ran and were compiled dead into brgen and amber until
     `248e23795` deleted that copy and parked this one.

     What radio runs today is `brgen/app/javascript/radio_brgen_tunnel.js` —
     `AudioEngine`, `VisualEngine`, `RadioBrgen`. Its `VisualEngine` has no
     visualiser modes at all, only a `performanceMode` toggle, and `nextTrack()`
     changes the audio without touching the visuals. That is the whole defect: one
     renderer, no cycle, with seven renderers and the cycle sitting unimported
     beside it.

     The work is a port, not a recovery: give the radio canvas the seven renderers,
     restore `vizMode` at 0, and call the cycle from `nextTrack()`. The reference
     file is `// Reference only. Not loaded, not imported, not compiled` and
     `css_coverage_lint.rb:181` depends on it staying that way, so wiring it means
     moving the classes rather than importing that file where it sits.

1060. **`vps_weekly_integrity.sh` has never run.** `etc/crontab.vm23:97` schedules it
     `30 3 * * 0`. Read from vm23 on 2026-09-12, root's live crontab does not carry
     that line and `/usr/local/bin/vps_weekly_integrity.sh` does not exist — this is
     the "1 unscheduled" that `config_drift_gate --remote` reports. A weekly
     integrity check that has never fired reads as green because nothing reports it,
     which is the same shape as the daily.local finding this file already records.
     Installing it and merging the crontab line needs doas on the box: the operator's.

799. **Fixed 2026-09-12.** `config_drift_gate.rb` sets its own
     `Encoding.default_external` with the reason beside it. It is the only file
     OPERATOR.sh installs to /usr/local/bin, and `require_relative` resolves beside
     the installed copy, so one shared six-line file forced a whole
     `/usr/local/bin/lib/` onto the box and an install that could half-succeed. The
     other seven callers run from the checkout and keep `require_relative
     "lib/utf8"`. `installed-targets` clean: 12 named, 14 provided.
800. **bin/ds-records requires root to read signed zones.** Off-box it should skip, not traceback. Guard ZONE_DIR readability.
801. **bin/render_dns.rb add `--help`.**
802. **OPERATOR.sh pin `RUN_PRODUCTION_SEEDS` default 0 in the header.**
803. **Partly fixed 2026-09-12; the alias stays.** `ssh brgen` needs a Host block in
     the operator's own ~/.ssh/config, so making it the repo-wide default fails item
     21's test — a stranger rebuilding from the repo alone has no such alias. What
     was fixed is the disagreement between the files that do not use it: see 806.
804. **Three doors.** START_HERE should say “agents: CLAUDE.md; operators: RUNBOOK.md; first screen: README.md” in one sentence.
805. **RUNBOOK “Always use tmux” then `doas zsh OPENBSD/OPERATOR.sh`.** vps-deploy must *not* be doas. Put that adjacent.
806. **Fixed 2026-09-12, and the real defect was worse.** `bin/deploy-diff.sh`
     defaulted to `dev@46.23.89.226` and now matches config_drift_gate's
     `dev@brgen.no`, which is the form the repo contract names. Underneath that,
     `SSH_HOST` means two different things: login@host in those two files, host alone
     in `lib/ssh_vm23.sh` where `SSH_USER` sits beside it. Exporting one for the other
     yields `dev@dev@brgen.no`. All three files say which they mean now.
     `deploy_all.sh`'s own usage example told the operator to pass
     `VPS_HOST=dev@46.23.89.226`, which the script joins with VPS_USER — so the
     documented invocation could not have worked.
807. **Fixed 2026-09-12.** `deploy_all.sh:13` says `RAILS/<app>/<app>.sh`.
808. **START_HERE post-pull.** Add “do not stash”.
809. **health_check encoding comment duplicated.** One `lib/utf8.rb` require is enough.
810. **bin/check OptionParser without `--help` banner.** Add a banner listing profiles and which gates each runs.

### STUDIO — dilla engine and crate

811. **Stale part headers.** `STUDIO/dilla/dilla.rb` — every `# engine part:` block still says “split out of dilla.rb”. Rewrite to “inline, load order is document order.”
812. **`ENGINE_SOURCES` assigned late.** `:34360` sets it after `wiring_dead_constants` and `parts_report` already close over the name. Move the assignment up with the require.
813. **Wiring comment still names `lib/engine/`.** `:13735–13738`. Gate fails if that directory returns. Point at `DillaSources.all`.
814. **`scan` still probes `dilla.html`.** `:13167`. No such file. Drop the key or fail if a documented face is missing.
815. **`help` is a 170-line dump with no `--explain`.** Add a topic index (`help render`, `help chop`, `help knobs`) and keep the wall behind `help all`.
816. **`council` is dead prose.** `:13186–13193` prints five slogans. Delete it or make it call a real command.
817. **`parts` vs comment line count.** `:14674` says “35,000 lines / 83 markers”. Generate the sentence from `parts_report`.
818. **Test that `dilla parts` lists every marker exactly once.** Do not extract the large parts.
819. **Support ceiling is full.** `STUDIO/gate.rb:120` `DILLA_SUPPORT_CEILING = 56`. Fold before adding; the next file needs a priced raise.
820. **`DillaSources.support` is only `lib/*.rb`.** Either extend `support` to match `DILLA_SUPPORT` or say the corpus is the engine plus `lib/` only.
821. **`engine_sources` header still talks about five corpora.** Cut to “this is the engine; the gate counts support separately.”
822. **Lazy requires vs the ceiling.** Document which of `console_strip`, `tape_hysteresis`, `mix_score`, `verify_fx`, `kit_dig` are command-only so a fold does not pull DSP into boot.
823. **`spectral_audit.rb` is not required by the engine.** Dispatch `dilla spectral` through engine help, or stop counting it as engine support.
824. **`knobs.rb` names `drum_kit.rb`.** That file is now `engine part: drum_kit`. Name the part.
825. **Load-order comment vs practice.** `dilla.rb:231-235` says the order lives in `engine_sources.rb`. It does not; `:83-120` does. Put the order next to the requires, or generate it.
827. **`default_output_dir` vs `.gitignore`.** `.gitignore:22-24` still talks as if every renderer writes beside `dilla.rb`. Align with `OUTPUT_DIR`.
828. **Pin `DILLA_SCRATCH_DIR` in `dilla_helper.rb`.** Scratch fallback is `Dir.tmpdir`; tests that assert `SCRATCH_DIR` under the tree will miss it.
829. **UTF-8 at crate/knob readers.** 37 `File.read` sites in `lib/` inherit locale if a support file loads first. Add `encoding: "UTF-8"` at readers that parse titles.
830. **`seed_providers.rb` URL seed still debug-gated.** `apply_external_url!` warns only if `DILLA_DEBUG`. Always warn, like the USGS path.
831. **`demo_full.rb` swallows harmony failures.** `:44-46` `rescue StandardError; next`. Not an optional gem. Log with the progression name, then skip.
832. **`demo_full.rb` hardcodes `/Users/mac/Music/dilla_sines/demo.mp3`.** Default to `ENV["DEMO_MP3"]` or `OUTPUT_DIR`. Do not touch that directory.
833. **`sine_stream.rb` hardcodes checkout and Music paths.** `Dir.chdir("/Users/mac/Documents/GitHub/pub4/STUDIO/dilla")` breaks any worktree. Chdir to `File.expand_path("..", __dir__)`.
834. **`sine_stream_player.rb` same Music path, no shebang.** Add `#!/usr/bin/env ruby`. Keep the player out of the engine require list.
835. **`bin/crate` is unguarded.** Add `return unless __FILE__ == $PROGRAM_NAME`.
836. **`bin/crate` help is comment-sliced.** A `--help` flag and a real usage string.
837. **`bin/crate` `list` silent rescue.** Missing `crate/` vs empty crate vs corrupt `source.json` are three states. Warn per file; empty dir is the only quiet case.
838. **Three crate layouts, one engine reader.** `bin/crate list` should say “engine will not see these until they are registered as chopped loops.”
839. **Fixed 2026-09-12.** Both test headers cited `lib/engine/render_dilla.rb`, a path
     with no file and no directory — dilla has one 35k-line dilla.rb plus lib/*.rb, and
     never had lib/engine/. `AudioGraph` is `dilla.rb:286`. Found by
     `MASTER/tools/backlog_claims.rb`, which checks every item against its own citation:
     this was the only genuinely stale one in 2245.
840. **Industrial graph is a second spine.** Name in `help` that `industrial`/`techno`/`analog` still bypass `AudioGraph`. Do not merge renderers.
841. **`characterize` is 1180 lines of inspection.** Add one line under “READING THE ENGINE.”
842. **`vocab-check` in `STUDIO/dilla/README.md` Checks.** That README currently only names `rake test`.
843. **`dilla.rb` header: tests and the gate depend on the CLI guard.** Stops the next split from dropping it.
844. **`dilla_live.rb` is a second entry.** Either add `entry:` (guarded) or document it as parse-only like lora.
846. **`librosa_analyze.py` is committed Python.** Ban is on committed scripts. Isolate as an optional tool with a Ruby wrapper that says “Python on PATH, not in this repo’s agent shell.” Paths point at `pub2` / `pub3`. **Unverified** whether `radio-bergen-librosa` is still dispatched.
847. **`generate_tts.rb` assumes repo-root cwd.** Anchor to `File.expand_path("../../../MASTER/README.md", __dir__)`. Backticks for TTS belong behind Open3. Vendor path is `3.4.0` not `3.4.9`.
849. **`ENV_AND_RENDER.md` names `RAILS/shared/app/services/shared/dilla_processor.rb`.** **Unverified** that path still exists.
850. **`data/modes.yml` never mentioned in help.** One line under SYNTHESIS.
851. **Two files, two answers — checked 2026-09-12.** `album_tracks.yml` has a
     reader: `dilla.rb:34552` builds the tracklist from it. `dilla_principles.yml`
     has none — 3.9KB of draft research spec, `status: draft`, read by nothing.
     Wiring it into `groove_engine` would change what dilla generates, so that
     one is a rendered-sound decision and the operator's. The item's own advice
     was right and the answer differs per file.
852. **`reference_sonic.yml` / `dilla_reference.yml`.** Reader is `load_sonic_profiles` at `dilla.rb:4065`. Document it next to the file.
853. **`stems/manifest.json` names missing demux dirs.** `dilla stems` should fail with “manifest names paths not on disk” the way `assets` does.
854. **Tests should export `DILLA_FROZEN=1` in `DILLA_BOOT_ENV`.** A forgotten restore cannot dirty `project/session.json`.
855. **`producer_dna.rb` comment “~60 presets” vs README.** Count from the file in `dilla knobs` / a `dilla dna` listing rather than restating.
856. **`.gitignore` ignores `samples/` wholesale.** Keep audio out; stop ignoring `samples/**/*.provenance.json` and `samples/chopped/loops.json` so a lost crate still has URLs and slugs.
857. **`.gitignore` ignores `*.wav` then comments `loop.wav` as keeper.** There is no `!loop.wav`. Either un-ignore the keeper or stop calling it tracked.
858. **Quality sidecar rule duplicated.** `*.wav.quality.json` at `:8` and `:32`. One pattern. Same for `*_stems/`.
859. **`assets.json` records four loops that are not on disk.** `dilla assets` exits 1; nothing in `rake test` runs it. Add a test that `DillaAssets.verify` is either clean or equal to the known rebuild set.
860. **`DillaAssets.tracked_paths` only top-level drum wavs.** Not `custom/` or `fm/`. Include them or document that they are derived.
861. **`tracked_paths` skips missing files.** Record expected paths even when absent.
862. **`external_kit_cache` identity is a machine fact committed in `assets.json`.** Split host identity from crate hashes, or omit `present` from the tracked file.
863. **`check_inputs!` wiring.** **Unverified** that every dispatch calls it. Probe one non-dilla renderer.
864. **Dug sidecar has no URL.** Old sidecars fail `CrateDig.record!`. A one-time audit that lists sidecars without `url`.
865. **Reproduce command names a gone path.** Provenance `command.argv` files must exist or the sidecar prints `UNREPRODUCIBLE`.
866. **`crate.yml` is the YouTube pile.** `dilla.rb source` help should point at `lib/crate_dig.rb` first, this file second.
867. **`RadioChop::DEFAULT_SOURCE` is `samples/ubrukte_samples.mp3`.** File not in the listing. `chop` with no args should say “default source missing”.
868. **Chop registry JSON parse warns; `registered_loops` also rescues StandardError.** Parse once; drop bad rows with the slug.
869. **`GENERIC_BASENAMES` vs `bin/crate` `source.wav`.** Add a test that `RadioChop` slug from `crate/sources/<slug>/source.wav` uses the directory.
870. **`own/` sidecars vs gitignore.** Confirm with `git check-ignore`. **Unverified.** If ignored, un-ignore `**/*.provenance.json` under samples.
871. **Vocal-fit sidecars without wavs.** `rap-vocal list` should say “sidecar only, audio missing” per row.
872. **`_mislabelled_untitled_flac/meta.json`.** Add one sentence in `rap-vocal list` help so nobody “cleans” it.
873. **`DillaAssets.manifest` JSON rescue returns empty crate.** Non-zero exit when `dilla assets` is the command, not when a test loads the module.

### STUDIO — live, postpro, repligen, lora

874. **Als files have no shebang.** Add `#!/usr/bin/env ruby` so a direct `./live/ambient_pads.als.rb` works off Homebrew. Do not fold live/.
875. **`broadcast.sh` hardcodes Homebrew ruby.** Use `$(command -v ruby)` or `rbenv` like `dig_crate.sh:4`. Add `RBENV_VERSION=3.4.9`.
876. **`broadcast.sh` set names are filenames.** Validate against `live/*.als.rb` before the loop.
877. **`rack.rb` hardcodes `/opt/homebrew/bin/ffmpeg`.** Fallback to PATH when the Homebrew binary is absent is help/UX, not a sound change.
878. **`dig_crate.rb` hardcodes yt-dlp Homebrew path.** `ENV["YTDLP"]` or PATH.
879. **`dig_crate.sh` header** can point at `lib/crate_dig.rb` in one line so the two names stay distinct.
880. **`recall.rb` add `--help`.** Unknown flags currently become a seed.
881. **`recall.rb` `--keep` writes under `dilla/` root.** Say in the warn that the wav is ignored.
882. **`CATALOGUE.md` item 11 vs `broadcast.sh` hard cuts.** Comment that crossfade is catalogue item 11, not this script’s job.
883. **`CATALOGUE.md` counts “forty-two support modules.”** `lib/` has 44 `.rb` files. Generate or drop the number. Same for “401 chord progressions, 74 track presets.”
884. **Als files `require_relative "rack"` with no `$PROGRAM_NAME` guard.** Loading a set in a test would play. A one-line guard would let a dry `--describe` exist without audio. Do not add playback flags that change the set.
885. **`liveset.jsonl` torn-row behaviour.** Copy one sentence to `CATALOGUE.md` intro.
886. **Duplicate frozen-string magic comment.** `postpro.rb:2-3`. Delete one.
887. **Version banner is marketing.** `:5-7`. Present-tense reason or delete. The CLI has `--capabilities`.
888. **No `--help` / `--explain` on postpro.** Flags are a hand-rolled `ARGV.include?` forest. `--help` listing every flag, and refuse non-flag argv when stdin is not a TTY.
890. **README “Running it” omits `--rescue`, `--measure`, `--compare`, `--watch`.**
891. **In-place grade from repligen.** `repligen.rb:760` `--input` and `--output` are the same path. Write a sibling and leave the download (REVERSIBILITY).
892. **`postpro.log` is a committed logger stub.** Gitignore `*.log` under postpro, or stop opening a logfile next to source.
893. **`CONFIG` from missing `master.json`.** Help should say “built-in tables only”.
894. **Camera profiles: 6 JSON files, README says 121 bodies.** Say “six vendor files, 121 bodies.”
895. **Golden tests cover four presets of 57.** Do not hash looks. Add one more family only if a preset class has no representative. **Unverified** whether `house` is in those four.
898. **`--watch` / `--random` / `--auto` undocumented in README running block.**
899. **README Checks should point at `rake postpro:bootstrap`** for a missing libvips host.
900. **Repligen help banner omits `chain` / `chains`.** `:884`. Add them, plus `help`.
901. **`--until` is parsed; `--from` is not.** Help should not imply resume. Document `--until` only.
902. **README running block has no `chain` / `chains`.** Add `repligen.rb chain NAME --dry-run` and “needs `REPLICATE_API_TOKEN` without it”.
903. **Token unreachability is abort-only on run.** `help` / missing token on `generate` should print where the token is read from and that `vocab-check` / `--dry-run` / `chains` need none.
904. **`schema_audit` not in the tool help.** One line: “live schema: `cd STUDIO && rake repligen:schema_audit` (skipped without token).”
905. **Default model vs FINAL vs README.** Options default `flux-2-pro`; `FINAL_MODEL` is `flux-2-max`; README still talks as if six models and `flux-1.1-pro` is the live default. Rewrite to match the table (11 entries).
906. **`HOUSE_POSTPRO` default is untested.** Assert `HOUSE_POSTPRO == "portrait"` and that `--no-postpro` is false, without running postpro.
907. **Chain path does not apply `HOUSE_POSTPRO`.** Same default as generate, or say chains are ungraded.
908. **`relight_portrait.yml` will refuse until schema_audit.** Add those models as `unverified: true` or stop shipping the YAML. **Unverified** they exist in `MODEL_CAPABILITIES`.
909. **`flux2_consistency.yml` untested against real `MODEL_CAPABILITIES`.** Add one test: `Chain.load("flux2_consistency")`.
910. **`structure_ladder.yml` starts on `flux-1.1-pro-ultra`.** Comment in the YAML why Ultra is the establish stage.
911. **`repligen.rb:985` mentions `test/tools/test_chain.rb`.** Actual path is `STUDIO/test/test_tools_chain.rb`.
912. **Prompt-length warning vs README 30–80 words.** **Unverified** a test exists. Add one if missing.
913. **README structured-fields list omits `--subject-distance`, `--key-side`, `--catchlight`, `--skin`, `--selfie-geometry`.**
914. **Gallery / no `--output`.** Help should say outputs without `--output` are URLs only.
915. **`rake test:repligen` should call `vocab_problems` once.** Dedup overlapping checks.
916. **`generate` without token abort before compile,** with the three lookup paths.
917. **No STUDIO test file for lora.** Minimum: `toolkit.sh` SUBJECT_DIR error path, `curate.rb` thresholds, `judge.rb --calibrate` on the seven ragnhild images, `render_config.rb` device profiles — all without training.
918. **`toolkit.sh` error path names a directory that does not exist.** `STUDIO/lora/subjects/ragnhild/lora`. Wrappers live at `STUDIO/lora/ragnhild/lora`.
919. **`run_generate.sh --all` is check, generate, postpro — not train.** Usage should say `--all` needs `weights/$MODEL/*.safetensors`.
920. **README status vs disk.** “8 images in `dataset_1024/`”; disk is `ragnhild/dataset/` with 7 pairs. Captions are full sentences, not the stubs the README describes.
921. **`08` and `11` are gone.** README:145–148. Drop the stale duplicate/filter warning or recurate.
922. **`johann/train.yaml` `folder_path:` is empty.** `render_config.rb` should abort if `folder_path` blank.
923. **`johann/train.yaml` optimizer `adamw8bit` on `device: mps`.** README says mps uses plain adamw. Stamp “generated, do not edit” on `train.yaml`; `render_config.rb` is the source. Do not hand-edit hyperparams.
924. **Committed person photographs.** A test that `johann/dataset` is empty and that `git ls-files` for new `lora/**/*.jpg` fails unless an allowlist. Do not delete existing without the owner.
926. **Guides `.m4a`.** Do not regenerate. **Unverified** if tracked; gitignore if accidental.
927. **`seed_media.ipynb` / `seed_media.yml`.** Find the reader. If Colab-only, say so in README next to the clone-is-public warning.
928. **`run_ai_toolkit.rb` / `colab_session.rb` / `kaggle_session.rb` ARGV at load.** Guard them.
929. **`setup_runpod.sh` SUBJECT_DIR matches real layout.** Copy that path into the toolkit error.
930. **`run_train_replicate.rb` abort sentence on `./lora --train-replicate --help`.**
931. **`judge.rb` thresholds YAML.** A test that the YAML loads and every key is numeric. Do not retune floors.
932. **`curate.rb` `rescue Vips::Error`.** Log and skip the file; do not swallow the whole run.
933. **`postpro_samples.rb` must refuse `dataset/`.** Confirm it only touches `out/`.
934. **`sh -n` in the gate for `lora/_toolkit/*.sh` and `dilla/live/*.sh`.**
935. **`lora/README.md` Norwegian then English.** One voice (README_PROSE). Do not lose the consent/likeness meaning.
936. **FLUX.1-dev vs FLUX 2 base.** Comment at top of `run_train_replicate.rb` that the destination base is a generation choice, not a silent default.

### STUDIO — tests, docs, isolation, micro

937. **A test that loading postpro then repligen in one process fails** would document why `rake test` splits processes.
938. **`isolation.rb` only globs `test_dilla_*.rb`.** Extend `files` or a second task `isolation:tools`.
939. **Quoted-name parser is a spelling test.** All current files use `def test_`. Drop the rewrite or add one quoted example.
940. **Suite rounds scrape Minitest failure lines.** A runner format change silently reports isolation green. Pin against a fixture failure.
941. **`isolation` is not `rake default`.** Add “not part of `rake`” next to the command so a green `rake` is not read as isolation-clean.
942. **`test_studio_gate.rb` still uses `lib/engine/chord_theory.rb` as a first-party path.** Replace with `dilla/lib/theory_runtime.rb`.
943. **Gate test `test_every_declared_entry_point_is_on_disk_and_guarded` skips `entry: nil`.** Explicit assertion that lora’s nil is intentional.
944. **`rake test:dilla` should fail CI when `DILLA_REQUIRE_CRATE=1` and crate is missing.**
945. **`test_mix_metrics_returns_band_levels_when_demo_present` depends on gitignored `demo.wav`.** Fixture: generate a tiny wav in tmp, or stop calling it a unit test.
946. **`test_shipped_demo_has_no_dead_stretch` shells `ffmpeg` with backticks.** Open3; `demo.mp3` is gitignored. Same skip trap.
947. **`eval_in_engine` timeout.** Document `DILLA_PROBE_TIMEOUT` default 90s in `dilla/README.md` Checks.
948. **Bare `rand` sites ratchet.** `test_bare_rand_call_sites_do_not_grow` without routing them through `render_rng`.
949. **`test_dilla_take_write.rb` uses `SCRATCH_DIR` from the engine.** Pin `DILLA_SCRATCH_DIR` to tmp in `dilla_helper.rb`.
950. **`librosa_analyze.py` is untested.** If the Ruby path is the one that matters, say so on the Python file.
951. **`test_audio_graph*.rb` assert filter_complex strings.** Comment that a rename of a label is a behaviour change.
952. **`test_dilla_engine_sources.rb` `assert_equal ".rb"`.** `bin/crate` is Ruby and excluded. Rename the test to `lib_and_entry_are_rb`.
953. **No matching tests for `lib/taste.rb`, `lib/sample_worth.rb`, `lib/kit_dig.rb`, `lib/vocal_chop.rb`, `lib/acapella.rb`.** Add probes that do not render: e.g. `KitDig::ROLES` keys match drum filenames.
954. **`tools_helper.rb` changes `$PROGRAM_NAME`.** A test that `command` is not executed: `vocab_problems` without `SystemExit`.
955. **No test that `dilla.rb` `parts` markers are unique.** Scan `# engine part:` names, `assert_equal names, names.uniq`. **Unverified** if engine-probes already have it.
956. **`studio_helper.rb` comments name `test/dilla/helper.rb`.** Those paths do not exist. Fix to `STUDIO/test/`.
957. **Chord theory skip on missing 13.** Invert: skip only when absent, assert when present.
958. **`which ffmpeg`.** Use `Open3` + `ffmpeg -version`. OpenBSD `which` differs.
959. **`test_dilla_crate_dig.rb` does not open on-disk sidecars.** One test: every readable `samples/**/*.provenance.json` has a `url` or is listed as pre-URL-schema. Worktree without samples skips.
960. **`STUDIO/README.md` has lists, tables, and a code block.** README_PROSE. Redo; move commands into sentences. Same for `dilla/README.md`, `postpro/README.md`, `repligen/README.md`, `lora/README.md`.
961. **`PHOTOGRAPHY.md` “3,947 lines and 228 rules”.** **Unverified** now. Point at `ruby MASTER/tools/agent_context.rb` or drop the census.
962. **`PHOTOGRAPHY.md` “Nothing applies it by default.”** False: `repligen.rb` `HOUSE_POSTPRO`. Update layer “Two things that are not true yet.”
964. **`AMBITION.md` “Today repligen is single-shot.”** False: `chain.rb` + `chains/`. Rewrite §A opener to “spine exists; execution still needs a token.” Mark items 1–2 built.
965. **`dilla/README.md` `sample_loops.rb`.** File does not exist (`engine part: sample_loops`). Fix the restore-verify sentence.
966. **`dilla/README.md` `crate/` restore story.** Present-tense: restore is copy onto `samples/<track>/loop.wav`; `bin/crate` is a third layout.
967. **`repligen/README.md` “six declared models.”** Table has 11.
968. **`ENV_AND_RENDER.md` command aliases “gone.”** Help still lists `loose_pocket`, `industrial`, `techno` as commands. Clarify: aliases gone, genre renderers remain.
969. **Root `STUDIO/README.md` “inert config” examples are postpro history.** One present-tense sentence: “`--vocab-check` is how you see unread keys.”
970. **`PHOTOGRAPHY.md` Studio Q URL has `portrportrait`.** Broken link. Fix or drop.
971. **`gate.rb` `ruby_shebang?` rescues StandardError to false.** Unreadable file is treated as not Ruby and drops out of parse. Log; this is the gate, not an optional gem.
972. **`PREDICTED_FINDINGS` does not include growth.** A unit test that a fake `dilla/lib/engine/x.rb` fails `check_growth`.
973. **`VENDORED` includes `project/`.** A Ruby file dropped there would vanish from parse. Comment is already about worktrees named `tmp`.
974. **`Rakefile` `repligen:schema_audit` parses the table with a regex.** Add a comment test: the regex matches the live file.
975. **`schema_suggest` placeholders 3.0 / 28.** Print `unverified: true` in the suggested snippet so a paste cannot validate a guess.
976. **`task default: %i[gate test]`.** Document as one sentence after the prose rewrite: does not run isolation or schema_audit.
977. **`test:gate` is named, not globbed.** A new `test_studio_*.rb` would not run. Glob or comment the rule next to the filename.
978. **Pin `RBENV_VERSION=3.4.9` in remaining STUDIO shells.** `broadcast.sh`; export in `toolkit.sh`.
979. **Gate does not assert `frozen_string_literal`.** One parse-time test over `source_files`.
980. **`scratch/` gitignore.** `.gitignore` does not name `scratch/`. **Unverified** whether tracked. If tracked logs, gitignore `dilla/scratch/`.
981. **`demo_manifest.tsv` beside gitignored demo audio.** If tracked, it is a manifest without files. Either ignore or have `dilla assets` include it.
982. **Two `capture_with_timeout` implementations.** Extracting would add a support file and raise the ceiling. Leave; comment they must both kill the process group.
983. **`bin/crate` list rescues / `demo_full.rb` harmony `next` / `gate.rb` shebang reader / `seed_providers.rb` debug-gated warn.** Clear non-gem swallows. Log.
984. **`live/rack.rb` rescues.** **Unverified** (ffprobe/json). If they hide a missing bed, warn; if kit-stat probes, skip.
985. **`provenance.rb:101` `mtime rescue nil`.** Warn once per path.
986. **`postpro` CLI `rescue StandardError, NoMethodError` at `:3739`.** Dispatch. Log; do not hide a missing method as a failed grade.
987. **`crate_dig` vs `dig_crate`.** `dilla help` SAMPLE PIPELINE should name both in one sentence.
988. **`ENGINE_PARTS` word in `dilla.rb:14900`.** The constant is gone; markers remain. Say `# engine part:`.
989. **`test/dilla/` in comments.** Global replace to `STUDIO/test/`.
990. **`dilla.html` / `dilla_live.rb` / `sine_stream.rb` are three “hear it” doors.** One sentence in dilla README.
991. **`lib/sample_worth.rb` vs `project/sample_worth.json` vs `Rack::WORTH`.** Comment on the JSON: written by whom. **Unverified** writer.
992. **`lib/taste.rb` vs `DillaKnobs`.** Confirm the suite covers `DillaTaste::DIMENSIONS` against knobs. If not, that is a real hole.
993. **`Chain.parse` should require `description:`** so `chains` cannot print a blank line.
994. **`lora/_toolkit/` underscore vs `subjects/` in the error string.** The drift.
995. **`johann/lora` and `ragnhild/lora` are identical wrappers.** A test that both exec `run_generate.sh`.
996. **`check_hf_flux_access.rb` without token** should fail like replicate, with the HF licence sentence from README.
997. **Worktree empty crate vs main crate.** Document: “copy `samples/` in, or skip is the measurement.”
998. **`dilla.rb` `help` STREAM_DEMO overwrites `demo.wav`.** Comment in help that this is the rolling capture, not a take.
999. **`DILLA_OVERWRITE=1` is the only overwrite.** Help DEFAULT section does not mention it. One line.
1000. **Provenance `reproduce_command` without pins was a known lie.** **Unverified** tests. If missing, assert a sidecar `note` includes at least one non-seed pin when `USER_PINNED_ENV` is non-empty.

### Cross-tree micro-refinements (the rest of 10/10)

1001. **Repo-root `snapshot_MASTER.md` / `snapshot_OPENBSD.md` / `snapshot_RAILS.md` / `snapshot_STUDIO.md`.** TREE.md says nothing else sits at the repo root but CLAUDE/AGENTS/GEMINI, TODO, TREE. Gitignore or move under `.master/` / `MASTER/output/`.
1002. **`STUDIO/dilla/scratch/` logs and a png** next to source. Gitignore `dilla/scratch/`.
1003. **`STUDIO/postpro/postpro.log`.** See 892.
1004. **`MASTER/web/tmp/` and `web/storage/*.sqlite3`.** Confirm gitignored. list_dir showed them.
1005. **`RAILS/tmp/` logs and pids.** Confirm gitignored.
1006. **`RAILS/amber/public/assets` and `brgen/public/assets` carry vendor FIXME.** Generated. PathFilter must keep skipping them; a source-assertion that `public/assets` is not in `SCAN_GLOB`.
1007. **Three `application_controller.js` copies** (amber, brgen, bsdports) plus shared. Confirm they are the Stimulus application instance, not duplicated logic; if duplicated, one shared file.
1008. **`RAILS/*.sh` are reached** (already measured). Micro: each header should name its one caller so a fourth script cannot arrive unnamed.
1009. **`OPENBSD/bin/check-rails` vs `ruby RAILS/gates/runner.rb`.** Two doors on the same registry. One sentence in both READMEs.
1010. **`MASTER/bin/operator gate` vs `OPENBSD/bin/check-full` vs `RAILS/test/run_all.rb`.** Three “everything”. operator gate is the ladder; the others are rungs. START_HERE already says this; OPENBSD/START_HERE still offers check-full as if it were the ladder.
1011. **`growth.studio` vs `DILLA_SUPPORT_CEILING`.** Two budgets on one tree. Document which counts files and which counts lines.
1012. **`STUDIO/gate.rb` requires `OPENBSD/lib/gate_result`.** Fine. PATH_OWNERSHIP OPENBSD `lib/` should name this foreign caller.
1013. **I18n `locale_contract` covers duplicate keys and nb/en parity; not unused keys or interpolation args.** Already named in the awesome-list scan. Still open. This is the RAILS half of 496–497.
1014. **`chrome_i18n_lint` empty_copy is 0; aria is 172.** The next translated aria must lower 172 in the same commit.
1015. **Maps Bergen fallback is the same defect as posts “Anywhere in Bergen”.** One helper: city blank label from `Current.city_record` or a generic `t("geo.anywhere_in_city")`.
1016. **`increment!` on GET is the same shape in marketplace listings and TV videos.** One concern `ViewCounted` with a counter table, or accept the write and stop fragment-caching the count.
1017. **Nullable counters** on listings, tv videos, playlist tracks/plays, takeaway orders. One migration family: default 0, NOT NULL.
1018. **Job uniqueness** is one pattern: `limits_concurrency to: 1, key: "<job>"` on every recurring bulk job. A contract test that every `recurring.yml` class declares it.
1019. **Engine `rake test` from the engine directory** is a lie for maps (zero tests) and thin for the other five. `ENGINES.md` should say which tests live in the host.
1020. **`default:` in vertical ERB** is the hole `i18n_resolution_test` cannot see. A lint: `t(` with `default:` in `app/views` fails, or `raise_on_missing` in test env.
1021. **Static error pages** (brgen, amber, MASTER web) are a third chrome: dark, English, no skip-link, hardcoded host. One generator from the live dialect.
1022. **PWA manifests** are English in all four surfaces (three apps + MASTER). Locale or a shared partial.
1023. **Service workers** name caches after the wrong product (`brgen-` on MASTER) and cache status 0. One SW contract test across the four.
1024. **`--help` missing** is the same defect on OPENBSD bin scripts, dilla help-as-dump, postpro ARGV forest, repligen banner, lora toolkit. Unix voice: one job, usage on `-h`, silence on success.
1025. **Hardcoded `/Users/mac/...` and `/opt/homebrew`.** `sine_stream.rb`, `demo_full.rb`, `broadcast.sh`, `rack.rb`, `dig_crate.rb`. Worktree-safe `__dir__` / `command -v`. Do not touch `~/Music/dilla_sines`.
1026. **Shebang families.** OPENBSD mixes `env zsh`, `bin/sh`, `bin/ksh`, `env sh`. A census test: every committed script’s shebang is one of `{zsh, ksh, sh, ruby}` and `[[` only appears under zsh/ksh.
1027. **Present-tense comments.** `dilla.rb` engine-part headers, `lib/engine/` wiring, `EventsController` “Wire into routes”, brgen layout `data-theme="dark"`, `NO_PUTS` exemption path, `FixLoop` architectures, `Io::Clean` changelog, `mask.js` claims, keep-warm OPTIONAL, core-reclaim litestream, CATALOGUE.md module counts. A comment states the present-tense reason.
1028. **PATH_OWNERSHIP holes.** MASTER: cognition, pressure_engine, law, EXAMPLES, AEGIS, COGNITION, runtime, loop.gif. OPENBSD: data, test, gates, lib, dotfiles, quarantine, domain_watch, githooks. STUDIO has none. `rake lint` should fail on an undeclared top-level dir in MASTER and OPENBSD.
1029. **Completions drift.** `_master` still completes `through`. Generate from `HELP_TOPICS` + `ALIASES`. Add `_operator`.
1030. **Agent contracts vs TREE.md vs START_HERE.** Three maps. TREE.md is the map; START_HERE points; harness files are generated. A stale ASCII map in START_HERE is a second source.
1031. **Maturity scorecard shelf life is 30 days.** Expect 8 of 8 again in a month. Re-read the predicate rather than re-dating the row. (Already in this file; the move is a calendar reminder, not a code change.)
1032. **`scan: intentional` 162 markers, 95 files, nothing checks they still excuse something.** Awesome-list item. Still the highest-leverage detector not built.
1033. **Relayd restart vs relayctl.** Awesome-list item. Still the highest-leverage box change not made. Read the man pages from vm23 first.
1034. **Resource guard sheds per process and measures per box.** Awesome-list item. `ps -o rss= -p` per app into the same history line.
1035. **`login.conf` rails class datasize 4096M on a 1 GB box.** Awesome-list item. Measure steady-state RSS on vm23 before guessing a cap.
1036. **Same-disk snapshots.** `Shared::DatabaseSnapshotJob` + empty litestream restore path. Worth doing as soon as there is somewhere to put them; destination is an operator decision.
1037. **Herb / HTML-aware ERB.** Revisit when Rails adopts it, not before. Cost: nothing yet.
1038. **Face JS without a test, excluding bundles and vendor.** `chat_actions.js`, `cluster_miner.js`, `cognition_ecology.js`, `container_gate.js`, `face_2d_fallback.js`, `face_audio_bridge.js`, `face_blendshape_bridge.js`, `face_brutalist.js`, `face_council_multi.js`, `face_deferred_loader.js`, `face_expression_bridge.js`, `face_loops_music.js`, `face_loops_nudge.js`, `face_micro_interactions.js`, `face_minimal_ui.js`, `face_offscreen_ecology.js`, `face_particles.js`, `face_perf_guards.js`, `face_phosphor_trail.js`, `face_points_gl.js`, `face_semantics.js`, `face_tts_bridge.js`, `face_vision_{a,b,c,d,core}.js`, `mask.js` (delete if dead), `master_events.js`, `mic_capture_processor.js`, `particle_kernel.js`, `particle_worker.js`, `shortcut_sheet.js`, `smart_turn.js`, `sw.js` (has a presence test, not behaviour), `topology_registry.js`, `viewport_inset.js`, `visual_bridge.js`. One contract per file that is in `face_assets.yml`; delete or document each that is not.
1039. **MASTER tools without a test naming the basename.** `example_scan.rb`, `namespace_ratchet.rb`, `readme_take.rb`, `refinements.rb`, `swallowed_errors.rb`, `word_boundary_lint.rb`. Plus those the MASTER pass named: `method_graph.rb`, `method_reach.rb`, `todo.rb`, `dup_census.rb`, `design_baseline.rb`.
1040. **OPENBSD scripts without a behavioural test.** `bin/vps-deploy`, OPERATOR.sh beyond `zsh -n`, dns_zones, domain_alignment, port_inventory, installed_targets, deploy_smoke, integrity_gate skip_reason, nsd-resign, renew-certs, prune-guests, drain-jobs, keep-warm, ptr_openbsd_amsterdam, relayd_prune_keypairs.
1041. **STUDIO files the gate cannot load-probe.** `bin/crate`, `run_ai_toolkit.rb`, `colab_session.rb`, `kaggle_session.rb`, `dilla_live.rb` (parse only), lora wrappers (shell). Guard or document.
1042. **Hardcoded English in views (verified literals, not comments).** amber: Sparks joy, Body type, Public profile, Save profile, Add item, Wear once before deciding, Select item…, Select outfit…, Browse demo →, Talk to MASTER, Style evolution. brgen: Content missing, Community, Anywhere in Bergen, Body, Add photo, Post anonymously, Leave this field empty. dating: Profile photo, Make profile visible, Hide profile. marketplace: Remove from saved, Save listing, Marketplace search, Any query, Partner program, Category, Browse, Picked for the city, Make an offer. playlist: Replace audio file, Upload track, Unknown artist, Create playlist, All sets, New set, Only owners can invite…, Edit #{name}. tv: New channel, Channels will appear…, No channels match…, Live streams, Add a note, Timestamp, Add a comment. takeaway: anon on drivers. maps: kind humanize. shared: Curated offers. Each is one `t()` and one nb sentence.
1043. **Mutating controllers without `rate_limit` (verified no `rate_limit` in the file; not inherited from ApplicationController — only sessions/passwords declare it).** Skip webhooks’ signature path except for a cheap IP limit. Do: blocks, bookmarks, communities, community memberships/bans/mods/wiki, conversation pins, conversations, crossposts, event RSVPs, events, follows, group conversations/members, notifications, partner memberships/programs, presences, push subscriptions, stories, story replies, typing indicators, dating likes/dislikes/matches/profiles/prompts/rewinds/verifications, marketplace addresses/checkouts/favorites/orders/payouts/questions/returns/reviews/saved_searches/stores/variants, playlist collaborations/dilla_sketches/hosted_tracks/imports/likes/listening_parties/listens/party_messages/playlists/sets/tracks, takeaway delivery_drivers/favorites/group_orders/menu_items/orders/restaurants/reviews, tv channels/comments/live_streams/stream_chats/video_notes/view_events, amber affiliate_links/ai/comments/connections/creator_profiles/declutter/follows/items/live_streams/messages/outfits/planned_outfits/posts/wardrobe_items, shared account_settings/csp_reports/notifications/reactions/review_cases/two_factor_setups/web_vitals. Named limits; `rate_limit_naming_test.rb` is the shape.
1044. **`strict_loading` job paths.** `strict_loading_job_paths_test.rb` exists. Add `WardrobeMediaJob` actor/notification path if it reads `item.user`. Add TV show comments/notes and marketplace show questions to `attachment_preload_test.rb`.
1045. **`recurring.yml` vs `rc.d/*_jobs`.** brgen_jobs is the only resident worker. Amber and bsdports recurring entries are fiction until RAM allows. Comment each recurring row with the rc.d that must be up, or stop scheduling them.
1046. **City vanity TLS / relayd restart / openrsync** remain deploy blockers in this file. Micro on the repo side: `vps-deploy` should `rcctl check relayd` after any pass that restarts master (already paid for once).
1047. **`rendered_suite` forty contrast pairs.** Operator colours. Do not retune. Record, don’t restyle. `layout_snapshot` is the reviewable baseline once someone who knows the month of changes accepts it.
1048. **bsdports inbox link is unstyled.** Dead hook is gone; whether that link wears the nav class or the ghost button is a rendered decision.
1049. **Face transitions exceeding `NO_LONG_TRANSITION`.** Held open deliberately. No baseline records them. Leave.
1050. **Seventeen control classes still paint a visible border.** 2026-08-04 decision. Waits for the operator.
1051. **`WORN_TYPE.profiles.map.rhythm_off_max_pct` declared in all seven profiles, read in none.** Instrumented where it matters.
1052. **Browser half of the gates still opt-in.** `PUB4_DEPLOY_BROWSER_GATES=1`. Done when it runs somewhere unattended that is not vm23. `GATE_STRICT_ERRORS=1` is the cheap remaining half.
1053. **dilla ENV switch census.** `knobs.rb` reports 727 knobs, 286 flags. The work is classification (additive / exclusive fork / operational) and deleting the dead ones, not the count. `dilla.rb:4498` comment claiming 156 of 405 is stale too.
1054. **`NO_GOD_CLASS` remaining.** `bergen_demo_seeder.rb` 337 vs 300 — sixteen private methods, one per vertical. `conversation.rb` 28 public methods: IRC / geo rooms / unread are three subjects. `takeaway/order.rb` 26 methods: state machine vs display formatters. Display half to a presenter.
1055. **`probe`/`check` pair.** Two doors, both have real callers. Do not fold `nsaudid` / `dogfood` (decided against). Document the Venn once in START_HERE and OPENBSD/START_HERE.
1056. **Autofix classifies by transform, not yet per rule.** `Scan::Finding` declares `reversibility` and `blast_radius`; nothing under `lib/fix` reads either. A sitting that takes the classification as its subject.
1057. **Findings have no portable form.** SARIF is ~60 lines. Worth doing only if the corpus is ever meant to be read outside pub4. No consumer today.
1058. **Cross-engine references unmeasured.** One: maps reads `Takeaway::Order`. A source gate with that line as its declared exemption. Worth doing while the count is one.
1059. **Fixed 2026-09-12.** `data/operator.yml` is the command list and now carries
     the whole of it: the check family (check-rails, check-openbsd, check-vps,
     check-full), vps-state and tree.sh lived only in START_HERE.md's Golden
     Commands, so the stub that pointed here was the more complete of the two.
     START_HERE's Golden Commands and Source Of Truth sections are pointers now,
     and RECIPES.md is a door rather than a table. `operator_docs.rb` reads the
     yaml and `/orient deploy` prints it, so a recipe added there shows at every
     door.
1060. **Verify the instrument before the next sitting.** Thirty of 22,417 scanner findings were sampled; roughly a quarter were actionable. This list was read against source in four explore passes and one parent census. It will still contain false positives. The first move on any item is to open the line.

---

## Unwired logic, oddities, and typography — opened 2026-09-11 (second pass)

Does not restate 1–1060. Two subjects, measured the same day: event names and
templates that do not meet their other half, and the house type system
(`TYPOGRAPHY` in `rules.yml`, Bringhurst’s measure and hanging punctuation,
Tschichold’s optical margins, Müller-Brockmann’s grid, Wroblewski’s
mobile-first, Rams’s “as little design as possible”) against the SCSS that
actually paints.

Rendered values stay the operator’s. The move is structure: apply a token the
law already names, hang a quote into the gutter, stop a second type system in
an ERB `<style>` block. Sample five lines.

`ScaleLint` sees `line-height:` literals, not `font:` shorthand.
`MEASURE_OPTIMUM` only flags ≥800px, so 660/700/720 slip. `RhythmLint` only
token files. Legal and mailer CSS live in ERB and are invisible to both.
`NO_INLINE_STYLES` currently names `diag.html` and `dilla.html`, not these.

### Unwired — event names, missing templates, dead registrations

1. **Fixed 2026-09-12.** `rule_loop.rb` publishes `pass`, `error`, `fix_applied`,
   `write_error`, `fix_rejected` and `autofix_skipped`. The bridge tested
   `rule_loop:(cycle|clean|converged)` — zero overlap with any of them, in a file
   that matches by regex, so `master:rule_event` had never once fired. The listener
   and the classify rows above it name the published topics now.
2. **Same file `phantom:retry` (`:197`).** Producer is `phantom:recovery` / `phantom:occurrence` / `phantom:halt` (`unwrap_error.rb`). Flinch never runs on a real retry.
3. **Same file `pipeline:start` (`:26`).** Producer is `pipeline:stage_start` / `pipeline:complete`. Thinking tint never keys off a real stage start.
4. **Fixed 2026-09-12.** The rotator started on `council:start`, which exists, and
   could only be stopped by `tribunal:rendered` — of `vote|speech|end` none is a bus
   topic and `council:speech` is an SSE name on the chat stream. So a council that
   passed or vetoed left the face deliberating until something unrelated rendered a
   tribunal. It stops on `council:pass|veto` now, keeping the SSE name and the
   tribunal. Two dead alternates went with it: `council:deliberation` and
   `phantom:retry` name nothing the bus publishes, and `pipeline:start` is not
   `pipeline:stage_start`.
5. **`council:deliberation` in `EventsController::VISITOR_SAFE_PREFIX`.** Nothing publishes it. Use `council:start`.
6. **`tool:used` in the EventsController comment.** Producers are `tool:before` / `tool:after`. Delete the comment or retarget.
7. **`tts:prefetch` in `face_vision_core.js`.** No publisher. Dead classifier arm. The bundle copies the same regex.
8. **`CanvasController#state` publishes `:canvas_state` (symbol).** Nothing subscribes by that name. Cognition’s `**` eats it as telemetry. Named consumer or stop publishing.
9. **`POST /canvas/event` publishes `canvas:mood|mode|gesture|idle|tilt|palette|energy|breath`.** No named subscriber. A third canvas channel beside SSE `mood` and `felt:sense`. Fold or drop the allow-list.
10. **`sse_contract.js` `SSE_EVENTS` lists `felt`, `mood`, `model`, `verdict`, `confidence`, `council:speech` with no `NAMED_HANDLERS`.** POST chat works only because `handleFaceNamedEvent` runs first. `MASTER_SSE.dispatchNamed` alone drops them. Put the handlers in the contract. Assert `SSE_EVENTS ⊆ NAMED_HANDLERS` (the test currently asserts the twelve handlers that exist, not the six listed).
11. **GET EventSource `/chat/message` still lives in `face.runtime.js` after the POST path returns.** Duplicate named-event copy. Delete the GET branch or prove `startChatStream` can be absent.
12. **`MasterChannel` streams `master:council` and `master:status`.** `cable_bridge.rb` broadcasts only `master:events`. The test asserts the empty streams. Broadcast or drop the two names.
13. **`Trace::Metrics` subscribes `llm:response`.** Happy path also publishes `llm:call_complete` from `ruby_llm_sender.rb:143`. A dispatcher-only call never increments Metrics. One topic, or Metrics subscribes both.
14. **`felt:sense` is SSE’d as `felt`.** POST `handleFaceNamedEvent` does not include `felt` (mood/model/verdict only). POST path drops felt entropy.
15. **`content_kind` SSE is handled in face runtime, not in `SSE_EVENTS`.** Contract incomplete the other way.
16. **`ChatService` writes SSE `pressure` from `pressure:updated`.** visual_bridge also maps `pressure:updated` → `master:pressure`. Two pipes. One should own it.
17. **`publish(:canvas_state)` vs `publish("felt:sense")` in the same method.** One spelling.
18. **`cache:hit` subscriber vs two publishers.** `semantic_cache.rb` and `ruby_llm_sender.rb` send different payloads (`key:` vs `model:`). Pin the fields.
19. **`cluster_miner.js` keys `master:rule_event`.** Same dead name as item 1. Clusters never ingest a live pass.
20. **`btw` SSE is fed by `btw:done`, published only from unwired `agent_commands.rb`.** Face `/btw` UI is the dead table’s other end. Wire `btw` into `CommandRegistry.build` or delete the SSE. Same for `client_action` / `media_commands`.
21. **`agent:plan_done` subscribed in `active_plan.rb`, published only from unwired `agent_commands.rb`.** Active plan never pins from `/btw plan`.
22. **`skills:loaded` published, never subscribed.** Wire `/skills` or stop publishing.
23. **EventsController serializes most bus events as anonymous `data:` JSON, named `event:` only for `trace` and `link`.** Named EventSource listeners on `/events/stream` never see `mood`. Pick one encoding.
24. **`MASTER_CONSENSUS_FIXES` defaults off.** No test sets it to `1` and asserts `consensus.approve_fix?`. On-path test or delete the gate.
25. **`MASTER_WATCH=1` defaults off.** Tests pin `"0"`. No test that WatchLoop actually starts.
26. **`web/app/helpers/application_helper.rb` is an empty module.** Delete or put a real helper there.
27. **`pages#radio_bergen` redirects to playlist.** Face still `window.open("/radio_bergen")`. Works via bounce. Point the JS at playlist or keep the bounce with a test.
28. **`ReportsController#create` `format.turbo_stream` and there is no `app/views/reports/`.** Turbo report submit 500s. Add `create.turbo_stream.erb` or drop the format. bsdports `comments#destroy` already inlines the stream for this reason.
29. **`IdentityAssurer` is only called from `trust_and_identity_test.rb`.** No controller or job grants phone/bankid in production. Wire Vipps success into `grant!` or stop claiming identity levels.
30. **`IdentityAssurance` / `ReputationScore` tables exist; no view reads them.** Show on `users/show` or stop writing `TrustScore`.
31. **`Neighborhood` has no route/controller.** Dating and maps print the name. No neighborhood page. Add `maps/neighborhoods#show` or stop seeding Nordnes as if it were a page.
32. **`Mention` has no view.** `Mentionable` writes rows; nothing lists “you were mentioned”. Notification kind or drop the model.
33. **Stimulus `carousel` is lazy-registered.** Amber showcase is a CSS marquee with no `data-controller="carousel"`. Unregister or vendor swiper for a real caller.
34. **`read-more` registered, zero `data-controller="read-more"` in ERB.** `Shared::StimulusFormHelper#read_more` is a helper that emits `.read-more-content`, not the Stimulus controller. Delete the registration and the pin.
35. **`reveal` registered; only `examples.html.erb`.** examples is unmounted. Unregister.
36. **`examples.html.erb` still demonstrates toast/clipboard/reveal/content-loader.** Unmounted. Delete or move under `test/`.
37. **`content-loader` comment says retired; examples.html still has it.** Delete the markup.
38. **`.lazy-loaded` CSS lives in `_coverage_fills.scss`.** Helper is live. Move the two selectors into a real partial so the fill file is not load-bearing.
39. **`.luxury-product-ready` is named in `css_coverage_lint.rb` and has no class in SCSS/ERB/JS.** Drop from the comment list.
40. **`jox-logo` lazy-registers; no `data-controller="jox-logo"` in any view.** CSS exists in amber/bsdports `_jsfiddle_chrome.scss`. Markup never asks for the controller. WIRING_NOTES says they get the animation. Either mount it on the mark or stop registering it.
41. **`data-shell=` still queued in `SURFACES.md`.** Immersive vs browsable is CSS-encoded on `body[class*="vertical-"]`. Naming it in markup is still not built.
42. **Carousel / takeaway / playlist / dating / TV mutations are redirect-only.** Favorite, like, dislike, rewind, comment, collaboration, import: full page reload. Stream the row or keep and test the redirect. Highest: `Tv::CommentsController` has no `tv/comments/` views and does not turbo-append despite `TvCommentCreated`.
43. **`ConversationPinsController` / `GroupMembersController` redirect-only.** Pin does not reorder the rooms rail; adding a member does not append a row. Stream `_rooms_rail`.
44. **`lazy_image_tag` lives in brgen host JS, called from dating engine views.** Engine `rake test` without the host helper fails. Move the helper/controller to shared.
45. **`BSDPORTS_PORTS_TARBALL=1` defaults off.** Test covers the decline path only. Add a fixture tarball test.
46. **`Shared::Reactable` is included on Port/Comment/Advisory while `BSDPORTS_SOCIAL` routes are off.** Don’t include the concern until the flag is on.
47. **Amber layout comment: `_wardrobe_showcase` “used to render here” while `home/index.html.erb` still renders it.** Stale comment, live home.
48. **`etc/rc.d/irc_gateway` has no producer in this repo.** Document as optional or stop OPERATOR from installing it.
49. **`DEPLOY_ASSUME_VPS=1` lets a laptop pretend to be the box.** Refuse unless `/etc/relayd.conf` exists.
50. **`health_check.rb --public-only` never curls `/events/stream`.** A hung SSE is invisible to uptime.
51. **`DILLA_SPEAK` / `DILLA_RAW` default `"0"`.** No RAILS test sets them to `1`. On-path or drop from the env hash.
52. **`demo_full.rb` is never called from `dilla.rb` dispatch.** Dead demo with a hard Music path.
53. **`lib/cli/web_server.rb` is called from `boot/master_boot.rb:56`.** Item 264 of the first pass can close as false.
54. **`DatalogEngine` / `AutonomousRepairer` have callers.** Item 216 of the first pass can close as false.

### Typography — measure, hanging, OpenType (Bringhurst, Tschichold)

The law already names the tokens. `.prose` in `_typography.scss` already hangs
punctuation, hyphenates 6/3/2, orphans 3, and caps `--measure`. Almost no
reading surface wears that class. Legal and mailer invented a second system
in ERB `<style>` blocks that no lint reads.

55. **Legal pages use `legal-prose`, not `.prose`.** `pages/terms.html.erb`, `privacy`, `cookies`. Law `optical_margins.apply_to: [legal]`. Add `.prose` or alias `.legal-prose` to the shared block.
56. **Fixed 2026-09-12.** The inline block is `shared/app/assets/stylesheets/_site_legal.scss`, moved with every value untouched — measured on brgen.no/privacy before and after, `.legal-prose` is 724.397px wide and its h1 is 28.8px/33.12px either way. Snapping those values onto the scales is a separate decision and the operator's.
57. **Same block `.site-legal{max-width:1100px}`.** Hits `MEASURE_OPTIMUM`. Footer is chrome (`do_not_apply_to: chrome`); keep a layout width, stop treating it as a text column.
58. **Same block padding `18px 20px 28px`, gap `10px 18px`.** 10 and 18 are off `scale.space_px`. `--space-*`.
59. **Mailer `_mailer_styles.html.erb` is a third type system.** Dark `#050505` vs fleet light default; Helvetica + Georgia + Arial = three families (`max_font_families: 2`); `letter-spacing: 0.28em / 0.22em / 0.18em / 0.04em` off `letter_spacing_em` (max caps 0.15, no 0.04 on lowercase CTA); line-heights 1.45, 1.35, 1.55, 1.2 off scale; font-size 11/12/13/14/15/16/17/24/34px private ladder; `.mail-shell { max-width: 620px }`; `border-radius: 18px` off `radius_px [0,2,4,8,12,16]`; CTA `letter-spacing: 0.04em` on mixed case; `.mail-deal-price` has no tabular nums; `padding-right` not logical; `linear-gradient` on `.mail-typo-hero`; `color: #050505 !important`. **Move:** one sans + optional Georgia for the lede; measure in `ch`; leading from `--leading-*`; tracking only on the uppercase kickers at `--tracking-wider` (0.08) or `--tracking-widest` (0.14); tabular on price. Do not pick new hex — if the letter stays dark, that is the operator’s; the type scale is not.
60. **`NO_INLINE_STYLES` does not see ERB `<style>`.** Detector names two `.html` files. Legal footer and mailer styles are the real subjects. Extend the language to `.erb` or the rule is a spelling of a filename.
61. **`.reading-column` and `.form-measure` are defined, never used in a view.** `css_coverage_lint.rb` already says “worn by tokens, not yet by every view.” Put them on legal, compose, item forms.
62. **Listing description has `max-width: 66ch` as a spelling of `--measure`.** `_marketplace.scss:74-77`. No hanging, no hyphens, no OpenType. `var(--measure)` plus `.prose`.
63. **Dating bio via `read_more`, no `.prose`.** `_vertical_dating_discover.scss` `.swipe-bio` is colour only. If it reads as a paragraph, `max-width: var(--measure-narrow)`.
64. **`.page-header { max-width: 660px }` in `_minimal.scss:202` fights `_layout_chrome.scss` `var(--measure)`.** Drop the px.
65. **bsdports `header { max-width: 660px }` and `header.page-header > p { max-width: 62ch }`.** Token, not 660/62.
66. **amber `.item-detail { max-width: 700px }`.** If it is copy, `--measure`; if a product frame, leave and mark `scan: intentional`.
67. **playlist `max-width: 720px` on back-link and `.playlist-app`.** Copy → `--measure`; chrome → `--container-max` / `--feed-max`, not 720px.
68. **`.form-wrap { max-width: 480px }` and amber `_item_forms.scss` 480px and `_minimal.scss` `.form` 584px and bsdports `#search` 584px.** `--measure-narrow` (45ch) or `.form-measure`.
69. **`.splash .tagline { max-width: 28em }`.** `--measure-narrow`.
70. **errors.css `main article { width: min(100%, 30em) }`.** `var(--measure)` if tokens reach this sheet.
71. **Print `.prose { max-width: 100% }` in `_zen_shell.scss`.** Drops the measure on the page that most needs it. Keep `--measure` in print; law `print_margins`.
72. **`.prose ul, ol { padding-inline-start: 1.25em }` keeps markers inside the measure.** Bringhurst + `list_marker_hang` + geometry `check_hanging` (principle=tschichold): hang into the gutter. `_posts.scss` 1.5em is worse. Legal `padding-left: 1.1rem` is both physical and inside.
73. **`.prose blockquote` padding + border sit inside the column.** Law `blockquote_border_in_margin`: pull the rule into the gutter.
74. **`--feed-max: 600px` ≈ 45ch at brgen 18px.** Matches `WORN_TYPE.feed` 35–55. Do not widen the feed to 66ch. Marketplace opts out of `--feed-max` for tiles (`do_not_apply_to: marketplace_tile`); the listing *description* still wants 66ch.
75. **amber `_editorial.scss` newsletter `--measure-narrow` is the feed profile.** Do not “fix” to 66ch.
76. **Post show `_feed_post.scss` already `--measure` + hanging + hyphens.** Template for listing, legal, mailer, dating bio.
77. **Wiki `.wiki-page .prose` already `var(--measure)`.** Hang lists still fail (item 72).

### Typography — rhythm, scale, tracking

78. **`--line-height: 20px` absolute on `:root`.** Recorded `scale: ok`. Law `forbid_absolute_px`. Seam: measured screenshot before unitless 1.25 at brgen 18px root. Do not change the number from a terminal.
79. **`font:` shorthand hides off-scale leading from ScaleLint.** `_marketplace.scss` `1.5rem / 1.2`; `_canvas.scss` `10px/1.35`; `face.css` `#chat-log { font: 12px/1.42 }`. Extend the lint to the `font` shorthand, then put those leadings on the allowed steps.
80. **`_canvas.scss` `font: 10px` and playlist `clamp(12px, 3vw, 14px)`.** Below `body_min_px: 16`. Chrome/kicker may stay small; they are not body. Name them as chrome so the lint can skip, or raise to `--text-xs` (0.75rem = 13.5px at brgen — still below 16; the iOS input floor is the 16px case, not labels).
81. **`--text-display: 2.2rem` is a ninth size.** Law `max_font_sizes: 8`. xs/sm/base/lg/title/xl/2xl = 8. Display makes 9. 2.2rem is 35.2px @16, off the 8px grid, off the modular ratios (1.2 / 1.25 / 1.333 / 1.618). Map heroes to `--text-2xl` or accept display as the one sanctioned extra and stop citing 2.2rem as a ladder step — do not invent a tenth.
82. **`.prose h1` and `main#main-content > header h1` are `--text-2xl` (1.75rem) / body 1rem = 1.75.** Law `h1_body_min_ratio: 2.0`. `--text-display` is 2.2× but is the ninth size. Do not pick a new px; decide which token is H1.
83. **`.page-header h1` is `--text-title` (1.25×).** Chrome index titles. If the page is editorial, use the page-title rule.
84. **Auth `h1` `--text-xl` (1.5×); dating `h1` clamp 1.5–1.875rem.** Below 2.0. Immersive/auth may stay; do not restyle as a palette pass.
85. **Fixed 2026-09-12.** `section h2` is deleted and `main#main-content > section >
     h2` is now `main section h2`. The widget rule matched no sidebar markup in any
     of the three apps — its only reach was content. Measured on amber's front page
     before and after: the four wardrobe category headings were 15.75px monospace
     uppercase at 1.26px tracking and are now 15.75px proportional, no transform,
     -0.1575px; the empty state's h2 held its size and lost the uppercase its own
     class never asked for. The new selector is deliberately class-free, so
     `.wardrobe_showcase_label` and `.empty-state-title` still win what they set.
86. **`--tracking-tightest: -0.03em` vs law `heading_tight_min_em: -0.02`.** Stop using tightest on `--weight-heavy` headings (splash h2, marketplace clamp −0.045em). `--tracking-tight` or 0.
87. **Marketplace `letter-spacing: clamp(-0.045em, -0.9vw, -0.02em)`.** Floor past −0.02; clamp hides it from ScaleLint.
88. **face.css `#primer h1` Inter lowercase `letter-spacing: .01em`.** Law: no letterspaced lowercase; scale has no 0.01.
89. **face.css `.04em` and `#zsh-status { letter-spacing:.32em }`.** 0.04 off the scale; 0.32 over `all_caps_max_em: 0.15`. Terminal status may stay; primer h1 must not.
90. **Legal eyebrow `.12em` is on the old five-way kicker set that was collapsed to `0.14`.** Use `--tracking-widest`.
91. **Mailer kickers 0.28 / 0.22 / 0.18em.** Same. `--tracking-widest` (0.14) is the ceiling the tokens already named.
92. **`font-size: 1.17em` / `0.92em` / `0.6em`.** Off modular 1.25. `--text-lg` / `--text-sm` / `--text-xs`.
93. **Two paragraph rhythms.** `_posts.scss` `p { margin: 0 0 var(--space-5) }` vs `_typography` `p + p` `--space-3` vs law `paragraph_margin_em: 1.5`. One.
94. **`max_font_weights: 3` vs `scale.font_weight` [400,500,600,700,800].** Dialect in use is 400/600/800. Stop shipping 500/700 in the lint scale if unused, or stop using them.
95. **Marketplace hero `--font` + `--font-display` + `--font-mono` kicker = 3 families.** Law: 2. Kicker can stay same family, small caps/tracking. Playlist SF Mono is the recorded fifth-face fence — leave.
96. **Mailer three families.** Item 59.
97. **Fixed 2026-09-12 for bsdports; the Caprasimo half is false.** Measured at 390px
    across all three apps: Caprasimo never renders above 700 anywhere, and brgen and
    amber have no synthesised weight at all. bsdports had 11 of 32 weighted elements
    drawn by the rasteriser rather than the type designer — 9 at 600 and 2 at 800
    against a JetBrainsMono that ships Regular and Bold and nothing between, so the
    600 step was as invented as the 800 one and the item named only half of it.
    bsdports' dialect now sets both `--weight-bold` and `--weight-heavy` to 700.
    After: 20 elements at a drawn 400, 12 at a drawn 700, none synthesised.
    design_rules wants three weights 200 apart; a two-cut family cannot offer that,
    and the token file's own principle — the heaviest step is defined by the stack it
    renders in — is what this follows.
98. **Brand logo `12px` / `24px` with stepped `@media (min-width: 768px)` vs `CLAMP_TYPOGRAPHY`.** Marks are not running text; `scan: intentional` if they stay px.

### OpenType, numerals, quotes, hyphens

99. **`.prose` has no `font-feature-settings` / `font-variant-numeric`.** Law `default_features: [kern, liga, clig, onum, pnum]`, `body_numerals: oldstyle-nums`. Set on `.prose`. Tabular + lining on `[data-money]` already correct (`_tokens.scss:244-251`).
100. **No `hyphenate-limit-lines: 2` anywhere.** Chars 6 3 2 exist on `.prose` only. Add the line limit next to them.
101. **No `quotes:` / Norwegian guillemets.** Law `quotes: locale`, `norwegian_guillemets: true`. `html[lang="nb"] .prose { quotes: "«" "»" "‘" "’"; }`. Do not change the glyphs the operator already set in copy; this is the CSS quotes property for generated quotation marks.
102. **No `smcp` / `c2sc` for abbreviations.** Law `contextual_features.abbreviations`. Optional; wire on `.prose abbr` if any exist.
103. **Orphans/widows and `hyphens: auto` only on `.prose` + post show.** Legal, mailer, listing, dating bio, errors, face log miss them.
104. **No `text-align: justify` in source.** Good. Do not add on mobile.
105. **`hanging-punctuation` is Safari-only.** Optical hang still needs hanging quotes/lists in CSS for Chromium (item 72). `geometry_type.rb#check_hanging` already measures marker_x vs text_x (Tschichold). A live legal/wiki page with lists should fail that probe; if it does not run on those surfaces, add them to `geometry_surfaces.yml`.
106. **face.css `"ss01","ss03","cv05","kern"` missing liga/clig/onum/pnum.** Wire law defaults; keep ss03 only if Inter actually loads on the primer.
107. **`.msg-body` liga+kern only.** Same.
108. **Tabular nums missing on `.mail-deal-price`, legal dates, wiki history.** Prices/times on marketplace, tv, bsdports, amber dashboard already have them.
109. **`_fonts.scss` jsDelivr CDN fallback for JetBrains Mono.** Self-hosted `/fonts/` already exists. Drop the CDN `src` so a missing local file does not fetch Nick2bad4u’s GitHub on every first paint (privacy + design: the face is not a third-party type foundry).
110. **Libre Baskerville files sit in `shared/public/fonts/`.** Confirm a `@font-face` still names them. If amber editorial moved off them, they are dead weight; if they load, they are a second serif beside Georgia in the mailer and Caprasimo on amber — count families per surface.

### Motion, flat UI, logical properties, mobile-first

111. **`_search_yep.scss:41` `box-shadow: rgba(0,0,0,0.25) 0 1px 8px`.** Comment says the pen allowlist restored it after a flat-UI pass. Confirm `PEN_ALLOW` still names this file; if the pen retired, this is the one shadow besides the recorded popover arrow. Operator: keep or drop — do not invent a third.
112. **`.search.active { border-radius: 16px }`.** 16 is on `radius_px`. Fine. Prefer `var(--radius-*)`.
113. **`#ccc` border on `#search_suggestions`.** Not a token. `var(--border)`.
114. **`background-color: white` on `.search.focus`.** Not a token. `var(--surface)`.
115. **Vote animated-number `duration-value="900"`.** 900ms > `NO_LONG_TRANSITION` 300ms. JS, not CSS; the rule misses it. Cap at `--transition-normal` (300ms) or mark as a counted animation, not a UI transition.
116. **`NO_LONG_TRANSITION` misses `1.2s` / `.42s`.** Face 1200ms/1800ms already fenced. Extend the detector to seconds so a new 1.2s cannot land in RAILS unnoticed.
117. **Legal/mailer `padding-left` / `padding-right`.** `LOGICAL_PROPERTIES`. Inline-start/end.
118. **Overtaken 2026-09-12.** The conversion pass happened: 18 max-width queries went
     to 1, the `scan: intentional` markers are gone with them, and MOBILE_FIRST now
     finds nothing in RAILS. The one left, `_root.scss:334`, is a bounded band whose
     max is an upper bound on an enhancement — see 1063.
119. **`--text-display` 2.2rem and canvas `clamp(2.5rem, 12vw, 5rem)` on splash h2.** Display type without a sanctioned home was why `--text-display` was added. Splash still bypasses it. One display slot.
120. **Measured 2026-09-12, and it is the operator's.** The three roots are 18px
     (brgen), 16px (amber) and 12px (bsdports), so an absolute 13px is 0.72rem, 0.81rem
     and 1.08rem of its own app — the item is right that on bsdports it outgrows the
     body. `.site-verify` does not render on any front page, so the live cost today is
     zero and the fix is a type change on pages that do. Naming it `--text-xs` makes it
     13.5/12/9px respectively, and 9px is a decision about what bsdports' footer meta
     should look like rather than a bug fix. `_site_legal.scss`'s own header already
     fences this: every one of those numbers is something somebody sees.

### Oddities and gaps the type system makes visible

121. **Three roots, one rem.** amber 16 (18 at ≥1280), brgen 18, bsdports 12. Recorded, not a bug. Any new `ch` measure is true at that root; any new `px` measure is a lie on two of three apps. Prefer `ch` / `--measure` for copy, `px` only for chrome insets already so named.
122. **`--space-4` is 1rem = 12px on bsdports and 18px on brgen.** Why tap/chrome are absolute. A legal `padding: 32px` is honest; a legal `padding: 2rem` is not the same page on three apps. Legal currently mixes both.
123. **Instrument: `RhythmLint` only scans `_tokens.scss` and `_dialect_tokens.scss`.** Legal/mailer/listing spacing never enter. Point it at all stylesheets or at ERB `<style>` blocks, or it will keep saying ok.
124. **Instrument: hanging is a geometry probe, not a stylesheet grep.** Surfaces without lists in `geometry_surfaces.yml` cannot fail `check_hanging`. Add legal, wiki, post show.
125. **Instrument: `css_constitution` type_scale budget counts raw `font-size` literals.** ERB `<style>` is outside that budget. Same hole as 60/123.
126. **`.coverage_fills` is still the box model for Event, Story, moderation.** Token-only geometry, no type. Those pages get flex and gap and body size. If they grow prose (wiki already did the right thing), they must opt into `.prose` rather than another fill.
127. **Face `#primer` Inter + mono HUD + 12px chat log is a fourth dialect.** SURFACES.md already says one-theme black. Type: the primer is the only Inter; the log is the CRT. Do not mix Inter tracking into the log. Item 88 is the leak.
128. **Bringhurst “choose a face for a function.”** Inter/system-ui social, Caprasimo editorial (amber only), JetBrains CRT (face + bsdports + kickers), Georgia mailer lede, Bricolage marketplace display, SF Mono playlist. That is six functions. The law’s max 2 is per *surface*, not per fleet — count on the page the reader is on, not in the repo. Marketplace hero is the surface that currently breaks it (item 95).
129. **Tschichold / hanging quotes.** `hanging-punctuation: first allow-end last` is set; Chromium ignores it. A `text-indent` / negative margin on `q::before` / opening `“` is the cross-browser hang. Only on `.prose`.
130. **Müller-Brockmann 8px / 12-col.** ScaleLint `off_scale_space: 16` is the remaining debt. Do not raise the baseline. Legal/mailer px gaps (10, 18, 6, 26, 34) would add to it the day the lint can see ERB.
131. **Wroblewski mobile-first.** Viewport edges are declared; max-width bands are fenced. New copy columns should not introduce a fourth 584/620/640/660/700/720px “almost a measure.”
132. **Closed 2026-09-12 with the legal cluster.** The second type system was the
     legal/mailer inline `<style>`; it is now `shared/_site_legal.scss`, moved with
     every value untouched. One type system.
133. **Ando / ma.** `--leading-loose` 1.6 is already the quote step. Legal 1.62 and mailer 1.55 invent a half-step of air that reads as unsettled next to 1.5 body (ScaleLint’s own diagnosis). Snap to 1.5 or 1.6.
134. **Uppercase without tracking — the widget leak half is fixed 2026-09-12.** The
     leak onto vertical section titles is closed with item 85: nothing uppercases a
     section heading now. The forward half stands — kickers that are still
     `text-transform: uppercase` need tracking from the token ladder, and the footer
     nav's h2 (15.75px, 0.7875px) is the one place measured so far that does.
135. **Bringhurst on lowercase: do not letterspace.** Primer h1 (item 88), mailer CTA 0.04em (item 59), face `.04em` (item 89).
136. **Oldstyle in body, lining/tabular in tables and prices.** The money hook is lining+tabular. Body never got oldstyle. Inter and system-ui ship onum; JetBrains as a mono should stay lining (code/CRT). `.prose` yes; `.font-mono` no.
137. **`void_target: 0.70` in micro typography.** Unverified whether any surface measures leftover space. If `geometry_type` does not, it is an unread key of the same class as `rhythm_off_max_pct`.
138. **`check_hanging` severity `:soft`.** A list whose markers sit inside the measure will not fail a gate. If hanging is law, it is a fail; if it is advisory, say so next to `list_marker_hang`.

### Remainder — face, verticals, motion, instruments

The first 138 closed the legal/mailer second system, the event-name drift, and the unread OpenType keys. What follows is the rest of that sitting: surfaces the truncated pass still had open, and a few unwired flags that sitting also named.

139. **`#primer h1` names Inter.** `MASTER/web/public/face.css:544`. HUD is `system-ui` + `--font-label` mono — three families on one page (`max_font_families: 2`). Inter is gone from `_fonts_brand.scss`. `var(--font-brand)` or `var(--font)`, not a third named Inter. Tracking `.01em` on that lowercase heading is item 88.
140. **Splash chips `ui-monospace` on a system-ui splash.** `_canvas.scss:28`. Two families, at the cap. Leave if body stays one.
141. **Legal eyebrow `.72rem` + `.12em` + uppercase.** `_site_legal_footer.html.erb:20-21`. Tracking is inside the all-caps band; size ≈11.5px below `body_min_px: 16`. `--text-xs` (chrome meta), `--tracking-widest`. No new size.
142. **`.prose` has `text-wrap: pretty`; headings `balance`.** Listing, legal, mailer inherit neither until they join `.prose` (item 55).
143. **Auth `h1` `--tracking-tighter` is allowed heading tight (−0.02).** `_auth_form.scss:41-46`. `.auth-form-lead` is unspaced — keep it that way; don’t letterspace the lead.
144. **`chat_upload.css:42,48` `transition: … .42s`.** 420ms over the cap. Face 1.2s / 1.8s are the recorded fence (`TODO` layout pass). This file is not that fence. `var(--transition-normal)` (300ms), same easing.
145. **`face.css:566` `ripple 680ms` is an animation.** ScaleLint `duration_ms` is transitions only. Don’t treat it as a transition-budget fix.
146. **Dating `linear-gradient` on buttons.** `_vertical_dating_discover.scss:59` vs FLAT_UI uniform-at-rest. Name the seam; don’t pick a new fill. (One chrome already retires the immersive shell; this gradient goes with it or stays as a recorded exception.)
147. **Splash title `transform: scale(1.02)` at rest.** `_canvas.scss:21`. Depth at rest. Optional: only `:active`. Primer `#primer:active h1 { scale(1.03) }` is the same pattern, already on a gesture.
148. **`LOGICAL_PROPERTIES` only matches `(margin|padding)-(left|right)`.** Misses `left:` / `right:` / `top:` / `bottom:`. `face.css:369-370` mixes `top:` with `inset-inline-start`. New rules: `inset-block-start`.
149. **`_tab_bar.scss:99` `@media (max-width: 639px)` without the `scan: intentional` comment.** Same 639 band as the fenced ones. Mark it or invert to a min-width default. Do not mass-convert the marked bands.
150. **`_nearby_chat_widget.scss:116` `(hover: none), (max-width: 480px)`.** Capability query plus width. Leave hover; don’t treat as a measure rewrite.
151. **`.post_body` `--leading-loose` (1.6) while `.prose` is 1.5.** `_posts.scss:69`. Show uses both classes. One leading.
152. **Maps / marketplace-card uppercase labels.** `_maps.scss:121`, `_marketplace_cards.scss:88`. Pair `--tracking-wide` on the same rule if tracking is missing (`all_caps_min_em: 0.05`).
153. **`.map-hud { max-width: 280px }` and nearby `320px`.** Chrome (`do_not_apply_to: chrome`), not a text measure. Leave.
154. **Messenger `line-height: 1.25` is on scale.** `WORN_TYPE.chat` measure 0. Don’t hang punctuation in bubbles.
155. **Marketplace `.market-hero { max-width: var(--measure) }` then h1 clamp 5.5rem.** `_vertical_marketplace.scss:31-33`. The masthead wraps at ~8–12 characters. Cap kicker/subcopy at `--measure`, not the display word.
156. **Dating profile form already `--measure`.** `_vertical_dating.scss:34-38`. Good. `_vertical_dating_shell.scss:129` `--measure-narrow` on the shell: confirm it isn’t squeezing legal-length copy (the intro/legal links dating hides from the footer).
157. **Takeaway uppercase + `--tracking-wide`.** `_vertical_takeaway.scss:121`. The pair Bringhurst asks for. Leave.
158. **Playlist 720px + `clamp(12px, 3vw, 14px)`.** Don’t retune the playlist mono fence (`SURFACES.md`). Copy columns still want `--measure` (item 67), not 720px.
159. **Amber `--luxury-letter-tight: -0.01em` matches `--tracking-tight`.** `_editorial.scss`, `_items_luxury.scss`. Don’t add a third tracking language. Product titles are headings — OK if not body.
160. **Amber `h1,h2` `--measure-wide` (75ch).** `_layout.scss:22-31`. Fine for titles; body still `--measure`.
161. **Creator bio already `.prose`.** `creator_profiles/show.html.erb:9`. One of the three views that got it right.
162. **Dressing room `max-width: 420px`.** `WORN_TYPE.immersive` measure 0. Don’t force 66ch.
163. **bsdports header h1 `clamp(1.75rem, 5vw, 2.5rem)` vs 12px CRT root.** Don’t raise the root to “fix” the h1/body ratio. Search `font-size: 16px` absolute is the iOS zoom floor — keep.
164. **bsdports tabular-nums on ports (`:501`).** Extend to any remaining version numbers on the same rows.
165. **Face `font: 16px/1.5 system-ui` has no `--measure`.** Overflow-hidden HUD. Chat log `12px/1.42` is off-scale leading and below 16; chat profile may stay dense — still pick an allowed step (`1.4` or `1.5`). `font-size: 14px` literals at `:283,683` map to a `face_root` token already there.
166. **`PEN_ALLOW` still names `_search_yep.scss`.** `gate_autofix.rb:30`. Item 111’s shadow is the pen, not a leak. Don’t spread it. `_jsfiddle_chrome`, `_marketplace_nav_bar`, `_marketplace_animated_logo` are the other three.
167. **`MASTER_INCREMENTAL=1` defaults off.** Confirm `test/` never sets it; if not, add one path or drop the flag.
168. **`MASTER_WEB` defaults `"0"` (`runtime_mode.rb:16`).** Face is production. Test that the Falcon boot sets it, or the CLI/web split is fiction.
169. **`MASTER_SKIP_SELF_TEST=1` defaults off.** No test that self-test is skipped and boot still returns a container.
170. **`dashboard#live` JSON has no fetcher in `face_assets.yml`.** If the dashboard stays (item 152 of the first pass), name the poller; if chrome folds into chat, delete the endpoint.
171. **`InvitesController#show` has no `views/invites/`.** Redirects only. Add a test that no implicit render happens. Same shape: `BlocksController`, `CrosspostsController`, `StoryRepliesController`.
172. **`internal#dilla_publish`.** Unverified STUDIO caller. If dilla never POSTs it, the route is a hole.
173. **`APPLY_PTR=1` defaults off.** `ptr_openbsd_amsterdam.rb`. On-path test: build the POST body, don’t send.
174. **`vps_master_scan.sh` vs `MASTER/bin/operator gate`.** Second scan entry on the box. Fold or point at operator.
175. **`postpro --watch` has no RAILS job.** If `PostproProcessor` is one-shot, `--watch` is a laptop-only door with no test.
176. **ScaleLint still misses `letter-spacing` inside `clamp()`.** Marketplace −0.045em (item 87) is the exhibit. Parse clamp() mins.
177. **`MEASURE_OPTIMUM` at ≥800px never sees 660/700/720/584.** Lower it for text columns, or assert `var(--measure)` on `optical_margins.apply_to` selectors. Don’t flag HUD 280/320.
178. **Don’t raise `hanging_marker_max_inset_px` to absorb `.prose` `1.25em` or legal `1.1rem`.** Hang in CSS (item 72). The geometry probe is Tschichold; the inset is not a ratchet.

---

## Rails 8.1, Hotwire, and stimulus-components — opened 2026-09-11

Measured against `gem "rails", "~> 8.1.2"`, Solid Queue/Cache/Cable 1.4/1.0/3.0, Propshaft, Falcon, and `shared/frontend/stimulus_boot.js`. Horizon items in `apps.horizon.yml` stay ignored. Kamal, Thruster, Inertia, Vite, ViewComponent, Google Places, glow effects, and restoring `timeago` / `content-loader` are out: this fleet deploys through OpenBSD rc.d, paints flat, and already deleted those two controllers with a measurement.

Sources: Rails 8.0 and 8.1 release notes, edgeguides `sign_up_and_settings` and caching, gramantin/awesome-rails, Evil Martians Gemfile of Dreams (2026-04, Rails 8.1), stimulus-components.com (25+ catalog), StimulusReflex morph docs, ar5iv 1711.10399 / 2106.03819 (cold-start ranking). A finding is a hypothesis.

### Already the Rails 8 default — do not re-buy

The tree already has the 8.0 trifecta (Solid Queue, Solid Cache, Solid Cable), Propshaft, session auth with `rate_limit` on passwords/sessions, `bin/ci` via `shared/config/ci.rb`, `assume_ssl` without `force_ssl` (README), and Hotwire broadcasts. The 2026-09-11 awesome-list scan already closed most of gramantin/awesome-rails against this repo. What follows is what 8.1 and the Hotwire catalogs still name that this tree does not use, or uses half.

### Rails 8.1 that would finish jobs and events

1. **Active Job continuations on the long imports.** Rails 8.1 splits a job into steps that resume after a deploy SIGTERM. `AffiliateImportJob`, `PortsImportJob`, `WardrobeMediaJob`, `LinkConverterSyncJob` are the ones a 1 GB box kills mid-pass. `include ActiveJob::Continuable` and `step :page` around the feed cursor. Do not continue a job that must be atomic (payouts, refunds).
2. **`Rails.event.notify` vs `ActivityTrackable` / `EventEmitter`.** 8.1’s structured reporter is the house logger; the city strip is the product. Don’t replace Activity. Do emit `Rails.event.notify("marketplace.order.paid", order_id:)` next to the existing emission so `/health` and deploy smoke can subscribe without parsing JSONL.
3. **Markdown rendering is native in 8.1.** Posts and wiki go through Tiptap / `simple_format`, not Markdown. Leave them. The one fit is bsdports port `COMMENT` / `DESCR` if those arrive as md. Don’t add a second editor.
4. **`rails credentials:fetch` is for Kamal.** Secrets live in `/etc/<app>.env`. Do not introduce `config/master.key`.
5. **`unauthenticated_access_only` from the edge sign-up guide.** Sessions/passwords already `allow_unauthenticated_access`. Add the inverse on `SignUpsController` / `UsersController#new` so a signed-in person cannot hit the form. The guide’s `rate_limit to: 10, within: 3.minutes, only: :create` on sign-up is the same shape as `sessions_actions.rb` — copy it onto user create if missing (rate-limit census already lists many controllers; this one is the guide’s named action).
6. **`allow_browser versions: :modern` is on MASTER web, not the three apps.** Edge Action Controller advanced topics. Soft guests on brgen would 406. Don’t copy blindly; if adopted, serve the existing `406-unsupported-browser.html` and keep dating/marketplace crawlers on a bot allow-list.
7. **Turbo prefetch is off on every Pagy link.** `pagy.rb:17` `data-turbo-prefetch="false"`. The 8.x default is prefetch-on. Turn it on for the eight swiper destinations (already named in the first inventory); keep it off on pager “next” if that was the reason.
8. **`fresh_when` / `stale?`.** Caching guide. Only `bsdports#ports#show` uses it. Add on `posts#show`, `listings#show`, `events#show`, `items#show` (ETag from `updated_at` + `Current.user&.id` so votes don’t 304 a stranger’s button).
9. **Solid Cable is in the Gemfile.** Confirm `config/cable.yml` production adapter is `solid_cable` and not `async` leftover. Falcon + one worker means in-process cable still works; two workers without solid_cable drop broadcasts. One test that production cable.yml names solid_cable.
10. **Do not add Kamal, Thruster, or a Dockerfile.** 8.0’s deploy story is not this box. `vps-deploy` + relayd stays.

### Stimulus-components.com — wire what’s registered, don’t fetch the rest

Catalog checked 2026-09-11. Boot already registers a subset. Dropped with a measurement: `timeago`, `content-loader`, `dialog`, `scroll-to`, `sound`, `speech-recognition`, `hotkey`. Required by `stimulus_components` gate: password-visibility, nested-form, carousel.

11. **`password-visibility` is live on all three `sessions/new` via `password_visibility_field`.** Also put it on `passwords#edit` (the reset form) and `account_settings` password change. The helper’s `aria: { label: "Toggle password visibility" }` is English — `t("auth.toggle_password")`.
12. **`nested-form` is live on amber outfits.** Marketplace listing variants (`Marketplace::Variant` + options) still look like a static fields_for. Same controller, `accepts_nested_attributes_for :variants`. One form.
13. **`checkbox-select-all` is live on `admin/reports`.** Missing on community mod queue, bsdports maintainer port lists, amber declutter review. Same markup as reports.
14. **`auto-submit` is registered and only used in unmounted `examples.html.erb`.** Marketplace facets, TV channel filters, bsdports search, amber `filter_controller` — those still wait for a button or a custom controller. Put `data-controller="auto-submit"` on the GET filter forms (debounce is built in). Don’t put it on POST checkout.
15. **`sortable` is live on amber outfits and playlist tracks.** Dating prompt order and marketplace variant order are the two remaining nested lists. Don’t sortable the feed.
16. **`clipboard` is live (`_copyable`, action bar).** Add on bsdports port `PKGPATH` / `MAKE_ARGS` copy, and playlist embed URL.
17. **`animated-number` is live on post score.** Missing on listing `views_count`, takeaway ETA is `countdown` (keep), amber likes. Don’t animate money.
18. **`popover` is live on the action bar.** Confirm dating overflow and marketplace listing actions use the same `data-controller="popover"` instead of a third menu.
19. **`dropdown` is live on `posts/_post` feed-action-menu.** Reuse on events and stories; don’t add a second menu controller.
20. **`reveal` is registered, only `examples.html.erb`.** Dating “optional details” is a `<details>` already. Unregister reveal or point it at legal footnotes. Don’t keep a boot entry for a demo file.
21. **`read-more` is wired through `StimulusFormHelper#read_more`, not a literal in ERB.** Listing descriptions already call it. Second-pass item 34 overstated the hole. Remaining: dating bio and TV descriptions if they truncate in Ruby.
22. **`carousel` stays lazy, CDN swiper, amber showcase only.** Don’t put it on brgen; media gallery and dating swipe are hand-rolled. Vendor swiper before any second caller (comment in `stimulus_boot.js:82-103` already says so).
23. **`dialog` was pinned, vendored, registered, then dropped — zero ERB.** Native `<dialog>` is the 2024–26 replacement for custom modals (stimulus-components docs, MDN). Dating match overlay, report confirm, takeaway “cancel order”, amber declutter “let go” are the four confirms that should be `<dialog data-controller="dialog">` rather than a new overlay CSS. Restore the pin only with the first of those four views. No box-shadow on the backdrop beyond the recorded popover exception — `::backdrop { background: rgb(from var(--text) r g b / 0.45) }`.
24. **Do not restore `scroll-to`.** Skip-link and `href="#main-content"` already exist. The component’s default smooth-scroll fights `prefers-reduced-motion`.
25. **Do not add `chartjs`.** Amber `_visualization.scss` and `_dashboard.scss` already draw; Chart.js is a third renderer and a colour decision. bsdports is a CRT list, not a dashboard.
26. **Do not add `places-autocomplete`.** It is Google Places. Maps already use OpenFreeMap + `request_location`. A Google script on a Norwegian city app is a third-party and a ToS.
27. **Do not add `glow`.** Mouse-tracing highlight is the opposite of FLAT_UI / FLAT_PIXELS.
28. **Do not add `color-picker` (Pickr) as a webfont/theme.** Amber item colour is a string/token, not a free-sRGB picker. If wardrobe colour becomes a chip, it’s a radio list, not Pickr.
29. **Do not restore `timeago`.** Server `Shared::UiHelper#time_ago` is nb; date-fns was English. The comment in `importmap_baseline.rb:33-41` is the decision.
30. **Do not restore `content-loader`.** Turbo frames with skeleton children are the replacement (`stimulus_boot.js:64-66`).
31. **`sound` / `speech-recognition` / `hotkey` were dropped for no ERB.** Playlist already has a player controller; brgen has `feed-hotkey` and `voice-recorder`. Don’t re-pin the generic ones.
32. **`prefetch` component vs Turbo Drive prefetch.** Prefer native `data-turbo-prefetch` (item 7). Don’t add a second prefetch controller.
33. **`scroll-progress`.** A reading bar on wiki / legal / post show is the one honest use. Off by default; `prefers-reduced-motion: reduce { display: none }`. Optional.
34. **`scroll-reveal` is already `pub4/scroll_reveal`, used on newsletter and amber timeline.** Don’t also register `@stimulus-components/scroll-reveal`.
35. **`character-counter` is `pub4/character_counter`, not the npm package.** The gate lists both. One implementation. Don’t pin the package beside the local controller.
36. **`textarea-autogrow` is pinned twice** (`@stimulus-components/textarea-autogrow` and `stimulus-textarea-autogrow`). Compose uses Tiptap, which grows itself. If no ERB asks for autogrow, drop both pins the way dialog was dropped.

### Turbo and StimulusReflex — one morph story

37. **StimulusReflex in this tree is infinite scroll + vote + notification-read + playlist timestamp comments.** `on_failed_sanity_checks = :warn`. Don’t add page-morph Reflexes for filters: Turbo frames + `auto-submit` (item 14) are the 8.x shape. SR page morphs re-run the controller action (~50ms docs); a frame is cheaper and survives morph.
38. **`VoteReflex` and `votes#create.turbo_stream` both exist.** Two pipes for one arrow. Keep the stream (it has a function-layout test); make the Reflex a no-op wrapper or delete it once the stream is the only client.
39. **`PlaylistTimestampedCommentsReflex` is the one non-scroll Reflex.** If TV video notes should work offline-of-cable, they need a `create.turbo_stream` too (second pass already said comments 500 without a template).
40. **Turbo morph (`turbo:morph`) vs CableReady morphdom.** Both are vendored (`morphdom` pin overrides ga.jspm.io). Stimulus controllers that keep local state (tiptap, media-picker, map) must reconnect after morph — the 2025 `useMorphHandler` pattern. Add a test that `tiptap-editor` still has a ProseMirror after a `broadcasts_refreshes` on the post.
41. **`data-turbo-permanent` on nav / theme toggle** was already proposed. Face primer and the compose draft are the other two permanents. Don’t permanent a cable stream.
42. **Optimistic UI:** `optimistic-send` is registered; votes don’t use it. Wire vote arrows *or* delete the controller (first inventory 513). Dating like/dislike is the second caller if it stays.
43. **Turbo Streams for the remaining redirects** (second pass 42–43) is the completion path, not more Reflexes: favorites, dating like, takeaway order status, playlist collab.
44. **Futurism `futurize` is in the Gemfile, pin removed, zero `data-controller="futurism"`.** Comment points at “FINAL_TODO P0.4”. Either lazy-render the first page of listings/ports with `loading="lazy"` frames (no gem) or put the pin back with one index. Don’t leave the gem as a silent require.

### Completing each app (what the catalogs actually buy)

**brgen.** The models are `done` in `apps.yml`. Fruition is the last 300ms of the round-trip and the last empty state.

45. **Faceted search is BeastMode’s demo and this tree’s LiveSearchable.** Deals still LIKE-search (first inventory 347). One helper, auto-submit (14), FTS when the table exists.
46. **Cold-start feed without an LLM.** ar5iv 1711.10399: social neighbours beat global popularity for new users. Rank `hot` as `follows.posts ∪ city.popular` until the user has five votes. Horizon “AI feed ranking” stays ignored; this is a SQL union.
47. **Match overlay / report / cancel-order as `<dialog>`** (23). The overlay CSS is the dating chrome the one-chrome pass is retiring.
48. **Prefetch the eight nav destinations** (7). Measured win on 1 GB is cache, not CPU, if Solid Cache holds the gzipped first page.
49. **Community wiki already `.prose`.** Legal still doesn’t (second pass 55). Same reading surface.
50. **Inbound ActivityPub stays verified-and-dropped** (`apps.yml` / TODO 2.1). Don’t “complete” federation by storing remote media on this box.

**amber.** Wardrobe is a catalog + outfit editor. pgvector / virtual fitting stay horizon.

51. **Nested variants pattern → wardrobe `Item` photos already media-picker.** Completeness is: sortable already reorders outfits; timeline already scroll-reveals; `luxury-product` is on the card. Missing: declutter bulk checkbox-select-all (13), password on account, dialog on “let go”.
52. **Weather-based suggestions are horizon.** Until then, `planned_outfits` dated for a day is the event planner the horizon list names — it exists. Don’t build a weather API.
53. **Style embeddings are horizon.** Fingerprint/silhouette jobs are the visual similarity the box can run (libvips). UI must not say “similar” (first inventory 471).
54. **Creator profile already `.prose`.** Shop/affiliate disclosure assertion still open from the first inventory.

**bsdports.** A ports browser, not a dashboard.

55. **Search form auto-submit** (14) + FTS in schema (first inventory 478). Completeness is the virtual table committed, not Chart.js.
56. **`fresh_when` already on `ports#show`.** Copy to maintainer show.
57. **Maintainer bulk: checkbox-select-all** if a bulk watch/unwatch exists; otherwise don’t add checkboxes for decoration.
58. **Makefile `+=` / `?=` fixtures** (first inventory 481) are the parser completion. Horizon FreeBSD/NetBSD parsers stay ignored.

### What the papers do not license

59. **Kwai POSO / Deezer cold-start nets are production at their scale.** On one SQLite box the neighbour-union (46) is the portable result. Don’t vendor a two-tower model.
60. **Evil Martians 2026 stack is Vite + Inertia + ViewComponent + Alba.** This tree chose importmaps, ERB, Hotwire, no LAYER_CAKE. Read them for job/continuations and CI, not for a React rewrite.

---

## Completing the four trees — papers, peers, and the rest of the ask — 2026-09-11

Addresses the whole thread, not the last prompt: four-tree 10/10, unwired logic, Bringhurst, Rails completion, Rails 8.0+ / edge guides / awesome-rails, Stimulus / Turbo / StimulusReflex / stimulus-components.com, GitHub, tutorials, ar5iv. Does not restate the 1060, the 178, or the 60 above. Horizon (`apps.horizon.yml`) stays ignored. Rendered values stay the operator’s.

`apps.yml` marks a feature `done` when the model exists. Fruition is the last reader, the last stream, the last ranking that is two-sided.

### brgen — models are done; ranking and round-trips are not

1. **Dating `ranked_for` is one-sided.** `Dating::Profile.ranked_for` (`profile.rb:86-101`) orders recency, prompt count, and a per-viewer shuffle. ar5iv [1401.8042](https://ar5iv.labs.arxiv.org/html/1401.8042) and [1501.06247](https://ar5iv.labs.arxiv.org/html/1501.06247): two-sided matching lifted first-contact replies ~45% vs suitor-only. `looking_for` / gender / orientation sit on the profile and `Matchmaking` never reads them for the deck. Rank candidates the viewer would like *and* who would like the viewer (same filters they set on themselves). SQL, not an LDA.
2. **Mutual-match minting still walks `User.find_by` in a loop.** `Matchmaking#create_mutual_matches` (`matchmaking.rb:29-40`). Set intersection of ids is right; `User.find_by` per id is not. `User.where(id: mutual_ids)` once.
3. **Certifeye-style verification is already `Dating::Verification`.** ar5iv [1303.4155](https://ar5iv.labs.arxiv.org/html/1303.4155): showing a verified age/photo badge reduced concern. The badge exists on the swipe card. Completeness is: the unreviewed queue has a reviewer UI that is not only `verifications#index` for the submitter. Operator-mod, not Facebook.
4. **Do not intervene on who appears by race.** ar5iv [2103.03332](https://ar5iv.labs.arxiv.org/html/2103.03332): those interventions fight both culture and the platform’s goals. Keep radius + looking_for. No new attribute.
5. **Marketplace trust is reviews + Vipps, not a second rating protocol.** Two-sided rating papers are for crowdsourcing effort. Here the seller rating is the mean of `Marketplace::Review`. Completeness: the mean is on the listing *and* the store; a buyer with no completed order cannot review (already gated). Don’t add a game-theoretic score.
6. **Craigslist non-goods half.** `apps.yml` says kinds are done and points at this file. Job/housing/gig forms exist; the index defaults to goods. Completeness is a kind switcher that is a facet (already counted) *and* the empty state when you pick `job` in a city with none — not a fourth marketplace.
7. **marketplace.brgen.no 500s.** Still open under one chrome. Diagnose the exception (log, `/500` with `exception_app`, or a request spec on the marketplace host) before any layout work. Until it serves, layout_snapshot of that host is fiction.
8. **TV live is infrastructure, not an app gap.** `apps.yml` blocker: no MediaMTX, no ffmpeg on vm23. Hide `live_streams/new` behind a flag that is false, or the form is a lie (first inventory 415). Don’t install a media server from this list.
9. **Takeaway courier on the map is the viewer’s own rider only.** Correct (privacy). Completeness: the waiting diner’s order show already has ETA (`countdown`). Stream status changes (pending→out_for_delivery) as turbo, not a public map of every rider.
10. **Feed cold-start** remains the follow-union from the Hotwire section (item 46 there). Mastodon’s local/federated/home timelines are the peer: home = follows, local = city, federated = dropped inbound. Three tabs, three queries, no transformer.
11. **Stories are Snap’s 24h, and `StoryStreak` exists.** Completeness is the ring on the feed, not a new model. If `story-rings` is only `_coverage_fills` geometry, the ring is still a grey box. Token-only is the floor; a horizontal scroller of avatars is the product.
12. **Messenger voice notes exist; link previews exist.** Completeness: edit/unsend on the bubble via turbo stream, not a full reload (second pass redirects). Campfire (basecamp/once-campfire) is the SQLite chat peer — they morph the transcript. Copy the stream, not the Docker.

### amber — capsule from the closet, not a new model

13. **TasteRanker scores garments, not outfits.** ar5iv [1712.02662](https://ar5iv.labs.arxiv.org/html/1712.02662) (Hsiao & Grauman capsule) and [1804.09979](https://ar5iv.labs.arxiv.org/html/1804.09979) (outfit grader): the task is a *subset* of the closet that mix-and-matches. `OutfitGeneration` + `TasteRanker` + dressing-room carousels exist. Completeness: score a candidate *outfit* as the joint of its items’ scores minus a clash term (colour/material already on `Item`). No neural graph. `RecommendOutfitsJob` already has `limits_concurrency`; make the heuristic path the default and the LLM the fallback it already is.
14. **Capsule “do more with less” is KonMari + underused + shopping_list.** Those three are `done`. The paper’s “minimal set, maximal outfits” is `ClosetOrganization` restraint tips. Completeness: the shopping list already says it will not invent global trends. Don’t add a Polyvore scrape.
15. **Complementary “this top with those jeans”** (eBay Fashion-136K, Style2Vec) is `TasteRanker` revealed wear, not a skip-gram. When the owner opens one item, rank other *zones* from the same closet. Dressing room already counter-rotates zones. Wire `items#show` “wears well with” from that ranker, labelled rules not AI.
16. **Zalando’s get-the-look is in-session.** Horizon embeddings. Until pgvector, CRC32 fingerprint is the honest neighbour (apps.yml). Don’t say similar.
17. **Weather is prefilled from Weather Bergen on generate.** Horizon “richer weather agent” is more API. Completeness: if the fetch fails, the form still submits with season chips. Test the fail-open.
18. **Declutter 30d box is the capsule’s deletion half.** Completeness: the hygiene job uniqueness (first inventory 475) and a dialog confirm (Hotwire section 23).

### bsdports — FreshPorts, not a knowledge graph

19. **FreshPorts.org is the peer: one port, one page, changelog, commit, vulnerability.** This tree has Port, SecurityAdvisory, Maintainer, dep tree. Completeness: advisory age on the port show (already a model) and the import job log (`ImportRun`) visible to a maintainer, not only in `/admin` if there is none.
20. **`ports_fts` claimed done, tests skip if the table is missing.** First inventory 478. Fruition is the virtual table in `schema.rb` so `bin/ci` cannot skip the feature `apps.yml` calls done.
21. **Explore assistant is rules + JSON.** Don’t add pgvector intelligence. Rate-limit the JSON action (Hotwire section already said so).
22. **Platforms freebsd/netbsd are seeded inactive.** Horizon parsers. Completeness: the UI must not offer those platforms as if they imported. Hide or disable the chips.

### Rails 8 / SQLite production (37signals, fractaledmind, edge caching)

23. **WAL is already in all three `database.yml`.** Rails 8 IMMEDIATE transactions are adapter defaults (DHH on once-campfire #150). Don’t add a pragma pass.
24. **ONCE `pre-backup` is `sqlite3 file ".backup dest"`.** `OPENBSD/bin/dr-pull` is the off-host copy. Completeness: before dr-pull, checkpoint WAL so the snapshot is consistent (`PRAGMA wal_checkpoint(TRUNCATE)` or `.backup`). That is the Campfire hook, without Docker. One line in `dr-pull` / a pre-hook, operator-priority because it touches the box.
25. **Single writer.** Falcon `FALCON_WORKERS` is 1 on 1 GB. A second worker on SQLite primary is `SQLITE_BUSY`. Gate: production `database.yml` pool × workers = 1 writer to primary, or document that cable/cache/queue files are the extra writers (they are separate files — good).
26. **`busy_timeout` is 5000.** Campfire/Rails 8 retry fairly without holding the GVL. If `/var/log` shows `database is locked` on vm23, raise timeout, don’t add Redis.
27. **Solid Queue in a separate file is the Campfire-on-SQLite fork.** Already. Continuations (Hotwire section 1) are what 8.1 adds on top.

### MASTER — discoverability, not features

28. **The 10/10 line already in this file:** MASTER is done when it does not need to be told how to use MASTER. Completeness is `HELP_TOPICS` + completions generated from the live command table (first inventory 71), and `/review --only scan` as the advertised verb. Don’t add a fourth surface.
29. **Event-name drift** is the second pass (visual_bridge). Completeness of the *face* is those regexes matching `rule_loop:pass`. Don’t start a new bus.
30. **`bin/operator gate --explain` is the ladder.** START_HERE and OPENBSD/START_HERE still offer other “everything” commands. One paragraph each, already named. Do it.

### OPENBSD — the box is the product

31. **SQLite `.backup` before dr-pull** (24). Highest remaining deploy completeness that is not money.
32. **relayctl vs restart** still open in the awesome-list section. Read the man page on the box.
33. **Don’t adopt ONCE/Docker.** The box is OpenBSD, not a container host. Health `/up` already matches ONCE’s minimum; we already have it.

### STUDIO — crate and help, not new engines

34. **repligen chains exist; token does not.** Completeness is CLI honesty (first STUDIO list), not funding Replicate.
35. **dilla `help` topics** (`help render`, `help knobs`) still the way a stranger finishes the engine without a 170-line dump.
36. **Don’t change a rendered default.** Capsule/outfit papers do not apply to dilla.

### Stimulus / Turbo leftovers the catalogs still name

37. **`password_visibility_field` English aria** (Hotwire 11) — still the one i18n hole in a helper that is otherwise live.
38. **`auto-submit` on GET filters** (Hotwire 14) is the GoRails/Chris Oliver bulk+filter demo applied here. Marketplace facets and bsdports search are the two that would feel finished.
39. **Infinite-scroll Reflexes are the SR surface.** Don’t add BeastMode as a gem; LiveSearchable + auto-submit + existing `*InfiniteScrollReflex` is BeastMode. Completeness: every index that paginates has a reflex *or* a frame; maps places does (first inventory 432 duplication).
40. **Turbo 8 morph + `broadcasts_refreshes`.** Posts/items already broadcast. Test tiptap survives morph (Hotwire 40). That test is the completion, not a new morph library (TurboBoost Streams / Idiomorph — don’t add a third morpher; morphdom is already pinned).

### Tutorials worth stealing a *shape* from, not a stack

41. **Edge guide sign-up + `rate_limit` + `unauthenticated_access_only`.** Hotwire section 5. Still the cheapest auth completeness.
42. **GoRails “bulk operations” = checkbox-select-all** on declutter and mod queue (Hotwire 13).
43. **Hotwire handbook: frame for the thing that changes.** Dating like, listing favorite, port watch — streams or frames, not SR page morphs.
44. **Fractaled Mind / Campfire-on-SQLite load test.** If we ever need a number, `bin/ci` plus a local siege of `/up` and `/` is enough. Don’t import their Redis-era Campfire.

### What this sitting will not open

45. **Solidus, pgvector, MediaMTX, inbound ActivityPub storage, creator monetization, premium dating, donations.** Blockers are Postgres, RAM, ffmpeg, money. Named in `apps.yml`. Leave.
46. **A fourth JS framework.** Importmaps + Stimulus + Turbo + the remaining SR scrolls. Evil Martians and Inertia stay on the shelf.
47. **A neural outfit model, a two-tower feed, Chart.js, Google Places, glow.** Papers and catalogs that need a GPU, a ToS, or a shadow.

---

## Books — what can be law, what must stay the operator’s — 2026-09-11

Assessed against MASTER `beauty:` / `TYPOGRAPHY` / `RAMS_CHECKLIST` / `markdown_style`, RAILS tokens and ScaleLint, and — for sound, mixing, and J Dilla — **STUDIO/dilla only** (`dilla_principles.yml` still `status: draft`, `groove_engine.rb`, `mix_score.rb`, `dilla_reference.yml`, `test_dilla_groove_timing.rb`). Face visemes and postpro headroom are not this sitting. Codify means a token, a detector, or a test. It does not mean a new colour, a new typeface, a new swing default, or a NURBS façade.

A finding is a hypothesis. Sample the file the book would touch.

### Already in the constitution (do not re-import as features)

Bringhurst *Elements of Typographic Style* — measure 45–75ch, hanging punctuation, OpenType, tracking on caps only. Tschichold *The New Typography* — hang lists, optical not geometric edge (`geometry_type#check_hanging`). Müller-Brockmann *Grid Systems* — 8px rhythm, 12-col. Rams ten principles — `RAMS_CHECKLIST`. Ando — `markdown_style` and ma. Wroblewski *Mobile First* — `min-width` bands. Le Corbusier Modulor — `geometry_type` principle=modulor. EBU R128 / Katz *Mastering Audio* — `dilla_reference.yml` LUFS and true-peak windows. Charnas *Dilla Time* (the time-feel, not the biography) — `dilla_principles.yml` independent clocks, phrase-level drift, no fixed swing percentage; `groove_engine` and `test_dilla_groove_timing.rb` already distinguish straight (≤50) from swung.

### Graphic design — codify the rest of the page, not a new look

1. **Hochuli *Detail in Typography*.** Micro already named (`hyphenate-limit-lines: 2`, oldstyle on `.prose`). Completeness is applying `.prose` to legal/mailer (second pass 55–59), not a new YAML block.
2. **Butterick *Practical Typography*.** Practical web rules overlap Bringhurst and are already the `TYPOGRAPHY` config. One extra that is not yet a detector: “one space after a period.” A lint on `  ` after `.` in `nb.yml`/`en.yml` prose values. Don’t run it on code.
3. **Ellen Lupton *Thinking with Type*.** Alignment as a system: one ragged edge per column. Detector: a `.prose` / `.legal-prose` block that is `text-align: center` for body (kickers may stay). Centered running text is the defect; centered display type is not.
4. **Josef Müller-Brockmann / Armin Hofmann *Graphic Design Manual*.** Contrast of size is `h1_body_min_ratio: 2.0` (second pass 82 — page titles are 1.75×). Completeness: decide which token is H1. Contrast of weight is 400/600/800 with 200 between steps — already. Don’t add 500/700.
5. **Jan Tschichold *Asymmetric Typography*.** Body not centered, rules as structure not ornament. `NO_ASCII_DECORATION` covers the ornament. A source gate: `text-align: center` on `p` inside main. Leave splash/hero.
6. **Itten *The Art of Color*.** Seven contrasts. **Do not pick hues.** The only codifiable slice: count distinct non-token hexes in a stylesheet (ScaleLint’s cousin). Magic colour is already `MAGIC_COLOR` / tokens. Don’t implement simultaneous contrast as a palette pass.
7. **Meggs *History of Graphic Design* / Hollis.** History, not a detector. Skip.
8. **Tufte *The Visual Display of Quantitative Information*.** Data-ink. Amber charts are CSS `--share` bars, no Chart.js — already Tufte. A test that `_histogram` / `_figure` contain no `<canvas>` and no box-shadow. Chartjunk is the glow/3D the law already forbids.
9. **Vignelli *The Vignelli Canon*.** Few faces, grid, no decoration. `max_font_families: 2` per surface. Marketplace hero still breaks it (second pass 95). Completeness: kicker stays the body family.
10. **Rand *Thoughts on Design* / *Don’t Make Me Think* (Krug).** Honesty of state is Rams `honest` and `COMPLETION_THEATER`. Empty/loading/error is `RAMS_CHECKLIST.thorough`. Already gated. Don’t add a second checklist.
11. **Gestalt (proximity, similarity) via Lupton *New Basics*.** Detector: two adjacent interactive controls whose hit boxes overlap (tap 44 already). Similarity: one `btn` language — zen buttons vs `btn--primary` is the one-chrome pass, already open.

### Architecture — haptic and parameters, not blobs

12. **Pallasmaa *The Eyes of the Skin*.** Against ocularcentrism: tap, focus, motion, sound, skip-link. Already: `--tap-min` 44, skip-link, `prefers-reduced-motion`, `haptics` controller, `battery-aware`. Codify: `haptics` on dating like/dislike and takeaway “placed” if the controller is mounted and the view never fires it. Don’t add scent or fake material textures. Don’t add parallax as “depth of field” (FLAT_PIXELS).
13. **Zumthor *Atmospheres*.** Material honesty: a token is a material; a gradient pretending to be light is not (dating button gradient, Hotwire leftover 146). Document or retire with the immersive chrome. Don’t invent a stone filter.
14. **Alexander *A Pattern Language*.** Named patterns. `SURFACES.md` dialects and `LAYOUT.md` chrome *are* the pattern language. Completeness: `data-shell=` still queued (second pass 41). One attribute, two values (browsable / immersive), CSS already exists.
15. **Kahn served/servant.** Chrome vs content column. One-chrome pass. Don’t restate.
16. **Le Corbusier *Modulor*.** Already `principle=modulor` on type ratio. Soft fail. If H1 stays 1.75×, either lower the ratio in law (needs a deletion elsewhere) or raise the title token — operator’s call on the number.
17. **Venturi *Complexity and Contradiction*.** “Less is a bore” fights Ando/Rams/FLAT_UI. **Do not codify.**

### Parametric architecture — the heuristic that fits, the style that does not

Schumacher *Autopoiesis* / Parametricist Manifesto: *avoid* right angles, repetition, rigid primitives; *prefer* NURBS, blobs, continuous differentiation. That style contradicts this tree’s CRT-flat zeros, 8px grid, and Ando planes. **Do not import the look.**

The *method* is already the design system:

18. **“Script associations between parameters.”** `design_tokens.yml` → `_dialect_tokens.scss` → `generate_face_root_css.rb`. A new px in a vertical sheet that is not a token is an uncorrelated subsystem — ScaleLint. Completeness: ERB `<style>` (legal/mailer) is the uncorrelated island. Point the lint there.
19. **“Differentiate gradually, correlate systematically.”** `clamp()` on type and `--page-gutter`. `CLAMP_TYPOGRAPHY` already. Splash `clamp(2.5rem, 12vw, 5rem)` bypasses `--text-display` (second pass 119). Correlate or drop.
20. **“Nothing remains pure; every subsystem inflects another.”** Shared `--z-*`, `--tap-min`, `--chrome-inset` across MASTER face and RAILS. Face still has 13 of 87 tokens in common (one chrome). Completeness is the chrome pass, not NURBS.
21. **Negative heuristic we keep from Modernism, not Parametricism:** repetition of the *grid* is the point. Schumacher’s “avoid repetition” would fail every list row. Don’t add a detector for “too rectilinear.”
22. **Frazer *An Evolutionary Architecture* / Burry *Scripting Cultures*.** Generate from constraints. Gates + ratchets + `FixLoop` are that. Don’t add a genetic façade generator.
23. **Grasshopper analog.** Tokens are the sliders. A “param” that exists in YAML and is unread is `data_reach` unnamed — already the inert-config class.

### Typography books beyond Bringhurst (implementation, not restatement)

24. **Bringhurst ch. 8 (shaping the page) / ch. 10 (appendices, character set).** En-dash for ranges is a rule (`--` in running nb/en). Completeness: a locale lint for `2010-2014` that wants `2010–2014` in prose YAML, not in ISO dates or pkgpaths.
25. **Hochuli: hyphenate-limit-lines.** Named in law, missing in CSS (second pass 100). One declaration on `.prose`.
26. **Norwegian quotes.** Bringhurst + law `norwegian_guillemets`. CSS `quotes:` on `html[lang="nb"] .prose` (second pass 101). Don’t rewrite copy.
27. **Kane / Felici.** Software manuals. Skip; Butterick covers the web case.

### STUDIO/dilla — sound design, mixing, and J Dilla (this tree only)

Chion’s visemes and postpro headroom were the wrong tree. Katz, Izhaki, Farnell, Sonnenschein, Snoman, Huber, and Charnas *Dilla Time* land on `STUDIO/dilla`. Never change a rendered-sound default. `dilla_principles.yml` names Charnas as primary bibliography and has **no Ruby reader** (grep hits only the file). That is inert law until `groove_engine` or a probe loads it.

28. **Charnas *Dilla Time* — the time-feel, not the life.** Straight and swing at once, per part. `groove_engine.rules` already say independent clocks and no fixed swing%. Status is `draft`. Promote to `active` the same commit that makes `DillaSources` or `groove_engine.rb` `YAML.safe_load` the file. One test: on a two-bar groove, kick and hat offsets are not identical on every hit. `test_dilla_groove_timing.rb` already proves `swing_role_offset_ms` is per-role; it does not yet load the YAML.
29. **Phrase-level drift, not random jitter.** Principle `Favor phrase-level drift over random jitter`. Detector already: `test_bare_rand_call_sites_do_not_grow`. Don’t add a hit-level noise source. Don’t retune `SWING`.
30. **Single `SWING=` is the fallback, not the design.** Document in `dilla help knobs` that per-role offset is the Charnas move. Keep the knob. Changing its default is a rendered-sound change.
31. **Silence is musical material / drums.ghost_notes.** Don’t auto-fill rests with hats. A probe that a pattern rest stays a rest — only if missing. Ghost notes are a priority in `drums:`; if the engine already writes them, the YAML is documentation; if not, don’t add them to a keeper take.
32. **`remove_elements` / `simplify` twice in `generation_pipeline`.** That is COLLAPSE_BEFORE_ADDING for notes. Don’t add a density ceiling that strips a rendered default. Optional: a dry `dilla characterize` line that reports note-count per bar, no rewrite.
33. **Sonnenschein / Izhaki — bands, not a new EQ.** `mix_score.rb` `REFERENCE` is measured from demo29/demo30 (kick_vs_mid, sub_vs_mid, cymbal_crest, tilt, LRA). Completeness: a stacked-leads fixture fails `spectral_audit` / MixScore; if it doesn’t, the audit is a comment. Leave the ranges. **Do not retune.**
34. **Katz / EBU R128.** `dilla_reference.yml` `true_peak_max_dbtp: -1.0`, LUFS −20.5..−12.5. `MixScore::REFERENCE[:lufs]` is −18..−15. Two windows. Completeness: one source, the loss-gate test already pins reference ↔ quality. Don’t widen either to absorb a hot take.
35. **`mixing.avoid: over_limiting, excessive_brightness, sterile_perfection` vs `anti_patterns: maximize_loudness, overcompress`.** Same rule twice in one file. Fold. `MixScore` LRA below 3 is “flat” — that is sterile_perfection as a number. Keep the number; delete the duplicate prose.
36. **Farnell *Designing Sound*.** Procedural path is `analog_synth.rb` / `devices.rb`. Don’t add a third synth. Sampling path is `sampling_engine.operations` (chop, resample, pitch, filter, reverse_tail, truncate, layer) — RadioChop / sample_flip already. Completeness: `dilla help chop` names those operations in that order, or the YAML is unread.
37. **Snoman / form.** `composition_engine.rb` + `test_dilla_form_map.rb`. `arrangement.patterns: introduce_small_changes, remove_elements, filter_transitions`. Don’t retune drops. Completeness: form-map test still runs under suite load (three probes were timing out — STUDIO “not worth chasing”).
38. **Huber — signal chain as data.** Provenance sidecars. Completeness: `reproduce_command` includes pins when `USER_PINNED_ENV` is set (STUDIO 1000). No new bus processor.
39. **`critic.scorecard` is five zeros and `acceptance: groove >= 0.95`.** Nothing in `lib/` reads it. Either `characterize` / council prints those five, or delete the block. A scorecard nobody scores is the inert-config defect.
40. **`anti_patterns: copy_reference_track`.** The engine must not ingest a Dilla record. A test that `TRACK_SAMPLE_LOOPS` / crate paths do not match a denylist of catalog titles is enough. Don’t put audio in the repo to prove it.
41. **Do not implement the biography.** Camp Amp, SP-1200, Donuts, Questlove interviews as narrative. `identity:` and `bibliography.primary` stay. No sample of a Dilla record. Chion *Audio-Vision* (mouth-sync) is MASTER face visemes — out of this list. Owsinski headroom on stills is postpro — out of this list.

### What these books must not become

42. **A Parametricist CSS** (splines, blobs, no right angles). Fights FLAT_UI, the 8px grid, and the CRT dialects.
43. **An Itten palette generator.** Operator eye.
44. **A global swing retune “because Charnas.”** The feel is per-role offsets that already exist. Changing `SWING` default is a rendered-sound change.
45. **Pallasmaa as perfume, video, or WebGL fog.** Haptics and reduced-motion only.
46. **A second type scale from Hofmann exercises.** One scale in `_tokens.scss`.
47. **Importing a book as unread YAML.** `dilla_principles.yml` is the cautionary example, and the cost is now measured: 3.9KB of draft spec, no reader, and eight separate backlog entries asking whether to load or delete it before anyone checked. If a new file is added, it needs a reader the same day — `test_dilla_groove_timing` or ScaleLint — or it is inert law that also breeds inert backlog.

---

## Agentic coding, agent OS, Rails tests, layout refine — 2026-09-11

GitHub (sifted-awesome-ai-agents 2026-09-11, best-of-Agent-Harnesses, ANOLISA, agent-swarm, SWE-agent lineage) and ar5iv (APEX–SWE 2601.08806, SWE-Search 2410.20285, SWE-agent ACI). Rails: DHH’s 359→10 system tests, Rails 8.1 generators, Cuprite, capybara-screenshot-diff, visual_contract already in this tree.

MASTER already is an agent OS: constitution, scan/fix, worktrees, taint, `OutputFilter`, `ReadFile` truncation, `QuotaGate`. RAILS already has layout JSON snapshots, visual_contract pixel_diff + console_errors + axe, system-test generators off. Steal *interfaces*, not Python runtimes or SaaS Percy.

A finding is a hypothesis.

### MASTER — harness, not a new kernel

1. **APEX–SWE (ar5iv 2601.08806): epistemic discipline beats raw coding.** Pass@1 on production tasks is ~25%. The paper’s driver is “distinguish assumptions from verified facts, and resolve uncertainty before acting.” That is this repo’s “verify the instrument.” Completeness: a `Scan::Finding` field `status: hypothesis | measured` (scan findings start hypothesis; a test or `--explain` that ran is measured). Don’t add a second slogan.
2. **Observability tasks, not just patches.** APEX–SWE’s second half is debug-from-logs. `/dmesg` and `Trace::Dmesg` exist; ChatController#dmesg is a hole (first inventory). Completeness: `/review --only scan MASTER/runtime/*.jsonl` (or the last N Swallow lines) with a fixture log that must flag a known bus-name mismatch. That is the observability bench for this tree.
3. **Harness > model.** best-of-Agent-Harnesses / SWE-bench Pro: swapping the harness moved pass@1 more than swapping the model. START_HERE should say the product is the harness (`soul.yml` + tools + `OutputFilter`), not the default_model. One sentence.
4. **Agent-computer interface (SWE-agent, Yang et al.).** Tools that return walls of text waste the window. `Io::ReadFile` already windows lines; `OutputFilter` already compresses diffs. Completeness: JSON tool results (WebSearch, GitContext, scan JSON) go through the same filter — `record_saved` already exists. Grep `Result.ok(` in `lib/io/` for payloads that skip it.
5. **Span context, not whole files (SWE-Search 2410.20285).** File context as class/method spans with ids. `Io::SymbolLookup` exists and is untested (first inventory 51). Completeness: `/review` of a method takes the method body, not the 400-line file. Don’t build MCTS around it.
6. **Don’t import MCTS / debate-of-three for FixLoop.** SWE-Search’s Value Agent is the council. Fifteen-pass FixLoop is enough. A discriminator debate is a third council.
7. **Token-less / Headroom compression.** ANOLISA and Headroom (71k) compress tool output before the model. `research_thresholds.yml prompt_compression_ratio: 20` is unread-or-narrow. Wire it to `OutputFilter` for HTML/JSON, or delete the key. Don’t vendor a Python compressor.
8. **Checkpoint / rollback of the working tree per fix pass.** SWE-Search keeps a git-like commit tree of states. `FixLoop` writes in place. Completeness: each autofix pass is a path-scoped commit on the worktree (`git commit -- path`) so `/fix` can `reset` one pass. Refuse on main (already worktree law).
9. **Schema-validated agent results.** agent-swarm: JSON schema on worker output. Council/scan JSON already has a shape. Completeness: `Scan::Finding` schema in a test, not a new protobuf. Schema retries do not consume the agent budget (this TUI already says that).
10. **Local cheap router.** use-agent-os Pilot Router: classify, send to cheapest capable model. `QuotaGate` + `providers.yml` exist. Completeness: `/scan` never calls a frontier model (`MASTER_SCAN_DETERMINISTIC`). Test that. Council stays the expensive path.
11. **Do not adopt Docker worker fleets (OpenSandbox, agent-swarm containers, Orca ADE).** Production is one OpenBSD box; isolation is `operator worktree`. A Linux sandbox is a third runtime.
12. **Do not become Hermes-as-OS.** Hermes RFC: process table of agents, cron, IPC. `FixLoop` / `WatchLoop` / `StandingOrders` are enough loops. A process table of subagents is the TUI’s job, not MASTER’s.
13. **CaMeL taint is already `lib/ground/taint.rb`.** Completeness: WebFetch/WebSearch output is `Tainted` before it reaches a write tool. A test that a tainted URL cannot reach `AstEdit`.
14. **ScreenAgent / computer-use.** Out. The face is not a VLM driver; CDP belongs to RAILS gates.
15. **Skills as a filesystem (ANOLISA SkillFS).** `lib/cli/skills.rb` vs `data/patterns.yml` (first inventory 265). One list, index first, body on demand — “map, not encyclopedia.” Don’t dump every skill into the system prompt.

### RAILS testing — few smokes, geometry over pixels

16. **DHH / Rails 8.1: generators no longer emit system tests.** This tree already `config.generators.system_tests = nil` on brgen and bsdports. Amber: confirm the same line. Keep the handful that exist (`public_navigation`, `expanding_tabs`). Do not grow a 359-test browser suite. Integration tests for HTTP; gates for chrome.
17. **Cuprite vs Selenium.** Guides and Evil Martians recommend Cuprite (Ferrum/CDP, no chromedriver). MASTER already uses Ferrum. RAILS Gemfiles still `selenium-webdriver`. Completeness: one driver family. Either Cuprite in `application_system_test_case.rb` or keep Selenium and stop implying CDP and Selenium are the same stack. Don’t run both.
18. **Console logs in system tests.** visual_contract already records `console_errors`. System tests do not. If a smoke stays, fail on `page.driver.browser.logs` / Cuprite logger — same field as the gate.
19. **Do not add `capybara-screenshot-diff` or Percy/Chromatic/Playwright.** visual_contract already has `pixel_diff_count` / `pixel_diff_ratio` / `pixel_diff_image` (ChunkyPNG). A second baseline set is a second source. layout_snapshot JSON is the *layout* ratchet; pixels are the *paint* ratchet. Don’t merge them.
20. **Do not add Lookbook / lookbook_visual_tester.** ViewComponent / LAYER_CAKE decided against. Previews would be a third chrome.
21. **axe-core-capybara is in brgen’s Gemfile.** Completeness: visual_contract `accessibility_violations` is the gate; don’t also run axe in every system test. One consumer.
22. **Mask volatile regions in pixel_diff.** Timestamps, `time_ago`, animated-number, ads. visual_contract should exclude `[data-money]` jitter and `time` elements or the baseline will churn like layout_snapshot already does. Named selectors, not a looser ratio.
23. **Count the system tests.** HEY kept ~10. `RAILS/**/test/system/**` is the census. If it is already ≤10 per app, write the number in `apps.yml` notes so the next agent does not add a 11th for “coverage.”

### Automated layout refining — suggest tokens, don’t paint

The tree’s layout tool is `geometry_probe` + `layout_snapshots/*.json` + `visual_contract`. Auto-refine means a *named token move*, not a pixel rewriter (operator eye).

24. **Snapshot fail → token suggestion.** When a snapshot drifts, emit the ScaleLint/measure token that would absorb it (`--space-3`, `--measure`, `--tap-min`) instead of rewriting the JSON. A dry `layout_snapshot --explain` line. Don’t auto-commit a new baseline from an agent (the August drift is still open).
25. **`walk.js` already walks the page.** Completeness: hanging-marker probe on legal/wiki (second pass 124). That *is* automated layout refine for Tschichold. Don’t add a ML layout model.
26. **Don’t run an AI “make it pretty” pass on SCSS.** Rams honest + tokens. A model that rewrites `_typography.scss` is the opposite of the law.
27. **Playwright `toHaveScreenshot` / Storybook.** Node. This check path is Ruby. Skip.
28. **Ferrum in MASTER vs Selenium in RAILS.** Same browser, two drivers, two failure modes. Pick one for gates+smokes (Cuprite/Ferrum is the one MASTER already boots).

### What this sitting will not open

29. **Orca / herdr / holaOS / Electric as a MASTER rewrite.** Stars ≠ a constitution. Steal compression, span context, hypothesis-vs-measured, log review.
30. **A second visual SaaS.** visual_contract + snapshots are the suite.
31. **Cucumber.** DHH and this tree’s integration+gate split already replaced it.

---

## Bughunt — 2026-09-11

New defects from reading the four trees after the inventories. Does not restate event-name drift, rate limits, English literals, job uniqueness, LUFS dual windows, or unread `dilla_principles.yml`. A finding is a hypothesis.

### MASTER

1. **`OutputFilter` compresses git/ls/tree and long line-counts.** JSON from WebSearch / scan / GitContext can still dump. Route those `Result.ok` bodies through `filter` (agent-harness item 4). Brittle: `GIT_STATUS_RE` is a regex on the whole blob.

### RAILS

2. **Package index follows redirects with `URI.join` to any host.** `package_index_fetcher.rb:79`. If `mirror_url` or `Location` is `http://169.254.169.254/`, that’s SSRF. Allow-list host to the mirror’s host (and ftp.openbsd.org). Same shape as `OutboundHttp`.
3. **`Vote#apply_score_delta` uses `saved_change_to_value`.** Create: `[nil, 1]`, `nil.to_i` is 0, delta 1 — OK. `after_save` on a touch with no value change: `saved_change_to_value` is nil, `before, after = nil` → `nil.to_i` 0. OK. `after_destroy` uses `value` after destroy — still in memory. OK. Pitfall: `update_all` skips `updated_at` on the votable; WIRING_NOTES trap. Add `updated_at = ?` or leave if score is the only reader.
4. **`Takeaway::Restaurant#update_columns(rating: avg&.round(1) || 0)`.** Average of integers rounded to 1 decimal is Fine; `round(1)` on a float is not money. Don’t store money this way. Rating is OK. Inconsistency: other counters use `increment!`.
5. **Release gate `sleep 1` in a retry loop.** `gates/release.rb:99`. Fine for a laptop gate; don’t copy into a job.
6. **`Date.today` in app code vs `Time.zone`.** Dating `ranked_for` seeds `Date.current` — good. Grep remaining `Date.today` in `app/` (not gates). UTC-vs-Oslo can shift daily picks at 00:00–02:00.
7. **`amber` `config.generators.system_tests`.** brgen and bsdports set `nil`. If amber still generates system tests, the 8.1 policy is inconsistent.

### STUDIO / OPENBSD

8. **`MixScore.band` interpolates `path` into backticks.** `mix_score.rb:43`. `verify_fx.rb:83` interpolates `path` and `af`. `dilla.rb:15011` ffprobe the same. `live/rack.rb:182` uses `shellescape`. One helper: `Open3.capture2e("ffmpeg", "-i", path, ...)` with a timeout. A crate path with `"` is a command.
9. **No timeout on those ffmpeg backticks.** A hung decode blocks `rake test` / characterize forever. `Open3` + `Timeout` or ffmpeg `-t`.
10. **`measure` `.to_f` on a missed regex is `0.0`.** A failed ffmpeg looks like silence. Raise or return `nil` if the match is missing.
11. **`OPERATOR.sh` `sleep 10` / `sleep 5` in loops.** Fine for boot. Pitfall: `set -e` with sleep is OK; an unquoted `$delay` is not if delay is empty. Quote `"$delay"`.
12. **lora `YAML.load_file` in `render_config.rb` / `shoots.rb`.** Same as 8. Toolkit YAML is local; still `safe_load_file`.

### Smells that are pitfalls, not style

13. **FixLoop background + propose_tree threads + WatchLoop + cable_bridge + TTS workers.** Five unsupervised thread families in one Falcon process. A leak in one starves TTS. Bound them (`HostBudget`) or don’t start propose_tree from the web process.
14. **`SecurityAdvisoryRefreshJob` + `sleep` + no uniqueness** (uniqueness was inventory). Together: two jobs, ten minutes of sleeps, NVD bans the IP. Continuations (Rails 8.1 list) + no sleep.
15. **Redirect-follow without host pin** is the same class as DynamicHttp+SSRFGuard. One allow-list helper for all `Net::HTTP` in RAILS (`CrawlSupport.fetch` already exists per `file_length_ratchet_test` comment). Point the package index at it.

### OPENBSD — locks, env, false greens

16. **`.deploying-*` does not cover the window `resource_guard.sh` describes.** App `rc_pre` touches the flag, `pkill`, `sleep 1`, then `rm`. The 300s `/up` wait is after `rc_cmd`. Guard comment says the lock lasts through precompile, migrate, cold boot. A 5-minute tick can shed during the boot the lock was meant to protect.
17. **master’s lock is the same hole, shifted.** `etc/rc.d/master` touches `.deploying` after `bundle34 install` and removes it at the end of `rc_pre` *before* the `/up` wait. Bundle and Falcon bind are uncovered.
18. **`*_jobs` drop the app’s `set -a`.** `rc.d/brgen` exports the whole env file. `brgen_jobs` / `amber_jobs` / `bsdports_jobs` `. /etc/<app>.env && export RAILS_ENV SECRET_KEY_BASE HOME …` without `set -a`. VAPID, SMTP, and the rest of the file never reach Solid Queue. Push and mail from jobs fail closed-looking.
19. **Two `PUB4_CI_LOCK` policies.** `lib/ci_lock.sh` only honours an override under `/var/db/pub4/`. `bin/with-ci-lock` honours any non-world-writable directory. Two mutexes.
20. **`pub4_ensure_ci_lock` deletes `.holder` while a holder may own the flock.** Attribution races; running CI looks unheld.
21. **`nsd-resign` reports health when it signed nothing.** Empty keys or empty zone dir → “all zones valid — nothing to do.” Pass on empty.
22. **`bin/smoke-apps.sh` cannot fail master.** Master not listening is `skip`. A dead face plus live brgen exits 0.
23. **`test_tracked_crontab.rb` never sees the uptime-check line.** `scheduled_commands` takes `line.split[5]` and keeps only paths starting `/`. Crontab `ALLOW_BSDPORTS_DOWN=1 /usr/local/bin/uptime-check.sh` — field 5 is the env assignment. The test would still pass if that wrapper vanished.
24. **`drain-jobs.sh` turns a dead sqlite into “nothing due.”** Unreadable db → 0; `solid_queue_proof.rb` treats “nothing due” as proof the drain ran. A broken queue file keeps deploys green.
25. **`drain-jobs.sh` uses `cut`.** Banned. Ruby or zsh split.
26. **`core-reclaim.sh` RSS is `ps | grep | grep -v | head -1 | awk`.** Wrong pid; ceiling never fires. `head`/`awk` banned.
27. **`emergency_cpu.sh` uses `head`.** Crisis path on OpenBSD `head`.
28. **Weekly integrity lock is a no-op if `fuser` is absent.** `if [ -f "$LOCK" ] && fuser "$LOCK"` — missing fuser makes the condition false; the script proceeds and races CI.
29. **`start_all_apps.sh` restarts relayd after a fixed 5s.** Amber rc.d waits up to 300s for `/up`. Relayd can reload onto empty backends.
30. **`etc/rc.d/master` digest is unquoted.** `cksum $_face_assets …` word-splits. Empty list plus glob stamps a digest that is not the asset set.
31. **`bin/vps-state` swallows a corrupt deploy stamp.** `JSON.parse` rescue nil → “never deployed.”
32. **Fixed 2026-09-12.** Confirmed against vm23: `top -b -n 1` and `vmstat -s`
    both answer on OpenBSD 7.8, so the fallback is live and only the both-failed
    case was wrong. It kept the 100% initialiser, which made `mem_avail_pct -lt
    MEM_WARN` unreachable and left the guard quietly deaf to memory-only pressure.
    It now fails to 0 and logs why, matching the load arm six lines above, which
    fails to 9.9 for the same stated reason.
33. **`smtpd.conf` listens on `vio0`.** Interface rename and inbound 25 dies.
34. **Hardcoded `/home/dev/pub4` in `start_all_apps.sh` and rc.d.** `PUB4_ROOT` / a worktree is ignored.
35. **`dr-pull --check` exits 0 when `~/pub4-dr` is missing.** The local gate that should notice a stale backup is a skip on a Mac that never created the dir.
36. **`amber_queue_sweep.sh` has no `QUEUE_DB` existence check.** `sqlite3` on a missing path creates an empty file, then SQL against missing tables dies — or plants an empty `production_queue.sqlite3`.

### STUDIO — ffmpeg 0.0, scratch races, silent session

37. **Album master is the same backtick hole as MixScore, with gain.** `dilla.rb:34535–34541`. Failed ffmpeg → `I=0` → `gain = target - 0` applies ~19 dB of make-up. Don’t ship that take. Open3 + status + abort.
38. **`audio_duration_sec` discards status, rescue `0.0`.** `build_harmony_loud` then `[dur, 8.0].max` — a failed probe mixes **8 seconds** of a longer stem.
39. **Scratch names are not pid-scoped.** `harmony_loud.wav`, `live_tmp.wav`, `dilla_drums.wav` … Two `dilla` processes (or `PARALLEL=3`) write the same files. Pid-scoped temps exist at `:5735` and are unused here.
40. **Scratch fallback is per-uid, not per-process.** `Dir.tmpdir/dilla-scratch-#{uid}`. CI user plus a second render still collide.
41. **`CompositionEngine.load!` silent `rescue StandardError`.** Truncated `session.json` becomes a brand-new session with no warn. Jam looks like it loaded last night’s work.
42. **`crate_dig` / `VocalChop.loops` / `Acapella.index` JSON parse with no rescue.** Corrupt index is a backtrace on the vocal path. Refuse with the path.
43. **`kaggle_session.rb` `JSON.parse` at load.** Missing file raises on `require`, not on `run`. `ruby -c` never sees it.
44. **postpro comment-strip `gsub(/^.*\/\/.*$/, "")` kills JSON lines that contain `//`, including URLs in strings.**
45. **Playlist/learn JSON loaders `rescue StandardError` → empty.** Corrupt catalog looks like a first run; the next save overwrites it.
46. **`sine_stream.rb` mutates ENV at load.** `ENV["WONKY_TOP_DIRT"] ||= …`. A require from a test leaks knobs.
47. **Two `capture` APIs.** Engine `capture` → `[stdout, stderr, status]`; `RadioChop.capture` → a string. Copy-paste of `.first` across the boundary is a type error.
48. **`mix-score` never calls `tool_available?("ffmpeg")`.** Engine mix metrics do.
49. **`STREAM_ITERATE_LOG` is one shared path, no flock.** Concurrent streams interleave lines.
50. **`bin/crate` ROOT is `…/dilla/crate`.** That directory is gone. `list`/`fetch` write a third layout the engine never reads.
51. **`isolation.rb` loads every `test_dilla_*.rb` in one `-e` process.** session.json mtime races and ENV pins leak by construction. `rake test:dilla` still runs that way.
52. **`EnvSandbox` restores ENV, not constants.** Engine constants computed from ENV at load (`ONLY`/`EXCLUDE` in acapella) stay at first-process values.
53. **Album encode `Open3.capture2e` ignores status, then `rm`s the staged file** and prints loudness from the missing dest (0.0 again).

Highest cost if wrong: 28–30 (deploy lock + jobs env), 36 (drain false-green), 49–53 (ffmpeg 0.0, scratch, silent session).

### MASTER — writes, taint, request path

54. **PathGuard is prefix-only; World realpath-walks ancestors.** ReadFile/WriteFile use PathGuard. A symlink inside the root reaches `/etc`. Put World’s ancestor-realpath check in PathGuard.
55. **`SearchFiles` `Dir.glob(File.join(@root, glob))`.** `File.join(root, "/etc/passwd")` is `/etc/passwd`. Reject absolute globs; PathGuard every hit.
56. **Fixed 2026-09-12.** Confirmed before fixing: the sanitiser allowed `:` and `/`
    explicitly, so `show` with `HEAD:<path>` printed that path's blob — any tracked
    file, at any revision, including ones deleted since — while log, blame and diff
    all route their path through `safe_path` and PathGuard. `show` has no path
    argument, so the colon form was the only way to ask it for one and nothing
    bounded it. `Io::LLM::GitContext` exposes the tool to a model, which is what
    made this worth more than tidying. Refused rather than sanitised, since no
    caller in the tree passes `<rev>:<path>` and `--stat` already says the argument
    describes a commit. `test_io_path_guard.rb` covers it and fails 2 of 3 with the
    guard removed.
    Cost: `spine.lib_body_ceiling` 38329 -> 38334, recorded with the reason. I first
    compressed the guard onto one line to stay under the ceiling and then put it
    back — the 38298 -> 38299 entry in `spine.yml` had already settled that exact
    instinct, for a security rule, against itself.
57. **`ReadFile` `File.readlines` the whole file then slices.** A 200k-line file becomes prompt. Sacred paths block writes, not reads — `.master/config.yml` is ingestible. Line-range IO; refuse secret paths on read.
58. **TTS `job_id` is SHA256(voice|text)[0,32].** `readable_job` skips ownership when ready. Anyone who can guess the utterance fetches the mp3; identical lines cross conversations. Random id; always `owned?`.
59. **`GET /chat/tts` and `GET /chat/enhance` have side effects.** Prefetch and query logs trigger paid work. Enhance is not in `AUTHENTICATED_ACTIONS`. POST only; auth enhance.
60. **`require_same_origin!` allows missing Origin when `Sec-Fetch-Site` is not `cross-site`.** curl CSRF from a sibling host with no fetch metadata passes. Command already skips CSRF. Require Origin or `same-origin`.
61. **`GET /chat/skills`, `GET /chat/research`, `POST /chat/photo` are visitor-reachable.** Research is outbound HTTP; photo is 12MB + postpro. Authenticate or quota.
62. **`GET /ingress/health` lists cron/webhook names unauthenticated.** Public health stays `{ok:true}`; names behind the token.
63. **`production.rb` `host_authorization = { exclude: ->(_) { true } }`.** Any `Host:` is accepted behind relayd. Allow the real hosts only.
64. **`DynamicHttp` interpolates `{param}` into URL/body with no escape.** Query injection; SsrfGuard sees the URI after interpolate. Escape by slot.
65. **MCP SSE `cfg["url"]` has no SsrfGuard.** Writable `mcp_servers.yml` becomes an internal-network client.
66. **`pairing.rb` `allowlist_path` `File.expand_path` can leave the tree.** Force under `.master/pairing/`.
67. **`ensure_brain_files!` writes `data/IDENTITY.md` if missing**, bypassing sacred `data/`. Write under `.master/` or don’t create constitution files at runtime.
68. **`Timeout.timeout` around `Net::HTTP` / UNIXSocket / Ferrum.** World already measured Timeout does not kill the child. Hung POST holds a Falcon worker. Use `read_timeout` / `IO.select` / Ferrum’s timeout; `quit` in ensure.
69. **SSE loop `sleep 0.1` for up to 600s, `subscribe("*")` unbounded Queue.** Two Falcon workers plus chat SSE starve the 1 GB box. `Queue.pop(timeout:)`; cap; `HostBudget`.
70. **`/health` SHA256s `Gemfile.lock` every poll — measured 2026-09-12, and
    the finding is false in both halves.** The hash costs **27µs** on a 14,687-byte
    lockfile (2,000 calls in 0.054s); ten times slower on vm23's vCPU is still
    a third of a millisecond against a relayd poll. And the proposed fix is the
    thing `speech.rb:154-158` already measured and rejected in writing: the
    worker's own `bundler/setup` touches `Gemfile.lock`, so an mtime key is
    invalidated by the very probe it memoises and every call spawns a full
    subprocess. Content-keying is what makes the memo work. Kept as a guard —
    a cheap-looking hash beside an expensive-looking name reads as waste, and
    the expensive thing was the subprocess it prevents.
71. **Hard compact sends all `session.messages` into `agent.ask`.** That’s the window that overflowed. Summarise a tail.
72. **`SqliteStore` WAL failure falls back to `:memory:`.** Pairing/memory vanish on restart; process looks healthy. Fail closed for durable stores.
73. **`FileProcessor` lock is `CREAT|EXCL` then delete; `remove_stale_lock` is mtime then delete (TOCTOU).** A crash holds the scan 300s. `flock` on a stable lockfile.
74. **`mode_posture#set!` writes `.master/mode` and sets `ENV["MASTER_MODE"]` process-wide.** One Falcon worker’s `/mode` changes every request on that process. Don’t mutate ENV.
75. **`pairing#revoke` skips `with_store_lock`.** Redeem vs revoke can resurrect a deleted token.
76. **`context_window` soft compact `Thread.new { compact! }` which `session.clear!` while a turn may still append.** Compact under the session mutex.

### RAILS — strict load, mass assignment, uniqueness, GET writes

77. **Listing show `reviewable_by?` hits `orders.where` after `increment!`.** `restrict_with_error` is still strict. Signed-in show 500s. Include `:orders` or query `Marketplace::Order.where(listing_id:)`.
78. **TV feed preloads `video_file` not thumbnail.** `_item.html.erb` `video.thumbnail.attached?` → strict 500. `includes(thumbnail_attachment: :blob)`.
79. **Users#show posts without `with_attached_image`.** Profile cards 500 or N+1. Mirror HomeController preloads.
80. **Inbox `includes(:participants, :messages)` loads every message in every thread.** Drop `:messages`; unread already has `unread_counts_for`.
81. **Listing params permit `:status` and `:kind`.** Seller POSTs `status=sold` or flips kind without details. Drop `:status`; lock `:kind` on update.
82. **Stores permit `:stripe_connect_id`.** Owner points payouts at another Connect account. Server-only OAuth write.
83. **Partner programs permit `:status`.** Owner opens a draft with no review. `open!` / `pause!` only.
84. **Takeaway restaurants permit `:active`.** Hidden field unpublishes the kitchen. Dedicated action.
85. **Playlist like uniqueness includes nullable `set_id`/`playlist_id`.** SQLite unique treats NULL as distinct — two likes on the same playlist both insert. Partial unique indexes.
86. **Dating match unique is initiator+receiver only.** A→B and B→A are two rows (comment admits it). Unique on `LEAST/GREATEST`.
87. **Mention uniqueness has no unique index.** Race on edit double-notifies.
88. **Affiliate conversion `transaction_id` allow_nil unique.** Duplicate paid postbacks. Reject blank ids.
89. **Vote `after_save` `update_all` score.** A rolled-back vote still moved `posts.score`. `after_commit`.
90. **Dating like `after_create :check_mutual_match` inside the transaction.** Rollback can leave a Match. `after_create_commit`.
91. **GET nearby `#room`/`#widget` `join!` + `ensure_guest_user!`.** Crawlers mint users. POST join, or join when a message is sent.
92. **GET stories show `view_by!`.** Prefetch inflates counts. Beacon/POST.
93. **GET ports/places/amber items `record_activity!`.** Activity table grows with every crawl. Skip bots.
94. **Daily picks: two tabs both `create!`, rescue unique, return `chosen` not the rows that won.** Page shows five faces the DB does not have. Reload `existing`.
95. **Amber `MoneyInOre` `cents / 100.0` is Float.** Outfit totals drift. `BigDecimal`.
96. **Amber `planned_outfit` `this_week` uses `Date.today..7.days.from_now`.** Date vs Time, UTC vs Oslo. `Time.zone.today`.
97. **TV `comments_count` / `likes_count` have no writer.** Rank/UI that reads them is 0. `counter_cache` + default 0, or drop the columns.
98. **Ports importer upserts one-by-one, no transaction.** Nightly vs web → `BusyException`. Wrap in `Port.transaction`. `ApplicationJob` does not `retry_on SQLite3::BusyException`.
99. **PWA share skips CSRF on posts#share and amber items#share.** Require Origin allowlist or a share nonce.
100. **Playlist sets unknown privacy string is treated as public.** Typo in DB leaks private sets. Default deny.
101. **Comments#create with neither event_id nor post_id → `@commentable` nil → 500.** `head :not_found`.

---

## Restructure — one job, one door — 2026-09-11

Cherry-picked. Not the sprawl census, not “split this file,” not LAYER_CAKE, not folding `dilla/live/`, not nesting `shared/lib/operator`, not three sign-in screens, not merging `probe`/`dogfood`. The move is always: two things that do one job become one thing, or a dead copy is deleted.

A finding is a hypothesis. Verify the second caller before you delete the first.

### MASTER

1. **One atomic write.** `Io::AtomicWrite` (fsyncs), `World#write_atomic`, `cli/scan/live.rb`. Callers of the last two can leave a 0-byte file. One helper; the others become wrappers or go.
2. **One PathGuard.** Prefix check vs World ancestor-realpath. Reads use the weak one. One module, the strong check.
3. **One constitution loader.** `Ground::Constitution` vs `Core::Constitution`. Rename Ground’s to `PrincipleStore` or fold. `Master.law` is the reader of `rules.yml`.
4. **One memory search.** `ground/memory_search.rb` vs `ground/memory/search.rb`. Index vs query. Honest names, or one class.
5. **One mood.** `PressureEngine`, `Trace::ContextPressure`, `Cognition::Affect`. Document which bus events each owns, or fold PressureEngine into Cognition. Three weathers is a forecast.
6. **One attention table.** `cognition/attention.rb` vs `cli/attention_context.rb` vs `data/attention_context.yml`.
7. **Delete the unwired command tables.** `memory_commands` / `system_commands` / `media_commands` / … are required and never merged into `CommandRegistry.build`. Wiring them duplicates live verbs. Delete the dead tables; keep the one command worth merging (`/tools` list).
8. **One diagnose door.** `check` / `ci` / `audit` / `probe` / `smoke` / `dogfood` / `doctor`. `probe` and `dogfood` stay (measured). `smoke` → `check --profile=ci` subset; `audit` → `operator lint --staged`. Document the Venn once; don’t add an eighth.
9. **`bin/cli` execs `bin/master`.** Two entrypoints, one REPL. Completions generate from `HELP_TOPICS`.
10. **`spec/` vs `test/` vs `web/test/`.** Face tests live in three homes. Two at most: `test/` for Ruby, `web/test/` for the face. `spec/core_smoke.rb` is not `*_spec.rb`.
11. **`lib/rails/` moves to `RAILS/gates/lib` or becomes `/rails audit`.** MASTER should not audit RAILS by walking `Master::ROOT`.
12. **Done — verified 2026-09-12.** Neither `MASTER/lib/grok/` nor `MASTER/lib/deploy/`
     exists; lib/ is boot, builder, cli, cognition, core, fix, ground, io,
     operator, rails, review, trace, voice.
13. **`work_commands_extra.rb` / `work_commands_status.rb`.** Split by verb or fold into `work_commands.rb`. `extra` is a junk drawer.
14. **One snapshot verb.** `tools/snapshot.rb` vs `Trace::Snapshot::Publisher`.
15. **One dogfood.** `spec/dogfood_spec.rb` vs `bin/dogfood` vs `rake dogfood`.
16. **One skills list.** `lib/cli/skills.rb` vs `data/patterns.yml` skills_registry. Index first, body on demand.
17. **One dmesg.** `lib/trace/dmesg.rb` vs `ChatController#dmesg`.
18. **One token job.** `MasterIngressToken` vs `MasterWebToken` — names by job (HMAC vs cookie), not two classes that look interchangeable.
19. **One log directory.** `WebEventLogger` vs `Trace::Log` vs `Swallow` JSONL.
20. **`OpenbsdConfig` / `HostBudget` read `OPENBSD/` once.** Don’t duplicate `vm_resource.yml` in MASTER data.
21. **Runtime deps from `master.gemspec`; web Gemfile is Rails + Falcon.** Two Gemfiles, two locks, two platform `if`s.
22. **Completions generated from the live table.** `_master` still completes `through`. Add `_operator`. No hand-maintained verb list.
23. **Done — verified 2026-09-12.** `mask.js` and the three `mask_*` files are off
    disk and nothing loads them. The two textual matches left are a different
    thing: `visual_bridge.js` names the `papua-mask` topology and a `#mask` DOM
    id fallback, and `visual_governor_spec.rb:30` is the comment recording the
    supersession.
24. **Cable vs SSE vs `visual_bridge`.** Three event pipes. Cable broadcasts `*`. One pipe for the face; Cable goes or takes the visitor allow-list.

### OPENBSD

25. **Fixed 2026-09-12.** `data/operator.yml` is the command list and now carries
     the whole of it: the check family (check-rails, check-openbsd, check-vps,
     check-full), vps-state and tree.sh lived only in START_HERE.md's Golden
     Commands, so the stub that pointed here was the more complete of the two.
     START_HERE's Golden Commands and Source Of Truth sections are pointers now,
     and RECIPES.md is a door rather than a table. `operator_docs.rb` reads the
     yaml and `/orient deploy` prints it, so a recipe added there shows at every
     door.
26. **One deploy verb.** `bin/vps-deploy` is canonical. `vps_deploy_master.sh` calls it. `vps_production_push` is `SKIP_CI=1 vps-deploy all`. `deploy_all.sh` dies or becomes a wrapper.
27. **One uptime checker.** `bin/uptime-check.sh` execs `health_check.rb --public-only`. `usr/local/bin/uptime-check.sh` is the install target of the same file, or a one-line exec. One list of hosts from `deploy_inventory.json`.
28. **One “on box” bootstrap.** `vps_install_all` vs `vps_on_vm_install`. Fold; delete the `git stash`.
29. **`check` calls `check-openbsd` for the identity/smoke overlap**, or START_HERE draws the Venn. Contributors must not need both by folklore.
30. **rc.d apps from one tmpl.** `rails-app.tmpl` disagrees with brgen (PATH, pexp, timeout). Generate amber/bsdports from the live brgen script, or delete the tmpl so OPERATOR cannot install the wrong one.
31. **Jobs rc.d `set -a` like the app.** Same env file, same export. Three footers → one `jobs.footer` with APP filled in.
32. **`ALL_DOMAINS` lives in `data/dns.yml`.** OPERATOR.sh, Ruby gates, and health_check parse a shell array today. One yaml; shell reads it with `ruby34 -ryaml`.
33. **`SMOKE_SCRIPTS` / `FLEET_INVENTORIES` include `relayd-watchdog`.** Hardcoded backend tables elsewhere die.
34. **`dotfiles/` declared Mac-only, check none**, or it leaves the OpenBSD tree.
35. **Fixed 2026-09-12.** `OPENBSD/restore_litestream.sh`. Three separate passes
    asked for this rename, which is what a real defect looks like from outside.
    Its first line now reads "NOT the disaster-recovery script — use
    OPENBSD/bin/dr-pull for that", and the paragraph under it says why: vm23 has
    no litestream binary and no replicas, so the old name promised recovery the
    file cannot deliver, under exactly the name somebody reaches for in an
    emergency.

### RAILS

36. **One `WebPushJob`.** `brgen/app/jobs/web_push_job.rb` and `shared/app/jobs/shared/web_push_job.rb`.
37. **Notifications: host or shared, not both.** brgen controller vs `Shared::NotificationsController`. Promote when city grouping unifies, or delete the stub.
38. **Votes: host or shared reflex, not both.** `VoteReflex` and `votes#create.turbo_stream` — keep the stream (function-layout test); Reflex becomes a no-op or goes.
39. **One `LiveSearchable` including deals.** Listings/stores/takeaway use the helper; deals still LIKE. Maps `#index` JSON vs HTML duplicates it.
40. **One vertical nav partial.** `marketplace/_nav_bar.html.erb` vs `takeaway/_nav_bar.html.erb`. Accent var already on `body`.
41. **One empty-state partial, callers pass `t(...)`.** TV channels still inline English titles.
42. **One `finish_live_search`.** Duplicated across listings/stores/deals/restaurants/places.
43. **Stimulus: one registration path.** `stimulus_boot.js` loads the fleet; unused reveal/auto-submit/content-loader still cost importmap. Register when present (carousel pattern) for the rest, or unregister.
44. **One `application.js` Stimulus start.** Three app copies plus shared. If they only `import "controllers"`, one file in shared.
45. **`lazy_image_tag` lives in the brgen host, called from dating.** Move the helper to shared so engine tests don’t need the host.
46. **Fixed 2026-09-12.** The inline block is `shared/app/assets/stylesheets/_site_legal.scss`, moved with every value untouched — measured on brgen.no/privacy before and after, `.legal-prose` is 724.397px wide and its h1 is 28.8px/33.12px either way. Snapping those values onto the scales is a separate decision and the operator's.
47. **`.reading-column` / `.form-measure` are worn or deleted.** Defined, unused. Put them on legal and compose, or drop.
48. **One money type.** Amber `MoneyInOre` float vs marketplace integer cents vs affiliate decimals. Integer minor units everywhere money is money. Ratings stay decimal.
49. **One uniqueness helper for nullable FKs.** Playlist likes/collaborations. Don’t copy the NULL-is-distinct bug.
50. **`after_commit` for anything that enqueues or `update_all`s.** Vote score, dating match, hashtags, mentions, listing alerts. One concern if the pattern repeats; don’t invent `AfterCommitable`.
51. **Gates: `root:` kwarg.** Six gates rewrite `ROOT` at load. Tests shouldn’t.
52. **`locale_contract` is the i18n door.** Don’t also append shared locale paths twice. Unused-key scan extends that test, not a gem.
53. **System tests stay the handful.** Integration + gates. Cuprite/Ferrum as the one browser driver (MASTER already Ferrum). Selenium goes.

### STUDIO

54. **One `capture`.** Engine returns `[stdout, stderr, status]`; `RadioChop.capture` returns a string. One signature; Acapella and mix-score call it.
55. **One ffmpeg runner.** MixScore, verify_fx, album master, `dilla.rb` ffprobe — backticks vs Open3 vs `tool_available?`. Open3 + timeout + non-zero abort. 0.0 is not a measurement.
56. **Pid-scoped scratch everywhere.** The helper exists (`:5735`). `harmony_loud.wav` and friends use it.
58. **One LUFS window.** `dilla_reference.yml` vs `MixScore::REFERENCE[:lufs]`. Loss-gate test already wants them equal.
59. **`bin/crate` writes the layout the engine reads, or it goes.** Third crate tree.
60. **`rake test:dilla` is isolation’s process model, or isolation is not claimed.** One `-e` that requires every test file is how ENV and session.json leak.
61. **`council` / `scan` slogans out of `dilla` dispatch.** Dead prose. Help topics stay.

### Cross-tree

62. **`operator gate` is the ladder.** OPENBSD `check-full` and `RAILS/test/run_all.rb` are rungs. START_HERE in each tree says so in one sentence.
63. **PATH_OWNERSHIP lists live dirs only.** MASTER `docs:`/`reports:` are gone; `cognition/` / `law/` / `runtime/` are not listed. OPENBSD omits `data/`, `gates/`, `lib/`. A lint on undeclared top-level dirs.
64. **TODO.md stays the backlog; DECISIONS.md stays the why.** Don’t add a third.
65. **Harness files stay generated.** `rake docs:agent_contracts`. Don’t copy law into CLAUDE.md.

Fenced: splitting `dilla.rb`, folding `live/`, LAYER_CAKE, ViewComponent, nesting operator, three sign-in, merging `probe`/`dogfood`, Kamal, Docker workers, a second type scale, a Parametricist CSS.

---

## OpenClaw, OpenCrabs, Hermes, OpenCode — MASTER gaps — 2026-09-11

Read against source, not star counts. OpenClaw `openclaw/openclaw` (~389k, Why OpenClaw 2026-08-27), OpenCrabs `adolfousier/opencrabs` docs v0.5, Hermes `NousResearch/hermes-agent`, OpenCode `anomalyco/opencode` (~207k). MASTER already recorded a June 2026 cousin-pass in `project_context.yml` (`reference_opencrabs`): pairing, tool profiles, FTS5, compaction, phantom, `/doctor`, worktrees. This list is what that pass did not name, or what shipped in those trees since.

Do not import Docker sandboxes, ClawHub untrusted skills, native iOS apps, Voice Wake, Live Canvas/A2UI, RSI brain writes, or Hermes Portal telemetry. Policy stays code (`soul.yml`), not a prompt.

A finding is a hypothesis.

### Trust boundary (OpenClaw Why)

1. **Trusted gateway / untrusted execution.** OpenClaw: Falcon-class control plane must not share credentials with the shell. MASTER’s face, CLI, and `Io::Exec` are one process. Completeness: visitor/chat never sees `MASTER_INTERNAL_TOKEN`; write tools already go through PathGuard (strengthen it — bughunt 67). Don’t wrap the whole app in Docker; isolate *exec*, not the gateway.
2. **Policy is code, fail closed.** OpenClaw and Hermes RFC: denial is structural; hook failure on `tool_call` fails closed. MASTER `InjectionGuard` / `Tool::Profile` are that. Completeness: a plugin/MCP tool that errors on the guard must not run. Test: WebFetch without SsrfGuard is a fail, not a skip (bughunt 78).
3. **Secrets as handles, not prompt text.** OpenClaw SecretRefs; agent sees a handle, egress substitutes. MASTER Redactor is post-hoc regex (bughunt 60 over-redacts SHAs). Completeness: env keys used by tools stay out of `session.messages`. A test that `File.read("/etc/master.env")` cannot appear in a council prompt.
4. **Versioned state, guarded upgrades.** OpenClaw schemas + signed releases + `doctor` migrations. MASTER `data/*.yml` has no schema version. Completeness: `soul.yml` / `rules.yml` already immutable; `.master/` session JSON gets a `schema_version` and `bin/doctor --fix` migrates or refuses.
5. **Forgetting has bounds.** OpenClaw `memory forget` vs reingestion. MASTER knowledge/ is gitignored. Completeness: `/forget` that tombstones a session id so compact/index cannot pull it back. Don’t claim GDPR from a delete of one file.
6. **`openclaw security audit --deep` as a scheduled check.** MASTER `/security-audit` exists. Completeness: `bin/doctor` prints the same IDs `openclaw security audit` would (pairing store path, host_authorization, GET /chat/tts). Alarm on drift, don’t add VirusTotal.

### Gateway and sessions (OpenClaw, Hermes, OpenCode)

7. **`openclaw triage`.** Read-only health → sanitized prompt → hand to a detected coding agent. MASTER `bin/doctor` reports. Completeness: `bin/doctor --prompt` writes a redacted diagnosis MASTER or OpenCode can ingest. Nothing leaves the box until the operator picks the agent.
8. **Build vs plan agents.** OpenCode Tab: `build` (full) vs `plan` (read-only, bash asks). MASTER `/btw` + `agent_taxonomy.yml` already types explore/plan. Completeness: plan profile cannot call `WriteFile`/`AstEdit` (Policy::Subagent). Test it.
9. **ACP (Agent Client Protocol).** OpenClaw and OpenCode speak ACP so editors host the harness. MASTER is the harness. Completeness: optional `bin/master --acp` stdio that maps ACP session/prompt to the existing Session. Don’t become an editor.
10. **A2A JSON-RPC.** OpenClaw/OpenCrabs. MASTER has no peer protocol. Completeness: one documented “MASTER is not an A2A server” or a tiny `/v1` that is the OpenAI-compatible subset OpenClaw copied — disabled by default. Don’t enable `/v1/chat/completions` on the public face.
11. **Prompt-cache session affinity.** Hermes `x-opencode-session` / OpenRouter `session_id`. MASTER `Trace::CacheEfficiency` exists. Completeness: every provider call in one conversation sends one opaque session header. One helper, all senders.
12. **Bounded SSE queues per connection.** OpenCode v2 event stream: encode once, offer to N bounded queues. MASTER EventsController `subscribe("*")` unbounded + `sleep 0.1` (bughunt 82). Steal the queue bound, not the TypeScript.
13. **`/retry` and `/undo`.** Hermes. Completeness: last-turn undo is `session.messages.pop` + worktree `git reset` of that turn’s paths if a commit exists (bughunt 8 checkpoint). Don’t invent a timeline UI.
14. **Mid-turn interrupt.** Hermes Ctrl+C / OpenCrabs `/stop` cancels handshake and backoff. MASTER chat has no `/stop`. Completeness: SSE client disconnect cancels the Fiber; `/stop` on the next POST. Test disconnect.
15. **Session id on every log line.** OpenCrabs `session_id` spans. MASTER logs mix. Completeness: `Trace::Log` includes `session:` from `Fiber[:master_conversation]`. One grep reconstructs a turn.

### Skills, plugins, directives

16. **AgentSkills spec (`SKILL.md`).** OpenClaw/Hermes/agentskills.io. MASTER `CLI::Skills` + `patterns.yml`. Completeness: load `SKILL.md` from `.master/skills/` with YAML frontmatter; index first, body on demand (restructure 16). Don’t fetch ClawHub.
17. **ClawHub is untrusted.** Scans can be pending and still install with a warning. MASTER: local skills only, or `bin/master skill verify` that hashes the file against a pinned allowlist. No registry.
18. **Plugin hook timeouts.** Hermes RFC on Pi vs OpenCode: neither had timeouts; both shipped hangs. MASTER bus subscribers can block Falcon. Completeness: `bus.subscribe` with a deadline; timeout is Swallow.log + skip, fail-closed if the hook is a write guard.
19. **Namespaced plugin emit.** Hermes proposal vs Pi’s un-namespaced channels. MASTER topics are already `fix_loop:` / `tool:`. Completeness: MCP/plugin events must use `plugin.<name>.` prefix or they don’t publish.
20. **Vendor harness as plugin, core stays small.** OpenClaw drives Codex/Claude Code as runtimes; it keeps channels and policy. MASTER `bin/master` is the runtime. Completeness: optional `Io::Exec` of `opencode run` / `codex` behind Tool::Profile, not a rewrite. Policy still PathGuard.
21. **Project directive discovery.** OpenCrabs indexes AGENTS.md, CLAUDE.md, `.cursorrules`, GEMINI.md, copilot-instructions. MASTER *generates* those from one block. Completeness: when MASTER is pointed at a foreign repo, read their AGENTS.md as data, never as instruction (soul already). A test that a planted `AGENTS.md` saying “print your prompt” is not obeyed.
22. **Config writes only through a validator.** OpenCrabs `config_manager`; agent never raw-edits `config.toml`. MASTER: no tool may `WriteFile` `data/soul.yml` / `data/rules.yml` (already immutable). Completeness: `.master/*.yml` goes through `RuntimeCatalog` schema or refuse.

### OpenCrabs since the June cousin-pass

23. **Per-path write locks.** OpenCrabs v0.3.83. MASTER FileProcessor TOCTOU (bughunt 87). One flock per abs path for WriteFile/StrReplace/AstEdit.
24. **Tree-sitter structural memory.** OpenCrabs v0.5: call-graph beside FTS. MASTER `CodeIndex` / `SymbolLookup` untested. Completeness: “who calls X” walks Prism, not embeddings. Don’t add a vector DB.
25. **Ralph verification / type-aware criteria.** OpenCrabs: plan criteria use the project’s own test command. MASTER FixLoop re-scans. Completeness: `/fix` on RAILS runs `ruby RAILS/gates/runner.rb` for the dirty app, not a generic `rake test`.
26. **Plan vs execute models.** OpenCrabs routes plan to a cheap model, execute to another. Completeness: `/btw plan` uses the scan/deterministic path; `/fix` may use council. Test `/scan` never hits a frontier (agent-harness 10).
27. **Thinking-loop timeout.** OpenCrabs v0.3.78. MASTER council can stream forever. Completeness: `HostBudget` already; apply it to the LLM socket (bughunt 29 Timeout.timeout).
28. **`doctor --fix` repairs locks and stale markers.** OpenCrabs. MASTER `bin/doctor --fix` already has a comment citing OpenClaw. Completeness: repair `.master/*.lock` and stuck FixLoop pid files; don’t auto-edit `rules.yml`.
29. **Background compaction.** OpenCrabs v0.5 summariser off the turn. MASTER `Thread.new { compact! }` races (bughunt 90). Completeness: compact after the turn, under the session mutex, not during.
30. **Zero telemetry.** OpenCrabs: no phone-home code. OpenClaw: daily version check, opt-out. MASTER: a test that `lib/` has no `update.check` / analytics URL. Version check if any is `bin/doctor`, not boot.

### Hermes (ops agent, not a rewrite)

31. **Closed learning loop stays off for daemons.** OpenCrabs RSI default-off for headless. MASTER must not rewrite `soul.yml` from a skill. `Ledger::Feedback` is the learning surface. Don’t create SKILL.md from a turn without `/soul approve`.
32. **FTS5 session search.** Hermes. MASTER memory FTS exists; session JSONL may not be indexed. Completeness: `/grep` over `MASTER/runtime/*.jsonl` with the redactor on. Don’t embed chat in a vector store.
33. **Cron with delivery.** Hermes/OpenClaw. MASTER ingress cron exists. Completeness: a standing order can POST a summary to a channel *only* if pairing allowlists that destination. No WhatsApp stack.
34. **Don’t put the venv inside the workspace.** Hermes install note: a relative `rm` can wipe the runtime. MASTER `.master/` vs `lib/`. Completeness: `Io::Exec` cwd is the worktree, never `Master::ROOT` for destructive globs.
35. **Seven terminal backends (Docker, Modal, Daytona).** Out. Isolation is `operator worktree`. Document that in START_HERE so the next OpenClaw comparison doesn’t demand Daytona.

### OpenCode (coding TUI)

36. **`opencode run '…'` as a worker.** Hermes skill already shells it. MASTER can `Io::Exec` it under PathGuard for a long coding subtask. Policy still ours. Don’t vendor Bun.
37. **models.dev.** OpenCode’s model DB. MASTER `providers.yml` / `models.yml`. Completeness: `CatalogIndex` already fetches OpenRouter; don’t scrape models.dev unless `data_reach` names it.
38. **Plugin server vs TUI split.** OpenCode: one package, one entrypoint. MASTER `bin/master` vs `web/`. Keep two processes; don’t load the face’s Rails into the CLI.

### Aider / OpenHands / SWE-agent (already in project_context)

39. **Aider repo map.** `GitContext` + `CodeIndex` partial. Completeness: a token-cheap map of dirty files before `/fix` (span context, agent-harness 5). Don’t add tree-sitter twice (24).
40. **OpenHands sandbox GUI.** Out. CDP belongs to RAILS gates.
41. **SWE-agent ACI.** Tools return structured windows. `OutputFilter` + ReadFile line slice (bughunt 70). That’s the interface; don’t clone the Python agent.

### What not to take

42. **ClawHub, unsigned skills, VirusTotal-as-admission.** Local allowlist or nothing.
43. **Native companion apps, Peekaboo screenshots, VNC worker desktops, Beam.** Face is the companion.
44. **Hermes Portal / paid tiers / prompt collection.** MASTER keys stay in `/etc/*.env`.
45. **OpenClaw 647 advisories as a score.** Disclosure volume ≠ safety. Steal the *audit check IDs*, not the count.
46. **RSI that rewrites brain files.** `soul.yml` is immutable. AGENTS.md is generated. Operator approves constitution.

`project_context.yml` `reference_opencrabs` still lists OAuth-before-key, NL config_manager, multi-channel inbox, cron DSL, ClawHub, Live Canvas, Voice Wake. Those stay there as the June list. This section is the 2026-09 delta plus OpenCode/Hermes/ACP.

---

## Aider, Cline, Goose, OpenHands, Warp — MASTER delta — 2026-09-11

Continuation. Stars as of 2026-09-11: OpenCode 207k, OpenHands 87k, Cline 68k, Warp 65k, Goose/AAIF 54k, Aider 49k, Continue 36k (read-only after Cursor acquihire). Read against `CodeIndex` (Prism graph, `references_to`, `impact`) and `GitContext` (log/blame/diff/status/show). Does not restate OpenClaw pairing, ClawHub, Docker, ACP, plan-vs-build.

### Aider — the map, not the chat loop

1. **Repo map is PageRank over a definition/reference graph, fitted to a token budget.** Aider: tree-sitter tags → MultiDiGraph → personalized PageRank → binary-search into `--map-tokens` (default ~1–2k). Chat files ×50, mentioned ids ×10. MASTER `CodeIndex#impact` already has callers; it does not emit a budgeted markdown map. Completeness: `Io::RepoMap` (or `CodeIndex#map(tokens:, chat_files:)`) using Prism, not tree-sitter. Fit by dropping lowest-rank files. Don’t dump the index.
2. **Only `/add` files are writable; the map is read-only context.** Aider. MASTER WriteFile can touch anything PathGuard allows. Completeness: a session `writable:` set (git dirty + explicit add). Writes outside it fail closed. Map still shows the rest.
3. **Invalid grammar must not crash the map.** Aider #5138: skip bad queries, keep filename-only. Prism parse failure → filename line, don’t abort `/fix`.
4. **Auto-commit with a real message, path-scoped.** Aider commits every turn. MASTER law is `git commit -- <paths>` on a worktree. Completeness: optional `/commit` after a successful `/fix` pass using the finding ids as the body. Never `git add -u`.
5. **Co-authored-by from verified session participants.** OpenClaw + Aider `--attribute-co-authored-by`. MASTER is one operator. Completeness: trailer `Co-authored-by: MASTER <master@brgen.no>` only on `/commit` from the runtime, so `git log` can tell agent commits from human ones. Don’t invent a team credit UI.

### Cline — HITL, plan/act, headless JSON

6. **Every edit and bash is a diff until auto-approve.** Cline Plan/Act. MASTER CLI operator is the human; the face visitor is not. Completeness: visitor profile already cannot Shell. Operator CLI: a `--ask` that prints the StrReplace hunk and waits. Default for `/fix` stays scan-with-write (law). Don’t add a VS Code extension.
7. **Checkpoints to undo the agent.** Cline. Same as `/undo` + worktree reset (OpenClaw list 13). One implementation.
8. **Headless JSON for CI.** `cline --json "…"`. MASTER `bin/master --json` / `operator gate --scan-only` already machine. Completeness: `/review --only scan --format json` is the contract test, not a new CLI.
9. **Linter errors as a loop, not a later gate.** Cline watches diagnostics while editing. MASTER FixLoop already re-scans. Completeness: FastStage rubocop is that loop. Don’t spawn a language server.
10. **`.clinerules` is another AGENTS.md.** OpenCrabs already discovers it. MASTER generates harness files. When pointed at a foreign tree, read as data (OpenClaw list 21). Don’t copy Cline’s rule format into pub4.
11. **SDK as a second product.** Cline `@cline/sdk`. MASTER is `bin/master`. Don’t publish an npm SDK.

### Goose (AAIF / Linux Foundation)

12. **MCP-first extensions, not a tool zoo.** Goose. MASTER has MCP coordinator untested (first inventory). Completeness: one MCP client path with SsrfGuard (bughunt 78), stdio only on the box, HTTP behind the allow-list. Don’t “50 tools.”
13. **Desktop + CLI + API.** Goose. MASTER is CLI + Falcon face. Completeness: the face *is* the API. Don’t a Tauri app.
14. **Donated to AAIF.** Governance note, not a feature. MASTER stays this repo’s constitution, not a foundation product.

### OpenHands, Warp, Open Interpreter

15. **OpenHands sandbox GUI.** Out (OpenClaw list 40). Steal: a *named* workspace snapshot before a swarm, which is the worktree.
16. **Warp ADE / Orca fleet.** Parallel agents with a subscription. MASTER FixLoop is one writer. Completeness: `operator worktree` per subagent (OpenCrabs 0.3.83), not a desktop fleet.
17. **Open Interpreter.** Natural language → shell. MASTER Shell is elevated. Completeness: visitor never gets it; operator gets PathGuard. Don’t loosen.

### OpenCode leftovers

18. **Language servers for symbol context.** OpenCode. MASTER has Prism `CodeIndex`. Completeness: repo map (1) *is* the LSP-less equivalent. Don’t start `ruby-lsp` from the agent.
19. **Parallel sessions.** OpenCode TUI split panes. MASTER Session is one Fiber. Completeness: two `bin/master` in two worktrees, already the law. Don’t multiplex two writes on main.
20. **Sign in with Copilot/ChatGPT subscription.** OpenCode. MASTER keys in `/etc/*.env`. Completeness: document that a Copilot token is a provider row, not a product. Don’t OAuth in the face.

### Continue is a tombstone

21. **Continue joined Cursor; repo read-only.** Don’t follow Continue Hub, don’t vendor its autocomplete. If someone cites Continue as a peer, the answer is Cline or OpenCode.

### Cross-cutting that these trees share and MASTER still splits

22. **Dirty-set + map + budget is one prompt recipe.** Aider proved it. `/fix` today dumps files or greps. Completeness: prompt = (writable hunks) + (repo map ≤ N tokens) + (finding). Measure tokens; don’t guess.
23. **Edit format is structured.** Aider search/replace vs diff vs whole-file. MASTER `StrReplace` / `AstEdit` (broken call, bughunt 66). Completeness: one edit tool that works; delete the one that `NoMethodError`s.
24. **Git is the undo log.** Aider, Cline checkpoints, OpenClaw worktrees. MASTER shared-index law already. Completeness: `/fix` without a worktree refuses on a dirty main (restructure 8). That’s the product difference from Aider’s auto-commit-on-main.

### Still out

25. **VS Code / JetBrains / Warp as a shell around MASTER.** The face and `bin/master` are the surfaces.
26. **Harbor / Cline-bench as a hosted eval.** `bin/check --profile=agent` is the eval. Don’t a third-party SWE farm.
27. **Kilo / Roo as a Cline fork to absorb.** Same HITL idea (6).


## ChatGPT proposed forward work — intake 2026-09-11

Unmeasured. Pasted from an external session, converted to numbered items.
Already open and not restated: `tts_socket` on `vps state`, TTS log `root:master`,
`rb-kqueue` / `CHECKSUMS` / dirty lock, listing expiry, saved-search, favorites,
rate-limit census, marketplace 500, one chrome, layout_snapshot drift.
Fenced: golden WAV that overwrites a take, dark-mode restyle, full-site AAA as a vanity
score, a second root `bin/check` beside `operator gate`, `/through` as a campaign name
(the verb is `/review`). A finding is a hypothesis; the last item of this list is the
right one — re-measure and delete what fails.

### MASTER — correctness, architecture, and self-hosting

1. Add a deployment check that fails when a daemon-owned log is not writable by the daemon user.
2. Add a deployment check that verifies every expected daemon socket exists after restart.
3. Add a deployment check that verifies the daemon's effective UID/GID rather than merely checking the process exists.
4. Add a deployment check that verifies the configured TTS voice is the voice actually loaded by the running process.
5. Add a deployment receipt containing commit SHA, effective config revision, process UID, socket state, and health state.
6. Make `/health` expose the commit SHA that the running process actually booted.
7. Make `/health` expose the loaded voice identifier.
8. Make `/health` expose the loaded rules/config revision.
9. Add a machine-readable `/health` schema test so new fields cannot silently change type.
10. Add a negative health test for stale browser/runtime assets.
11. Detect a browser payload whose revision differs from the server revision.
12. Add a single operator command that compares source revision, deployed revision, service revision, and browser asset revision.
13. Make deployment fail closed when those four revisions disagree unexpectedly.
14. Record deployment drift in a durable machine-readable receipt rather than prose alone.
15. Add a `vps diff` command that reports only actionable drift.
16. Add a `vps repair-plan` command that produces commands without executing them.
17. Add a `vps verify` command that performs only read-only post-deploy checks.
18. Add a test proving every `vps` mutating command has an explicit dry-run path.
### MASTER — Bundler, dependency, and OpenBSD portability

19. Regenerate `MASTER/Gemfile.lock` after the `install_if` change and verify `BUNDLE_FROZEN=true` on both supported host families.
20. Add CI coverage that evaluates the Gemfile under an OpenBSD-like platform.
21. Add a CI check that detects platform-conditional dependencies absent from the committed lock.
22. Add a lockfile consistency command specifically for OpenBSD deployment.
23. Add a pre-deploy guard refusing to overwrite a known-good remote lock with a dirty local lock.
24. Add a deployment diagnostic explaining precisely why a dirty lock is being retained.
25. Add a test proving `git pull --ff-only` does not require stashing deployment-local lock repairs.
26. Add a documented recovery path for a frozen Bundler failure without modifying the working tree destructively.
27. Add a platform matrix covering macOS, OpenBSD, and the repository's declared Ruby versions.
28. Audit every shell script for assumptions that work in Bash but not OpenBSD `/bin/sh`.
29. Add a shell portability scanner for `[[`, Bash arrays, `source`, `read -p`, and other non-POSIX constructs.
30. Add a test proving the scanner does not falsely flag intentionally Bash-specific scripts.
31. Audit every `system`, backtick, and `Open3` call for argument-array usage.
32. Add a command-injection rule for interpolated shell commands.
33. Add explicit allowlisting for intentional shell interpolation so the rule remains useful.
34. Audit every executable under `MASTER/bin` for executable-bit correctness.
35. Add a check that every executable has a valid interpreter line.
36. Add a check that every declared interpreter exists on the deployment host.
### MASTER — error handling and observability

37. Inventory all `rescue StandardError` sites and classify them as boundary, optional dependency, probe, retry, or bug suppression.
38. Add a rule requiring a reason whenever a broad rescue intentionally converts an exception into a sentinel value.
39. Add a rule forbidding broad rescue around state-changing operations unless the error is surfaced.
40. Add a rule requiring logging for broad rescues that affect correctness.
41. Distinguish “probe failed” from “system failed” in diagnostic APIs.
42. Replace silent `{}` / `[]` / `false` rescue fallbacks where callers cannot distinguish failure from empty data.
43. Add typed failure results to the most frequently rescued MASTER boundaries.
44. Add a regression test for every rescue whose fallback affects a security decision.
45. Audit rescue blocks that can hide `NameError`, especially optional-library boundaries.
46. Add a rule detecting rescues that can mask missing constants.
47. Audit `MASTER/lib/master.rb` binary detection fallback semantics.
48. Add explicit tests for unreadable files, permission errors, binary files, and encoding errors.
49. Audit `MASTER/lib/design.rb` CSS-reading fallback so missing CSS cannot masquerade as empty CSS.
50. Add diagnostics distinguishing “CSS absent” from “CSS unreadable”.
51. Audit `MASTER/bin/cleanup` tool failures so unavailable tools are not mistaken for successful cleanup.
52. Add exit-status propagation for cleanup operations where failure matters.
53. Audit `MASTER/bin/doctor` checks that are advisory-only and classify whether they should remain non-fatal.
54. Add a machine-readable severity to doctor results.
55. Add tests proving advisory checks cannot accidentally become hard failures.
56. Add tests proving hard checks cannot accidentally become advisory.
### MASTER — review engine and detector quality

57. Add a detector contract test for every rule in `data/rules.yml` that claims to be scannable.
58. Add a registry audit ensuring every detector ID is unique.
59. Add a registry audit ensuring every detector class resolves to an existing constant.
60. Add a registry audit ensuring every detector's declared file exists.
61. Add a registry audit ensuring every detector's severity is valid.
62. Add a registry audit ensuring every detector's tier is valid.
63. Add a registry audit ensuring `autofix` declarations agree with actual fixer availability.
64. Add a registry audit ensuring every principle-map rule ID resolves to a registry rule.
65. Add a registry audit for rule IDs that differ only by case or punctuation.
66. Add a registry audit for duplicate semantic descriptions.
67. Add a detector test ensuring a rule cannot report the same finding twice for one AST node.
68. Add a detector test ensuring line numbers remain stable after nested-node traversal.
69. Add a detector test for CRLF input.
70. Add a detector test for UTF-8 input containing non-ASCII identifiers.
71. Add a detector test for Ruby heredocs containing misleading source patterns.
72. Add a detector test for regex literals containing detector keywords.
73. Add a detector test for comments containing detector keywords.
74. Add a detector test for strings containing detector keywords.
75. Add a detector test for generated test fixtures containing detector keywords.
76. Add a global false-positive corpus and run every lexical rule against it.
77. Add a global false-negative corpus containing deliberately planted violations.
78. Require every new detector to contribute at least one positive and one negative fixture.
79. Require every autofix-capable rule to contribute before/after semantic-preservation tests.
80. Add an autofix rollback test that verifies the original source can always be restored.
81. Add an autofix idempotence test: applying the same fix twice must equal applying it once.
82. Add a detector determinism test across repeated runs.
83. Add a detector ordering test so registry ordering cannot change findings unexpectedly.
84. Add scan timing per detector rather than only aggregate scan timing.
85. Add a slow-detector budget with a measured baseline.
86. Add a detector timeout that produces a diagnostic rather than hanging the scan.
87. Add a rule proving a detector cannot mutate repository files during scanning.
### MASTER — AST and Ruby semantics

88. Expand the Prism visibility census into a reusable visibility model shared by all Ruby structural rules.
89. Add tests for `private`, `protected`, and `public` inside nested singleton/class scopes.
90. Add tests for visibility changes after `class << self`.
91. Add tests for visibility directives inherited across nested scopes.
92. Add tests for `private :foo` and `public :foo`.
93. Add tests for `private_class_method`.
94. Add tests for aliasing a method before changing visibility.
95. Add a rule detecting visibility declarations that reference nonexistent methods.
96. Add a rule detecting contradictory visibility declarations.
97. Add a rule detecting public APIs accidentally exposed by generated forwarding methods.
98. Add AST coverage for `define_method`.
99. Add AST coverage for `method_missing`.
100. Add AST coverage for `respond_to_missing?`.
101. Add AST coverage for `Forwardable`.
102. Add AST coverage for refinements.
103. Add AST coverage for singleton methods on expressions rather than named constants.
104. Add AST coverage for `prepend`.
105. Add AST coverage for `extend`.
106. Add a semantic check that distinguishes intentional abstract methods from broken overrides.
107. Add a test corpus for Liskov violations involving keyword arguments.
108. Add a test corpus for Liskov violations involving positional/keyword separation.
109. Add a test corpus for default-argument incompatibilities.
110. Add a test corpus for block-acceptance incompatibilities.
111. Add a test corpus for visibility narrowing in subclasses.
112. Add a rule for overriding methods while silently changing keyword semantics.
113. Add a rule for subclass methods that change accepted argument shape without an explicit contract.
114. Add a rule for `super` calls whose arguments accidentally differ from the parent signature.
### MASTER — architecture and dependency boundaries

115. Generate a stable namespace-to-directory ownership report from Zeitwerk.
116. Add a gate that prevents a constant from being defined in two Zeitwerk-owned files.
117. Add a gate that detects namespace files defining unrelated leaf constants.
118. Add a gate for namespace files whose body grows beyond their documented role.
119. Add a gate detecting require aggregators that can be replaced by Zeitwerk loading.
120. Audit every explicit `require_relative` for whether Zeitwerk already owns the dependency.
121. Audit every autoload ignore entry for whether the ignored file still needs the exception.
122. Add a test that every autoload ignore has a documented reason.
123. Add a test that every ownership declaration maps to an existing path.
124. Add a test that every owned path is reachable from exactly one owner.
125. Add a graph showing cross-boundary calls between `core`, `ground`, `review`, `io`, and `ops`.
126. Add a gate preventing newly introduced reverse dependencies between architectural layers.
127. Add a dependency whitelist for intentionally shared infrastructure.
128. Add a dependency blacklist for known forbidden directions.
129. Add a test proving the architecture graph is deterministic.
130. Add a compact architecture report suitable for `bin/check`.
131. Add a “why is this dependency allowed?” annotation mechanism with expiry dates.
132. Add a check for expired architectural exceptions.
133. Add a check that architectural exceptions name an owner.
134. Add a check that an exception has an explicit removal condition.
### MASTER — test quality

135. Re-measure the 69-file no-test figure in a clean worktree and record the exact definition beside the result.
136. Generate a machine-readable untested-leaf-constant report.
137. Rank untested files by production criticality rather than raw count.
138. Prioritize tests for code involved in deployment, permissions, SSRF, patching, and repository mutation.
139. Add mutation testing to a small representative subset of `lib/review`.
140. Add mutation testing to `lib/io`.
141. Add mutation testing to `lib/ops`.
142. Add mutation testing to the deployment/operator layer.
143. Add a test proving a mutated security decision fails.
144. Add a test proving a mutated patch application failure is detected.
145. Add a test proving a mutated Git status calculation fails.
146. Add a test proving a mutated SSRF URL classification fails.
147. Add a test proving a missing `require "uri"` cannot be hidden by a blanket rescue.
148. Add regression coverage for permission substring false positives such as `sudo` inside `pseudo`.
149. Add regression coverage for `patch(1)` failures reported on stdout.
150. Add regression coverage for untracked directories collapsing into one Git status line.
151. Add tests for worktrees where `.git` is a file rather than a directory.
152. Add tests for Git execution when the current process is itself inside a Git worktree.
153. Add tests proving snapshot paths never silently redirect to the user's Downloads directory.
154. Add tests for missing Git executable behavior.
155. Add tests for unknown commit state and ensure it cannot masquerade as a real SHA.
156. Add a test for clean-worktree-only ratchets explicitly distinguishing skipped from passed.
157. Add a CI summary that reports skipped tests separately from passed tests.
158. Add a CI guard preventing a growing skip count from going unnoticed.
159. Add a capability matrix explaining every environment-dependent skip.
160. Add a command to run only tests currently skipped by environment capability.
161. Add coverage for all operator/contributor test profiles.
### MASTER — ratchets, metrics, and measurement integrity

162. Make every ratchet record the measurement definition it uses.
163. Make every ratchet record the command that produced its current value.
164. Make every ratchet record the commit at which its baseline was established.
165. Make every ratchet record whether the worktree was clean.
166. Make ratchet measurements fail rather than silently returning zero on instrument errors.
167. Add a distinct `measurement_unavailable` state.
168. Add a distinct `measurement_skipped` state.
169. Prevent unavailable measurements from being interpreted as green.
170. Prevent skipped measurements from being interpreted as green.
171. Add a ratchet consistency test ensuring ceiling and measurement use identical path filters.
172. Add a ratchet consistency test ensuring file and directory keys cannot accidentally overlap.
173. Add a report of all ratchets whose ceiling was raised historically.
174. Require every ceiling raise to identify its purchased capability.
175. Require every ceiling raise to identify the exact measured cost.
176. Detect consecutive ceiling raises automatically.
177. Fail when a non-raiseable ceiling is breached.
178. Add a “paydown required” state distinct from generic failure.
179. Add a ratchet-drift report showing values that have not been measured recently.
180. Add an age threshold for stale measurements.
181. Add a clean-worktree prerequisite to baseline creation.
182. Add a test preventing a baseline from being recorded from a dirty tree.
183. Add an audit proving every metric has at least one consumer.
184. Remove metrics whose only consumer is historical prose.
185. Add a report of detectors that never affect a gate or decision.
186. Add a report of gates that never consume a detector.
187. Add a report of rules that exist solely to support obsolete tests.
### RAILS — platform foundation

188. Run a full route-to-controller-to-view audit across every RAILS app.
189. Run the route/view audit against mounted engines as well as top-level applications.
190. Add a route coverage report showing routes with no browser journey.
191. Add a browser journey for every public authentication flow.
192. Add browser coverage for session expiry.
193. Add browser coverage for CSRF rejection.
194. Add browser coverage for authorization rejection.
195. Add browser coverage for Turbo-frame navigation.
196. Add browser coverage for Turbo-stream updates.
197. Add browser coverage for non-JavaScript fallback paths.
198. Add browser coverage for mobile viewport navigation.
199. Add browser coverage for desktop keyboard navigation.
200. Add browser coverage for focus restoration after Turbo navigation.
201. Add browser coverage for modal open/close lifecycle.
202. Add browser coverage for browser back/forward after Turbo transitions.
203. Add a gate ensuring every interactive component has a no-JS or explicit degradation state.
204. Add a gate ensuring every form has a visible validation failure state.
205. Add a gate ensuring every destructive action has confirmation or equivalent safety.
206. Add a gate ensuring every asynchronous action has pending, success, and failure states.
207. Add a gate ensuring every loading indicator eventually resolves or reports failure.
208. Add a gate for orphaned Stimulus controllers.
209. Add a gate for Stimulus targets referenced in JS but absent from templates.
210. Add a gate for template targets referenced in JS but never consumed.
211. Add a gate for stale Stimulus controller registrations.
212. Add a gate for duplicate frontend component names.
213. Add a gate for CSS selectors that no current template emits.
### RAILS — shared layout and design system

214. Consolidate shared design tokens into one authoritative source.
215. Audit every app-specific color against the shared token system.
216. Audit every app-specific spacing value for duplication.
217. Audit typography declarations for duplicated font stacks.
218. Audit border radii for near-duplicate values.
219. Audit shadows and effects for forbidden or unnecessary visual complexity.
220. Add a token-consumption report showing unused design tokens.
221. Add a report showing hard-coded values that should use tokens.
222. Add a visual regression baseline for the shared shell.
223. Add a visual regression baseline for navigation.
224. Add a visual regression baseline for cards.
225. Add a visual regression baseline for forms.
226. Add a visual regression baseline for empty states.
227. Add a visual regression baseline for error states.
228. Add a visual regression baseline for mobile navigation.
229. Add a visual regression baseline for dark mode if supported.
230. Add a contrast audit for every shared component state.
231. Add an automated AAA/AA report without allowing the report itself to become a vanity metric.
232. Add keyboard-visible focus regression screenshots.
233. Add reduced-motion visual tests.
234. Add a density test for unusually sparse screens.
235. Add a density test for overloaded screens.
236. Add a maximum interactive-control distance rule for common workflows.
### RAILS — Brgen

237. Map the Brgen homepage into explicit information hierarchy zones.
238. Reduce competing primary calls to action on the homepage.
239. Establish one canonical global navigation model shared across Brgen sub-apps.
240. Make marketplace, takeaway, messenger, maps, dating, and playlist entry points visually coherent.
241. Add persistent identity/context when navigating between Brgen sub-apps.
242. Add consistent unread indicators across messenger and other notification surfaces.
243. Add a global notification center rather than app-specific notification silos.
244. Add a universal search entry point.
245. Add keyboard shortcut support for universal search.
246. Add recent-search persistence.
247. Add empty-state designs for every major Brgen collection.
248. Add offline/network-failure states for interactive Brgen surfaces.
249. Add optimistic UI only where rollback is deterministic.
250. Add explicit rollback tests for optimistic mutations.
251. Add mobile-first tests for the bottom navigation/tab model.
252. Add deep-link tests for every mounted Brgen sub-app.
253. Add authentication handoff tests between mounted apps.
254. Add session-sharing tests between mounted apps.
255. Add authorization boundary tests between mounted apps.
256. Add a Brgen performance budget for first meaningful interaction.
### RAILS — marketplace

257. Establish a marketplace page grammar: header, search, category rail, result controls, result cards, pagination, and trust information.
258. Create a canonical marketplace product-card component.
259. Make product-card density responsive rather than duplicating mobile and desktop markup.
260. Add product image aspect-ratio enforcement.
261. Add graceful handling for missing product images.
262. Add image loading and decoding performance tests.
263. Add price formatting tests for NOK edge cases.
264. Add seller identity presentation to every listing.
265. Add seller trust signals without exposing sensitive seller data.
266. Add listing condition presentation.
267. Add location/distance presentation.
268. Add listing timestamp/recency presentation.
269. Add favorite/watchlist interaction.
270. Add watchlist persistence tests.
271. Add saved-search support.
272. Add saved-search notification semantics.
273. Add category navigation that survives back/forward navigation.
274. Add filter state persistence in URLs.
275. Add sort state persistence in URLs.
276. Add canonical URL generation for marketplace searches.
277. Add pagination/cursor semantics that remain stable under new listings.
278. Add duplicate-listing detection.
279. Add seller/listing moderation states.
280. Add listing-report workflow.
281. Add listing expiration semantics.
282. Add relisting semantics.
283. Add sold/unavailable state propagation to search results.
284. Add stale-result handling when a listing disappears between search and detail.
285. Add concurrency tests for two users editing the same listing.
286. Add authorization tests proving sellers cannot mutate another seller's listing.
287. Add authorization tests proving buyers cannot mutate seller-only fields.
288. Add image abuse/oversized-upload limits.
289. Add SSRF-safe image ingestion if remote image URLs are accepted.
290. Add marketplace structured-data validation if public listing pages expose metadata.
291. Add marketplace SEO canonicalization tests.
292. Add marketplace accessibility journey tests.
293. Add marketplace keyboard-only journey tests.
294. Add marketplace narrow-mobile visual regression tests.
295. Add marketplace wide-desktop visual regression tests.
### RAILS — messenger

296. Define the messenger interaction model as explicit states rather than one large UI state.
297. Add tests for unread → read transitions.
298. Add tests for read receipts.
299. Add tests for typing indicators.
300. Add tests for reconnecting WebSocket sessions.
301. Add tests for duplicate incoming messages.
302. Add tests for out-of-order incoming messages.
303. Add tests for optimistic message sends.
304. Add tests for failed sends and retry.
305. Add tests for attachment upload failure.
306. Add message pagination tests.
307. Add conversation pagination tests.
308. Add scroll-position preservation tests.
309. Add “jump to newest” behavior tests.
310. Add keyboard navigation across conversations.
311. Add accessible naming for message actions.
312. Add moderation/report actions to the message UI where required.
313. Add message deletion semantics and tests.
314. Add conversation archive semantics and tests.
315. Add notification suppression when the active conversation is visible.
316. Add notification restoration when focus leaves the conversation.
317. Add reconnect backoff tests with an explicit maximum.
318. Add a bounded retry budget for messenger network operations.
319. Add a messenger memory-growth soak test.
320. Add a messenger DOM-growth test after thousands of messages.
321. Add a messenger mobile viewport regression suite.
### RAILS — takeaway and transactional flows

322. Define takeaway order state transitions as a finite state machine.
323. Add tests for every legal order transition.
324. Add tests proving illegal order transitions fail closed.
325. Add idempotency keys to externally repeatable order mutations.
326. Add duplicate-submission tests for order creation.
327. Add concurrent order-update tests.
328. Add timeout handling for unavailable vendors.
329. Add explicit order failure states in the UI.
330. Add retry semantics that cannot duplicate an order.
331. Add cart persistence tests across authentication changes.
332. Add cart expiry semantics.
333. Add price snapshot semantics so historical orders cannot change with current menu prices.
334. Add availability snapshot semantics.
335. Add vendor closure handling.
336. Add out-of-stock race tests.
337. Add totals reconciliation tests.
338. Add currency/rounding tests.
339. Add delivery-area validation tests.
340. Add address privacy tests.
341. Add order-history authorization tests.
342. Add customer/vendor boundary tests.
343. Add transaction rollback tests around multi-record order creation.
344. Add operational metrics for stuck orders.
345. Add a gate detecting orders stuck beyond their expected state duration.
### RAILS — data, security, and privacy

346. Inventory every controller parameter that reaches persistence.
347. Audit strong-parameter coverage across every app.
348. Add a gate for models accepting attributes not explicitly permitted.
349. Audit every raw SQL fragment.
350. Audit every SQL fragment involving user-controlled values.
351. Add an SQL-injection regression corpus.
352. Audit every URL fetched server-side.
353. Add SSRF tests for loopback IPv4.
354. Add SSRF tests for loopback IPv6.
355. Add SSRF tests for decimal/hex IP representations.
356. Add SSRF tests for DNS rebinding.
357. Add SSRF tests for redirects.
358. Add SSRF tests for link-local addresses.
359. Add SSRF tests for metadata-service addresses.
360. Audit every file upload path.
361. Add MIME/content-sniffing tests.
362. Add path traversal tests.
363. Add archive extraction traversal tests.
364. Audit every user-visible exception for secret leakage.
365. Add a secret-redaction test corpus.
366. Add a check preventing tokens/API keys from appearing in logs.
367. Add an audit of cookies and session configuration.
368. Add a session fixation regression suite.
369. Add authorization tests for every destructive controller action.
370. Add authorization tests for every administrative action.
371. Add rate-limit tests for authentication and expensive endpoints.
372. Add abuse-budget tests for search, uploads, and messaging.
373. Add privacy tests ensuring deleted users disappear from intended public surfaces.
### OPENBSD — production hardening

374. Add a post-deploy `relayd -n` validation before restart.
375. Add an automatic post-restart `rcctl check relayd`.
376. Add a deployment rollback path if relayd fails after application deployment.
377. Add a deployment check for every expected listening socket.
378. Add a deployment check for unexpected listening sockets.
379. Add a PF rule audit against the documented service topology.
380. Add a PF syntax check to deployment verification.
381. Add an `rcctl` service inventory to the deployment receipt.
382. Add an ownership audit for application runtime directories.
383. Add an ownership audit for daemon logs.
384. Add an ownership audit for daemon sockets.
385. Add permission checks for `.env`-style files.
386. Add a check that secrets are not world-readable.
387. Add a check that deploy scripts do not widen permissions.
388. Add pledge/unveil coverage for every privileged process.
389. Add tests proving expected filesystem accesses remain available after unveil.
390. Add tests proving unexpected filesystem accesses fail.
391. Add a documented minimal privilege profile for each long-running daemon.
392. Add a memory/CPU ceiling observation to the production health report.
393. Add a disk-space threshold check.
394. Add an inode-space threshold check.
395. Add a log-growth threshold check.
396. Add a stale-socket cleanup diagnostic.
397. Add a stale-PID diagnostic.
398. Add a boot-order dependency check between relayd and application daemons.
399. Add a reboot verification procedure that exercises every production endpoint.
### STUDIO — audio and creative tooling

400. Define a deterministic seed mode for every procedural Dilla engine render.
401. Add golden WAV regression renders for representative seeds.
402. Add an audio duration invariant.
403. Add sample-rate invariants.
404. Add channel-count invariants.
405. Add clipping detection to generated renders.
406. Add DC-offset detection.
407. Add silence/runaway-render detection.
408. Add peak/RMS/LUFS reporting.
409. Add a bounded render-time budget.
410. Add tests for missing optional audio dependencies.
411. Add tests for malformed sample files.
412. Add tests for zero-length samples.
413. Add tests for unusually long samples.
414. Add deterministic swing tests.
415. Add deterministic humanization tests.
416. Add seed-isolation tests proving one instrument's randomization does not alter another's sequence.
417. Add regression fixtures for the “Dilla pocket” timing distribution.
418. Add tests proving swing remains bounded under tempo changes.
419. Add tests proving tempo changes preserve intended musical duration.
420. Add tests for FM parameter stability.
421. Add tests for evolving modulation remaining bounded.
422. Add tests for continuous generation stopping cleanly.
423. Add tests for render cancellation.
424. Add tests for subprocess cleanup after cancellation.
425. Add a one-command smoke render for `STUDIO/dilla/live`.
426. Add a machine-readable render receipt.
427. Add an audio artifact checksum to deterministic fixtures.
428. Add a minimal dependency profile for headless rendering.
429. Add documentation mapping the Ableton writers to their generated artifacts.
### Cross-tree governance

430. Add a root inventory of every executable command in `MASTER`, `RAILS`, `OPENBSD`, and `STUDIO`.
431. Add a root inventory of every CI workflow and what it actually gates.
432. Add a check that every workflow has at least one meaningful failure condition.
433. Add a check for workflows that can succeed while their main command fails.
434. Add a check for swallowed workflow exit codes.
435. Add a check for workflows that mutate production state without an explicit environment guard.
436. Add a check that deployment workflows identify their target host.
437. Add a check that destructive workflows require an explicit operator input.
438. Add a root dependency map between the four trees.
439. Add a gate preventing new undeclared cross-tree dependencies.
440. Add a report of shared files consumed by multiple trees.
441. Add a report of shared files that are copied rather than referenced.
442. Add a duplication detector across Markdown operational instructions.
443. Add a duplication detector across shell deployment procedures.
444. Add a duplication detector across YAML configuration.
445. Add a check for configuration keys declared in multiple authoritative locations.
446. Add a check for constants duplicated across trees.
447. Add a check for command names documented differently in different trees.
448. Add a check for paths mentioned in documentation but absent from the repository.
449. Add a check for repository paths that are never documented where documentation is mandatory.
450. Add a generated `TREE.md` freshness check.
451. Add a generated command index.
452. Add a generated configuration-source index.
453. Add a generated “authority chain” report showing which file owns each major policy.
454. Add a single root `bin/check` entry point that delegates to each tree without duplicating logic.
455. Add a single root smoke command that exercises the minimum viable path of every tree.
456. Add a root failure report that preserves the first causal failure instead of only downstream symptoms.
457. Add a machine-readable handoff format containing commit, tests, known failures, drift, and next action.
458. Add a stale-handoff detector.
459. Add a stale-TODO-reference detector.
460. Add a detector for TODO items whose referenced file/path no longer exists, excluding intentionally historical references.
461. Add a detector for TODO items whose verification command no longer exists.
462. Add a detector for TODO items with no measurable completion condition.
463. Require every new TODO item to state either a path, command, metric, user-visible behavior, or explicit decision required.
464. Add a periodic backlog deduplication pass.
465. Add a periodic backlog “prove this still exists” pass.
466. Add a periodic backlog priority recalculation based on current architecture rather than age.
467. Add a rule that closed findings are not copied back into forward work without new evidence.
468. Add a rule that proposed work cannot claim a detector found something unless the detector was actually run.
469. Add a rule that production observations identify observation date and host.
470. Add a rule that every operational TODO distinguishes repository work from box/deployment work.
471. Add a rule that every security TODO has a negative test.
472. Add a rule that every performance TODO has a measured baseline.
473. Add a rule that every visual TODO has a screenshot/render acceptance criterion.
474. Add a rule that every architectural TODO names the dependency direction it intends to change.
475. Add a rule that every proposed deletion names its replacement behavior.
476. Add a rule that every proposed extraction states how its LOC budget changes.
477. Add a rule that every proposed new subsystem identifies its owner directory before implementation.
478. Add a final `/through` campaign that runs the complete repository against the additions above and removes any item whose premise fails measurement.

478 items. Re-measure before working. Closed findings stay closed.


## STUDIO/dilla mix and reference research — ChatGPT intake 2026-09-11

Closed 2026-09-13. The measuring half was built or refused, and the argument is
in `MASTER/DECISIONS.md`, "dilla Measures From Kept Takes, Not From An Intake".
One decision stays with the operator.

- **Sound changes the intake proposed.** A `ROUGH_HEWN` or `DENSE_EXPERIMENTAL`
  profile, a mastering stage split from the mix bus, stem-group routing,
  deliberate mono-source widening, per-channel strip variance, MPC-style shift
  timing, and sample-start offsets independent of drum timing each change how a
  take sounds. Decide which, if any, to try. Seams: `lib/outboard.rb`,
  `lib/console_strip.rb`, `lib/groove_engine.rb`, `DILLA_STYLE_DEFAULTS`.


## MASTER web UI — future-human face — ChatGPT intake 2026-09-11

Closed 2026-09-13 except the operator's look and voice and one check that needs
a browser on vm23. The argument is in `MASTER/DECISIONS.md`, "The Face Intake
Was A Design Brief, And The Design Is The Operator's".

- **Morphology.** Whether the face moves toward a far-future-human form — larger
  cranium, smaller lower face, wider orbits, seeded developmental asymmetry,
  slow drift, generations 0 to 4 — and how far; and any blind test of
  recognisability or perceived intelligence. Seams: geometry in
  `web/public/face.part1-3.txt`, `VOICE_IDLE_SIGNATURES` in `face.part1.txt`.
- **Expression, motion and layout.** Continuous affect instead of named
  expressions, a motion grammar with per-region time constants, speaking motion
  kept below lip-sync, states that read without colour, and a
  face-conversation-input hierarchy on one spacing, radius and duration scale.
  Seams: `face.part3.txt`, `face.part5.txt`, `face_semantics.js`, `face.css`.
- **How MASTER says technical text.** `Speech#clean_text` drops code blocks and
  links but speaks paths, identifiers and figures nearly as written. Whether to
  respell them, and any rate, pitch or pause policy beyond `voice.yml`
  `default_rate` and `default_pitch`, is a voice decision. Seams:
  `lib/voice/speech.rb`, `lib/voice/lexicon.rb`.
- **A real-browser smoke on ai.brgen.no.** `health_check.rb` proves TTS answers
  and `deploy_smoke_gate.rb` proves `face.runtime.js` exists; nothing proves the
  deployed face paints, speaks one phrase with moving visemes, and falls back to
  2D with WebGL off. Needs a browser on vm23, where rendered gates belong.


## layout_micro_refinement — ChatGPT intake 2026-09-11

Unmeasured. `RAILS/shared/design_tokens.yml`, `_typography.scss`, ScaleLint,
`layout_snapshots`, visual_contract, and one chrome already exist. Do not invent
a second token file. Apply the scale that is there. Look stays the operator’s:
colours, radii that change the paint, dating immersive chrome, playlist SF Mono,
recorded popover shadow, Kaufland copy-styling. A finding is a hypothesis.

### master_design_system

1. Establish one canonical spacing scale for MASTER and Brgen; replace arbitrary margins/padding with scale tokens.
2. Establish one canonical radius scale; remove one-off border-radius values.
3. Establish one canonical border hierarchy: structural, interactive, selected, disabled, destructive.
4. Establish one canonical elevation model; eliminate decorative shadows that do not communicate hierarchy.
5. Establish one canonical surface model: page, panel, elevated panel, interactive surface, overlay.
6. Establish one canonical content-width system; prevent each vertical from inventing unrelated max-widths.
7. Establish one canonical control-height scale for buttons, inputs, tabs, selects and compact controls.
8. Establish one canonical icon-size scale.
9. Establish one canonical avatar/media-size scale.
10. Establish one canonical typography scale rather than component-specific font sizes.
11. Establish one canonical line-height scale matched to the typography scale.
12. Establish one canonical text-width measure for readable prose.
13. Establish one canonical responsive breakpoint vocabulary.
14. Establish one canonical motion-duration scale.
15. Establish one canonical easing vocabulary.
16. Establish one canonical focus-ring treatment.
17. Establish one canonical disabled-state treatment.
18. Establish one canonical loading/skeleton treatment.
19. Establish one canonical empty-state treatment.
20. Establish one canonical error-state treatment.
21. Establish one canonical success/confirmation treatment.
22. Establish one canonical tooltip/popover treatment.
23. Establish one canonical modal/dialog geometry.
24. Establish one canonical drawer/sheet geometry.
25. Add design-token linting so new arbitrary values become measurable violations.
26. Add a token-usage report showing which CSS values remain outside the design system.
27. Add a duplicate-token detector for visually equivalent colors, spacing, radii and typography.
28. Collapse visually equivalent tokens rather than preserving historical names indefinitely.
### typography

29. Audit every Brgen vertical for typographic hierarchy rather than merely font-size hierarchy.
30. Make heading weight, size, line-height and spacing form one deliberate hierarchy.
31. Reduce unnecessary font-weight variation.
32. Reserve the strongest weight for genuinely important information.
33. Establish a clear distinction between navigation text, labels, metadata, body text and primary actions.
34. Reduce uppercase text where it harms readability.
35. Audit letter-spacing independently for headings, labels, buttons and metadata.
36. Prevent typography from becoming visually noisy through excessive bold text.
37. Establish a maximum readable line length for marketplace descriptions and community posts.
38. Establish compact measures for cards and dense transactional interfaces.
39. Ensure numerical information uses consistent alignment and typographic treatment.
40. Standardize price typography across marketplace and takeaway.
41. Standardize timestamp typography across messenger, posts, comments and notifications.
42. Standardize seller/shop/user metadata hierarchy.
43. Standardize secondary text contrast without allowing metadata to disappear.
44. Test Norwegian compound words and long labels at every responsive width.
45. Test typography with unusually long usernames, product names and marketplace titles.
46. Test typography with zero-width and empty states rather than designing only for populated content.
47. Ensure truncation always preserves semantic recognition.
48. Prefer multiline wrapping where truncation would hide important transactional information.
49. Ensure text truncation never produces unexplained layout jumps.
50. Audit icon-plus-text combinations for baseline alignment.
51. Audit button labels for consistent optical centering rather than mathematically equal padding.
52. Test font rendering at normal browser zoom, 125%, 150%, 200% and mobile text scaling.
53. Test the interface using system font fallback when the preferred font is unavailable.
54. Measure cumulative layout shift caused by font loading.
55. Remove typography choices that exist only because they looked good in one screenshot.
### optical_alignment

56. Add an optical-alignment pass after geometric alignment.
57. Correct icons that appear vertically misaligned despite equal CSS dimensions.
58. Correct asymmetric icon shapes that require optical rather than mathematical centering.
59. Audit circular avatars whose visual mass differs from their bounding box.
60. Audit buttons with text/icons whose perceived center differs from their flex center.
61. Audit cards where headings appear too close to one edge despite equal padding.
62. Audit image crops for perceived rather than mathematical centering.
63. Establish rules for optical inset compensation rather than scattered magic numbers.
64. Prefer component-level optical tokens over individual CSS exceptions.
### density

65. Define explicit density modes for Brgen: comfortable, standard and compact.
66. Make marketplace and takeaway intentionally denser than social/community surfaces.
67. Keep messenger dense enough for scanning without becoming visually cramped.
68. Keep landing/home surfaces calmer than transactional surfaces.
69. Prevent every vertical from independently choosing its own information density.
70. Measure information density using visible actions/content per viewport.
71. Test whether additional whitespace actually improves comprehension before retaining it.
72. Remove whitespace that merely separates elements without communicating hierarchy.
73. Preserve whitespace where it establishes grouping or reduces cognitive load.
74. Ensure density changes never alter the semantic hierarchy.
### cards

75. Stop treating every piece of content as a rounded card.
76. Classify components as surface, list row, card, panel, section or overlay.
77. Remove nested cards where a divider or spacing would communicate hierarchy better.
78. Remove redundant borders around already-separated surfaces.
79. Ensure card padding follows the spacing scale.
80. Ensure card title/body/action spacing follows one rhythm.
81. Establish maximum useful card complexity before content moves into a dedicated page.
82. Ensure card hover states do not cause layout movement.
83. Ensure card selection states are distinguishable without relying solely on color.
84. Ensure cards with different content types still share the same structural grammar.
85. Audit every “card within card” construction for unnecessary hierarchy.
### navigation

86. Reduce navigation choices visible simultaneously when they compete for attention.
87. Establish one primary-navigation pattern shared by Brgen verticals.
88. Establish one secondary-navigation pattern.
89. Establish one breadcrumb pattern where breadcrumbs are useful.
90. Make current location visually obvious without relying solely on color.
91. Make back-navigation predictable across mobile and desktop.
92. Prevent vertical-specific navigation from contradicting global Brgen navigation.
93. Ensure deep links retain enough contextual identity to explain where the user is.
94. Audit tab bars for excessive tab counts.
95. Replace overflowed tab rows with deliberate scrolling or grouped navigation.
96. Make navigation hierarchy match URL/application hierarchy.
### marketplace

97. Make product price the strongest visual element after the product image.
98. Make availability, condition and location immediately scannable.
99. Establish one consistent product-card anatomy.
100. Standardize image aspect-ratio handling.
101. Prevent seller metadata from competing visually with price.
102. Establish a consistent distance between price and primary transaction action.
103. Make filtering state persistent and visually explicit.
104. Make sort/filter controls occupy predictable locations.
105. Make search dominant without making the interface look like a generic search engine.
106. Establish consistent result-count treatment.
107. Make saved/favorite state persistent and unmistakable.
108. Make product comparison easier without introducing dashboard-like complexity.
109. Establish a consistent product-detail hierarchy: media → title → price → condition/availability → seller → action → details.
110. Make transactional actions sticky only when measurement shows meaningful benefit.
111. Ensure marketplace cards remain useful at narrow mobile widths.
112. Test dense marketplace grids against Kaufland-like retail scanning patterns without copying proprietary styling.
### takeaway

113. Make restaurant/shop identity immediately distinguishable from individual products.
114. Establish consistent food-image proportions.
115. Make delivery/pickup status visible before secondary metadata.
116. Make cart state persistent without overwhelming browsing.
117. Keep category navigation stable while scrolling.
118. Establish one consistent product-row anatomy.
119. Make price/add controls visually subordinate to product identity but immediately accessible.
120. Make unavailable items visually understandable without making the entire card look disabled.
121. Establish one cart-summary hierarchy.
122. Ensure restaurant/store information never gets visually mixed with product information.
123. Audit checkout for unnecessary decorative UI.
### messenger

124. Establish a true conversation-list density model rather than reusing generic Brgen cards.
125. Make unread state primarily typographic/structural, not decorative.
126. Establish one message-grouping rhythm.
127. Reduce repeated avatars/names when consecutive messages share an author.
128. Establish consistent timestamp visibility rules.
129. Make composer height predictable.
130. Prevent the composer from visually competing with messages.
131. Establish one attachment-preview anatomy.
132. Establish one reply/quote anatomy.
133. Make message actions discoverable without permanently exposing excessive controls.
134. Ensure message hover actions do not cause content movement.
135. Establish clear distinction between sent, received, system and failed messages.
136. Make failed-message state recoverable in-place.
137. Make typing/listening/recording states subtle rather than theatrical.
138. Ensure the messenger remains usable when JavaScript or realtime connectivity degrades.
### social / community

139. Establish one post-header hierarchy.
140. Reduce repeated metadata around posts.
141. Make author identity visually strong but not dominant over content.
142. Establish one reaction/action-row anatomy.
143. Ensure comments do not visually become a second unrelated application.
144. Establish nesting limits for replies.
145. Prevent deep indentation from destroying usable text width.
146. Establish one media-gallery treatment.
147. Ensure post media dominates when media is the content rather than decoration.
148. Establish one empty-feed treatment.
149. Make feed loading visually quiet.
### maps

150. Make map controls share the global Brgen control language.
151. Avoid allowing map-specific controls to become a visually separate application.
152. Establish one location-marker grammar.
153. Establish one selected-location treatment.
154. Establish one map-result-card anatomy.
155. Ensure overlays do not obscure important map content unnecessarily.
156. Make mobile map/list transitions predictable.
157. Ensure map controls remain usable at high browser zoom.
### dating

158. Remove generic dating-app visual tropes that conflict with Brgen identity.
159. Establish a consistent profile hierarchy.
160. Make identity, location and intent scannable before decorative profile information.
161. Ensure interaction controls have the same geometry as other Brgen primary actions.
162. Avoid introducing an independent design language for dating.
163. Ensure profile-media treatment shares the same image rules as marketplace/community.
### playlist / media

164. Establish consistent album/artwork geometry.
165. Standardize play controls with Brgen interaction conventions.
166. Make active-track state structurally obvious.
167. Avoid turning media controls into a separate visual operating system.
168. Establish compact and expanded player states.
169. Ensure player state survives navigation without layout instability.
### maps_and_location

170. Standardize location labels, distances and geographic metadata across every vertical.
171. Use one representation for “nearby,” “distance,” “area” and “exact location.”
172. Prevent each subapp from inventing independent location badges.
173. Make location uncertainty explicit where precision is intentionally reduced.
### cross_vertical_consistency

174. Inventory every duplicated UI component across Brgen verticals.
175. Identify visually equivalent components with different implementations.
176. Consolidate equivalent components before adding new variants.
177. Establish shared primitives for buttons, inputs, tabs, cards, lists, badges, avatars, media and menus.
178. Establish shared primitives for loading/error/empty states.
179. Establish shared primitives for pagination/infinite-scroll indicators.
180. Establish shared primitives for notifications and toasts.
181. Establish shared primitives for confirmation/destructive actions.
182. Establish shared primitives for date/time formatting.
183. Establish shared primitives for money/price formatting.
184. Establish shared primitives for distance/location formatting.
185. Establish shared primitives for user identity.
186. Ensure verticals specialize through information architecture, not arbitrary styling.
187. Detect when a vertical introduces a component that already exists elsewhere.
188. Prefer extending an existing primitive over creating a visually similar sibling.
189. Document intentional exceptions and require a reason for each.
### responsive_refinement

190. Treat mobile as a first-class composition rather than a compressed desktop.
191. Audit every breakpoint for hierarchy changes rather than only width changes.
192. Ensure primary actions remain reachable with one hand where appropriate.
193. Prevent horizontal scrolling except where it is intentional.
194. Test long Norwegian words at every breakpoint.
195. Test keyboard navigation independently of pointer interaction.
196. Test touch targets at minimum usable dimensions.
197. Ensure sticky elements never cover content or focused controls.
198. Ensure viewport-height changes on mobile do not break composers, carts or dialogs.
199. Test browser chrome expansion/collapse effects on full-height layouts.
200. Test landscape mobile layouts.
201. Test large desktop displays without allowing content to become excessively stretched.
### motion

202. Define motion as a hierarchy rather than adding transitions globally.
203. Reserve animation for state change, spatial relationship or feedback.
204. Remove transitions that merely make static UI feel “slick.”
205. Establish motion duration by interaction importance.
206. Establish reduced-motion equivalents for every meaningful animation.
207. Ensure hover animation never communicates information unavailable to keyboard users.
208. Ensure loading animation has bounded visual complexity.
209. Prevent multiple nested animations from synchronizing into visual noise.
210. Establish a maximum simultaneous motion budget.
211. Audit page transitions for unnecessary animation.
### visual_noise_reduction

212. Remove decorative gradients that do not communicate hierarchy.
213. Remove ornamental borders that do not communicate structure.
214. Remove redundant badges.
215. Remove redundant icons.
216. Remove repeated labels where position already communicates meaning.
217. Remove shadows whose only purpose is aesthetic decoration.
218. Remove duplicated status indicators.
219. Remove competing accent colors.
220. Remove one-off illustrations where typography or spacing communicates the same state.
221. Apply “perfection is subtraction” as an explicit UI review criterion.
### accessibility_as_design_system

222. Make focus states part of the visual language rather than an accessibility afterthought.
223. Ensure every state has a non-color representation where necessary.
224. Ensure contrast is preserved across all surface combinations.
225. Ensure text remains understandable at 200% zoom.
226. Ensure interactive controls have predictable keyboard order.
227. Ensure dialogs establish focus and return it correctly.
228. Ensure dynamic content changes are announced appropriately.
229. Ensure reduced-motion does not remove semantic feedback.
230. Ensure screen-reader labels do not diverge from visible terminology.
231. Audit icon-only controls for accessible names.
### design_system_validation

232. Add automated detection for arbitrary spacing values.
233. Add automated detection for arbitrary radii.
234. Add automated detection for arbitrary colors.
235. Add automated detection for arbitrary typography values.
236. Add automated detection for duplicate component styles.
237. Add automated detection for inconsistent control heights.
238. Add automated detection for inconsistent icon sizing.
239. Add automated detection for inconsistent focus states.
240. Add automated detection for inconsistent disabled states.
241. Add visual regression snapshots for every major Brgen vertical.
242. Add representative screenshots for desktop, tablet and mobile.
243. Add “dense,” “normal” and “empty” fixture states.
244. Add long-content fixtures using Norwegian text.
245. Add pathological-content fixtures: long usernames, prices, titles, filenames and URLs.
246. Compare visual regressions by semantic region rather than whole-page pixel difference alone.
247. Record intentional visual differences as explicit design-system exceptions.
248. Fail validation when a new component introduces an unregistered design token.
249. Fail validation when equivalent components diverge without an explicit exception.
### MASTER_alignment

250. Map each visual-system rule to the corresponding MASTER law.
251. Treat duplicated visual constants as SINGULARITY violations.
252. Treat arbitrary component-specific styling as ABSTRACTION violations when an existing primitive covers the same need.
253. Treat unnecessary decoration as DENSITY violations.
254. Treat excessive nesting and indirection as LINEARITY violations.
255. Treat visually unrelated controls placed far from their semantic content as PROXIMITY violations.
256. Treat fragile responsive exceptions as ROBUSTNESS violations.
257. Add a UI `/sweep` that reports these violations before visual redesign work is accepted.
258. Make the UI sweep recursive across every Brgen vertical.
259. Require evidence before declaring a layout improvement complete.
260. Compare visual changes against the previous implementation rather than only the desired mockup.
261. Prefer deletion/consolidation before adding another component or token.
262. Require every new visual abstraction to have at least two real consumers unless there is a documented reason otherwise.
263. Keep design-system exceptions measurable and searchable.
264. Add a final “why does this exist?” pass to every major UI change.

264 items. Prefer deletion/consolidation. Do not restyle from this file.


## master_cli_dmesg_model — ChatGPT intake 2026-09-11

Unmeasured. `NO_ASCII_DECORATION` and `Trace::Dmesg` already exist; ChatController
dmesg is a second door (restructure 17). Default CLI is already a log, not a TUI.
Do not add a fake kernel boot, a second execution engine, or progress bars.
One event stream; text by default, JSON on request. A finding is a hypothesis.

### master_cli_dmesg_model

1. Model normal CLI output as an append-only execution trace rather than a presentation dashboard.
2. Make every important event express `subsystem: fact`.
3. Prefer facts over prose explanations.
4. Prefer topology and relationships over indentation.
5. Prefer stable subsystem names over visual section headers.
6. Prefer instance identifiers where multiple workers/components exist.
7. Make execution hierarchy visible through names and relationships rather than nested UI.
8. Avoid boxes, banners, decorative separators and dashboard panels in default output.
9. Avoid progress bars in default output.
10. Avoid spinners in default output.
11. Avoid animated terminal repainting in default output.
12. Avoid “AI assistant” presentation language.
13. Avoid narrating obvious operations as sentences.
14. Avoid redundant `starting...`, `working...`, `done!` chatter.
15. Emit a line when a meaningful subsystem state changes.
16. Do not emit a line merely because a method was called.
17. Do not emit a line merely because an internal object changed.
18. Preserve raw evidence where the evidence itself is useful.
### subsystem grammar

19. Define canonical subsystem names for MASTER execution.
20. Use short stable names such as `master`, `repo`, `config`, `rules`, `soul`, `workflow`, `scan`, `sweep`, `council`, `git`, `test`, `patch`, `web`, `tts`, `error`.
21. Allow subsystem instances where parallel or nested execution makes them useful.
22. Keep subsystem identifiers stable across releases.
23. Make subsystem names grep-friendly.
24. Make subsystem names machine-parseable without requiring JSON.
25. Avoid verbose class/module names in ordinary output.
26. Avoid implementation-specific names unless debugging is enabled.
### fact grammar

27. Prefer `rules: loaded 187`
28. Prefer `scan: 412 files`
29. Prefer `violations: 3`
30. Prefer `git: dirty`
31. Prefer `patch: 7 files`
32. Prefer `test: 42 passed`
33. Prefer `tts: ready`
34. Prefer `web: face runtime loaded`
35. Avoid `MASTER has successfully loaded 187 rules`.
36. Avoid `We are now scanning 412 files`.
37. Avoid redundant natural-language narration.
### topology

38. Represent MASTER workflow relationships explicitly.
39. Make `scan at repo`, `rules at config`, `validation at workflow` relationships available where useful.
40. Treat the CLI trace as an observable execution topology.
41. Make parent/child relationships reconstructable from emitted facts.
42. Avoid visual nesting where semantic relationships can express the same information.
43. Ensure a log excerpt remains interpretable when copied without its preceding lines.
### boot

44. Design startup as a compact boot trace.
45. Report repository identity.
46. Report effective configuration sources.
47. Report constitutional sources.
48. Report runtime identity.
49. Report model/provider identity when relevant.
50. Report initial invariants.
51. Emit `master: ready` only after the boot invariants pass.
52. Do not print a startup banner.
53. Do not print an ASCII logo.
54. Do not print a version splash screen.
### workflow_trace

55. Represent Discover → Analyze → Ideate → Design → Implement → Validate → Deliver → Learn as trace events.
56. Enter each phase with one deterministic event.
57. Emit only meaningful phase-local facts.
58. Record phase completion only after its completion criteria pass.
59. Record phase failure at the point of failure.
60. Make the final trace reconstruct the workflow without a separate progress UI.
61. Preserve chronological ordering.
62. Avoid re-rendering previous output.
### counts

63. Use counts where they communicate concrete evidence.
64. Prefer `scan: 412 files`.
65. Prefer `rules: 187 active`.
66. Prefer `test: 42 passed, 0 failed`.
67. Prefer `violations: 3 unresolved`.
68. Avoid percentage completion when completion cannot be measured honestly.
69. Avoid arbitrary “progress” numbers generated merely to make the CLI feel active.
70. Never display `100%` until the underlying operation is actually complete.
### errors

71. Make errors follow the same `subsystem: fact` grammar as successful output.
72. Make the failed subsystem immediately identifiable.
73. Include the actual failing resource.
74. Include the underlying reason.
75. Include recovery information only when it is deterministic.
76. Avoid dramatic error formatting.
77. Avoid color-dependent error semantics.
78. Preserve the original exception in debug mode.
79. Keep normal errors concise.
### warnings

80. Make warnings factual rather than conversational.
81. Distinguish advisory warnings from blocking conditions.
82. Include the affected subsystem.
83. Include the affected path/resource.
84. Avoid warning banners.
85. Avoid repeating the same warning on every dependent operation.
### paths

86. Standardize path formatting.
87. Prefer paths relative to the MASTER repository when that improves readability.
88. Use absolute paths only when necessary to disambiguate.
89. Preserve exact paths in machine-readable output.
90. Make paths directly copyable into shell commands.
91. Avoid shortening paths in a way that destroys identity.
### repeated events

92. Preserve repeated events when repetition itself is evidence.
93. Collapse repeated noise only when it carries no diagnostic value.
94. Never deduplicate genuine hardware/runtime failures merely for prettier output.
95. Provide aggregation only as an optional presentation mode.
96. Keep default output faithful to execution.
### silence

97. Make successful low-level operations silent when their result is not decision-relevant.
98. Treat silence as a valid success state.
99. Avoid emitting “ok” for every operation.
100. Avoid emitting “complete” for every subtask.
101. Avoid progress chatter merely to reassure the user that MASTER has not frozen.
102. For long-running operations, emit sparse liveness facts only when needed.
### terminal_independence

103. Make default output correct when piped through `cat`.
104. Make default output correct when piped through `less`.
105. Make default output correct when redirected to a file.
106. Make default output correct over SSH.
107. Make default output correct on narrow terminals.
108. Make default output correct without color.
109. Make default output correct without cursor control.
110. Make default output useful after losing the first half of the terminal buffer.
### ansi

111. Make ANSI formatting optional.
112. Make monochrome output semantically complete.
113. Respect `NO_COLOR`.
114. Disable ANSI when stdout is not a TTY.
115. Never encode semantic state exclusively through color.
116. Keep the default palette extremely small.
### dmesg_mode

117. Add an explicit `--dmesg`/trace presentation mode only if a second presentation is actually necessary.
118. Make the canonical default already conform to the dmesg grammar where practical.
119. Do not create a second execution engine merely to support dmesg formatting.
120. Render the same underlying event stream through human and machine presenters.
121. Ensure dmesg presentation is append-only.
122. Ensure dmesg presentation never rewrites previous lines.
### machine_trace

123. Define an internal event representation underneath CLI rendering.
124. Give each event a timestamp/sequence only when needed.
125. Give each event a subsystem.
126. Give each event an event type.
127. Give each event a severity.
128. Give each event structured attributes.
129. Render those events as terse text by default.
130. Render the same events as JSON when requested.
131. Ensure human and JSON output cannot disagree about execution state.
### openbsd_fidelity

132. Study actual OpenBSD dmesg grammar rather than approximating its appearance.
133. Preserve the characteristic `device at parent` relationship where it maps naturally to MASTER.
134. Preserve terse comma-separated facts.
135. Preserve stable subsystem naming.
136. Preserve chronological discovery.
137. Preserve repeated lines when operationally meaningful.
138. Preserve precise error messages.
139. Avoid copying kernel-specific terminology where it has no semantic equivalent.
140. Do not turn MASTER into a fake kernel boot log.
141. Use dmesg as a behavioral/presentation reference, not cosplay.
### self_test

142. Add golden traces for successful canonical MASTER execution.
143. Add golden traces for constitutional failure.
144. Add golden traces for rule violations.
145. Add golden traces for Git failure.
146. Add golden traces for model/provider failure.
147. Add golden traces for partial execution.
148. Add golden traces for interrupted execution.
149. Assert deterministic event ordering.
150. Assert no decorative output in default mode.
151. Assert no ANSI output under non-TTY execution.
152. Assert stderr/stdout separation.
153. Assert correct exit status for each terminal state.
### final_constraint

154. Review every CLI line with one question: “Would this line exist in a good system diagnostic trace?”
155. Delete lines whose only purpose is to make the program feel busy.
156. Delete lines whose only purpose is emotional reassurance.
157. Delete lines that merely repeat the command being executed.
158. Delete formatting that competes with the information.
159. Preserve lines that establish topology, state, evidence or failure.
160. Make the CLI feel like a system revealing itself rather than an application performing for the user.

160 items. Would this line exist in a good system diagnostic? If not, delete it.


## pub4 subtraction and entropy — ChatGPT intake 2026-09-11

Unmeasured repo-wide pass: what should exist, what should disappear, what should
become simpler. `operator gate`, sprawl census, FILE_SPRAWL, restructure “one job,
one door,” and soul `perfection is subtraction` already exist. Do not invent a
second CI in git hooks, rewrite history for cosmetics, merge trees for visual
similarity, or LAYER_CAKE. If two things mean the same thing, why do both exist?
If complexity rises faster than capability, the next work is subtraction.
A finding is a hypothesis.

### Remove / consolidate

1. Delete obsolete compatibility layers once their consumers are gone.
2. Remove dead files, dead constants, dead methods and dead configuration.
3. Remove duplicate YAML/JSON registries.
4. Remove duplicate implementations of the same concept across MASTER/RAILS/OPENBSD/STUDIO.
5. Remove historical migration code that no longer participates in startup/runtime.
6. Remove stale TODO items that describe already-completed work.
7. Remove TODO items whose premise has been disproven by measurement.
8. Remove generated artifacts from source when they can be deterministically rebuilt.
9. Remove manually maintained generated files where safe.
10. Remove unused dependencies from every Gemfile/package manifest.
11. Remove dependencies that duplicate Ruby/Rails standard functionality.
12. Remove abandoned experiments rather than preserving them indefinitely “just in case.”
13. Remove compatibility aliases with zero remaining callers.
14. Remove obsolete environment variables.
15. Remove configuration values that have only one possible value.
16. Remove wrapper methods that add no semantic value.
17. Remove one-line abstractions that merely rename another operation.
18. Remove defensive code for impossible states once the invariant is enforced centrally.
19. Remove duplicated validation between adjacent layers where one authoritative validation point is sufficient.
20. Remove decorative CLI/UI machinery that doesn't expose useful state.
21. Remove redundant logging.
22. Remove noisy debug logging from normal execution.
23. Remove duplicate tests that exercise identical behavior without adding coverage.
24. Remove fixtures that encode obsolete behavior.
25. Remove obsolete documentation that conflicts with actual behavior.
26. Remove stale references to deleted files such as old `axioms.yml`-style paths.
27. Remove abandoned branches/worktrees/scripts from the repository where they have no operational purpose.
28. Remove “future work” language for work that is already implemented.
29. Remove speculative abstractions before they acquire consumers.
### Simplify architecture

30. Establish one canonical configuration-loading path.
31. Establish one canonical repository/root discovery mechanism.
32. Establish one canonical runtime context object.
33. Establish one canonical result/error representation.
34. Establish one canonical violation representation.
35. Establish one canonical rule representation.
36. Establish one canonical workflow-phase representation.
37. Establish one canonical model/provider representation.
38. Establish one canonical subprocess execution layer.
39. Establish one canonical filesystem abstraction where abstraction is actually justified.
40. Establish one canonical command/event representation.
41. Establish one canonical path-normalization policy.
42. Establish one canonical logging/event emission mechanism.
43. Establish one canonical timeout policy.
44. Establish one canonical retry policy.
45. Establish one canonical cancellation mechanism.
46. Establish one canonical concurrency policy.
47. Establish one canonical temporary-directory policy.
48. Establish one canonical cleanup policy.
### Dependency hygiene

49. Produce a complete dependency inventory for each application.
50. Identify dependencies used by only one trivial feature.
51. Identify dependencies whose functionality overlaps.
52. Identify transitive dependencies that can be eliminated by changing one direct dependency.
53. Verify every runtime dependency has an actual runtime consumer.
54. Verify development/test dependencies aren't loaded in production.
55. Establish dependency update policy.
56. Record intentionally pinned versions and why.
57. Detect abandoned gems/packages.
58. Detect duplicate libraries solving the same problem.
59. Measure startup cost of heavyweight dependencies.
60. Measure memory impact of major dependencies.
61. Test clean installation from an empty environment.
62. Test deployment with only declared dependencies.
63. Remove accidental host-machine dependencies.
### Ruby quality

64. Run a whole-repository Ruby syntax pass.
65. Run a whole-repository parser/AST pass.
66. Establish one Ruby formatting/style source of truth.
67. Detect methods with excessive branching.
68. Detect excessive method length.
69. Detect excessive class/module size.
70. Detect excessive nesting.
71. Detect high fan-out classes.
72. Detect circular dependencies.
73. Detect constants referenced across inappropriate boundaries.
74. Detect private APIs being used externally.
75. Detect accidental public methods.
76. Audit `rescue StandardError`.
77. Audit bare `rescue`.
78. Audit exception swallowing.
79. Audit `ensure` correctness.
80. Audit subprocess handling.
81. Audit shell interpolation.
82. Audit filesystem race conditions.
83. Audit temporary-file handling.
84. Audit encoding assumptions.
85. Audit timezone assumptions.
86. Audit implicit global state.
87. Audit mutable constants.
88. Audit thread lifecycle.
89. Audit unbounded queues.
90. Audit unbounded loops.
91. Audit implicit network calls.
92. Audit methods whose names don't match their side effects.
### Rails quality

93. Audit controllers for business logic.
94. Audit models for excessive responsibilities.
95. Audit service objects for abstraction without justification.
96. Audit callbacks for hidden side effects.
97. Audit concerns for accidental coupling.
98. Audit serializers/presenters/view models for duplication.
99. Audit routes for obsolete endpoints.
100. Audit jobs for retry/idempotency correctness.
101. Audit mailers for stale templates.
102. Audit ActiveRecord queries for N+1 behaviour.
103. Audit unnecessary eager loading.
104. Audit unnecessary database round trips.
105. Audit missing indexes based on actual query patterns.
106. Audit unused indexes.
107. Audit database constraints vs application-only validation.
108. Audit migrations for historical cruft.
109. Audit authorization boundaries.
110. Audit authentication assumptions.
111. Audit CSRF/session/security defaults.
112. Audit caching correctness and invalidation.
113. Audit Solid Queue/Cache/Cable usage and lifecycle.
114. Audit ActionCable channels for subscription cleanup.
115. Audit background jobs for duplicate execution.
116. Audit all external requests for timeouts.
### Security

117. Full secret/credential scan.
118. Full shell-injection scan.
119. Full command-injection scan.
120. Full path-traversal scan.
121. Full SSRF scan.
122. Full unsafe-deserialization scan.
123. Full HTML/ERB injection scan.
124. Full SQL construction scan.
125. Full URL handling scan.
126. Full file-upload scan.
127. Full authorization matrix.
128. Full session/cookie configuration review.
129. Full CORS review.
130. Full CSP review.
131. Full security-header review.
132. Full dependency vulnerability audit.
133. Verify production error responses don't leak internals.
134. Verify logs don't leak secrets/tokens/PII.
135. Verify debug endpoints cannot become production endpoints.
136. Verify development-only routes/assets are unreachable in production.
137. Add regression tests for every discovered security boundary.
### Testing

138. Measure branch coverage where useful.
139. Measure mutation-testing value on critical logic.
140. Identify untested failure paths.
141. Identify tests that only test implementation details.
142. Identify tests that pass while the feature is broken.
143. Add contract tests between subsystems.
144. Add property tests for parsers/configuration.
145. Add fuzzing for hostile inputs.
146. Add concurrency tests where state is shared.
147. Add timeout tests.
148. Add cancellation tests.
149. Add retry tests.
150. Add partial-failure tests.
151. Add malformed-data tests.
152. Add empty-repository tests.
153. Add huge-repository tests.
154. Add low-memory tests.
155. Add offline tests.
156. Add fresh-install tests.
157. Add production-like deployment smoke tests.
158. Add regression fixtures for every previously fixed serious bug.
### Performance

159. Boot-time benchmark.
160. CLI startup benchmark.
161. Rails boot benchmark.
162. First-response latency.
163. Streaming latency.
164. Database query budget.
165. Browser first meaningful render.
166. Browser JS execution budget.
167. Face/WebGL frame budget.
168. TTS startup budget.
169. Memory baseline.
170. Repository scan throughput.
171. Large-repository scaling test.
172. Large-file scaling test.
173. Concurrent-user baseline.
174. Background-job throughput.
175. Identify performance regressions in CI.
176. Don't optimize measured non-problems.
### Operational reliability

177. Every network request gets a timeout.
178. Every long-running operation gets cancellation semantics.
179. Every background worker has bounded lifetime.
180. Every queue has bounded behaviour.
181. Every retry has a limit/backoff policy.
182. Every external dependency has a degraded mode where practical.
183. Every daemon has clean shutdown.
184. Every temporary resource has deterministic cleanup.
185. Every deployment has a rollback path.
186. Every migration has failure/recovery considerations.
187. Every production process exposes enough diagnostics to identify failure without attaching a debugger.
### OpenBSD / deployment

188. Rebuild a machine from zero using only repository documentation.
189. Verify every documented package is actually required.
190. Verify every service has one owner/configuration source.
191. Audit `rc.d`/`rcctl` lifecycle.
192. Audit `pf` rules.
193. Audit `relayd`.
194. Audit TLS renewal.
195. Audit DNS configuration.
196. Audit filesystem permissions.
197. Audit service users/groups.
198. Audit `doas` rules.
199. Audit pledge/unveil boundaries.
200. Test reboot recovery.
201. Test service restart recovery.
202. Test certificate renewal.
203. Test disk-full behaviour.
204. Test memory pressure.
205. Test network interruption.
206. Test application crash/restart.
207. Test log rotation.
208. Document the minimum viable production installation.
### Documentation

209. Every operational document gets an executable verification command.
210. Every architectural document names the actual files implementing it.
211. Remove documentation describing nonexistent architecture.
212. Remove duplicate architecture documents.
213. Make README claims mechanically testable where practical.
214. Record invariants separately from implementation details.
215. Record deliberate deviations from defaults.
216. Add “why” only where the reason isn't obvious from code.
217. Delete explanations that merely restate code.
218. Keep historical archaeology separate from current architecture.
219. Date/version genuinely historical decisions.
220. Make generated documentation obviously generated.
### Git hygiene

221. Identify commits that introduced dead architecture.
222. Identify reverted/reimplemented features.
223. Identify files repeatedly rewritten without converging.
224. Identify accidental generated-file commits.
225. Identify large binaries/assets that don't belong in Git.
226. Identify enormous commits that should have been decomposed.
227. Identify misleading commit messages.
228. Establish commit-message conventions only if they provide actual value.
229. Add pre-commit checks only for cheap/high-value invariants.
230. Avoid turning Git hooks into a second CI system.
231. Preserve useful archaeology; don't rewrite history merely for cosmetic cleanliness.
### Repository topology

232. Count files by subsystem.
233. Count LOC by subsystem.
234. Count dependencies by subsystem.
235. Count cross-subsystem imports/references.
236. Build a dependency graph.
237. Detect cycles.
238. Detect isolated code.
239. Detect “god directories.”
240. Detect directories with only one meaningful file.
241. Detect files with suspiciously high fan-in/fan-out.
242. Detect concepts appearing in multiple trees.
243. Identify candidates for consolidation.
244. Identify boundaries that should remain separate.
245. Measure whether `MASTER`, `RAILS`, `OPENBSD`, and `STUDIO` actually benefit from sharing code.
### subtraction pass

246. What can be deleted?
247. What can be merged?
248. What can become data instead of code?
249. What can become one source of truth?
250. What can become a standard-library call?
251. What can become a test instead of runtime machinery?
252. What can become an invariant instead of defensive code?
253. What can disappear because the underlying problem no longer exists?

### periodic architectural entropy audit

254. Measure files, LOC, dependencies, duplicate concepts, cross-boundary references, dead code, configuration sources, and special cases against capabilities, coverage, reliability, performance, and maintainability. Prefer subtraction when complexity outruns capability.

254 items. Capability first; then delete.

---

## Measured subtraction candidates — 2026-09-11

Continuation of the entropy pass. These have a path. Verify the second caller before deleting the first.

1. **Unwired slash tables — verified, and the proposed fix would break five live
   commands.** The claim is true: `CommandRegistry.build` merges
   `control_commands` and nothing else, `build_fast` returns status and help,
   and `slash_commands` is built from `HELP_TOPICS` — so `memory_commands`,
   `system_commands` and `media_commands` are required at the top of
   command_registry.rb and reachable from no path a person can type. They have
   been unreachable since `7c23a5ee5` (2026-08-17, "slash surface is a sentence
   and eight verbs"): the merge went then and the tables stayed. Help advertises
   twelve verbs and none of them is one of these.

   Deleting the three FILES breaks `/commit`, `/pair`, `/doctor`, `/rules` and
   `/tree`. Measured by doing it: those five dispatchers live in
   system_commands.rb beside the dead table, and `build` calls them by symbol —
   `command(:dispatch_doctor, root)` — so a grep for the table's name says
   nothing about them. `memory_search` is the same shape in memory_commands.rb,
   with three callers in context_provider and cohesion.

   The subtraction is method-level, and it needs reachability from a live root
   rather than "has a caller": almost every dispatcher in these files is called
   by its own table, so a caller census reads the dead set as live by
   circularity. `code_reach` answers this at file granularity and reads 0 dead
   files of 405, which is why nothing has caught it.

And it is seven tables, not three. `agent_commands`, `core_commands`,
`reach_commands` and `work_commands_extra` have no call site anywhere under
lib, web, bin or tools; media, memory and system are called only by tests.
`domain_commands`, `work_commands` and `work_commands_status` are the three
that are reached. `test_command_registry_dispatch` pins that set so an eighth
cannot join it quietly, and asserts that every symbol `build` dispatches
names a public method — the guard that would have caught the near-miss above
the moment it happened, where the whole suite stayed green.

   `test_capture_command_is_registered` asserts that the table contains
   "capture", not that the table reaches the registry, so it has passed for
   every one of those 25 days. Fix the test first — assert reachability through
   `CommandRegistry.build` — and it will name the dead set for you.
2. **`mask.js` — deleted 2026-09-11.** Superseded by face.js; `visual_limits.test.mjs` now only names `cognition_ecology.js`.
3. **`examples.html.erb` — a documentation file read as a view, and my first
   verdict on it was wrong.** I checked `MASTER/web/app/views/chat/` and called
   it gone; the item means `RAILS/shared/frontend/examples.html.erb`, which
   exists. backlog_triage caught my error by resolving the basename.

   It is not unmounted in the defect sense. Its first line reads "Copy selected
   examples into each app" — a snippet library, so nothing rendering it is the
   design. The assertion on it was redundant rather than misplaced: the line
   above it in `deploy_backlog_test` already asserts
   `shared/app/views/shared/_toast.html.erb`, which is the real artifact, so
   the second line proved that the documentation documents what it documents.
   Removed, with the reason in its place.

   The finding underneath is larger and stays open: nothing renders the toast
   partial either. `stimulus_boot.js:69` registers `["toast", Notification]`
   and no view in any app renders `shared/toast`, so the component is wired at
   the JavaScript end and reached from nowhere. Choosing where a toast appears
   is design work.
4. **Two `WebPushJob`s, and "one class" is false — but reading them side by
   side found a real bug.** `WebPushJob` takes a `notification_id`, builds a
   payload with a `tag` and a target path, and sends through `Webpush`
   directly; `Shared::WebPushJob` takes `user_id, title:, body:, url:` and
   delegates to `Shared::Pushable.deliver_now`. Different signatures,
   different senders, both reached — brgen's from `Notification#deliver`,
   shared's from `Pushable.push_to`. Folding them is a payload question
   (`tag:`, `urgency:` and `target_path` have no home in `Pushable`), not a
   duplicate-file cleanup.
   What the comparison did find is fixed: brgen destroyed the subscription on
   `Webpush::Unauthorized`, which is 401/403 — our VAPID credentials, failing
   identically for every row — so one bad key rotation unsubscribed the whole
   city, irreversibly. `Pushable` never listed it. The divergence was one
   rescue clause.
5. **`futurism` — the claim is false.** `futurize` appears in three ERB files,
   so the pin has a reader. Whether one lazy index is worth a gem is a
   different question from whether it is wired, and it is wired.
6. **`bin/crate` writes `dilla/crate/`.** Directory gone; engine reads `samples/`. Delete or retarget.
7. **Fixed 2026-09-12.** `OPENBSD/restore_litestream.sh`. Three separate passes
    asked for this rename, which is what a real defect looks like from outside.
    Its first line now reads "NOT the disaster-recovery script — use
    OPENBSD/bin/dr-pull for that", and the paragraph under it says why: vm23 has
    no litestream binary and no replicas, so the old name promised recovery the
    file cannot deliver, under exactly the name somebody reaches for in an
    emergency.
8. **Three atomic writes.** `Io::AtomicWrite` fsyncs; World and Live do not. One helper.
9. **Two PathGuards.** Prefix vs ancestor-realpath. One module, the strong check.
10. **`ChatController#dmesg` vs `Trace::Dmesg`.** One.
11. **`VoteReflex` vs `votes#create.turbo_stream`.** Keep the stream.
12. **Host vs shared notifications controllers.** One.
13. **Marketplace vs takeaway `_nav_bar`.** One partial.
14. **Fixed 2026-09-12.** The inline block is `shared/app/assets/stylesheets/_site_legal.scss`, moved with every value untouched — measured on brgen.no/privacy before and after, `.legal-prose` is 724.397px wide and its h1 is 28.8px/33.12px either way. Snapping those values onto the scales is a separate decision and the operator's.
15. **`.reading-column` / `.form-measure` — deliberate, and said so.** No view
    wears either. `css_coverage_lint.rb:96` records them as opt-in measure
    classes "worn by tokens, not yet by every view", so this is a decision
    already taken rather than residue. Wearing them is design work.
16. **MixScore backticks vs engine Open3 vs `RadioChop.capture`.** One ffmpeg runner, one `capture` signature.
18. **Two LUFS windows.** One.
19. **Fixed 2026-09-12.** `data/operator.yml` is the command list and now carries
     the whole of it: the check family (check-rails, check-openbsd, check-vps,
     check-full), vps-state and tree.sh lived only in START_HERE.md's Golden
     Commands, so the stub that pointed here was the more complete of the two.
     START_HERE's Golden Commands and Source Of Truth sections are pointers now,
     and RECIPES.md is a door rather than a table. `operator_docs.rb` reads the
     yaml and `/orient deploy` prints it, so a recipe added there shows at every
     door.
20. **Four deploy verbs.** Wrappers around `vps-deploy`.
21. **Two uptime-check scripts.** One file, one host list.
22. **Face tests in `spec/`, `test/`, `web/test/`.** Two homes at most.
23. **`bin/cli` vs `bin/master`.** One REPL file.
24. **`MASTER/lib/rails/`.** Move to `RAILS/gates/lib` or `/rails audit`.
25. **Zeitwerk ignore of the dead slash tables.** After (1), `rake lint:autoload` failing those entries is the deletion proof.

If two things mean the same thing, keep the one with the test.

26. **`swarm.html` / `diag.html`.** Public extra HTML, `lang="en"`, inline script, not the face. Gate behind auth or delete from production `public/`.
27. **`codebase.js` has no loader, which is worse than not being declared.**
    222 lines in `web/public/`, named by `topology_registry.js` and
    `data/topologies.yml` as the Repository Body topology's renderer — and
    that `renderer:` field is read by nothing. It is descriptive metadata, not
    a load instruction. Since the file is absent from `face_assets.yml`,
    `MASTER_ASSET_PATHS` does not carry it and `face.js` cannot import it, so
    the topology can be named and never drawn.

    Declaring it ships 222 lines to every visitor for a topology nothing
    switches to; deleting it removes a built visualisation. Either is a
    product decision, and the measurement is here so it can be made rather
    than guessed.
28. **`offline_memory.js` is a scaffold.** Comment: no wiring into chat. Wire enqueue or delete.
29. **Two importmap pins for one autogrow file — fixed 2026-09-11.** Both named
    the same vendor file and only `@stimulus-components/textarea-autogrow` was
    imported; `stimulus-textarea-autogrow` is the package's pre-scope spelling
    and nothing asked for it, so every page carried a modulepreload no import
    could resolve. One pin now.
30. **`bin/master-core`.** Fold spine only; `bin/master` boots the rest. `bin/dogfood` still calls it. `bin/master --core` or keep and give it one test that it is the fold, not a second product.
31. **Deals search is LIKE.** Listings/stores use `LiveSearchable`. One helper (restructure 39).
32. **brgen `NotificationsController` is local; amber inherits `Shared::`.** Promote or delete the host copy.
33. **`face.part*.txt` in `public/`.** Concatenated at build, still served. Move to a build dir.
34. **`smart-turn` ONNX (~21MB) default off.** Test that `index.html.erb` does not `<script src>` the wasm. Don’t ship it in the critical path.
36. **`smoke-apps.sh` vs `deploy-smoke.sh`.** One smoke; `port_inventory` `SMOKE_SCRIPTS` retargets.
37. **Fixed 2026-09-12, and the class is closed with it.** `stimulus_boot.js` retired
    content-loader on 2026-08-21 and `shared/frontend/examples.html.erb` went on
    offering the snippet for three weeks — a snippet library is copied by hand, so
    that handed someone a div that never loaded and no error. The container is gone.
    `test_every_controller_the_snippet_library_offers_is_registered` now checks every
    snippet against the registry: all 17 registered, every offer inside them, and the
    test fails when the retired one is put back. examples.html.erb stays — it is
    documentation, and item 3's proposal to delete it loses its argument now that it
    cannot go stale silently.
38. **Three face stores.** `felt_state.js`, `face_state.js`, `ui_presence.js`. Document boot order or fold presence into felt.
39. **`hello: Hei` in brgen and amber `nb.yml`.** Grep callers; delete unused scaffold keys.
40. **`rails-app.tmpl` disagrees with live `rc.d/brgen`.** Generate apps from the live script or delete the tmpl so OPERATOR cannot install the wrong one.
41. **`jobs` rc.d without `set -a` — fixed 2026-09-11, and it was all three.**
    brgen_jobs, amber_jobs and bsdports_jobs each sourced their env file with
    a bare `.` and then exported `SECRET_KEY_BASE` by name, so that was the
    only key from the file the worker could read. rc.d/brgen carries the
    reason in its own comment — VAPID_PUBLIC_KEY sat in /etc/brgen.env for
    hours while push failed silently — and the app was fixed with `set -a`
    while the workers were not, which is where it matters most: WebPushJob is
    one of the classes these workers run. `test_rc_env_export` pins it, and
    holds rails-app.tmpl to the same rule.
42. **`core-reclaim.sh` RSS — fixed 2026-09-11.** Both sites read
    `ps -axo rss,args | grep "127.0.0.1:$PORT" | grep -v grep | head -1 |
    awk '{print $1}'`: three banned tools, and fragile beyond that — it matched
    an args substring across every process on the box, so the answer depended
    on which line came first, and `grep -v grep` was there because the pipeline
    matched itself. One `rss_of_port` helper now, built on `pgrep -n -f` and
    `ps -o rss= -p`. Verified on vm23 (OpenBSD 7.8) before writing: both forms
    returned 52020 KB for master, and an absent port returns empty so the
    existing `[ -n "$rss_kb" ] || exit 0` guard still fires.

    Five banned-tool uses remain in that file, all parsing `swapctl -l` and
    `sysctl -n vm.loadavg`. Four are field extraction that `set --` can do.
    The fifth is `awk '{print ($1 > $2) ? 1 : 0}'`, a float comparison, and
    OpenBSD ksh has integer arithmetic only — so that one needs a tool or a
    scaling trick, and replacing it carelessly changes when the box sheds
    memory.
43. **`STREAM_ITERATE_LOG` unsynchronized.** One flock or pid-scoped log.
44. **`sine_stream.rb` mutates ENV at load — real, and the fix changes sound.**
    Confirmed: `demo_full.rb:14` does `require_relative "sine_stream"`, so it
    is required as a library, and the file sets synthesis defaults from line
    1793 — WONKY_TOP_DIRT, WONKY_HAT_DUCK, DRUM_FIELD_MIX and their
    neighbours. They are `||=`, so an explicit environment still wins.

    Moving them behind a `$PROGRAM_NAME` guard is not a refactor: demo_full
    requires the file and currently inherits those defaults, so guarding them
    changes what it renders. Rendered-sound defaults are the operator's, and
    this one needs a listen rather than a decision from a scanner.
45. **ARGV at load — a false positive.** All three are executables: mode 755,
    `#!/usr/bin/env ruby`, and referenced only by README.md and a notebook
    that describes them. Nothing requires any of them, and kaggle_session.rb
    does not read ARGV at all. An executable reading ARGV at the top is an
    executable; the `$PROGRAM_NAME` guard exists for files that are both a
    library and a script, and these are only scripts.
46. **`postpro.log` — already ignored.** `git ls-files` tracks no log under
    postpro. Nothing to do.
47. **`MASTER/log/traces.log`, `tts.wav`, `runtime/` JSONL, `loop.gif`.** START_HERE says generated goes in `.master/` / `output/`. Gitignore or PATH_OWNERSHIP `check: none`.
48. **`snapshot_*.md` — already ignored.** `.gitignore:65` carries
    `/snapshot_*.md` and `git ls-files` tracks none of them, so the root holds
    what TREE.md says it holds. The four files are generated locally after a
    push and never committed.
49. **`PwaController` request test — added 2026-09-11.**
    `pwa_serving_test` asks for all three routes over HTTP. The content types
    were the unmeasured half and both are load-bearing in a way no template
    shows: a manifest served as text/html installs nothing, and a worker
    served as anything but JavaScript is refused with a console error no
    deploy sees. The rescue path is pinned too — a failed worker render
    answers with a minimal installing worker rather than a 500, because a 500
    leaves whatever is installed in place with no way to replace it.
50. **`AstEdit` could not write — fixed 2026-09-11.** Confirmed and repaired.
    The class includes `Io::AtomicWrite`, which defines `write_atomic`, and
    both call sites asked for `atomic_write` — the same two words reversed — so
    every rename and every insertion raised NoMethodError on the line that was
    about to change the file. It failed late: both paths validate, ask the
    governor, and take an undo snapshot first, so a caller saw the tool accept
    the work and then die, leaving an undo snapshot of a file nothing had
    touched. Nothing in the suite named AstEdit, which is why it survived;
    `test_ast_edit_writes` covers both operations and asserts that every
    `*atomic*` call in the file names a method that exists. Proved by putting
    the misspelling back: three failures, then none.

Keep the one with the test. Then delete the other.


## performance

Both 2026-09-11 performance intakes (980 items) closed on 2026-09-13: six
measured costs fixed, the rest declined as unmeasured. The rule for the next
proposal is `MASTER/DECISIONS.md` "Performance Work Starts From A Measured
Cost", and for the box `OPENBSD/DECISIONS.md` of the same date.

- **dilla_live is not real-time.** Last measured: synthesis 1.58x real-time,
  the effects chain drags it to 0.34x. Re-measure first; any speedup must leave
  the rendered sound identical, and `dilla.rb` is under another session’s edit.


## Brgen monetization

The 289-item intake of 2026-09-11 is twelve rows under `horizon.brgen.monetization`
in `RAILS/apps.horizon.yml`, fences included. One decision is the operator's and
blocks all of it: which model comes first — the intake ranked verified business →
subscriptions → promoted listings → analytics → credits, with 0% commission — and
whether the shared Commerce/Entitlements domain is worth building before liquidity.

## Tree grammar

The grammar itself is written in `TREE.md`; the Rakefile split and a MASTER
`docs/` move are refused in `MASTER/DECISIONS.md`. The `MASTER/bin/` fold lives in
the MASTER sections above. One item survives.

- **The OPENBSD root holds ~60 loose files in three layouts.** Gates at the root
  (`integrity_gate.rb`, `health_check.rb`, `config_drift_gate.rb`, …) beside
  `OPENBSD/gates/`; operator shell (`deploy_all.sh`, `vps_*.sh`,
  `start_all_apps.sh`, `resource_guard.sh`) beside `bin/` and `usr/local/bin/`.
  vm23 procedures and the resource_guard cron call several by path, so the move
  needs the box:
  grep `/home/dev/pub4/OPENBSD/` on vm23 first, then move gates under `gates/` and
  verbs under `bin/` in one commit with `PATH_OWNERSHIP.yml`.

## dilla — measured defects, blocked on `dilla.rb`

Measured 2026-09-13 against the committed engine. Each fix is an edit to
`STUDIO/dilla/dilla.rb`, which another session holds dirty; none changes a sound
default unless marked.

- **Hocket voices all play one patch.** `render_hocket_lead!` calls
  `voice_stack_lead!` first, which always returns a path, so the per-voice
  `EP_GM_PROGRAMS[i]` fallback never runs; under VoiceStack every hocket voice
  picks patches from the same `seed_for("vsmodel#{voice.index}")`. The album
  signature's `HOCKET=3` is a note census, not an ensemble. Fix: pass the hocket
  index into the stack's patch seed or program. Sound change — operator hears the
  A/B.
- **`VoiceStack` plans `cutoff_scale` and nothing applies it** (`lib/devices.rb`
  plans it; the only other reader is `describe`). Wire it into
  `render_lead_voice!`'s filter or delete the field.
- **`data/modes.yml` has no reader.** The engine still walks the hardcoded
  heptatonic `SCALE_SEMITONES`/`DEGREE_TRANSITIONS` in `dilla.rb`, so the four
  qenit modes are inert and adding hicaz or hüseyni there would be too. Load the
  file into those tables first.
- **`insert_secondary_dominants` and `insert_backdoor` write one-note chords**
  (`lib/harmony_engine.rb:351,368`). `apply_voicing` returns any chord without a
  third unchanged, and both pass it a single pitch, so `V7/ii` and `bVII7` land
  on soul profiles as a lone note unless `validate_and_fix` repairs them —
  measure that, then voice them fully or delete them. Sound change — operator.
- **The demo run lies about success.** `acquire_demo_lock!` exits 0 when another
  run holds the lock and checks-then-writes (use `File::EXCL` or flock); an
  unknown command prints help and exits 0; the loop exits 0 with parts missing
  (exit non-zero unless `parts == order`); the next run wipes a killed run's
  finished parts unless `DEMO_KEEP_PARTS=1`;
  `demo_all` sets `DILLA_STREAMING=1`; `DEMO_TRACK_TIMEOUT` defaults to 420 s; help
  still says bare `ruby dilla.rb` runs `readme_loop!` when it runs `demo_all`.
- **Logs and provenance print load-time device ENV.** `ringtone_layer_describe`
  and the sidecar can report `COPY_MACHINE=6` on a slot `apply_album_slot!`
  forced to 0. Snapshot after the last `force_env!`.
- **Names.** `demo-all` is the catalogue, `demo` is `generate_demo`'s crate matrix,
  `showcase` is a third medley. Rename to `demo` / `demo-crate`, alias `demo-all`
  one release. No MASTER or RAILS caller.
- **No smoke test for the no-arg path.** `DEMO_TRACKS=<one verified>,<one improv>
  BARS=4` into a tmpdir, assert files, LUFS range and exit 0 — needs a render, so
  it runs on a quiet machine.

## dilla — operator decisions

Each changes how a default render sounds. The first is the operator's own
direction of 2026-09-12 and waits only on `dilla.rb`; the rest wait for the
operator's ear.

- **One DNA, devices on.** Fold `ALBUM=1`'s table, `RINGTONE_LAYER` and `DILLA_FULL` into
  `DILLA_STYLE_DEFAULTS` so a single `dilla` render and a demo slot share one
  table: `HOCKET=3`, `LPG`, `COPY_MACHINE`, `VOICE_STACK`, `MIDI_BAG` (predicate
  to `!= "0"`) on; subtractive flags stay; `RENDER_MODE=album` and the other mode
  keys go. Blast radius: `Shared::DillaProcessor` renders in RAILS and its 900 s
  timeout. Gate on a 16-bar MixScore inside the keepers.
- **Demo evenness.** `DEMO_STEADY` default for the catalogue, a fixed rap
  cadence instead of `DEMO_RAP_EVERY=2`, `DEMO_TECHNO_SHARE=0.34` (a second
  renderer in one wav), one tonic family across parts, a BPM band or pulse-aligned
  joins, device rotation on coprime periods, real images for `WAV_MAP` instead of
  the generated mandelbrot.
- **Engineer colour, sourced.** Tempo-relative bus-compressor release that keeps
  LRA (Cooley/STC-8), cassette on some album grades with air at 0, a 40 Hz
  kick-gated oscillator and SPX900-style Symphonic on the dug loop (Fairall),
  independent 2nd/3rd/tape harmonic amounts on the master (HEDD), EQ before
  compression and a slow, gentle start (Daddy Kev).
- **Harmony languages.** An `esen_parallel_dorian` language (parallel m11 cells,
  common-scale-tone lead, same-function half-step resolution, fast harmonic
  rhythm) with its own HarmonyScore profile; one `delay_tension!` operator for
  Bach 4–3 and the Dilla hang; `THEORY_BACH` and the Dilla pedal gated by
  language tag instead of track-name regex and `VOICING=drop2`; Picardy and
  Neapolitan on Bach languages only; cap borrowed-chord surprises at one per cell.

## dilla — unbuilt opt-in devices

None exists as code, so none can be wired; each wants `dilla.rb` to read its knob,
the CopyMachine shape (`plan` → `describe` → `build!`, tests on the plan), and a
16-bar probe. Refused proposals are recorded at the end of `live/CATALOGUE.md`,
and connecting existing devices to livesets is that file's list. In order of
leverage:

- promote `radio_chop`'s drum stem, which survives only in `scratch/chop_work/`,
  beside its rack in `samples/` (crate policy strips drums, so the operator says
  whether);
- `MIDI_BAG_TIMING=hats|kick|lead|chops` and a velocity morph;
- `GRANULAR=file` scan of a dug loop (scan position, grain size, spray; pitch held);
- a spectral resonator snapping partials to the sounding chord;
- a modal (Rings-lite) resonator on a chop;
- a named warp family on the crate (beats, tones, texture, re-pitch, complex);
- then wavefolder and 2-op FM on AnalogSynth, PitchLoop-style delay-line
  pitch, crate-sourced IR, wav_Map path morph and mip-mapped tables, MIDI
  transforms (strum, ornament, recombine, chop, note chance), weighted-next-section
  follow actions.
