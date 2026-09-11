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

**Forward work is the last section of this file**, merged from `WISHLIST.md` on
2026-09-06.
---

## MASTER

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
- **Whether the one scheme keeps an accent.** `magic_hex` is ratcheted at 77 and
  `contrast_below_aaa` at 37, of which the bulk are `--danger`, deliberately the one
  non-grey. `vertical_accents` still gives marketplace, tv, dating and the rest their
  own ink. The decision is whether one accent survives for interactive affordance — a
  link with no colour needs an underline instead. Both ratchets count RAILS, so this
  belongs beside the RAILS section rather than here.
- **The deploy.** See the box state below; nothing is blocking it.
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

**MASTER's voice is `en-NG-EzinneNeural`** (`data/voice.yml:23`), and vm23 speaks
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

### Survey findings still open

Re-measured 2026-09-09. Every number here was wrong by a little in the previous
version, which is the argument for re-running the instrument rather than quoting it.

**Twenty-three files in `lib/` are below the sprawl threshold, and the merge is not
free.** `FileSprawlRule` (`MASTER/lib/review/scan/rules/meta_rules.rb:284`) run over
`lib/` names 23, of which two are lone-file directories —
`MASTER/lib/cli/propose/candidate_sources.rb` and
`MASTER/lib/review/repo_ecology/co_change_graph.rb` — and the rest are under 25 code
lines. `lib/io/antigravity.rb` is **not** on this list any more — it absorbed its
folded subdirectory and is 231 code lines. But `lib/` is under
`push_dir(__dir__, namespace: Master)` (`MASTER/lib/master.rb:150`), so every merge
moves a constant and needs either a caller rename or a new `data/autoload.yml` entry
that `rake lint:autoload` will then hold to account. Do these one at a time with the
constant rename in the same commit; do not sweep them.

`review_crew/agents.rb` was the one with no constant to move — a require aggregator
carrying an autoload ignore — and it is folded: `review_crew.rb` names the eight files
where it loads them, and the ignore list is 44. **`security_error.rb` at 3 code lines is
declined, and the reason generalises.** Zeitwerk maps `Master::SecurityError` to that
path and nowhere else, so absorbing it means defining a class in `lib/master.rb`, the
namespace file, which carries its own `loc_body_budgets` key separate from `lib/` — two
lines saved in one row and charged to another. `FILE_SPRAWL`'s subject is a directory
holding one file or a name repeating its parent, and a file Zeitwerk requires to sit
exactly where it does is neither.

**Declaration order in `lib/` is already right, and the residual is constants, not
methods.** A Prism walk over all 405 files, tracking visibility per
class/module/singleton scope, finds **zero** scopes where a public non-`initialize`
def precedes the first one. The two backward call edges this entry named — `run`
below twenty helpers in `pub4/gate_chain.rb`, and `run_forever` above its only caller
in `fix/fix_loop/background_runner.rb` — are both reordered.

**What is left of that entry is a marker nobody can add.** It also asked for
`gate_chain`'s helpers to be `private_class_method`, and they cannot be while
`test_gate_chain` drives `stages`, `council_fix?`, `picks_in`, `classify` and
`verdict` directly. Reaching five methods through `send` to satisfy a marker is a
worse trade than the marker is worth; if somebody wants the surface narrowed, the
work is deciding which of the five the test should reach through `run` instead.

**The constants residual was read one by one on 2026-09-10 and declined, and the
reading is why.** 161 constants in `lib/` have exactly one use 80 or more lines below
their declaration, and the five this entry named as the worst are each a reason not to
move them. `llm_dispatcher.rb`'s `COST_PER_TOKEN` and `CACHE_WINDOW` are read again in
`llm_dispatcher/ruby_llm_sender.rb:104-114`, so "one use" was within-file only and the
census overcounts by however many constants a sibling file reads. `speech.rb`'s
`WORKER_TIMEOUT_PER_CHAR` and `WORKER_TIMEOUT_MAX` are a trio with `WORKER_TIMEOUT`,
which has two readers, and moving two of three splits a triple that shares one
paragraph of reasoning. `personality_prompt_builder.rb`'s `CORE_SECTIONS` is explained
by the class header comment eleven lines above it; moving it to `:585` separates the
constant from the paragraph that says what it is for. **A convention that would make
three of the five files worse is not being applied to the other 156 on faith.** If
somebody wants this, the instrument has to count sibling-file readers first.

**The biggest subjects in `lib/`, by `CodeMetrics.body_lines`:**
`review/scan/rules/surface_rules.rb` 518, `structural_rules.rb` 512,
`voice/speech.rb` 471, `voice/personality_prompt_builder.rb` 386,
`voice/expression.rb` 306, `review/repo_ecology.rb` 298, `voice/engines.rb` 296,
`review/llm_dispatcher.rb` 295, `review/scan/self_test.rb` 294,
`review/scan/rules/semantic_rules.rb` 290. `cli/command_registry/work_commands.rb` has
left this list at 246. The rules files are registries of `RuleDSL.rule` calls and
already carry `SMALL_FILES` findings; splitting them moves lines rather than removing
them, so they pay nothing toward the ceiling and should be left alone until someone
wants them split for reading. By directory, counting only the files directly in each,
`lib/ground` is 4,323 over 50 files, `lib/io` 4,143 over 56, and
`lib/review/scan/rules` 3,341 over 16.

**`ABC_SIZE` fires four times over its ratchet of 40, not three.** The entry that
called this "the one figure that re-measured exactly" named three and missed
`MASTER/lib/review/scan/rule_registry_audit.rb:139` `#classify_yaml_entries` at 43.8,
which is not new — the same measurement over `ad6e6c0b0` reports it. The other three
are `MASTER/lib/voice/emotion.rb:20` `#analyze` at 74.7,
`MASTER/lib/cli/session/command_ops.rb:24` `#run_critique` at 42.2, and
`MASTER/lib/ground/phase_gates.rb:103` `#automatic_gate_met?` at 41.4. Run the rule over
`lib/**/*.rb` directly rather than reading a triage bucket, which is where the fourth
went. `rake constitution` overall is 1,791 findings, 101 actionable against a budget of
1,500, and passes.

`classify_yaml_entries` builds five populations from one pass, and the shape that
lowers it is to split the lexical trio out. Nothing gates on it — `ABC_SIZE` is a
threshold rather than a ratchet row — and the split adds a `def` and an `end` to a
`spine.lib_body_ceiling` with no headroom, so it waits for a reason better than the
number.

**`emotion.rb#analyze` at 74.7 is the largest and is deliberately not being
refactored.** Its ABC is arithmetic rather than branching — five weighted sums over the
signal table — and the shape that would lower it is to move the coefficients into a
table and fold them. That changes the association order of a float sum, and its outputs
are `exaggeration`, `cfg_weight` and `warmth`: the controls MASTER's speech is
synthesised with. A refactor that alters the last bits of those is a change to what
MASTER sounds like, made by somebody who cannot hear it. It stays until a sitting that
can A/B the audio.

**`NO_PUTS`' eleven findings are closed**, and the rule exempts
`MASTER/lib/operator/gate_chain.rb` by name. The statement is "no bare puts in library
code" and its exemptions are the paths that print for a living. The file rather than
its directory: the sibling `status_report.rb` renders a string that `bin/operator` prints,
which is the shape the rule asks for and the proof `lib/pub4` should not be exempt
wholesale. `gate_chain` cannot take that shape — the ladder runs for minutes and the
report is the progress, so a buffered return delivers the account after the run it was
meant to narrate.

**`FILE_VAGUE_NAME` and `sprawl.vague_names` measure different things and neither
number is the other.** `FILE_VAGUE_NAME`'s one finding is closed:
`provider_quarantine_manager.rb` is `provider_quarantine.rb`, and
`ProviderQuarantineManager` is `ProviderQuarantine`. "Manager" is a category rather
than a name, and the class was already named for what it does — it quarantines a
provider. Renaming it lost nothing, because the accessor in
`model_router/diagnostics.rb` reads better as `quarantine` than as
`quarantine_manager`. The rule never surfaces in `rake constitution` because it is
`severity: :info` (`naming_rules.rb:239-240`) and the info filter drops it, which is
why one finding sat there for as long as it did. `sprawl.vague_names` is 2 of 2
and both are Zeitwerk: `MASTER/lib/boot/data.rb` and `MASTER/lib/io/base.rb`, the
latter named after the constant it defines, so the finding is that the *concept* is
called `Base` — a design decision and not a rename.

#### Not worth chasing

Measured and rejected, so the next reader does not spend a day on it.

**There are no oversized methods.** The largest body in `lib/` is 20 code lines, tied
across seven methods (`io/media_intent.rb:76`, `pub4/status_report.rb:38`,
`review/llm_dispatcher.rb:239`, `cli/pipeline/through.rb:71`,
`review/scan/rule_dsl.rb:39`, `cli/command_registry/system_commands.rb:127`,
`review/scan/ast_fixer/dead_code_and_commas.rb:15`); the next is 19, and the `DENSITY`
limit is 20. The `ABC_SIZE` rows above are branch density in short methods, not length.

`MAGIC_NUMBER_SPREAD` from `cross_file_analysis.rb` reports fourteen literals recurring
across files — `100` in 24 files, `200` in 20, `120` in 16. These are limits, widths
and percentages that mean different things in each file; the rule's own comment records
that an earlier version fired on the named constants it was recommending. Naming them
centrally would couple unrelated subsystems. Likewise its `SPRAWL` rows (`cost` in 13
files, `cache` in 19, `provider` in 17) and `SCATTERED_CONFIG` rows (`ENV PATH` in 9)
are namespaces, not sprawl.

`COPY_PASTE_BLOCK` finds one group in all of `lib/`, and the `DRY` structural-clone
rule finds three cross-file groups, of which one — `review/repo_ecology.rb:231`
`#grade_for` and `trace/context_pressure.rb:21` `#band_for` — is two banding functions
over different domains that happen to share a `case` shape. Extracting a shared band
helper for two callers buys nothing.

`code_reach` is 0 of 0 and correct: no file in `lib/` is unreached. Re-running
`tools/code_reach.rb` answers nothing new.

**All sixteen individually-run lint gates are green** — `lint:dedup` (2 known
cross-file duplicates, 0 new), `lint:reader_singularity` (451 source files, 7 data
files with more than one reader), `lint:doc_citations`, `lint:instruments`,
`lint:constant_collisions` (399 requirable of 2,469, 0 collisions), `lint:capability`,
`lint:scan_coverage` (414 files), `lint:autoload` (45 ignores, all still necessary),
`lint:frozen`, `lint:rule_reach`, `lint:models` (412 live, 0 stale ids),
`lint:principle_trace` (81 of 147 registered rules untraced, ratcheted to 81 on
2026-09-10), `lint:cohesion` (30 families, ratcheted to 30), `core_smoke`,
`security_sweep`. Do not re-audit the green ones; audit why they were once
unreachable instead.

### Inert law and config

The dominant defect class in this tree: a declaration with no reader. What is open is
the class, not an instance. When you find one: **find the reader before trusting a
config key, and add the gate, not just the fix** — a two-direction test is what stops
the two halves blurring back together. `limits.yml`, `security.yml`, `patterns.yml`
and `tts.yml` were each closed that way, and `test_limits_split.rb` and
`test_security_defaults.rb` are the shape to copy.

**The `data/tts.yml` instance is the one to remember, because it was inert in the
other direction.** The file's own header said "NOTHING RUNNING READS THIS … every key
below, the engine chain included, is inert", from a caller trace that stopped one frame
short of `Voice::Playback`. Every hop resolves today:
`Cli::Session::ResultDisplay:82` → `Playback.speak` (`playback.rb:68`) →
`Playback.synthesize` (`:114`) → `Speech.synthesize` (`speech.rb:279`), with
`synthesis_mode` (`:271`) consulting `Transcendent.load_config`
(`transcendent.rb:49`), which reads the file. `Ground::RuntimeCatalog:117` is a second
reader. **A config that governs how MASTER sounds told its next reader it governed
nothing**, which is the same defect as an unread key and costs more. It was found after
three fixes had already been written against that subsystem, not before — so trace the
caller first.

**Do not use that entry as a source for the `lib/voice` budget.** A name-based census
over `lib/voice` reports seven files with no `Voice::`-qualified reference outside the
directory — `Enrich`, `ProductionDna`, `StrunkPass` and the four `Renderer::` mixins,
734 lines — and every one of them is reached from inside it, three by `include`. The
instrument was the prefix. `renderer.rb:23` includes `PromptComponents` with no
`require_relative` beside its three siblings and resolves through Zeitwerk, which is
also why a naive merge of that directory raises: see the reverted folds below.

#### A general "every data key has a reader" gate does not work here

It is the obvious next gate and it is not buildable statically. Measured before
building, which is the only reason it was not built:

- **At the key level: 607 of 1173 second-level keys** across `data/**/*.yml` have no
  literal mention in first-party code. 52% — a checker wrong more often than right.
- **At the section level: 49 of 238 top-level sections.** Better, and legible, but
  still holding whole classes of false positive: `personas.yml`'s persona names and
  `models.yml`'s model rows are registry entries selected by a config value at runtime,
  and `doc_paths_baseline.yml` is keyed by the very document paths it exists to list.

The reason is that this tree reaches its data four ways a grep cannot follow:
interpolated filenames (`review/modes.rb` opens `data/prompts/mode_#{mode}.yml`),
directory globs, the `DATA_ALIASES` table, and generic section loaders like
`RuntimeCatalog.load(section)`. All four are legitimate.

Two things worth keeping from the attempt. **`loc_budgets` looked dead and is not** —
it is read by the `loc_budget` task in the Rakefile, which a `lib/`-only search misses,
so any search for readers has to include `Rakefile` and `bin/`. And **the top remaining
candidate, `limits.yml` `guidance` (29 keys), is the closure above working exactly as
designed** — the deliberately unread half of the split. An unread-key gate would have
reported the fix as the defect.

So the honest scope is per-file and by hand, with a two-direction test. A repo-wide
gate would need a baseline carrying a written reason for all 49, which is a decision
about 49 sections rather than a mechanical step.

**`data_reach` does tell which file a reader opened, and the entry that said otherwise
was reading an older tool.** `misattributed` reports every key named in code that never
mentions its file — the `success_criteria` shape, where `lib/ground/phase_gates.rb:133`
names the word while reading session state rather than `rules.yml`. The 37 at the
ceiling is still a floor on the real number, because a key named in a comment counts as
named.

**Its own instrument was punishing the house rule, and that is fixed.** Attribution
asked for the yaml basename in the same file as the key, and a reader obeying
`lint:reader_singularity` never writes one — it asks `Master.load_rules`,
`Master::RULES_PATH` or `@rules.data(:soul)`. Nine live readers were reported unread for
following the rule, `rules.yml#llm_output_rules` and `soul.yml#prompt_ordering` among
them. `DataReach::ACCESSORS` names the handles each file is legitimately reached by, and
the test pins both directions: an accessor names its own file and vouches for no other.

**The 36 that remain are four families and none is a defect** — read this before
chasing the number. Fourteen are registry rows selected by a config value at runtime
(`personas.yml` 7, `providers.yml` 5, `prompts.yml` 2), the case the subsection above
already names as unreachable by any grep. Six are a `schema` or `meta` version key read
by a version check rather than by name. Nine are archive and recovery manifests
(`pub_archive_restore.yml`, `recovery_pub.yml`) whose keys are data about a restore
rather than configuration. The rest are keyed by something other than an identifier —
`namespace_ceilings.yml` by tree path, `soul.yml#language` and `#research` by a nested
reader. **A ceiling over them needs a written reason for all 36, which is a decision
about 36 rows rather than a mechanical step, and that is the same argument this section
already makes against the repo-wide version.**

### The shape of the tree

`sprawl_census` counts three things over every tracked file in all four trees, and
`bin/operator measure` carries them: a directory holding one file, a name that repeats its
parent, and a name that says nothing on its own. `FILE_SPRAWL` in the scan registry
measures the first two for MASTER's `.rb` files and skips `law/`, `core/`, `test/` and
`spec/`, so it reports zero here and means only that.

**19 one-file directories against a ceiling of 19**, all of them mandated: OS install
paths, Zeitwerk, ports fixtures, OmniAuth, PWA, and dilla vocal, render and stem
takes. The row is at its ceiling, and the ceiling is not MASTER's to lower — it counts
all four trees. Read the live figure from `MASTER/bin/operator measure`, not from here.
The map is `TREE.md`.

Calibrate a new kind against a real file before adding it. The first pass called 130
RAILS paths too deep and 26 names vague, and every one was the rule misreading a path
Zeitwerk requires — the same way 596 of 981 design findings died. Stutter took three
attempts before it separated `dilla/dilla.rb`, which reads correctly at a command line,
from `lib/cli/cli.rb`, which held `Master::CLI::CLI`. What tells them apart is whether
the file declares the name twice.

**`tools/repo_inventory.rb` had been reporting the four trees as sprawl, and nobody
noticed because nobody could act on it.** Both of its allowlists had gone stale in both
directions at once: five of seven root files and four of six root directories named
subjects that do not exist — `MASTER.md`, `index.html`, `OPERATOR/`, `dilla/`,
`multimedia/`, `sh/` — while `MASTER`, `RAILS`, `OPENBSD`, `STUDIO`, `TODO.md` and
`TREE.md` were absent, so each was reported as non-canonical. That is the worst state
an allowlist can reach, and the reason it stayed there is that a report naming the
repo's own trees as defects is one everybody scrolls past.
`spec/lifecycle_tools_spec.rb` holds both lists to the tree in both directions now, and
the tool grew the `$PROGRAM_NAME` guard every other tool here has, so reading its
constants no longer runs a census.

**Its `new` marker had no true positive either**, which is the same test the two deleted
learned smells failed. Thirty-four of thirty-five findings were `app/views/**/new.html.erb`
— a Rails route action, not "the new version of a file" — and the thirty-fifth was
`new_framework_defaults_8_0.rb`, a name Rails generates. A marker that only ever matches
a framework convention is measuring the convention.

**What repo_inventory reports now is 60 `low_density_slug` findings and nothing else**,
and they are a naming campaign rather than a defect list: `lib/boot/data.rb`,
`lib/io/base.rb`, `lib/cli/session/command_handlers.rb`. Two of those are the same
`sprawl.vague_names` pair this file already records as a design decision and not a
rename. Read the list before believing the number.

### Top-level ROOT

**43 files across the repo define a bare top-level `ROOT`**, each pointing at a
different tree. In their own processes that is harmless, which is why it stands. It
stops being harmless the moment two of them are loaded together: Ruby warns
`already initialized constant ROOT`, lets the **second assignment win**, and the loser
then reads the wrong tree with no further complaint.

**It cost something again on 2026-09-10, and the cost was one line of warning in a
green run.** A new spec reading `tools/repo_inventory.rb`'s allowlists loaded the file,
and its `ROOT` collided with `spec/dogfood_spec.rb`'s — which resolves to `MASTER/`
where the tool's resolves to the repo root, so whichever loaded second sent the other
looking in the wrong tree. `rake spec` was green through it. It is `INVENTORY_ROOT`
now, after `SWEEP_ROOT`. **The pattern to take from this: the collision arrives when
somebody makes one of these files requirable, and making a script requirable is
otherwise a pure improvement, so the hazard shows up attached to good news.**

That happened in `rake test`, where `test_security_sweep.rb` requires
`tools/security_sweep.rb` and `test_dilla.rb` loads `STUDIO/dilla/dilla.rb`. Depending
on load order, the security sweep would have run `git ls-files` against `STUDIO/dilla`
and reported the repo clean having scanned a music directory. The warning in
`bin/check`'s output was the only thing standing between that and a silent pass, and it
read as cosmetic noise. MASTER's is `SWEEP_ROOT` now
(`MASTER/tools/security_sweep.rb:13`).

**`rake lint:constant_collisions`** asserts that no two files reachable by a
`require_relative` define the same top-level constant: 398 requirable files of 2,473
first-party Ruby, 0 collisions. Only `require_relative` is followed — a plain `require`
resolves against `$LOAD_PATH`, which depends on how the process was started, and
guessing at it would produce a gate that is wrong in both directions. So the other 43
bare `ROOT`s stay, and stay a hazard the day one of them is required.

**An orphan sweep must include the repo-root `bin/` and must not filter by
extension.** A 2026-08-03 sweep deleted `lib/operator/status_report.rb` as an orphan and
broke `MASTER/bin/operator` for six days: the grep matched only `*.rb`/`*.yml`/`*.md` and
`MASTER/bin/operator` has no extension, and it ran from `MASTER/`, where `bin/` does not
mean the repo-root `bin/` that holds the caller. Pinned by
`test/test_entrypoint_requires.rb`, which checks requires rather than constants — a
constant sweep can be fooled by an extension filter; a missing file cannot.

### `/scan`'s autofix corrupts code — do not run it unattended

Trialled on `RAILS/gates` alone before turning it loose on RAILS's 2,326 files. It
wrote three files and **two of the three were damage**:

    RAILS/gates/support/design_metrics.rb
    -  brgen/engines/*/app/assets/stylesheets/*.scss
    +  brgen/engines/*/app/assets/stylesheets/*.scss,

`TRAILING_COMMAS` fired inside a `%w[]` array, where a comma is a literal character and
not a separator. The glob now ends in a comma and matches nothing, so
`light_only_vertical_keys` would report a clean tree having read no file.

    RAILS/gates/support/geometry_probe/walk.js
    -  return seen[sel] === 1 ? sel : sel + '[' + seen[sel] + ']';
    +  return seen[sel] === 1 ? sel : `${sel}[${seen}`[sel] + ']';

The template-literal rewrite mangled a three-term concatenation: it closes the template
early, then indexes the resulting string by `sel`. Every duplicate selector key becomes
`"undefined]"`. **`node --check` passes** — a silent semantic corruption that survives
a syntax check is the worst shape this has, and it is the shape a tree-wide unattended
run would have written everywhere. Both reverted; the third change, a blank line, was
harmless. One in three.

Both instances are pinned. `percent_word_array_close?`
(`lib/review/scan/ast_fixer/dead_code_and_commas.rb:140`) skips `%w %W %i %I`, held
both directions by `test_trailing_commas_skip_percent_word_arrays`
(`test/test_ast_fixer_transforms.rb:408`); `convert_string_concat`
(`ast_fixer/web_transforms.rb:155`) declines a chain followed by `(`, with
`test_public_js_has_no_template_literal_called_as_a_function` asserting the shape in
the tree. **Other autofix transforms can still mangle**; `--no-autofix` remains the
safe default on an unattended tree until each transform has that shape of test.

Pipe mode used to ignore ARGV, so `bin/cli /scan RAILS` with no TTY printed nothing and
exited 0. It honors the argument now, then stdin. Paths still resolve after
`bin/master` chdirs into MASTER, so a sibling tree is `../RAILS` or the `rails` alias.

### Self-test debt

**agent-ignore** — triage only when the task explicitly targets scan rules.

`rake selftest` reads 0 and `rake selfcheck` is clean, both on 2026-09-09. Read the live
figure from the task, never from here: selftest has been 0, 1, 2, 3, 6 and 7 on
different days of the same fortnight, and a "clean since" claim in `START_HERE.md` was
already stale once. Treat any count as true for the commit that carries it and no
further.

Two things about the mechanism, because neither is obvious from the number.
`self_test_heartbeat_publishes_clean_scan_metrics` does not fail on a non-zero count,
so nothing gates `selftest`: a non-zero reading is visible only to whoever runs the
task. **`selfcheck` is different, and an earlier record here had it backwards.**
`SelfCheck#gate!` (`lib/fix/self_check.rb:53`) is called from
`lib/builder/ai_boot.rb:158` and publishes `self_violation`, which `ai_boot.rb:183`
subscribes to `fix_loop.halt!` — so a red `selfcheck` halts background autofix for
every session. The 2026-08-19 note claiming `gate!` had no caller and that "this number
gates nothing" was wrong, and acting on it would leave a real halt in place while
reading as noise.

Triage each new finding as: true violation to fix / scanner false positive / rule
exemption needed / rule threshold too strict / known debt to leave alone. **What must
not happen is the count being driven to zero by re-exempting the fold** — the fold is
inside `lib/` on operator instruction precisely so it is measured by the law it applies
to everything else.

### The face, and TTS on the box

**The face's mood channel is complete at both ends and has no middle, and it is an
operator call because closing it changes what a visitor sees.** `face.part5.txt:1032`
listens for an SSE `mood` event and does three things `felt` does not — mood history,
the surprise lift on `curious`, and the colour tint through `fadeColorTo(TINT[m])`.
`web/app/services/chat_service.rb:120` subscribes to `agent:mood` to feed it. **Nothing
in the repo publishes `agent:mood`**, so the tint has never fired.

The near neighbour is not a substitute and reading it as one is the trap here.
`felt:sense` carries a mood, but `publish_canvas_state` builds it from
`@params[:state]` — the browser posting its own state back — so that channel is the
face echoing itself, not MASTER telling the face anything. The emotional state MASTER
does compute lives in `voice/emotion.rb` as `exaggeration`, `cfg_weight` and `warmth`,
and nothing maps those to a mood word. **So this is an unbuilt producer rather than a
broken wire: the SSE plumbing, the listener and the tint table are all there.** Wiring
it starts the face changing colour on its own, which is a look somebody has to see.

**operator-priority.** Voice Mode and boot contracts are covered by
`web/test/face_boot.test.mjs` (static assertions on `face.runtime.js`), and the WebGL
primer guard has the same pattern. **Manual iOS Safari tap-testing remains operator
work when boot assets change materially** — nothing in CI drives a real touch event.

End-to-end TTS audio depends on host binaries (`espeak`, `ffmpeg`, and the worker).
Web wiring can be correct while synthesis is unavailable, and `pkg_add` succeeding at
install time is not evidence a binary is on the box now. Check `GET /health`
`deploy.tts_socket` and `test -S .master/tts.sock` on vm23. Measured there 2026-08-17:
ffmpeg 6.1.3 and ffprobe are both in `/usr/local/bin` and `Engines.ffmpeg?` evaluates
true inside MASTER's own bundle, so the PATH the daemon runs with resolves it — which
the cron-PATH lesson elsewhere says not to assume.

`lib/voice/engines.rb`'s two ffmpeg fallbacks used to return quietly, so a host without
ffmpeg served un-concatenated audio with nothing logged. They report through
`Swallow.log(..., severity: :load_bearing)` now, naming the consequence. **Any future
post-synthesis DSP must call `report_missing_ffmpeg` on its own fallback path** rather
than returning silently.

**The one-shot Edge fallback has not been re-probed on the box.** Production TTS is
the daemon; the fallback is `synthesize_edge_oneshot`, now on the daemon's path
(`synth_forked`, and `SSL_CERT_FILE` set the way `worker_env` does). That does not
prove the box writes a non-empty MP3 — `/health` is a capability check. Re-probe on
vm23 with a real oneshot before calling the fallback healthy.

**There is no `edge-tts` binary to look for, and the gem is spelled with hyphens.**
MASTER never shells out to an `edge-tts` executable — it runs `bin/tts-worker` under
its own bundle, and the dependency is the Ruby gem `rb-edge-tts`, pinned to a git
source in the root `Gemfile`. Two checks said TTS was unavailable here and both were
the instrument: `command -v edge-tts` looks for something that never existed, and a
grep for `rb_edge_tts` misses `gem "rb-edge-tts"` because the require spells it with
underscores and the Gemfile with hyphens. The ground truth is one command —
`echo hi | ruby bin/tts-worker en-GB-RyanNeural +0% +0Hz /tmp/x.mp3` — and it writes a
real MP3.

**The TTS probe fix is paid out of two budgets that were already over.** `edge_tts_ready?`,
the memo and the worker probe add 35 body lines to `lib/voice` and the same 35 to
`spine.lib_body_ceiling`, and no ceiling was raised. It is not a Transcendent deletion
waiting for an owner: `Playback` calls `Speech.synthesize` for every spoken CLI reply
and `bin/tts-speak` calls `Transcendent.synthesize`, so those lines are the code MASTER
speaks with, and `synthesize_bytes` is the one method only tests reach. So `lib/voice`
is over its budget with no dead weight in it, which makes this an extraction rather
than a deletion. `speech.rb` at 471 and `personality_prompt_builder.rb` at 386 are
where to open it. Taking 35 lines out of somewhere unrelated to make the number look
right would be the accounting the budget exists to prevent.

### Live gotchas

Facts with no home of their own, kept because each was expensive to find.

- **`rake studio` and `bin/check --profile=agent` ran the same task and answered
  differently, and the deciding factor was how the parent shell was started.** Bare,
  `studio_gate` passed; through `bin/check`, which runs rake under `bundle exec`, it
  failed with "postpro does not boot — ruby-vips gem missing" on a host where a plain
  `ruby -e 'require "vips"'` says ok. STUDIO has no Gemfile and resolves its own gems,
  so a child that inherits MASTER's bundle cannot load any of them. `studio_test`
  cleared five variables by hand for exactly this and `studio_gate` cleared none —
  **and the five were not enough anyway**: Bundler 4 sets `BUNDLER_SETUP`, and a child
  ruby loads `bundler/setup` off it with `RUBYOPT` already cleared, so the grandchild
  was still bundled. Both call `Bundler.with_unbundled_env` now, which is what
  `test:web` already concluded in its own paragraph three tasks below. `bin/check
  --profile=agent` reads clean. **The general shape: a gate that passes bare and fails
  under a profile is an environment leak, not a finding, and the hand-rolled list of
  bundler variables is wrong on every bundler release that adds one.**

- **A council pass looks exactly like a hang.** On a dev Mac the provider is the
  `claude` CLI (`llm_dispatcher.rb:291 send_claude_cli`), not an HTTP API, so a run
  with no `*_API_KEY` in the environment still reaches a model and
  `Master.any_api_key_present?` is not the question. `CLAUDE_CLI_TIMEOUT_S` is 300
  (`llm_dispatcher.rb:42`) and the council runs 26 personas four at a time, capped by
  `TOTAL_BUDGET_S` at 600 (`review/council/deliberation.rb:40`). Add four scans of
  ~90s each and `/through master` needs roughly sixteen minutes. It spends most of that
  at 0% CPU with an empty pipe, because the CLI buffers when stdout is not a TTY and
  every persona thread is blocked on `IO#read`. Two sessions have now killed it
  believing it was stuck. `ps` shows the truth: count the `claude --print` subprocesses
  before concluding anything.
- **Constructing a `Session` flips a process-wide flag.** `Session#initialize`
  (`lib/cli/session.rb:41-49`) calls `set_visitor_mode_if_unauthenticated`
  (`session/repl_flow.rb:12`), which sets `Fiber[:master_visitor] = true` whenever the
  config carries no `web_token`, and fiber storage outlives the test that set it. That
  was the "known flake" in `TurnRouterTest`: a later test reaching `TurnRouter.call`
  took the visitor branch and errored inside a test about the Fold. `test_cli.rb`,
  `test_cli_bridge.rb` and `test_pairing.rb` all clear it now. Not a product defect — a
  real CLI reads a 64-char `web_token` — but the web path sets and clears this per
  request while the CLI sets it for the life of the process.
- **`rake mutate` chose its candidates with a regex over the file text**, so it read a
  numbered list in a comment and the 8 in `"UTF-8"` as integers, and `sub` then rewrote
  the first match anywhere rather than the one in the code. Three well-documented files
  reported eight survivors for mutations no test could see. It walks Prism's token
  stream now and names the line each mutation is on.
- **Getting scanner locations by hand needs two unwraps and a Hash.**
  `Scanner#scan_dir` returns `Result::Ok([[path, Result::Ok([...])], ...])` and the
  findings inside are plain Hashes with symbol keys, not `Finding` objects — `f.rule`
  raises, `h[:rule]` works. Three attempts died on that. Start from:

  ```ruby
  pairs = sc.scan_dir(File.join(Master::ROOT, "lib")).value
  all = pairs.flat_map { |path, res| Array(res.value).map { |h| h.merge(path:) } }
  ```

- **A lint that checks a basename cannot see a namespace.** `rake autoload` was red and
  `rake lint:autoload` called the same file clean. Three files under
  `lib/review/scan/engines/` declared `Master::Review::Scan::PathFilter` while the
  directory implies `Scan::Engines::PathFilter`, so eager loading raised on a name the
  lint approved: it matched `module <Basename>` anywhere in the file and never asked at
  what nesting. It compares the whole path-implied constant now, and all 45 ignores
  still measure as necessary under the stricter reading — which is the check that the
  fix did not just widen the hole.
- **`\b` next to punctuation is worth re-reading; it has cost something three times.**
  `TYPE_CHECK` was `/\b(is_a\?|instance_of\?)\b/`, and a trailing `\b` needs a word
  character beside it while `?` is not one — so `OPEN_CLOSED`'s `is_a?` clause could
  never fire and half of what its description promises was dead from the start. It is
  `/\b(is_a\?|instance_of\?)/` now (`structural_rules.rb:508`), and the fix was free:
  repo-wide findings go 3 → 3, because no `case` anywhere dispatches on `is_a?` across
  three or more branches. The other two were `TODO.md` read as a work marker, and a
  lookbehind excluding `:` that hid every `Ground::BootChecks` caller from a dead-file
  census.
- **The rule-id census is settled, and the three answers are all explainable.** Build
  the scanner and read `@rules` — that is the collection `RuleOrder` receives from
  `ai_boot.rb:122`, and `r.id` is a `String`. It holds 147. A `Rule.registry` walk gives
  fewer because bridge classes are rejected; a regex over `law/*.rb` and
  `lib/review/scan/rules/*.rb` for `Law.define(:X)` and `RuleDSL.rule :x` gives more,
  with mixed case, which is what `tools/rule_hygiene.rb` uses and why its numbers
  differ. All three are correct for their own question. For "does this key weight
  anything", only the first is.
- **A rule fixture can pass for the wrong reason, and one can exist where this file
  said none could.** `TYPOGRAPHIC_EXCELLENCE`'s first draft, `warn "loading..."`, did
  not fire, because the rule reads a bare quoted ellipsis and that is prose containing
  dots. And a rule whose subject is a forbidden shape can still hold its own example:
  `SILENT_RESCUE` reads a line that *starts* with `rescue`, so an escaped one-line
  string is a worked example everywhere and a finding nowhere. This file twice recorded
  that as impossible.
- **Two sweeps for the bug shapes `style.ruby.bugs_to_avoid` names found nothing, and
  one instrument was wrong.** No `@bus&.publish(...) || value` in `lib`, `bin`, `web` or
  `tools`. The only `Dir.chdir` is `bin/master:74`, the documented cause of the
  `/scan RAILS` path trap. Four `next if` inside a `flat_map` turned out to be four
  `filter_map`s — `filter_map` drops the nil correctly, and a proximity-based grep
  cannot tell the two apart. Do not re-list them.
- **"A test that never names a `Master::` constant" is not a hollow-test detector.** It
  flags 38 files, and the bulk are gates that legitimately read files rather than
  constants — `doc_paths`, `doc_numbers`, `constant_collisions`, `security_sweep`. Same
  false-positive rate as the dead-file census. The one hollow test found by that
  session was found by reading the subject, not by a pattern.
- **Five rules carry no detector and no obvious class, and all five are accounted
  for** — do not re-list them. `WHITESPACE_PUNCTUATION`, `KEYWORD_ARGS`, `BARE_RESCUE`
  and `MESSAGE_CHAIN` each carry `folded_into:` naming the rule that reports for them,
  and `PROSE_OMIT_QUALIFIERS` is generated by `law/prose.rb` from the `prose.en.ids`
  mapping rather than declared.
- **`learned_smells` declaring five while its own comment said four is closed, and the
  disagreement was the finding.** The comment listed the four that "survive" and omitted
  `frozen_string`, declared fifty-five lines above it. The list is three now —
  `magic_number`, `sycophancy`, `duplicate_code` — and the comment counts them. **Prose
  and data disagreeing about the size of a list is how a detector nobody believes in
  stays registered**, which is exactly what had happened to both of the two deleted.

### `self_findings`: what our own rules find in our own trees

Two ratchet rows over the same corpus — 3,155 files on 2026-09-10, across eleven trees
plus `MASTER/web`. `data/self_findings.yml` carries every finding with its file and
line, so the arrival names itself.

The four generated face bundles are excluded once now rather than twice: the exclusion
lives in `Scan::PathFilter::GENERATED_FACE_BUNDLES` and `tools/self_findings.rb` reads
it. The two copies agreed only for as long as somebody edited both, and one spelled the
bundles as strings inside a regex while the other spelled them as paths — a difference
no test could see.

**`self_findings.law` is 279 against 279 and at its ceiling** — the "slack by eight"
this entry recorded was a stale number quoted from prose rather than read from
`bin/operator measure`, which is the mistake the header of this section warns about. It
moves several points in a day because it counts every tree, and the bulk of what moves
is `STUDIO/dilla`; lowering the ceiling from a shared checkout records a low the
committed tree does not hold, so it stays dilla's owner's row to ratchet on a settled
tree. The recorded members are the snapshot at 289:
`NULLISH_COALESCING` 76, `NO_COLUMN_ALIGN` 42, `GUARD_CLAUSE` 27,
`NO_MULTIPLE_LANGUAGES` 22, `NO_INLINE_SCRIPT_BLOCK` 21, `I18N_COVERAGE` 18,
`PROSE_OMIT_QUALIFIERS` 18, `NO_CHANGELOG_COMMENT` 16 and sixteen smaller. **Read the
member list, not the number.**

**`self_findings.registry` is 53 against 53, and what is left is two
rules.** `NO_GOD_CLASS` 29 live (32 recorded) and `SILENT_RESCUE` 24. All the
`SILENT_RESCUE` are under `STUDIO/` and nineteen under `STUDIO/dilla/`, which is the
operator decision above. `NO_GOD_CLASS` is more than ten public methods or more than
three hundred code lines, led by `RAILS/brgen/engines/takeaway/app/models/takeaway/order.rb`
at 31 defs, `conversation.rb` at 28, `user.rb` at 27, and
`RAILS/brgen/lib/brgen/bergen_demo_seeder.rb` at 902 lines. Nothing there is
instrument; it is decompositions in three trees, most of them live Rails models.

**The census had never read `MASTER/web`, and widening it is the lesson.**
`self_findings` walked eleven trees and the face was not one of them, so `FOR_OF`,
`TEMPLATE_LITERALS`, `ASYNC_AWAIT`, `FACE_POINT_IS_ONE_PIXEL` and `NO_JQUERY` read as
silent because nothing they govern was ever handed to them. **A rule that fires on
nothing may have no subject rather than no defects. Before believing a silent law,
check that the census reads the tree its subject lives in.**

The face's generated bundles are third party for this purpose. `face.runtime.js`,
`face.modules.bundle.js`, `face_vision.bundle.js` and `three.face.module.js` are 12,047
lines built from `face.part1-5.txt`, so counting them measures the generator's output
rather than anything a person wrote. That exclusion is declared twice — in
`tools/self_findings.rb`'s `THIRD_PARTY` regex and in
`lib/review/scan/engines/path_filter.rb:48` — which is one more copy than it needs.

**Fixing `CodeMetrics.public_method_count` is why `NO_GOD_CLASS` moved, and the
correction is worth holding.** It read visibility off a stop marker: the walk ended at
the first `private` or `protected`. Every consequence was an *under*count — a `public`
below `private` re-opens the scope and everything after it went uncounted; `protected`
read as end-of-class; `def self.x` below `private` is still public and the walk had
already stopped; `private def x` and `public def x` are CallNodes wrapping the DefNode,
so neither was ever seen; `class << self` was invisible. Measured across `lib`, `law`
and `tools`: 2,588 public methods before, 2,663 after, twenty classes moved, and
`Ground::RuntimeCatalog` read **0** while having 14, because every one of its methods is
a class method written below a `private`. It is a two-pass visibility model now, with
eight hand-derived cases in `test/test_visibility_semantics.rb`.

Two notes on the patch that came with that finding, kept because they are the reason to
re-derive rather than apply. Its own retroactive-visibility test could not pass against
it — a single forward pass counts a method public before `private :foo` below the def
tells it otherwise — and its `private_class_method` case declared 1 where Ruby gives 2,
since the `initialize` above the bare `private` stays public. **The diagnosis was right
and worth acting on; the arithmetic in the fixtures was not.**

### File sprawl: what is left, and why the limit stops being the argument

`MASTER/lib` is 405 files for 38,217 body lines: a mean of 94 against a 300-line limit.
Ten directories merged with nothing renamed, because Zeitwerk maps `orders.rb` to
`Ground::Orders` and loads `Orders::Autocommit` with it, so a child that already nests
under the directory's constant needs no new name and no caller changes.

**The arithmetic that makes a merge worth anything.** Every child of `x/` repeats the
same `module A / module B / module X` scaffold and its three `end`s, and a merge keeps
one copy: with N children nested D deep, a merge drops `(N-1) * 2D` lines before a
single line of logic moves. The first pass at this added the children's line counts
together and concluded that one directory in nineteen could merge —
`lib/ground/orders` measured 314 code lines as eight files and 271 as one; it was never
over the limit, the sum was.

**And a merge costs `spine.lib_body_ceiling` rather than saving.** `body_lines` excuses
a `module` whose body is exactly one module or class; a merged scaffold holds several,
so the ceremony starts counting. One ratchet rewards one class per file and the other
counts files. That tension is real, and neither number is wrong — but a reduction pass
should expect the spine row to move the wrong way and say so rather than look for a
bug.

Sixteen directories would merge if the 300-line limit were the only obstacle. Judged by
subject rather than by the number:

- `ground/policy` (4 files, 362 lines), `voice/renderer` (4, 377) and
  `cli/routing/model_router` (5, 311) are each one subject and marginally over. **All
  three were attempted on 2026-09-08 and reverted, and the reason is not size.**
  `voice/renderer.rb` does `include GitStatus` at `:21` and its four mixins at `:21-24`
  while the merged modules would land below; `model_router.rb` does the same. Under
  Zeitwerk those are autoloaded on reference — `PromptComponents` has no
  `require_relative` at all and resolves — and in one file the `include` runs before the
  definition exists. The merge is possible: the parent's body has to come **after** the
  children rather than before. A naive fold produces a file that passes `ruby -c` and
  raises `NameError` on every constant. `ground/policy` has no parent file and merges
  cleanly at 370 lines.
- `cli/session` (9, 1,177), `cli/command_registry` (13, 1,530) and `review/scan/rules`
  (16, 3,341) are genuinely several subjects. Leave them.
- `lib/io` (56 files) and `lib/ground` (50) are the two biggest directories and neither
  is a namespace directory — their children do not nest under a shared constant, so a
  merge there needs constants renamed. That is the real remaining work and it is not
  mechanical.

**Deriving a scaffold from the source is unsafe; the path is the only honest source.**
Reading it as "the leading run of `module`/`class` lines" ate each child's own
`class Autocommit` wherever the children are classes rather than modules. The merged
file still parsed, and `Registry` then named six classes that no longer existed — a
green `ruby -c` over a broken tree. The check that caught it was loading the constants,
not parsing the file.

**Deletion is nearly exhausted.** The unreached-file question over the fourteen roots
that load by require or ordered manifest — every tracked file searched, no extension
filter, and a lookbehind that does not exclude `:` — finds three files and 87 code
lines, and two are hand-run operator tools whose loss removes capability:
`OPENBSD/bin/sync_deploy_inventory.rb` and `RAILS/tools/sync_auth_schema.rb`. Neither is
named by any doc, Rakefile or runbook, which is the real finding about them. Rails
`app/` trees are outside this census on purpose: a controller is reached by routing and
a view by render, so a constant search there reports convention as death.

**Absorption by single reader is mostly a mirage.** Eighty-one files have exactly one
non-test Ruby reader and fit the limit combined, but five of those readers are
`lib/builder/boot_phases.rb`, which constructs everything — being its only reader is
what a wiring file means, and folding those five would build the god class the limit
exists to prevent. Others point at a web controller from `lib/`, which would invert the
layering.

Before anyone proposes deleting antigravity wholesale: it is live. `agy` is installed,
`lib/cli/skills.rb:70-76` reads the adapter, and it discovers five real skills today.
`GEMINI.md` does not replace it — that is an instruction file, this is a skills adapter,
and the `agy` row in `data/providers.yml:9` is a third thing sharing the name.

### Method-level reach: the instrument took five attempts

`tools/method_reach.rb` and `tools/method_graph.rb` are the census and its transitive
answer. Both are kept for the faults they found rather than the deletions they made,
because every fault is a class of mistake:

- **Send-prefix dispatch reaches methods with no call site**, nine of them.
- **A name inside a log string is not a call**, and `run_swallow_report` logs its own
  name.
- **An endless method carries its body on the def line**, so skipping the def line lost
  sixteen callers including the only one `undo_line` has.
- **A substring grep for `dispatch_core` matches `dispatch_core_slash_command`**, a
  different method.
- **An interpolation is code.** Blanking string literals blanked
  `"…#{role_description}…"`, the only call four swarm workers have.
- **A setter or an index cannot be reached by name.** `x.model = v` tokenises as
  `model`; `x[k]` as nothing. `model=`, `[]` and `[]=` were dead by construction.
- **A hook is invisible to a call-site census by definition.** `Result` defines
  `deconstruct_keys` twice for `case … in {ok:}` and nothing names it; `core.rb` defines
  `_dump` for Marshal. The `FRAMEWORK` list in `method_graph.rb` is that blind spot
  written down rather than discovered again.

The rule the closure taught: **two independent readings agreeing is the bar for
deleting**, and the transitive layer must be walked by a graph rather than by hand —
deleting `dispatch_review` orphans `review_target`, which orphans `run_tribunal`, which
orphans `snapshot_artifact`, and `snapshot_artifact` reads as reached only because
`data/maturity.yml` names it in evidence prose.

**The `run_*` family this entry used to point at is gone.**
`lib/cli/session/command_ops.rb` is 45 lines and holds three `run_*` methods, not
twelve. And 59 `def dispatch_*` remain in `lib/` and are the live command surface, not
leftovers — do not read the earlier deletion of twenty obsolete handlers as a mandate to
sweep these.

### Scanner Conventions

Seven shapes of one defect: **each converts the absence of a property into evidence of
it.** A gate, a test or a reader accepts something that merely looks like the thing it
was checking for, and the result is a defect that arrives carrying its own certificate
of compliance. Six were found in one week of 2026-08, in different subsystems, by
different sessions; the seventh in RAILS on 2026-09-05, and it had been costing a
thousand assertions a run.

#### 1. A comment outlives the rule it explains

Any check that greps source for a string must strip comments first. A rule and the
paragraph explaining the rule contain the same words, so a raw `include?` /
`refute_includes` matches the prose about a thing as readily as the thing. This fired
four times on 2026-08-10 alone: a test refused a partial for containing `popover` where
the match was the comment recording the popover's removal; a weight test counted three
Stimulus controllers in a partial rendering two, having read the comment quoting the
markup it replaced; and the `nbsp_entity` and pagy-helper rules each flagged the comment
explaining themselves. A fifth, one layer out: a CSS pass "confirmed" a rule had been
deleted from three bundles when sass had preserved the `/* */` comment naming it.

The fix is one line at the read site, and it differs per language:

```ruby
source.gsub(/<%#.*?%>/m, "")          # ERB
source.gsub(%r{/\*.*?\*/}m, "")       # CSS/SCSS block comments
source.lines.reject { |l| l.strip.start_with?("#") }.join   # Ruby, YAML
```

The comment stripper must pick its pattern from the file's extension. Extending one to
`//` and `/* */` for every language mangled
`OPENBSD/installed_targets_gate.rb`'s `CONFIG_GLOBS = ["etc/crontab*", "etc/*.local",
"etc/rc.d/*"]` — the strip ran from `/*` to the end of the line and left `"etc` behind,
which is the abbreviation `COMPLETION_THEATER` flags. The ratchet caught it as registry
0 → 1 in the same sitting.

The failure mode is asymmetric, which is why it matters: a `refute_includes` that reads
comments produces a *false alarm* the next author "fixes" by deleting the explanation.
That is how a codebase loses the reasons for its own decisions.

#### 2. An exemption outlives its subject

When a gate carries an allow-list — exempt paths, baseline numbers, known offenders —
the entries must be **checked against reality, not merely consulted.** An exemption
whose subject no longer exists is a hole in the gate that nobody can see, precisely
because the thing it excuses is invisible.

When `RAILS/FINAL_TODO.md` was deleted it surfaced two immediately, because both tests
named the file the moment it went: `doc_numbers` was still granting it dimension
exemptions and `doc_paths` was still excusing a generated schema path on its behalf.
Neither had had a subject for as long as it took to notice.

`rake lint:autoload` is the shape to copy: it does not merely read its ignores, it
asserts each one is still necessary and fails naming any that is not. Cheap check when
adding one: every path in an allow-list should resolve, and every numeric exemption
should name the file it was granted for. Note that "resolve" needs the right base
directory — a probe that assumed repo root reported 89 phantom stale entries in
`data/autoload.yml`, whose paths are relative to `MASTER/lib/`. Verify the instrument
before believing the finding.

**The same shape can live in the check rather than the list**, which is harder to see:
`doc_paths` decides whether a token is a repo path by asking whether its head directory
resolves, so deleting `MASTER/docs/` made every citation into it invisible to the gate
written to catch stale citations. `docs/SEVERANCE.md` is cited by two governing
documents and checked by nothing.

#### 3. A build artifact outlives the source it was built from

The one that hides best, because while the source stays correct every reader who checks
the source concludes the tree is fine. Found in amber: `public/assets` held a precompile
from before a rename, and in development Rack::Static serves `public/` *ahead of*
propshaft, so the stale bundle won its own route — the browser got July's JavaScript
while the repo held August's. It was noticed only because that copy happened to be
*corrupt* and took every Stimulus controller down with it.

That detail is the warning, not the incident. A corrupt stale artifact announces itself;
a merely outdated one serves last month's behaviour in silence, indefinitely.

- When behaviour contradicts source, check what is being served before re-reading the
  source. `curl` the asset path and diff it against the file it claims to be.
- `public/assets` is gitignored, so this never ships — it is a local-only trap, which
  also means CI cannot catch it for you.
- The same shape reaches production by a different road:
  `MASTER/web/public/face.runtime.js` is generated from the four `face.part*.txt` files
  beside it, and a commit that edits a part without regenerating leaves a stale artifact
  tracked in git. That is why `rake assets:precompile` belongs in the same commit as any
  face-source edit.

#### 4. A staleness alarm silenced by regenerating the artifact

Corollary to 3, and it cost four broken JavaScript call sites in `e7e48eed1`.
`AstFixer`'s `template_literals` transform converted a `+`-chain ending in a *call* by
taking only the callee, producing a template literal invoked as a function: a
`TypeError` on every execution, and **valid syntax**, so `node --check` and the commit's
own "All parse" claim were both satisfied.

Two of the four were caught only indirectly, by
`test_public_asset_manifest_matches_source_files`, whose message reads "generated asset
drifted" — a *staleness* message. Running `assets:precompile` to clear it copies the
broken source over the good digested asset and turns the alarm off without fixing
anything, which is exactly what happened first.

Closed three ways: the call sites restored; the transform now declines any chain
followed by `(`; and `test_public_js_has_no_template_literal_called_as_a_function` fails
on the *shape*, in the tree, rather than through a drift message. When a test reports
drift, ask what the drift is evidence of before regenerating.

#### 5. A test that punishes the improvement it exists to detect

A gate that watches for a finding must be written so that fixing the finding is not a
failure. `RAILS/test/gate_live_and_css_budget_test.rb` asserted that one specific colour
pair measured *below* the AA contrast threshold, with the message "the finding this
pairing exists to surface has gone". Anyone who improved that accent would have been met
with a red test naming their fix as the regression. Nobody was, because it was already
failing for an unrelated reason, so the trap sat armed and invisible behind another red.

1. **Assert the invariant, not the instance.** `refute_empty findings` survives every
   legitimate fix; `assert specific_pair.ratio < threshold` survives none.
2. **Read a name from the constant that owns it.** A test that spells out a value the
   code already names cannot tell a rename from a regression.

The tell is a test whose failure message describes something good happening. Invert it
and ask what a successful fix looks like in CI; if the answer is "red", the assertion
points the wrong way.

#### 6. A writer that reports an edit it did not make

`rake lint:spine RATCHET=1` printed "raise log cleared" and cleared nothing. Its
substitution matched continuation lines only (`    .*`), deliberately, after an earlier
version matched dashed lines only and left the file unparseable — the fix for a loud
failure introduced a silent one, and the comment above it explained the reasoning for a
pattern that had stopped matching anything. The allowance was therefore a countdown to
permanent failure rather than the budget `spine.yml` describes, and nothing could show
it: a cleared log and a log that was never touched look identical from outside.

The fix is not the regex. It is that the task now **reads back what it wrote** and
aborts if `raised` is not empty. A writer that can claim an edit it did not make belongs
to the same family as the others — the absence of a property reported as evidence of it
— and the remedy is the same: assert the outcome, not the attempt.

**In a data file the indentation is the syntax**, and a squiggly heredoc exists to
remove it. Writing a ceiling note into `rules.yml` with `<<~` stripped the four-space
indent off every line, turned the ceiling into a top-level key, and made the file
unparseable — `data_reach`, `self_findings` and all three `rule_audit` rows read
*unreadable* in the same breath. **A census that cannot parse a file reports it clean.**
`git checkout --` put it back and the note went in through an exact-match edit. This is
the seventh time it has cost something in this tree.

#### 7. A root constant that resolves one level too high

`RAILS/brgen/test/source_reader.rb` computed the tree as
`File.expand_path("../../..", __dir__)`. The file is at `RAILS/brgen/test/`, so that is
the repo root and not `RAILS/`. Two guards in the same expression were supposed to catch
it — the chain only accepts a candidate holding `shared/app`, then one holding `shared`
— and both missed, so it fell through to `candidates.last`, which is the wrong path it
had just rejected. **A fallback that ends in "use the last one anyway" is not a
fallback.**

The cost was 39 errors and one failure in brgen's suite, and the number that matters is
the other one: **974 runs carrying 3,486 assertions became 974 runs carrying 4,529**. A
thousand assertions had never run on any checkout that is not `/home/dev/pub4`, which is
the first candidate and why the box never saw it. The two verticals it re-armed —
`InfiniteScrollWiringTest` and `DeployBacklogTest` — are the ones that read source
rather than exercise it.

Same family as `Operator::OperatorDocs::ROOT`, recorded above at four levels instead of
three, and the remedy is the one that entry named: **assert the resolution, not the
reads.** `test_root_resolves_to_the_rails_tree` checks that ROOT holds `shared/app` and
`brgen/app` and is called `RAILS`, because a wrong root fails as a missing file and
reads as a missing file.

#### What follows from all seven

- **A new gate's first run must be against a known-bad input, not a clean tree.** A
  green first run is the least informative outcome available: it is equally consistent
  with "nothing is wrong" and "nothing is measured". Every check added on 2026-08-10 was
  mutated six ways and watched to fail before being believed — and two of them did not
  fail, and were wrong.
- **Registration is not execution.** `rendered_invariants` shipped with an instance
  `run` and no class-level `.run`, which is how `runner.rb` invokes a gate: it was a row
  in `gates.yml`, listed by `--list`, counted as coverage, and never once executed. It
  is the gate written to catch declarations with no reader.
- **A gate must read the source of truth, not restate it.** `domain_alignment` — whose
  whole purpose is proving the fleet's domains and ports agree — held its own literal
  table of the three domain/port pairs. Edit `apps.yml` and it keeps asserting the old
  numbers, and passes.
- **When writing a check that recognises a pattern, name the cases you already know and
  pin them through it first.** An ownership-guard sweep found its own regex matching the
  *fixed* branch, because after `user` comes a dot rather than `_id`.
- **A test that becomes green while measuring nothing is worse than a test that
  errors**, because it now reads as coverage. Two of the three rule tests fixed by one
  `require` line then passed while asserting only that the rule responds to `check` and
  returns an Array, which every `Rule` subclass does by inheritance. Both were rewritten
  against what the rules decide and mutation-checked — nine mutations, nine caught.

### Not Debt

Settled decisions. Do not re-litigate these; each was argued once and the argument is
recorded.

- **The fold spine living inside `lib/`.** Merged 2026-08-12 on operator instruction;
  `DECISIONS.md` records the reversal and what was kept (the no-backedges test and the
  `core_files` invariant). It is measured by the law it applies to everything else, which
  is the point. `spine.core_files` is 7 of 7, and a new top-level concept there is a
  design change rather than a line-count question.
- **One rule registry.** The four `data/rules/*.yml` shards were folded into
  `data/rules.yml` on the same instruction; that directory no longer exists. Their single
  consumer was `load_rules`, which merged them back before any scanner saw them.
- **Local `knowledge/` corpus and generated `output/` artifacts.** Never committed.
- **Deferred WebGL boot.**
- **The gap between the registry classes and the declared rules.** Checked on the theory
  that the difference was inert law — declared rules nothing implements, which would be
  this file's dominant defect class at the constitutional layer. It is not: every
  declared rule has a detection path, in the corpus, in `law/`, or by `folded_into`
  naming the rule that reports for it. `RuleRegistryAudit` measures the split, `SelfTest`
  reads it, and `test_rule_registry_audit.rb` pins it. Re-measured 2026-09-09 at **242
  declared** and 147 built by the registry, split 141 semantic, 15 structural, 0 lexical
  and 92 carrying no detector field — 92 and not the 86 this entry used to say, which
  was the subtraction corrected under "The rule corpus" above. The lexical hatch is
  deliberately idle and
  `RuleRegistryAudit` prints `lexical hatch empty` rather than two zeros a reader has to
  add up — so the day somebody declares a `detect_lexical` again, a test fails and asks
  whether the bridge is still wanted.
- **Media-generation severance.** Re-severed 2026-07-14 (`76b11fec4`), confirmed
  permanent 2026-07-15. The policy reads at `MASTER/DECISIONS.md:124-128`; the
  `docs/SEVERANCE.md` those documents cite no longer exists. If the LoRA training loop
  needs generation capability again, express it as `lib/core/world.rb` handlers per the
  original absorption plan — do not restore the deleted `io/lora_pipeline.rb` or
  `video_chain.rb`.

### External AI proposals are mostly already built

A ~90-item roadmap arrived from ChatGPT proposing an execution model of *intent →
understand → inventory → classify → research → plan → change → test → measure → review
→ report*, natural language as the primary interface, and a final acceptance suite.
Every claim was checked against the tree. **The list below is kept as a guard: these
exist, with the reader named, so do not implement them again.** Line references
re-verified 2026-09-09.

- *Rule applicability* — `law/law.rb`'s `languages`, `path`, `path_exclude` and `scope`
  verbs plus `Rule#applies?` (`law/law.rb:60`; the method is not called `applies_to?`).
  `languages` is used 63 times across `law/*.rb`. This is also the answer to automatic
  design-system activation: `law/css.rb` judges stylesheets by declaration, with one
  deliberate exception — `NO_MULTIPLE_LANGUAGES` at `css.rb:111` declares five languages
  because its subject is a file mixing them.
- *Rule provenance* — all 118 `Law.define` blocks carry `source`, `severity`, `fix` and
  both fixtures, enforced structurally at `law/law.rb:210-215`. `tools/rule_reach.rb` and
  `tools/autofix_reach.rb` detect a rule with no enforcement, and both are ratchet rows.
- *Render before claim* — `rendered_suite`, `gates/support/cdp_session.rb`,
  `visual_contract` and `layout_snapshot`. The doctrine is enforced further than the
  roadmap asks: `GateResult#measured_nothing?` (`OPENBSD/lib/gate_result.rb:169`)
  distinguishes *inconclusive* from *passed*, so a suite that skipped every live check
  cannot report green.
- *Risk classifier* — `lib/cli/fold_risk.rb`, `lib/ground/failure_taxonomy.rb`.
- *Evidence ledger* — `lib/trace/ledger.rb`, `lib/trace/recorder.rb`,
  `runtime/events/activity.jsonl` (`trace/log.rb:57,64`), and
  `.constitutional_violations.jsonl`, written by `trace/hooks.rb:101`.
- *No false completion* — `soul.yml`'s `anti_simulation`, `SURFACE_ERRORS_FIRST`,
  `NO_DEAD_ENDS`, and `GateResult#measured_nothing?`.
- *Provider broker, matrix, fallback* — `data/providers.yml`, `ModelRouter` with
  `failover_config`, `provider_availability` and `escalation` under
  `lib/cli/routing/model_router/`, plus `provider_quarantine`, and
  `circuit_breaker_registry` and `quota_gate` under `lib/io/`. The quota gate already
  classifies the failure, parks the tier, carries the skip into the verdict and re-probes
  on backoff.
- *Boot receipt* — `Ground::BootReceipt` (`lib/ground/boot_receipt.rb:20`), printed by
  `bin/doctor:168`: commit, a digest over the five governing data files, the soul
  version, the three rule populations counted separately, provider availability, and
  capabilities. Deterministic — no clock, no host path — so a changed digest names a
  changed constitution.
- *Offline as a capability* — the receipt names it. `network` is a TCP open to a resolver
  rather than a DNS lookup, because a captive portal answers DNS and nothing else, and
  that case reads as "the model is down". One `network=no` explains every provider miss
  printed under it.
- *Web-vitals budget* — `Deploy::WebVitalsBudget`, registered in
  `RAILS/gates/gates.yml:343` as `web_vitals_budget`. The telemetry it grades is
  `RAILS/shared/frontend/hotwire.js` sampling LCP, CLS and INP at 1% through
  `PerformanceObserver`. INP is deliberately not in the live half: it is defined over
  real interactions, a scripted load produces none, and reading that silence as zero
  would print the best possible score for a page nobody touched.
- *Swarm* — `Review::Swarm::Coordinator#analyse_and_review` (`:180`) is reached from
  `Pipeline::Through#run_critique` (`lib/cli/pipeline/through.rb:308`, called at `:140`),
  carried as the last keyword because `Command#dependency_kwargs`
  (`command_registry/command.rb:59`) zips the registry's positional arguments against the
  keyword names in declaration order. A lean boot passes nil and the stage is the stage
  it was.
- *Local model tier* — `data/models.yml:363-367` declares a Tier-D local tier of three
  Ollama models, `enabled_when_env: OLLAMA_BASE_URL`. Still absent: a hardware probe, a
  bootstrap, and a benchmark. (`agy` is not "marked offline" — it is a CLI binary reached
  by `command:`, with availability through `Master.agy_cli_available?`
  (`lib/boot/runtime.rb:101`); it is keyless, which is a different property.)

**One of its items is genuinely open, and it grew rather than closed.** *Intent has more
than one door.* `CLI::Stages::Intake:37` maps every non-slash line to `:llm`, while
`CLI::IntentRouter` is a separate keyword scorer read by `TurnRouter` (`:103`, `:142`),
`FoldRisk` (`:16`) and `Policy::Orchestration` (`:31`). And `TurnRouter:31-39` now
branches natural language **five** ways — `casual_reply` twice,
`Io::MediaIntent.dispatch`, `dispatch_inferred`, `dispatch_through_workflow` and
`run_fold`. Closing the classifier did not merge the doors; it added to them.

**The framing worth keeping.** The roadmap's closing standard — that MASTER is 10/10
when it does not need to be told how to use MASTER — is the right target, and a better
statement of the goal than any of the items under it. What it underrates is that the
tree's problem has not been missing features for some time: it is discoverability and
detection reach. Three of one day's four survey agents led with an instrument that had
been wrong, and the largest single lead handed to a collapse pass —
`PARALLEL_HIERARCHY`'s 33 findings — was entirely false. **An acceptance suite that
proves the detectors are right is worth more than one that proves the features exist.**

### Tag legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise,
  horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## RAILS
### Parity gaps — forward work

What brgen would need to read as a peer of TikTok, Snapchat, Mastodon, x.com,
Reddit, Craigslist and Facebook, and its verticals as peers of
Amazon/Temu, Tinder/Hinge, DoorDash/Foodora and Messenger. The former
`RAILS/TODO.md`.

This is **not** a second feature inventory — `apps.yml` is feature truth and
the horizon subsection below holds the aspirational items. Everything here is a
gap those two do not record. It carries its own caveat, which still stands:
several entries were stale within a day of being written (price-drop alerts,
takeaway push, the courier/event/story map layers were all built while this
list still called them open). **A finding is a hypothesis; re-measure before
working from one.**

Scope is brgen and its engines. amber and bsdports are not measured against
consumer apps, and their planned work stays in `apps.horizon.yml`. Paths below
are relative to `RAILS/`.

Verified against the tree on 2026-08-19. The reason a gap can exist at all is
that `apps.yml` records a feature as `done` when the model exists, and several
of those models exist with nothing reading or writing them.

---

### Cross-tree session records, filed here by mistake

Four of the five records below belong to MASTER, STUDIO and OPENBSD, not to
RAILS. They were appended under the Tier 1 heading, which promises a schema
nothing reads, and they describe census tools, a STUDIO gate, nine expired
domains and the `/through` stages instead. Only the `constitutional_scan`
budget record is a RAILS gate's. Moving them means editing three other trees'
sections while their agents are in this file, so they are named here and left
where they sit.

#### A census of the census tools: two of thirty-six were reaching nothing — 2026-09-07

Asked of every `MASTER/tools/*.rb`: does anything in the repo name it? Twenty-nine
are named by a Rakefile task, a test, a gate, `bin/operator` or a workflow. The
first pass called eleven unreferenced and **that pass was wrong about five of
them** — it searched for the string `tools/<name>` and the Rakefile spells its
shell-outs `File.join(__dir__, "tools", "<name>.rb")`. Verify the instrument
before the finding, again, and this file's own rule paid for itself inside ten
minutes.

Two were real:

- **`tools/load_order.rb` — deleted.** It guarded dilla's `ENGINE_PARTS`, an
  81-file manifest whose order was load-bearing. The engine is one file now,
  and `engine_sources.rb` says so in its own comment: "Two ways the list could
  lie went with the split … Neither is expressible any more." The tool's regex
  finds no manifest, so it reported "0 manifest entries, every load-time
  constant is defined above its reader" — a clean verdict over an empty set,
  which is the shape STUDIO's own gate test was failing on an hour earlier.
- **`tools/agent_context.rb` — wired.** It prints the law in force in 691
  bytes: the 29 rules that can refuse a write, and how many run without a
  model. That is wish 45 of the list below, already built and named by
  nothing, so it is now in the agent contract every harness file is generated
  from.

`growth.master` is **1048/1047** after this and the doc_paths deletion — one
file over, from three this morning, and both deletions were of instruments
whose subject had retired rather than of anything anyone reads.

#### Two censuses over one subject, and the copy was the unrun one — 2026-09-07

`MASTER/tools/doc_paths.rb` and `MASTER/test/test_doc_paths.rb` both asked
whether a repo path a document cites still exists. The test is run by
`rake test` and by `tools/todo.rb`; **nothing ran the tool** — no Rakefile
task, no gate, no bin script names it — and it carried no baseline, so it
reported eight dead paths of which seven were exemptions the test already
holds in `data/doc_baselines.yml`, each with its argument written out.

The tool is deleted. Its wider sweep is kept where it belongs: the three
documents it covered and the test did not — `MASTER/EXAMPLES.md`,
`OPENBSD/DECISIONS.md` and `OPENBSD/SSH_ACCESS.md` — are in the test's `DOCS`
list now, and all three are clean under it.

The eighth finding was real and is fixed. `OPENBSD/DECISIONS.md` said legacy
path strings "still resolve via `MASTER/lib/operator/paths.rb`", in the present
tense, about a file that does not exist; they resolve through
`RAILS/shared/lib/operator/deploy_paths.rb`, which is what `Operator::DeployPaths` is.
A decision record making a live claim about a missing file is the shape this
guard exists for, and it took an unrun tool to find it.

`growth.master` 1050 → 1049 and `self_findings.registry` 52 → 51 come with the
deletion: one fewer file, one fewer `NO_GOD_CLASS` subject.

#### The STUDIO and OPENBSD suites, run and read — 2026-09-07

Both were run end to end for the first time in this session's memory. They are
the two trees whose tests nothing in MASTER's `rake test` reaches.

**STUDIO's gate declared a tree that no longer exists — fixed.** `gate.rb`'s
`TREES` carried `tools/**/*.rb`, and `STUDIO/tools/` went away at `5a18c40d7`
when `isolation.rb` was hoisted to the STUDIO root. Its own test says what that
costs — "a glob that matches nothing passes every check in the file while
covering nothing" — and it was failing on exactly that. The `gate` entry's
`*.rb` already covers both root files; the dead entry is gone and the owner
line names them.

That unblocked the rest of the suite, because `rake test` aborts at the first
failing sub-suite. What it reached next is real and is dilla's owner's:

**124 hand-cut sample loops have no track preset, so nothing renders them.**
`test_every_hand_cut_sample_loop_is_reachable_as_a_track_preset` says why it is
a test rather than a comment: a loop reaches a render only when a TRACK name
resolves to it, so one with no preset and no alias is selectable by typing
`TRACK=<slug>` by hand and never appears in the medley or the rotation. Nothing
errors. The test was written when three of four measured loops were in that
state; the crate has grown since. Naming 124 presets is authoring, not repair —
it is a musical decision per loop, and this repo's own rule is that a
rendered-sound default is never changed on an agent's judgement.

**OPENBSD is nine suites green and one red for money.** `test_domain_expiry`
fails on nine domains past their expiry date, measured 2026-09-07: brmingham.uk
and glasgw.uk 75 days, lverpool.uk and mnchester.uk 74, dnver.us 66, cardff.uk,
denvr.us and edinbrgh.uk 25, wshingtondc.com 16. Renew at the registrar, then
`OPENBSD/bin/domain_watch.rb --update` refreshes the snapshot. Nothing in the
repo can close this one.

#### One verb with named stages, and all four trees under it — 2026-09-06

Two changes, one subject: what the runtime offers and what it reads.

**The verb.** `command_registry.rb` has carried a closed public surface for
months — its own comment says "Scan/fix/critique stay as methods
ThroughPipeline calls; they are not slash verbs" — so the fold was already
done and nobody could tell, because `TurnRouter.rewrite_slash` mapped every one
of those words to a bare `/through`. Asking to scan ran the fix loop, the
council and the principle map.

Each word now carries the stage it names. `/scan` is `/through --only scan`,
`/critique` and `/council` are `--only critique`, and the words that mean the
whole pass still mean the whole pass. **The scan stage fixes what it finds, on
the spot**, which is why `/scan` and `/fix` name the same stage: a finding is
cheapest to repair at the moment it is found, and a fix loop with no scan in
front of it has nothing to act on. `--no-autofix` and `--dry-run` still hold it
back, which is what `bin/gate` and the RAILS gate pass.

An unknown stage runs nothing and says so. Silently widening a pass because a
flag was misspelled is the failure the flag exists to prevent, and silently
narrowing one is the same failure wearing the other coat.

**The trees.** `constitutional_scan` scanned the Rails half only, so STUDIO's
155 source files and OPENBSD's 107 were governed by a law that never opened
them. It runs all seven targets now — brgen, amber, bsdports, shared, STUDIO,
OPENBSD, MASTER — in **184 seconds**, which is the same gate that cost 48
minutes for one app this morning.

Recording the three new ceilings turned up the instrument defect underneath
them. The gate reads the first `scan: done` line, and that line has two
spellings: `6 violations` and `clean -- no violations`. The count regex knew
only the digits, so a target whose aesthetic pass is clean fell through to the
**deep** pass's number — STUDIO read 317 and OPENBSD 72 against ceilings
measured at 0 in the same run that printed "clean". A target was being judged
on a different profile than its neighbour depending on whether its first pass
found anything. Both spellings count now, and the budget file says in its own
head that every number in it is the aesthetic profile.

Where the seven stand: STUDIO 0/0, OPENBSD 0/0, MASTER 15/15, brgen 15/27,
amber 4/28, and the two that were already over — bsdports 6/3 and shared 15/8,
whose findings are spacing and colour values in a design its owner drew.

#### `constitutional_scan` was unaffordable, and two of its four budgets are over

The gate shells `/scan` at `MASTER/bin/cli` once per app, and `SAFE_ENV`
disabled autofix, background, watch and heartbeat but never asked for the
deterministic tier — so the runtime handed the scan an agent and every file
cost a model round trip. Measured 2026-09-06: **brgen alone ran 48 minutes of
wall clock against 35 seconds of CPU**, idle in a TLS read, which is the exact
stall `MASTER_SCAN_DETERMINISTIC` was added to MASTER for. `capture2e` has no
timeout, so there was no bound on it either. With the flag and a
`GATE_SCAN_TIMEOUT_S` bound, all four targets finish in **113 seconds**.

What that uncovers is the part that matters. The gate has been failing, and
nobody could see it because nobody could run it:

    brgen      15 / 27   under
    amber       4 / 28   under
    bsdports    6 / 3    OVER +3
    shared     15 / 8    OVER +7

Verified against `2e2e464c2` — the same numbers before this session's rule
changes, so the overage is the tree's, not the instrument's.

**The findings are CSS and this repo says not to touch them on my own
judgement.** bsdports is `EIGHT_PX_RHYTHM` ×4, `CHOICE_OVERLOAD` and
`SIGNAL_NOISE`; shared is `EIGHT_PX_RHYTHM` ×6, `MAGIC_COLOR` ×3,
`NO_DECORATIVE_FX`, `TOUCH_TARGET_MIN`, `CONTRAST_TOKENS`, `RAMS_UNOBTRUSIVE`,
`REDUCED_MOTION` and `WHITESPACE_RHYTHM`. Every one is a spacing, colour or
motion value in a design its owner is a trained architect of, and
`RAILS/CLAUDE.md` says restore or ask, never invent a layout fix.

One thing to know before acting on the number: the gate reads the **first**
`scan: done` line, which is the aesthetic profile. The full profile in the same
run reports 60 for bsdports and 187 for shared. The budgets were recorded
against the aesthetic number, so the row is consistent — but it is a narrower
claim than "constitutional preflight" sounds, and re-basing it against the full
profile is a separate decision with four new ceilings in it.

### Tier 2 — structurally absent

#### 2.1 No federation (Mastodon) — **done, outbound half**

A brgen account can now be followed from anywhere in the fediverse and its
public posts deliver outward. WebFinger, NodeInfo, actor documents, outbox,
followers, a verified inbox, HTTP signatures, per-inbox delivery with retry.

The city partitioning does the work: `@kari@brgen.no` and `@kari@oshlo.no` are
different accounts because the cities are already different origins with
different populations, which is the same shape as two Mastodon instances. Every
lookup resolves against the *requested host* — answering for the wrong city
would hand a stranger's posts to whoever asked.

Security decisions, since the inbox is where an unverified string becomes an
action:

- **The signer and the claimed author must match.** Without that check a valid
  signature from any actor authorises an activity attributed to any other, and
  every account is forgeable by anyone with an account anywhere.
- **Partial coverage fails closed.** A signature over nothing but `Date` is a
  valid signature that proves nothing about the request, so
  `(request-target)`, `host`, `date` and `digest` are all required.
- **The Digest header is checked**, or a signed request can carry any body.
- **Signatures expire** (5 minutes), so a captured request cannot be replayed.
- **Delete only removes what its sender owns.** A verified signature proves who
  is asking, not what they may ask for.
- Bodies are capped before parsing; keys are cached, because re-fetching an
  actor per inbox POST makes our inbox an amplifier pointed at whoever is being
  impersonated.
- The followers collection reports a count and lists nobody. Who follows a
  small-city account is worth more to a scraper than to anyone else, and the
  protocol does not require publishing it.

Keys are RSA-2048 generated on first use, not at signup — brgen mints a real
`User` row for every cookieless visitor and almost none of them federate.

**Check:** `brgen/test/lib/fediverse_signature_test.rb` (10, every way
verification can be got wrong), `brgen/test/controllers/fediverse_test.rb` (10,
discovery and the city boundary), `brgen/test/controllers/fediverse_inbox_test.rb`
(12, including impersonation, body-swap, replay and duplicate delivery).

**Still open — the inbound half.** Remote `Create`, `Announce` and `Like` are
verified, recorded as seen and then dropped: brgen does not store remote posts.
That is deliberate rather than unfinished — ingesting them means remote media
proxying, remote content moderation (`ModerationReport` has no model for
content whose author is not local) and a blocklist story, each of which is
larger than everything above. The handler says so instead of pretending.

Still open: inbound storage. There is no `RemotePost` model or table, which is
the half the paragraph above says is deliberate.

#### 2.2 No `Event` model (Facebook) — **done**

The largest missing noun on the list, and the one with the most already sitting
underneath it: `Place`, `PlaceCheckIn`, `Neighborhood`, the maps engine, and a
city-strip on the home page that now carries `EventCreated`.

`Event` + `EventRsvp`, with the decisions worth keeping:

- **Location is two-sided.** An event either points at a `Place` (which fills in
  coordinates, venue name and neighbourhood at validation) or carries free text.
  Requiring a Place means nobody can post a party in their own flat; requiring
  coordinates means nobody can post before the venue is settled.
- **`upcoming` means "has not finished", not "has not started"** — a three-day
  festival is still on during day two, and dropping it at the opening minute is
  how a what's-on page lies.
- **RSVP is three-way.** "Interested" is the majority answer on every event
  platform; collapsing it into going/not-going both overstates attendance and
  loses the reminder signal. Pressing the answer you hold withdraws it.
- **The counts are recounted, not counter-cached.** Rails increments on create
  and decrements on destroy, and a status moving from going to interested is
  neither. `update_columns` writes `updated_at` by hand, because the card is
  fragment-cached on `[event]`.
- **Cancelling is not deleting.** People have it in their calendar; `cancel!`
  notifies everyone who said they were coming and the event stays readable.
- `capacity` nil means unlimited, and `places_left` returns nil rather than 0 so
  it cannot render as "0 places left". A full event still takes "interested".

**Check:** `brgen/test/models/event_test.rb` (12) and
`brgen/test/controllers/events_controller_test.rb` (9).

**The map pin is built, and was already checked.** `Maps::HomeController#events_layer`
draws every published event that has not finished, has coordinates, and starts
inside a seven-day horizon — a map that reaches further ahead is a wall of pins
rather than an answer to "what is on near me".

**Check:** `brgen/test/controllers/maps_layers_test.rb` (6), which covers all
four layers: an event with coordinates is pinned, one beyond the horizon is
not, a place carries its own name rather than the string "Map point", an
expired story is gone, and a courier is drawn for the customer waiting on that
order and for nobody else.

Recorded because closing this line cost a wrong turn worth more than the line:
the check was hunted for by grepping the test tree for `events_layer` and
`points_json`, neither of which a test that reads `data-map-points-value` off
the rendered page contains. Searching for the implementation's vocabulary
inside a test that speaks the browser's is the same instrument error as
searching for the noun when only the verb is written — 1.2 above records the
first instance of it, in this same subsystem.

**Still open:** recurring events, and ticketing beyond an external link.

#### 2.3 No Story / ephemeral media (Snapchat) — **done**

Ephemerality existed only inside DMs. `Story` + `StoryView` put it on a public
surface.

- **The lifetime is a column, not a computation.** `expires_at` is stored, so
  the `alive` scope, the countdown label and the sweep all read one value rather
  than each re-deriving 24 hours and eventually disagreeing.
- **`alive` hides an expired story before the sweep runs**, so a link stops
  working the moment it should rather than whenever the job catches up. The
  sweep is about the bytes: `destroy`, not `delete_all`, so the Active Storage
  blobs go with the rows on a 1 GB VPS.
- **Seen is a set, not a log.** Opening twice is one view and the author's
  viewer list never repeats a name. `create_or_find_by!` was wrong here — it
  rescues the *database's* uniqueness error, and the model validation fires
  first, so a second open raised instead of reading as "already seen".
- **Camera-first**: the file field carries `capture="environment"`, which opens
  the rear camera on a phone and degrades to a file picker on a desktop.
- **The area comes from the position the app already has.** `locations#update`
  stores it coarsened to ~1 km; the compose form opts in rather than taking a
  fresh GPS read. The existing `geolocation` Stimulus controller POSTs to that
  endpoint and has no form-field targets, so hidden inputs wired to it would
  have been controls that do nothing.
- A ring is a person, not a photo: grouped by author, followed authors first.

**Check:** `brgen/test/models/story_test.rb` (10) and
`brgen/test/controllers/stories_controller_test.rb` (7).

**Closed 2026-08-19.** The Snap-Map is `Maps::HomeController#stories_layer`,
which is only acceptable because the coordinates are coarsened to ~1 km on write
— a pin says "around here", not "at this address".

A reply is a direct message carrying the story it answers, so it stays readable
after the 24 hours are up; only `alive` stories take one, because a reply box
that still works after the sweep is a promise broken quietly.

`StoryStreak` counts days running that two people have answered *each other* —
mutual, because a streak one person can hold up alone is a posting counter
rather than a pair still talking. Whether it is over is computed on read: a
sweep that has not run yet would leave a dead streak on the page, and the answer
is one date comparison.

**Found while wiring the reply box, and fixed:** `Conversation.direct_between`
read `for_user(a).for_user(b)`, which looks like an intersection and is not —
both scopes join the same association, Rails collapses them, and the predicates
AND on one participant row. It always answered nil, so `find_or_create_direct`
always created, and **every pair of people got a new DM thread each time they
opened one from a different button**.

#### 2.4 `Community` was eight columns (Reddit) — **done**

Roles on `community_memberships` (member / moderator / owner), plus rules,
flair, privacy, icon, banner, `members_count` and an archive flag on
`communities`. A community can now be run by its own members.

- **Owner is a membership row, not just `communities.user_id`.** The creator
  gets one on create, and the migration backfills every existing community —
  otherwise each one predating today has an empty moderator list and nobody who
  can appoint anyone.
- **The last owner cannot be demoted.** Nothing else in the app creates an
  owner, so that is not a state to recover from later.
- **Only an owner appoints.** If a moderator could change roles, one could
  demote the person who made the community, and there is nothing above them to
  appeal to. Moderators may edit rules and flair; only an owner may delete.
- **Reading and posting are separate questions.** Restricted is the interesting
  case: the whole city reads it, only members post. Enforced in the controller,
  because a hidden compose link is not a permission check.
- **The queue is derived, not denormalised.** `ModerationReport` is polymorphic
  and carries no `community_id`; `Community#moderation_queue` reaches it through
  the community's posts and their comments, so there is no column to backfill
  and keep true.
- Flair is the label itself on `posts.flair`, not an id — flairs are edited as a
  text list, so an id would dangle the moment a community renamed one.

**Found while wiring it, and fixed:** `ModerationWorkflow#transition!` read the
polymorphic `report.reportable` on a report loaded by `find`, raising under
strict loading *after* the status had been written — **`Admin::Reports#update`
has been on that path the whole time**, so resolving any report from the admin
queue 500'd. And `communities#show` compared `Current.user != @community.user`,
a lazy read that raised for every signed-in visitor while rendering fine for
guests — the same shape as the tv video page.

**Check:** `brgen/test/models/community_governance_test.rb` (9) and
`brgen/test/controllers/community_moderation_test.rb` (9).

**Bans are built.** A mod queue that can resolve a report but not stop the
person who caused it is half a tool: resolving takes the content down and the
same account posts the same thing a minute later.

`CommunityBan` is its own table, not a flag on `community_memberships`, because
a public community takes posts from anyone — the person to ban usually has no
membership row, and inventing one to hold the ban would make them a member and
bump `members_count` in the act of banning them. Checked before privacy in
`postable_by?`, since a public community is exactly where a ban has to bite.

Scoped to the community and nowhere else: one community's moderator silencing
someone across the whole city is not a lever that should exist. Temporary bans
lapse on their own; a moderator cannot be banned without being demoted first (a
fight the app should not settle); any moderator can lift any ban, because a mod
team that cannot undo each other's mistakes escalates everything to the owner;
and the banned person is told with the reason, because a ban nobody is informed
of reads as the site being broken.

**Check:** `brgen/test/models/community_ban_test.rb` (10) and
`brgen/test/controllers/community_bans_controller_test.rb` (6).

**Crossposts and the wiki are built (2026-08-18).** A crosspost is a `Post` in a
second community with its own comment thread, not a join row — a repost boosts
into followers' timelines and belongs to no community, which is the other act. A
crosspost of a crosspost points at the original, or "seen in four communities"
cannot be answered without walking a chain. `postable_by?` is the whole
permission check, so a community that banned an account cannot be reached
through a crosspost either.

The wiki is `CommunityWikiPage` plus `CommunityWikiRevision`: moderators write,
whoever can read the community reads. Writing goes through `revise!` rather than
`update!`, so no caller can save a page and forget the revision, and a revert is
a new revision rather than a deletion of the ones after it — a wiki whose
history can be edited is a wiki nobody can audit.

**Check:** `brgen/test/controllers/crossposts_controller_test.rb` (5),
`test/models/community_wiki_page_test.rb` (5),
`test/models/community_wiki_revision_test.rb` (4),
`brgen/test/controllers/wiki_controller_test.rb` (5) — the class inside is
`Communities::WikiControllerTest`; the namespace is not a directory.

**Still open:** nothing in this entry.

#### 2.5 No vertical video surface (TikTok) — **done**

`tv.­*/feed`: one video per screen, ranked by watch time. `home#index` stays as
it was — the grid is the YouTube answer to "what is there", and this is the
other question.

Only possible because 1.2 records watch time. Ranking a feed on `views_count`
would have served whatever got the most accidental clicks, since that counter
is incremented on page load.

- **Snapping is CSS, not JS.** The browser already does momentum,
  rubber-banding and keyboard paging correctly; a hand-rolled scroller gets at
  least one of those wrong on some device. Stimulus only decides what plays and
  what gets recorded.
- **`100dvh`, not `vh`** — mobile browser chrome collapses on scroll, and `vh`
  leaves a strip of the next video showing under the address bar all the way
  down.
- **No `autoplay`, `preload="none"`.** Ten videos preloading at once is a few
  hundred megabytes on a phone; the controller plays the visible one and pauses
  the rest. `muted` + `playsinline` because iOS refuses to autoplay anything
  else, and sound is opt-in.
- **Watch time is the furthest point reached, sampled while it plays** — a
  looping video's `currentTime` returns to zero, so the max is the only honest
  number. Reported with `sendBeacon` on scroll-away and unload.
- A video with no file is not in the feed at all: a blank screen you cannot
  scroll past is worse than a shorter feed.
- **Logged-out viewers count.** brgen mints a real `User` per visitor, so their
  watch time ranks too — for video that is the point, since most viewers are
  never signed in. `PruneGuestUsersJob` `destroy_all`s those users and the view
  events are `dependent: :destroy`, so the rows go with them.

**Found while wiring it:** the nested view-events path carries the video's slug
(`Sluggable#to_param`) and the create action looked up by `id` — the third time
that trap has appeared today, after `post_vote_path` and `post_repost_path`.

**Check:** `brgen/test/controllers/tv_feed_test.rb` (6), including that one
viewer who watched a clip through outranks 500 page opens.

Live streaming stays blocked — see "Blocked" below.

**Closed, and the line here was the last to know.** `Sequencing` below has
recorded tv sounds as done since 2026-08-20 while this paragraph still called
them open — two statements about the same subject in one file, disagreeing.
`Tv::Sound` is the audio identity: a clip that names no
sound becomes the origin of its own, a second clip reuses it and the count
follows, and the sound page is the "more of this" surface. A duet names its
original and inherits its sound, and a video may refuse answers. Deleting the
source clip leaves the sound, or every remix loses its parent with it.

**Check:** `brgen/test/controllers/tv_sounds_and_duets_test.rb` (6).

---

### Tier 3 — per-surface parity

#### Marketplace (Amazon / Temu) — **basket done**

`Marketplace::Order` is a per-listing *offer* with its own payment, which is the
right shape for classifieds: a bike from a stranger is negotiated, not added to
a cart. It was the wrong shape for a shop — four things meant four payments,
four PSP round trips and four card charges, with nowhere to put an address.

So `Marketplace::Checkout` sits **above** the orders rather than replacing them,
and both shapes keep working. One basket, one payment, one address, many orders,
split by seller for fulfilment.

- **`Marketplace::Address` is its own record**, so a second purchase does not
  mean typing it again and a later edit does not rewrite the address printed on
  last month's label.
- **Fulfilment is a separate axis from payment.** A paid order that has not
  shipped and a shipped order awaiting payment are both real states; collapsing
  them into one column is why "where is my parcel" goes unanswered. `ship!`
  carries a tracking code and tells the buyer.
- **`stock` is nil for one-of-a-kind**, a number for a shop. Defaulting to 1
  would have made every private sale read as a shop with one left.
- **Paying is all-or-nothing** — a half-paid basket, one card charged, is the
  state nobody can resolve.
- The payment services stopped reading `order.listing.currency`/`.title` and now
  ask the payable for them, so a basket goes through the *same* guarded path
  (including the sk_test_-key-in-production guard) rather than a second one.
- Check order in `checkouts#create` is the order a buyer should meet it in:
  nothing to pay for → provider unconfigured → no address → then a basket.
  Getting this wrong produced a `DoubleRenderError`, i.e. a 500 for a buyer who
  had simply not saved an address.

**Check:** `brgen/test/models/marketplace_checkout_test.rb` (8) and
`brgen/test/controllers/marketplace_basket_test.rb` (5).

**Listing Q&A is built (2026-08-19).** Asking went through the offer thread, so
the seller answered "is it still available" once per buyer and the answer left
with them. `Marketplace::Question` is public on the listing, answered by the
seller, notifying both ways as kind `alert` (which is pushable). Answered
questions sort first; an unanswered one still shows, because it is the question
the next buyer has too.

**Check:** `brgen/test/controllers/marketplace_questions_test.rb` (3).

**Depth is built.** `Marketplace::Variant` + `VariantOption` are the real
schema this entry asked for rather than a column; `Marketplace::Return` and
`Marketplace::Payout` are the money half, and the payout rules are the part
worth keeping: paying does not enqueue a payout, delivery does, a release with
no Stripe stays pending rather than reading as sent, and a received return
voids a pending payout without claiming a refund Stripe has not confirmed.
`ListingFacets` counts what remains once a facet is picked — ignoring its own
filter, respecting the others — and the saved list is `/wishlist`, not
`/saved`, because the host declares `saved` before it mounts the engine.

**Check:** `brgen/test/controllers/marketplace_variants_test.rb`,
`marketplace_returns_test.rb`, `marketplace_saved_and_facets_test.rb`, and
`brgen/test/models/marketplace_payout_test.rb` (5).

**Countdown is built.** `Deal#ends_in` is the remaining seconds, or nil with no
end or after it; the card and the show page render `marketplace.deals.ends_in`
through `distance_of_time_in_words`. No extra Stimulus.

**Still open:** coupons, referral credit and bundle pricing have no model at all.

Solidus remains blocked — see below — so all of this is native-path work.

#### Dating (Tinder / Hinge) — **ranking and prompts done**

The deck was `ORDER BY RANDOM()`: orientation, neighbourhood and a 20 km radius
filtered the pool and nothing ranked it, so someone last seen in March sat
beside someone online now — and every reload reshuffled, so a profile you had
just passed could not be found again.

`Dating::Profile.ranked_for` orders by three things, in this order:

1. **recency** — who is actually around; a deck full of dormant accounts is a
   dating app nobody matches on;
2. **effort** — profiles with prompts answered, because that is what gives the
   viewer something to reply to;
3. **a per-viewer, per-day shuffle** — stable while someone browses, different
   tomorrow, and different between two people.

Deliberately *not* attractiveness, engagement, or any like-count feedback loop:
ranking people by the attention they already receive is how these products end
up with a handful of accounts getting everything.

The shuffle is a per-viewer **multiplier** over a prime modulus, not an offset.
The first version added a per-viewer salt, which shifts every id equally and
leaves the order identical — the test that two viewers see different decks is
what caught it.

`Dating::Prompt` is the Hinge half: a fixed question list (free text becomes a
second bio), three per profile, and a like that points at one answer and says
something about it. Plain likes still work — a product that refuses one is a
product people stop using at 1am. Prompt ids are scoped to the liked person's
own profile, or a like could point at a stranger's answer.

Who-liked-you is its own page, not folded into the deck: people who have already
said yes are a different decision from people who have not seen you.

**Check:** `brgen/test/models/dating_ranking_test.rb` (8) and
`brgen/test/controllers/dating_likes_test.rb` (6).

**Unmatch is built.** `Dating::Match#unmatch!` writes `unmatched`, drops the
mutual likes so the pair can like again, and rematch flips the same row back
to `matched` rather than inserting a second pair. The matches list is still
`active` (matched only); destroy is scoped to a participant.

**Check:** `engines/dating/test/models/dating/match_test.rb` (likes cleared,
rematch, strict loading) and `brgen/test/controllers/dating_unmatch_test.rb`
(participant can, stranger 404s).

**Rewind is built.** Last pass only: `Dating::Dislike.rewind!` destroys the
most recent dislike and the deck query already excludes dislikes, so that
profile comes back. A like is a different decision (it may have created a
match) and is left alone. Empty rewind is a flash, not a 404.

**Check:** `brgen/test/controllers/dating_rewind_test.rb` (last pass undone,
a like is not).

**Verification and daily picks are built.** `Dating::Verification` asks for a
named pose and carries it into the review, requires a selfie, and allows one
open request at a time; only the configured admin reviews, and a blank admin
address makes nobody a reviewer rather than everybody. `Dating::DailyPick`
draws once and stays put for the day, and does not repeat a face already shown
this week — a picks list that reshuffles on reload is the same defect the deck
had before it was ranked.

**Check:** `brgen/test/controllers/dating_verification_and_picks_test.rb` (6).

**Still open:** super-like and boost, both purchases — `apps.horizon.yml` has
them as `agent: ignore`.

#### Takeaway (DoorDash / Foodora) — **hours, tips, scheduling done**

`Takeaway::OpeningHour` is a row per weekday, not a JSON blob: "is this open
now" is a query, and a blob turns the restaurant list into a Ruby loop over
every row on the page. Minutes past midnight rather than a `Time` (which
carries a date and a zone that mean nothing here), and `closes_minute` may
exceed 1440 — because closing after midnight is normal for a kitchen, and
reading only today's row says a place open until 02:00 is shut at 00:30.

- **No hours recorded = open.** Most restaurants have none yet and defaulting
  to closed would empty the listing; `active` stays the "not trading" switch.
- **A closed kitchen still takes a scheduled order** — that is most of what
  scheduling is for. Enforced in the controller, because a hidden button is not
  a closing time.
- The tip is in the total from `calculate_totals!`, not added somewhere later.
- A scheduled order estimates from **when it was asked for**, or it is
  permanently late for having been placed that morning.

**Check:** `brgen/test/models/takeaway_hours_test.rb` (8).

**Order-again is built.** `orders#again` copies available items at current
prices onto a new pending ticket with the same address. Items that left the
menu are skipped; if none remain, the diner is sent to the restaurant rather
than placing an empty order. Tip and scheduled_for stay off — those are
per-ticket. The show-page "reorder" control is a POST, not a link at the
menu.

**Check:** `engines/takeaway/test/models/takeaway/order_test.rb` (`build_reorder`)
and `brgen/test/controllers/takeaway_order_again_test.rb` (copy, skip-empty).

**The live courier map is built** — see 1.4; the maps engine draws the viewer's
own courier while the order is out for delivery.

**Group orders are built.** The host opens the ticket and gets a token rather
than an id — a numeric id in a link people forward around is an invitation to
read the next table's order — anyone with the link adds their own line, a line
can be taken back only by whoever added it, and a confirmed ticket takes no
more. Shares name what each person owes without the delivery fee, because
splitting a fee four ways is a decision the host makes, not one the app makes
for them.

**Check:** `brgen/test/controllers/takeaway_group_orders_test.rb` (6).

Web push on each `transition_to!` is on the path too: `order` is in
`PUSHABLE_KINDS`, so a transition reaches a lock screen rather than only the
in-app list.

**Still open:** nothing in this entry.

#### Messenger — **reply, edit and unsend done**

Typing indicators, read receipts, reactions, presence, disappearing messages and
attachments were already there.

- **Reply-to**: in a channel with several conversations at once, a message with
  no referent is one nobody can follow.
- **Editing is bounded to 15 minutes.** A message that can be rewritten hours
  later is one a reader cannot trust, and the receipt saying they read it is
  already gone.
- **Unsending has no window at all** — a message sent to the wrong room, on a
  chat where people post real addresses, is a safety problem rather than a typo.
- **The unsend is soft.** The row stays and the body goes, because a hard delete
  leaves a hole in a thread and orphans whatever replied to it. That required
  exempting deleted messages from the content presence validation, or the record
  is permanently invalid and every later save on it — a receipt, a reaction —
  fails.

**Check:** `brgen/test/models/message_edit_test.rb` (7).

**Closed 2026-08-18, except the calls.** Voice messages, forwarding, link
previews, message search, group naming with admin roles, and pinned
conversations are built.

The recorder writes into the composer's own file field, so a voice note goes
through the same create path as a photo — `duration_seconds` and `Message#voice?`
had shipped and nothing in the tree could produce an audio message. An
attachment is now a message on its own: a voice note has no words in it by
definition.

Forwarding is a copy, not a pointer: the copy has to outlive the original being
unsent, it belongs to the forwarder, and its readers usually cannot open the
thread it came from. Both ends are scoped to the reader's own conversations.

Link previews carry title, site and summary and **no image**: hotlinking one
tells that server the IP of everyone in the thread, and proxying it is remote
media hosting — the problem 2.1 defers. One row per URL, so the same article in
twenty rooms is one fetch rather than twenty pointed at whoever was linked.

Search reads `visible.unexpired` like every render does, or ephemerality would
be a rendering choice rather than a promise.

A group DM is a `Conversation` with a name and no slug (a #channel is one with a
slug), and roles reuse the IRC ladder already on the participant row. Ops rename
and remove; any member may add, because a group where only the founder can bring
someone in is one people work around by starting a second group. The last op
leaving hands the room to the longest-standing member rather than trapping them
in it.

Pinning is per-participant and a timestamp: a pin on the shared row would let
either side reorder the other's inbox, and pinned threads order among
themselves.

**Found while wiring the controls, and fixed:** reply, edit and unsend had a
route, a model method, a test each — and no control on any page. A backend
nobody can reach is not a feature.

**Check:** `brgen/test/controllers/{conversation_pins_controller,conversation_search,message_forward,group_conversations_controller,voice_message}_test.rb`
and `test/models/link_preview_test.rb`.

**Still open:** no WebRTC anywhere, so still no voice or video calls.

#### Craigslist — **expiry, renewal and the non-goods verticals done**

Geo listings, categories, city subdomains, casual (no-store) listings,
buyer–seller chat and FTS were already there. Listings now expire after 45 days
and can be renewed.

**Expiry is a scope, not a state change.** `live` (active *and* unexpired) is
what the policy scope resolves for public surfaces; `active` still includes a
lapsed listing, which is what lets its owner see and renew it. A listing that
silently vanished from its own seller's account would read as a bug rather than
a policy. Renewing restarts the window from now, so renewing late does not
immediately expire again, and it clears the notice flag so the next lapse is
announced too.

**Check:** `brgen/test/models/listing_expiry_test.rb` (8).

**A listing has a kind.** `goods`, `job`, `housing` or `gig`, with three detail
tables behind the three new ones — employment type and a salary range, rent and
deposit and rooms, gig pay and start time. Price is required only where a price
means anything, so a job advert no longer has to name one. The index filters by
kind and defaults to goods, and the top-offers strip filters with it: it drew
from every listing there is, so the moment a second kind existed a bicycle
search carried a job advert above it.

**Check:** `brgen/test/controllers/marketplace_kinds_test.rb` (8), which also
pins the 2FA guard reached from inside an engine — `two_factor_required?` turns
on once an account has an active listing, so every seller's second listing was
a `UrlGenerationError` 500 against a host path the engine's route set does not
hold.

**Still open:** the anonymised contact relay — it needs mail infrastructure
(inbound routing and per-listing addresses), which is an operator change on
vm23 rather than app code, and `brgen.no` mail is only outbound-verified today.

---

### 134 ways to feel instant — forward work, 2026-08-29

Was `RAILS/INSTANT.md`, a per-tree backlog at a tree root that nothing in the
repo named. This file is the one backlog, so it is here. Nothing below has
been re-measured since it was written; read the caveat in its last section
before working from any item.


Proposals for making brgen, amber and bsdports read as fast, 2026-08-29.

Speed and the feeling of speed are different problems and only one of them is
about milliseconds. A page that paints in 400 ms and moves under your thumb
feels quicker than one that paints in 200 ms and sits still while it thinks.
Both are worth having; they are not the same work, and confusing them is why
most performance passes make a site measurably faster and subjectively the same.

Marked **[built]** when the tree already does it — audit reach before proposing
is this repo's own rule, and thirteen of the items below were already here.
**[cheap]** is an afternoon, **[deep]** is a project, **[yours]** is a decision
rather than work.

Grounded in what these three apps actually run today: Turbo 8 with
`turbo_refreshes_with :morph`, Solid Cache/Cable/Queue and importmap with no CDN
pins.

**Every other number in that sentence was wrong, re-measured 2026-09-10, and two
of them carried the argument for half the list.** Stimulus controllers are 68,
not 30 (28 in the apps, 40 in `shared/frontend`). Pagy is in 37 controllers, not
13. Three views fragment-cache, not zero — `brgen/posts/_post`,
`brgen/events/_event` and `amber/posts/_post`, each on a composite key that
includes the viewer's vote. And conditional GET is one response in all of
`RAILS/`, `bsdports` `ports#show`, not two in brgen: brgen has none.

Two things fall out of the re-measurement, and they are the reason the D section
is not the afternoon it reads as:

- **The composite cache key forecloses `cached: true`.** `render collection:,
  cached: true` builds its own key from the partial; `_post` keys on
  `[post, voted, reposted, quote]` because the card carries per-viewer output.
  Item 66 cannot be had without giving that up, and giving it up renders one
  viewer's vote state to everyone.
- **A per-view counter and a fragment cache cannot both be right.** The
  marketplace card is the obvious next cache and it renders
  `listing.views_count`, bumped by `increment!`, which does not touch
  `updated_at` — so `[listing]` would never bust and the count would freeze.
  `touch: true` busts on every view and buys nothing. Item 64 names this trap;
  what it does not say is that the trap is what stops item 61 from spreading.

Item 4 and item 5 are built and the list never knew: `shared/frontend/hotwire.js`
observes LCP, INP and CLS through `PerformanceObserver` and POSTs them to
`WebVitalsController`, which logs rather than writing a table — a defensible
choice on a 1 GB box, and the only half of 4 still open. Items 7 and 8 are built
too, in `shared/config/initializers/bullet_and_profiler.rb`, which also records
why they were inert before it existed. Item 21 verifies clean: no
`data-turbo-cache="false"` exists anywhere in the tree.

#### A · Measure first, because the instrument is usually wrong (1–13)

This tree's stated dominant defect is that measurement code is wrong more often
than the code it measures. Everything below this section is guessing until
something here is running.

1. **Server-Timing headers on every response**, so the browser's own network
   panel shows view / db / cache split without a profiler. **[cheap]**
2. Emit `Server-Timing: miss` vs `hit` for the fragment cache, so a cache that
   never hits is visible rather than assumed.
3. A `RAILS/gates/` check that fails when p95 server time on the route manifest
   crosses a ceiling — a ratchet, like every other gate here. **[deep]**
4. Real User Monitoring for the three Core Web Vitals via `PerformanceObserver`.
   **[built]**, except that the endpoint logs rather than writing a table.
5. Record **INP**, not FID. FID measured how fast the first tap was
   acknowledged; INP measures every interaction. **[built]**
6. Log the **slowest 1% of interactions with their target element**, so "the app
   feels slow" becomes "the compose button takes 340 ms".
7. `rack-mini-profiler` is mounted in development by
   `shared/config/initializers/bullet_and_profiler.rb`. **[built]**
8. Bullet for N+1 detection in development and test, raising in test rather than
   logging. **[built]**, in the same initializer.
9. A boot-time query counter per controller action, asserted in a test. Query
   count is the metric that regresses silently.
10. Track **payload bytes per route** in the same manifest the probe uses, so a
    view that doubles is caught by a number and not by a reader.
11. Measure on the box, not the Mac. vm23 is 1 GB and 1 vCPU; a 12 ms local
    render is not a 12 ms production render. **[yours]**
12. Keep a **before/after pair for every change in this document**. A filter can
    be wired correctly, run without error, and be transparent.
13. Screenshot-diff the first 300 ms of a navigation, not just the settled page.
    Perceived speed lives entirely in frames nobody currently looks at.

#### B · Navigation — the single biggest lever here (14–37)

14. **`data-turbo-prefetch` on hover/touchstart** for the nav bar's eight
    destinations and every feed link. Turbo 8 ships this; it is off by default
    on nothing, but the app sets it to `false` in one place and never on. A 65
    ms hover before a click is 65 ms of free head start. **[cheap]**
15. Prefetch on `mousedown` rather than `click` — worth ~80 ms and costs
    nothing.
16. **`data-turbo-preload` on the top ten destinations**, so they are in the
    Turbo cache before the first click. **[cheap]**
17. Cap preload to what a 1 GB box can serve; preloading everything is a
    self-inflicted DDoS on vm23. **[yours]**
18. `turbo_refreshes_with :morph, scroll: :preserve` is set in
    `ApplicationController`. **[built]**
19. Extend morphing to the feed so a new post arrives without losing scroll
    position or an open composer. **[cheap]**
20. `data-turbo-permanent` on the nav bar, the theme toggle and the player, so
    they survive a navigation without re-initialising. Three exist already; the
    nav bar is not one of them.
21. **Instant back/forward** via Turbo's restoration cache — verified, nothing
    defeats it: `data-turbo-cache="false"` appears nowhere. **[built]**
22. Render a **cached preview frame** on navigation start, then replace it.
    Turbo does this; make sure the preview is not visually identical to a blank
    page.
23. Frame-level navigation for the feed's sort tabs, so Hot/New/Following swap a
    list rather than a document. **[cheap]**
24. `turbo_frame_tag` with `loading: "lazy"` for below-fold panels — sidebar
    widgets, related listings, comment threads past the first ten. **[cheap]**
25. Eager frames for above-fold content, lazy for everything else, decided by a
    single helper rather than per view.
26. **Cross-document View Transitions** for same-origin navigations. Zero today.
    Two CSS rules give the feed→post navigation a shared-element morph.
    **[cheap]**
27. Name the post's image and title as view-transition targets so they animate
    into the detail page instead of cutting.
28. View transitions on the theme toggle, so light↔dark crossfades instead of
    snapping. **[cheap]**
29. Guard every transition behind `prefers-reduced-motion` — 37 such blocks
    already exist, so the convention is set. **[built]**
30. **Turbo Drive progress bar** styled once in `shared/_shell.scss`.
    **[built]**
31. Delay the progress bar to 500 ms. Shown immediately it advertises slowness
    on requests that would have felt instant.
32. Restore scroll position per-frame, not per-document, on the messenger and
    channel logs.
33. Make the eight verticals cross-host `target="_blank"` navigations *feel*
    like same-app moves by pre-warming DNS: `<link rel="dns-prefetch">` and
    `preconnect` for the seven subdomains. **[cheap]**
34. `preconnect` costs a socket each — measure before shipping all seven on a 1
    GB box.
35. Speculation Rules API as a progressive enhancement over Turbo's prefetch,
    for browsers that have it.
36. A **back-navigation cache warm**: when a reader opens a post, keep the
    feed's DOM rather than re-fetching on return.
37. Kill any full-page reload that Turbo could have handled — audit every `data:
    { turbo: false }`; each is a document load, and there are several.

#### C · The waiting problem — optimistic UI (38–60)

The cheapest millisecond is the one the reader never waits through.

38. **Optimistic vote counts.** The arrow flips and the number increments on
    tap; the request reconciles. Voting is the most-repeated interaction in the
    app.
39. Optimistic follow/unfollow, with a rollback on failure.
40. Optimistic reactions on messages and comments.
41. Optimistic post submission — the post appears in the feed greyed, then
    settles. **[deep]**
42. A shared `optimistic_controller.js` so the pattern is written once rather
    than five times, which is how the aecho bug in dilla happened.
43. **Rollback must be visible.** A silently reverted optimistic update teaches
    readers not to trust the UI.
44. Queue optimistic actions offline and replay on reconnect. **[deep]**
45. **Skeleton screens** for the feed, matched to the real card's geometry.
    Shimmer that does not match the content it replaces reads as a bug.
46. Skeletons only past ~200 ms — below that they flash and make things worse.
47. Reserve space for every async region so nothing shifts when it lands (CLS is
    a felt problem, not just a metric).
48. `aria-busy` on regions that are loading, so the experience is the same for a
    screen-reader user.
49. **Blurhash placeholders** — the job, the helper and a Stimulus controller
    all exist. **[built]**
50. Verify blurhash actually reaches the feed card. Built and unreached is this
    repo's most common finding.
51. Lazy-load images below the fold — only 8 usages across brgen and shared for
    107 views. **[cheap]**
52. `fetchpriority="high"` on the LCP image, `low` on everything below it.
53. `decoding="async"` on every non-critical image.
54. Explicit `width`/`height` on every image so layout is stable before bytes.
55. **Disable the submit button on submit** and say what is happening, rather
    than letting a reader tap twice.
56. Inline validation on blur instead of a round trip on submit.
57. Debounce search input at 150 ms, not 300 — 300 is perceptible.
58. Show cached/local results while the network result is in flight.
59. Never block a UI update on an analytics call.
60. Local echo in the messenger: the message appears in the thread the instant
    it is sent, before the broadcast returns.

#### D · Server latency (61–86)

61. **Fragment-cache the feed card.** Three views do already; the traps in the
    preamble are what stops the fourth. Still the largest server-side win
    available, and no longer **[cheap]**.
62. Russian-doll caching: post → comments → comment.
63. Cache the nav bar and footer, which are identical on every page of a host.
64. **Watch `update_column`** — it skips `updated_at`, so `[record, …]` cache
    keys do not bust and the page shows a stale value while the console shows
    the new one. This has bitten this tree before.
65. `touch: true` on the associations that participate in cache keys.
66. Collection caching with `cached: true` on the feed's render call — one
    multi-read instead of N reads. Closed against: the cached partials key on
    the viewer's vote, and `cached: true` cannot express a composite key.
67. **Conditional GET**: `fresh_when`/`stale?` on show actions. One in the whole
    of `RAILS/`, and it is bsdports' `ports#show`. A 304 is the cheapest
    response there is. **[cheap]**
68. `expires_in` with `public: true` on genuinely public pages so relayd can
    serve them without touching Falcon.
69. Cache the expensive count queries; a "1.2k members" that costs a full count
    on every page load is a common shape.
70. Counter caches instead of `COUNT(*)` on association reads.
71. Audit the 50 `includes` calls against the actual N+1s — some are almost
    certainly loading associations the view no longer renders.
72. `select` only the columns the view uses on wide tables.
73. Cursor pagination instead of offset for the infinite feed; `OFFSET 10000` is
    a table scan. Pagy supports it. **[deep]**
74. Index every column the feed's ordering and filtering touches, verified with
    `EXPLAIN` rather than assumed.
75. Move blurhash, image variants, notifications and federation delivery off the
    request into Solid Queue — most already are. **[built]**
76. Never render a view that performs a write.
77. Set a hard timeout on any external call in a request path; an unbounded
    fetch is an unbounded page.
78. Cache the geolocation lookup, which is per-request today and per-city by
    nature.
79. HTTP/2 is presumably on at relayd — verify rather than assume.
80. Brotli for text responses; gzip as the fallback.
81. Stream the response with `render stream: true` for the slowest page, so the
    head reaches the browser while the body is still being built. **[deep]**
82. Send `<head>` early via 103 Early Hints so CSS starts downloading during
    server think-time. **[deep]**
83. Cache warm after deploy — the first reader should not pay for the cold
    cache. The keep-warm script exists for the boot storm; extend it.
84. Keep the cold-start problem in view: vm23 measured 12.19 s cold against 0.40
    s warm on an idle box. No front-end work survives that.
85. Consider a read replica or a materialised view for the city trending feed.
    **[deep]** **[yours]**
86. Rate-limit expensive endpoints so one reader cannot make the app slow for
    everyone on a 1 vCPU box.

#### E · Assets and first paint (87–104)

87. importmap carries no CDN pins and vendors tiptap locally. **[built]**
88. Seven CDN pins once cost brgen 537 requests per load; keep a gate that fails
    if a CDN pin reappears. **[cheap]**
89. `pin` defaults to `preload: true`, so a modulepreload fetches every pin
    eagerly and any dynamic `import()` is decorative. Audit which of the current
    pins genuinely need preloading.
90. Lazy-register Stimulus controllers that are used on one surface — the map,
    the voice recorder, the lightbox, the radio tunnel.
91. Split the stylesheet per app surface so a marketplace reader does not parse
    the messenger's rules. The built CSS is ~370 KB. **[deep]**
92. Inline the critical above-fold CSS and defer the rest. **[deep]**
93. `content-visibility: auto` on below-fold feed cards — one CSS property,
    large paint saving on long feeds. **[cheap]**
94. `contain: layout style paint` on cards so one card's change cannot reflow
    the list.
95. Self-hosted fonts are already vendored rather than fetched. **[built]**
96. `font-display: swap` so text paints before the face arrives.
97. Subset the fonts to the glyphs Norwegian and English actually use.
98. Preload only the one font weight above the fold.
99. `--font-brand` ships as a zero-byte system stack by design — do not "fix"
    this into a webfont. **[built]** **[yours]**
100. Serve AVIF with WebP and JPEG fallbacks through the existing variant
     pipeline.
101. Generate responsive `srcset` widths rather than shipping one large image.
102. A service worker for the app shell, so a repeat visit paints from disk.
     **[deep]**
103. Offline page already exists — extend it to a cached shell rather than a
     message. **[deep]**
104. Version and precache the built CSS/JS so a repeat visitor fetches neither.

#### F · Input and touch (105–118)

105. `touch-action: manipulation` to remove the 300 ms tap delay on anything
     that is not a scroll surface. **[cheap]**
106. Respond to `pointerdown`, not `click`, for state that is purely local.
107. Every tap target at 44 px — already the convention here. **[built]**
108. `:active` states on every interactive element. A control that does not
     acknowledge the finger reads as broken regardless of how fast it is.
109. Haptics via the Vibration API on primary actions, where supported.
110. `passive: true` on scroll and touch listeners so they cannot block
     scrolling.
111. `content-visibility` plus windowing for lists past a few hundred rows.
     **[deep]**
112. `scroll-behavior: smooth` only where it helps; on a long feed it is slower
     than a jump.
113. Overscroll containment on modals and drawers so a scroll gesture does not
     leak to the page behind.
114. Keyboard: `/` to search and ⌘K for the palette already exist. **[built]**
115. `j`/`k` feed traversal, `.` to refresh — the shortcuts a heavy reader
     expects from this class of app.
116. Focus the first field on any surface whose purpose is typing.
117. Optimistic focus: keep the caret in the composer after posting.
118. Never steal focus during an async update.

#### G · Real time (119–128)

119. Solid Cable is installed and 15 models broadcast. **[built]**
120. Broadcast `later` rather than inline, so a write is not slowed by delivery.
121. Broadcast a fragment, not a re-render of the page region.
122. Typing indicators exist in the messenger. **[built]**
123. Presence dots on the channel list, driven by the same cable.
124. Live vote and comment counts without a refresh.
125. Debounce broadcast storms — a hundred votes a second is one update.
126. Reconnect with backoff and tell the reader when the socket is down.
127. Replay missed messages on reconnect rather than leaving a hole. **[deep]**
128. Server-Sent Events instead of a socket for the feeds that are read-only —
     cheaper on a 1 GB box. **[yours]**

#### H · Motion that reads as speed (129–134)

129. Nothing over 200 ms. A 300 ms transition is a slow app with an animation.
130. Ease-out for entrances, ease-in for exits — the reverse feels sluggish.
131. Animate `transform` and `opacity` only; every other property costs layout.
132. Stagger list entrances by 20–30 ms, no more; a long stagger is a queue.
133. Cut the animation, never the acknowledgement, under
     `prefers-reduced-motion`.
134. One motion vocabulary across the three apps, in the shared tokens, so a
     reader crossing hosts does not cross timing curves.

#### What not to do

**Do not add a spinner where a skeleton belongs.** A spinner says "wait"; a
skeleton says "here is the shape of what is coming". Only one of them makes the
wait shorter.

**Do not preload everything.** Production is one box with 1 GB of RAM and one
vCPU, and every prefetch is a real request against it. Prefetching the whole nav
bar on hover is a good idea for a reader and a bad one for forty readers.

**Do not ship an optimistic update you cannot roll back.** A UI that lies and
then quietly corrects itself is worse than one that waits.

**Do not tune animations before caching the feed card.** Three fragment caches
against 54 declared transitions is the wrong ratio, and no easing curve
compensates for a view that rebuilds itself on every request.

**Do not trust an item on this list because it is written down.** Thirteen were
already built, and the ones that most look like wins — prefetch, preload,
streaming — are the ones most likely to be already on, inert, or actively
harmful on this hardware. Find the reader before trusting the setting.

### Blocked — do not chase

These are recorded in `RAILS/apps.yml` with verified blockers. Repeated here
only so nothing above reads as available.

- **Live streaming (tv).** Needs a media server (nginx-rtmp / MediaMTX / SRS)
  plus transcoding. ffmpeg is not installed on vm23. Infrastructure, not app
  code — `Tv::Broadcast` already models `stream_key`/`go_live!`/`end_live!`.
- **Solidus marketplace.** `brgen/config/database.yml` is sqlite3 in all four environments
  and Solidus supports Postgres/MySQL in production. This is a database
  migration first, not a gem install.
- **pgvector-backed recommendations.** Same Postgres dependency.

---

### Sequencing

Tier 1 and Tier 2 closed on 2026-08-19, apart from the inbound half of
federation, which is deliberate rather than unfinished. Tier 3 and the WebGL
blind spot closed on 2026-08-20: marketplace depth (variants, returns,
wishlist, facets), the verticals' own gaps (dating verification and daily
picks, tv sounds, takeaway group orders, the Craigslist kinds), outbound
federation's remaining half, and a gate that can see a WebGL surface.

What is left is what an app cannot close on its own, and every item is recorded
with its blocker rather than left implied:

1. **Inbound federation** — accepting remote posts, which is a moderation and
   spam problem before it is a code one.
2. **Seller payouts and PSP refund transfer** — the code half landed:
   `Marketplace::Payout` and `Payments::StripeTransfer` enqueue on delivery and
   fail closed, so a payout with no Connect account or no key stays pending with
   a reason rather than reading as sent. What is left is not code — it is a
   Stripe Connect account per seller and a platform balance to transfer from.
3. **The anonymised contact relay** — inbound mail routing on vm23.
4. **Live streaming, Solidus, pgvector** — infrastructure, listed under Blocked.
5. **Unblocked, and nobody has asked for them.** Recurring events and ticketing
   beyond an external link (2.2); coupons, referral credit and bundle pricing
   (marketplace). Each is a new noun a reader would meet on a page, so the
   absent model is a product decision rather than a gap — verified 2026-09-10
   that no column, table or service for any of them exists. An agent choosing
   what a coupon is would be choosing the product.

### The stylesheet ceilings, and what a split has to prove — closed 2026-09-10

`_zen_shell.scss` is 454 against a ceiling of 454 and `_messenger_window.scss`
is 395, under the 400 limit and off the list. `RAILS/test/file_length_ratchet_test.rb`
is green, and the standalone suite is 92 files, 636 runs, 0 red.

What kept these two alive for weeks was not the split but the proof: moving a
partial moves it in the cascade and no test in this tree reads cascade position,
so "nothing changed" was an assertion nobody could check. The method that
unblocked it is the part worth keeping. Build each app's `application.scss`
expanded before and after, parse both into ordered declarations, compare the
sets, and report every pair whose relative order changed unless specificity
already decides it. Prove the instrument first — zero findings on an identical
pair, 439 on a planted block move — then read what is left. The button family
produced 24 tied pairs across three apps, all `.btn` against a utility, and a
scan of 2,030 view and helper files found no element wearing both.

A candidate whose two halves never contend is a seam. `SURFACES.md` used to say
splitting a base layer scatters the cascade story; it now says how to answer
that per candidate.

Both splits are paid inside `RAILS/`, so no ceiling in another tree moved.
`growth.rails` is 2372 against 2372: two partials in (`shared/_zen_buttons.scss`,
`brgen/_messenger_inbox.scss`) and two files out — `RAILS/INSTANT.md` folded into
this document above, and `shared/app/helpers/application_helper.rb`, which two of
the three apps shadowed and none of the three reached.

### Deploy blockers

What stops a RAILS deploy from being a one-command operation, each with what
happens today, what has to change, and what already checks it. The former
`RAILS/BLOCKERS.md`. A blocker leaves this list when its unblock
criteria are met, not when it stops being mentioned.

This is the single home for them. `README.md` used to carry the list as five
unowned sentences under "Media integration"; two of them had gone stale without
anyone noticing, which is the argument for giving them a place with enough
structure that staleness shows. Operator-side debt is **not** duplicated here —
it is the OPENBSD section of this file and stays there.

---

### 1. City vanity TLS

**Status:** blocks first install of a new city apex; does not block day-to-day
deploys of the three live apps.

`OPERATOR.sh` stage 1 issues an acme certificate for every apex in
`ALL_DOMAINS`. relayd can only load a keypair for a certificate that exists on
disk, so an apex without a cert is an apex relayd will not serve — and
`OPENBSD/etc/relayd.conf` has held a keypair line for a certificate that did not
exist, which is worse than missing: installing that file downs every site on the
box.

**Owner:** operator. Requires registrar action (DNS delegation), which an agent
must not perform.

**Unblock criteria**

- Every apex in `OPERATOR.sh#ALL_DOMAINS` resolves and serves its own cert.
- `relayd -n` passes against the repo copy of `relayd.conf` on the box before
  install, not after.

**Checked by:** `domain_alignment` compares `ALL_DOMAINS` against
`Brgen::DomainRegistry` and asserts a keypair exists for the four live apexes.
Nothing checks the city apexes are actually reachable — that is deliberate: the
seven live cities sit behind `domain_alignment`, and the half that is registrar
money belongs to the domain expiry watch rather than to a gate.

---

### 2. relayd restart after route changes

**Status:** the missing half is built; the entry stays open until a real deploy
has exercised it on vm23.

A route change in `relayd.conf` needs `rcctl restart relayd`, and that restart
is not free. On 2026-08-10 relayd's `ca` process died during a restart
(`ca_dispatch_relay: invalid relay hash` → `lost child` → `parent terminating`)
and took every site on the box down for nine minutes. The deploy that triggered
it had logged `relayd(ok)` seconds earlier, because the check ran before the
restart.

**Owner:** operator.

**Unblock criteria**

- Post-restart verification is a separate step from pre-restart validation, and
  a deploy cannot report success on the earlier one.
- The failure signature is distinguishable from an app shed: relayd death
  refuses on **443** in ~30ms with sshd still up and the app answering on its own
  port from the box; a shed app leaves TLS answering and only the app port
  closed. Not port 80 — relayd declares one relay, `listen on 0.0.0.0 port 443
  tls`, so 80 refuses on a healthy box and tests nothing.

**Checked by:** `deploy_smoke_gate` validates relayd config content, and
`relayd_confirm_live` in `RAILS/_service.sh` re-checks 443 for 20s after the
restart, before the deploy is allowed to report success. It names which of the
two failure shapes happened: 443 refused while the app port still answers is
relayd down; both refused is the app, not relayd.

---

### 4. openrsync on vm23

**Status:** the README entry was wrong. Corrected here.

The README said "openrsync broken on vm23 — deploy uses git pull". Those are two
different operations and only one of them is a workaround:

- **Repo update** on the box is `git pull`, and always was. That is the design,
  not a fallback.
- **Tree sync** into `/home/<app>/app` is `sync_tree` in `RAILS/_sync.sh`, which
  calls `openrsync -a --delete` first, retries without `--delete`, and only then
  falls back to a `tar cf - | tar xf -` copy, logging `openrsync failed; falling
  back to tar copy`.

So openrsync is used on every deploy, with a working fallback. The bundle-cache
bootstrap in `_deploy.sh` called it too, with no fallback at all; it goes through
`sync_tree` now, so all four calls have one.

**Owner:** operations, low priority.

**Unblock criteria**

- If openrsync is genuinely unreliable on this release, the bundle-cache calls
  need the same fallback the tree sync has.
- If it is reliable, the fallback stays as insurance and this entry closes.

**Checked by:** the bundle-cache bootstrap now goes through `sync_tree` like
the tree sync does, so all four calls have the openrsync -> tar fallback. The
remaining half of this entry stands: the fallback is still silent apart from a
log line, so a box where openrsync never works deploys correctly and slowly
forever without anyone learning.

### Horizon — aspirational features (agent: ignore)

Migrated from `RAILS/apps.horizon.yml`, which is **kept** because
`MASTER/lib/operator/status_report.rb` counts it and a deploy contract test
asserts it exists. These items are **`agent: ignore`** — out of scope for
agents unless explicitly requested. Canonical active inventory is
`apps.yml`; do not implement horizon items by default.

- **brgen**
  - _core_
    - AI feed ranking — status: planned
    - creator monetization — status: planned
  - _subapp_tv_
    - live stream infrastructure — status: planned
  - _subapp_dating_
    - premium memberships / boost purchases — status: planned
  - _subapp_marketplace_
    - AI recommendations — status: planned
  - _subapp_playlist_
    - creator donations / ad-free tier — status: planned
- **amber**
  - _wardrobe_
    - fashion embeddings (pgvector) — status: planned
    - visual similarity search — status: planned
    - virtual fitting room — status: planned
    - mood matcher — status: planned
    - event outfit planner — status: planned
    - sustainable styles / resale — status: planned
    - weather-based suggestions — status: planned
    - global trends / local designer highlights — status: planned
    - style agents (MASTER integration) — status: planned
- **bsdports**
  - _core_
    - FreeBSD/NetBSD ports parsers — status: planned (OpenBSD-only production scope)
    - semantic package search (pgvector) — status: planned
    - infrastructure knowledge graph — status: planned
    - OpenBSD package intelligence — status: planned

### Survey of `RAILS/` — 2026-09-08, structure, order and the shared engine

A read-only pass over the three apps, the shared engine and the gates. No code
under `RAILS/` was changed. Ranked by value, with what was run to verify each.
Everything measured live: the standalone suite is green but for the length
ratchet, every source gate passes, and every RAILS lint sits exactly on its
ceiling.

**Instrument note first, because it cost two findings.** BSD `grep` has no `\|`
alternation in a basic regular expression, and a pattern built through a Ruby
double-quoted string arrives as one. Two searches for `A\|B` therefore reported
zero hits over subjects that were there — `Shared::ConsentHelper` read as absent
while `shared/lib/shared/engine.rb:91` registers it, and two lints read as
unreferenced while `MASTER/tools/ratchets.rb:325` measures both. Use `grep -E`.
This is the "BSD variants break GNU idioms" rule catching a survey of its own
tree.

#### 3. Reading order — the five lints are done, the gates cases are not worth it

The five `Operator::*Lint` modules read entry first now. Each was reordered on its
own and checked the same way: every lint's findings and counts snapshotted to
JSON before the first move and compared after each, byte identical throughout.
`scale_lint`'s first attempt raised on require — the module's closing `end` was
inside the slice being reordered, so `REPO_ROOT` landed in `module Operator`. A
reorder that carries a scope terminator is not a reorder.

The four gates cases from the same pass, at a lower threshold, were read and
rejected. `gate_calibration.rb`'s `run` is already fourth in its class and
`dom_surface_schema.rb`'s `self.check` is second; neither is an inversion at a
useful threshold. `geometry_type.rb`'s `check` sits directly above the eight
`check_*` methods it dispatches to, so lifting it above `profile` and `worn`
would put 150 lines between it and the helper it calls on its first line —
the move makes that file worse, not better. `layout_search.rb`'s `report` is
behind four public methods a caller may want on their own.

`test/method_length_ratchet_test.rb`'s `measure` stays where it is: in a
Minitest class the entry points are the four `test_*` methods, and they are
below it already.

The counterpart defect is absent. A public method declared below a scope's first
`private` appears **nowhere** in `RAILS/` — 0 findings over 1,461 files, with the
instrument proved on a planted positive that was then deleted.

#### 4. The sign-in screen is written three times — decided 2026-09-10, it stays three

Not consolidated, and the reason is that the three copies differ on more axes
than the note counted. Beyond the field wrapper (brgen floats its labels, the
other two do not, and that is the deliberate visual difference) they differ in
DOM order — brgen puts the input before the label because `.field--float` needs
the label to be the input's sibling — and in per-field attributes. A shared
template with locals for the wrapper, the ordering, the sign-up path and four
field options is harder to read than three copies, and `WIRING_NOTES.md` states
the rule this falls under: duplication beats the wrong abstraction.

The create-account link is behaviour and it is correct. bsdports has no
registration route at all — `bsdports/config/routes.rb` carries
`resource :session`, magic links and `sso/from_master`, and no registrations
resource — so there is nothing for a sign-up link to point at. amber's
`new_registration_path` and brgen's `new_user_path` are each their own app's.

What was a defect, and is fixed: amber's copy had drifted on three things that
are not visual. `autocomplete: "email"` is now `"username"`, the token a
password manager pairs with `current-password`; `required` stops a blank form
costing a round trip; and `value: params[:email_address]` re-fills the address
after a failed attempt. brgen and bsdports carried all three and only amber did
not.

#### 5. `rendered_geometry.rb`'s token shelf — stale, it was already built

The entry proposed extracting `check_token_conformance`, `token_palette`,
`collect_hexes` and `expand_hex` into `rendered_geometry/token_checks.rb`. All
four are in `gates/support/rendered_geometry/token_checks.rb` and have been
since the 422 → 344 pass; `deploy_gates_contract_test` is what moved it out of
`gates/lib/`, since a check module is not a gate. The proposal was written from
the earlier number.

`rendered_geometry.rb` still sits at 344 against its own 344 ceiling, and the
`CEILINGS` comment in `file_length_ratchet_test.rb` already says at length why
what is left does not divide: two further cuts look available and neither
survives reading, because the gate files four checks under `fitts_law` that
share `critical?`, and the one clean separation by probe field names a data
source rather than a question. The next check breaches and wants a raise argued
there, not a shelf.

#### 6. `shared/lib/operator/` keeps a flat drawer — decided 2026-09-10, no shelf

Decided against and written into `shared/WIRING_NOTES.md`. The shelf is already
spelled in the filenames — thirteen of the twenty names end in `_lint` — the
file count does not move, so no ratchet is paid either way, and the cost is
renaming thirteen constants and following them through `MASTER/tools/ratchets.rb`,
whose `lint_module` derives each constant from the basename. That is a
cross-tree rename of another tree's ratchet table bought for one path segment.

#### 7. Smaller, verified

- **The bare top-level names are settled (2026-09-10).** `Scrape` was the one
  with no framework paying for it — nothing resolves a plain service by bare
  name — so it is `Shared::Scrape` now, moved with its six call sites. The other
  sixteen stay bare and `shared/WIRING_NOTES.md` says which kinds and why: a
  controller, a mailer, a policy and the `Application*` bases are resolved by
  bare constant from the host, and a model's name is its table name, so
  `Shared::SiteVerification` would look for `shared_site_verifications` and grow
  a `class_name:` on every association to it.

  **The silent collision this entry recorded is named and gone (2026-09-10).**
  It was `ApplicationHelper`, in two apps at once: brgen's and amber's shadow the
  engine's, so the engine's copy loaded only in bsdports. A census of every
  top-level path the engine defines against every path the three apps define
  finds those two and nothing else. The engine's copy is deleted rather than
  renamed, because it carried nothing anyone reached — its three `include`s are
  all supplied to every app already, by the `shared.seo_kit` and
  `shared.schema_helper` initializers and by `Shared::ApplicationSetup`'s
  `helper Shared::StimulusFormHelper`, and its three methods (`nok`,
  `norwegian_date`, `api_date`) have no caller anywhere in `RAILS/`. `nok` was
  also a second money formatter disagreeing with the one under contract:
  `Shared::MoneyDisplay` renders `kr 3 500` and `nok` would have rendered
  `3 500,00 kr`. `zeitwerk:check` on bsdports says "All is good!" and all three
  app suites and the standalone suite are green without it.
- `RAILS/test/` holds 80 files in one drawer and `test/gates/` holds 13.
  `run_all.rb` globs recursively (`test/**/*_test.rb`), so subject shelves —
  `test/lints/`, `test/layout/` — need no runner change. Navigational only.
- `dns_zones` is the one red gate: `bsdports.org` resolves to
  185.134.245.114, not to us. Already the OPENBSD section's
  `bsdports_org_delegated_to_parking`; not a RAILS defect.
- `Shared::Engine.config.eager_load_paths` being empty is settled and is a Rails
  internal: the eleven directories reach `Rails.autoloaders.main` with no
  eager-load exclusions, and `zeitwerk:check` passes. Written up in
  `shared/WIRING_NOTES.md`, including why the measurement needs `db:prepare`
  first.

#### Not worth chasing — measured and rejected

- **The three per-app `Current` models.** `amber` and `bsdports` are
  byte-identical six-liners and brgen's 36-line version is a strict superset with
  eleven extra attributes it genuinely needs. `Current` has to be a bare constant
  for `Current.user`; there is nothing to share.
- **`brgen/app/models/user/*_associations.rb`.** Seven files of 12–48 lines, one
  per vertical, and the cohesion census proposes a `user/associations/` shelf.
  `brgen/ENGINES.md` says under "What stays in the host": shared models, `User`
  first. Moving them into the engines contradicts the contract; renaming them
  gains a path segment.
- **The `honesty` shelf in `gates/lib/source/`.** Three files, 275 lines,
  united by a word rather than a subject — affiliate disclosure, Faker filler and
  payment claims. `gates.yml` addresses each by `require` and `class`, so a shelf
  renames three classes and edits three rows for one path segment in a directory
  of 17. The census's constant renames are wrong here anyway: gates use explicit
  `require_relative` with hand-chosen namespaces.
- **The four ActiveRecord regroups the census proposes** — `item` and
  `declutter` in `amber/app/models`, `community`, `fedi` and `story` in
  `brgen/app/models`. `OutfitItem -> Item::Outfit` collides with `Outfit`, and
  every one of them costs `class_name:`/`table_name:` churn through
  strict-loading associations for a navigational gain. `fedi_*` is the only one
  that reads cleanly as `Fedi::*`, and it is four files of 119 lines.
- **The four missing assets `asset_url_lint` reports.** Both exemptions are
  documented at `shared/lib/operator/asset_url_lint.rb:48-60` and verified still
  true: the three `pp-neue-montreal` woff2 are a licensed face that cannot be
  committed, behind two `local()` entries and an Arial fallback; `lg.svg` is
  lightGallery's IE9 tail entry that no browser asks for.
- **`RAILS/*.sh`.** All ten root scripts are reached — `_scaffold.sh` and
  `_service.sh` from `_deploy.sh`, the rest from `OPENBSD/bin/vps-deploy`,
  `vps_ci.sh` and the contract tests. Not sprawl.
- **`MASTER/tools/cohesion.rb <dir>` on a tree root.** It globs
  `File.join(dir, "*.rb")` and does not recurse, so `cohesion.rb RAILS/shared`
  reports "nothing to merge" having read zero files. Use
  `--census --tree=RAILS --list`.

#### What could not be measured

The app suites DO run in a worktree, and the earlier note here saying otherwise
was wrong. `cd RAILS/<app> && RBENV_VERSION=3.4.9 rbenv exec bundle exec rails
test` resolves each app's bundle and prepares its own sqlite from the checked-in
schema: brgen 994 runs, amber 254, bsdports 102, all green on 2026-09-10, plus
the shared engine's own three files. What genuinely does not run here is the
rest of `bin/ci` — RuboCop and Brakeman — and the system tests. Do not report a
shared-engine change unverified on the grounds that the apps are unreachable.

And a fact that cost a verification before it was noticed: **the fleet on
38182/61352/47312 serves the main checkout, not your worktree.** Its rendered
HTML names `/Users/mac/.../pub4/RAILS` in the partial comments it emits. So
every live gate measures main while you edit a branch, and a view change is
invisible to `surface_schema`, `first_screen`, `page_simulation`,
`human_walkthrough` and the rest until it lands. Gate *data* files are read from
your tree, which is why a schema change shows and a template change does not.
Score the served HTML against the schema by hand if you need the answer before
the merge.

---

### Session of 2026-09-10 — the RAILS sweep, and what it decided

Closed: both stylesheet ceilings, the ten live selectors the CSS census called
dead, the `.price` disagreement, three red files in the standalone suite. The
suite is 92 files, 636 runs, 0 red — the first clean run this file has recorded.

Three instrument repairs, and they are one lesson wearing three coats. **A gate
that asserts one of several correct outcomes reports the environment as the
tree.** amber's `/demo` renders when the demo wardrobe is seeded and redirects
home when it is not; brgen's marketplace renders a grid when there are listings
and an empty state when there are none. Three checks demanded the first branch
each time — `function_layout`'s live row, `exemplars.yml`'s `nav_before_grid` and
`surface_schemas.yml`'s `product_grid` — so a checkout with an empty database
read as a broken app, and had for long enough that the one real finding
underneath (an English sentence in the marketplace empty state) was invisible
behind it. Each names the set of correct answers now and stays falsifiable: the
redirect must land where the row says, the nav must still precede the region.

The second: **check what the instrument opens before believing what it says.**
`accent_on_prose` globbed brgen's stylesheet directory, and brgen's bundle is not
that directory — `_stack_brgen` forwards eleven shared partials and
`application.scss` names more by bare name. It follows the `@use` graph now, 80
files where the glob found 53. The `.price` note in `visual_contract_lint.rb` had
recorded the wrong reason for the right verdict; the answer is that brgen's
`.price` carries no colour at all (`_stack_brgen` does not forward `_minimal`)
while amber's and bsdports' do, and this lint speaks for brgen's grayscale
identity rather than for the luxury or wscons dialects.

The third: **an extractor that ends at a quote cannot read a Ruby class value.**
`css_coverage_lint` recorded ten selectors as unused while a browser painted
them, because a class value with a quote inside it arrived truncated at that
quote and was then dropped as interpolated. It walks the value now — the
string's own text plus the text of every string nested in its interpolations —
and reads `app/helpers/**/*.rb` as views, because a helper that builds a tag
builds markup. `unused_selector` 153 to 134, `undefined_class` still 0, and
nothing became unused in the exchange.

#### Still open, and each is the operator's

- **`rendered_suite` fails on about forty contrast pairs, every one a colour.**
  `#d62828` on `#efefef` at 4.36 against a 4.5 floor (the nav badge, on twelve
  surfaces), `#ff5b24` at 2.7 (dating's Vipps line), the playlist teal at 4.44,
  `#6b7fd7` on white at 3.72 (the channel name). All are values the operator
  drew, and the house rule is that an agent may not choose a rendered value. They
  also measure the main checkout's compiled CSS rather than a branch's.
- **bsdports' inbox link is unstyled.** It defaulted to a class no stylesheet
  defines — `nav-link`, where the tree spells it `nav_link` — so it has always
  painted as the bare anchor its three nav siblings are. The dead hook is gone;
  whether that link should wear the nav class or the ghost button beside it is a
  rendered decision.

#### Closed on 2026-09-10, and one of the three entries was wrong

- **The 23 English sentences are keys.** `chrome_i18n_lint`'s `empty_copy` is a
  ban at 0 now. Each sentence went into the `empty.*` or `actions.*` family the
  same view already drew its title from, with the English kept verbatim in
  `en.yml` and a bokmål sentence beside it — the copy is the locale file's
  decision from here, not the template's.
- **The reaction bar renders `t("reactions.kinds.<kind>")`.** Words, not glyphs:
  translating what is there preserves the rendered shape, and swapping seven
  words for seven glyphs is the design decision this entry said it was. Its
  aria-label went with it — it was built from the kind and the target's Ruby
  class name, so a Norwegian reader heard "Angry post". `aria_label` 8 → 7.
- **`conversations#index` was not a product question, and the entry misread the
  tree.** Nothing renders `_conversation_row` into `#conversation-list`: a
  reflex appends `beforebegin` its own sentinel, and `shared/_infinite_scroll_sentinel`
  is not on that page at all. `ConversationsInfiniteScrollReflex` was named by no
  view, no test and no other file — 32 reflex classes, 31 mounted — so it was
  deleted, and `infinite_scroll_reflex_contract_test` now asserts every reflex is
  mounted by a view, which is the check that would have caught it. The messenger
  inbox is a rail capped at 30 with search above it, and that cap now says so in
  `load_rail`.

### Session of 2026-09-11 — nine source gates got a test, and two were not measuring

Nine gates that read source text had no test at all: `phantom_foreign_keys`,
`schema_migration`, `frontend_production`, `frontend_auditor`,
`css_minify_integrity`, `scale_ratchet`, `dialect_purity`, `locale_shadowing`
and `content_honesty`. Each has one now, and each plants the defect the gate
exists to catch, asserts the gate fails and names it, removes the defect and
asserts it passes. A test that only runs a gate over this tree and asserts clean
proves nothing — it passes equally against a gate whose body is `return ok` —
and every one of these was driven against a deliberately gutted gate to prove it
goes red.

Two of the nine were measuring less than their green line claimed.

- **`schema_migration` has read 3 of the 200 `create_table` calls in this
  repository.** Its duplicate-table scan is
  `/create_table\s+["':](\w+)["']/`: the opening delimiter may be a colon but
  the closing one must be a quote, so `create_table :posts` — the form every
  migration in `amber`, `brgen` and `bsdports` uses — matches nothing. The check
  has never seen a duplicate because it has never seen a table. Fixing the regex
  is one character and is **not** a free win: it lights up 16 duplicates in
  brgen, 7 of them `create_table … if_not_exists: true` inside deliberate repair
  migrations (`repair_missing_identity_and_trust_tables`,
  `ensure_locality_tables`, `fix_dating_foreign_keys`). So the check needs the
  exemption before it needs the regex, and the two together are the work.
- **`css_minify_integrity`'s selector-loss half cannot fire.** It compiles each
  entrypoint `:expanded` and `:compressed` and fails when a selector in a
  three-or-more item list is missing from the compressed output. That is a real
  dart-sass bug and it shipped a full-width avatar on brgen.no. dart-sass 1.101.0
  does not have it: a 30-item compound-selector list, quoted attribute values,
  escaped and unicode selectors, `:is()`, `@media` and `@supports` all survive
  compression intact here. What the gate still proves is that each app's
  `application.scss` compiles, which is worth keeping and is what its test
  pins. Re-check the loss half whenever sass-embedded moves.

A third finding is about the shape of the gates rather than about any one of
them. **Six of the nine resolve their subject from constants computed at load
time and take no root argument** — `phantom_foreign_keys` (`ROOT`),
`schema_migration` (`ROOT`, `RAILS_ROOT`), `frontend_auditor` (`ROOT`, `APPS`),
`dialect_purity` (`RAILS`, `TOKENS`, `WIRING`), `locale_shadowing`
(`RAILS_ROOT`, `APPS`, `BUDGET`) and `content_honesty` (`ROOT`, `RAILS`). The
only way to run one over a planted tree is to rewrite those constants around the
call, which `RAILS/test/gates/gate_fixture.rb` does and undoes. It works, and it
is the wrong seam: `File.expand_path("../../../..", __dir__)` is the arithmetic
this tree has now had wrong four times, and a `root:` keyword would make both
the gate and its test say where they are looking. The three that already pass a
path or a root — `frontend_production`'s `check_layout`/`check_views`,
`css_minify_integrity`'s `check_app`, `frontend_auditor`'s underlying
`Shared::FrontendAuditor.call(root:)` — needed none of it.

Smaller, and closed by the tests rather than left open: `frontend_auditor`
raises exactly one `:error` rule (`embedded_app_file`) and everything else is
advisory unless `GATE_AUDITOR_STRICT=1`; `scale_ratchet` reports a count under
its baseline as a warning asking for the new low to be recorded, never as a
failure; and `content_honesty`'s live half says "sitemap not probed" rather than
claiming a clean sitemap when nothing is listening.

## OPENBSD

### Operator debt — still open

Each item carries a hidden HTML-comment marker on its own line under its heading;
`MASTER/lib/operator/operator_docs.rb:55` counts those markers for the
`MASTER/bin/operator status` debt line, so keep exactly one per open item.

#### `libvips_local_build`  — tag: operator-priority

<!-- open-debt -->

vm23 runs a locally built libvips and `pkg_add -u` will replace it with the stock
package, which sets `-Drsvg=disabled` and so carries no svgload at all. amber's
garment cut-outs need it, and the loss is quiet: `Amber::GarmentSilhouette#png`
returns nil and logs one line when vips cannot read SVG, and the seeder keeps
whatever photos the items already had, so the site does not break — the cut-outs
merely stop regenerating. Healthy on 2026-09-11: `vips --version` reads 8.14.5,
`vips -l` lists four svgload operators, and the rebuilt package is still at
/usr/ports/packages/amd64/all/libvips-8.14.5.tgz. Detection is live at
`/etc/daily.local:71`, which reads the loader list every morning and names the
recovery. What stays open is conditional operator work: after any `pkg_add -u`
touching graphics, run `make reinstall` in /usr/ports/graphics/libvips — the port
path for the dependency is x11/gnome/librsvg, not graphics — and confirm four
svgload operators again.

#### `off_host_dr`  — tag: operator-priority

<!-- open-debt -->

One purchase is left: an off-host object store. `ruby OPENBSD/bin/dr-pull --check`
reports the newest pull one day old and seven kept, integrity-checked on arrival
and restore-drilled, but those copies sit on the operator Mac — one other disk,
not a bucket.

The same purchase closes the crate, and that is the sharper half. `STUDIO/dilla/
samples/` is 84 MB on exactly one disk, of which 75 MB is `own/` — the operator's
and named collaborators' own recordings — and `.gitignore` excludes all of it.
dr-pull cannot help: it pulls from vm23 to the Mac, and the crate is already on
the Mac, so writing it into `~/pub4-dr/` puts a second copy on the disk it is
already on. Until there is a bucket, the crate has no backup at all, and
`samples/dug/` is down to one record from 161 as the standing demonstration of
what that costs. litestream is absent by decision: it is not in OpenBSD ports,
neither the binary nor an rc.d script exists on the box, and it is out of
`pkg_scripts`, which reads master brgen amber bsdports brgen_jobs.
`OPENBSD/etc/litestream.yml` stays correct for the day someone builds the binary,
and nothing else may name it as a backup. The shed ladder it used to head is two
real services: `ksh OPENBSD/test/resource_guard_test.sh OPENBSD/resource_guard.sh`
passes all eight cases and sheds bsdports first, amber last, so the guard's
cheapest step takes a site down.

#### `multi_app_ram`  — tag: operator-priority

<!-- open-debt -->

The operator command is a provider resize of vm23, and nothing in this repository
can do it; after it lands `sysctl hw.physmem` must read at least 2147483648.
Measured 2026-09-11: `hw.physmem` is 1056952320 and `swapctl -s` reports 1652096
of 2588672 blocks used, 64 percent — down from 84 two days earlier, which is
core-reclaim working rather than the ceiling moving. A resize was recorded here
as scheduled for a Friday in August and the box is unchanged, so read the box,
never a date. The standing decision is to stay at 1 GB with one
resident worker, brgen_jobs, and it reopens only if amber earns its own. Two
shapes read as a broken app rather than as memory: amber needs about twenty
seconds to signal ready and a bare `falcon serve` defaults to a thirty-second
health-check window, so reproduce a start by hand only with
`--health-check-timeout 300`, which the rc.d passes; and `bin/vps-deploy:180`
already stands the app's job worker down for the CI run, so standing it down by
hand first makes that step skip.

#### `home_partition_full_from_git_history`  — tag: operator-priority

<!-- open-debt -->

What is open is a coordinated history rewrite, and only the operator can schedule
it. The ten largest objects in history are 80–87 MB WAV renders under a
`DEPLOY/dilla/renders/beats/` path that no longer exists, every deploy pulls them,
and the fix is a force-push to a public repo with a vm23 re-clone in the same hour
and every session quiescent. Strip the blobs and the key purge in one pass. It is
not pressure: measured 2026-09-11, /home is 69 percent with 5.1G free of 17G, /var
is 16 and / is 18, and /home/dev/pub4's .git is 3.6G. Re-read it
with `ssh dev@brgen.no 'df -h /home; du -sh /home/dev/pub4/.git'`.

#### `bsdports_org_delegated_to_parking`  — tag: operator-priority

<!-- open-debt -->

One registrar change, at Domeneshop and nowhere else: set bsdports.org's
nameservers to ns.hyp.net and ns.brgen.no. It costs nothing — whois reads status
ACTIVE, autoRenewPeriod, and a registry expiry of 2027-08-08T14:15:10Z, so the
registration is paid and only the delegation is wrong. The app is well and
answers 200 on 127.0.0.1:47312 behind relayd; the domain is parked.

Measured 2026-09-11: the .org registry still delegates to
ns1/2/3.expireddomain.hyp.net, those publish 185.134.245.114 and
2a01:5b40:0:bc04::1, `https://bsdports.org/up` returns 000 because parking
terminates no TLS, and `http://bsdports.org/up` returns 200 from Domeneshop's
parking page. A check that reads a status code therefore calls the domain healthy
while it serves someone else's page. `ruby RAILS/gates/runner.rb dns_zones` catches
it by comparing the answer against 46.23.89.226, and bsdports.org is its one
failure — that gate reads the three app domains
(`OPENBSD/gates/dns_zones.rb:69`), so no count of expired city domains
belongs in this row.

The deadline is a certificate, not a registration. `/etc/ssl/bsdports.org.fullchain.pem`
carries `notAfter=Nov 10 16:56:43 2026 GMT`, and acme-client renews over HTTP-01,
which needs the name to resolve here — so a delegation still wrong that week ends
TLS for bsdports.org until it is fixed. It is done when `dns_zones` passes.

Nothing else in OPENBSD reads the parking as the app being down. `uptime-check`
carries `ALLOW_BSDPORTS_DOWN=1` on its crontab line, with the reason and the
condition to drop it; `bin/deploy-smoke.sh` keeps the public check required and
names the delegation when it fails, while `http://127.0.0.1:47312/up` stays
required and is what actually measures the app.

### Guards worth not re-discovering

A fixed finding is not a backlog item and is deleted when it closes; `git log`
holds the why. What stays here is the false positive worth not paying twice.

**dev's passwordless root is decided, not open.** `/etc/doas.conf:39` reads
`permit nopass setenv { … } dev as root` and it stays. The exposure, the four
mitigations it rests on, and the one narrowing someone could actually walk are in
`OPENBSD/DECISIONS.md` — "dev keeps passwordless root, and here is the exposure",
with a review trigger. Two things before reopening it. Check the rule with `doas
-C /etc/doas.conf id` and never with `-u dev`: `-u` names the target user, so the
`-u dev` form asks whether dev may run a command as dev, which no rule permits,
and it printed `deny` against `permit nopass` for the plain form on the same box
in the same minute. This row read as done for weeks on that backwards
measurement. And the remote half is already closed — `/etc/rc.d/master:64` carries
`daemon_user="master"`, like the three apps. Before moving any app off its own
daemon_user, note what the master switch cost: `Bundler.setup` ends in
`Definition#write_lock`, which touches Gemfile.lock on every boot, and under a
new user that is EACCES with a trace naming `File.utime` and nothing about
permissions. `BUNDLE_FROZEN=true` in the daemon's env is the fix and is
load-bearing.

**amberapp.com is not ours.** A row here once recorded it as bought and certified
after reading a 114-byte JS-redirect page. That page is Afternic's for-sale
lander; the domain has been at GoDaddy since 2019 with `ns1/ns2.afternic.com` and
a fast-transfer record, and the listing asks USD 5,999. Read whois before calling
a domain ours. amber is canonical at amber.brgen.no, buying the apex is a spend
decision for Johann and Ragnhild, and the coupling matters: the session cookie is
`domain: :all`, scoped to the registrable domain, so a move off brgen.no silently
ends cross-app sign-in, and `Shared::SsoToken` is consume-only in this tree.

### The shell tree — what is still open

Re-verified 2026-09-10 against the box, read-only. brgen, amber and bsdports all
answer 200 on `/up`, and master answers on 53187.

#### The box is not this repository, and one OPERATOR.sh run closes every difference

`SSH_HOST=dev@brgen.no ruby OPENBSD/config_drift_gate.rb --remote` is the way to
ask, and it is the only form of this row that cannot go stale. The enumeration
that used to sit here named eight files and was wrong within a day: re-run
2026-09-10, ten differ, `etc/rc.d/master` has since come into line, and
`core-reclaim.sh`, `resource_guard.sh` and `config_drift_gate.rb` have joined.
Read the gate, not this paragraph.

Two facts the gate reports that a re-run will not explain. Two targets are absent
from the box altogether rather than merely different: `emergency_cpu.sh`, which
is the only thing `resource_guard.sh`'s crisis tier can run, and
`vps_weekly_integrity.sh`. And in every case the repo is the newer side, so there
is nothing to copy back.

Root's crontab is the eleventh and it hid the longest. `crontab.vm23:97`
schedules `/usr/local/bin/vps_weekly_integrity.sh`, `OPERATOR.sh:311` installs
it, and the box has neither the line, nor the file, nor `/var/log/pub4/` for it
to write into — re-checked over ssh 2026-09-10, all three still absent — so the
weekly integrity pass has never run once, while every `/etc` file the drift gate
compared matched and it said clean. The gate now compares the crontab too, as a
set of commands rather than bytes (OPERATOR.sh merges the pub4 lines onto
OpenBSD's own, so a byte compare would always fail), scoped to `/usr/local` so
the four base-system lines are not four permanent false alarms.
`test/test_config_drift_gate.rb` carries the shape it must flag and the shape it
must not.

Nothing here can install any of it. `MASTER/bin/operator vps deploy` does not do it
either — this is `doas zsh OPENBSD/OPERATOR.sh` on the box, and it is the whole
of what this row still wants. The two repairs the script itself needed are
committed and `git log` holds them.

#### Not worth chasing

- **The three deploy scripts nothing calls.** `deploy_all.sh`,
  `vps_run_remote.sh` and `manual_master_deploy.ksh` stay, as recovery paths for
  three cases `bin/vps-deploy` does not cover. Decided 2026-09-10; the argument is
  in `OPENBSD/DECISIONS.md` and the count is not to reopen it.
- **The seven readers of the load average.** They cannot share a library and two
  of them must not agree. `core-reclaim.sh:65` takes the 1-minute figure because
  it is about to cost somebody a cold boot; `resource_guard.sh:101` takes the
  5-minute one because it must not shed a site over a spike. Both lines now say
  so. A shared file would also have to be installed to `/usr/local` — root sources
  only root-owned absolute paths (`resource_guard.sh:135`) — which is a new install
  target rather than a fold. The banned-tools rule governs MASTER's shell effect,
  not what this tree commits.
- **Nine two-line expect shims.** `vps_console_status.exp`, `_probe`, `_short`,
  `_install`, `_fix_key`, `_poll_install`, `_start_install`, `_sync_and_install`
  and `vps_drop_install.exp` each delegate one line to `vps_console.exp`.
  `vps_safety_gate.rb:63-74` names all nine and fails when one stops delegating,
  which is how `require_console_risk_ack` cannot be bypassed by adding a tenth.
  Folding them means changing that gate, and the gate is the point.
- **Ruby entry points come last, everywhere.** `installed_targets_gate.rb`'s `run`
  and `health_check.rb`'s first `def` sit below the definitions they use. The
  language wants the definition before the call and the tree is consistent about
  it. Reordering buys nothing. `config_drift_gate.rb` is the one exception and it
  is deliberate: a `$PROGRAM_NAME == __FILE__` guard splits definitions from the
  run so its test can require the file without the skip line exiting the test
  process.
- **`bin/vps-deploy:153`'s `[[ -x /usr/local/bin/config_drift_gate.rb ]]` guard.**
  It has the shape `installed_targets_gate.rb` records as a dead guard, and it is
  not one: `OPERATOR.sh` installs that file, the box has it dated Aug 25, and it
  wrote `/tmp/vps-deploy-drift.out` on the last deploy.
- **Hardcoded ports in `bin/smoke-apps.sh` and `bin/deploy-smoke.sh`.** `ruby
  RAILS/gates/runner.rb port_inventory` compares them against `apps.yml` and
  passes.
- **Most `|| true`.** About a hundred instances, and the majority are idempotence
  on `rcctl`, `pkill`, `chmod`, `install` and `rm -f`. `start_all_apps.sh:16-17`
  swallows enable and start and then fails correctly at :24. Read the exit path
  before flagging one.
- **`dotfiles/mov.sh`.** 2,343 lines, the largest shell file here, thirty
  banned-tool hits, and a torrent-and-transcode tool with nothing to do with vm23.
  It is the owner's dotfile; moving it is a growth argument.
- **The four `data/debt.yml` and `archive/recovery` mentions that remain.**
  `RUNBOOK.md:16-22` says in so many words to read `archive/recovery` as
  document-only, and `DECISIONS.md:200` and `PATH_OWNERSHIP.yml:17` both write
  "the old data/debt.yml", which is history rather than a live path. The two that
  pointed at files which never existed — `vps_console_common.exp`'s refusal
  naming `VPS_SAFETY.md` and `OPERATOR_CONTRACT.md`, and `deploy_all.sh`'s header
  citing a manifest inside an `archive/` this repo does not create — are fixed.
- **Four gates that pass and mean it.** `OPENBSD/installed_targets_gate.rb` is
  clean at 12 configured targets against 15 the repo provides,
  `OPENBSD/tools/reach.rb` reports 10 cron, 8 rcd and 57 zones with none
  unreachable, and `OPENBSD/deploy_smoke_gate.rb` and `port_inventory` pass.
  `/usr/local/bin/config-drift-check` cannot be run as dev at all — it exits on
  EACCES reading /var/nsd/etc/nsd.conf — so its green is a root measurement, not one
  a session can take.
- **The `config_drift_gate.rb` and `config-drift-check` name pair.** Two
  questions — repo-versus-live `/etc` bytes, and relayd, acme and nsd consistency —
  under two names one letter apart, and the confusion has already cost a check its
  life once. Renaming either breaks an install line and a crontab entry.

## STUDIO

No standing backlog file exists for STUDIO, and none is invented here. dilla,
postpro, repligen and lora carry their working decisions in their own
`README`/`AMBITION`/`ENV_AND_RENDER` docs and in operator memory. Two standing
constraints bound any agent work in this tree:

- **Renders are irreplaceable.** dilla and postpro write real output with rotating
  seeds; never render over a take that matters, and never change a rendered-sound
  or graded-look default on your own judgement.
- **dilla is production tooling**, aimed at being genre-agnostic — Detroit lean,
  but techno, soul and jazz must blend as parameters. That is a design goal, not a
  backlog item to close unprompted.

Re-measured 2026-09-11 against the crate itself, and most of what stood here was
describing a crate this machine does not have. `samples/` is gitignored, so a
worktree shows an empty crate that is not empty; the figures below come from
copying the real `samples/` in and asking the engine, which is the only way to
measure it without writing to the operator's only copy. dilla is under active
edit; line numbers inside `dilla.rb` move, symbol names do not.

### The crate — read this first

**There is no `samples/chopped/` on this machine, and there are no 124 racks.**
This section described 124 rack directories, 161 registry rows, 13 byte-identical
wavs and 153 mid-phrase cuts; none of it is on disk. `RadioChop.registered_loops`
returns nothing, `TRACK_SAMPLE_LOOPS` is the five builtins, and `samples/` holds
`drums`, `dug`, `own` and `rauingar` and nothing else. Every file in it is dated
2026-08-31.

The likely account is the one the engine's own test writes down: `74d9e4c1b`
cleared the crate on 2026-08-16 on the operator's call — 133 renders and 498
samples — and it is being rebuilt from source. The test's whitelist matches disk
exactly today, naming `kembara_rindu`, `semua_untuk_mu`, `lo_borges` and
`arat_swost_wolet` as the four builtins awaiting the rebuild and treating
`rauingar` as present, which is what disk says. A backlog measured against 124
racks after that clearing was measuring something else.

**If the operator expected 124 racks to be there, they are not, and only they can
say whether that is the August clearing or a later loss.** Nothing in this
repository can restore them and no session should assume either answer.

- **What is left is in no backup, and that is the open item.**
  `STUDIO/dilla/.gitignore:19` ignores `samples/` wholesale, so not one file is
  tracked. The irreplaceable half is `samples/own/` — 75 MB of the operator's own
  and named collaborators' recordings — plus `rauingar` and the 1.1 MB drum rack,
  84 MB in all, on exactly one disk. That is the state `samples/dug/` was in the
  day it went, and dug is down to one record.

  `OPENBSD/bin/dr-pull` cannot be the answer and this row used to say it could.
  dr-pull pulls FROM vm23 TO the Mac; the crate is already on the Mac, so writing
  it into `~/pub4-dr/<stamp>/` puts a second copy on the same disk, which is not a
  backup. This is the same blocker as `off_host_dr` above — one purchase, an
  off-host object store — and the two rows are one row.
- **160 of the crate's sources are gone, and no loop is reproducible from its
  sidecar.** `samples/dug/` holds one record, `arat_swost_wolet.mp3`, with its
  provenance sidecar. The sidecars carry a reproduce command naming a path that no
  longer exists, and only the titles survive, in the slugs; re-fetching by title
  returns a different upload, so offsets and mastering will not match. New fetches
  record the HTTP URL — `CrateDig.archive_entry` and `ccmixter_entry` store `url`
  and `record!` refuses an entry without one. `dilla/crate/` from `bin/crate` is
  gone the same way, taking with it the two takes whose sidecars name
  `crate/loops/semua_untukmu`.
- **The eight `sheger_*` rows are half alive, and deleting them would throw away
  measured tuning.** This is settled, not open, and it is written here so nobody
  re-derives the wrong half. `TRACK=sheger_01` renders today: `TRACK_PRESETS` has
  a live row for it carrying its own measured tempo and progression. What it lacks
  is the bed — `TRACK_SAMPLE_LOOP_ALIASES` resolves it to `ubrukte_samples_01`,
  which RadioChop registered out of the crate that was cleared, so
  `sample_loop_entry` finds nothing and says nothing. Eight half-working tracks
  read as eight working ones. `test_every_sample_loop_alias_names_a_loop_something
  _registers` pins the eight as known-dead, tightens as each chop re-registers,
  and fails on a ninth; the same test asserts the preset rows are live so nobody
  deletes them on the strength of the aliases.
- **Eight of the sixteen recorded assets are not the files that were recorded.**
  `ruby STUDIO/dilla/dilla.rb assets` exits 1 today: three loops missing — the
  crate-rebuild three — and eight changed. Seven of the eight are drum one-shots
  that kept their byte count and changed their hash, so they were re-synthesised
  after the manifest was written; the eighth is `samples/rauingar/loop.wav`, which
  went from 920,358 bytes to 3,397,694 and is the re-cut the engine's test already
  records as "rauingar is back on disk". Nothing runs this check, which is why it
  has been red without anyone knowing. `dilla assets record` closes it and blesses
  whatever is on disk as canonical, which is the operator's to say — a re-record
  that includes a wrong file makes the check agree with the wrong file forever.
  The report itself is fixed: it decided on the hash and printed the byte count,
  so a re-encoded one-shot read as "12426 bytes → 12426" and looked like a bug in
  the check rather than a difference in the file.
- **Writing `TRACK_PRESETS` rows for chops is still forbidden to an agent, when
  there are chops again.** A slug with no preset row falls through to
  `TRACK_PRESETS[:timeless]`, so appending rows changes what those slugs render.
  `dilla.rb` writes down a mechanical derivation for the `sheger_*` rows — take
  `progression` and `feel` from the existing preset nearest the chop's measured
  tempo — and whether that derivation is the right sound is the owner's. Nothing
  else moves if rows are appended: `demo_all_order`, the stream rotation and
  `chopped_bed_pick` all read `TRACK_SAMPLE_LOOPS` or `RadioChop.registry` rather
  than `TRACK_PRESETS`, and only the explicit `showcase` subcommand enumerates the
  preset table.

### Which crate layout survives is the owner's call

dilla has four crate surfaces and three layouts with one reader. The engine reads
`samples/chopped/loops.json` through `RadioChop.registered_loops`
(`lib/radio_chop.rb:634`). `lib/crate_dig.rb` writes `samples/dug/` from the
Internet Archive and LibriVox, filtered to expired copyright. `live/dig_crate.rb`
rips YouTube with `yt-dlp`. `bin/crate` declares a third layout,
`crate/{sources,stems,loops}`, calling itself the replacement for `samples/`, and
that directory no longer exists.

The licensing half of this is closed. `crate_dig` and `dig_crate` are one word
order apart and used to take opposite positions in silence — crate_dig's header
said YouTube rips are "neither licensed nor defensible, and this does not add to
that pile" while its near-namesake did exactly that and said nothing — so a
reader learned the tree's position from whichever file they opened. dig_crate now
leads with what it is, points at the path that clears, and warns on stderr on
every run; crate_dig says its sentence is about itself. Which layout survives is
still the owner's, and neither file can clear a recording.

### The engine is one file, and its support directory is full

`dilla.rb` is about 35,200 lines and carries the 83 `# engine part:` parts that
were under `lib/engine/`, in the order they were required, because that order was
load-bearing. `DillaSources` defines the corpus and `STUDIO/gate.rb` fails if
`lib/engine/` reappears.

`DILLA_SUPPORT_CEILING` is 56 and now counts every first-party Ruby file dilla
carries beside the engine, at any depth: 44 in `lib/`, 4 in `bin/`, 6 in `live/`
and 2 in `scripts/`. It used to count `%r{/dilla/lib/[^/]+\.rb\z}` alone, which
was an escape hatch in both directions — `MASTER/tools/cohesion.rb` proposes three
regroups into subdirectories of that same `lib/`, and taking any one of them
would have dropped the guarded count to 35 and quietly disabled the ceiling it
appeared to relieve, while twelve support files in `bin/`, `live/` and `scripts/`
sat outside it entirely. A regroup is free now and a fifty-seventh file is not.

Folding the 44 into fewer files is undone, and 14 of them use `__dir__` or
`__FILE__`, which shift a directory level when a file moves — the bug that broke
three tests during the first fold, and the reason to do the second one
deliberately rather than as a tail-end.

A second entry used to sit under "From the 2026-08-31 session" telling the next
session to split the monolith along its seams, and the two could not both be
followed. It is gone, and this is the resolution: the direction is out of the
monolith, but every destination is a file under `lib/` and
`DILLA_SUPPORT_CEILING` leaves no room for one. A split therefore starts by
moving support code together, not by moving engine parts out, and until somebody
does that the honest answer is that the monolith stays.

`dilla parts` is the index the engine's map never had: every `# engine part:`
marker with the line it starts at and how many it holds, `dilla parts <needle>`
to filter, generated so it cannot go stale. Its test catches the two ways the
index can lie without a render noticing — a marker lost in an edit, and two parts
sharing a name. The seams worth naming are the parts over 1,000 lines — `patch`
1578, `progression_tables` 1210 (pure data, the most extractable thing in the
file), `render_dilla` 1191, `characterize` 1180, `cli_commands` 1164 and
`render_techno` 1071. **Splitting any of them is not proposed here**, and the
decision not to reopen `lib/engine/` stands.

### The engine probes pass, and the seed question is smaller than it looked

`rake test:dilla` is 305 runs and 0 failures, with 3 skips when the real
`samples/` is present and 4 in a worktree. Both failures this section recorded
are gone. `test_every_genre_renderer_reaches_the_master_bus` passes —
`render_analog` reaches the bus — and `test_every_hand_cut_sample_loop_is
_reachable_as_a_track_preset` passes with `semua_untuk_mu` among the four
builtins its whitelist names as awaiting the crate rebuild. Three of the skips
are the timeouts recorded under "not worth chasing" below; the fourth is the
loop-file check standing down because a worktree has no crate to measure, which
is where it used to fail on `rauingar` and send a session after the engine.

`RENDER_SEED` stays open and is a quarter the size this said. `test_dilla_render
_seed.rb` pins `stable_hash`, `seed_for`, `noise_seed`, `render_pick` and
`render_rng`. The claim was that 92 sites in `dilla.rb` call bare `rand`,
`Array#sample` or `Random.new` outside those helpers; measured, 31 of the 32
`.sample` calls already pass `random:`, and of the 76 `Random.new` calls all but
thirteen carry a seed while those thirteen are `seed ? Random.new(seed) :
Random.new`, unpinned only when their caller passes none. What actually varies
under a pinned seed is eight bare `rand` calls and one `.sample` — which is why a
pinned render still moves by about 0.012 dB. Routing any of them through
`render_rng` changes what that site renders, so it is the owner's, one site at a
time, but it is now a list somebody could finish.

### Two knob findings, and eight of the ten conflicts were the scanner

Six of the ten "knobs whose default differs between files" were the scanner's own
reading, and two more were per-command arguments. `DillaKnobs.conflicts` reports
seven names now, each with the site and the enclosing method, and
`test_the_set_of_knobs_with_two_defaults_does_not_grow` pins the set so an eighth
fails. `ruby dilla.rb knobs conflicts` is the report.

The three the scanner should never have called defaults: `MELODIC_LEAD`, whose
`"0"` is the comparand in `ENV.fetch("MELODIC_LEAD", "0") != "0"` one line below a
`return false if ENV["MELODIC_LEAD"] == "0"` and is therefore reachable only when
the knob is unset; `HARM_VOL`, whose `"2.4"` is the base of an increment on a line
that both reads and writes the knob; and `EVOLVE_EVERY`, whose `"2"` is the tail
of a chain that belongs to `STREAM_HARMONY_EVERY`. `EVOLVE_HARMONY_W` and
`EVOLVE_GROOVE_W` each read two of their literals in the two arms of one `if`
inside `evolve_weights`. `LISTEN_PASSES` is 0 in the render path and 3 in the
`listen_loop` subcommand, which its own help text documents. `TRACK`, `BARS` and
`BPM` are per-command — and `BPM`'s two literals are a silence placeholder and a
positional argument, while the site that decides every render reads `ENV["BPM"] ||
DEFAULT_BPM` and is 86, which no scan of literals can see. Opaque sites are
counted and printed now, so an incomplete list says it is incomplete.

Of the three that survived, two are closed and one is the owner's ear. The
`RENDER_BEAUTY_MIN` "conflict" was a ladder read as a disagreement — 65 to keep
iterating, 68 to keep a streamed take, 70 to keep a rendered one — and both gates
now say so beside their literal. `stream_iterate_evolve_harmony!` no longer
destroys a pinned `EVOLVE_HARMONY_W`; it applies the `USER_PINNED_ENV` rule
`style_env_write!` applies everywhere else, and an unpinned stream walks exactly
as before. **The `HARM_VOL` bump stays a pass behind itself**, because 2.4 plus
0.05 is the 2.45 the engine already defaults to and raising the base is a mix
value: `composition_engine.rb` carries the measurement beside the line, and the
change is the owner's.

### Small, mechanical, and none of them touch sound

- The `#!/usr/bin/env ruby` scripts under `dilla/bin` no longer disagree with the
  tree: all three now carry `# frozen_string_literal: true`, which the other 104
  Ruby files in STUDIO already had, so all 107 do. The `.sh` strict-mode row and the
  `NEVER_BATCH_DELETE` row that used to sit here named `dilla/bin/*.sh` and
  `bin/sine_stream_ticks.rb`, and neither exists: `dilla/bin` is four files.
- `lib/knobs.rb` and `dilla.rb` used to state the knob count in prose — 632 across
  119 files, and 610 — against a census the tool computes on demand and which
  reports 729 across 45. Both now point at the command instead of restating it,
  which is the only form of that sentence that cannot go stale.

#### Not worth chasing

- **Folding `dilla/live/`.** The three `*.als.rb` sets share 10 identical code
  lines out of 81, 94 and 104, and the duplication is already extracted into
  `Rack`, which each calls 7 to 15 times — so folding them would collapse three
  distinct arrangements rather than three copies of one. Decided 2026-09-11: they
  stay. `broadcast.sh:24` and `recall.rb:89` resolve a set by filename and
  `Rack.journal!` writes the set name into `project/liveset.jsonl` as data, so a
  rename also breaks replay of every journalled pass — free today, because the
  journal holds 32 rows and not one carries `seed` or `set`, and never free again
  once a pass is played with the keys the sets now write. `dig_crate.rb` was the
  one movable piece, on the argument that crate ingest belongs beside
  `lib/crate_dig.rb`; it stays where it is, because moving a tool the crate
  rebuild is actively run from is a hazard for a filing improvement, and the
  confusion the move was meant to fix — two files one word order apart taking
  opposite positions on licensing — is fixed in the files themselves.
- **The three scripts that live twice.** `/Users/mac/Music/dilla_sines/` holds six
  Ruby files, three with a tracked twin — `sine_stream.rb` 2,023 lines outside
  against 2,027 tracked, `demo_full.rb` 130 against 127, `player.rb` 61 against
  `sine_stream_player.rb` — and not one pair is byte-identical. It is not a stale
  copy of the scripts, which is what this row assumed: the directory is a running
  installation, with its own renders, logs and shell runners beside them
  (`now.wav`, `proof.wav`, `beat.wav`, `stream.log`, `run_sines.sh`). Retiring the
  outside copies orphans the output next to them, so it is the operator's and it
  is a move rather than a delete. Nothing in this repository may touch the
  operator's home directory, and no census can see it — `dup_census` reads tracked
  files only and excludes `STUDIO/` besides.
- **Merging the three techno renderers.** `render_industrial`,
  `render_hate_techno` and `render_techno` share `techno_harmony_roots` and the
  schedule builders and look like three copies of one renderer. They hold
  genuinely different arrangements, and merging on surface similarity flattens
  three sounds into one. Read all three before proposing it again.
- **Flattening `STUDIO/dilla/renders/` into the dilla root.** Counted before
  doing it: `slum` emits fourteen files, `loose_pocket beats` twenty-eight, plus
  `foundry_pulse.mp3`, `hate_session.mp3`, `ALBUM.mp3` and `beat.wav` — about
  forty-six named files, before the contents of `renders/{wav,demo,mastered,
  beats,rescued}/`. `demo.wav` in the dilla root is the demo's own path and is
  already how `demo_all` defaults; every batch renderer keeps `renders/`. The
  session CLAUDE.md records was about the REPO root, and that half is closed:
  `DILLA_OUTPUT_DIR` defaults to the invoking directory, except when that
  directory is the repo root, where dilla refuses and writes to
  `STUDIO/dilla/renders/` with a line on stderr.
- **Blanket rescues in STUDIO.** The remaining discards are optional gem probes,
  external binaries whose output is parsed, optional state files and process
  teardown, and they are correct as they stand. A census that reports them again
  is measuring the idiom.
- **Preset reach in `postpro` and `lora`.** A reach census read 27 false positives
  here: presets are selected by name from argv (`postpro.rb:2942`, `:3335`,
  `:3457`), so a table driven that way has no in-tree reference by design, and the
  `PRINT_STOCKS` half came from a lookbehind excluding `:` when every use is
  written `print_stock: :kodak_2383`. `postpro` already owns the question in
  `vocab_check` (`postpro.rb:3573`), which asks whether a stock, lens or print
  stock is defined and used by no preset. Do not add a second census.
- **The 37 slugs in `sample_worth.json` that name no rack.** `loops.json` is gone
  with the crate, so there is nothing to compare them against; stale rows are
  dropped at load (`radio_chop.rb:637`) and pruned on the next chop (`:879`).
  Inert by design, and a rebuilt crate prunes it.
- **The sample rate declared ten times under three names.** `SAMPLE_RATE` in
  `dilla.rb`, `lib/acapella.rb`, `lib/radio_chop.rb` and `lib/vocal_chop.rb`;
  `RATE` in `lib/analog_synth.rb`, `lib/sample_flip.rb`, `lib/space_fx.rb`,
  `lib/verify_fx.rb` and `bin/sine_stream.rb`; and `SU_TUNNEL_IR_RATE` in
  `dilla.rb`. Every library one is namespaced, so nothing collides, and 44,100 is
  not a matter of taste. `lib/sample_worth.rb:18` is an eleventh `RATE` and not one
  of these: it is 11,025 on purpose, with the Nyquist reason beside it. The bare
  literal appears 46 times more, most of them inside ffmpeg filter strings, and
  interpolating those would touch render-path strings for no behavioural gain.
- **The three `cohesion.rb` regroups.** They no longer evade
  `DILLA_SUPPORT_CEILING`, which counts at any depth now, so the only argument
  left against them is the one the backlog already made: nine files with 14
  `__dir__`/`__FILE__` references between them, moved to satisfy a shape rather
  than to answer a question anyone has.
- **The three engine tests that time out under suite load.**
  `test_smoke_two_bar_render`, `test_provenance_separates` and
  `test_dilla_frozen_reads` pass in about 23 seconds alone against the 90-second
  `PROBE_TIMEOUT` (`test_dilla_engine_probes.rb:26`), and skipped rather than
  failed in the full 87-second `rake test:dilla` run today. Not a defect in what
  they measure; the budget does not survive a loaded machine, and a green subset
  here proves only that.

## Cross-cutting programs

Larger efforts that span trees or do not belong to any single one. Each is a
program with its own sitting, listed so they are visible in one place rather
than implied across four.

- **Seed realism.** Only population is missing, and the entry used to imply more.
  Measured 2026-09-10: `CitySeed::COORDINATES` and `TIME_ZONES` each hold 43
  keys against `DomainRegistry::ENTRIES`'s 43 cities, the set difference is empty
  both ways, and `rows_from_registry` uses `.fetch`, so a new registry entry
  without a row raises at load. Population has no column in any of the three
  schemas and no seed anywhere.
- **Bringhurst typography codification.** Most of it is enforced already, and
  what is left is three named gaps rather than a programme. The size ladder
  (`_tokens.scss:52-65`), the weight ladder (`_dialect_tokens.scss:84-86`) and
  the measure, leading and tracking ladders (`_typography.scss:14-28`) are
  tokens; `css_constitution.rb:212-227` reads both ladders out of the
  stylesheets so no gate copy can drift, and `css_budget.yml` holds `type_scale`
  at 0 and `weight_ladder` at 2. `check_caps_tracking`, `MEASURE_OPTIMUM` and
  `geometry_type.rb`'s rendered measure and modular-scale checks cover the rest.
  What is not enforced: no lint says a `line-height` literal must come off
  `--leading-*` (`css_constitution.rb:61` lists `line_height` as a config key
  that never got a reader). Sized 2026-09-10 before anybody opens it — 87
  literals across the fleet, seven of them in `face.css` — so it is a new
  `css_budget` row and a pass over the operator's own stylesheets, not a lint
  somebody adds on the way past. `MASTER/web/public/face.css` sits outside the asset
  pipeline and cannot read the ladders, which is the whole of the residual +2 on
  `weight_ladder`; and `rules.yml`'s `beauty.typography_bringhurst` is four
  slogans with no detector.
- **The layout pass.** Roughly 178 proposals from a study of joi.com, kimi.com
  and medium.com, worked one category at a time; about sixty are closed. Its own
  section below carries the state and the doctrine it produced.
- **Web-face redo.** The MASTER web face (WebGL + TTS) wants a rebuild; see the
  web-face notes in the MASTER debt records for the current failure map.
- **Onboarding.** A first-contact path that gets a new agent or contributor from
  clone to a green check without reading every contract. `MASTER/bin/onboard` is
  not it: it writes `.master/config.yml` and never runs a check.
- **Local-LLM fallback**, and it is not "one method", which is what this entry
  said until somebody wrote it. `Master::Review::LLMDispatcher#send_llm_request`
  has branches for `agy:`, `claude-cli:` and `web-chat:` and none for `ollama:`,
  so a chain that reaches the local tier ships the id to the OpenRouter client
  and errors. The branch is easy; paying for it is the work. Written and
  measured 2026-09-10 as an `OllamaSender` module beside `RubyLLMSender`: 51
  body lines and one file. `llm_dispatcher.rb` cannot hold it — the class is at
  298 code lines against NO_GOD_CLASS's 300 — and every ceiling it lands against
  sits at exactly its value, so it costs a `growth.master` raise and a
  `spine.lib_body_ceiling` raise, and `models.yml` gains a reader against a
  `reader_singularity` ceiling that is also full. Done when somebody spends
  those deliberately, or absorbs 51 lines elsewhere in `lib/` first. The tier is
  correctly absent unless `OLLAMA_BASE_URL` is set — it used to sit in every
  fallback chain on every machine.
- **Aegis, seaborne.** A safety agent for the water, and the first body the
  embryo could plausibly take. It is a program rather than a feature because
  most of it is gated on hardware; the section below says what is buildable now
  and what is not.

## The layout pass — opened 2026-09-02

A study of joi.com, kimi.com and medium.com, read against this tree, produced
roughly 178 proposals, worked one category at a time. The list itself lived in a
conversation and was never written down, so the closed items are recoverable
only from `git log` and perhaps forty of the open ones are gone. What follows is
what survived, not a copy of the original.

What the pass taught, which is worth more than the list:

- **Most proposals were not problems.** Of the three raised against motion, two
  were already satisfied — `transition: all` was two sites rather than a
  pattern, and `REDUCED_MOTION` was met. The real defect was thirty byte-
  identical copies of one reduced-motion reset, which no proposal named.
- **A finding against the design system is usually a finding against the
  instrument.** `--transition-fast` looked undeclared in every bundle until the
  resolver was found to follow `@use` and not `@forward`; `.42s` read as 42000ms
  until the regex was fixed. Compile the three apps before and after, and
  compare, rather than trusting a scan.
- **A value-preserving snap is a fix; a value-changing one is a decision.**
  160ms is `--transition-fast` written 20ms apart, and whether those are one
  step or two is a question about how a hover should feel. Off-scale values that
  cannot move without changing the render are recorded as baselines in
  `design_tokens.yml` with the argument beside them, never snapped to silence a
  lint.
- **A retirement is not finished while a test still names the retired thing.**
  Collapsing `--measure-body` left `layout_contract_test` asserting the retired
  spelling, and the obvious way to make it green was to re-declare the twin.
- **Sticky hover is not a defect here.** 122 `:hover` declarations across 52
  files against four `@media (hover: ...)` guards reads alarming until the
  hovers are classified: eighty-two only repaint, thirty declare nothing that
  matters on touch, and the ten that move or reveal are opacity or transform
  nudges. Nothing strands a tap. Re-classify before re-opening this.

### Open, by category

These five numbers are the whole record and nothing enumerates their members —
no file, no ledger, no commit. The commit that wrote this section says so
outright, and re-reading the tree for it in 2026-09-10 found nothing either. So
they cannot be worked from: re-run the study, or work from the verified items
below, which do name their files.

- **Controls** — 10 left.
- **brgen** — 9 left.
- **Radius** — 6 left.
- **amber** — 5 left.
- **Instrument** — 4 left.

### Held open deliberately

**Four face transitions exceed `NO_LONG_TRANSITION`.** `face.css:380` at 1200ms,
`:635` at 1800ms, `:867` at 400ms, `:1015` at 600ms, and `chat_upload.css:42,48`
at 420ms each. Left alone: this is the operator's own face timing, and the rule
caps UI transitions, not a deliberate slow reveal. No baseline records them, so
this line is the only thing standing between them and a well-meaning fix.

**Seventeen control classes still paint a visible border, and one question
covers all of them.** `.deal-cat` at `RAILS/brgen/app/assets/stylesheets/_marketplace.scss:48`
sets `border: 1px solid var(--border)` beside `background: var(--surface-elevated)`
on line 47, so it carries both the fill and the line the 2026-08-04 decision
traded away (`WIRING_NOTES.md:359,378-381`). Its six call sites are all in the
marketplace engine — takeaway has none — and sixteen other control-like classes
across eleven stylesheets do the same, from `.carousel-btn` to `.pager-link`. So
this is not a one-line lint fix on one class: it is whether the 2026-08-04
decision reaches controls that were never revisited. It changes rendering, so it
waits for the operator.

### Closed 2026-09-10, and none of the three was a defect

- **A shared display-type slot stays unbuilt, and the argument is now at the
  rule.** `_typography.scss` carries it above `main#main-content > header h1`:
  the marketplace hero is the fleet's only opt-out and matches the id itself to
  outrank it; lowering the shared rule to a class changes which override wins on
  every surface that has one, and `:not()` ties rather than wins because it takes
  its argument's specificity. An opt-out is a design decision about what display
  type means, not a refactor.
- **playlist's two scales are one recorded fence and one already-recorded gap.**
  `SURFACES.md:65` has held the `--edge-*` hairlines against a shared edge scale
  that does not exist since before this entry was written, so the line was a
  second copy of it. `--font-mono` is the fifth face and it is deliberate — the
  vertical is branded on the SF family, stated at the head of
  `_vertical_playlist.scss`, and the token is scoped to `body.vertical-playlist`
  so nothing else inherits it. Recorded in `SURFACES.md` under Fences.
- **`WORN_TYPE.profiles.map.label_min_px` has a reader** — `MASTER/test/test_design_rules_worn_type.rb:48-71`,
  which names it deliberately unwired and says enforcing it means measuring
  rendered label sizes. The same test found the larger unread key,
  `rhythm_off_max_pct`, declared in all seven profiles and read in none.
  Instrumented where it matters; it does not need a backlog line.

## From the 2026-09-01 audit

- **The browser half of the gates still measures nothing unattended.** The live
  half no longer does: `vps-deploy` runs nine gates on every deploy with
  `GATE_REQUIRE_LIVE=1` as of 2026-09-10, on the one host where a closed port is
  a deploy that did not come up rather than a laptop. What is still opt-in is
  `PUB4_DEPLOY_BROWSER_GATES=1`, and the argument against making it the default
  is in `vps-deploy` beside the flag: the box is 1GB with four apps resident and
  `resource_guard` sheds amber and bsdports under exactly the pressure Chrome
  adds, so a deploy that takes the site down to check the site has failed at the
  only thing it was for. Done when the browser half runs somewhere unattended
  that is not vm23. `GATE_STRICT_ERRORS=1` is the cheap remaining half and can
  go into the same line the day somebody has read one ledger's worth of errored
  gates.
- **The 61-track crate fetch was abandoned at 2, and the staging is bigger than
  this entry said.** `~/dilla-crate-incoming` holds two FLACs (42 MB), four fetch
  scripts, four logs and `stems/htdemucs_ft/` with demucs output for both tracks
  — eight wavs, 161 MB, 202 MB in all, every file dated 2026-08-31. Nothing in
  the repo references the directory. Not closed here on purpose: those two FLACs
  are source audio, renders reproduce and samples do not, and deleting the
  operator's audio on an agent's judgement is the one move this repo's own
  memory forbids. His call, and only his.

---

# Forward work

Merged from `WISHLIST.md` on 2026-09-06, which is now deleted. That file held
wishes, hypotheses and the shape a tree would take if somebody rebuilt it,
while this one held records with a measurement behind each. Two files meant two
places to look and two places to go stale, and the split cost more than it
bought: a reader chasing one subject had to know which half owned it, and three
entries above already point across the seam.

What was true of the old file stays true of this section. **Every section is
dated and says who wrote it**, because several are not by the same hand and
disagree in places. An item leaves this section when the tree ships it, not
when it stops being mentioned. Where a wish has been measured against the tree
it belongs above, as a record, not here.

## Open from the enumerations — 2026-09-09

Four enumerations sat here: 112 things from 2026-08-29, twelve external
hypotheses, two near-identical 220-item wish lists written from outside the tree,
and 110 wishes from 2026-09-06. All 674 items were read against the tree.
Thirty-nine declared themselves done, another fourteen proved already true on a
grep, and the two 220-item lists were unmeasured advice — several items name gems
this fleet does not run, among them sidekiq, CarrierWave, ransack, searchkick and
`has_and_belongs_to_many` — so both went whole. What survived is below, each item
naming the file it concerns and what closing it looks like.

The enumerations proved their own opening claim, which is the half worth keeping:
a finding is a hypothesis until the instrument has been checked. A second pass on
2026-09-10 proved it again on the survivors: of sixteen items, one asserted the
opposite of the truth, three had numbers that did not reproduce by any method,
and two named the wrong file. Seven closed. The instrument entries closed by
being built — `bin/operator measure --why <row>` names the members behind a number
and checks that they add up to it, `--since <ref>` reads the recorded ceilings
out of git so a session can diff its own effect before pushing, `bin/operator gate
--tree <TREE>` drops the stages that prove another tree, and `bin/operator rule <ID>`
prints the declaration, whether it reaches a detector, and the definition
verbatim with the comment that earned its exemption.

Two of those closures need saying rather than deleting, because the next reader
will otherwise re-open them. **Silent detectors were already measured**:
`measure` has carried `rule_audit.silent` as a ratchet row all along and it
reads 39, and `--why rule_audit.silent` now names them. Its corpus is `law/`'s
rules over `MASTER/lib`, `law/`, `RAILS/shared` and the two hand-written
JavaScript homes — chosen deliberately and widened once already — not the whole
fleet, which is what `bin/operator gate` and `self_findings.registry` measure.
**Gate cost is measured, not declared**: `gates.yml` gained a `needs` field
consolidating runner.rb's hardcoded browser list, and refused a `cost` field on
the ground that a declaration cannot show the failure a cost field is for. A
gate that doubles reads the same as a gate that did not; only a history can tell
them apart, so `runner.rb` prints each gate's measured median from the ledger
before it starts and the ledger flags a gate whose last five runs are twice its
earlier ones. And the deploy question the third gate entry left open is
answered: `vps-deploy` runs nine gates on every deploy, with the cost argument
for which nine written beside them.

### STUDIO

- **The dilla ENV switch census does not reproduce, by any method.** The entry
  said 138 default off. `lib/knobs.rb` — the engine's own registry, which infers
  type and default from source — reports 727 knobs, 286 of them flags, of which
  80 default on, 38 carry an explicit `"0"` and 168 have no default at all: 206
  default-off flags, 189 once `DILLA_FULL`'s eighteen are subtracted. An
  independent regex over `dilla.rb` and `lib/*.rb` gives 475. `dilla.rb:4498`'s
  own comment claims 156 of 405 and is stale too. The count is not the work; the
  classification is. Done when the default-off flags are sorted into additive,
  exclusive fork and operational, and the dead ones deleted rather than renamed —
  `knobs.rb` is the instrument to do it with, and it already answers the type
  half.

### RAILS and MASTER

- **`NO_GOD_CLASS` is the fleet's largest single piece of design debt.** It is
  not growing: the entry that said so compared
  `bergen_demo_seeder.rb`'s 902 raw lines against its own 834 code lines, the
  same file measured two ways on the same day. That file is now 337 code lines —
  the five hundred lines of literal Bergen it carried moved to
  `bergen_demo_data.rb` and come back through `include`, and its six tests pass
  unchanged. It still breaches, at 337 against a 300 limit, and it stays counted:
  what is left is sixteen private methods, one per vertical, driven by one
  `seed!`, and splitting that means ten files with one caller each — a god class
  traded for FILE_SPRAWL.

  The other two breach on public method count, not length, and each wants a
  different cut. `brgen/app/models/conversation.rb` is 28 public methods over
  178 code lines and is genuinely several subjects: IRC channels (`:17-104`),
  geo rooms (`:106-132`) and unread counting (`:236-321`) are three
  self-contained blocks with their own constants, and the last is a pure query
  concern. `takeaway/order.rb` is 26 methods over 179 lines and is one subject in
  three layers — a state machine, delivery and ETA, and eight pure display
  formatters. Moving the five `*_display` methods to a presenter drops it to 21
  and the five status aliases to a generated loop drops it to 16, so neither
  half clears the limit alone and the real cut is the state machine.
- **The `probe`/`check` pair is the ladder with two doors**, and both doors have
  real callers — `RUNBOOK.md` and `bootstrap_docs.rb` for probe, `CLAUDE.md` and
  thirty `PATH_OWNERSHIP.yml` rows for check. `probe`'s `ci` entry shells
  `bin/ci` which shells `check --profile=ci`, and `check`'s `full` profile shells
  `probe all`. `gate`, `audit`, `doctor` and `check` are four genuinely distinct
  things, not eleven. The two folds this entry used to propose — `nsaudit` and
  `dogfood` into `check` — are decided against: `bin/probe` carries the argument
  beside them, and it is the bare top-level `ROOT` that makes a subprocess the
  safe shape.

## From the awesome-list horizon scan — 2026-09-11

Ten curated lists were read against the tree: `awesome-ruby`, `ruby-bookmarks`,
`analysis-tools-dev/static-analysis`, `awesome-rails`, two `awesome-hotwire`
forks, `awesome-css`, `awesome-html5`, `awesome-markdown`, two
`awesome-openbsd` lists and `awesome-selfhosted`. Almost everything they name
this repo either has, has decided against with a measurement, or cannot run on
one 1 GB box. What survived is below, and every item was checked against the
tree before it was written down — four candidates died on that check, including
one this scan first reported as missing and then found in all four
`Gemfile.lock`s.

- **Autofix has no safety tier, and the default is to fix.**
  `Scan::Scanner#should_autofix?` returns true unless the rule has a
  `prediction_engine` entry carrying a `confidence` threshold in `rules.yml`.
  Three rules do — `null_usage`, `abbreviation`, `nesting_depth` — against 242
  declared. The other 239 are fixed at any confidence. `Scan::Finding` already
  declares `reversibility` and `blast_radius`, `semantic_rules.rb` and
  `meta_rules.rb` populate them, and nothing under `lib/fix` reads either;
  `Fix::RuleLoop` reads `confidence` alone. RuboCop and Standard both solve this
  by declaring safety per rule and splitting the command — `--fix` against
  `--fix-unsafely`. Cost: no dependency. A `safe` field on `Law::Rule` and on
  the registry's `declare`, a default of unsafe for a rule that does not say,
  and a flag on `/fix`. The work is classifying 242 rules, not writing the
  field. Worth doing when someone is willing to make that classification the
  session's subject; the ceiling on its value is already recorded above, where
  `/scan`'s autofix is marked do-not-run-unattended.

- **relayd is restarted every time an app comes back, and relayctl can do the
  same job without it.** All four `rc.d` scripts run `rcctl restart relayd` once
  their app answers `/up`, and `start_all_apps.sh` runs it again; `vps-deploy
  all` therefore drops the single `listen on 0.0.0.0 port 443 tls` five times in
  one pass, for every host on the box. The nine-minute outage of 2026-08-10 was
  that restart. `relayctl(8)` has `table disable` / `table enable` and `poll`
  ("Schedule an immediate check of all hosts"), which is exactly the kick the
  comment in each script asks for and touches no listener; bracketing the
  restart with `table disable` also stops relayd recording a booting app as
  failed. Cost: base tools, three lines per script. Worth doing once the man
  pages for `relayd.conf(5)` and `relayctl(8)` have been read from vm23 and one
  app has been bracketed by hand. `relayctl reload` — not restart — is the
  answer for a genuine `relayd.conf` change.

- **162 `scan: intentional` markers, in 95 files, and nothing checks that any of
  them still excuses something.** `law/practice.rb`'s `EXEMPTIONS_EXPIRE` says
  an opt-out outliving its subject is a hole in a gate nobody can see, and it is
  a `practice` rule, so it carries no detector. One half of it is detectable:
  scan the file again with the marker stripped, and a marker whose line draws no
  finding is stale. erb_lint ships this as `NoUnusedDisable`. Cost: no
  dependency, one pass of an existing scanner and one ratchet row. Worth doing
  now — the scanner is already there, the law is already declared, and the
  number is unaudited.

- **The resource guard sheds per process and measures per box.**
  `resource_guard.sh` logs `load`, `mem_avail` and `shed` per tick and decides
  which of amber and bsdports to drop, but never reads a single process's RSS,
  so the log cannot say which daemon was the cost. Cost: `ps -o rss= -p` per
  app, three lines, into the same history line the thresholds were already
  recalibrated against. Worth doing before the thresholds are touched again;
  8/14 and `LOAD_RESTORE` 2.0 were set against an aggregate.

- **The `rails` login.conf class caps datasize at 4096M on a 1 GB box.**
  brgen, amber and bsdports all inherit it, so the limit is not one.
  `login.conf(5)` limits are honoured because `rc_exec` runs the daemon through
  `su(1)` under a class named after the rc.d script. A realistic per-app
  `datasize-cur` turns a leaking app into a `NoMemoryError` inside that app
  rather than a swap storm that takes the box. `openfiles-cur` inherits 128 from
  `daemon`, which is low for a fiber-per-connection Falcon. Cost: two lines per
  class. Worth doing once each app's steady-state RSS has been measured on
  vm23 — a number guessed low kills a healthy app, which is worse than the
  swap.

- **relayd's listen backlog is the default 10.** `relayd.conf(5)`: "The backlog
  option is 10 by default, is limited to 512 and capped by `kern.somaxconn`."
  Ten pending connections in front of four apps that take 30-40s to boot cold.
  Cost: one word. Worth doing when someone can show connections being refused
  during a restart rather than merely being slow.

- **Two i18n checks the contract tests do not carry.** `locale_contract_test`
  covers duplicate keys, one home per key, root naming and nb/en parity;
  `i18n_resolution_test` covers every defaultless `t()` resolving. Absent: a key
  defined in a locale file and referenced nowhere, and interpolation arguments
  agreeing across locales — `%{count}` in `nb` and missing in `en` renders the
  literal. i18n-tasks is the gem for both and is the wrong shape here: it needs
  search paths declared for six mounted engines and `pub4-shared` or it reports
  every engine key as unused. Cost: about thirty lines in each existing test
  file, no dependency. Worth doing when a translation_missing or a bare
  `%{count}` is seen on a page.

- **Cross-engine references are unmeasured, and there is one.** Measured
  2026-09-11 over all six engines under `brgen/engines`: one engine reads
  another's constant — `maps/app/controllers/maps/home_controller.rb:75` reads
  `Takeaway::Order`, deliberately, for the courier layer — and zero associations
  cross an engine boundary. `isolate_namespace` does not prevent either.
  Packwerk exists to prevent both and carries a C extension through
  `better_html`. Cost: one row in `gates.yml` and a source gate reading text,
  shipping with that one line as its declared exemption. Worth doing while the
  count is one; at ten it is a cleanup rather than a line held.

- **Snapshots never leave the disk they protect.**
  `Shared::DatabaseSnapshotJob` writes `VACUUM INTO` copies beside the database
  and says so in its own comment; `restore_backups.sh` restores from
  `/var/backups/litestream/`, which `OPENBSD/DECISIONS.md` records as empty and
  unfillable, litestream being Go and absent from ports. So the box has
  same-disk snapshots and a restore path that points at nothing. Cost: base
  tools — `openrsync -e ssh` is already used by every deploy, and the snapshots
  are gzipped. Worth doing as soon as there is somewhere to put them; the
  destination is an operator decision and the data is irreplaceable.

- **Findings have no portable form.** `Scan::Finding` carries `rule_id`,
  `message`, `line`, `severity` and `fix` — everything SARIF needs — and
  `law/`'s rules carry the two fixtures that would fill a SARIF rule's help
  text. 242 rules are currently legible only to this repo's own reporters. Cost:
  about sixty lines of Ruby, no dependency. Worth doing only if the corpus is
  ever meant to be read by something outside pub4; there is no consumer today,
  and building one for a reader that does not exist is the defect this file
  records most often.

- **An HTML-aware ERB parser is arriving whether or not we choose it.** Herb
  parses HTML and ERB into one tree and uses Prism for the Ruby inside the tags;
  GitHub runs it on the monolith and there is an open PR to make it Rails'
  HTML-aware ERB implementation. It is a C extension, so under the argument this
  tree already used against tree-sitter it is a reject — but if Rails adopts it,
  it lands on vm23 as a dependency and the argument changes from "do we want a
  native parser" to "we have one, do `law/html.rb`'s regexes still earn their
  keep". Cost: nothing yet. Worth revisiting when that PR merges, and not
  before.

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

