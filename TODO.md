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
(`ast_fixer/web_transforms.rb`) declines a chain followed by anything binding
tighter than `+` — a call, a subscript, a member, a tag — which is the `walk.js`
corruption above and `'a'.repeat(3)` beside it, both held by
`test_string_concat_declines_a_chain_followed_by_a_subscript_or_member`.

The general net is in now, and it is the reason this entry no longer ends in
"never run it unattended". `AstFixer.propose` builds a candidate without touching
the disk, `MechanicalAutofix` is the governed writer, and the same `WriteGuard`
that judges every constitutional write judges the candidate — only what a fix
*introduces* can refuse it, so a file carrying debt stays repairable. A deleting
transform also waits for a person on both paths now rather than only on the
rule-driven one. What the guard cannot see is a change that introduces no
finding and is still wrong, which is exactly the `walk.js` shape, so a transform
still earns its own test.

The gate costs 90-180 ms per file it judges, plus 207 ms once to build the
scanner, measured on this tree. It runs only on files that already have an
autofixable finding, so a tree-wide pass pays it tens of times rather than
thousands.

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

- **Autofix classifies by transform, not yet per rule.** The tier landed: a
  transform that deletes waits for `MASTER_AUTOFIX=1`, and one that adds runs
  unattended, because an addition shows itself in the diff it makes. Only four
  of 242 rules declare a transform at all, so today that is
  `remove_immediate_dead_code` on one side and three `add_*` on the other, and
  the `prediction_engine` thresholds it replaced could refuse nothing — they
  were keyed `null_usage`, `abbreviation` and `nesting_depth`, three words
  naming no rule, so every lookup missed and every rule came back allowed.
  What remains is the per-rule half. `Scan::Finding` declares `reversibility`
  and `blast_radius`, `semantic_rules.rb` and `meta_rules.rb` populate them,
  and nothing under `lib/fix` reads either. RuboCop and Standard split the
  command instead — `--fix` against `--fix-unsafely`. The work is classifying
  242 rules, not writing the field, and it is worth a session that takes the
  classification as its subject rather than a pass that guesses.

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

## From the gem and ruby_llm audit — 2026-09-11

Two questions were asked of the tree: what hand-rolled logic belongs to a gem,
and what does MASTER hand-roll that the gem it already loads provides. Ten
declared-and-never-required gems came off both lockfiles, the swarm reviewer
stopped reading an unparseable reply as an approval, and cost stopped being one
flat rate for every model. What follows is what the audit found and did not
close.

- **`relative_luminance` omits the gamma decode.**
  `lib/review/scan/source_masking.rb:318` computes luma and calls it relative
  luminance, so the `< 0.4` dark-background threshold beside it is calibrated
  against the wrong quantity. `RAILS/gates/support/design_metrics/contrast.rb:34`
  does the same named quantity correctly. Two implementations, one wrong.
  Correcting it moves gate output, so it needs a recalibrated threshold in the
  same change — otherwise the fix reads as a regression.

- **MASTER pins ruby_llm `~> 1.3` and locks 1.13.2; stable is 1.16.0.** Four
  things MASTER hand-rolls are in the version already locked. `with_schema`
  takes a plain Hash and returns a parsed one, against six regex extractors.
  `Model::Info#function_calling?` and `#supports_vision?` answer what
  `TOOL_CAPABLE_RE`, `VISION_RE` and `NON_VISION_RE` are built to guess.
  `request_timeout`, `max_retries` and `retry_backoff_factor` are never set in
  `lib/boot/runtime.rb`, so ruby_llm retries three times inside each
  circuit-breaker call and the breaker counts one. `with_tools(*t, calls: n)`
  caps tool rounds, where `REACT_MAX_STEPS` guards only the emulated path, so
  native tool calling runs uncapped. Each is a separate change with its own
  test; the pin moves last.

- **`KeyRotator.configure_current!` mutates process-wide `RubyLLM.configure`
  while the fix loop runs rule groups in threads.** `RubyLLM.context { }` gives
  per-call isolation and is in 1.13.2. The race is a wrong key on a concurrent
  call, which reads as a provider error rather than as a race.

- **A `:free` OpenRouter model is charged the flat rate.** Cost now reads the
  registry, but the registry does not carry `...:free` ids, so they fall back
  to $15 per million — the most expensive rate in the catalogue, for tokens
  that cost nothing. Pricing them at zero is right only if `:free` is verified
  per id rather than read off the suffix.

- **`lib/review/embeddings.rb` is hand-written Net::HTTP against Ollama**, and
  1.13.2 ships an ollama provider with `RubyLLM.embed`.

- **`ruby_llm-test`, `-evaluations` and `-tribunal` are worth evaluating** —
  provider mocking for the suite, and a quality framework for the council.
  `ruby_llm-schema` is deprecated in favour of schematist and should not be
  adopted; pass a Hash. Skip `-resilience`, `-top_secret`, `-agents`, `-team`
  and `-template`: MASTER owns richer versions of each, and its circuit breaker
  is dollar-budget-aware and survives a restart, where the gem version is
  neither.

- **`lib/review/scan/rules/lexical_rules.rb` re-implements about fifteen
  RuboCop cops in 369 lines**, while `external_linter_rules.rb:47` shells out
  to RuboCop. Real duplication, but each rule id is a name the law addresses,
  so replacing them renames the law. Not small.

- **Four hand-built RIFF headers in dilla** — `dilla.rb:25123`, `:34192`,
  `lib/devices.rb:611`, `bin/sine_stream.rb:1670` — against `wavefile`, which
  is already declared and already used at `lib/music_gems.rb:231`. Container
  bytes only, identical PCM, so it changes no sound.

- **`Route#suggest` carries a Levenshtein matrix**
  (`lib/cli/stages/route.rb:53-67`) where `DidYouMean::SpellChecker` is a
  stdlib default gem Ruby loads at boot. Verified to return the same answers
  on the command list. No dependency, fifteen lines.

Three things were checked and left hand-rolled on purpose.
`RAILS/gates/support/cdp_framing.rb` implements RFC 6455 in 162 lines because
gates run under bare `ruby` with no bundle, ferrum lives only inside the
per-app bundles, and the gates need `host-resolver-rules`, which ferrum does
not expose. `lib/trace/event_bus.rb` is not wisper: wisper broadcasts to
listeners, where this does glob topic matching, redaction, Fiber-scoped
conversation stamping and telemetry spans. And `estimate_tokens` stays
`bytesize / 4`, because the accurate answer is `tiktoken_ruby`, a Rust native
extension, and this repo deploys to OpenBSD.

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

1. **`tools.yml` names a dead adapter tree.** `MASTER/data/tools.yml:2` — “Adapters in `lib/master/tools/`”. Factories live in `lib/builder.rb` `DEFAULT_TOOL_MAP` and `lib/io/*.rb`. Rewrite the header.
2. **Repligen/Postpro declared, never constructed.** `data/tools.yml:32-33` list them; `lib/builder.rb:16-53` has no factories. CLI shells STUDIO. Add factories or drop the rows.
3. **`runtime.yml` still maps a deleted docs tree.** `data/runtime.yml:7` `source: docs/cognitive_runtime.md`; `landed_subsystems` names files under `MASTER/docs/`, which does not exist. Point each at the live file or delete.
4. **`topologies.yml` is the deleted pixel-field, still loaded.** `data/topologies.yml:1-4`. `cell_grammar` / `emotional_mapping` / `palettes` sit in `data_reach.yml` `unnamed_members`. Drop those keys or wire one renderer.
5. **Palette keys contradict one chrome.** `topologies.yml:34-42` operator/review/visitor palettes. Mark canvas-only and test that chrome does not read them, or delete.
6. **`START_HERE.md` has a broken sentence.** `:142` “…`yml` (active read-modify-write…” — the filename was eaten. Restore the stem or cut the clause.
7. **`START_HERE.md` still defends deleted YAML.** `:147-150` discusses `visual_clusters.yml` / `mobile_web_opportunities.yml`. They were deleted 2026-08-11. Move the paragraph to DECISIONS.
8. **Three files, one voice string.** `soul.yml:9` `voice: en-NG-EzinneNeural`; `voice.yml:23` `neural:`; `tts.yml` for the engine. One reader (`Voice::Policy`) should own the string; the others cite it.
9. **`limits.yml` still titled Tier 1 Law in START_HERE.** `:170`. `limits.yml:1-18` is explicit that most of it is unread `guidance:`. Retitle START_HERE to match `test_limits_split.rb`.
10. **`project_context.yml` names `MASTER/exe/tts-worker`.** `:36` — worker is `MASTER/bin/tts-worker`.
11. **`project_context.yml` still lists `visual_clusters.yml` as a fold exception.** `:27`. Remove.
12. **`data/claude/` is empty but still a default corpus.** `lib/ground/memory_index.rb:11` and `lib/cli/brain_overlay.rb:7` still glob it. Drop it from `DEFAULT_DIRS`.
13. **`data_reach.yml` 28 unnamed keys.** Including `runtime.yml#cognitive_spine`, `soul.yml#evolution_log`, `topologies.yml#palettes`, `models.yml#ollama_*`, `personas.yml#british`, `providers.yml#mistral`. For each: find a reader or delete. Do not build a repo-wide unread-key gate.
14. **`reader_singularity.yml` still allows 10 readers of `rules.yml`.** Collapse remaining readers onto `Master.load_rules` / `Master.law`.
15. **Dual constitution classes.** `lib/ground/constitution.rb` vs `lib/core/constitution.rb`. Rename Ground’s to `PrincipleStore`.
16. **Dual memory search.** `lib/ground/memory_search.rb` vs `lib/ground/memory/search.rb`. Rename the index one `DocIndexSearch`.
17. **Three mood systems.** `lib/pressure_engine.rb`, `lib/trace/context_pressure.rb`, `lib/cognition/affect.rb`. Document which bus events each consumes, or fold PressureEngine into Cognition.
18. **Dual attention.** `lib/cognition/attention.rb` vs `lib/cli/attention_context.rb` vs `data/attention_context.yml`. One table of weights.
19. **`bootstrap.yml` vs `bootstrap_docs.rb`.** Both mention `/tail` `/replay`. `/tail` is not in `CommandRegistry.build`. Confirm callers.
20. **`security.yml` `gateway.port: 18789` is a second listen story.** Web Falcon is 53187. Add a sentence that 18789 is not the face.
21. **`PATH_OWNERSHIP.yml` owns missing dirs.** `docs:` and `reports:` — neither exists. Delete the keys.
22. **`PATH_OWNERSHIP.yml` omits live dirs.** No entries for `lib/cognition/`, `lib/pressure_engine.rb`, `law/`, `AEGIS.md`, `COGNITION.md`, `EXAMPLES.md`. Add them.
23. **`PATH_OWNERSHIP.yml` `tools/` check is a source-grep spec.** `:179` `spec/lifecycle_tools_spec.rb` asserts `bin/doctor` contains `"check_yaml"`. Point the check at a real tool test.
24. **`data/tools.yml` `name:` vs `Master::Io::`.** Header says `Master::Tools`. Runtime is `Master::Io::ReadFile`. Align the namespace.
25. **`RuntimeCatalog.load("tts_phrases")` vs `data/tts.yml`.** Confirm `tts_phrases` exists in a catalog `sections` list (`runtime_catalog.rb:20-24` already records a miss).
26. **`DATA_ALIASES` vs filenames.** Audit `lib/boot/data.rb` aliases against files on disk.
27. **`soul.yml` `sacred_paths` includes `bin/cli`.** `:65`. `bin/master` is the instruction surface. Add it or drop `bin/cli` if it is only a pointer.
28. **`soul.yml` `anti_simulation.forbidden: [will, would, could, might]`.** If the detector is lexical it is noise; if unused it is inert law.
29. **`models.yml` ollama rows unnamed.** Delete or wire `QuotaGate` / router.
30. **`personas.yml#british` unnamed.** Delete or add to `Personality.persona_names`.
31. **`providers.yml#mistral` unnamed.** Row or reader, not both silent.
32. **Three lists of council words.** `council.yml` vs `HELP_TOPICS` vs `TurnRouter::MODEL_ALIASES`. One table.

### MASTER — untested lib

33. **`HashDigCompat`.** `lib/boot/hash_dig_compat.rb` prepends `Hash#dig` process-wide. Prove MRI nil-short-circuit vs coltrane’s raise; prove `install_hash_dig_compat!` is idempotent.
34. **`BrainOverlay`.** `lib/cli/brain_overlay.rb`. Test `core_brief` and `load_context` against a planted markdown dir, not empty `data/claude`.
35. **`ResyncService`.** `lib/cli/resync_service.rb` — `git reset --hard origin/main`. Dry-run must not reset; live path refused without a flag.
36. **`FixPreviewReport`.** `lib/cli/fix_preview_report.rb`. No test of render shape.
37. **`DeliberationPrep`.** `lib/cli/deliberation_prep.rb` — `rescue StandardError` at `:17`. No unit test.
38. **`CouncilCrit`.** `lib/cli/council_crit.rb`. No test.
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
77. **`bin/nsaudit` is a two-spine leftover.** Confirm it still has a job; if it only audits namespaces, fold into `rake lint:autoload`.
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
88. **`web/CLAUDE.md` dated 2026-07-10.** `:265-272` resource_guard paused — verify against `OPENBSD/resource_guard.sh` before trusting. Add a last-verified or cut numbers that drift.
89. **`help.rb` “read-only” vs scan writes.** `:18` vs `:30-32`. Pick one sentence.
90. **`MechanicalAutofix` “`/scan` and `/self`”.** `/self` is a model alias for `/review`. Say `/review --only scan`.
91. **`lib/cli/README.md` still mentions `data/claude`.** `:33`. Empty dir.
92. **`mask.js` header claims `window.MASTERMask`.** Spec says mask.js is superseded (`spec/web/visual_governor_spec.rb:30-36`). Delete the file or the claim.
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
103. **`lib/grok/`.** If MASTER only ingests LoRA transcripts, name it `lib/io/grok_transcripts.rb`.
104. **`lib/deploy/`.** Easy to confuse with `OPENBSD/`. Rename `lib/operator/deploy_docs.rb`.
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
123. **`test_design_rules_worn_type.rb` reads `rules.yml` text.** Call `Design::Thresholds.worn_profile`.
124. **`test_edge_case_stub_generator.rb` asserts generated tests contain `skip`.** Generate real stubs or delete the generator.
125. **`spec/core_smoke.rb` is not `*_spec.rb`.** `rake spec` does not run it; `rake core_smoke` does. Rename.
126. **Three homes for face tests.** `web/test/`, `test/test_web_*.rb`, `spec/web/`. Pick two.
127. **`web/test/locale_contract_test.rb` vs `RAILS/test/locale_contract_test.rb`.** Extract one helper.
128. **`test_master_boot.rb` skips if `rules.yml` missing.** In this repo that skip can never fire usefully. Remove; let it fail.
129. **`test_style_guides.rb` skips unless `OPERATOR` checked out.** OPERATOR is not a tree. Dead skip or wrong path.
130. **`test_io_key_rotator.rb` skips unless two key vars.** Fixture ENV so empty/single-key branches run.
131. **FakeConfig `send(k) rescue nil`.** `test_agent.rb:12`. Swallows everything. Stop.

### MASTER — web face

132. **`mask.js` is dead weight.** Still on disk; `visual_limits.test.mjs:72` still iterates it. Delete `mask.js`, `mask_generators.js`, `mask_topologies.js` if nothing imports them.
133. **`codebase.js` not in `face_assets.yml`.** Topology `renderer: codebase.js` (`topologies.yml:95`) but the shell never loads it. Add to a deferred group or stop naming it.
134. **`offline_memory.js` not in the manifest.** `sw.js:78` says drain lives there; the contract test only asserts the file exists.
135. **`swarm.html` / `diag.html`.** Extra HTML, `lang="en"`, scanline overlay against FLAT_UI. Route behind auth or delete.
136. **`index.html.erb` `<title>brgen</title>`.** `:17` hardcoded. `t("face.title")` in nb/en.
137. **`en.yml` `hello: "Hello world"`.** Unused scaffold. Delete.
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
380. **Engine locales are one key.** `engines/dating/config/locales/{en,nb}.yml` only `dating.bio: "Bio"`. Move all dating keys into the engine or delete the stub.
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
478. **bsdports FTS tests skipped.** `port_test.rb:137,144` — `ports_fts` not in `schema.rb`. Commit the virtual table to schema or stop calling the feature done in `apps.yml`.
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
491. **WCAG AAA claimed.** `apps.yml` “not a full-site AAA audit”. Don’t claim AAA in README.
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
583. **`DillaRenderJob`.** Must not overwrite takes. Assert output dir `STUDIO/dilla/renders/<seed>/` or brgen equivalent; never `$PWD`.
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
596. **Vertical content column.** Shared `.page-header` / measure cap not applied on vertical homes. Use `.app-shell` column; don’t change accents. (One chrome, already open — this is the container half named per file.)
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
624. **Network table is missing.** `SSH_ACCESS.md` and `RUNBOOK.md` both say the canonical network table is in `README.md`. `README.md` has none. Put one table in `SSH_ACCESS.md` and make the others pointers.
625. **Uptime-check prose is a second URL list.** `RUNBOOK.md` still says the wrapper curls four hardcoded hosts. `bin/uptime-check.sh` now execs `health_check.rb --public-only`. Rewrite the paragraph.
626. **Crontab table is incomplete and stale.** `RUNBOOK.md` lists four jobs; `etc/crontab.vm23` also schedules prune-guests, core-reclaim, keep-warm, drain-jobs, weekly-integrity. The relayd-watchdog row still says it heals `doas.conf` trailing newline; that heal was removed. Expand the table from the tracked crontab.
627. **Production-push scope is wrong.** `RUNBOOK.md` table says `vps_production_push.sh` covers “master + brgen + amber”. The script also deploys bsdports.
628. **httpd 6666 comment vs CLAUDE.** `CLAUDE.md` still says `httpd.conf` listens on `* port 6666`. Live file listens on `127.0.0.1 port 6666`.
629. **MEM_RESTORE numbers drifted.** `CLAUDE.md` “thresholds are now 8/14”. `resource_guard.sh` is MEM_WARN 8 / MEM_RESTORE 10.
630. **keep-warm OPTIONAL set is inverted.** Comment says “bsdports and master are resource_guard's OPTIONAL set”. Guard has `CORE="master brgen"` and `OPTIONAL="bsdports amber"`.
631. **core-reclaim still names litestream in OPTIONAL.** Match `resource_guard.sh`.
632. **Four recipe lists.** `data/operator.yml`, `RECIPES.md`, `START_HERE.md` Golden Commands, `RUNBOOK.md` deploy-all table. Make `operator.yml` the only command list.
633. **RECIPES.md is thirteen lines.** Either fill it from `operator.yml` or delete and point.
634. **Feature inventory stated twice.** `START_HERE.md` “App inventory” and “Feature inventory” both `RAILS/apps.yml`. One line.
635. **DECISIONS vs unsigned zones in git.** “61 zones … none of them in git”. `var/nsd/zones/master/` holds 57 unsigned `*.zone` templates by design. Narrow the decision to signed artifacts / keys.
636. **RUNBOOK still describes a fixed deploy_all header.** Current header says there is no archive. Update RUNBOOK.
637. **deploy_all still logs archive/recovery.** `deploy_all.sh:49`. Delete the log line.
638. **tools/tree.rb still DRIFTs a missing dir.** Prints `archive/recovery` as DRIFT. Drop both.
639. **PATH_OWNERSHIP lists `archive/`.** Directory does not exist. Remove the row.
640. **Retired-apps prose vs extra_zones.** RUNBOOK says foodielicio.us went with baibl; `data/dns.yml` `extra_zones` still serves them. Pick one source.
641. **dns.yml comment vs ALL_DOMAINS.** “five zones not in ALL_DOMAINS (anti-gambling trio, bsdports.net, foodielicio.us)”. `bsdports.net` has no zone. Rewrite from `city_zones` + `extra_zones`.
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
658. **dns_zones NAMESERVER is a literal.** `gates/dns_zones.rb` `"46.23.89.226"`. `data/dns.yml` already has `nameserver.ip`.
659. **OPERATOR PUBLIC_RESOLVERS includes 8.8.8.8.** `dns_zones.rb` uses `1.1.1.1 9.9.9.9`. One list in `data/dns.yml`.
660. **BRGEN_IP / HYP_IP restated.** Scripts should read `dns.yml` (or a tiny `data/host.yml`).
661. **relayd-watchdog BACKENDS table hardcoded four ports.** Add this file to `SMOKE_SCRIPTS` / `FLEET_INVENTORIES`.
662. **vps-state APPS hardcoded.** `%w[brgen amber bsdports]`. Read apps.yml and master_face.
663. **vps_ci_all apps hardcoded.** Same.
664. **start_all_apps SERVICES hardcoded.** Derive from inventory + master.
665. **keep-warm TARGETS hardcoded.** Read apps.yml in ksh the way uptime-check does.
666. **usr/local/bin/uptime-check FALLBACK list.** If apps.yml is unreadable, fail; do not quietly check a 2026-08 fleet.

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
713. **check-openbsd zsh -n covers two files.** Add `vps-deploy`, `vps_ci.sh`, `deploy_all.sh`; `ksh -n` for `resource_guard.sh`.
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
747. **render_dns.rb extra_hosts key is unused in dns.yml.** Document extra_hosts or remove the dig.
748. **DMARC assert in `--check`.** Do not also emit `_dmarc` in zone_body for mail_domain.
749. **domain_inventory.yml `state: unknown` never alarms.** Fail or skip-with-count so “32 unknown” is visible.
750. **Nominet dates in inventory are already past.** Add `domain_watch --update` recipe in operator.yml.
751. **ALL_DOMAINS is a shell array parsed by regex in three Ruby files.** Move the city list to `data/dns.yml` `city_zones:` and have OPERATOR.sh read it with `ruby34 -ryaml`.
752. **No test for bin/vps-deploy.** At least: refuse uid 0; `all` expands to the four names; `SKIP_CI=1` path names `${app}.sh`.
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
769. **health_check load_apps rescue returns standalone only.** If apps.yml is unreadable it warns and returns empty. Fail closed.
770. **health_check `--core` still requires smtpd.** Document as required.
771. **resource_guard ALL_APPS_FLAG vs start_all_apps.** Name the flag in PATH_OWNERSHIP.
772. **emergency_cpu not under usr/local/bin in the repo.** Two layouts (root vs usr/local) for installed scripts. Same for `resource_guard.sh`, `config_drift_gate.rb`, `vps_weekly_integrity.sh`.
773. **Crisis tier on the box is missing the binary.** Confirm `explicitly_installed` scan matches `install -m 755 … emergency_cpu`. **Unverified scan.** If the install line does not match the regex, fix the regex, not the box.
774. **etc/litestream.yml header still reads as a how-to.** First lines should be: inert by decision; not in ports; do not enable; dr-pull is the backup. Keep the yaml body.
775. **OPERATOR `setup_litestream`.** Add `rcctl ls failed` must not contain litestream as a check in health_check.
776. **restore_backups.sh is a litestream restore that must fail.** Rename to `restore_litestream.sh` so nobody runs it as DR, and print `use bin/dr-pull` on the first line of usage.
777. **port_inventory RETIRED_CONFIG_PATHS includes litestream.yml.** Add a positive test: litestream.yml may exist, must not appear in pkg_scripts.
778. **vps-deploy drift gate is advisory.** Add `VPS_DEPLOY_DRIFT=fail` opt-in. Do not flip to blocking from here (box is dirty).
779. **vps-deploy `DEPLOY_ALL` vs apps.yml.** Derive Rails names from yaml; keep master first and optional last as comments + a test.
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
799. **lib/utf8.rb is installed next to config_drift_gate.rb.** Awkward `/usr/local/bin/lib/utf8.rb`. Vendor the require as a relative file documented in the gate header.
800. **bin/ds-records requires root to read signed zones.** Off-box it should skip, not traceback. Guard ZONE_DIR readability.
801. **bin/render_dns.rb add `--help`.**
802. **OPERATOR.sh pin `RUN_PRODUCTION_SEEDS` default 0 in the header.**
803. **data/operator.yml `ssh brgen` vs IP.** Use the Host alias everywhere instead of the IP.
804. **Three doors.** START_HERE should say “agents: CLAUDE.md; operators: RUNBOOK.md; first screen: README.md” in one sentence.
805. **RUNBOOK “Always use tmux” then `doas zsh OPENBSD/OPERATOR.sh`.** vps-deploy must *not* be doas. Put that adjacent.
806. **config_drift_gate SSH default `dev@brgen.no`.** Other scripts default to the IP. One default (`SSH_HOST` from operator.yml).
807. **deploy_all still says `rails/<app>/<app>.sh` in usage.** Path is `RAILS/<app>/<app>.sh`.
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
826. **`FLYLO_` alias warn vs help.** Help still has `flylo_abstract`, `flylo_fm_shimmer` in `redo_nine.sh:39`. Present-tense: those are pocket/lead names, not the banned prefix.
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
839. **`AudioGraph` comment vs tests.** Still cite `lib/engine/render_dilla.rb:640-695`. Point at `engine part: render_dilla`.
840. **Industrial graph is a second spine.** Name in `help` that `industrial`/`techno`/`analog` still bypass `AudioGraph`. Do not merge renderers.
841. **`characterize` is 1180 lines of inspection.** Add one line under “READING THE ENGINE.”
842. **`vocab-check` in `STUDIO/dilla/README.md` Checks.** That README currently only names `rake test`.
843. **`dilla.rb` header: tests and the gate depend on the CLI guard.** Stops the next split from dropping it.
844. **`dilla_live.rb` is a second entry.** Either add `entry:` (guarded) or document it as parse-only like lora.
845. **`playlist_learn_agent.sh` is bash.** `#!/usr/bin/env bash`. Law is zsh. `#!/bin/zsh` plus `set -euo pipefail`.
846. **`librosa_analyze.py` is committed Python.** Ban is on committed scripts. Isolate as an optional tool with a Ruby wrapper that says “Python on PATH, not in this repo’s agent shell.” Paths point at `pub2` / `pub3`. **Unverified** whether `radio-bergen-librosa` is still dispatched.
847. **`generate_tts.rb` assumes repo-root cwd.** Anchor to `File.expand_path("../../../MASTER/README.md", __dir__)`. Backticks for TTS belong behind Open3. Vendor path is `3.4.0` not `3.4.9`.
848. **`redo_nine.sh` points at missing chops.** `samples/chopped/ubrukte_samples_0N/loop.wav`. Refuse with “no chopped rack” rather than render empty beds. Do not retune the rows.
849. **`ENV_AND_RENDER.md` names `RAILS/shared/app/services/shared/dilla_processor.rb`.** **Unverified** that path still exists.
850. **`data/modes.yml` never mentioned in help.** One line under SYNTHESIS.
851. **`data/album_tracks.yml` / `dilla_principles.yml`.** Find the reader before calling them inert.
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
889. **`--video` exists; PHOTOGRAPHY.md says stills only.** Update PHOTOGRAPHY: video path exists, frame-by-frame, grain hold vs moving.
890. **README “Running it” omits `--rescue`, `--video`, `--measure`, `--compare`, `--watch`.**
891. **In-place grade from repligen.** `repligen.rb:760` `--input` and `--output` are the same path. Write a sibling and leave the download (REVERSIBILITY).
892. **`postpro.log` is a committed logger stub.** Gitignore `*.log` under postpro, or stop opening a logfile next to source.
893. **`CONFIG` from missing `master.json`.** Help should say “built-in tables only”.
894. **Camera profiles: 6 JSON files, README says 121 bodies.** Say “six vendor files, 121 bodies.”
895. **Golden tests cover four presets of 57.** Do not hash looks. Add one more family only if a preset class has no representative. **Unverified** whether `house` is in those four.
896. **`motion.rb` `--explain` cost print.** Surface it as `postpro --video FILE --explain` (no grade).
897. **`rake test:motion` should print the skip count.** Rakefile does not.
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
925. **`contact_sheet.jpg` in `ragnhild/`.** If generated, gitignore and document the command.
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
958. **`which ffmpeg`.** Use `Open3` + `ffmpeg -version` like `motion.rb`. OpenBSD `which` differs.
959. **`test_dilla_crate_dig.rb` does not open on-disk sidecars.** One test: every readable `samples/**/*.provenance.json` has a `url` or is listed as pre-URL-schema. Worktree without samples skips.
960. **`STUDIO/README.md` has lists, tables, and a code block.** README_PROSE. Redo; move commands into sentences. Same for `dilla/README.md`, `postpro/README.md`, `repligen/README.md`, `lora/README.md`.
961. **`PHOTOGRAPHY.md` “3,947 lines and 228 rules”.** **Unverified** now. Point at `ruby MASTER/tools/agent_context.rb` or drop the census.
962. **`PHOTOGRAPHY.md` “Nothing applies it by default.”** False: `repligen.rb` `HOUSE_POSTPRO`. Update layer “Two things that are not true yet.”
963. **`PHOTOGRAPHY.md` “postpro is stills only.”** False: `motion.rb`.
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
1026. **Shebang families.** OPENBSD mixes `env zsh`, `bin/sh`, `bin/ksh`, `env sh`. STUDIO has bash (`playlist_learn_agent.sh`). A census test: every committed script’s shebang is one of `{zsh, ksh, sh, ruby}` and `[[` only appears under zsh/ksh.
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
1059. **`operator.yml` vs RUNBOOK vs CLAUDE vs START_HERE vs RECIPES.** Five operator doors. `operator.yml` is the command list; CLAUDE is the gotchas; RUNBOOK is the box; START_HERE is the first screen; RECIPES points. Delete the copies.
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

1. **`visual_bridge.js` listens for `rule_loop:(cycle|clean|converged)`.** `:158`. The bus publishes `rule_loop:pass` / `rule_loop:fix_applied` / `rule_loop:error` (`rule_loop.rb:110,186`). `master:rule_event` never fires. Same family as `swallow:error` vs `error:swallowed`. Align the regex with the producer.
2. **Same file `phantom:retry` (`:197`).** Producer is `phantom:recovery` / `phantom:occurrence` / `phantom:halt` (`unwrap_error.rb`). Flinch never runs on a real retry.
3. **Same file `pipeline:start` (`:26`).** Producer is `pipeline:stage_start` / `pipeline:complete`. Thinking tint never keys off a real stage start.
4. **`council:vote|speech|end` (`visual_bridge.js:200`) vs bus `council:start|pass|veto`.** The rotator never stops from the bus. `council:speech` is an SSE name on the chat stream, not a bus topic.
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
56. **`.legal-prose` is defined in `_site_legal_footer.html.erb` as an inline `<style>`.** `:18-28`. Second type system: `max-width:64ch` not `var(--measure)`; h1 `line-height:1.15` off `[1, 1.25, 1.4, 1.5, 1.6]`; body `line-height:1.62` off scale; `ul{padding-left:1.1rem}` physical, markers inside the measure; padding `32px 20px 64px`; h1 margin `6px` off the 8px grid; footer `font-size:13px` / `12px`. **Move:** delete the `<style>`; put legal on `_typography.scss` tokens. Values of colour stay; the seam is the file.
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
85. **`section h2` in `_shell_widgets.scss` is `--text-xs` + uppercase + mono.** `_typography.scss` already had to restore family on `main > section > h2`. Keep the widget rule scoped (`.sidebar section h2`), never `section h2`.
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
97. **`--weight-heavy` (800) is synthesised on Caprasimo and JetBrains Mono.** Comment in `design_tokens.yml` already says so. Heavy belongs on `system-ui` headings only; editorial faces stay 400/700.
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
118. **`@media (max-width)` bands marked `scan: intentional` are not a conversion pass.** Leave. New work uses `min-width` from `design_tokens.yml#viewport`.
119. **`--text-display` 2.2rem and canvas `clamp(2.5rem, 12vw, 5rem)` on splash h2.** Display type without a sanctioned home was why `--text-display` was added. Splash still bypasses it. One display slot.
120. **`font-size: 13px` in `.site-legal`.** Below 16. Footer meta; name it `--text-xs` so it scales with the root instead of painting 13px on bsdports’ 12px root (13px there is *larger* than body). Absolute px meta on a 12px root is the defect `design_tokens.yml` scale comment already names.

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
132. **Rams “as little design as possible.”** Two complete type systems (shared `_typography.scss` vs legal/mailer `<style>`) is the opposite. Delete the second; do not add a third.
133. **Ando / ma.** `--leading-loose` 1.6 is already the quote step. Legal 1.62 and mailer 1.55 invent a half-step of air that reads as unsettled next to 1.5 body (ScaleLint’s own diagnosis). Snap to 1.5 or 1.6.
134. **Bringhurst on all-caps: letterspace.** Kickers that are `text-transform: uppercase` without tracking, or with tracking off the token ladder, are the defect. Shared widget `section h2` already tracks wide — and that rule leaked onto vertical section titles, which is why tv/marketplace read as a different product until `_typography.scss` restored the family. Keep that fence.
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
47. **Importing a book as unread YAML.** `dilla_principles.yml` is the cautionary example (draft, parallel to the tests). If a new file is added, it needs a reader the same day — `test_dilla_groove_timing` or ScaleLint — or it is inert law.

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

1. **`cable_bridge.rb` subscribes `"*"` and broadcasts every bus event on `master:events`.** `MASTER/web/config/initializers/cable_bridge.rb:18-25`. Visitor-safe prefixes exist on `EventsController`; Cable has none. A logged-in face tab receives `council:veto`, tool paths, `fix_loop:*`. Filter with the same allow-list as SSE, or don’t subscribe `*`.
2. **That thread `rescue StandardError` to `Rails.logger.debug`.** A failed broadcast is silent in production (`debug`). `warn` or Swallow.log.
3. **`MASTER_CABLE_BRIDGE_STARTED` is a constant flipped in `after_initialize`.** Reload in development can warn or skip a second boot. A module ivar, not a constant.
4. **`TtsJob.spawn_worker` `report_on_exception = false`.** `tts_job.rb:86`. A worker death is invisible; the pool `reject!(&:alive?)` only notices on the next spawn. Log the exception before the loop, or leave report on.
5. **`ai_boot.rb` `Thread.new { wl.run }` and `watcher.run_forever` with `abort_on_exception = false`.** Same: a dead WatchLoop looks like a hang. `abort_on_exception = true` in non-test, or join+restart with a log.
6. **`bus.subscribe("fix_loop:clean") { Thread.new { propose_tree.call } }`.** Every clean/plateau starts an unbounded thread. If FixLoop fires often, this is a thread leak. One worker, or `Thread.new` only if the previous finished.
7. **`OutputFilter` compresses git/ls/tree and long line-counts.** JSON from WebSearch / scan / GitContext can still dump. Route those `Result.ok` bodies through `filter` (agent-harness item 4). Brittle: `GIT_STATUS_RE` is a regex on the whole blob.
8. **`YAML.load_file` in `RAILS/gates/release.rb:37` and `OPENBSD/verify_deploy_identity.rb:16`.** Ruby 3.4 `Psych.load_file` still permits aliases; not `safe_load_file`. These files are ours, but the habit is the bug. `YAML.safe_load_file`.
9. **`World#write_atomic` rescue deletes tmp then re-raises.** Good. `File.delete(tmp)` if rename succeeded on a sibling crash? Only in rescue. Fine. The pitfall: if `abs` is on another device, `File.rename` raises EXDEV and the write never lands. Document, or copy+rename.

### RAILS

10. **`SecurityAdvisoryRefreshJob` sleeps 6s between ports, 50 ports → ~5 min on the bulk worker.** `bsdports/app/jobs/security_advisory_refresh_job.rb:8-19`. On a 1 GB box that is the whole queue. Drop the sleep; NVD is rate-limited in `NvdCve` or with `limits_concurrency`. `rescue StandardError` per port is fine; the sleep is the bottleneck.
11. **When the cursor is past the last id, the job wraps to `Port.order(:id).limit(50)` forever.** Same file `:14`. Intended recycle, but it never idles. After a wrap, write cursor and `return` if the first id is ≤ the previous cursor.
12. **Package index follows redirects with `URI.join` to any host.** `package_index_fetcher.rb:79`. If `mirror_url` or `Location` is `http://169.254.169.254/`, that’s SSRF. Allow-list host to the mirror’s host (and ftp.openbsd.org). Same shape as `OutboundHttp`.
13. **`Hashtag.find_or_create_by!(name:)` under a unique index.** `taggable.rb:20`. Concurrent posts with the same tag raise `RecordNotUnique` and fail the `after_save`. Rescue and `find_by!`.
14. **`Vote#apply_score_delta` uses `saved_change_to_value`.** Create: `[nil, 1]`, `nil.to_i` is 0, delta 1 — OK. `after_save` on a touch with no value change: `saved_change_to_value` is nil, `before, after = nil` → `nil.to_i` 0. OK. `after_destroy` uses `value` after destroy — still in memory. OK. Pitfall: `update_all` skips `updated_at` on the votable; WIRING_NOTES trap. Add `updated_at = ?` or leave if score is the only reader.
15. **`usage_count` on hashtags is nullable.** `schema.rb:570`. `increment!` on nil raises. Default 0, NOT NULL (same family as listing `views_count`).
16. **`Takeaway::Restaurant#update_columns(rating: avg&.round(1) || 0)`.** Average of integers rounded to 1 decimal is Fine; `round(1)` on a float is not money. Don’t store money this way. Rating is OK. Inconsistency: other counters use `increment!`.
17. **Release gate `sleep 1` in a retry loop.** `gates/release.rb:99`. Fine for a laptop gate; don’t copy into a job.
18. **`Date.today` in app code vs `Time.zone`.** Dating `ranked_for` seeds `Date.current` — good. Grep remaining `Date.today` in `app/` (not gates). UTC-vs-Oslo can shift daily picks at 00:00–02:00.
19. **`amber` `config.generators.system_tests`.** brgen and bsdports set `nil`. If amber still generates system tests, the 8.1 policy is inconsistent.

### STUDIO / OPENBSD

20. **`MixScore.band` interpolates `path` into backticks.** `mix_score.rb:43`. `verify_fx.rb:83` interpolates `path` and `af`. `dilla.rb:15011` ffprobe the same. `live/rack.rb:182` uses `shellescape`. One helper: `Open3.capture2e("ffmpeg", "-i", path, ...)` with a timeout. A crate path with `"` is a command.
21. **No timeout on those ffmpeg backticks.** A hung decode blocks `rake test` / characterize forever. `Open3` + `Timeout` or ffmpeg `-t`.
22. **`measure` `.to_f` on a missed regex is `0.0`.** A failed ffmpeg looks like silence. Raise or return `nil` if the match is missing.
23. **`OPERATOR.sh` `sleep 10` / `sleep 5` in loops.** Fine for boot. Pitfall: `set -e` with sleep is OK; an unquoted `$delay` is not if delay is empty. Quote `"$delay"`.
24. **lora `YAML.load_file` in `render_config.rb` / `shoots.rb`.** Same as 8. Toolkit YAML is local; still `safe_load_file`.

### Smells that are pitfalls, not style

25. **FixLoop background + propose_tree threads + WatchLoop + cable_bridge + TTS workers.** Five unsupervised thread families in one Falcon process. A leak in one starves TTS. Bound them (`HostBudget`) or don’t start propose_tree from the web process.
26. **`SecurityAdvisoryRefreshJob` + `sleep` + no uniqueness** (uniqueness was inventory). Together: two jobs, ten minutes of sleeps, NVD bans the IP. Continuations (Rails 8.1 list) + no sleep.
27. **Redirect-follow without host pin** is the same class as DynamicHttp+SSRFGuard. One allow-list helper for all `Net::HTTP` in RAILS (`CrawlSupport.fetch` already exists per `file_length_ratchet_test` comment). Point the package index at it.

### OPENBSD — locks, env, false greens

28. **`.deploying-*` does not cover the window `resource_guard.sh` describes.** App `rc_pre` touches the flag, `pkill`, `sleep 1`, then `rm`. The 300s `/up` wait is after `rc_cmd`. Guard comment says the lock lasts through precompile, migrate, cold boot. A 5-minute tick can shed during the boot the lock was meant to protect.
29. **master’s lock is the same hole, shifted.** `etc/rc.d/master` touches `.deploying` after `bundle34 install` and removes it at the end of `rc_pre` *before* the `/up` wait. Bundle and Falcon bind are uncovered.
30. **`*_jobs` drop the app’s `set -a`.** `rc.d/brgen` exports the whole env file. `brgen_jobs` / `amber_jobs` / `bsdports_jobs` `. /etc/<app>.env && export RAILS_ENV SECRET_KEY_BASE HOME …` without `set -a`. VAPID, SMTP, and the rest of the file never reach Solid Queue. Push and mail from jobs fail closed-looking.
31. **Two `PUB4_CI_LOCK` policies.** `lib/ci_lock.sh` only honours an override under `/var/db/pub4/`. `bin/with-ci-lock` honours any non-world-writable directory. Two mutexes.
32. **`pub4_ensure_ci_lock` deletes `.holder` while a holder may own the flock.** Attribution races; running CI looks unheld.
33. **`nsd-resign` reports health when it signed nothing.** Empty keys or empty zone dir → “all zones valid — nothing to do.” Pass on empty.
34. **`bin/smoke-apps.sh` cannot fail master.** Master not listening is `skip`. A dead face plus live brgen exits 0.
35. **`test_tracked_crontab.rb` never sees the uptime-check line.** `scheduled_commands` takes `line.split[5]` and keeps only paths starting `/`. Crontab `ALLOW_BSDPORTS_DOWN=1 /usr/local/bin/uptime-check.sh` — field 5 is the env assignment. The test would still pass if that wrapper vanished.
36. **`drain-jobs.sh` turns a dead sqlite into “nothing due.”** Unreadable db → 0; `solid_queue_proof.rb` treats “nothing due” as proof the drain ran. A broken queue file keeps deploys green.
37. **`drain-jobs.sh` uses `cut`.** Banned. Ruby or zsh split.
38. **`core-reclaim.sh` RSS is `ps | grep | grep -v | head -1 | awk`.** Wrong pid; ceiling never fires. `head`/`awk` banned.
39. **`emergency_cpu.sh` uses `head`.** Crisis path on OpenBSD `head`.
40. **Weekly integrity lock is a no-op if `fuser` is absent.** `if [ -f "$LOCK" ] && fuser "$LOCK"` — missing fuser makes the condition false; the script proceeds and races CI.
41. **`start_all_apps.sh` restarts relayd after a fixed 5s.** Amber rc.d waits up to 300s for `/up`. Relayd can reload onto empty backends.
42. **`etc/rc.d/master` digest is unquoted.** `cksum $_face_assets …` word-splits. Empty list plus glob stamps a digest that is not the asset set.
43. **`bin/vps-state` swallows a corrupt deploy stamp.** `JSON.parse` rescue nil → “never deployed.”
44. **`resource_guard.sh` memory path fail-opens to 100%.** If top and vmstat fail, memory-only pressure never sheds.
45. **`smtpd.conf` listens on `vio0`.** Interface rename and inbound 25 dies.
46. **Hardcoded `/home/dev/pub4` in `start_all_apps.sh` and rc.d.** `PUB4_ROOT` / a worktree is ignored.
47. **`dr-pull --check` exits 0 when `~/pub4-dr` is missing.** The local gate that should notice a stale backup is a skip on a Mac that never created the dir.
48. **`amber_queue_sweep.sh` has no `QUEUE_DB` existence check.** `sqlite3` on a missing path creates an empty file, then SQL against missing tables dies — or plants an empty `production_queue.sqlite3`.

### STUDIO — ffmpeg 0.0, scratch races, silent session

49. **Album master is the same backtick hole as MixScore, with gain.** `dilla.rb:34535–34541`. Failed ffmpeg → `I=0` → `gain = target - 0` applies ~19 dB of make-up. Don’t ship that take. Open3 + status + abort.
50. **`audio_duration_sec` discards status, rescue `0.0`.** `build_harmony_loud` then `[dur, 8.0].max` — a failed probe mixes **8 seconds** of a longer stem.
51. **Scratch names are not pid-scoped.** `harmony_loud.wav`, `live_tmp.wav`, `dilla_drums.wav` … Two `dilla` processes (or `PARALLEL=3`) write the same files. Pid-scoped temps exist at `:5735` and are unused here.
52. **Scratch fallback is per-uid, not per-process.** `Dir.tmpdir/dilla-scratch-#{uid}`. CI user plus a second render still collide.
53. **`CompositionEngine.load!` silent `rescue StandardError`.** Truncated `session.json` becomes a brand-new session with no warn. Jam looks like it loaded last night’s work.
54. **`crate_dig` / `VocalChop.loops` / `Acapella.index` JSON parse with no rescue.** Corrupt index is a backtrace on the vocal path. Refuse with the path.
55. **`kaggle_session.rb` `JSON.parse` at load.** Missing file raises on `require`, not on `run`. `ruby -c` never sees it.
56. **postpro comment-strip `gsub(/^.*\/\/.*$/, "")` kills JSON lines that contain `//`, including URLs in strings.**
57. **Playlist/learn JSON loaders `rescue StandardError` → empty.** Corrupt catalog looks like a first run; the next save overwrites it.
58. **`sine_stream.rb` mutates ENV at load.** `ENV["WONKY_TOP_DIRT"] ||= …`. A require from a test leaks knobs.
59. **Two `capture` APIs.** Engine `capture` → `[stdout, stderr, status]`; `RadioChop.capture` → a string. Copy-paste of `.first` across the boundary is a type error.
60. **`mix-score` never calls `tool_available?("ffmpeg")`.** Engine mix metrics do.
61. **`STREAM_ITERATE_LOG` is one shared path, no flock.** Concurrent streams interleave lines.
62. **`bin/crate` ROOT is `…/dilla/crate`.** That directory is gone. `list`/`fetch` write a third layout the engine never reads.
63. **`isolation.rb` loads every `test_dilla_*.rb` in one `-e` process.** session.json mtime races and ENV pins leak by construction. `rake test:dilla` still runs that way.
64. **`EnvSandbox` restores ENV, not constants.** Engine constants computed from ENV at load (`ONLY`/`EXCLUDE` in acapella) stay at first-process values.
65. **Album encode `Open3.capture2e` ignores status, then `rm`s the staged file** and prints loudness from the missing dest (0.0 again).

Highest cost if wrong: 28–30 (deploy lock + jobs env), 36 (drain false-green), 49–53 (ffmpeg 0.0, scratch, silent session).

### MASTER — writes, taint, request path

66. **`AstEdit` calls `atomic_write`; the helper is `write_atomic`.** `lib/io/ast_edit.rb:69,91`. Every write is `NoMethodError` caught as `Result.err`. The dangerous tool cannot edit. Rename the call.
67. **PathGuard is prefix-only; World realpath-walks ancestors.** ReadFile/WriteFile use PathGuard. A symlink inside the root reaches `/etc`. Put World’s ancestor-realpath check in PathGuard.
68. **`SearchFiles` `Dir.glob(File.join(@root, glob))`.** `File.join(root, "/etc/passwd")` is `/etc/passwd`. Reject absolute globs; PathGuard every hit.
69. **`GitContext#show` takes `path` as a git ref.** `HEAD:.master/config.yml` dumps the web token. Blame/diff use `safe_path`; show does not. Never `rev:path`.
70. **`ReadFile` `File.readlines` the whole file then slices.** A 200k-line file becomes prompt. Sacred paths block writes, not reads — `.master/config.yml` is ingestible. Line-range IO; refuse secret paths on read.
71. **TTS `job_id` is SHA256(voice|text)[0,32].** `readable_job` skips ownership when ready. Anyone who can guess the utterance fetches the mp3; identical lines cross conversations. Random id; always `owned?`.
72. **`GET /chat/tts` and `GET /chat/enhance` have side effects.** Prefetch and query logs trigger paid work. Enhance is not in `AUTHENTICATED_ACTIONS`. POST only; auth enhance.
73. **`require_same_origin!` allows missing Origin when `Sec-Fetch-Site` is not `cross-site`.** curl CSRF from a sibling host with no fetch metadata passes. Command already skips CSRF. Require Origin or `same-origin`.
74. **`GET /chat/skills`, `GET /chat/research`, `POST /chat/photo` are visitor-reachable.** Research is outbound HTTP; photo is 12MB + postpro. Authenticate or quota.
75. **`GET /ingress/health` lists cron/webhook names unauthenticated.** Public health stays `{ok:true}`; names behind the token.
76. **`production.rb` `host_authorization = { exclude: ->(_) { true } }`.** Any `Host:` is accepted behind relayd. Allow the real hosts only.
77. **`DynamicHttp` interpolates `{param}` into URL/body with no escape.** Query injection; SsrfGuard sees the URI after interpolate. Escape by slot.
78. **MCP SSE `cfg["url"]` has no SsrfGuard.** Writable `mcp_servers.yml` becomes an internal-network client.
79. **`pairing.rb` `allowlist_path` `File.expand_path` can leave the tree.** Force under `.master/pairing/`.
80. **`ensure_brain_files!` writes `data/IDENTITY.md` if missing**, bypassing sacred `data/`. Write under `.master/` or don’t create constitution files at runtime.
81. **`Timeout.timeout` around `Net::HTTP` / UNIXSocket / Ferrum.** World already measured Timeout does not kill the child. Hung POST holds a Falcon worker. Use `read_timeout` / `IO.select` / Ferrum’s timeout; `quit` in ensure.
82. **SSE loop `sleep 0.1` for up to 600s, `subscribe("*")` unbounded Queue.** Two Falcon workers plus chat SSE starve the 1 GB box. `Queue.pop(timeout:)`; cap; `HostBudget`.
83. **`/health` SHA256s `Gemfile.lock` every poll** to memoise selftest. Relayd hits this. Hash on mtime+size change only.
84. **Hard compact sends all `session.messages` into `agent.ask`.** That’s the window that overflowed. Summarise a tail.
85. **`SqliteStore` WAL failure falls back to `:memory:`.** Pairing/memory vanish on restart; process looks healthy. Fail closed for durable stores.
86. **Three atomic writes; only `Io::AtomicWrite` fsyncs.** World/Live can leave a 0-byte file after rename of an unflushed tmp. One helper.
87. **`FileProcessor` lock is `CREAT|EXCL` then delete; `remove_stale_lock` is mtime then delete (TOCTOU).** A crash holds the scan 300s. `flock` on a stable lockfile.
88. **`mode_posture#set!` writes `.master/mode` and sets `ENV["MASTER_MODE"]` process-wide.** One Falcon worker’s `/mode` changes every request on that process. Don’t mutate ENV.
89. **`pairing#revoke` skips `with_store_lock`.** Redeem vs revoke can resurrect a deleted token.
90. **`context_window` soft compact `Thread.new { compact! }` which `session.clear!` while a turn may still append.** Compact under the session mutex.

### RAILS — strict load, mass assignment, uniqueness, GET writes

91. **Listing show `reviewable_by?` hits `orders.where` after `increment!`.** `restrict_with_error` is still strict. Signed-in show 500s. Include `:orders` or query `Marketplace::Order.where(listing_id:)`.
92. **TV feed preloads `video_file` not thumbnail.** `_item.html.erb` `video.thumbnail.attached?` → strict 500. `includes(thumbnail_attachment: :blob)`.
93. **Users#show posts without `with_attached_image`.** Profile cards 500 or N+1. Mirror HomeController preloads.
94. **Inbox `includes(:participants, :messages)` loads every message in every thread.** Drop `:messages`; unread already has `unread_counts_for`.
95. **Listing params permit `:status` and `:kind`.** Seller POSTs `status=sold` or flips kind without details. Drop `:status`; lock `:kind` on update.
96. **Stores permit `:stripe_connect_id`.** Owner points payouts at another Connect account. Server-only OAuth write.
97. **Partner programs permit `:status`.** Owner opens a draft with no review. `open!` / `pause!` only.
98. **Takeaway restaurants permit `:active`.** Hidden field unpublishes the kitchen. Dedicated action.
99. **Playlist like uniqueness includes nullable `set_id`/`playlist_id`.** SQLite unique treats NULL as distinct — two likes on the same playlist both insert. Partial unique indexes.
100. **Dating match unique is initiator+receiver only.** A→B and B→A are two rows (comment admits it). Unique on `LEAST/GREATEST`.
101. **Mention uniqueness has no unique index.** Race on edit double-notifies.
102. **Affiliate conversion `transaction_id` allow_nil unique.** Duplicate paid postbacks. Reject blank ids.
103. **Vote `after_save` `update_all` score.** A rolled-back vote still moved `posts.score`. `after_commit`.
104. **Dating like `after_create :check_mutual_match` inside the transaction.** Rollback can leave a Match. `after_create_commit`.
105. **GET nearby `#room`/`#widget` `join!` + `ensure_guest_user!`.** Crawlers mint users. POST join, or join when a message is sent.
106. **GET stories show `view_by!`.** Prefetch inflates counts. Beacon/POST.
107. **GET ports/places/amber items `record_activity!`.** Activity table grows with every crawl. Skip bots.
108. **Daily picks: two tabs both `create!`, rescue unique, return `chosen` not the rows that won.** Page shows five faces the DB does not have. Reload `existing`.
109. **Amber `MoneyInOre` `cents / 100.0` is Float.** Outfit totals drift. `BigDecimal`.
110. **Amber `planned_outfit` `this_week` uses `Date.today..7.days.from_now`.** Date vs Time, UTC vs Oslo. `Time.zone.today`.
111. **TV `comments_count` / `likes_count` have no writer.** Rank/UI that reads them is 0. `counter_cache` + default 0, or drop the columns.
112. **Ports importer upserts one-by-one, no transaction.** Nightly vs web → `BusyException`. Wrap in `Port.transaction`. `ApplicationJob` does not `retry_on SQLite3::BusyException`.
113. **PWA share skips CSRF on posts#share and amber items#share.** Require Origin allowlist or a share nonce.
114. **Playlist sets unknown privacy string is treated as public.** Typo in DB leaks private sets. Default deny.
115. **Comments#create with neither event_id nor post_id → `@commentable` nil → 500.** `head :not_found`.

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
12. **`lib/deploy/` → `lib/operator/deploy_docs.rb`.** The name collides with `OPENBSD/`.
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
23. **`mask.js` and the three mask_* files.** Dead; delete with the tests that grep them.
24. **Cable vs SSE vs `visual_bridge`.** Three event pipes. Cable broadcasts `*`. One pipe for the face; Cable goes or takes the visitor allow-list.

### OPENBSD

25. **`operator.yml` is the command list.** RUNBOOK, CLAUDE, START_HERE, RECIPES currently copy it. Pointers, not tables. RECIPES is thirteen lines — fill from yaml or delete.
26. **One deploy verb.** `bin/vps-deploy` is canonical. `vps_deploy_master.sh` calls it. `vps_production_push` is `SKIP_CI=1 vps-deploy all`. `deploy_all.sh` dies or becomes a wrapper.
27. **One uptime checker.** `bin/uptime-check.sh` execs `health_check.rb --public-only`. `usr/local/bin/uptime-check.sh` is the install target of the same file, or a one-line exec. One list of hosts from `deploy_inventory.json`.
28. **One “on box” bootstrap.** `vps_install_all` vs `vps_on_vm_install`. Fold; delete the `git stash`.
29. **`check` calls `check-openbsd` for the identity/smoke overlap**, or START_HERE draws the Venn. Contributors must not need both by folklore.
30. **rc.d apps from one tmpl.** `rails-app.tmpl` disagrees with brgen (PATH, pexp, timeout). Generate amber/bsdports from the live brgen script, or delete the tmpl so OPERATOR cannot install the wrong one.
31. **Jobs rc.d `set -a` like the app.** Same env file, same export. Three footers → one `jobs.footer` with APP filled in.
32. **`ALL_DOMAINS` lives in `data/dns.yml`.** OPERATOR.sh, Ruby gates, and health_check parse a shell array today. One yaml; shell reads it with `ruby34 -ryaml`.
33. **`SMOKE_SCRIPTS` / `FLEET_INVENTORIES` include `relayd-watchdog`.** Hardcoded backend tables elsewhere die.
34. **`dotfiles/` declared Mac-only, check none**, or it leaves the OpenBSD tree.
35. **`restore_backups.sh` → `restore_litestream.sh`.** First line of usage: `use bin/dr-pull`. Name is the architecture.

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
46. **Legal/mailer `<style>` die.** `_typography.scss` is the type system. `.legal-prose` aliases `.prose`.
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
57. **`dilla_principles.yml` is loaded by `groove_engine` or deleted.** Draft YAML with no reader is a second constitution.
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

Unmeasured. Research-derived; not a claim the engine should imitate an artist.
Already open: unread `dilla_principles.yml`, dual LUFS windows, MixScore 0.0 on
ffmpeg fail, per-role swing vs global `SWING`, provenance pins, ENV census.
Fenced: shipping copyrighted reference audio, golden WAV that overwrites a take,
changing a rendered-sound default, “sounds more Dilla” as a gate, vinyl-as-effect.
Objective render/analysis condition before complete. A finding is a hypothesis.

### Source and arrangement

1. Add a `SOURCE_FIRST` quality gate proving that tonal/frequency overlap is resolved at instrument/sample selection before corrective EQ.
2. Add a kick/bass separation metric based on fundamental-frequency overlap, not merely low-frequency RMS.
3. Add a test fixture where two different kick/bass timbres with identical EQ curves demonstrate why source choice matters more than corrective EQ.
4. Add `ARRANGEMENT_SONIC_DENSITY` measurement for simultaneous occupied frequency regions.
5. Add a metric for redundant spectral occupation between harmonic layers.
6. Add a “great mix is a great arrangement” diagnostic that reports conflicts before mix processing.
7. Add a per-layer `frequency_role` classification: sub, low, low-mid, mid, presence, air.
8. Make layer-role conflicts visible in render diagnostics rather than silently corrected.
9. Add a `TIMBRAL_FIT` score measuring whether a sound naturally occupies its assigned register.
10. Add a regression proving that deleting corrective EQ does not materially degrade a deliberately well-arranged reference.
11. Add a “minimal processing wins” comparison between source selection and post-EQ correction.
12. Add an arrangement-density ceiling before bus processing begins.
### Dilla timing

13. Add a timing-analysis report separating grid deviation, swing, voice-specific offset and phrase-level drift.
14. Add `MICROTIMING_PROFILE` fixtures for kick, snare, hat, ghost and percussion independently.
15. Measure timing distributions rather than only average offsets.
16. Add a `TIMING_ENTROPY` metric so perfectly repetitive offsets are distinguished from genuinely varied microtiming.
17. Add a test proving that global swing and independent voice displacement are not interchangeable.
18. Add a test proving that moving the kick with the snare destroys the engine's intended anchor relationship.
19. Add phrase-level timing drift without changing the declared BPM.
20. Add controlled “straight + swung simultaneously” fixtures.
21. Add MPC-style shift-timing emulation as an explicit operation rather than hiding it inside swing.
22. Add a timing-profile export so a render can be inspected without listening to it.
23. Compare human-readable timing reports against millisecond-domain measurements.
24. Add a regression preventing a future global-quantize operation from erasing voice-specific timing.
25. Add a `NO_QUANTIZE` invariant that checks the final rendered event positions rather than only the input flag.
26. Add a test showing that two grids with equal swing percentages can have materially different pocket.
27. Add a “Dilla-time” diagnostic name only as an analytical label, not as a claim of stylistic authenticity.
### Sampling and chopping

28. Add sample-start micro-offsets independent from drum microtiming.
29. Add sample-end seam quality measurement using waveform correlation.
30. Add zero-crossing/seam diagnostics without forcing zero-crossing edits.
31. Add loop-phase continuity analysis.
32. Add a transient-preservation score for chopped samples.
33. Add a sample-decay preservation score after varispeed.
34. Measure pitch-dependent transient smearing after resampling.
35. Compare independent resampling algorithms against the existing varispeed path.
36. Add alias-energy measurement after every pitch/time transformation.
37. Add a Nyquist-folding regression for heavily pitched-down samples.
38. Add a deliberately degraded low-bit-depth sample fixture.
39. Add a distinction between desirable sampler coloration and accidental digital aliasing.
40. Add SP-1200-style bandwidth/bit-depth experiments as measured profiles rather than aesthetic claims.
41. Add SP-303-style resampling experiments separately from SP-1200 emulation.
42. Add MPC-style interpolation/resampling experiments separately from SP-family processing.
43. Record source sample rate, bit depth, resampler and pitch ratio in render metadata.
44. Make every transformed sample reproducible from its source plus transformation metadata.
45. Add a “sample lineage” report from original source to final rendered event.
46. Add source-window hashes so a changed source cannot silently invalidate an old analysis.
47. Add a test proving that cached separation is invalidated when the source window changes.
### Madlib / deliberately rough production

48. Add a `ROUGH_HEWN` processing profile whose defining property is constrained processing, not generic distortion.
49. Separate intentional bandwidth limitation from accidental clipping.
50. Add a low-resolution sampler profile with independently measured noise, bandwidth and aliasing.
51. Add a test proving that roughness can be retained while transient damage remains bounded.
52. Add a `CHARACTER_PRESERVATION` score comparing pre/post processing spectral shape.
53. Add a “do less” mix mode that refuses unnecessary corrective processing.
54. Add a processing-budget report showing how many dB of cumulative EQ, compression and saturation have been applied.
55. Add a cumulative nonlinear-processing metric across the complete signal path.
56. Add a test where additional saturation is rejected because it no longer increases a desired measured characteristic.
57. Add deliberate mono-source widening as an explicit operation, rather than assuming stereo width exists in the source.
58. Measure correlation before and after widening.
59. Reject widening that materially damages mono compatibility.
60. Add a “rough but stable” reference fixture.
61. Add a “clean but lifeless” counter-reference fixture to prevent optimization toward cleanliness.
62. Add a `CONSTRAINTS` section to each production profile documenting which imperfections are intentional.
### Dave Cooley / mastering

63. Add a dedicated mastering stage that is analytically separate from mix processing.
64. Make mix-bus output available before mastering so the two stages can be compared directly.
65. Add pre-master crest-factor reporting.
66. Add post-master crest-factor reporting.
67. Add integrated, short-term and momentary loudness reporting.
68. Add true-peak reporting alongside sample peak.
69. Add intersample-peak detection.
70. Add loudness-range reporting.
71. Add spectral-balance reporting before and after mastering.
72. Add stereo-width reporting before and after mastering.
73. Add phase-correlation reporting before and after mastering.
74. Add mono-collapse reporting before and after mastering.
75. Add a mastering delta report: what actually changed rather than only the final numbers.
76. Add a mastering invariant preventing loudness normalization from becoming the only optimization target.
77. Add a regression where two masters with equal LUFS are distinguished by crest factor and transient preservation.
78. Add a regression where a louder master is rejected when it materially increases distortion without improving intelligibility.
79. Add a `MASTERING_INTENT` field separate from `LOUDNESS_TARGET`.
80. Add separate digital, streaming and archival mastering profiles.
81. Add a vinyl-oriented pre-master diagnostic without pretending that vinyl playback is a mastering effect.
82. Add low-frequency mono compatibility analysis below configurable crossover points.
83. Add a report identifying stereo information that disappears below mono fold-down.
84. Add a test for low-frequency phase inversion.
85. Add a test for stereo widening creating out-of-phase low end.
86. Add a “mastering restraint” metric measuring cumulative broadband gain.
### Bob Power / mix engineering

87. Add per-channel tonal-role metadata to make source frequency choices explicit.
88. Add channel-level headroom reporting.
89. Add mix-bus headroom reporting.
90. Add a headroom regression before nonlinear processing.
91. Add a detector for cumulative gain staging that creates distortion before the intentional saturator.
92. Add dynamic EQ fixtures for material whose timbre changes substantially with level.
93. Add automated vocal proximity-effect diagnostics where vocal processing exists.
94. Add dynamic spectral snapshots at multiple loudness percentiles.
95. Add a test proving that static EQ cannot always solve level-dependent tonal changes.
96. Add automation-aware spectral analysis.
97. Add a report showing which frequency bands require automation rather than static EQ.
98. Add serial-processing accounting so EQ/compression decisions can be inspected stage by stage.
99. Add “two light stages versus one heavy stage” comparison fixtures.
100. Add a compression artifact detector focused on transient flattening.
101. Add release-time modulation detection for audible pumping.
102. Add an attack-time diagnostic showing whether transients are being removed.
103. Add parallel-compression fixtures preserving dry transients.
104. Add parallel-compression phase/correlation checks.
105. Add a mix-stage versus master-stage processing boundary test.
### Todd Fairall / tracking-to-mix continuity

106. Record whether a source entered the engine as simulated tape, digital sample, live recording or synthesized material.
107. Preserve recording-medium metadata through the render pipeline.
108. Add ADAT-like constrained-recording tests distinct from generic tape saturation.
109. Add analog-console-style per-channel coloration before summing.
110. Verify that per-channel nonlinearities occur before summing.
111. Add a regression comparing pre-sum saturation against post-sum saturation.
112. Add a bus-intermodulation diagnostic.
113. Measure harmonic products created only after multiple channels are summed.
114. Add a test proving that a master-only saturator cannot reproduce the same intermodulation structure.
115. Add console headroom as an explicit simulation parameter.
116. Add a console overload diagnostic separate from clipping.
117. Add channel-strip variation so every channel is not mathematically identical.
118. Add deterministic per-channel component variance.
119. Add a test proving that channel variation remains reproducible under the same seed.
120. Add an A/B render between identical strips and statistically varied strips.
### Daddy Kev / Flying Lotus

121. Add a dedicated `DENSE_EXPERIMENTAL` reference profile for highly layered material.
122. Measure whether added layers actually remain distinguishable at the mix bus.
123. Add an “information density” metric combining event density, spectral occupancy and dynamic contrast.
124. Add a transient-density metric for complex drum programming.
125. Add a contrast metric between dense and sparse sections.
126. Add section-aware mastering analysis rather than only whole-track averages.
127. Add a long-form loudness trace so dynamic architecture survives mastering.
128. Add a “four-month-mastering” style analysis mode: allow iterative mastering passes while recording each delta.
129. Store mastering-pass metadata and final decision rationale.
130. Add an A/B/X listener fixture for tiny mastering differences.
131. Add parallel compression as an explicit experimental bus mode.
132. Add serial-compression experiments with artifact measurement after every stage.
133. Add compressor topology metadata to every render.
134. Add compressor attack/release normalization in milliseconds rather than only percentages.
135. Add pumping detection synchronized against BPM.
136. Add groove-aware compression diagnostics so compressor modulation can be compared with the beat grid.
137. Add granular-processing fixtures inspired by FlyLo's documented recent return to audio-engineering study.
138. Add grain-density, grain-size and randomization metadata to granular renders.
139. Add deterministic granular seeds for reproducibility.
140. Add a test proving that granular randomization does not alter timing-critical drum transients.
141. Add a sound-palette registry for synth, reverb and spatial treatments rather than accumulating arbitrary effect knobs.
### Rich Costey / complex mix architecture

142. Add explicit stem groups for drums, bass, harmonic material, samples, effects and vocals.
143. Add stem-level metering before the final bus.
144. Add stem-to-stem masking analysis.
145. Add stem solo/unsolo render comparison automation.
146. Add a deterministic “mix inspection” render that outputs every stem's measurements.
147. Add a final-bus report identifying which stem caused each master-bus threshold crossing.
148. Add transient contribution analysis by stem.
149. Add low-end contribution analysis by stem.
150. Add stereo-field contribution analysis by stem.
151. Add a test preventing a single stem from silently dominating the entire master-processing chain.
### Tape, console and nonlinear DSP

152. Separate tape compression, tape saturation, tape frequency response, wow/flutter and noise into independently measurable stages.
153. Add harmonic-order reporting for every nonlinear stage.
154. Report 2nd, 3rd, 4th and 5th harmonic energy independently.
155. Add a regression for the existing symmetric-transfer-function limitation.
156. Add asymmetric nonlinear fixtures specifically for even-harmonic generation.
157. Add DC-bias removal verification after asymmetric nonlinear processing.
158. Add oversampling-factor reporting for every nonlinear processor.
159. Add alias-energy reporting before and after oversampling.
160. Add an oversampling cost/quality table generated from actual renders.
161. Add CPU-cost measurements for every nonlinear stage.
162. Add a render-budget gate preventing an expensive DSP feature from silently multiplying render time.
163. Add deterministic analog-model noise seeded separately from musical randomness.
164. Add a distinction between correlated tape noise and independent channel noise.
165. Add wow/flutter rate distributions rather than a single “wobble” parameter.
166. Add dropout event metadata with deterministic seeds.
167. Add dropout detection to quality reports.
168. Add a test ensuring dropout processing cannot erase a transient-critical event.
169. Add console transformer coloration separately from clipping.
170. Add input/output transformer stages separately where the model supports them.
171. Add phase-alignment diagnostics around console coloration.
172. Measure whether multiple console instances produce qualitatively different spectra from one harder-driven instance.
### Spatial and stereo engineering

173. Add a stereo-image centroid measurement.
174. Add mid/side energy reporting.
175. Add mid/side spectral reporting.
176. Add low-frequency side-energy reporting.
177. Add a configurable maximum low-frequency side-energy threshold.
178. Add mono-collapse RMS loss measurement.
179. Add mono-collapse spectral loss measurement.
180. Add phase-correlation traces over time.
181. Add transient-specific stereo analysis.
182. Add reverb-tail stereo-width analysis.
183. Add a distinction between source stereo width and artificial widening.
184. Add widening provenance metadata.
185. Add a regression that rejects widening if it increases side energy without increasing perceptually useful information.
### Reference listening / objective validation

186. Create a small licensed reference corpus covering Dilla, Madlib and Flying Lotus-adjacent production characteristics.
187. Do not ship copyrighted reference audio into the repository; store only derived measurements and hashes.
188. Store reference metadata separately from generated fixtures.
189. Add reference spectral-envelope summaries.
190. Add reference crest-factor summaries.
191. Add reference loudness summaries.
192. Add reference stereo-correlation summaries.
193. Add reference timing distributions.
194. Add reference low-end distribution summaries.
195. Add reference transient-density summaries.
196. Add a `REFERENCE_DISTANCE` report comparing a render against derived reference features.
197. Keep “artist resemblance” out of the pass/fail gate; measure engineering properties instead.
198. Add perceptual listening notes beside numerical measurements.
199. Require every perceptual claim in `dilla_reference.yml` to point to a reproducible measurement or source.
200. Add provenance for each external research claim.
201. Add a research-source date and URL to each reference entry.
202. Add a contradiction field where two engineering sources disagree.
203. Add confidence only where the evidence genuinely warrants it.
204. Add explicit `unknown` states rather than inventing undocumented gear settings.
205. Add a gate rejecting “sounds more Dilla” as a completion criterion.
### Render reproducibility

206. Hash the complete DSP configuration before every render.
207. Include engine version, Ruby version, ffmpeg version and fluidsynth version in render metadata.
208. Include sample-source hashes in render metadata.
209. Include random seeds in render metadata.
210. Include DSP oversampling settings in render metadata.
211. Include all mastering parameters in render metadata.
212. Add bit-for-bit deterministic rendering where the backend permits it.
213. Add tolerance-based waveform comparison where codec output prevents bit identity.
214. Add deterministic regression renders for every major Dilla profile.
215. Store derived analysis beside each golden render.
216. Make golden-render invalidation explicit when DSP changes.
217. Add a `RENDER_SIGNATURE` command producing one compact reproducibility line.
### Mix validation gates

218. Add hard clipping detection before encoding.
219. Add true-peak detection after encoding.
220. Add NaN/Inf detection after every DSP stage.
221. Add denormal-number detection where relevant to long-running DSP.
222. Add DC-offset detection before final export.
223. Add excessive-subsonic-energy detection.
224. Add excessive-inaudible-ultrasonic-energy detection before final encoding.
225. Add codec-preview rendering for MP3 output.
226. Compare WAV and MP3 loudness after encoding rather than assuming equivalence.
227. Compare WAV and MP3 true peak.
228. Compare WAV and MP3 stereo correlation.
229. Add a lossy-encoding artifact report.
230. Add a final `MASTER_SAFE` gate combining peak, true peak, DC, subsonic, phase and loudness checks.
231. Keep every gate independently inspectable rather than collapsing failures into one score.
### Architecture / maintainability

232. Audit `STUDIO/dilla` for DSP parameters that exist in documentation but have no reader.
233. Audit the inverse: implemented parameters that are undocumented.
234. Make every environment knob discoverable from one generated registry.
235. Generate `ENV_AND_RENDER.md` parameter tables from the actual registry.
236. Add a gate detecting documentation-only DSP controls.
237. Add a gate detecting undocumented DSP controls.
238. Collapse duplicate DSP constants only after measuring actual call-site semantics.
239. Keep `DILLA_STYLE_DEFAULTS` and `DILLA_BEST_DEFAULTS` semantically distinct and document why.
240. Add a test proving profile defaults cannot silently override explicit user pins.
241. Add a test proving normalization cannot alter diagnostic A/B measurements.
242. Add a test proving render-mode selection does not change unrelated profiles.
243. Audit every `rescue StandardError` in dilla and classify it as recoverable, optional, or fatal.
244. Ensure optional-engine failures are visible in render metadata rather than silently becoming a degraded render.
245. Add an explicit degraded-render state.
246. Make `dmesg` report the exact DSP degradation when a component is unavailable.
247. Add render-stage timing to the dmesg output.
248. Add per-stage CPU and wall-clock cost to quality JSON.
249. Add a gate against DSP stages whose runtime grows unexpectedly with track length.
250. Add maximum-memory reporting for separation and render stages.
251. Add cleanup guarantees for temporary audio files after failed renders.
252. Add an interrupted-render recovery test.
### High-value experiments

253. Build a Dilla-style comparison: straight grid → global swing → per-voice swing → free timing, with identical sounds.
254. Build a Madlib-style comparison: clean digital → constrained sampler → rough constrained sampler → overprocessed, and measure where character turns into damage.
255. Build a Cooley-style comparison: mix-only → restrained master → loud master, with objective deltas.
256. Build a Bob Power-style comparison: source-choice correction versus EQ correction.
257. Build a Fairall-style comparison: per-channel nonlinear processing versus master-only nonlinear processing.
258. Build a Daddy Kev-style comparison: serial compression versus parallel compression.
259. Build a Flying Lotus-style density test: sparse arrangement → dense arrangement → dense arrangement with intentional negative space.
260. Build a “same LUFS, different music” test suite to prevent loudness from becoming the quality metric.
261. Build a “same swing, different pocket” test suite.
262. Build a “same EQ, different source” test suite.
263. Build a “same saturation amount, different harmonic structure” test suite.
264. Build a “same stereo width, different mono compatibility” test suite.
265. Build a “same RMS, different crest factor” test suite.
266. Build a “same spectral centroid, different transient structure” test suite.
### Documentation / research corpus

267. Expand `dilla_reference.yml` with Bob Power's source/timbre/frequency-selection observations.
268. Add Todd Fairall's ADAT → studio-console workflow as a documented historical reference.
269. Add Dave Cooley's Donuts/The Shining mastering role and preserve the distinction between mastering and mixing.
270. Add Dave Cooley's Madlib/Quasimoto constrained-hardware workflow.
271. Add David Kennedy's analog-console/tape workflow and room-acoustics observations.
272. Add Daddy Kev's compression methodology as a technical reference.
273. Add Flying Lotus' recent audio-engineering/granular-synthesis comments as a current research note.
274. Add Rich Costey's mixing credit for *You're Dead!* to the engineering provenance.
275. Record which facts are direct interviews, which are album credits and which are secondary analysis.
276. Do not turn undocumented folklore about Dilla's exact gear/settings into hard engine requirements.
277. Separate historically documented technique from modern recreation.
278. Add a `research_status` field to every reference item: `verified`, `inferred`, `contested`, `unknown`.
279. Add a `measurement_status` field: `measured`, `provisional`, `unmeasured`.
280. Add a quarterly research-review task so new interviews/credits can be incorporated without silently changing historical claims.

280 items. Measure before working. Do not retune a keeper take to pass a metric.


## MASTER web UI — future-human face — ChatGPT intake 2026-09-11

Unmeasured. The face is a rendered look; TTS voice is a rendered sound. Defaults
stay the operator’s. Implementable from this list: state machines, event streams,
sync budgets, health/TTS reliability, reduced-motion, WebGL fallbacks, declarative
payloads, measurements. Geometry, brightness, colour, and voice defaults are named
and left. No cyberpunk implants, no neon, no “sounds more human” as a gate.
A finding is a hypothesis. Blind-tests of perceived intelligence are operator work.

### Evolutionary direction

1. Define a written morphological hypothesis for the face before changing its geometry.
2. Establish that the target is a plausible far-future human descendant, not a robot face.
3. Preserve enough bilateral symmetry for the viewer to recognize a face immediately.
4. Gradually break present-day human proportions rather than jumping directly to alien morphology.
5. Introduce a larger cranial volume as a subtle long-term evolutionary signal.
6. Reduce the visual dominance of the jaw and lower face.
7. Experiment with a slightly smaller lower-face region.
8. Increase forehead/upper-cranium visual mass.
9. Explore slightly larger orbital regions without making the eyes cartoonishly large.
10. Explore reduced visible sclera as an evolutionary variation.
11. Test slightly increased interocular distance.
12. Test reduced nasal prominence.
13. Test a less projecting mouth region.
14. Test subtler ears or partial loss of visible external ears.
15. Explore a neck/head proportion suggesting reduced dependence on today's musculature.
16. Introduce subtle cheek/temporal structural changes rather than cosmetic “alien” features.
17. Create a morphology parameter space rather than one fixed future-human model.
18. Establish a conservative default within that parameter space.
19. Add one or more extreme experimental morphologies behind explicit development flags.
20. Ensure morphology changes preserve recognizability.
21. Measure recognizability against silhouette and landmark consistency.
22. Add a morphology regression so future visual changes cannot accidentally return the face to generic human proportions.
23. Add `FUTURE_HUMAN_MORPHOLOGY` as a conceptual profile, not an arbitrary collection of knobs.
24. Document which morphological assumptions are speculative.
25. Keep scientific plausibility separate from visual preference.
26. Avoid claiming that any particular future morphology is scientifically predicted.
27. Add a `morphology_rationale` section to the face documentation.
### Far-future human visual language

28. Develop a visual language based on biological continuity rather than cyberpunk aesthetics.
29. Avoid glowing circuit traces, robot panels, mechanical eyes and obvious technological implants.
30. Avoid conventional humanoid robot facial geometry.
31. Avoid gratuitous neon effects.
32. Avoid decorative HUD elements competing with the face.
33. Let the unusual morphology carry the science-fiction quality.
34. Use depth, density and motion rather than color to communicate intelligence.
35. Make the face feel grown rather than manufactured.
36. Make the geometry look computationally generated but biologically organized.
37. Introduce controlled developmental asymmetry.
38. Add tiny persistent asymmetries between left and right facial structures.
39. Make asymmetry deterministic and seedable.
40. Allow asymmetry to increase subtly with runtime age.
41. Add slow morphological drift over long sessions.
42. Ensure drift never changes identity abruptly.
43. Make the face's “age” independent of conversation count.
44. Add a very slow biological-style breathing/deformation field.
45. Add subtle pulse-like depth modulation.
46. Add extremely slow cranial surface movement.
47. Keep all such movement below the threshold of distracting animation.
### Eyes

48. Redesign eye behavior around attention rather than animation.
49. Separate gaze direction from cursor position.
50. Add attention targets for user input, generated response and environmental events.
51. Add gaze dwell time.
52. Add gaze uncertainty.
53. Add deliberate gaze shifts before speech.
54. Add gaze stabilization during important TTS phrases.
55. Add brief gaze release after completing a thought.
56. Add blink timing influenced by conversational state.
57. Prevent periodic blinking from looking like a fixed animation loop.
58. Add correlated left/right eyelid movement with small natural asymmetry.
59. Add occasional micro-saccades.
60. Add saccade suppression during focused processing.
61. Add a distinction between visual curiosity and visual attention.
62. Make cursor attraction a weak cue rather than literal eye tracking.
63. Add an “uncertain gaze” state for ambiguous input.
64. Add a “deep attention” state for long reasoning/TTS segments.
65. Add a “social attention” state when directly addressing the user.
66. Add a “listening” gaze state.
67. Add a “speaking” gaze state.
68. Add a “thinking” gaze state without using the stereotypical looking-up animation.
### Face geometry

69. Separate anatomical landmark generation from point-cloud rendering.
70. Generate a stable semantic landmark layer before scattering visual points.
71. Give forehead, orbit, cheek, nose, mouth and jaw independently measurable regions.
72. Add region-specific point density.
73. Add depth-dependent point density.
74. Add curvature-dependent point density.
75. Add controlled biological growth fields.
76. Make point density respond to morphology rather than merely depth.
77. Prevent dense regions from becoming visually brighter solely because they contain more points.
78. Normalize density-driven luminance.
79. Add a geometry-preservation regression for major facial landmarks.
80. Add silhouette comparison renders.
81. Add depth-map comparison renders.
82. Add face-area occupancy measurement.
83. Add cranial-to-facial-area ratio measurement.
84. Add upper-face/lower-face ratio measurement.
85. Add orbital-area measurement.
86. Add jaw-area measurement.
87. Add facial-width measurement.
88. Track these metrics across morphology changes.
### Biological emergence

89. Replace some purely random point placement with constrained growth processes.
90. Generate secondary structures from primary facial landmarks.
91. Add developmental growth fields.
92. Use deterministic noise rather than uncontrolled randomness.
93. Test reaction-diffusion-inspired surface structures.
94. Test Voronoi-like cellular organization.
95. Test branching patterns only where anatomically plausible.
96. Reject patterns that look like circuitry.
97. Test subtle vascular-like density variation.
98. Test subtle neural-network-like structures only at microscopic visual scale.
99. Ensure these structures disappear naturally when zoomed out.
100. Add a distance-dependent representation: gross morphology at distance, microstructure close up.
101. Make the face visually richer when inspected rather than merely larger.
102. Add level-of-detail transitions that preserve morphology.
103. Prevent LOD transitions from visibly popping.
### Expression

104. Replace a small set of explicit expressions with continuous affect dimensions.
105. Separate affect from facial morphology.
106. Model curiosity, attention, uncertainty, amusement, concern, confidence and calm as continuous values.
107. Map affect onto multiple facial regions simultaneously.
108. Avoid emoji-like expression changes.
109. Avoid exaggerated eyebrow animation.
110. Avoid mouth animations that resemble cartoon speech.
111. Add micro-expression layers beneath deliberate expressions.
112. Add expression inertia so state changes are gradual.
113. Add expression recovery after emotionally intense responses.
114. Add a neutral state that still feels alive.
115. Add a low-energy state for long idle periods.
116. Add an alert state for user interruption.
117. Add an error state that communicates “something went wrong” without looking frightened.
118. Add an unavailable state that communicates absence rather than failure.
119. Add expression tests driven from recorded conversation states.
### Listening behavior

120. Make the face visibly listen while microphone input is active.
121. Drive subtle facial changes from voice activity rather than loudness alone.
122. Distinguish speech from background noise.
123. Add input-energy smoothing.
124. Add speech onset anticipation.
125. Add speech offset relaxation.
126. Prevent noisy microphones from producing frantic face motion.
127. Add a listening confidence signal.
128. Add an explicit “I hear you” state before transcription completes.
129. Make listening visually distinct from thinking.
130. Make thinking visually distinct from speaking.
### TTS / speech embodiment

131. Make TTS timing the primary driver of speaking animation.
132. Synchronize facial activity to actual phoneme/word timing where available.
133. Add viseme-independent speech motion so the face does not become a talking cartoon.
134. Drive mouth-region density from speech energy.
135. Drive subtle jaw movement from low-frequency speech energy.
136. Drive upper-face attention independently from speech.
137. Keep facial movement below exaggerated lip-sync thresholds.
138. Add phrase-level breathing gaps.
139. Add micro-pauses before important clauses.
140. Add longer pauses where punctuation indicates conceptual boundaries.
141. Preserve natural speech rhythm instead of maximizing speech throughput.
142. Measure average pause duration.
143. Measure phrase-length distribution.
144. Add TTS prosody metadata to the browser payload.
145. Expose pitch contour to the face only after smoothing.
146. Expose energy contour to the face only after smoothing.
147. Add speech-rate normalization.
148. Ensure face animation remains coherent across different voices.
149. Make the face respond to prosody rather than a specific voice's absolute frequency.
150. Add a voice-independent TTS animation layer.
151. Add voice-specific optional tuning on top of that layer.
### Voice character

152. Treat TTS voice as part of the MASTER persona rather than a disconnected browser feature.
153. Preserve the constitutional voice policy as the source of truth.
154. Add voice characteristics to the browser runtime payload.
155. Add explicit speech-rate policy.
156. Add explicit pitch policy.
157. Add explicit pause policy.
158. Add explicit emphasis policy.
159. Add pronunciation overrides for technical vocabulary.
160. Add pronunciation tests for MASTER-specific terminology.
161. Add pronunciation tests for Ruby/Rails/OpenBSD terminology.
162. Add pronunciation tests for mathematical notation where TTS encounters it.
163. Add pronunciation tests for file paths and commands.
164. Prevent raw shell commands from being spoken character by character unless explicitly requested.
165. Add human-readable spoken forms for paths and identifiers.
166. Add sentence-level speech normalization before synthesis.
167. Keep displayed text and spoken text separate while retaining one semantic source.
168. Add a speech transcript event stream so browser animation knows exactly what is being spoken.
### TTS reliability

169. Add an explicit TTS state machine: idle → preparing → speaking → paused → complete → failed.
170. Expose that state to the browser.
171. Make stale TTS state impossible after a failed synthesis.
172. Add socket liveness detection.
173. Add TTS worker restart detection.
174. Add synthesis timeout detection.
175. Add browser playback timeout detection.
176. Add stale-audio detection.
177. Add duplicate-audio detection.
178. Add interrupted-speech cancellation.
179. Add queue cancellation when a newer response supersedes an older one.
180. Add bounded TTS queue length.
181. Add backpressure reporting.
182. Add browser-side retry only for transport failure, not synthesis failure.
183. Add server-side retry only for transient worker failure.
184. Never silently fall back to a different voice.
185. Make degraded TTS visible in the face state.
186. Add an audible/visual test covering worker death and recovery.
187. Add a test covering browser reload during active speech.
188. Add a test covering network interruption during speech.
189. Add a test covering two simultaneous browser tabs.
### Voice + face synchronization

190. Create one timestamped event stream for text, TTS and face state.
191. Use the same event timestamps for browser animation and audio.
192. Measure audio-to-face latency.
193. Measure face-to-audio lead/lag.
194. Set a hard synchronization budget.
195. Add automatic synchronization correction.
196. Prevent animation from running ahead indefinitely when audio stalls.
197. Prevent audio from continuing indefinitely after the face runtime dies.
198. Add synchronization diagnostics to browser developer output.
199. Add a recording mode capturing TTS plus face state for regression testing.
200. Add golden synchronization traces.
### Face as an interface

201. Make the face itself communicate system state without requiring text.
202. Define visual states for listening, thinking, speaking, idle, unavailable and error.
203. Keep those states distinguishable at thumbnail size.
204. Keep those states distinguishable without color.
205. Add reduced-motion equivalents for every state.
206. Add high-contrast equivalents for every state.
207. Ensure screen readers are not forced to interpret decorative face animation.
208. Expose semantic state through accessible text.
209. Prevent animation from stealing keyboard focus.
210. Ensure the face never blocks chat controls.
211. Make face interaction optional.
212. Add a minimal mode containing only the face and essential controls.
213. Add a terminal-style mode for low-end hardware.
214. Add a static fallback for WebGL failure.
215. Add a low-resolution fallback for weak GPUs.
216. Add a reduced-point-count fallback.
217. Ensure the fallback preserves the same morphological identity.
### Performance

218. Measure face CPU usage separately from chat/TTS.
219. Measure GPU frame time.
220. Measure memory consumption.
221. Measure shader compilation time.
222. Measure first meaningful face render.
223. Measure time from page load to face-ready.
224. Keep TTS startup independent from face rendering.
225. Prevent face initialization from delaying first interaction.
226. Keep the existing no-prefetch rationale intact unless measurements change it.
227. Add adaptive point-count scaling.
228. Add adaptive animation-frequency scaling.
229. Add thermal/CPU-pressure detection where available.
230. Reduce face simulation rate before reducing interaction responsiveness.
231. Never sacrifice TTS responsiveness to preserve cosmetic animation.
232. Add performance telemetry to the browser test harness.
233. Add a low-end benchmark representative of the production VPS/browser combination.
### Rendering quality

234. Replace fixed exposure tuning with a perceptual face-visibility test.
235. Add automatic detection of a face whose points are technically present but visually unreadable.
236. Measure minimum facial-region contrast.
237. Measure depth readability.
238. Measure silhouette readability.
239. Add dark-background and light-background render tests.
240. Add different-display-brightness tests.
241. Add small-viewport tests.
242. Add large-viewport tests.
243. Add high-DPI tests.
244. Add low-DPI tests.
245. Prevent exposure from being the universal solution to poor geometry.
246. Separate geometry visibility from exposure.
247. Separate point alpha from exposure.
248. Separate depth shading from exposure.
249. Add a perceptual render-quality report.
### Motion language

250. Define a face motion grammar before adding more animations.
251. Give every motion a semantic cause.
252. Remove motion that exists solely because “the screen should move.”
253. Add inertial transitions between states.
254. Add different time constants for eye, face, jaw and microstructure movement.
255. Prevent all facial regions from moving synchronously.
256. Introduce subtle correlated-but-independent biological motion.
257. Add low-frequency motion.
258. Add medium-frequency attention motion.
259. Add high-frequency micro-expression motion only where justified.
260. Prevent high-frequency noise from reading as jitter.
261. Add a motion-energy budget.
262. Add a gate preventing excessive motion during speech.
### Evolution over long sessions

263. Give the face a persistent identity seed.
264. Keep identity stable across reloads where policy permits.
265. Allow tiny non-destructive morphological drift.
266. Keep drift deterministic for reproducibility.
267. Separate identity seed from conversation seed.
268. Prevent different tabs from accidentally generating different identities.
269. Add long-session tests lasting at least one hour.
270. Add long-session memory/performance measurements.
271. Add long-session visual-drift measurements.
272. Prevent cumulative shader-state degradation.
273. Prevent accumulated audio/face synchronization drift.
274. Add a “generational drift” development mode for visual research only.
### Generational morphology experiments

275. Define Generation 0 as present-day human reference.
276. Define Generation 1 as minimally divergent future human.
277. Define Generation 2 as anatomically divergent but recognizable.
278. Define Generation 3 as substantially post-human.
279. Define Generation 4 as far-future descendant.
280. Keep each generation reproducible.
281. Document the morphological changes between generations.
282. Avoid making later generations simply “more alien.”
283. Change proportions, density, expression and movement independently.
284. Add an evolution-comparison view for development.
285. Add silhouette comparison between generations.
286. Add depth-map comparison between generations.
287. Add landmark comparison between generations.
288. Add a subjective design review for each generation.
289. Do not present speculative generations as scientific predictions.
### Web layout refinement

290. Establish a strict visual hierarchy: face → conversation → input → system state.
291. Give the face enough negative space to read as an entity rather than an ornament.
292. Reduce competing chrome around the face.
293. Make chat content feel like a conversation with the face rather than a conventional chatbot dashboard.
294. Make TTS activity visually subordinate to the face itself.
295. Keep controls visually quiet until interaction.
296. Make the primary input surface obvious without looking like a generic SaaS text box.
297. Create a persistent but unobtrusive system-status region.
298. Make connection/TTS state available without permanent status clutter.
299. Establish one spacing scale for the entire MASTER UI.
300. Establish one radius scale.
301. Establish one border-weight scale.
302. Establish one typography hierarchy.
303. Establish one animation-duration scale.
304. Remove one-off spacing values where equivalent tokens exist.
305. Remove redundant shadows.
306. Avoid decorative gradients whose only purpose is visual noise.
307. Prefer depth created by spacing, translucency and geometry.
308. Keep the face visually dominant without increasing its brightness arbitrarily.
309. Ensure the chat surface never visually overwhelms the face.
310. Ensure mobile layout preserves the same hierarchy.
311. Add narrow-screen composition tests.
312. Add ultra-wide composition tests.
313. Add keyboard-only navigation tests.
314. Add touch-target tests.
315. Add reduced-motion layout tests.
### Layout states

316. Design a dedicated first-load state.
317. Design a listening state.
318. Design a thinking state.
319. Design a speaking state.
320. Design a waiting-for-input state.
321. Design an offline state.
322. Design a degraded-TTS state.
323. Design a WebGL-unavailable state.
324. Design a reconnecting state.
325. Ensure every state preserves the same spatial hierarchy.
326. Prevent layout shifts when TTS starts.
327. Prevent layout shifts when the face changes rendering mode.
328. Prevent chat history from moving the face unexpectedly.
329. Add visual regression snapshots for every state.
### Interaction refinement

330. Add interruptible TTS.
331. Add immediate visual acknowledgement when the user starts typing.
332. Add immediate visual acknowledgement when speech input starts.
333. Add a clear distinction between submitted and pending input.
334. Add response streaming without making the face wait for the entire response.
335. Let the face transition into thinking as soon as processing actually begins.
336. Let the face transition into speaking only when audio actually begins.
337. Stop speaking animation when playback actually stops.
338. Make cancellation visually immediate.
339. Preserve scroll position during streaming.
340. Prevent streaming text from causing excessive layout reflow.
341. Add conversation density controls without changing the underlying semantics.
342. Add a distraction-free mode.
343. Add a face-only focus mode.
344. Add a text-only accessibility mode.
### Asset and deployment correctness

345. Keep source face modules and generated `face.runtime.js` provably synchronized.
346. Add a byte-for-byte build verification for generated face artifacts.
347. Keep the existing regression around stale `face.runtime.js`; it has already caught a real failure.
348. Add a deployed-asset version stamp to the browser payload.
349. Display asset-version mismatch as a development diagnostic.
350. Add a production smoke test that loads the actual face asset rather than only checking source files.
351. Add a production smoke test that speaks one short TTS phrase.
352. Add a production smoke test that verifies face/TTS synchronization.
353. Add a production smoke test for WebGL fallback.
354. Add a production smoke test for stale cached face assets.
355. Make cache invalidation deterministic after face-runtime changes.
356. Ensure browser payload and server voice policy cannot silently disagree. The current chat view already exposes both persona and `MASTER_VOICE_POLICY` to the browser.
### Research / scientific grounding

357. Research human craniofacial evolution and distinguish robust evolutionary evidence from speculative futurism.
358. Research encephalization and explicitly avoid equating brain size with intelligence.
359. Research sensory-system evolution relevant to visual morphology.
360. Research possible future effects of technology-assisted cognition without visually turning them into implants.
361. Research reduced mastication hypotheses carefully; do not directly translate them into a smaller jaw without evidence.
362. Research sexual selection versus functional selection in facial morphology.
363. Research developmental constraints on facial evolution.
364. Research bilateral symmetry and developmental noise.
365. Research facial motion perception and human sensitivity to micro-expressions.
366. Research uncanny-valley thresholds specifically for point-cloud faces.
367. Research whether increased cranial proportions actually improve perceived intelligence or merely trigger science-fiction stereotypes.
368. Record sources and confidence for every biological design assumption.
369. Keep the visual design explicitly labeled as speculative evolutionary art rather than scientific prediction.
### Master face research experiments

370. Generate 10 morphology variants from the same identity seed.
371. Blind-test recognizability.
372. Blind-test perceived intelligence.
373. Blind-test perceived age.
374. Blind-test perceived biological versus artificial origin.
375. Blind-test perceived emotional expressiveness.
376. Measure which geometric changes produce the strongest perception shifts.
377. Remove changes that create “alien” perception without improving the future-human hypothesis.
378. Find the minimum morphological divergence that makes the face feel clearly post-human.
379. Find the maximum divergence that remains recognizably human.
380. Use that interval as the design envelope.
381. Test morphology without animation.
382. Test animation without morphology.
383. Test both together.
384. Prefer changes that remain convincing in all three conditions.
### One-source-of-truth

385. Make face morphology parameters declarative.
386. Make TTS policy declarative.
387. Make face/TTS state mappings declarative.
388. Generate browser payload from those declarations.
389. Generate documentation from those declarations where practical.
390. Add a consistency gate between server voice policy, browser payload and runtime.
391. Add a consistency gate between face source modules and generated runtime.
392. Add a consistency gate between CSS layout tokens and rendered layout tests.
393. Reject undocumented face parameters.
394. Reject browser-only face state names that have no server/runtime semantic.
395. Reject TTS states that have no browser representation.
### Final design criterion

396. The face must look alive without looking animated.
397. The face must look evolved without looking alien.
398. The face must look intelligent without relying on glowing eyes or UI clichés.
399. The face must look biological without pretending to be a photograph.
400. The face must communicate listening, thinking and speaking without cartoon expressions.
401. The TTS must sound like a coherent entity rather than a text-to-speech subsystem.
402. The web UI must feel like an interface to a future intelligence rather than a website containing a chatbot.
403. Every visual effect must have a semantic, biological, perceptual or interaction reason.
404. Delete effects that cannot explain why they exist.

404 items. Hypothesis first; do not retune the live face from this file.


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
2. **`mask.js` / `mask_generators.js` / `mask_topologies.js`.** `visual_governor_spec.rb:30` says mask.js is superseded. Comments in `cognition_ecology.js` and `visual_governor.js` still name it. Delete the three files and the comments.
3. **`examples.html.erb` — already gone.** The file is not in the tree and no
   controller references it. Nothing to do.
4. **Two `WebPushJob`s.** `RAILS/brgen/app/jobs/web_push_job.rb` and `RAILS/shared/app/jobs/shared/web_push_job.rb`. One class.
5. **`futurism` — the claim is false.** `futurize` appears in three ERB files,
   so the pin has a reader. Whether one lazy index is worth a gem is a
   different question from whether it is wired, and it is wired.
6. **`bin/crate` writes `dilla/crate/`.** Directory gone; engine reads `samples/`. Delete or retarget.
7. **`restore_backups.sh`.** Litestream. Rename; first usage line `use bin/dr-pull`.
8. **Three atomic writes.** `Io::AtomicWrite` fsyncs; World and Live do not. One helper.
9. **Two PathGuards.** Prefix vs ancestor-realpath. One module, the strong check.
10. **`ChatController#dmesg` vs `Trace::Dmesg`.** One.
11. **`VoteReflex` vs `votes#create.turbo_stream`.** Keep the stream.
12. **Host vs shared notifications controllers.** One.
13. **Marketplace vs takeaway `_nav_bar`.** One partial.
14. **Legal/mailer `<style>` vs `_typography.scss`.** Delete the ERB type systems.
15. **`.reading-column` / `.form-measure` — deliberate, and said so.** No view
    wears either. `css_coverage_lint.rb:96` records them as opt-in measure
    classes "worn by tokens, not yet by every view", so this is a decision
    already taken rather than residue. Wearing them is design work.
16. **MixScore backticks vs engine Open3 vs `RadioChop.capture`.** One ffmpeg runner, one `capture` signature.
17. **`dilla_principles.yml` unread.** Load from `groove_engine` or delete.
18. **Two LUFS windows.** One.
19. **`operator.yml` vs RUNBOOK vs CLAUDE vs START_HERE vs RECIPES.** One command list.
20. **Four deploy verbs.** Wrappers around `vps-deploy`.
21. **Two uptime-check scripts.** One file, one host list.
22. **Face tests in `spec/`, `test/`, `web/test/`.** Two homes at most.
23. **`bin/cli` vs `bin/master`.** One REPL file.
24. **`MASTER/lib/rails/`.** Move to `RAILS/gates/lib` or `/rails audit`.
25. **Zeitwerk ignore of the dead slash tables.** After (1), `rake lint:autoload` failing those entries is the deletion proof.

If two things mean the same thing, keep the one with the test.

26. **`swarm.html` / `diag.html`.** Public extra HTML, `lang="en"`, inline script, not the face. Gate behind auth or delete from production `public/`.
27. **`codebase.js` not in `face_assets.yml`.** Topology still names it. Add to a deferred group or stop naming it.
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
35. **`bin/nsaudit`.** Two-spine leftover. Fold into `rake lint:autoload` or delete.
36. **`smoke-apps.sh` vs `deploy-smoke.sh`.** One smoke; `port_inventory` `SMOKE_SCRIPTS` retargets.
37. **`content-loader` retired in comments; `examples.html` still has it.** After deleting examples (3), drop the leftover markup if any remains.
38. **Three face stores.** `felt_state.js`, `face_state.js`, `ui_presence.js`. Document boot order or fold presence into felt.
39. **`hello: Hei` in brgen and amber `nb.yml`.** Grep callers; delete unused scaffold keys.
40. **`rails-app.tmpl` disagrees with live `rc.d/brgen`.** Generate apps from the live script or delete the tmpl so OPERATOR cannot install the wrong one.
41. **`jobs` rc.d without `set -a`.** Same env file as the app (bughunt 30). One export path.
42. **`core-reclaim.sh` RSS via `ps | grep | head | awk`.** Wrong pid; banned tools. `ps -o rss= -p`.
43. **`STREAM_ITERATE_LOG` unsynchronized.** One flock or pid-scoped log.
44. **`sine_stream.rb` mutates ENV at load.** Don’t require it from tests; or don’t set ENV in a library file.
45. **`kaggle_session.rb` / `colab_session.rb` / `run_ai_toolkit.rb` ARGV at load.** Guard with `$PROGRAM_NAME`.
46. **`postpro.log` — already ignored.** `git ls-files` tracks no log under
    postpro. Nothing to do.
47. **`MASTER/log/traces.log`, `tts.wav`, `runtime/` JSONL, `loop.gif`.** START_HERE says generated goes in `.master/` / `output/`. Gitignore or PATH_OWNERSHIP `check: none`.
48. **`snapshot_*.md` — already ignored.** `.gitignore:65` carries
    `/snapshot_*.md` and `git ls-files` tracks none of them, so the root holds
    what TREE.md says it holds. The four files are generated locally after a
    push and never committed.
49. **`PwaController` has no request test.** `pwa_master_contract_test.rb` greps ERB. `GET /manifest` 200 JSON.
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

---


