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

What is open is one file and it is not a placement question. **`ground/unified_diff_editor.rb`
has no caller outside its own test** in any of the four trees. It parses, summarises
and builds unified diffs and nothing asks it to; `code_reach` reads it as reached
because the test names the constant. It belongs with the unwired declarations below —
the question is what was meant to apply a diff through it, not whether to delete it.

Two cautions for whoever moves the next file. A move is a constant rename, so check
for callers that write the bare name inside the same module first — `PressureEngine`
looked dead to a qualified-name census and is constructed at `MASTER/lib/builder.rb:165`
on every full boot, though not under `Builder.build_fast`. And re-base the source and
destination `loc_body_budgets` keys in the same commit, by the body lines that moved
and no more: the sum has to be zero, because a move pays nothing toward a breach.

### Waiting on an operator decision

Each of these is a call about money, taste or ownership. None is a defect and none
should be closed by an agent's judgement.

- **The face reads as a shadow at its own defaults, and the README take does not.**
  `RAILS/gates/probes/face_loop_record.rb` records it with `uColor` pinned to 3.4 and
  `uExposure` to 2.8, because a 360-pixel README embed of dim grey dots on black
  reads as nothing at all. Receding points sit at `shade = mix(0.14, 1.0, depth)` in
  `face.part2.txt:164`, so most of the face is painted at a seventh of full brightness
  before alpha. **The decision is whether the live face should move with the
  recording.** `design_tokens.yml`'s `face_root.anchors` is pinned by a production
  gate, so the change is not free. If the answer is yes, the honest fix is the
  shader's floor rather than a uniform the recorder happens to hold.
- **Whether the one scheme keeps an accent.** `magic_hex` is ratcheted at 77 and
  `contrast_below_aaa` at 37, of which the bulk are `--danger`, deliberately the one
  non-grey. `vertical_accents` still gives marketplace, tv, dating and the rest their
  own ink. **The decision is whether one accent survives for interactive
  affordance** — a link with no colour needs an underline instead.
- **The deploy.** See the box state below; nothing is blocking it.
- **Three rule statements are the constitution's wording.**
  `rule_hygiene.statement_conflicts` is 3 of 3. `BE_CONCISE`, `PRESERVE_FIRST` and
  `SIMPLEST_WORKS` each have a soul-derived `practice` in `law/practice.rb` saying
  something other than the kernel rule of the same name: `BE_CONCISE`'s practice is
  "minimal response", about the voice, against "omit needless words, omit needless
  code", about the source; `SIMPLEST_WORKS`' practice is "refuse to create god
  classes", which is `NO_GOD_CLASS`' subject and severity. **Resolving one deletes or
  renames a statement that reaches the system prompt.**
- **`SILENT_RESCUE` 26 belongs to dilla's owner.** Every one is in STUDIO and
  nineteen are in dilla, where a `rescue StandardError` around an optional gem call
  is load-bearing for a render. Narrowing one on my own judgement is the change this
  repo's own rules say not to make.
- **`STUDIO/dilla/live/` is eight files and reads like one subject** — `rack.rb`,
  `recall.rb`, `dig_crate.rb`, `dig_crate.sh`, `broadcast.sh` and three `*.als.rb`
  Ableton writers. Folding it is the obvious win and it is not an outsider's to take:
  these render real audio.
- **`growth.rails` taxes a test at the rate it taxes sprawl.** The row cannot tell a
  new test from a new god class. The fix is two rows per tree, source and test, so
  sprawl stays resisted while coverage is free to grow. **Splitting a ratchet re-bases
  four ceilings** and wants its own sitting.

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

*The root cause is upstream of the lock.* `MASTER/Gemfile:47` guards
`rb-kqueue` behind a runtime `if RUBY_PLATFORM =~ /bsd/` rather than a
`platforms:` or `install_if` block, so the lockfile is host-dependent by
construction: a Mac evaluating that Gemfile never declares the gem, and no
`bundle lock --add-platform x86_64-openbsd` can add it. That is why the box's
lock must stay divergent, why `--ff-only` only works while no commit touches
it, and why frozen mode keeps colliding with it. Fixing the Gemfile is what
closes this properly.

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

### The ratchets that are off — measured 2026-09-10

`MASTER/bin/pub4 measure` reports two rows off. Read it there rather than here; this
list goes stale in a day and has done so repeatedly.

    spine.lib_body_ceiling   38209 / 37464   OVER +745
    growth.studio              146 / 153     SLACK -7

`spine.lib_body_ceiling` has its own section below and is the one real debt.
`growth.studio` is seven files under, and it is STUDIO's to ratchet rather than
MASTER's: the row is measured in a shared checkout with dilla work live in it, and a
low recorded from another session's tree is the mistake this file records twice
already.

`self_findings.law` and `sprawl.lone_dirs` read slack by eight and one, and neither is
MASTER's either. Both count across all four trees, three of which had sessions in them
the day this was measured.

### Line budgets: eight of twenty-four over, and `law/` is nearly double

`rake loc_budget`, measured 2026-09-10:

    law           1613 / 852      lib/review   10456 / 9765
    lib/voice      3395 / 3181    lib/trace     2035 / 1999
    lib/pub4        696 / 470     lib/core       762 / 682
    lib/boot        276 / 227     lib/ground    4904 / 4896

`lib/io` came off this list by deletion rather than by a bigger number, which is what
`limits.yml` asks for: `Io::Gateway::Adapter` was a contract module nothing included,
and which would have broken any adapter that did include it, so five body lines closed
a four-line breach.

**The other eight were read for something to delete and there is nothing.** Not a
refusal to look. `CrossFileAnalysis` over `lib/` and `law/` together reports one
copy-paste block and four `DRY` structural pairs, and no clone inside any over-budget
directory: the pairs are `markdown_files`/`files`, `read_js`/`read_erb`,
`grade_for`/`band_for`, and two five-line `deep_merge`s in `ground/config.rb` and
`cognition/state.rb`. Collapsing all four saves about thirty lines against an overage
of two thousand, and the `deep_merge` pair costs `cognition` a dependency on `ground`
to save four. `code_reach` is 0 of 405 and the largest method body in `lib/` is 20
lines. The two biggest files in `lib/review` are registries of `RuleDSL.rule` calls,
where shrinking means deleting rules, and `law/practice.rb` at 558 is the same shape
one layer up: rules carrying a statement, a fix and two fixtures each, which is the
form `law/law.rb:210-215` enforces structurally.

So these eight record real growth, and each wants the sponsor `spine.yml` describes —
a commit naming what the lines buy — rather than a sweep. `lib/ground` at eight over
is the exception in kind rather than in size: it is another session's eight lines,
sitting above a ceiling re-based twice for moves, and it closes the day anything at
all leaves that directory.

### `spine.lib_body_ceiling` cannot be paid by deletion or extraction

38,209 against 37,464, 745 over, and it has been over for weeks. Two questions were
asked before arguing about a raise and both are settled.

**Nothing in `lib/` is dead.** `tools/code_reach.rb` asks of a file what `data_reach`
asks of a declaration: under Zeitwerk a file runs when its constant is named, so a
constant nothing names is a file nothing runs. It reads 0 of 405, and the ratchet row
exists to hold it there.

**Extraction moves the number the wrong way.** The counter is non-blank non-comment
lines across `lib/**/*.rb` minus the Zeitwerk wrappers, so splitting `speech.rb` into
two files under `lib/voice` moves the lines and adds a `def` and an `end`. Only three
things move it: deleting code nothing reaches, collapsing a real duplicate, or a
sponsored raise, which `spine.yml` allows "in a commit that names what the lines buy"
and caps with `consecutive_raises_allowed`.

**De-duplication is worth about thirty lines.** `CrossFileAnalysis` over `lib/` names
six DRY pairs; three collapsed for 31 lines against an overage in the hundreds. The
other three are judgement: `read_js` is byte-identical in two `lib/rails` files and
the only home is a new mixin, which costs `growth.master` a file to save four lines;
`grade_for`/`band_for` and `markdown_files`/`files` match on shape and not on
meaning. `CROSS_FILE_DRY`'s 22-file `File.read` and the `MAGIC_NUMBER_SPREAD` rows
save nothing at all — a shared reader is still one call per site. Line Jaccard across
`lib/` peaks at 0.17, and exactly one method body appears twice in the whole of it.

So the payment is a subsystem decision with an owner, not a sweep, and no single
change can name what 753 lines buy — which is why this row stays red rather than
being priced.

**The census was wrong twice before it was right, and both were the same family of
mistake.** The first version whitelisted file extensions, so `bin/cli` and the
`Rakefile` were invisible and two live files read as dead. The second excluded `:`
from its lookbehind, so every caller writing `Ground::BootChecks` was invisible and it
reported thirteen files — 975 lines, against a 977-line overage at the time, which is
exactly the kind of coincidence that should stop you. The tree was quarantined to test
it and the runtime refused to boot on `Ground::BootChecks.run(root:)`, a call the
census had just declared absent. A `\b` after a `?`, a lookbehind excluding `.`, a
lookbehind excluding `:` — three now, all the same shape. Both traps are fixtures in
`test_code_reach.rb` and both go red under mutation.

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

- **The anti-simulation guard on MASTER's own replies is a whole method, not two
  predicates, and closing it is a posture decision.** `Ground::Tool::Protocol`
  declares `fake_execution_risk?` (`tool.rb:100`) and `operational_claim?` (`:104`)
  and nothing calls either; only its `brief` is reached, from `cli/brain_overlay.rb`,
  which puts the protocol in the system prompt. The reader they were written for is
  `Voice::OutputGuard#validate`, which asks the same question in its own words —
  `COMPLETION_CLAIM`, `MODIFICATION_CLAIM` and `EVIDENCE_MARKERS` — and **is itself
  called by nothing but `test_output_guard.rb`.** `Voice::Renderer:51` calls
  `sanitize` and never `validate`, so all six of its issue checks are inert, and the
  two Protocol predicates are the inert half of an inert method. What the next person
  needs is not a caller but an answer: when MASTER's own reply claims work it cannot
  show, does it warn, append the evidence hint it already appends, or refuse? That is
  posture, and it is the operator's. The one thing neither side detects today is
  Protocol's own third requirement — a shell block presented as execution — and
  `COMMAND_BLOCK` is the regex for it.
- `MASTER/lib/ground/unified_diff_editor.rb` — the whole file, not a method.
  `parse`, `applyable?`, `summary` and `build_single_file` are named by
  `test_unified_diff_editor.rb` and by nothing else in any tree. `Fix::PatchApplier`
  shells out to `patch(1)` instead, and `ResearchThresholds` declares
  `edit_format: :unified_diff` as policy with no code between the two. Same question:
  what was supposed to apply a diff through this?
- `MASTER/lib/ground/maturity_scorecard.rb` — the same shape one layer up.
  `data/maturity.yml` is a real scorecard and `rules.yml:330` says the personality
  prompt reads it; the only callers of `MaturityScorecard` are its own test.

What this entry used to claim, corrected because a stale orphan list sends the next
reader hunting callers for methods that have them or do not exist:

- `review/security.rb`'s `safe?` (`:89`) and `clean!` (`:91`) are called from
  `MASTER/lib/io/web_fetch.rb:108` and `:111`.
- `provider_quarantine_manager.rb`'s `record_and_assess` (`:44`) is called from
  `model_router/diagnostics.rb:42`; `escalation.rb`'s `next_escalation_tier` (`:58`) is
  called at `:34` and pinned by `test_provider_quarantine_wiring.rb`.
- `ground/policy/workflow.rb` has no `autofix?` and no `confirm?` — its methods are
  `phase`, `workflow`, `gates` and `brief`, and neither word appears in the file.
- `provider_quarantine_manager.rb` has no `route?`. Its predicate is `quarantined?`.

### The rule corpus

Live figures from `bin/pub4 measure`, `rake lint:rule_reach` and `rake lint:rule_audit`
on 2026-09-09. `data/rules.yml` declares **242** rules, of which 141 carry
`detect_semantic`, 15 `detect_structural`, **0 `detect_lexical`**, and 86 carry no
detector field and resolve through `law/` or a `folded_into`. `law/` holds 118
`Law.define` blocks and the registry builds 147. `rule_reach` is 70 of 70: 115 rules
run without a model, 74 need one, 70 are dropped by the info filter.

**`CLAUDE.md`'s own enumeration snippet cannot run, two ways.** It says 228 rules and
does `d["rules"].each { |scope, rs| ... }`, but `rules:` is a flat array of 242, so
the block raises `NoMethodError`; and `YAML.safe_load_file` on that file now raises
`Psych::AliasesNotEnabled` before the block is reached. Whoever next edits `CLAUDE.md`
owes it `YAML.unsafe_load_file` and a flat `each`.

Still open, and each is a decision rather than a sweep:

- **Five mechanical transforms are worth writing.** `EN_DASH_RANGE`,
  `NO_UPDATE_ATTRIBUTE`, `QUOTE_VARIABLES`, `DOUBLE_BRACKET` and
  `WHITESPACE_PUNCTUATION` are mechanical in principle and unwritten in fact. They are
  `autofix: false` today, which is honest. **Naming a transform before writing it is
  how the dangling counter filled up last time**, so write the transform first and
  then name it.
- **39 rules fire on nothing in this corpus**, at a ceiling of 39. The header in
  `rule_ratchets.audit` is right that silence is usually a property of the sample — but
  `FROZEN_STRING_LITERAL`, `MEANINGFUL_NAMES` and `WHY_NOT_WHAT` are in the list *and*
  among the 86 rules that carry no detector field at all, which is a different reason
  for silence and worth separating.
- **136 registry rules sit outside `rule_deps`**, floor 136 and down only. A rule
  outside the graph is one `RuleOrder` cannot sequence.
- **`lint:principle_trace` is 81 of 101 untraced, twenty under its recorded low.**
  Either ratchet it or say why the twenty are not real.
- **Two learned smells still fail the uniqueness test that deleted five others.**
  `future_tense` reads 12 where `SIMULATION` reads 3, and all nine extra are lines
  `SIMULATION` deliberately spares, five of them inside the directory it exempts.
  `frozen_string` reads 2, both a percent-literal string in a file that already
  declares `frozen_string_literal: true`, where such a literal is frozen anyway. Both
  want deleting rather than narrowing, which is **a decision about the learned-smell
  mechanism** rather than about two detectors.

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

### `rake test` completes, and one test is red — 2026-09-10

**This section once said `rake test` "cannot complete on a dev Mac at all", aborting
on `cannot load such file -- rack/test`. That has not been true for some time:
`rack-test` resolves here (`MASTER/Gemfile:32`, lock 2.2.0) and the task runs to the
end.** Believing it is why three dead test files went unnoticed once.

    2227 runs, 6774 assertions, 1 failures, 0 errors, 12 skips   (157s)

- `TestRatchets#test_no_ratchet_is_over_its_ceiling` — `spine.lib_body_ceiling`, and
  the section above says why it stays.

`test_no_ratchet_is_slack` skips rather than fails whenever the measured trees are
dirty, which in a shared checkout is most of the time; read it in a clean worktree
before believing it green.

**`docs/SEVERANCE.md` does not exist, and both documents that name it now say so.**
`MASTER/DECISIONS.md:126` records the rename and the deletion, and
`MASTER/START_HERE.md:89` writes "the record of it went with `docs/`". The standing
policy on media-generation severance survives only as `DECISIONS.md:124-128`, and that
is where to read it. Do not restore `io/lora_pipeline.rb` or `video_chain.rb`; if the
LoRA training loop needs generation capability again, express it as
`lib/core/world.rb` handlers.

`TODO.md` is not in `test_doc_paths`' `DOCS` list, so nothing checks the paths in this
file. That is the one half of that gate still open.

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

The measurable residual is constants: 161 constants in `lib/` have exactly one use 80
or more lines below their declaration. The worst are
`MASTER/lib/voice/speech.rb:27-28` (`WORKER_TIMEOUT_PER_CHAR` and
`WORKER_TIMEOUT_MAX`, used only at `:611`),
`MASTER/lib/voice/personality_prompt_builder.rb:20` (`CORE_SECTIONS`, used only at
`:585`), and `MASTER/lib/review/llm_dispatcher.rb:15`, `:18` and `:20`
(`COST_PER_TOKEN`, `CACHE_WINDOW`, `MS_PER_SECOND`, used at `:374`, `:369` and `:379`
— though the first two are read again in `llm_dispatcher/ruby_llm_sender.rb:104-114`,
so "one use" is within-file only). Move each next to its one reader. This is cosmetic
and safe, and it is what the convention means by constants used only deep inside going
last.

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
`MASTER/lib/ground/phase_gates.rb:103` `#automatic_gate_met?` at 41.4. The first is
the only one worth a sitting. `rake constitution` overall is 1,791 findings, 101
actionable against a budget of 1,500, and passes.

**`NO_PUTS` fires eleven times, all in `MASTER/lib/pub4/gate_chain.rb`** (`:242`,
`:250`, `:255` and on), which is a command-line reporter and arguably the rule's
exemption rather than its subject. Read the rule's statement before acting; nobody has.

**`FILE_VAGUE_NAME` and `sprawl.vague_names` measure different things and neither
number is the other.** `FILE_VAGUE_NAME` has one finding,
`MASTER/lib/cli/routing/provider_quarantine_manager.rb:1` — "manager" is a category —
and it never surfaces in `rake constitution` because the rule is `severity: :info`
(`naming_rules.rb:239-240`) and the info filter drops it. `sprawl.vague_names` is 2 of 2
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
`lint:constant_collisions` (398 requirable of 2,473, 0 collisions), `lint:capability`,
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

### Top-level ROOT

**44 files across the repo define a bare top-level `ROOT`** — 16 in MASTER, 14 in
OPENBSD, 7 in RAILS, 7 in STUDIO — each pointing at a different tree. In their own
processes that is harmless, which is why it stands. It stops being harmless the moment
two of them are loaded together: Ruby warns `already initialized constant ROOT`, lets
the **second assignment win**, and the loser then reads the wrong tree with no further
complaint.

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
- **`learned_smells` declares five entries and its own comment says four.**
  `data/rules.yml:637` holds `frozen_string`, `magic_number`, `sycophancy`,
  `future_tense` and `duplicate_code`; the comment at `:712` lists the four that
  "survive" and omits `frozen_string`, declared 55 lines above it. Prose and data
  disagree about the size of the list, which is how a duplicate detector stays
  registered.

### `self_findings`: what our own rules find in our own trees

Two ratchet rows over the same corpus of 3,033 files across eleven trees plus
`MASTER/web`. `data/self_findings.yml` carries every finding with its file and line, so
the arrival names itself.

**`self_findings.law` is 279 against 287 and slack by eight**, having been 294 against
289 the day before. It moves that far in a day because it counts every tree, and the
bulk of what moves is `STUDIO/dilla`. Lowering the ceiling from a shared checkout
records a low the committed tree does not hold, so this is dilla's owner's row to
ratchet on a settled tree. The recorded members are the snapshot at 289:
`NULLISH_COALESCING` 76, `NO_COLUMN_ALIGN` 42, `GUARD_CLAUSE` 27,
`NO_MULTIPLE_LANGUAGES` 22, `NO_INLINE_SCRIPT_BLOCK` 21, `I18N_COVERAGE` 18,
`PROSE_OMIT_QUALIFIERS` 18, `NO_CHANGELOG_COMMENT` 16 and sixteen smaller. **Read the
member list, not the number.**

**`self_findings.registry` is 55 against 55, and what is left is two
rules.** `NO_GOD_CLASS` 29 live (32 recorded) and `SILENT_RESCUE` 26. All 26
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
  `lib/cli/routing/model_router/`, plus `provider_quarantine_manager`, and
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

### Three files over their length ceilings

`RAILS/test/file_length_ratchet_test.rb`, the one red file in the standalone
suite. `limits.yml`'s rule holds here too: a breach is paid by extraction or
deletion, never by a bigger number.

    shared/app/assets/stylesheets/_zen_shell.scss        502 / 477   (+25)
    brgen/app/assets/stylesheets/_messenger_window.scss  446 / none declared
    brgen/test/services/deploy_backlog_test.rb           558 / 557   (+1)

`user_flow.rb` and `rendered_geometry.rb` left the list on 2026-09-09.
`_messenger_window.scss` is the new arrival and has no ceiling at all, which is
the shape the counterpart half of that test exists to make visible.

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

#### 2. brgen re-implements the concern that exists to hold it

`shared/app/controllers/concerns/shared/application_setup.rb` is the one place
the three apps set up a controller. amber and bsdports use it —
`amber/app/controllers/application_controller.rb:4`,
`bsdports/...:4`. brgen does not:
`brgen/app/controllers/application_controller.rb:4-23` inlines the same five
includes, the same three `helper` calls and the same three settings, and carries
a longer version of the same comment that `application_setup.rb:13-16` carries,
each pointing at the other. `helper Shared::ConsentHelper` at line 20 is now
redundant besides: `shared/lib/shared/engine.rb:91` registers it for every app.

#### 3. The `Pub4::*Lint` family puts its entry point last

A Prism pass over 1,267 Ruby files under `RAILS/` (visibility tracked through
bare `private`/`public` call nodes, entry point taken as the method callers name)
finds six inversions, and five are one family:

    shared/lib/pub4/css_coverage_lint.rb:407     #scan, 22 helpers and 130 lines above it
    shared/lib/pub4/layout_stability_lint.rb:225 #counts, 12 helpers, 114 lines
    shared/lib/pub4/asset_url_lint.rb:186        #scan, 11 helpers, 84 lines
    shared/lib/pub4/scale_lint.rb:214            #check, 22 helpers, 83 lines
    shared/lib/pub4/breakpoint_lint.rb:162       #scan, 6 helpers, 39 lines
    test/method_length_ratchet_test.rb:111       #measure, 3 helpers, 30 lines

In each the reader meets `engine_dirs`, `strip_erb`, `to_px` and twenty siblings
before meeting `scan`, and `run` — the ratchet-printing main — is last of all.
They are `module_function` modules, so nothing is private and the fix is ordering
alone: entry, then what it calls, then the rest. `ScaleLint::Finding` and a few
helpers are named directly by tests, so nothing can be made private.

Four smaller cases in the gates, from the same pass at a lower threshold:
`gates/support/geometry_type.rb:60` (`check` behind five helpers it calls),
`gates/support/layout_search.rb:63` (`report` behind six),
`gates/support/gate_calibration.rb:36`, `gates/support/dom_surface_schema.rb:21`.
`geometry_type`'s `check_measure` and `check_tabular` are called from
`test/gates/rendered_gates_test.rb:307,314`, so again ordering only.

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
- `Shared::Engine.config.eager_load_paths` is empty while
  `Shared::Engine.paths.eager_load` lists eleven directories. Whether that means
  the engine is not eager-loaded in production, or is only a Rails 8.1 internal,
  is **not settled** — `bin/rails zeitwerk:check` could not finish in this
  worktree because the development database has no `users` table. Least sure item
  here; worth ten minutes on a migrated checkout, because it is the difference
  between a boot failure and a first-request 500.
- Eager loading needs a migrated database either way: `zeitwerk:check` aborted at
  `bsdports/app/controllers/categories_controller.rb:6` with `Could not find
  table 'users'`, because `Shared::Authentication.allow_unauthenticated_access`
  reads `::User.column_names` in a class body.

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
merely stop regenerating. Healthy on 2026-09-09: `vips --version` reads 8.14.5,
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
not a bucket. litestream is absent by decision: it is not in OpenBSD ports,
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
Measured 2026-09-09 with all four apps answering: `hw.physmem` is 1056952320 and
`swapctl -s` reports 2163920 of 2588672 blocks used, 84 percent. A resize was
recorded here as scheduled for a Friday in August and the box is unchanged, so
read the box, never a date. The standing decision is to stay at 1 GB with one
resident worker, brgen_jobs, and it reopens only if amber earns its own. Two
shapes read as a broken app rather than as memory: amber needs about twenty
seconds to signal ready and a bare `falcon serve` defaults to a thirty-second
health-check window, so reproduce a start by hand only with
`--health-check-timeout 300`, which the rc.d passes; and `bin/vps-deploy:180`
already stands the app's job worker down for the CI run, so standing it down by
hand first makes that step skip.

#### `internet_app_runs_as_passwordless_root_user`  — tag: operator-priority

<!-- open-debt -->

`MASTER/bin/master` from a terminal runs as dev, and dev is still nopass root:
`/etc/doas.conf:39` reads `permit nopass setenv { … } dev as root`, and `doas -C
/etc/doas.conf id` printed `permit nopass` on 2026-09-09. The remote half is
closed — `/etc/rc.d/master:64` carries `daemon_user="master"`, in the same shape as
the three apps. The operator work is to drop or scope line 39, and it is not doas
command scoping; see DECISIONS.md for why cmd rules cannot work here. Check it
with `doas -C /etc/doas.conf id`, not with `doas -C /etc/doas.conf -u dev id`,
which this row used to name: `-u` sets the target user, so that form asks whether
dev may run a command as dev, prints `deny` today, and reads as done. Before
moving brgen, amber or bsdports off their own daemon_user, check what the master
switch cost a deploy: `Bundler.setup` ends in `Definition#write_lock`, which
touches Gemfile.lock on every boot, the daemon had always written it as dev, and
under a new user it is EACCES with a trace naming `File.utime` and nothing about
permissions. `BUNDLE_FROZEN=true` in the daemon's env is the fix and is
load-bearing.

#### `home_partition_full_from_git_history`  — tag: operator-priority

<!-- open-debt -->

What is open is a coordinated history rewrite, and only the operator can schedule
it. The ten largest objects in history are 80–87 MB WAV renders under a
`DEPLOY/dilla/renders/beats/` path that no longer exists, every deploy pulls them,
and the fix is a force-push to a public repo with a vm23 re-clone in the same hour
and every session quiescent. Strip the blobs and the key purge in one pass. It is
not pressure: measured 2026-09-09, /home is 69 percent with 5.1G free of 17G, /var
is 16 and / is 18, and /home/dev/pub4 is 4.5G of which .git is 3.6G. Re-read it
with `ssh dev@brgen.no 'df -h /home; du -sh /home/dev/pub4/.git'`.

#### `bsdports_org_delegated_to_parking`  — tag: operator-priority

<!-- open-debt -->

One registrar change, at Domeneshop and nowhere else: set bsdports.org's
nameservers to ns.hyp.net and ns.brgen.no. The app is well — it deployed on
2026-09-09 beside brgen and amber and answers on port 47312 behind relayd — and the
domain is parked. Measured 2026-09-09: the .org registry still delegates to
ns1/2/3.expireddomain.hyp.net, those publish 185.134.245.114 and
2a01:5b40:0:bc04::1, `https://bsdports.org/up` returns 000 because parking
terminates no TLS, and `http://bsdports.org/up` returns 200 from Domeneshop's
parking page. A check that reads a status code therefore calls the domain healthy
while it serves someone else's page. `ruby RAILS/gates/runner.rb dns_zones` catches
it by comparing the answer against 46.23.89.226, and bsdports.org is its one
failure — that gate reads the three app domains
(`RAILS/gates/lib/host/dns_zones.rb:69`), so no count of expired city domains
belongs in this row. whois still shows autoRenewPeriod against an expiry of
2027-08-08: the registration is paid, the nameservers were never put back. It is
done when `dns_zones` passes, and it must be done before the certificate at
/etc/ssl/bsdports.org.fullchain.pem expires on Nov 10 2026, because acme-client's
HTTP-01 renewal needs the name to resolve here.

### Guards worth not re-discovering

A fixed finding is not a backlog item and is deleted when it closes; `git log`
holds the why. What stays here is the false positive worth not paying twice.

**amberapp.com is not ours.** A row here once recorded it as bought and certified
after reading a 114-byte JS-redirect page. That page is Afternic's for-sale
lander; the domain has been at GoDaddy since 2019 with `ns1/ns2.afternic.com` and
a fast-transfer record, and the listing asks USD 5,999. Read whois before calling
a domain ours. amber is canonical at amber.brgen.no, buying the apex is a spend
decision for Johann and Ragnhild, and the coupling matters: the session cookie is
`domain: :all`, scoped to the registrable domain, so a move off brgen.no silently
ends cross-app sign-in, and `Shared::SsoToken` is consume-only in this tree.

### The shell tree — what is still open

Re-verified 2026-09-09 against the box, read-only, the day brgen, amber and
bsdports all deployed. All three answer 200 on `/up`.

#### 1. Live `/etc/rc.d/amber` and `/etc/rc.d/bsdports` still wait 30 seconds where the repo waits 300

The difference is one number: `while [ "$_i" -lt 300 ]` in the repo against `-lt
30` on the box, at `rc.d/amber:58` and `rc.d/bsdports:63`. That loop sets `_up_ok`,
and `_up_ok` decides whether `rcctl restart relayd` runs, so an app that answers
`/up` late leaves relayd pointing at a dead backend and logs `relayd skipped` —
the recurring amber and bsdports shed-and-stay-down. Commit `d76fa573c` raised
both to 300 for that reason on 2026-08-28; the live files are dated Aug 27 17:35
and today's deploy did not replace them. Fix: one `install_root_configs` run. Five
files drift, not three — `/tmp/vps-deploy-drift.out`, written by today's deploy at
16:16, names doas.conf, newsyslog.conf, rc.d/master, rc.d/amber and rc.d/bsdports.
In amber and bsdports the drift is this timeout plus a comment citing the retired
`OPENBSD/data/debt.yml`, and in doas.conf it is that comment alone. A drift gate
red on comments is what teaches an operator to skim a red gate.

#### 2. `uptime-check.sh` has mailed root 8,270 DOWN lines, and the waiver already exists

`/var/log/uptime-check.log` is 692 KB and holds 8,270 `DOWN` lines: 5,140 for
`https://bsdports.org/up` and 2,698 for amber. Root's crontab runs
`/usr/local/bin/uptime-check.sh` every five minutes and mails root on a DOWN line,
and `OPENBSD/usr/local/bin/uptime-check.sh:72` already honours
`ALLOW_BSDPORTS_DOWN=1` — the crontab line does not set it. The fix is an operator
edit to root's crontab, or that waiver as the default while the domain is parked;
`bin/deploy-smoke.sh:201` makes the same HTTPS probe a required check and needs
the same treatment. Thousands of mails whose cause is known make root's mailbox
unreadable, which is the lesson the litestream `rcctl ls failed` decision already
recorded.

#### 3. `etc/rc.d/master:112` narrows the asset digest when a script fails

`_face_assets=$(... face_asset_paths.rb 2>/dev/null)` yields an empty list when
that script fails, so the digest falls back to the hardcoded inputs and reproduces
the stale-fingerprint bug the comment above it describes. Both stamp writes in the
same file guard on success; this is the quieter half and nothing guards it.

#### 4. Seven scripts deploy this box, and two report success having done nothing

`bin/vps-deploy` is the one CLAUDE.md and RUNBOOK name. The others are
`deploy_all.sh`, `vps_install_all.sh`, `vps_on_vm_install.sh`,
`vps_production_push.sh`, `vps_deploy_master.sh` and `manual_master_deploy.ksh`.
Three build the three face bundles, precompile and run the `master_web_assets`
gate, with three different failure semantics: `etc/rc.d/master:100` swallows the
face build behind `|| true`, `vps_deploy_master.sh:42` swallows it the same way,
and `manual_master_deploy.ksh:37` records `_fail=1` and exits 1 at :43. Two end
green whatever happened — `vps_on_vm_install.sh:22` turns a failed app deploy into
`WARN: $app failed` and finishes on `log "done"` at :28, defeating its own `set
-euo pipefail`, and `vps_install_all.sh:61` finishes on `doas rcctl check master
2>/dev/null || true`. `deploy_all.sh`, `vps_run_remote.sh` and
`manual_master_deploy.ksh` are named by `RUNBOOK.md` and by nothing that runs.
`OPENBSD/bin` holds exactly 17 tracked executables against its
`pub4_entrypoint_ceilings` of 17 (`MASTER/data/spine.yml:466`), so nothing new
lands there until something folds. Fix: retire the scripts whose only caller is
the runbook, and make the survivors exit non-zero.

#### 5. Seven places read the load average, and the awk ban has no detector here

`vps_master_scan.sh:13-15` notes the ban and does the comparison in one `ruby34
-e`. `vps_ci_all.sh:13` and `:17` still shell out to awk for the same `vm.loadavg`
field, and `bin/check-openbsd:39` only runs `zsh -n` over that file, which is
syntax. The seven readers are `vps_ci_all.sh`, `vps_master_scan.sh`,
`resource_guard.sh:101`, `usr/local/bin/core-reclaim.sh:65` and
`usr/local/libexec/stale_ci_cleanup.ksh:16` in awk, and
`usr/local/bin/drain-jobs.sh:52` and `usr/local/bin/prune-guests.sh:49` in Ruby.
The ban itself governs MASTER: `zsh.banned_commands` in `MASTER/data/rules.yml`
has two readers, `MASTER/lib/io/shell.rb:27` and
`MASTER/lib/voice/personality_prompt_builder.rb:325`, so it bounds what MASTER's
shell effect runs, not what this tree commits. Fix: one `lib/load.sh` the seven
callers share, then either a scanner rule over `OPENBSD/**/*.{sh,ksh,zsh}` or a
note saying the ban is advice outside MASTER.

#### 6. Usage comes after the work in four files

`OPERATOR.sh` is 977 lines and prints its usage at 925, inside `main()`.
`bin/deploy-smoke.sh` handles `-h|--help` at 161, after the banner at 149, so
`--help` prints `deploy-smoke: mode=--help timeout=20s` and then the usage.
`validate_doas.ksh` puts its general usage at 105 of 116, with the first side
effect above it, and `lib/ssh_vm23.sh` at 52 of 60. What an operator needs first
should come first.

#### 7. Nine two-line expect shims, and six dangling in-tree paths

`vps_console_status.exp`, `_probe`, `_short`, `_install`, `_fix_key`,
`_poll_install`, `_start_install`, `_sync_and_install` and `vps_drop_install.exp`
are each one line — `exec [file join [file dirname $argv0] vps_console.exp]
<subcommand> {*}$argv` — and the dispatcher already takes the subcommand as its
first argument. Their shared guard is wired: `vps_console.exp:8` sources
`vps_console_common.exp`, which calls `require_console_risk_ack`. Its refusal
message at `vps_console_common.exp:13` names `OPENBSD/VPS_SAFETY.md` and
`OPENBSD/OPERATOR_CONTRACT.md`, neither of which exists; the other four dangling
references are `RUNBOOK.md:18` and `deploy_all.sh:6` to
`OPENBSD/archive/recovery/manifest.json`, and `DECISIONS.md:200` and
`PATH_OWNERSHIP.yml:17` to the retired `OPENBSD/data/debt.yml`. That is the whole
list. The shims refuse without `I_UNDERSTAND_CONSOLE_RISK=1` and were not run.

#### 8. One dead local in `restore_backups.sh`

`ROOT_DIR` at line 21 is assigned and read nowhere in the file.

#### Not worth chasing

- **Ruby entry points come last, everywhere.** `config_drift_gate.rb`'s skip
  guard, `installed_targets_gate.rb`'s `run` and `health_check.rb`'s first `def`
  all sit below the definitions they use. The language wants the definition before
  the call and the tree is consistent about it. Reordering buys nothing.
- **`bin/vps-deploy:153`'s `[[ -x /usr/local/bin/config_drift_gate.rb ]]` guard.**
  It has the shape `installed_targets_gate.rb` records as a dead guard, and it is
  not one: `OPERATOR.sh:310` installs that file, the box has it dated Aug 25, and
  it wrote `/tmp/vps-deploy-drift.out` during today's deploy.
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

Everything below was re-measured on 2026-09-09 in the main checkout, because
`samples/` is gitignored and a worktree therefore shows an empty crate that is not
empty. dilla is under active edit; line numbers inside `dilla.rb` move, symbol
names do not.

### The crate

- **The crate is in no backup, and that is the open item.**
  `STUDIO/dilla/.gitignore:19` ignores `samples/` wholesale, so not one rack is
  tracked, and `OPENBSD/bin/dr-pull` copies the three production databases and
  nothing else. The 124 rack directories under `samples/chopped/` are
  irreplaceable audio living on exactly one disk, which is the state `samples/dug/`
  was in the day it went. Pull `samples/` to the rotated off-box location dr-pull
  already uses, or somewhere the operator names.
- **All 124 chopper-registered racks are unreachable as presets.** Verified by
  running the test that asserts otherwise: `ruby
  STUDIO/test/test_dilla_engine_probes.rb -n
  test_every_hand_cut_sample_loop_is_reachable_as_a_track_preset` fails in 0.7
  seconds and names 124 slugs. The four reachable loops are all builtins —
  `kembara_rindu`, `semua_untuk_mu`, `lo_borges` and `arat_swost_wolet` — so this is
  not scattered oversight: the chopper has never written a preset row. Making
  `chop` write one is mechanical; **naming 124 presets is authoring and stays the
  owner's**.
- **160 of the crate's 161 sources are gone, and no loop is reproducible from its
  sidecar.** `samples/dug/` holds one record, `arat_swost_wolet.mp3`. The sidecars
  carry a reproduce command naming a path that no longer exists, and only the
  titles survive, in the slugs; re-fetching by title returns a different upload, so
  offsets and mastering will not match. New fetches record the HTTP URL —
  `CrateDig.archive_entry` and `ccmixter_entry` store `url` and `record!` refuses
  an entry without one. `dilla/crate/` from `bin/crate` is gone the same way,
  taking with it the two takes whose sidecars name `crate/loops/semua_untukmu`.
- **153 racks were cut by the seam test that preferred mid-phrase**, and re-cutting
  them needs the sources. The source-free remedy is rotating each loop onto its
  strongest downbeat, which is content-preserving because a rack is one whole
  period, but the measure needs a floor first: several of the largest apparent
  gains are a quiet tail scoring as a downbeat, and one rack starts at -57 dB.
- **148 registry rows carry only what a wav can be asked for.** bpm came back from
  each file's duration and voicing from its spectrum; `source`,
  `source_start_sec`, `self_similarity` and `rejoin_db` cannot be recomputed
  without the source, and `vocal_chop` skips a row that cannot name its record
  rather than guessing.

### Which crate layout survives is the owner's call

dilla has four crate surfaces and three layouts with one reader. The engine reads
`samples/chopped/loops.json` through `RadioChop.registered_loops`
(`lib/radio_chop.rb:634`). `lib/crate_dig.rb` writes `samples/dug/` from the
Internet Archive and LibriVox, filtered to expired copyright, because — its own
header says — YouTube rips are "neither licensed nor defensible", while
`live/dig_crate.rb:37` rips YouTube with `yt-dlp`. `bin/crate` declares a third
layout, `crate/{sources,stems,loops}`, calling itself the replacement for
`samples/`, and that directory no longer exists. `crate_dig` and `dig_crate` are
one word order apart and take opposite positions on licensing, which is worth
fixing whichever layout wins.

### The engine is one file, and its support directory is full

`dilla.rb` is 35,142 lines and carries the 83 `# engine part:` parts that were
under `lib/engine/`, in the order they were required, because that order was
load-bearing. `DillaSources` defines the corpus, `STUDIO/gate.rb` fails if
`lib/engine/` reappears, and `DILLA_SUPPORT_CEILING = 44` (`gate.rb:116`) caps the
modules that could grow in its place — `dilla/lib` holds exactly 44 tracked `.rb`,
so the next module fails the gate, while `dilla/bin` at 11 files and `dilla/live`
at 8 are not counted at all. `MASTER/tools/cohesion.rb STUDIO/dilla/lib` proposes
three regroups, `engine/`, `harmony/` and `score/`, nine files between them; taking
any of them moves those files out of `%r{/dilla/lib/[^/]+\.rb\z}` and drops the
guarded count to 35, quietly disabling the ceiling it appears to relieve. Raise
the ceiling with a reason, or extend it to `bin/` and `live/`; do not regroup to
get under it.

Folding the 44 into fewer files is undone, and 14 of them use `__dir__` or
`__FILE__`, which shift a directory level when a file moves — the bug that broke
three tests during the first fold, and the reason to do the second one
deliberately rather than as a tail-end.

`dilla.rb` also carries its own map and nothing indexes it. The cheap win is a
generated index of the 83 part markers so a reader can find a subject without
grepping. The seams worth naming are the parts over 600 lines — `patch`,
`progression_tables` (pure data, 8 constants and 4 defs, the most extractable
thing in the file), `render_dilla`, `characterize`, `cli_commands` and
`render_techno` — and the seven methods over 250 lines, of which `render_dilla` is
963. **Splitting any of them is not proposed here**, and the decision not to
reopen `lib/engine/` stands.

### Five scripts live twice, and four pairs have drifted

`/Users/mac/Music/dilla_sines/` holds six Ruby files. Five have tracked twins in
`STUDIO/dilla/bin/`, and only `demo_from_stream.rb` is byte-identical. Measured by
SHA-256: `sine_stream.rb` is 2,023 lines outside against 2,025 tracked,
`demo_full.rb` 130 against 125, and `make_ticks.rb` and `player.rb` differ in
content from `sine_stream_ticks.rb` and `sine_stream_player.rb` at equal length.
`demo_render.rb`, 4,393 bytes, has no tracked twin at all. No census can see this:
`dup_census` reads tracked files only, and excludes `STUDIO/` besides. The scripts
run from the repository now, so the fix is to retire the outside copies rather
than keep diffing them.

### Ten knobs get a different default depending on which read site runs

`DillaKnobs.conflicts` already computes this and nothing gates it. The three
operational conflicts are reconciled. The ten that remain shape a render and are
**the owner's alone**, the sharpest being `MELODIC_LEAD`: `dilla.rb:8754` reads
`ENV.fetch("MELODIC_LEAD", "0") != "0"` and `:9242` reads `ENV.fetch("MELODIC_LEAD",
"1") != "0"`, so with nothing set one predicate says the melodic lead is off and
the other says it is on. Then `HARM_VOL` 2.45 against 2.4 in
`composition_engine.rb`, `EVOLVE_HARMONY_W` 0.18/0.08/0.12, `EVOLVE_GROOVE_W`
0.22/0.06, `EVOLVE_EVERY` 3/2, `LISTEN_PASSES` 0/3, `RENDER_BEAUTY_MIN` 65/70 and
`BPM` 92/90. `BARS` and `TRACK` are per-command and are not defects. The fix worth
suggesting is a ratchet: `DillaKnobs` already has the answer, so pin ten and let
the eleventh fail.

### Four rescues lose a measurement, and the rule cannot see them

`SILENT_RESCUE` (`MASTER/lib/review/scan/rules/lexical_rules.rb`) reads lines that
begin with `rescue`, so a modifier `rescue` and a `rescue` whose whole body is
`next` are counted by nothing. `dilla.rb:6285` and `:6286` wrap `band_rms` inside
`cross_sample_convolve!`; if either raises, `trim` falls to 0.0, the convolved bed
ships unmatched in level, and the `dmesg` at `:6295` prints "matched dB → dB" with
the numbers missing. `live/recall.rb:36` and `bin/sine_stream_player.rb:41` are
the other two. The five loop-control ones — `lib/music_gems.rb:200`,
`lib/harmony_engine.rb:362`, `bin/demo_full.rb:42`, `bin/sine_stream.rb:1830` and
`lora/_toolkit/run_train_kaggle.rb:144` — each skip a member of a loop and are the
least alarming shape. Extending the rule to both forms is a MASTER change, not a
STUDIO one.

Three blanket clauses read as narrow and are not: `lib/master_heuristics.rb:24`
catches `StandardError, Psych::Exception`, `lib/music_gems.rb:152` catches
`::Coltrane::ChordNotFoundError, StandardError`, and `lib/verify_fx.rb:220`
catches `StandardError, ArgumentError`, and all three named classes descend from
`StandardError`. **Narrowing any of them is the owner's**; deleting a redundant
class name is not. The remaining discards are optional gem probes, external
binaries whose output is parsed, optional state files and process teardown, and
they are correct as they stand — with one worth a log line rather than a rescue:
`lib/seed_providers.rb:88` and `:99` set `SWING` and `HARM_VOL` from USGS and
open-meteo, so a failed fetch silently leaves the defaults and an operator who
asked for a seeded swing cannot tell whether they got one.

### `dilla/live/` is three subjects, and the fold is free only until the next pass

The three `*.als.rb` sets share 10 identical code lines out of 81, 94 and 104 —
the duplication is already extracted into `Rack`, which each set calls 7 to 15
times — so folding them would collapse three distinct arrangements, not three
copies of one. Two costs are measurable: `broadcast.sh:24` and `recall.rb:89`
resolve a set by filename, and `Rack.journal!` writes the set name into
`project/liveset.jsonl` as data, so a rename breaks replay of every journalled
pass. Today that cost is zero — the journal holds 32 rows and not one carries
`seed` or `set`, the two keys `recall.rb:37` filters on, so `live/recall.rb`
prints "no seeded passes yet" and can replay nothing. The sets do write both keys
now (`live/ambient_pads.als.rb:133` and its siblings), so the next pass played is
the first replayable one, and the fold is free before then and never free again.
`dig_crate.rb` is the third subject: crate ingest, nothing to do with playback, and
it belongs beside `lib/crate_dig.rb`. **Still the owner's to take.**

### Small, mechanical, and none of them touch sound

- `lib/knobs.rb:389` says `dilla knobs` reports 632 knobs across 119 files.
  Running it reports 729 across 45. A hand-kept figure in prose, against a census
  the tool computes on demand.
- `dilla.rb` requires `lib/frozen_state` five times (`:118`, `:18009`, `:20952`,
  `:30230`, `:30605`) and `tmpdir` twice (`:79`, `:33966`).
- The law findings in STUDIO cluster in `dilla/bin`: all five `.rb` there lack `#
  frozen_string_literal: true`, all five `.sh` there lack strict mode where
  `live/broadcast.sh:9` shows the convention of stating why it goes without, and
  `NEVER_BATCH_DELETE` fires at `bin/sine_stream_ticks.rb:15`, which clears every
  wav under `~/Music/dilla_sines/ticks` at startup.
- Three engine tests pass in about 23 seconds alone and time out under suite load
  against the 90-second `PROBE_TIMEOUT`
  (`STUDIO/test/test_dilla_engine_probes.rb:26`): `test_smoke_two_bar_render`
  (`:2289`), `test_provenance_separates` (`:2618`) and `test_dilla_frozen_reads`
  (`:2658`). Recorded, not re-run today. Not a defect in what they measure; the
  budget does not survive a loaded machine, and a green subset here proves only
  that.

#### Not worth chasing

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
- **The 37 stale rows in `loops.json` and the 37 slugs in `sample_worth.json`.**
  161 registered against 124 on disk; dropped at load (`radio_chop.rb:637`) and
  pruned on the next chop (`:879`). Inert by design.
- **The sample rate declared eleven times under three names.** `SAMPLE_RATE` in
  `dilla.rb`, `lib/acapella.rb`, `lib/radio_chop.rb` and `lib/vocal_chop.rb`;
  `RATE` in `lib/analog_synth.rb`, `lib/sample_flip.rb`, `lib/space_fx.rb`,
  `lib/verify_fx.rb`, `bin/sine_stream.rb` and `bin/demo_from_stream.rb`; and
  `SU_TUNNEL_IR_RATE` in `dilla.rb`. Every library one is namespaced, so nothing
  collides, and 44,100 is not a matter of taste. The bare literal also appears in
  32 ffmpeg filter strings, and interpolating it would touch 32 render-path strings
  for no behavioural gain.
- **The three `cohesion.rb` regroups**, for the ceiling reason above.

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

- **`.price` still wears the accent.** `shared/_minimal.scss:474` sets
  `color: var(--accent)`, while `visual_contract_lint.rb:52` records that
  `.price` dropped the hue on 2026-08-21. One of the two is wrong. It sits
  outside the brgen-scoped glob, so `accent_on_prose` cannot report it.
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
- **brgen's layout comment describes a mechanism that is gone.**
  `brgen/app/views/layouts/application.html.erb:22` says the surface theme is
  "per vertical, not a constant" and sends the reader to
  `ApplicationHelper#surface_theme` for the mapping; that method now returns
  `DEFAULT_SURFACE_THEME`, which is `"light"` for every surface.

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

- **Twenty-seven of the fifty-one RAILS gates never call `checked!`.**
  `flow_journey` reported PASSED over 25 journeys while its verdict line read
  "checked nothing", because `measured_nothing?` saw `checks_ran == 0`. That one
  is fixed and the rest were never read. Some of the twenty-seven are suites
  that delegate, so classify before fixing; `live/first_screen.rb`,
  `live/user_flow.rb` and `source/css_constitution.rb` are among them.
- **Live RAILS gates still measure too little.** `user_flow`, `first_screen`,
  `payment_honesty`, `content_honesty` and several rendered gates skip when the
  app ports are closed. Run the suite once with `GATE_REQUIRE_LIVE=1`,
  `GATE_STRICT_INCONCLUSIVE=1` and `GATE_STRICT_ERRORS=1` on a host where brgen,
  amber and bsdports are listening, then record any findings that only appear
  live.
- **brgen's `Gemfile.lock` was written by a different bundler major than the
  box resolves with.** vm23 runs ruby 3.4.9 with bundler 4.0.17; amber and
  bsdports record `BUNDLED WITH 4.0.7`, brgen records `2.7.2` and writes its
  `RUBY VERSION` as `3.4.9p82`, which is the older bundler's format — so the
  whole lockfile, not just the footer, came from 2.x. Re-resolving is a
  deploy-day change with a rollback plan: the body was resolved by the bundler
  that wrote it, `vps-deploy` installs from it on a 1 GB box, and
  `vps_gemfile_lock_drift` already records that a Mac-written lock against
  BSD-only gems is how this breaks.
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
- **Six `capture2e` calls in gates have no timeout** — in
  `lib/live/deploy_drift.rb`, `lib/meta/constitutional_scan.rb` and
  `lib/source/frontend_production.rb`. One of them hung a whole run with no
  output and no verdict. Done when every subprocess a gate spawns is bounded.
- **A skipped gate still reads as a pass in the summary.** `runner.rb --all`
  should close with the skipped gates and their reasons as a list, the summary
  line should separate passed from failed from measured-nothing, and
  `GATE_STRICT_INCONCLUSIVE=1` should be the CI default while staying optional
  locally. The live gates that skip on closed ports are the case to settle: boot
  the triangle for them, or fail rather than skip.
- **A red gate that never loaded prints an empty failure list.** `rails_runtime`
  was red for months naming no finding, because it failed at require time. Done
  when a load failure says so instead of reporting zero findings.
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

## Aegis, seaborne

Aegis is the proactive-bodyguard concept: passive sensing, active analysis,
preemptive action. Written for a city it is a hard build and a poor business.
Written for the water it is a narrower build with paying customers, and it is
the case where this runtime's offline-first design stops being a preference and
becomes the product.

**The urban threat model does not port.** It assumes an adversary who is human,
intentional, and three seconds away, in a place with dense infrastructure. At
sea the threat is environmental and indifferent, the timescale is twenty minutes
to twelve hours, rescue latency is hours rather than minutes, and connectivity
is absent by default rather than merely degraded. Every intervention that
depends on deceiving a person — the synthetic phone call, the fake system
update, the lit-street route — has no one to deceive and nowhere to walk. Gait
analysis, proximity tailing and weapon identification go with them.

What survives is small and gets much stronger. Immersion and sudden-deceleration
detection replace the acoustic and gait tiers. The last-known-position heartbeat,
a footnote in the urban spec because the city has signal, becomes the entire
value proposition. The forensic packet already has a regulatory home, because
voyage data recording is mandated on commercial vessels and is currently dumb.

**Man overboard is the anchor, and the only one worth starting from.** It maps
onto the existing pipeline almost unchanged: immersion plus acceleration anomaly
triggers, biometrics confirm the wearer is alive, an AIS-MOB and satellite burst
carries position, and the packet is the record. It is far more tractable than
the urban case because there is no intent to model and no adversary adapting to
the detector, and it drops the whole privacy surface with them. Existing MOB
beacons are pull-cord or water-contact triggers with no discrimination and no
prediction. The gap a model actually fills is drift: cold-water displacement is
predictable from sea state and current, and a search wants the probable position
twenty minutes from now, not the position at the moment of the fall.

**The gate is hardware, not software.** A phone cannot host this — salt,
immersion, battery, and the fact that it rides in a pocket rather than against
skin. The sensing substrate has to become a wearable or a vessel-mounted box
before any of the sensing tiers are worth writing. So the order is: prove the
tier-one anomaly stack on phones on land, where iteration is cheap, then port
detection to marine hardware, where the regulation and the budgets are. The
urban build is the laboratory, not the product.

**Do not scaffold the sensing tiers yet.** Stub sensors, placeholder threat
classes and a maritime module wired to nothing would be this tree's dominant
defect committed deliberately, and `data/soul.yml` forbids it under
anti_simulation. Nothing in this program is written until it has a reader.

The one piece buildable today with no hardware and no speculation is the drift
model: a pure function from entry position, sea state, current and elapsed time
to a probable-position ellipse, testable against published search-and-rescue
drift data. It is useful on its own to anyone running a search, it is the part
with real intellectual content, and it is falsifiable — which the rest is not
until there is a device. Start there or start nowhere.

Norway is the place to do it: the fishing fleet, the aquaculture pens, the
offshore wind buildout, Sjøfartsdirektoratet, and an Innovasjon Norge case that
argues far more readily for maritime safety than for a constitutional runtime.
It is the same pitch as `MASTER/README.md` makes, with a body attached.

---

## A hundred, toward a catalogue of livesets — 2026-09-02

Written after the three sets in `STUDIO/dilla/live/` landed, and after the
operator said what the lost Ableton sets were made of: Goldbaby drums, a master
chain of many Sonitex instances and several Nasty VCS on *summing phasy*, one
sweet sample, and Dilla's rule — make old things sound new and new things sound
old. The sets exist to replace a life's work that a robbery took. Three is not a
catalogue, and this is the list of what would make it one.

One fact shapes most of what follows. `dilla.rb` already carries the sound
design: devices (`COPY_MACHINE`, `HOCKET`, `VOICE_STACK`, `LPG`, `BUS_PATCH`,
`WAV_MAP`, `MIDI_BAG`), section maps, four mix buses, a modulation matrix, 401
chord progressions, 74 track presets, and forty-two support modules under
`lib/`. The three sets reach for about six of its knobs and re-synthesise from
scratch what the engine would have handed them. So a large share of this list is
not *build* — it is *connect*, which is this repo's dominant defect written down
in `MEMORY` as inert config and dead wiring.

**[cheap]** is an afternoon. **[deep]** is a project. **[yours]** is a decision
rather than work. **[risk]** changes a rendered sound and so is not mine to
choose. Numbers are for citation, not for order.

### A · The catalogue: sets to build (1–20)

1. **`vocal_chop_beats.als.rb`** [cheap] — `lib/vocal_chop.rb` already separates
   a vocal stem and refuses any rack that cannot name its source. Thirteen racks
   can. A set built on the voice rather than the instrumental is one new file
   against work already done.
2. **`drum_break_beats.als.rb`** [deep] — `radio_chop` runs `htdemucs_6s` and
   throws the drum stem away. Keeping it gives every record in the crate its own
   break, which is the other half of the sampling tradition and currently
   discarded at the moment it is most expensive to compute.
3. **`two_deck.als.rb`** [deep] — two beds at once. `Rack.grid` already derives a
   tempo from a loop's own duration, so beat-matching two racks is arithmetic
   that exists. A DJ shape rather than a beat: one record under another, one
   leaving as the other arrives.
4. **`interlude.als.rb`** [cheap] — twenty to forty seconds, one idea, no
   arrangement. *Donuts* is thirty-one pieces in forty-three minutes. The sets
   are all ninety-six or a hundred and eighty seconds because that was the first
   number typed, not because anything measured it.
5. **`beat_tape.als.rb`** [deep] — one render containing six linked pieces with
   transitions between them: a side of a tape rather than a track. The unit the
   lost sets probably were.
6. **`remix.als.rb`** [cheap] — `samples/own/` holds nine finished recordings by
   the operator and named collaborators. Every set so far plays other people's
   records. One that plays ours is a different thing to own.
7. **`spoken_word.als.rb`** [deep] — `lib/acapella.rb` exists. A bed under speech
   is the oldest form in the tradition and the one the crate is best suited to.
8. **`jazz_trio.als.rb`** [deep] — `chord_based_beats` voices its chords as
   detuned sines because that was the cheapest honest thing. `lib/harmony_lead.rb`
   and `lib/analog_synth.rb` and the four cached soundfonts exist. The same
   progressions through a real instrument is a second set, not a change to the
   first.
9. **`tape_loop.als.rb`** [deep] — a physical loop degrading each pass:
   `lib/tape_hysteresis.rb` is already written and the set would be the first
   caller that makes its behaviour audible over time rather than statically.
10. **`long_form.als.rb`** [cheap] — twenty minutes rather than three. The pad
    set is already the shape; only `TOTAL` and the swell period stand in the way,
    and a set you can leave running is a different use than a set you audition.
11. **`radio.als.rb`** [deep] — never ends. `live/broadcast.sh` rotates four
    processes with hard cuts between them; a set that crossfades its own
    successor is the thing that was actually wanted.
12. **`field.als.rb`** [yours] — a bed that is a place rather than a record.
    Needs recordings that do not exist yet, and making them is a day out with a
    recorder, which is the cheapest new material this project could get.
13. **`minimal.als.rb`** [cheap] — one voice, no kit, no bed, no console stack.
    Useful mostly as a control: everything else in the room is additive and
    nothing measures what each addition is worth.
14. **`flip.als.rb`** [cheap] — `lib/sample_flip.rb` chops against chords and is
    one of the engine's better ideas. No set reaches it.
15. **`dfam.als.rb`** [cheap] — `lib/dfam_engine.rb` models a semi-modular drum
    voice and is likewise unreached from `live/`.
16. **`gospel.als.rb`** [cheap] — the eight-bar climb specialised: slower harmonic
    rhythm, the climb as the whole arrangement rather than a row sampled out of a
    table of four hundred.
17. **`techno.als.rb`** [yours] [risk] — the crate rules exclude industrial
    techno and the standing goal is a genre-agnostic engine where techno, soul
    and jazz are parameters rather than forks. Those two are in tension and only
    the operator can resolve it.
18. **B-side sets** [cheap] — the same seed through a deliberately different
    room. Costs one environment variable if the console parameters become data;
    see 31.
19. **Tempo families** [cheap] — the beat sets both sit at 82–104 because that
    is where the crate lands after drag. A set at 60 and a set at 140 would say
    whether the room survives outside its comfortable octave.
20. **A set per crate region** [deep] — `project/sample_worth.json` scores every
    rack on seven terms. The sets use only the aggregate. Sets keyed to *voicing
    density* or *chord-register presence* would each sound like a different
    record collection, which is what a shelf of Ableton sets actually was.

### B · The room is sitting on an engine it does not call (21–36)

21. **`COPY_MACHINE`** [cheap] — the bed played six times at once at different
    speeds, with `_FAMILY=harmonic|chromatic|spray`. This is precisely what
    `sampled_based_beats` hand-rolls with `asetrate` and three voices, done
    better, already tested, and reachable.
22. **`VOICE_STACK`** [cheap] — four voices each playing all of it, differing in
    register, tuning and timbre, with a macro that picks a model and a patch from
    212. The pad set's four-interval voicings are a poor cousin of this.
23. **`HOCKET`** [cheap] — one line split across voices with `round_robin`,
    `pendulum`, `shift_register` modes. Nothing in `live/` splits anything.
24. **`LPG`** [cheap] — a Buchla low-pass gate, measured at 17.5 dB more high-band
    fall than body over a decay. It is what makes a note read as *struck*, and the
    chord set's whole problem is that its notes read as *triggered*.
25. **`BUS_PATCH`** [cheap] — a whole modulation patch on a bus: one source per
    destination, depths biased low, at least one inverted, `BUS_PATCH_SEED` to
    pin it. Movement over ninety-six seconds is the sets' weakest dimension and
    this is the built answer.
26. **`WAV_MAP`** [cheap] — a picture read as an oscillator in the track's key.
    Not a gimmick if the picture is a photograph of the thing the piece is about.
27. **`SECTION_LAYERS=full`** [cheap] — the harmony bus leaves in the intro and in
    any breakdown over eight seconds. The sets each hand-roll one volume
    automation across a fixed bar range and call it an arrangement.
28. **`FORM_FIT`** [cheap] — stretch a form across the track rather than cycling
    it, on by default past 64 bars. The pad set at 180 seconds is four intros
    cycling and does not know it.
29. **`DILLA_MIX_BUSES` and `CONSOLE_STACK`** [cheap] — four buses and a summing
    stack measured at 23 dB less third harmonic at three stages than one. The
    sets do their own flat `amix` with hand-tuned weights that had to be
    re-measured by hand this session when the kit changed.
30. **`FROZEN_STATE` / `DILLA_FROZEN`** [cheap] — the engine's own A/B pin. The
    sets grew a parallel seed mechanism because nobody checked whether one
    existed.
31. **Make the console parameters data, not call sites** [cheap] — `Rack.sonitex`
    and `Rack.vcs` are invoked eleven times across three files with literal
    numbers. A named table (`warm`, `dry`, `blown`, `phasy`) turns "which room"
    into a knob, which is what 18 and most of section G need.
32. **`lib/outboard.rb`** [cheap] — eight emulations, four of which measuring
    proved dead. The live rack re-implements two of the four that work.
33. **`lib/producer_dna.rb` and `GROOVE_DNA=donuts`** [deep] — `drunk_kit`'s
    jitter figures are hand-chosen constants. A DNA table already describes this
    and would let a set be *in the manner of* rather than *approximately drunk*.
34. **`lib/knobs.rb`** [cheap] — nineteen documented knobs the sets do not read,
    so a set cannot be steered without editing it.
35. **`lib/taste.rb` and the scoring modules** [deep] — `mix_score`,
    `groove_score`, `harmony_score` and `spectral_audit` can each judge a render.
    Nothing judges a pass. A set that scored itself and refused to journal a bad
    take would make the catalogue self-curating.
36. **`RINGTONE_LAYER` and `PAD_LAYERS`** [cheap] [risk] — known-good layers with
    known switches, unreached from `live/`.

### C · Drums (37–46)

37. **Run `lib/kit_dig.rb`** [cheap] — it cuts a kit from `samples/own/` by
    running demucs and keeping only the drum stem. It has never been run: there is
    no `provenance.json`, and `samples/drums/custom/` is the downloaded
    `03-soulful-vintage`. Our own drums are one command away and beat re-buying
    anything.
38. **Re-acquire Goldbaby** [yours] — nothing on this machine is named it. The
    licences presumably survive the robbery even though the sets did not; the free
    packs would do to start. This is the single named ingredient of the lost
    chain that is simply absent.
39. **More than one sample per role** [cheap] — `LIVE_KIT` plays one `kick.wav`
    for every kick in the piece. Real machines and real drummers do not repeat a
    waveform, and round-robin over a folder is the difference between a kit and a
    trigger.
40. **Velocity, not just position** [cheap] — `drunk_kit` jitters *when* a hit
    lands and never *how hard*. Dilla time is both, and the level dimension is the
    one that reads as a human.
41. **Ghost notes from the snare recording** [cheap] — a ghost is a quiet short
    snare, not a separate file. Deriving it would remove a role from `KIT_ROLES`
    and make more kit directories qualify.
42. **The two-kick habit** [cheap] — the engine already alternates a second kick
    body (`kit[:ind_kick]`). The live rack does not.
43. **Kit-aware mix weights** [cheap] — the sampled bus gain was matched by
    rendering and measuring, by hand, once. A calibration step that measures each
    kit on install and stores its trim is the version that survives a new kit.
44. **Swing that is not jitter** [cheap] — the hat pattern adds a flat 34 ms to
    odd steps. That is a swing setting, the exact thing the comment above it says
    this is not.
45. **Name a `DRUM_LOOP` replacement** [yours] [risk] — it currently falls back to
    `~/Downloads/techno_drums.mp3`, outside the repo and against the crate rules.
46. **A kit from the crate itself** [deep] — every rack has a discarded drum stem
    (see 2). A kit cut from the same record as the bed would glue in a way no
    imported kit can.

### D · The crate, and not losing it twice (47–58)

47. **Record the source URL at fetch time** [cheap] — forty-one of forty-two
    sources are gone with no URL anywhere. This is the same failure that took the
    Ableton sets: irreplaceable material with no way back. It is a one-line change
    and it is the most important item on this page.
48. **Write provenance before the audio** [cheap] — a sidecar written first
    cannot be outlived by what it describes, which is how `henrik_debich` alone
    survived.
49. **Checksum the racks and deduplicate** [cheap] — 161 rows, 123 unique wavs, 38
    phantoms in 28 collision groups. Dropping duplicates is measurement, not
    judgement.
50. **A silence floor on the downbeat measure** [cheap] — the rotation fix for the
    153 mis-cut racks is blocked on this, because a quiet tail currently scores as
    a bar line and one rack starts at −57 dB.
51. **Then rotate the 153** [deep] — content-preserving, since a rack is one whole
    period.
52. **Back the crate up off this machine** [yours] — `samples/` is gitignored by
    path, the renders are gitignored, and the one copy of both is a laptop. The
    robbery is the argument.
53. **A crate manifest that is not the audio** [cheap] — titles, seams, keys,
    worth scores and URLs in one committed file, so a lost crate can be re-cut
    rather than merely mourned.
54. **Dig more** [cheap] — `samples/dug/` holds one file. `dig`, `dig-seams` and
    `dig-cc` exist and work.
55. **Attribution as a build artifact** [cheap] — `credits` exists. A set that
    plays CC-BY material should be able to print what it owes without being asked.
56. **Key-aware bed selection** [cheap] — all 161 racks now carry `key`; nothing
    reads it. Two decks (3) and any harmony over a bed need it.
57. **Retire `sample_worth`'s single number** [deep] — it is seven terms collapsed
    to one, and the collapse is where a set loses the ability to ask for a
    *kind* of record rather than a *good* one.
58. **A rack the operator marked** [cheap] — no way exists to say *this one*. A
    starred flag in the worth table would outrank every automatic score, which is
    the correct hierarchy.

### E · Playing them, not running them (59–70)

59. **A set should not exit** [cheap] — every set renders a fixed block and stops.
    A performance does not.
60. **Change something while it plays** [deep] — the engine already has
    `asendcmd` modulation and a `modulate` command; `MOD_RATE_HZ` names its
    resolution. The live rack builds one static graph.
61. **MIDI in** [deep] — the difference between a generator and an instrument.
62. **A pass you can nudge** [cheap] — drag, kit, weights and drop points are
    all decided before the first sample and cannot be touched after.
63. **Cue the next bed** [cheap] — `pick_bed` chooses once, silently. Being able
    to see and reject the next choice is most of what a DJ does.
64. **Mute groups** [cheap] — kit, bed, phrase, crackle. Four switches would make
    the sets performable with nothing else on this list done.
65. **Tap tempo** [cheap] — the grid is derived from the record. Sometimes the
    record is wrong.
66. **A set that listens** [deep] — `LISTEN_PASSES` exists in the engine.
67. **Two sets at once** [deep] — `broadcast.sh` runs one at a time by design; the
    interesting case is a pad set under a beat set.
68. **Stop cleanly** [cheap] — killing audio this session meant killing processes.
    A set should end on a bar.
69. **A visible transport** [cheap] — bar number, section, next change. The banner
    prints once and then ninety-six seconds pass in silence.
70. **The rig on the box** [yours] — `playlist.brgen.no` is the label. A set
    rendering nightly on vm23 into the catalogue is a different project than a set
    played on a laptop, and the capacity ceiling there is real.

### F · Keeping, naming, releasing (71–82)

71. **Every take, not the kept ones** [yours] — `--keep` is opt-in and a good pass
    is recognised after it has gone. Ring-buffering the last ten renders costs
    disk and no decisions.
72. **A take is not a wav** [cheap] — `renders/live_<seed>/` holds an ignored wav
    and a tracked json. That asymmetry is right and should be stated somewhere a
    reader finds it.
73. **Replay verification in the suite** [cheap] — three determinism defects were
    found this session by rendering one seed twice and comparing hashes. Nothing
    stops a fourth.
74. **Name the takes** [cheap] — a seed is not a title. `dilla` already generates
    track names.
75. **Stems** [cheap] — `VOICE_STACK_STEMS` exists for the engine. A kept take
    that cannot be remixed later is a photograph, not a session.
76. **Export the set, not the audio** [deep] — the thing that was lost was
    editable. A take that reopens as parameters is the only real answer to the
    robbery, and the `.als.rb` naming already claims it.
77. **A catalogue file** [cheap] — `project/liveset.jsonl` is a log. A catalogue
    is the subset worth keeping, in order, with titles.
78. **Mark the three that must not be shared** [cheap] — the existing label rules
    already distinguish them and the live rig knows nothing about it.
79. **Loudness for the destination** [cheap] — every set ends in `dynaudnorm` and
    a limiter at a hand-picked `volume=`. Integrated LUFS is a solved measurement
    and lies about speech over music, which matters for 7.
80. **A sleeve** [yours] — `STUDIO/postpro` grades images and `repligen` generates
    them. A catalogue with covers is a release.
81. **Publish the tracklist** [yours] — `playlist.brgen.no` exists and is empty of
    this.
82. **Delete nothing automatically** [cheap] — the scratchpad sweeps audio, and a
    long render that lands there is gone. Renders must be written outside it and
    be resumable.

### G · The master chain, against the one that was lost (83–92)

83. **Verify `vcs` against the plugin** [yours] — `Rack.vcs` is `aphaser` into
    `aecho` and was written toward *summing phasy* from description alone. Nobody
    has A/B'd it against the real thing, and the operator is the only person who
    can say whether it is close.
84. **Count the instances honestly** [cheap] — the sets run five or six Sonitex
    stages and five or six VCS stages. *Tons* was the word used about the lost
    chain. Whether more is more here is measurable and unmeasured.
85. **Order matters and is unrecorded** [yours] — where in the chain each instance
    sat is not something the sets can guess.
86. **Per-channel versus master** [cheap] — the current placement is at every
    summing point, which is defensible and is not what a plugin chain on a master
    bus does.
87. **Gain staging as a measurement, not a constant** [cheap] — `vcs` carries a
    `volume=1.9` makeup that exists because three instances were throwing away
    22 dB. That is the right fix and the wrong form: it should be derived.
88. **`sonitex` runs its crusher at half strength** [cheap] — `acrusher` defaults
    `mix=0.5` and `Rack.sonitex` never sets it, so all eleven stages are fifty per
    cent dry. Whether full strength is better is an ear question; that the knob
    was never turned is a fact.
89. **The 1260 is a sample rate as much as a bit depth** [deep] — `acrusher` also
    carries `samples` (1 to 250, currently 1, meaning off) and an `lfo`. Bit
    reduction alone is the cheapest third of what a 12-bit sampler does.
90. **Tape before the console** [cheap] — `lib/tape_hysteresis.rb` is written and
    unused in `live/`, and tape is where the lost chain's *old* came from.
91. **A dry control** [cheap] — no set can be heard without the room. Nothing
    proves the room is an improvement.
92. **Measure THD, not taste** [cheap] — `CONSOLE_STACK`'s documentation cites a
    measured 23 dB figure. The live rack cites nothing.

### H · Instruments before findings (93–100)

93. **Nothing in the suite covers `live/`** [cheap] — three sets, a shared rack and
    a recall tool, and `grep` over `STUDIO/test` finds no reference to any of it.
94. **A graph that builds is not a graph that sounds** [cheap] — two defects this
    session were empty filter strings from Ruby comments inside line continuations,
    which ffmpeg reported as `No such filter: ''`. A lint over the built graph
    would have caught both before the render.
95. **`aloop` is not reproducible at scale** [deep] — proven at 1.5 million
    samples, fine at 120 000, bisected to the filter. The workaround is in
    `ambient_pads`; the boundary is unknown and the other sets sit on the wrong
    side of not knowing.
96. **Every generator needs a seed** [cheap] — `anoisesrc` seeds from the clock.
    One audit over the tree for unseeded sources would close the class rather than
    the instance.
97. **PRNG draw order is an interface** [cheap] — adding a `rand` above an
    existing one silently invalidates every journalled seed. Nothing states this
    and nothing tests it.
98. **A/B by rendering, always** [cheap] — the kit change was verified by
    rendering seed 777 against `HEAD` and comparing SHA256. That is the standard
    and should be a script rather than a habit.
99. **Level-match before judging** [cheap] — the louder arm wins every informal
    comparison, and three of this session's comparisons needed a measured trim
    before they meant anything.
100. **Ask what the lost sets sounded like, in more detail** [yours] — tempos,
    lengths, whether any were performance sets rather than beat sketches, what a
    typical one had on its channels. Four sentences from the operator are worth
    more than any twenty items above them.
