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
`bin/pub4 vps state --remote` does not. Surfacing it there would have named
this in one command instead of four deploy passes.

### The box, verified 2026-09-09

`MASTER/bin/pub4 vps state --remote` is the only honest way to answer this and it is
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

Every row `MASTER/bin/pub4 measure` prints is green or is another tree's. Read the
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
both are at their ceilings. **Read `bin/pub4 measure`. Do not quote this paragraph.**

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
is eight rows of debt.** `bin/doctor` prints `summary_line` under the boot receipt —
the receipt says what booted, the scorecard says what has been proven and when. It
now names how many rows are past `EVIDENCE_SHELF_LIFE_DAYS`, set to 30 because a
`verified` taken off month-old evidence is a claim again. All eight rows in
`data/maturity.yml` were last checked on 2026-07-22, so the count reads 8 of 8. **That
is the open item now: re-verify them or mark them, one at a time, with the evidence.**

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

Live figures from `bin/pub4 measure`, `rake lint:rule_reach` and `rake lint:rule_audit`
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

Two were drafted, run over the tree, and are blocked on the cross-file index below.
Neither is a guess.

- **`LAYER_CAKE`** — a chain of sibling methods each of which only forwards. At three
  links, the honest reading, this tree has **none**, and a rule that fires on nothing
  joins `rule_audit.silent`, which is at its ceiling. At two links it finds 9, and
  reading them says why that threshold is wrong: three are `rescue_handlers.rb` naming
  one exception each before forwarding to `render_http_error`, the shape `rescue_from`
  requires, and the rest (`ok? -> ok`, `unwrap -> value!`) are aliases. A two-link
  forward is an alias, not a cake. A real layer cake spans files — controller to
  service to repository — and no per-file rule can see it.
- **`DEAD_ABSTRACTION`** — the class half is precise and almost empty: 4 classes declare
  a body that is only `raise NotImplementedError`, and exactly **1** has no
  implementer. The module half is a false-positive machine and must not ship as
  written: 367 of 419 modules that define methods are included at most once, because
  nearly every module here is a `module_function` namespace rather than a mixin, so the
  census measures Zeitwerk's file-to-constant mapping and calls it a dead abstraction.
  One finding does not pay for a rule.

#### Larger AST work — multi-session projects

Each is its own sitting, with an owner and a design, not a sweep.

- **A cross-file AST / symbol index.** Every rule that needs to know "who implements
  this" or "who calls this" (`DEAD_ABSTRACTION`, `LAYER_CAKE`, feature envy across
  files) currently cannot see past the file it is in.
- **An incremental scan cache keyed on file SHA.** Re-parse only what changed; a full
  scan re-walks the whole tree every run.
- **tree-sitter for real JS / SCSS ASTs.** The JS and SCSS rules are lexical because
  there is no real parse tree for those languages here; a real AST retires whole
  classes of false positive.
- **Prose / CSS / audio "AST" rules.** The same deterministic-detector idea applied to
  non-Ruby artifacts — documents, stylesheets, and dilla's render graph.
- **A clone → extract-method autofix.** `DUPLICATE_CODE` detects; nothing extracts.

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

**119 of 405 `lib/` files have no test or spec naming their innermost class or
module**, re-measured 2026-09-09. The earlier records of 163 of 445 and 188 of ~400
used the same method against larger trees; the fall is mostly `lib/` shrinking and the
rule-fixture pass.

The argument for closing the gap is what happened when eight named constants got their
first tests on 2026-08-01: four live defects fell out, all in code that looked fine.

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

### `rake studio` fails on dilla, not on vips

**This section said `rake studio` fails locally because `ruby-vips` and `libvips` are
not installed. Both are installed** — `test_tools_postpro.rb` prints `vipsgem=true`
and passes — and `studio_gate` itself passes, parsing 110 Ruby files. What fails is
`studio_test`, inside dilla, and the three defects are real:

    302 runs, 14098 assertions, 2 failures, 1 errors, 3 skips

- `test_every_hand_cut_sample_loop_is_reachable_as_a_track_preset`
  (`STUDIO/test/test_dilla_engine_probes.rb:1038`) — the loop `semua_untuk_mu` points
  at a missing file.
- `test_every_genre_renderer_reaches_the_master_bus` (`:1180`) — `render_analog` never
  sets an integrated loudness.
- `TestRenderSeed#test_render_rand_stays_in_the_unit_interval`
  (`STUDIO/test/test_dilla_render_seed.rb:75`) — `NoMethodError: undefined method
  'render_rand'`. The helper the test names does not exist.

These belong to dilla's owner. `rake studio` is the fourth prerequisite of `rake
audit`, so it is what the audit hands you after the earlier gates pass.

### Survey findings still open

Re-measured 2026-09-09. Every number here was wrong by a little in the previous
version, which is the argument for re-running the instrument rather than quoting it.

**Twenty-five files in `lib/` are below the sprawl threshold, and the merge is not
free.** `FileSprawlRule` (`MASTER/lib/review/scan/rules/meta_rules.rb:284`) run over
`lib/` names 25, of which two are lone-file directories —
`MASTER/lib/cli/propose/candidate_sources.rb` and
`MASTER/lib/review/repo_ecology/co_change_graph.rb` — and the rest are under 25 code
lines. The cheapest are the ones whose constant nothing outside names:
`MASTER/lib/security_error.rb` at 3 code lines,
`MASTER/lib/review/review_crew/agents.rb` at 8 (already an autoload ignore, so a pure
require aggregator), `MASTER/lib/fix/constants.rb` at 10. `lib/io/antigravity.rb` is
**not** on this list any more — it absorbed its folded subdirectory and is 231 code
lines. But `lib/` is under `push_dir(__dir__, namespace: Master)`
(`MASTER/lib/master.rb:150`), so every other merge moves a constant and needs either a
caller rename or a new `data/autoload.yml` entry that `rake lint:autoload` will then
hold to account. Do these one at a time with the constant rename in the same commit;
do not sweep them.

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

**`ABC_SIZE` fires three times over its ratchet of 40**, and this is the one figure
that re-measured exactly: `MASTER/lib/voice/emotion.rb:20` `#analyze` at 74.7,
`MASTER/lib/cli/session/command_ops.rb:24` `#run_critique` at 42.2, and
`MASTER/lib/ground/phase_gates.rb:103` `#automatic_gate_met?` at 41.4. `rake
constitution` overall is 1,791 findings, 101 actionable against a budget of 1,500, and
passes.

**`emotion.rb#analyze` at 74.7 is the largest and is deliberately not being
refactored.** Its ABC is arithmetic rather than branching — five weighted sums over the
signal table — and the shape that would lower it is to move the coefficients into a
table and fold them. That changes the association order of a float sum, and its outputs
are `exaggeration`, `cfg_weight` and `warmth`: the controls MASTER's speech is
synthesised with. A refactor that alters the last bits of those is a change to what
MASTER sounds like, made by somebody who cannot hear it. It stays until a sitting that
can A/B the audio.

**`NO_PUTS`' eleven findings are closed**, and the rule exempts
`MASTER/lib/pub4/gate_chain.rb` by name. The statement is "no bare puts in library
code" and its exemptions are the paths that print for a living. The file rather than
its directory: the sibling `status_report.rb` renders a string that `bin/pub4` prints,
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

**And `data_reach` cannot tell which file a reader opened.** Its test is whether the
key name appears anywhere in first-party code, so `success_criteria` counted as reached
for as long as it existed — `lib/ground/phase_gates.rb:133` names it, reading session
state rather than `rules.yml`. The 37 at the ceiling is a floor on the real number, not
the number.

### The shape of the tree

`sprawl_census` counts three things over every tracked file in all four trees, and
`bin/pub4 measure` carries them: a directory holding one file, a name that repeats its
parent, and a name that says nothing on its own. `FILE_SPRAWL` in the scan registry
measures the first two for MASTER's `.rb` files and skips `law/`, `core/`, `test/` and
`spec/`, so it reports zero here and means only that.

**19 one-file directories against a ceiling of 20**, all of them mandated: OS install
paths, Zeitwerk, ports fixtures, OmniAuth, PWA, and dilla vocal, render and stem
takes. The row reads one under and the ceiling is not MASTER's to lower — it counts
all four trees. Read the live figure from `MASTER/bin/pub4 measure`, not from here.
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
extension.** A 2026-08-03 sweep deleted `lib/pub4/status_report.rb` as an orphan and
broke `MASTER/bin/pub4` for six days: the grep matched only `*.rb`/`*.yml`/`*.md` and
`MASTER/bin/pub4` has no extension, and it ran from `MASTER/`, where `bin/` does not
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
`bin/pub4 measure`, which is the mistake the header of this section warns about. It
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

Same family as `Pub4::OperatorDocs::ROOT`, recorded above at four levels instead of
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
  and 86 carrying no detector field. The lexical hatch is deliberately idle and
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
are named by a Rakefile task, a test, a gate, `bin/pub4` or a workflow. The
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
path strings "still resolve via `MASTER/lib/pub4/paths.rb`", in the present
tense, about a file that does not exist; they resolve through
`RAILS/shared/lib/pub4/deploy_paths.rb`, which is what `Pub4::DeployPaths` is.
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

### Tier 1 — closed, verified 2026-09-08

Five entries here named a schema and a model that nothing read or wrote. All
five were wired, and every reader was found again on 2026-09-08 rather than
taken from the note: repost through `RepostsController`, the `button_to` in
`shared/_action_bar` and the `Current.reposted_post_ids` memo; watch time
through `Tv::ViewEvent#record_progress!`, the `tv/view_events` endpoint, the
`tv-player` video target and `Tv::Video::WATCH_TIME_SQL`; saved-search alerts
through `SavedSearchAlertJob`, scheduled every thirty minutes in
`brgen/config/recurring.yml`; courier dispatch through
`Takeaway::Order#transition_to!` calling `DeliveryDriver.nearest_free`, drawn
by `Maps::HomeController#courier_layer`; and mentions through
`Shared::Mentionable` on `Post`. The seven test files those entries name run
sixty-seven tests, all green. The records are deleted; `git log` holds the
reasoning.

One line of 1.5 was wrong when it was written, and it is the finding worth
keeping. It said `Stream` still has no writer and that the table stays. No
`Stream` model and no `streams` table exist anywhere in `RAILS/`.
`Tv::LiveStream` is the table it meant, and it has a full writer —
`Tv::LiveStreamsController` creates, updates, destroys, `go_live!` and
`end_live!` — with `vertical_forms_test.rb` posting the real form and
asserting the row. What is absent is the media half: `apps.yml` records the
model done and notes "no WebRTC/RTMP", so ingest is Tier 2 work rather than an
unwired column.

---

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

### Two stylesheets over their length ceilings

`RAILS/test/file_length_ratchet_test.rb`, the one red file left in the
standalone suite. `limits.yml`'s rule holds here too: a breach is paid by
extraction or deletion, never by a bigger number.

    shared/app/assets/stylesheets/_zen_shell.scss        502 / 477   (+25)
    brgen/app/assets/stylesheets/_messenger_window.scss  446 / none declared

`user_flow.rb` and `rendered_geometry.rb` left the list on 2026-09-09,
`deploy_backlog_test.rb` and `design_metrics.rb` on 2026-09-10 — the second by
folding thirteen check_* call lines into the symbol list its check count now
reads, 345 → 342.

**Both that are left are stylesheets, and that is why they are still here.**
Splitting a partial moves it in the cascade, and every candidate cut in
`_zen_shell.scss` is argued out below and still ends "wants the owner's yes".
`_messenger_window.scss` has no ceiling at all, which is the shape the
counterpart half of that test exists to make visible; recording one would admit
its current length rather than measure it, so it waits on the same yes.

**`_zen_shell.scss` is not an extraction, and that is the finding.** Its rules
reach the apps through one `@forward` in `_stack_brgen.scss`, so source order
is cascade order, and Sass allows `@use`/`@forward` only at the top of a file.
A partial lifted out of the middle lands after everything that followed it. The
only order-preserving split is head/forms/tail — three files, two of which are
named for a position rather than a subject. The forms block (`.input-group`,
`.field--float`, `.dropzone`, the direct-upload and error families, `fieldset`)
is the subject that is there; taking it needs the owner, because this repo says
restore or ask and never invent a layout change.

**The deadlock that kept this list alive is gone.** It read: `file_length` is
per file and wants a split, `growth.rails` counts files and was thirteen over,
so every split deepened an overage nobody could account for; a raise was
forbidden by both. `growth.rails` is at its ceiling now, with each of the
thirteen named in `spine.yml`, so a split costs one nameable line instead. Two
were paid that way on 2026-09-08 and left the list:

- `deploy_backlog_test.rb` 631 → 557. Playlist import, track ownership, hosted
  tracks and set likes are `playlist_wiring_test.rb` — four contracts that
  arrived one at a time and read as one subject, out of a bundle of forty.
- `gates/support/cdp_session.rb` 339 → 288, off the list outright. Finding
  Chrome, launching it, waiting for `DevToolsActivePort`, discovering the page
  target and reaping the process are `chrome_process.rb`; what is left speaks
  CDP to a browser that is already running. The first split, in August, took
  the RFC 6455 half. Verified against a real Chrome — viewport, headers,
  cookies, navigate, status, evaluate, a computed style, a bounding rect, a key
  press, console capture, a screenshot and a thrown `JsError` — identical
  before and after, and both timeout paths driven to prove `CdpSession::Timeout`
  rather than the stdlib `Timeout` the first split had to learn about.
- `gates/lib/research/design_metrics.rb` 462 → 345. Input size, heading
  hierarchy, the weight ladder, font families and lowercase tracking are
  `design_metrics/type_checks.rb`, a module included back into the gate like
  `ContrastChecks` beside it. Every one of them reads a font declaration out
  of the SCSS and judges it against typography.

**The diff standard this file set is what caught the real defect**, and it was
not in either split. Running the gate's whole sorted output against the tree
before the change showed one extra line — `no ceiling recorded in
css_budget.yml`. Moving `contrast_checks.rb` into `design_metrics/` the day
before had broken `File.expand_path("../data/css_budget.yml", __dir__)` for the
second time, in the same method whose comment records the first: the gate ran
unbudgeted and still reported ok. The path is anchored on the gates root now,
and `gate_live_and_css_budget_test` asserts that all four budget readers —
design_metrics contrast, css_constitution rules, css_constitution weight,
constitutional_scan targets — return something. **The ceilings existing in the
YAML and the gate reaching them are two facts, and only the first was ever
asserted.** Proved by mutation: restore the old path and the test goes red.

Two left the list on 2026-09-06, and only one of them by extraction.
`page_inventory.rb` went 444 → 288 by **deletion**, which is the note worth
keeping: it carried five filename ladders for resolving a view's URL, under a
comment inviting their removal "when the route table proves it redundant, not
before". Counted rather than assumed — the ladders were reached three times in
a full 204-page run, twice for the same view — and the two views they answered
turned out to have no GET route at all, so the fallback was inventing URLs and
sending `page_simulation` at them. A file over its ceiling is sometimes a file
doing something it should not do.

The reading that transfers: measure how often a fallback is taken before
extracting the file that holds it. Three calls out of 204 is not a fallback,
it is a residue.

**The remaining three carry nothing dead, measured 2026-09-06.** A Prism census
over every method finds zero with no caller.

Two instrument errors while measuring that, both the same family and both worth
not repeating. A dead-method census reported eleven methods with no caller; the
first eight were predicates, where the `\b` after `Regexp.escape("fractional?")`
demands a word character after the `?` — the fourth time `\b` next to
punctuation has cost something here. The other three were reported dead because
the lookbehind excluded `.`, so a method reached only as `receiver.name` read
as unreachable. Eleven findings, zero real.

### One model nothing writes

Found 2026-09-05 while giving the nine promiseless models their reason, and
worth its own record because the marker on each said "nothing writes it", which
is a finding rather than an exemption.

- **`Stream` — dropped 2026-09-06.** It was the pre-Active-Storage way to hang
  a media file off a post: `url`, `content_type`, `duration`, created in the
  first schema batch ten minutes before `posts` existed, never written. Three
  models had taken the job — `Post has_one_attached :image/:video/:audio` with
  `Shared::MediaProcessable` for uploads, `Playlist::Track` (`SOURCE_TYPES`
  upload/youtube/spotify/soundcloud/whyp/direct/dilla) for audio hosted
  elsewhere, and `LinkPreview` for a pasted URL — with `Tv::LiveStream` and
  `Tv::StreamChat` owning live video. Wiring it meant a second media path
  beside Active Storage, which is what `ONE_SOURCE` forbids.

**`Mention` was the second and closed the same day** (`a05def16c`).
`Shared::Mentionable` writes the rows from `@username` in title and content and
notifies each named user, which is what `Notification::KINDS` and the
notifications controller's group order had been promising while `Post has_many
:mentions` stayed empty. It carries a real validation now rather than the
marker: one row per named user per post, which is the promise `mention_test`
makes twice and which no unique index enforces.

`Tagging` was the third candidate and is not one — verify the instrument before
the finding. A grep for `Tagging.` and `taggings.create` finds only readers,
because the writer is `self.hashtags = tags` inside
`Shared::Taggable#sync_hashtags`, an `after_save` on every post. An association
assignment writes the join row without ever naming its class.

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
`MASTER/lib/pub4/status_report.rb` counts it and a deploy contract test
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

#### 1. `_zen_shell.scss` does have a subject-named split, and the button family is it

The standing note above says the only order-preserving split is head/forms/tail.
That was reasoned from "source order is cascade order", which is true only
between two rules that can match the same element *and* set the same property.
Measured rather than assumed: a script walked the 104 top-level blocks, recorded
each block's selector tokens and declared properties, and reported every ordered
pair sharing both. **37 pairs out of 5,356 possible pin the order.** Everything
else in the file is free to move.

The `.btn` family at lines **94–160** — `.btn`, `:hover`, `:disabled` and
`[aria-disabled]`, the four compound variants and `.btn-sm`, with the comment at
126–132 that explains the compound-specificity contract — is pinned to itself and
to nothing outside itself. Fourteen of the 37 pairs are internal to it; none
crosses its boundary. Lift it verbatim into `_zen_buttons.scss` and it pays 67
source lines against a +25 overage, named for its subject.

Specificity closes the gap the pair list cannot. The only other rules in the file
that a `<button class="btn">` matches are `*, *::before, *::after` at 4–8,
`input, button, textarea, select { font: inherit }` at 28–30 and `:focus-visible`
at 45 — 0-0-0 and 0-0-1 against `.btn`'s 0-1-0, so they lose whatever the order.
Every `.btn` mention in the file is inside 94–160 or inside the two media blocks
below.

One position constraint, and it is the whole of the surgery. `_zen_shell.scss`
also names `.btn` inside `@media (forced-colors: active)` at 598–605 and
`@media print` at 607–624. Print uses `!important` and does not care; the
forced-colors block is 0-1-0 against the base's 0-1-0 and must stay later. So the
new partial is `@forward`ed **immediately before** `zen_shell` in both
`_stack.scss` and `_stack_brgen.scss` — after `animations`, which keeps it later
than `_layout_chrome.scss:107` and `_minimal.scss` (whose line 291 records that
zen_shell's position is the one that wins) and earlier than zen_shell's own media
overrides. Nothing moves, nothing is renamed, no value changes.

Two further blocks report zero pairs — the feedback family `.empty-state*`,
`.skeleton`, `.toast*` at 174–222 and `.tooltip*` at 257–279 — and **do not take
that verdict**, because the instrument compares property names and does not know
shorthand from longhand. `.toast:215` sets `border` and `.toast--success:221`
sets `border-inline-start`; different names, one cascade. `.empty-state*` also
appears in `_empty_state.scss`, forwarded after `zen_shell`. Either would need a
shorthand-aware pass first.

Confidence: the pair list is a lower bound. It matches selector tokens exactly,
so a compound or prefix relation between two classes that never share a selector
is invisible to it, and it does not see shorthand/longhand or inherited
properties. The button family survives all three gaps for a checkable reason —
every variant selector literally contains `.btn`, and the specificity argument
above covers what the pairs do not. The extraction is still a structural move and
wants the owner's yes, because the house rule is restore or ask.

#### 3. Reading order — the five lints are done, the gates cases are not worth it

The five `Pub4::*Lint` modules read entry first now. Each was reordered on its
own and checked the same way: every lint's findings and counts snapshotted to
JSON before the first move and compared after each, byte identical throughout.
`scale_lint`'s first attempt raised on require — the module's closing `end` was
inside the slice being reordered, so `REPO_ROOT` landed in `module Pub4`. A
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

#### 4. The sign-in screen is written three times, and two of the copies lack something

`{amber,brgen,bsdports}/app/views/sessions/new.html.erb`, 27–38 lines each, 74%
of their non-comment lines shared, with no shared counterpart —
`shared/app/views/sessions/` does not exist, though `Shared::SessionsActions` is
the controller and all three `sessions_controller.rb` are five-line shims onto
it. Two differences remain, and only one of them is behaviour:

- bsdports offers no create-account link at all; amber links
  `new_registration_path`, brgen `new_user_path`.
- brgen uses `.field--float`, the other two plain `.field`. That is the
  deliberate visual difference and is not for an agent to unify.

Record the create-account link as behaviour; the consolidation into
`shared/app/views/sessions/new.html.erb` with the field wrapper as a local is a
second step and needs the owner, because it moves markup.

#### 5. `rendered_geometry.rb` sits exactly on its own raised ceiling

It is 344 code lines against a 344 ceiling and a 300 general limit, across 20
`check_*` methods, so the next check breaches. A Prism census found nothing
dead and a fresh grep finds no twin of `fractional?`, `on_rhythm?`,
`expand_hex`, `collect_hexes`, `rect_gap`, `undersized?`, `inline_target?`,
`critical?` or `token_palette` anywhere in the repo, so the payment is
extraction. The shelf with the clearest edge is the colour group —
`check_token_conformance`, `token_palette`, `collect_hexes`, `expand_hex`,
about 40 lines answering one question, extractable as
`rendered/rendered_geometry/token_checks.rb` and included back in exactly as
`design_metrics/type_checks.rb` and `contrast_checks.rb` already are.

Sequencing, since `growth.rails` is at 2374/2374 and `.md` counts toward it: a
split costs one file, and `RAILS/INSTANT.md` is one to spend. It is 304 lines of
forward proposals at a tree root, referenced by nothing in the repo, while the
repo rule is that every per-tree backlog folded into this file. Fold it into the
forward-work section and delete it, and the button partial and the token shelf
are both paid for.

#### 6. `shared/lib/pub4/` wants a `lint/` shelf, and it costs no files

13 of the 20 files in that directory end `_lint.rb` — 2,819 lines — and the other
seven are `deploy_paths`, `ci_guard`, `load_average`, `master_design`,
`baseline_ratchet`, `dialect_token_drift_check` and `importmap_preload_audit`,
which are not lints. `MASTER/tools/cohesion.rb --census --tree=RAILS --list`
proposes the regroup and it is the largest of the sixteen it finds. Moving files
into `pub4/lint/` leaves the count unchanged, so the ratchet is neutral; the cost
is renaming `Pub4::ScaleLint` to `Pub4::Lint::Scale` and following it through
`MASTER/tools/ratchets.rb:318-327` (which derives the constant from the basename
at line 360, so that mapping changes too), `shared/config/ci.rb:53-60`,
`gates/lib/source/scale_ratchet.rb` and nine test files. Worth doing, but it is
an afternoon and it touches a MASTER ratchet, so it is not a first move.

#### 7. Smaller, verified

- `shared/app/services/scrape.rb` defines bare top-level `Scrape` from an engine
  autoload root, called from six places in two apps. It works, but the engine
  puts 19 files at unnamespaced roots, and one of them has already lost a
  collision silently. The `Application*` five must stay
  bare by Rails convention; `scrape.rb`, `site_verification.rb`,
  `schema_helper.rb` and `passwords_mailer.rb` need not.
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
  documented at `shared/lib/pub4/asset_url_lint.rb:48-60` and verified still
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

The `rendered_*` and `live_*` families need a booted fleet and the fleet was not
booted, so `rendered_suite` and its eleven leaves, `user_flow`, `first_screen`,
`surface_schema`, `flow_journey`, `page_simulation`, `deploy_drift`,
`human_walkthrough`, `visual_contract` and `gate_mutation` are unmeasured here.
So is per-app `bin/ci`: RuboCop, Brakeman and the app test suites want each app's
bundle and a migrated database, and this worktree has neither. The
`_zen_shell.scss` split wants `RAILS/bin/triangle up` and a full
`rendered_suite` before it is called done.

---

## OPENBSD

### Operator debt — still open

Each item carries a hidden HTML-comment marker on its own line under its heading;
`MASTER/lib/pub4/operator_docs.rb:55` counts those markers for the
`MASTER/bin/pub4 status` debt line, so keep exactly one per open item.

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
(`RAILS/gates/lib/host/dns_zones.rb:69`), so no count of expired city domains
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

#### 1. Ten files on the box are not the files in this repository, and one OPERATOR.sh run closes every one

Re-measured 2026-09-10 with `SSH_HOST=dev@brgen.no ruby
OPENBSD/config_drift_gate.rb --remote`, which is now the way to ask. It is not
two files, which is what this row said until today. Eight differ —
`etc/doas.conf`, `etc/newsyslog.conf`, `etc/rc.d/master`,
`usr/local/bin/config-drift-check`, `drain-jobs.sh`, `prune-guests.sh`,
`relayd-watchdog` and `uptime-check.sh`, the last of those 914 bytes live against
2,877 in the repo — and two are absent from the box altogether:
`emergency_cpu.sh`, which is the only thing `resource_guard.sh`'s crisis tier can
run, and `vps_weekly_integrity.sh`. In every case the repo is the newer side, so
there is nothing to copy back.

Root's crontab is the eleventh and it hid the longest. `crontab.vm23:97`
schedules `/usr/local/bin/vps_weekly_integrity.sh`, `OPERATOR.sh:311` installs
it, and the box has neither the line, nor the file, nor `/var/log/pub4/` for it
to write into — so the weekly integrity pass has never run once, while every
`/etc` file the drift gate compared matched and it said clean. The gate now
compares the crontab too, as a set of commands rather than bytes (OPERATOR.sh
merges the pub4 lines onto OpenBSD's own, so a byte compare would always fail),
scoped to `/usr/local` so the four base-system lines are not four permanent false
alarms. `test/test_config_drift_gate.rb` carries the shape it must flag and the
shape it must not.

The script itself was wrong in two ways and is fixed, so the OPERATOR.sh run
installs something worth running. It ran entirely as root out of root's crontab
and its first act was to source `lib/ci_lock.sh` from the dev-writable checkout
and then run two Ruby programs from it — the escalation `OPERATOR.sh:316` refuses
for `config_drift_gate.rb` and `crontab.vm23:42` refuses for `uptime-check`; root
now makes the log directory, opens the log and drops to dev, and reads not a line
of `/home/dev/pub4` as root. And a bare `set -e` meant a failing integrity gate
ended the run before the public health pass, on exactly the week something was
already wrong, with the output redirected so cron had nothing to mail; both gates
now run and the exit status carries the result.

Nothing here can install any of it. `MASTER/bin/pub4 vps deploy` does not do it
either — this is `doas zsh OPENBSD/OPERATOR.sh` on the box.

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

What is left is one live taste and two real bugs, all three mix values and
therefore the owner's:

- **`RENDER_BEAUTY_MIN` is two floors on two gates.** `stream_iterate_acceptable?`
  takes 65, `render_quality_acceptable?` takes 70, and under `DILLA_STREAMING`
  the second one takes `STREAM_BEAUTY_MIN`, which is 68. Three numbers, all live,
  and choosing among them is choosing a sound.
- **The `HARM_VOL` bump is a pass behind itself.**
  `composition_engine.rb`'s listening loop raises harmonic gain when the render
  is too quiet: `ENV["HARM_VOL"] = (ENV["HARM_VOL"] || "2.4").to_f + 0.05`. On a
  run where nobody set `HARM_VOL`, 2.4 plus 0.05 is exactly the 2.45 the engine
  already defaults to, so the first correction changes nothing and a three-pass
  loop gets two effective bumps. Raising the base to 2.45 is the fix and it is a
  mix value.
- **The stream's harmony walk destroys a pinned `EVOLVE_HARMONY_W`.**
  `stream_iterate_evolve_harmony!` writes `ENV["EVOLVE_HARMONY_W"]`
  unconditionally, so a value the operator pinned is gone after one iteration.
  That is the shape `USER_PINNED_ENV` exists for and which the `BPM` code already
  checks; honouring the pin changes what a stream renders for whoever pinned it.

### Rescues that lose a measurement, and the rule that cannot see them

`SILENT_RESCUE` (`MASTER/lib/review/scan/rules/lexical_rules.rb`) reads lines that
begin with `rescue`, so a modifier `rescue` and a `rescue` whose whole body is
`next` are counted by nothing. Extending the rule to both forms is a MASTER
change, not a STUDIO one, and it is the half still open.

The three that lost something real are fixed and none of them changed a render on
the path where nothing raises. `cross_sample_convolve!` measured the source and
the convolved bed behind `rescue nil`, so a failed measurement left `trim` at 0.0
and the `dmesg` beneath printing "matched dB → dB" with both numbers gone; the
rescue stays, an unmatched bed being better than no bed, but it names which
measurement would not take, and the matched and unmatched lines are now two
different sentences. `bin/sine_stream_player.rb` swallowed a failed archive move,
which made the same take play forever because the loop picks the first file in
the queue each turn. `live/recall.rb` dropped an unparseable journal row in
silence, which is how a pass that happened gets reported as "no seeded passes
yet". The five loop-control ones — `lib/music_gems.rb:200`,
`lib/harmony_engine.rb:362`, `bin/demo_full.rb:42`, `bin/sine_stream.rb:1830` and
`lora/_toolkit/run_train_kaggle.rb:144` — each skip a member of a loop and are the
least alarming shape.

**Narrowing a blanket rescue is still the owner's**, and it is now the only half
left: the three clauses that named a class already covered by `StandardError`
(`lib/master_heuristics.rb`, `lib/music_gems.rb`, `lib/verify_fx.rb`) are down to
`StandardError` alone, which the `music_gems` one also needed for a second reason
— resolving `::Coltrane::ChordNotFoundError` while handling an exception raises a
NameError of its own where the gem is absent. `lib/seed_providers.rb` now says
when a USGS or open-meteo fetch fails, so an operator who asked for a seeded swing
can tell whether they got one. The remaining discards are optional gem probes,
external binaries whose output is parsed, optional state files and process
teardown, and they are correct as they stand.

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
- **`dup_census` excludes `STUDIO/`** with no comment saying why
  (`MASTER/tools/dup_census.rb:30`), against a header claiming every tracked file.
  What the exclusion hides is 3 duplicate sets, 13.9 KB, all legitimate. Worth one
  comment, not a campaign.
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

- **Seed realism.** Coordinates and timezones for every DomainRegistry city
  live in `CitySeed::COORDINATES` / `TIME_ZONES`. Population has no column and
  no seed.
- **Bringhurst typography codification.** Turn the typographic rules the design
  system already half-follows into enforced tokens and a gate, rather than
  convention.
- **The layout pass.** Roughly 178 proposals from a study of joi.com, kimi.com
  and medium.com, worked one category at a time; about sixty are closed. Its own
  section below carries the state and the doctrine it produced.
- **Web-face redo.** The MASTER web face (WebGL + TTS) wants a rebuild; see the
  web-face notes in the MASTER debt records for the current failure map.
- **README consolidation.** The per-tree READMEs overlap and drift; one pass to
  make each the single maintained long-form reference for its tree.
- **`tree.rb` on entry.** Run the tree map on session entry so an agent orients
  from the real layout rather than a remembered one.
- **Onboarding.** A first-contact path that gets a new agent or contributor from
  clone to a green check without reading every contract.
- **Local-LLM fallback.** A path that keeps the runtime working when no API key
  and no `claude` CLI are present. `models.yml` declares a local tier gated on
  `OLLAMA_BASE_URL`, but only `review/embeddings` and the boot receipt read that
  variable, so no chat path falls to it.
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

Counts are what remained when each category was last read; re-measure before
working from one.

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

### Still open, each verified 2026-09-09

- **A shared display-type slot is unbuilt.** `_vertical_marketplace.scss:42`
  outranks `_typography`'s page-title rule by matching an id, and the comment
  above it carries the workaround under protest. A hero wants to opt out by
  name.
- **`.deal-cat` keeps a border nothing explains.** `_marketplace.scss:48` sets
  `border: 1px solid var(--border)` where the 2026-08-04 decision traded control
  borders for surface fills. Changing it moves rendering across marketplace,
  stores and takeaway at once, so it is a decision rather than a lint fix.
- **playlist forks two scales.** `--edge-soft` and `--edge-strong` are the donor
  a shared edge scale wants, and `--font-mono: "SF Mono"` is a fifth typeface by
  accident (`_vertical_playlist.scss:9,11,16`).
- **`WORN_TYPE.profiles.map.label_min_px` has no reader.** Declared at
  `rules.yml:3364` and read by nothing. `data_reach` counts top-level keys only,
  so no instrument sees a nested one.

## From the 2026-08-31 session

- **`rules.yml` refactor.** Aggressively DRYing the law wants a measured pass.
  The two things holding it — a down gate and a mis-scanning scanner — closed on
  2026-09-01, so only the work remains.
- **`dilla.rb` is 35,142 lines**, against `lib/`'s 44 files and 15,894 lines, so
  the monolith still holds 69% of the engine. Split along the seams it already
  has: the renderers, the ENV default tables, the SMF writers, the patch
  registries. The direction is out of the monolith, not into it.
- **Do not flatten `STUDIO/dilla/renders/` into the dilla root.** Counted before
  doing it: `slum` emits fourteen files, `loose_pocket beats` twenty-eight, plus
  `foundry_pulse.mp3`, `hate_session.mp3`, `ALBUM.mp3` and `beat.wav` — about
  forty-six named files, before the contents of `renders/{wav,demo,mastered,
  beats,rescued}/`. The root holds `demo.wav`, `demo.mp3` and `loop.wav`, and
  CLAUDE.md says build output never sits there, recording the session whose
  renders lived at the root for weeks. Two instructions pointed opposite ways
  and the count settles it: `demo.wav` in the root is the demo's own path and is
  already how `demo_all` defaults; every batch renderer keeps `renders/`.
- **Merge the three techno renderers.** `render_industrial`,
  `render_hate_techno` and `render_techno` share `techno_harmony_roots` and the
  schedule builders but hold genuinely different arrangements. Read all three
  before cutting; merging on surface similarity flattens the arrangements into
  one sound.

## From the 2026-09-01 audit

- **Live RAILS gates still measure too little.** `user_flow`, `first_screen`,
  `payment_honesty`, `content_honesty` and several rendered gates skip when the
  app ports are closed. Run the suite once with `GATE_REQUIRE_LIVE=1`,
  `GATE_STRICT_INCONCLUSIVE=1` and `GATE_STRICT_ERRORS=1` on a host where brgen,
  amber and bsdports are listening, then record any findings that only appear
  live.
- **`bin/sine_stream.rb:975` is the last un-oversampled `asoftclip`.** Every
  other saturation site runs `oversample=4` or `8`, and dilla's README says the
  rule reaches every real `asoftclip=type=` filter string; this one runs the
  ffmpeg default and aliases above Nyquist. Left alone deliberately — it changes
  how the stream sounds, which is the operator's ear. Worth an A/B before it
  moves.
- **The 61-track crate fetch was abandoned at 2.** `~/dilla-crate-incoming`
  holds two FLACs and three fetch scripts from the 2026-08-31 rebuild, which
  finished by another route into `samples/chopped/`. Either resume that fetch
  deliberately or delete the staging directory; a half-finished download beside
  a finished crate reads as the crate.
- **`chmod 555 /etc/rc.d/master` cannot survive its own installer.**
  `OPERATOR.sh:196` sets it and the loop at `:198` chmods every `/etc/rc.d/*` to
  755, yet the box runs every app rc.d at 555. Both lines came from the same
  original split and neither reading is contradicted by a comment or a RUNBOOK
  line, so the intended mode is the operator's call. Found 2026-09-02.

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
a finding is a hypothesis until the instrument has been checked.

### The instrument

- **`bin/pub4 measure` cannot say why a row moved.** There is no `--why` and no
  `--since`: three censuses record their members and the rest record a bare
  integer, so "OVER +826" cannot be attributed and a session cannot diff its own
  effect on the ceilings before pushing. Done when `--why <row>` prints the
  members behind a number and `--since <ref>` prints every row's delta against a
  commit.
- **A silent detector still reads like a clean tree.** `bin/pub4 rule <ID>
  --corpus all` answers that one rule at a time; nothing reports the set. Done
  when `bin/pub4 measure` marks the rules that fire nowhere in the fleet beside
  their ceilings.

### Gates

- **`RAILS/gates/gates.yml` declares neither a gate's cost nor what it needs.**
  `constitutional_scan` spent 48 minutes on brgen alone inside a model round trip
  (measured 2026-09-06, recorded at `lib/meta/constitutional_scan.rb:23`) and
  `rendered_suite` monopolises a Mac for an hour; `runner.rb` prints nothing
  before starting either. Done when each row carries its cost and its
  preconditions, `runner.rb` prints them first, and the ledger records each
  gate's wall time, so a gate that doubles is visible before it is unrunnable.
- **Nothing automated runs the gates at all, which is the bigger half of the
  `GATE_STRICT_INCONCLUSIVE` entry.** `runner.rb --all` now closes with each
  inconclusive gate's reasons, names any gate that failed while listing no
  finding, and bounds every subprocess through `gates/support/bounded_command.rb`
  — but measured 2026-09-10, neither `OPENBSD/vps_ci.sh` nor `OPENBSD/bin/vps-deploy`
  invokes the runner, and `shared/config/ci.rb` never did either. The only
  callers are `OPENBSD/bin/check`, `check-openbsd`, `check-rails` and
  `MASTER/bin/probe`, all of which a person types. So the fifty-one gates are an
  operator tool, and the twenty-seven that could report a pass having measured
  nothing had been failing to measure in a tool no pipeline runs.

  Setting a strictness flag is therefore the wrong shape of fix. The question is
  whether the deploy should run gates at all, and that is an operator decision
  with a real cost: the box is one core, the live gates want the apps up, and a
  deploy that runs them is a deploy that takes minutes longer. Decide that first;
  the flag follows from it in one line either way.
- **`bin/pub4 gate --tree <TREE>`** — the ladder scoped to one tree, for the
  common case of working in one. Today it is all four or nothing.

### STUDIO

- **`MELODIC_LEAD=1` and `SCALE_LEAD=1` resolve and produce no lead.** Both
  switches are read, all four lead lanes return empty, and the render reports
  "lead: none". Done when a lead is audible under those switches, or they go.
- **`FLYLO_QUINT_HATS` is read by nothing under either prefix**, and the quint
  assertion in `STUDIO/test/test_dilla_engine_probes.rb:2067` passes because
  quint is never scheduled at all. That test's own comment points at this entry.
  Done when quint is wired, or the switch and its assertion are deleted together.
- **`DILLA_OUTPUT_DIR` defaults to `Dir.pwd`** at `STUDIO/dilla/dilla.rb:143`,
  which is how one session's renders lived at the repo root for weeks. Done when
  the default is `STUDIO/dilla/renders/` and a stems render lands under
  `renders/<seed>/stems/`, where the gitignore already expects output.
- **138 dilla ENV switches default off and are unclassified.** `DILLA_FULL` turns
  on the eighteen additive ones. Done when the rest are sorted into additive,
  exclusive fork and operational, and the dead ones are deleted rather than
  renamed.

### RAILS and MASTER

- **`NO_GOD_CLASS` is the fleet's largest single piece of design debt, and it is
  growing.** `RAILS/brgen/lib/brgen/bergen_demo_seeder.rb` is 902 lines against
  the 834 recorded on 2026-09-06; `brgen/app/models/conversation.rb` is 356 and
  `brgen/engines/takeaway/app/models/takeaway/order.rb` is 285. One decomposition
  at a time, measured against `MASTER/data/self_findings.yml`.
- **`MASTER/bin` holds 27 executables against a ceiling of 27.** `check`, `gate`,
  `ci`, `audit`, `dogfood`, `preflight`, `probe`, `smoke`, `smoke-web`, `doctor`
  and `nsaudit` are eleven doors onto one ladder, and `CLAUDE.md` says two
  surfaces, no third. Done when `entrypoints.master` falls by folding rather than
  by raising the ceiling.
- **An agent cannot read one rule cheaply.** `bin/pub4 rule <ID>` prints
  findings; it prints neither the rule's fixtures nor the exemption it carries,
  and the exemption is the half that gets broken. Done when it prints both, in a
  `--json` form as well, so an agent can hold the rule instead of 4,000 lines of
  YAML.

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

