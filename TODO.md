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

`WISHLIST.md`, beside this file, is the other half and not a second copy of it.
It holds forward work: wishes, hypotheses, and the shape a tree would take if
someone rebuilt it — several hands, each section dated and signed. This file
holds records, and a record carries the measurement that opened it. The test is
whether something was measured against the tree, not whether it sounds like
work: an unmeasured proposal belongs there however concrete it reads, and a
wish that has been read against the tree belongs here. Where the two touch one
subject only one of them carries it. Two backlogs saying the same thing is the
defect this repo keeps writing down.

---

## MASTER

### Rule and AST-detector backlog

Deterministic detectors in `MASTER/lib/review/scan/rules/`, following the
`MiddleManRule` / `NOISE_NAME` pattern landed 2026-08-29. Each gives a
currently semantic-only concept a keyless detector. All six were verified absent
from `data/rules.yml`, `law/`, and `lib/review/scan/rules/` before being listed —
genuinely missing, not already built under another name.

Four of the six are built, 2026-08-31. Each was drafted, measured against all
four trees, and narrowed against the false positives that measurement found
before it was allowed into the registry — the numbers below are what that cost,
and they are in the rules' own comments so the next reader does not re-derive
them. `MASTER/test/test_smell_detectors.rb` holds each one twice: a source it
must flag and a source it must not, because an exemption nothing tests is a
comment.

- **`BOOLEAN_TRAP`** — **done**. A positional parameter defaulting to a boolean;
  keywords are exempt, since `cache: true` already makes the call site say what
  is true. 1 finding tree-wide (`postpro.rb` `shadow_lift`). Narrow on purpose.
- **`DATA_CLUMPS`** — **done**, and note the plural, for the reason the
  paragraph below already gave: the prior in `data/rules.yml` and the
  `rule_deps.yml` node both name `DATA_CLUMPS`, and both now resolve. 48
  findings across 30 files, down from 81 before two exclusions: identical
  signatures are one interface implemented many times rather than a clump —
  `check_ast(ast, code, path:)` is a contract, and its nine implementers were 33
  of the original findings — and overlapping windows over the same signatures
  are one clump seen three times, so the longest run wins.
- **`TYPE_IN_NAME`** — **done**. 44 findings across 24 files, down from 85.
  Three exclusion classes, each a measured false positive: `to_hash`/`from_hash`
  is the Ruby conversion protocol, a digest is spelled `_hash` too (`prev_hash`
  renamed to `prev` loses the only thing the name said), and `_list` is a domain
  noun as often as a type. `old_string`/`new_string` are exempt because they are
  the edit-tool schema this runtime hands a model — an external contract, like
  `to_hash`.
- **`NUMBERED_NAME`** — **done**, but only for numbered *siblings*: a name whose
  stem appears in the same file with a different number. 5 findings, all of them
  `mix_v7` through `mix_v11` in `dilla.rb`. Without the sibling requirement it
  found 15, of which `fet1176`, `fairchild670` and `stc8` are the names of real
  hardware — an 1176 compressor, a Fairchild 670, a Coles STC-8 — and `inv3` and
  `normalize_to_y1` are maths. A lone number in a name is usually a fact about
  the world. Locals were measured and dropped for the same reason: 114 findings,
  nearly all dilla and postpro, where `t1` and `d8` are the notation the DSP is
  transcribed from and `prev2` is the sample two frames back.

The other two are **measured and blocked on the cross-file index**, which is the
larger AST work listed below. This is not a guess about them; both were built as
drafts and run over the tree:

- **`LAYER_CAKE`** — a chain of sibling methods each of which only forwards.
  Built and measured at both plausible depths. At three links, which is the
  honest reading of "a call chain that only forwards", this tree has **none** —
  and a rule that fires on nothing joins `rule_audit.silent`, which is already
  over its ceiling. At two links it finds 9, and reading them says why that
  threshold is wrong: three are `rescue_handlers.rb` naming one exception each
  before forwarding to `render_http_error`, which is the shape `rescue_from`
  requires, and the rest (`ok? -> ok`, `unwrap -> value!`) are aliases. A
  two-link forward is an alias, not a cake. The finding underneath: a real layer
  cake spans files — controller to service to repository — and no per-file rule
  can see it. It waits on the symbol index.
- **`DEAD_ABSTRACTION`** — same answer, arrived at the same way. Measured
  tree-wide with a throwaway cross-file census. The class half is precise and
  almost empty: 4 classes declare an abstract method (a body that is only `raise
  NotImplementedError`), and exactly **1** has fewer than two implementers —
  `MASTER/lib/io/gateway.rb:5`, with none. The module half is a false-positive
  machine and must not ship as written: 367 of 419 modules that define methods
  are "included at most once", because nearly every module in this tree is a
  `module_function` namespace rather than a mixin, so the census measures
  Zeitwerk's file-to-constant mapping and calls it a dead abstraction. One real
  finding does not pay for a rule; the single `Gateway` is worth a look by hand.

**Already exist — do not re-list these as todo:** `LONG_PARAMETER_LIST`,
`PRIMITIVE_OBSESSION`, `FEATURE_ENVY`, `COUPLER_SMELLS`, `LAZY_CLASS`,
`SPECULATIVE_GENERALITY`, `NO_SHOTGUN_SURGERY`, `TEMPORAL_COUPLING`.

**Closed 2026-09-04, and it closed the right way round.** The advice was to name
the detector `DATA_CLUMPS` so the prior and the dep node would wake up, and that
is what happened: the rule is built, the scanner carries the id, and both rows
now resolve. `violation_priors["DATA_CLUMPS"]` weights it and
`PRIMITIVE_OBSESSION after: [DATA_CLUMPS]` orders it.

The census the paragraph deferred is settled too, in `72a8cfae8`. Three attempts
gave three answers because three different instruments were being used, and each
is right about its own question — `Rule.registry` is short until `RuleDSL` is
touched, a regex over `law/` and the rule DSL sources sees ids the scanner never
builds, and only one of them answers "does this key weight anything". That one
is: build the scanner and read `@rules`, which is the collection `RuleOrder`
receives. It holds 145 String ids. Measured that way, `violation_priors` had 59
keys of which 4 resolved and `rule_deps` had 35 of which 17 did; the dead rows
are gone and both headers now state the invariant. See "From the 2026-09-04
MASTER audit" below.

#### Larger AST work — multi-session projects

These are not single detectors; each is its own sitting, with an owner and a
design, not a sweep.

- **A cross-file AST / symbol index.** Every rule that needs to know "who
  implements this" or "who calls this" (`DEAD_ABSTRACTION`, `LAYER_CAKE`,
  feature-envy across files) currently cannot see past the file it is in.
- **An incremental scan cache keyed on file SHA.** Re-parse only what changed;
  a full scan re-walks the whole tree every run.
- **tree-sitter for real JS / SCSS ASTs.** The JS and SCSS rules are lexical
  because there is no real parse tree for those languages here; a real AST
  retires whole classes of false positive.
- **Prose / CSS / audio "AST" rules.** The same deterministic-detector idea
  applied to non-Ruby artifacts — documents, stylesheets, and dilla's render
  graph — each of which currently has only lexical or no checks.
- **A clone → extract-method autofix.** `DUPLICATE_CODE` detects; nothing
  extracts. The autofix that turns a detected clone into a shared method.

### Debt — resolved records

Closed records are deleted when they close, and `git log` holds them. A finding
that is fixed is not a backlog item, and a file that keeps every one it ever had
teaches the reader to skim. What stays here is forward work and the false
positives worth not re-discovering — those are guards, not history.

### Still open after this session

- **`data/rules.yml` is under its budget as of 2026-09-04** — 3690 against a
  ceiling ratcheted from 3944 in `72a8cfae8`, which removed 254 body lines of
  declaration no reader consults. The record below is kept for its method, which
  is the part that transfers: a field whose removal moves no measurement was
  measuring nothing, and the proof is three censuses reading identically across
  the change. The `pwa:` question it ends on is answered — the block stayed and
  the room was found elsewhere.

  What it said at the time: **`data/rules.yml` is 35 body lines over its budget**, and the 35 have a name.
  102 lines came out: a row whose id `law/` owns is rejected by
  `YamlDeclarativeRule` before any detector field is read, so the `languages`,
  `path_match`, `requires_absent` and `whole_file` those rows carried scoped a
  detector that is not there — the scope is stated once more, correctly, in the
  law file. Removal only, and proved by the three censuses that read this file
  reporting identical numbers after it: a field whose removal moves no
  measurement was measuring nothing.

  That leaves 3714 against 3679, and the remainder is the 37-line `pwa:` block
  `3f5447c17` added to `design_rules` an hour earlier. So the file was at its
  ceiling once the dead declarations went, and what is over is one deliberate
  addition rather than accumulated fat. `limits.yml` says "Measured once at the
  rename. Down only from here", so this is an owner's call between shrinking the
  `pwa:` block and moving a ceiling that predates a consolidation it never
  measured — not something to settle by finding 35 more lines to cut.

  Two more duplications sit in the same rows and were left: `fix` and `source`
  repeat what the law file declares, but `/why <RULE_ID>` reads both out of
  `rules.yml` rather than out of `law/`. Converging `WhyExplainer` onto the law
  is the move that makes those safe to remove; doing it in the other order
  empties a live surface.
- **Four ratchets are over, re-measured 2026-09-05 after `lib/autonomy` went**:
  `spine.lib_body_ceiling` 38253/37464, `growth.master` 1050/1047,
  `growth.rails` 2371/2358 and `growth.studio` 155/138. Every one that is left
  counts size, which is the shape worth knowing: what remains is folding, and
  folding is a sitting rather than a fix.

  `growth.master` is three files over and one of those three is the test that
  came with the hooks wiring, named rather than absorbed. A constant-name census
  over `lib/` offered three files to fold and all three were wrong:
  `HashDigCompat` is required by path and called by method name,
  `RubyRuleSupport` is used inside its own multi-class file, and `Trace::Hooks`
  was three-quarters wired. Two files is exactly the distance at which a census
  stops being a measurement and starts being a shopping list.

  **Extraction cannot pay `spine.lib_body_ceiling`, and this file said it could.**
  The counter is non-blank non-comment lines across `lib/**/*.rb` minus the
  Zeitwerk wrappers, so splitting `speech.rb` into two files under `lib/voice`
  moves the lines and adds a `def` and an `end` — the number goes up. Only three
  things move it: deleting code nothing reaches, collapsing a real duplicate, or
  a sponsored raise, which `spine.yml` allows "in a commit that names what the
  lines buy" and caps with `consecutive_raises_allowed`.

  What de-duplication is actually worth here was measured rather than guessed.
  `CrossFileAnalysis` over `lib/` names six DRY pairs; three are collapsed (the
  finding-shape accessor written four times, a dead `mtimes`/`quiescent?` pair,
  and `load_data` written twice) for **31 lines against an overage of 1,162**.
  The other three are judgement: `read_js` is byte-identical in two `lib/rails`
  files and the only home is a new mixin, which costs `growth.master` a file to
  save four lines; `grade_for`/`band_for` and `markdown_files`/`files` match on
  shape and not on meaning. `CROSS_FILE_DRY`'s 22-file `File.read` and the
  `MAGIC_NUMBER_SPREAD` rows save nothing at all — a shared reader is still one
  call per site.

  So the arithmetic is: this is not a de-duplication problem. The only
  line-counts of the right order are `lib/autonomy` at 400 (the wire-or-delete
  decision above) and `lib/review` at 622 over its own budget, and neither is a
  sitting somebody finishes in an afternoon.

  Six of the ten rows that were over closed the same day. `self_findings` is at
  151 from 165 — two findings were in the scanner itself, and the other twelve
  were a frozen-literal comment that sat under a `require` and so declared
  nothing, six dilla files that had none, and a broadcast script that says in a
  marker why strict mode would end the broadcast. `data_reach` is at 35 because
  `doc_baselines.yml#doc_paths` gained the reader it never had. The three RAILS
  rows — `model_contract.uninferrable_inverse` 54, `model_contract.no_validations`
  9 and `destructive_action.unconfirmed_destroy` 29 — are 0 against floors of 0.

  `spine.lib_body_ceiling` fell 636 net: 695 back from the antigravity collapse,
  59 spent on rule fixtures. `growth.master` fell six files. Read the live figures
  from `MASTER/bin/pub4 measure`; the list here has been three, then five, then
  six on three consecutive readings, so its value is the shape and not the
  numbers. `data_reach` fell 37 to 36 when `three_mirror_redundancy` gained a
  reader, and the remaining 36 were read once: most are the false-positive
  classes this file's own 2026-08-12 entry names. `topologies.yml`'s eight and
  `runtime.yml`'s five are served whole through `RuntimeCatalog` and
  `/runtime/topologies`, and the browser picks the sections by name;
  `personas.yml` and `models.yml`'s ollama rows are registry entries selected by
  a config value. `rules.yml#schema_metadata` is the same shape read once more
  on 2026-09-05 and is a third class again: nothing loads the key, and the block
  under it documents two fields — `reversibility` and `blast_radius` — that
  `semantic_rules.rb` and `meta_rules.rb` do pass to `Finding.build`. It is a
  schema note, not config, and deleting it would delete the only statement of
  what those two fields may hold. Do not delete from this list without finding the reader —
  that entry says why a stricter version of the tool is not buildable, and this
  is what its error looks like from the inside.
### `/scan`'s autofix corrupts code — opened 2026-08-31, do not run it on a tree

Trialled on `RAILS/gates` alone before turning it loose on RAILS's 2,326 files.
It wrote three files and **two of the three are damage**:

    RAILS/gates/support/design_metrics.rb
    -  brgen/engines/*/app/assets/stylesheets/*.scss
    +  brgen/engines/*/app/assets/stylesheets/*.scss,

`TRAILING_COMMAS` fired inside a `%w[]` array, where a comma is a literal
character and not a separator. The glob now ends in a comma and matches nothing,
so `light_only_vertical_keys` would report a clean tree having read no file.

    RAILS/gates/support/geometry_probe/walk.js
    -  return seen[sel] === 1 ? sel : sel + '[' + seen[sel] + ']';
    +  return seen[sel] === 1 ? sel : `${sel}[${seen}`[sel] + ']';

The template-literal rewrite mangled a three-term concatenation: it closes the
template early, then indexes the resulting string by `sel`. Every duplicate
selector key becomes `"undefined]"`. **`node --check` passes** — a silent
semantic corruption that survives a syntax check is the worst shape this has,
and it is the shape a tree-wide unattended run would have written everywhere.

Both reverted. The third change, a blank line in `webgl_surfaces.rb`, was
harmless. One in three.

The `%w[]` trailing-comma rewrite is pinned: `percent_word_array_close?` skips
`%w %W %i %I`, and `test_trailing_commas_skip_percent_word_arrays` holds both
directions. The template-literal call-site corruption was already closed
(`convert_string_concat` declines a chain followed by `(`). Other autofix
transforms can still mangle; `--no-autofix` remains the safe default on an
unattended tree until each transform has that shape of test.

Pipe mode used to ignore ARGV, so `bin/cli /scan RAILS` with no TTY printed
nothing and exited 0. It honors the argument now, then stdin. Paths still
resolve after `bin/master` chdirs into MASTER, so a sibling tree is `../RAILS`
or the `rails` alias.

### Tag Legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise, horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

### Spine Ceiling

**Not open.** The number, its full raise/ratchet log and the reasoning behind every
move live in `data/spine.yml`, which is the file `rake lint:spine` reads. This
section held a copy and the copy drifted — it read "38,294, allowance 1 of 2" while
`spine.yml` had ratcheted to 38,285 and cleared the log, which is the two-source
failure this register warns about elsewhere in its own words.

Worth knowing without becoming a second copy: the ceiling has ended each of the
last two days exactly at `lib/`, no headroom, so the next line added breaks the
ratchet and the paragraph below about paying a breach out of `lib/` is not
hypothetical. Read the current number from the task, never from here — the
figure this paragraph used to quote was stale within a day, twice.

What belongs here is the rule the ratchet taught, because it is not in the
mechanism:

**Ratchet once, at the end of a session, on a settled tree.** An intermediate
ratchet has already locked in a state that was not clean and blocked the work that
would have made it so (2026-08-03). And on 2026-08-12 a ratchet taken while three
other sessions had uncommitted `lib/` edits recorded a low that was not the
ratcheting session's to hold — in a shared checkout the honest moment is after the
tree stops moving, not after your own part of it does.

**A breach is paid out of `lib/`, not out of this file.** Three of the four breaches
so far were closed by deleting code nothing referenced; the fourth was a raise, and
it needed the operator to sponsor it because the orphan account was empty. That
sequence is the mechanism working. `rake lint:spine RATCHET=1` clears the raise log
when `lib/` genuinely falls, which is what makes the allowance a budget and not a
countdown.

**Measure in a clean worktree, never in the shared checkout.** On 2026-08-14 the
same change read `39251/39258` here and `39298/39295` at `origin/main` — 47 lines
of skew, entirely other sessions' uncommitted `lib/` edits. The shared-tree number
is not wrong about that tree; it is a reading of a tree nobody is going to commit.
`git worktree add --detach <path> origin/main` and run the task there.

#### Three raises, no ratchet, in one day — 2026-08-14

Not a complaint about any of them. Each was argued in `spine.yml` and each bought
something: +3 for per-visitor chat conversations, +44 and +10 for design-gate rules
that could not pass on correct markup, retiring 381 and then 434 findings. Net +57,
zero reductions, and `lib/` closed the day at exactly its ceiling again.

What that costs is legibility rather than lines. The header of `spine.yml` already
says it — "a ceiling that rises whenever a day's work pushes against it measures
nothing" — and the 2026-08-01 note already asked that the next raise not be granted
on "it was only a bug fix". A note left that same morning asking the following
session to ratchet rather than raise was read and raised past, twice, by sessions
doing legitimate work. So the honest reading is not that anyone misbehaved: it is
that the mechanism currently has no move available except assent.

**The orphan account is empty, verified rather than assumed.** Hunted before asking
for the +3: zero dead private methods across `lib/`, zero unreferenced constants,
and the fourteen classes a conservative sweep flagged are all false positives —
scanner rules reached through `RuleDSL`, `RubyRunner` called from `RAILS`.
`RiskClassifier`, the orphan the last audit named, was already deleted. Same
conclusion as 2026-08-12.

So "make `lib/` fall back first" no longer names a cleanup anybody can do on the way
past. It needs a decision that some subsystem is worth deleting or absorbing, which
is design work with an owner, not a sweep. Until someone takes that decision, expect
every feature to arrive as a raise, and read a green `lint:spine` as "the ceiling was
moved to meet it" rather than as "the spine held".

### Self-Test Debt

**agent-ignore** — triage only when the task explicitly targets scan rules.

`rake selftest` reports **12 findings, re-measured 2026-09-04** — 1 LINEARITY, 2
ABSTRACTION, 9 DENSITY, and 0 for every other law. It was 0 on 2026-08-19, and
six of the twelve are in `lib/ground/antigravity/`, a directory that did not
exist when that measurement was taken. The table and the reasoning are under
"From the 2026-09-04 MASTER audit" below; this section keeps the history of how
the count was driven to 0 the first time, because the method is what transfers.

The 1 of 2026-08-18 — `god class Constitution is 348 lines` — closed the way the
2026-08-12 idiom findings did: the count was the instrument, not the design.
NO_GOD_CLASS's line branch measured raw AST span, charging for rationale
comments — the counter DENSITY and lint:spine each already retired for the
same reason — so Constitution read 348 while holding 250 code lines against
the 300 limit. The branch now counts code lines through CodeMetrics, pinned
in both directions in `test_scan_rule_false_positives.rb`, and all 79 core
tests hold: no split, no exemption, and `rm -rf` stays blocked. The reverted
split (`972894e70`) stays reverted; nobody owes one. The day of
`self_violation` halting every `/through` fix stage ended with the unit
correction, not with anyone deleting the law's own reasoning to appease its
counter. Treat any count here as
true for the commit that carries it and no further: it has been 0, 1, 2, 3, 6 and
7 on different days of the same fortnight, and a "clean since" claim in
`START_HERE.md` was already stale once.

`test/test_heartbeat.rb` passes at the count above — 7 runs, 12 assertions, 0
failures on 2026-09-04. The note here that
`self_test_heartbeat_publishes_clean_scan_metrics` fails *because* the count is
non-zero no longer holds, so the count is not gated by that test and a
non-zero `selftest` is currently visible only to whoever runs the task.

Triage each new finding as: true violation to fix / scanner false positive / rule
exemption needed / rule threshold too strict / known debt to leave alone.

### The fold spine had never been scanned — opened 2026-08-12

**operator-priority** — this is a decision to make, not noise to chase.

`SelfCheck#run` scans `File.join(@root, "lib")`. So does `selftest`. For the
three weeks `core/` existed as a sibling of `lib/`, **every gate MASTER points at
its own source skipped the constitutional fold entirely** — the six files that
judge every effect before it touches the world were the only ones exempt from the
law they enforce. Nothing declared that exemption; it fell out of a path.

Merging the spine into `lib/` on 2026-08-12 subjected it, and it fails:

```
[ABSTRACTION] lib/core/constitution.rb:16  Constitution — 16 public methods (max 10)
[ABSTRACTION] lib/core/memory.rb:10        Memory       — 17 public methods (max 10)
[DENSITY]     lib/core/fold.rb:28          run          — 24 code lines (max 20)
```

`rake selfcheck` independently gains `NO_GOD_CLASS` 2 and `SILENT_RESCUE` 1 from
the same files. Measured twice, because attribution in a shared tree is a guess
otherwise: 19 → 22 on a clean HEAD worktree with only the move applied, and
17 → 20 in the working tree against the "Scanner noise" baseline below. Same +3,
same three files, from two different starting points.

**Two of the three are closed, by option 2 — 2026-08-12.** Nothing was
exempted, no threshold moved, and `core_files` was still 6 at that point.

- **`Constitution` 16 → 4.** Twelve of the sixteen are rule factories that only
  `default_rules` calls, verified against `lib/`, `test/`, `spec/`, `tools/`,
  `bin/` and `web/`. They are `def self.` — and `private` marks a position in the
  instance-method stream that class methods never enter, so the class read as
  fully public however it was arranged. They are now
  `private_class_method`, and `CodeMetrics.public_method_count` honours that
  declaration, pinned by `tools/fixtures/class_methods.rb`. ABSTRACTION was
  measuring the idiom, not the surface.
- **`Fold#run` 24 → 14 code lines.** The admitted half moved to a private
  `apply`. A private method is not a new concept, so `core_files` never came
  into it — the conflict below was real for decomposition into *files*, not for
  decomposition inside one.

`rake selftest` 3 findings → 1. `rake selfcheck` 20 → 19, `NO_GOD_CLASS` 2 → 1.
The +16 code lines this cost are accounted line by line in `data/spine.yml`;
they spent the second and last raise of the allowance.

**`Memory` closed by option 3 — 2026-08-12, operator-sponsored.** Option 2 could
not reach it: only `detect_host_memory_mb` was internal, and every other method
had a caller. That was the count telling the truth rather than measuring an
idiom. `Memory` was **three jobs in one object** — a transcript, an evidence
ledger, and the risk gates — and the Constitution reached straight past the first
to ask the other two.

`lib/core/proof.rb` is the second and third of those: what has been shown, and
what must be shown before `done`. `core_files` 6 → 7, the first raise since the
spine was written, argued in `data/spine.yml`. Memory 16 public methods → 7,
Proof 8, Constitution 4, Fold 2.

Two things were deliberate. Nothing forwards: the Constitution and the CLI reach
`memory.proof.*` directly, because a delegator would have kept the public count
where it was and hidden the seam the count existed to point at. And the +10 code
lines were **absorbed rather than raised for** — the raise allowance was spent,
`spine.yml` says the next line into `lib/` comes out of `lib/`, and a sweep found
no `lib/` file with a declared constant nothing else references. They came out of
the new code instead, leaving `lib/` net 0.

**`rake selftest` 3 findings → 0. `rake selfcheck` 20 → 18.** The fold is clean
under its own law for the first time since it was subjected to it.

What must not happen, and did not: the count being driven to zero by re-exempting
the fold, which would restore the invisible hole and lose the one thing the merge
bought — the fold is measured by the law it applies to everything else.

### Constitution Scan Debt

**agent-ignore** — `rake constitution` is broader than `rake selftest` and still
reports thousands of self-scan findings. Do not chase zero. Track the count down
by removing false positives and fixing high-signal violations.

#### Two copies found by reading the buckets — 2026-08-12

**3,602 findings / 125 actionable → 3,166 / 20**, without fixing a single line of
the code being scanned. Both were duplicate detections, found the way the veto
audit found its 119: by reading the findings instead of the count.

- **`NO_PUTS` 105 → 5.** Its exemption read `/now/cli`, and `lib/now/` was renamed
  to `lib/cli/` in `693d2630d`. The exemption kept pointing at the old address, so
  105 findings appeared in the largest *actionable* bucket — every one in
  `lib/cli/`, 100 of them in `lib/cli/cli/`, all of them decisions the rule's own
  author had already made and the rename silently undid. This is the
  exemption-outliving-its-subject defect inverted: the subject moved out from
  under the exemption, and a gate began firing on exactly what it exempted.
- **`learned_smells` 10 → 8.** `long_line` restated the registered `LONG_LINE` as
  a raw regex: 334 findings, of which **3** landed on a line no other rule
  reports — and all 3 in `lib/io/llm.rb`, which `LONG_LINE` deliberately exempts.
  So 331 duplicates plus a quiet override of an exemption, at `:warning` where the
  real rule says `:info`, with the id as its whole message. `debug_output` carried
  the *same* id as the registered rule, making its findings indistinguishable
  rather than merely doubled; its `autofix: remove_debug_call` names nothing that
  exists anywhere.

The other eight learned smells pass the test the EMPTY_RESCUE deletion used —
`magic_number`, `future_tense`, `duplicate_code`, `sycophancy` and `todo_comment`
are the only implementation of what they detect. Two entries went, not the layer.

Both pinned in `test/test_scan_rule_false_positives.rb`, and generalised: no
learned smell may share an id with a registered rule, and no two rules may report
the same long line.

### Scanner noise

**Re-measured 2026-09-05: 1 violation, `NO_GOD_CLASS` on `EventStore`.** What
closed the other two is under "From the 2026-09-04 MASTER audit" below. The
triage that follows is kept because the reasoning transfers — it is how each of
the 31 was classified, and three of those classes are why the number fell — but
the numbers in it are 2026-08-19 and are no longer the tree. One line in it is
now wrong on its own terms and worth reading with that in mind: "`etc` inside a
directory-alternation regex read as a placeholder", counted as a legitimate
false positive nobody could narrow. It was narrowable, and it was the last
error-severity finding standing between this gate and the design question that
is left.

**Three more learned smells failed the uniqueness test, 2026-09-05.** The 2026-08-12
pass above deleted `long_line` and `debug_output` for restating a registered rule
and kept the rest; three of the remaining eight fail the same test, and all three
fail it the same way — a raw regex repeating a registered rule's pattern, plus
whatever that rule deliberately spares.

- **`bare_rescue`** — `law/universal.rb`'s FAIL_VISIBLY says in its own header
  that it folds BARE_RESCUE, and it deliberately does not match `rescue => e`,
  which rescues StandardError and is the fix BARE_RESCUE prescribes. So the
  smell's findings were FAIL_VISIBLY's again on a silent rescue (0 unique) or a
  report against correct code. Its deletion also closed rule_hygiene's last id
  case collision.
- **`trailing_ws`** — TRAILING_WHITESPACE's pattern, with neither a path
  exemption nor a language scope on either side. Probed across `.yml`, `.md` and
  `.css`: 4 findings, 0 unique.
- **`todo_comment`** — a strict subset of TODO_FIXME's pattern, one marker
  fewer. Over `lib/` it scored 4 findings and 3 unique, and all 3 sat inside the
  `/review/scan/rules/` directory TODO_FIXME deliberately exempts, because a
  rule that names a marker is a detector and not a marker. Its whole unique
  yield was a quiet override of another rule's exemption — `long_line` exactly.

`rake selfcheck` was **31 violations across 7 rules** (measured 2026-08-19
after the law-fixture pass and the first twin retirement), every one triaged:

- `SILENT_RESCUE` 12 — the standing track above.
- `guard_expensive_ops` 9 — the verified false positives, still counted.
- **7 are scanner sources describing defects**: the registry UNBOUNDED_RETRY
  twin's own description/detector/message lines, chaos_agent's report
  strings, the SQL-null normalise transform's regex, FAIL_VISIBLY's detector,
  and `etc` inside a directory-alternation regex read as a placeholder. A
  lexical rule cannot see into a string or regex literal; these are the one
  place the pattern is legitimately spelled. Counted, per the 2026-08-15
  precedent.
- `never_batch_delete` 3 — self-owned temp-file cleanup verified line by
  line: Swallow rotating its own log backups, SemanticCache#invalidate_all!
  clearing its own root, Engines deleting the chunks it just concatenated.
  Not the operator-batch-delete hazard the rule guards.

It was 46-across-10 earlier the same day, and the delta is the law reading
itself, now closed structurally: `FileProcessor#law_conducted` runs
`Law.conduct` at the one read site, so every rule — bridge and registry alike
— sees law/ fixtures and detectors as declarations, not conduct.

#### The law had 72 registry twins, and they drifted — opened 2026-08-19, closed 2026-08-21

Closed in three sittings. The first eleven retired with the reverse-doctrine
discovery: the richer implementation wins, whichever side it lives on. The
final 42 (cdc7f7141): 28 registry blocks retired into their laws with the
narrowing ported and fixture-pinned, 14 laws retired into their richer
registry twins (Prism, tag_source, shebang awareness, indent walking), and
KEYWORD_ARGS folded into FEW_ARGUMENTS on both sides. The census also caught
the constitution's own inert config: law/rails.rb declared `languages
%i[rails]`, which FILE_LANGUAGE_MAP has never produced — four laws that had
never matched a file. Twin census reads zero; the twin-census check is the
regression guard.


#### The data layer's duplicate census — opened 2026-08-19, line-level collapses done 2026-08-21

`rake lint:dedup` (ContentDedupScan's first-ever reader) holds the line-level
census. The three recorded collapses landed 2026-08-21, each with its reader
traced first:

- **soul `absolute.anti_simulation`** — the voice.yml shadow (already one
  word drifted) is deleted, the fallback arm removed, and
  test_rules pins that the constitution accessor still carries the list.
- **The openrouter default** — providers.yml is the one source;
  `Master.openrouter_default` / `Master.free_primary_model` (boot/runtime.rb)
  are readers through the sanctioned loaders, the soul negotiable copy is
  deleted, and the reader-singularity ratchet is what forced the accessor
  shape.
- **Replicate env vars** — models.yml `media_providers` had **no reader at
  all**: the slugs live in voice/engines.rb and repligen, the env in
  providers.yml. The whole block was a declaration claiming a routing that
  never existed; deleted.

Both structural ones — the pairs the line-matcher cannot see, because one half
is Ruby — are closed 2026-09-05.

- **`Consensus::DEFAULT_MODELS`** restated models.yml's `three_mirror_redundancy.pool`
  under a comment asking the next reader to keep the two in step by hand, which
  is how a model swapped in one place leaves the consensus voting with one
  nothing else routes to. `Master.three_mirror_pool` is the reader now and
  `test_consensus.rb` pins the pool against the file, the quorum against the
  pool's size, and the injection point that keeps an explicit list winning.
- **`operator_principles` vs `principle_map`** was two vocabularies with nothing
  naming the authoritative one, and it settled itself: `operator_principles` is
  no longer a section of `rules.yml` at all — its 47 entries went to
  `law/practice.rb`, where each declares how it is checked. What was left were
  three references to the dead section, and the worst of them was a live gate.
  `RUNTIME_DOCS_YAML` sent an operator to `rules.yml#operator_principles` and,
  at error severity, told them to **delete** any `data/principles/*.md` — which
  is exactly what `Ground::Constitution` globs and parses. A rule forbidding
  what a live loader requires, invisible only because the directory is empty.
  That location is allowed now, one level deeper still fires, and the `/principles`
  empty message names the directory rather than the vanished section.


Worth naming: `SelfCheck#gate!` — the method that would halt background
autofix on this count — has **no caller** (verified 2026-08-19), so this
number gates nothing. The halt that stopped every /through fix stage on
2026-08-18 was SelfTest's laws count via ai_boot's `self_violation`
subscription, cleared when NO_GOD_CLASS switched to code lines.

The 13 is not the 11 of 2026-08-13 plus the exemption lifted below. Measured both
ways on one tree: the same 13 sites outside `lib/review/scan/rules/` are reported
by the old predicate and the new one, so the two that arrived since are drift in
`lib/`, and every finding the exemption had been hiding is fixed rather than
counted.

#### The rescue rules exempted the scanner from itself — closed 2026-08-15

`SILENT_RESCUE` and `NARROW_SILENT_RESCUE` both carried
`next [] if path.to_s.include?("/review/scan/rules/")`, with no comment, no gate
and no false positive to justify it: all **11 findings it suppressed were real
code**, none a comment or a regex literal. The directory it excused is the one
where a swallowed error does the most damage, because a rule that returns `[]`
reports the file it failed on as clean.

Two of the 11 were law failing open rather than ordinary swallowing.
`VetoPatternRule#load_patterns` rescued to `{}` and `#check` returns `[]` on an
empty pattern set, so an unreadable `data/rules.yml` retired every veto pattern
in silence; `YamlDeclarativeRule` dropped any declared rule whose
`detect_lexical` would not compile, which is inert law arriving by exception.
Both now report through `Swallow.log(..., severity: :load_bearing)`, as does
`Rule#check`, the shared AST default whose `rescue → []` made a bug in any
`check_ast` indistinguishable from a clean tree.

Three `rules_mtime` methods rescued `File.mtime` to `nil`; they ask
`File.exist?` now, since a missing file was the only failure they meant. One
inner rescue in `NestingDepthRule#scan_depth` was deleted outright rather than
made to report: it duplicated the base-class rescue one frame down, and two
layers of swallowing over the same call is how the first one stays invisible.

**An empty rescue body is a discard again.** `EMPTY_RESCUE` was deleted on
2026-08-12 as a pure duplicate, and "coverage is unchanged by construction" held
for every shape but one: `discard_body?` walked to the first non-blank line,
found `end`, and called it neither handled nor discarded. Probed rather than
argued, which is the only reason it was found. `lib/pub4/check_runner.rb` held
the single live instance.

It read 17 with `SILENT_RESCUE` 10 on 2026-08-12. The +1 arrived without a new
`rescue` anywhere in `lib/` — `git log -p` over the range shows zero added rescue
lines and the tree is clean — so it came from a rule moving under the code rather
than code moving under the rule, most likely the scan narrowing in `fca0883e5`.
Left as measured rather than explained away, which is what the caveat below is
for.

It was 34 across 6 the day before, and 17 of the 17 that went were the rules
misreading their own tree rather than code getting fixed:

- `EMPTY_RESCUE` 11 → **deleted.** It shared `SilentRescue.discard_body?` with
  `SILENT_RESCUE` and `NARROW_SILENT_RESCUE` and differed only in which `rescue`
  lines it matched, so across MASTER it produced 37 findings and **0 unique**. Its
  own comment claimed it "doesn't re-flag what those already catch"; it re-flagged
  all 37, 8 of them at both `:error` and `:warning` at once. It also made severity
  depend on comma count — `rescue Errno::ESRCH` was an error, the identical
  `rescue Errno::ESRCH, Errno::EPERM` only a warning — because its naked-class
  branch matched one whitespace-delimited token.
- `bare_rescue` 1 → 0 and `fail_visibly` 1 → 0. Both were the entry above:
  "the autofixer that repairs bare rescues flagging its own source" was
  `@transforms << :bare_rescue`, a symbol, matched by `rescue\s*$`. Recorded here
  as noise for weeks; it was one lookbehind.
- `guard_expensive_ops` 9 → 5. The four that went were prose about truncation and
  `rm -rf`. `detect_lexical` is a raw regex over raw lines, so the YAML bridge read
  comments as code — the same defect as `DEBUG_OUTPUT` reading `p << "…"` as a
  `Kernel#p` call. Comment-only lines are blanked in the bridge now; `scan_lines`
  itself is untouched, because several rules mean to read comments.

The five surviving `guard_expensive_ops` are still false positives — a `truncate`
string helper, a policy regex *listing* the forbidden verbs, a `CONFIRM` array of
symbols, a fixture string — and were verified line by line as code rather than
prose, which is why they stay counted. Narrowing further needs its own reasoning.

It was 71 before `STALE_NAMESPACE` (25 → 0) and `COMPLETION_THEATER` (12 → 0) were
narrowed on 2026-08-01.

Every narrowing on this list is pinned in both directions by
`test/test_scan_rule_false_positives.rb`: the false positive is gone *and* the real
violation still fires. Copy that shape — a rule whose false positives are removed
without a test asserting it still fires has been turned off, not fixed. The
2026-08-12 pass added the two cases that shape does not cover on its own: a test
that fails if `EMPTY_RESCUE` is ever re-registered, and one that asks *every*
registered rule how many of them call a given `rescue` line a discard, where the
answer must be one. A comparison between the two survivors would have passed
before the deletion, since those two were already disjoint — which is why a
duplicate rule can sit in a tree this heavily tested for as long as it did.

#### The veto patterns had never been read — audited 2026-08-12

`selfcheck` is error/critical only, so `:veto` findings never reached it, and
`rake constitution` sorts them into a bucket outside the actionable budget.
Nobody had opened either. All five patterns, every finding across `lib/` read
and classified: **229 findings, 4 real.**

| pattern | before | after | what it was matching |
|---|---|---|---|
| `sql_injection` | 87 | 0 | `execute\|query.*#\{` binds as `(execute)\|(query.*#\{)`, so the bare word `execute` was a merge blocker — `execute_job`, `pre_execute?`, and the parameterized form the rule prescribes |
| `unfinished` | 119 | 0 | `pending` (an order state, and inside *depending*), prose ellipsis, and Ruby's exclusive range `[0...-1]` |
| `unsafe_calls` | 23 | 3 | markdown fences and code spans inside Ruby strings; `Shellwords.escape`'d backticks and the Open3 arg-array form, both of which are the fix this rule prescribes |
| `race_conditions` | 0 | — | **deleted.** `if.*\n.*=.*\n.*if` needs three lines and `scan_lines` matches one at a time. It could never fire, at `:veto`, since it was written |
| `secrets` | 0 | 0 | correct, and the only one that was |

The three surviving `unsafe_calls` are real shell-outs with interpolation
(`ground/host_budget.rb`, `trace/snapshot_collector.rb`, `voice/engines.rb`);
two take their value from `ENV`.

Two gaps left open rather than papered over, both needing an AST rule instead of
a lexical veto — `scan_lines` is per line and cannot see across one:

- **SQL built in a heredoc.** `@db.execute(<<~SQL, args)` puts the interpolation
  on a later line than the call. The one instance in `lib/` is parameterized and
  safe; the rule cannot tell, and would not catch a real one.
- **Check-then-act.** What `race_conditions` was reaching for. If the concern is
  wanted it needs a real rule class; a three-line regex was never going to be it.

Also fixed here: `VetoPatternRule` scanned raw source, so a comment describing a
shell interpolation vetoed the file explaining it — the same defect
`without_comment_lines` was written for on the declarative side, which the veto
path never got. It is now per-pattern: `unfinished` declares `reads_comments`
because a work marker lives in a comment, and nothing else does.
`without_comment_lines` moved to the shared `Rule` base rather than being copied.

### Three principles with no scanner rule — evidence pinned, coverage not faked

`pledge_unveil`, `secrets_rotation` and `audit_logging` still have empty
`rule_ids` in `data/principle_map.yml`. Linking them to `LEAST_PRIVILEGE` or
`SECRET_PROXIMITY` would close the map gap without measuring the thing the
row names. `test/test_principle_evidence.rb` pins the sources that exist:

- `pledge_unveil` — `lib/ground/pledge.rb` applied from `lib/boot/master_boot.rb`
- `audit_logging` — `lib/trace/log/audit.rb` append-only `tool:before` log
- `secrets_rotation` — no rotator. Keys live in `/etc/*.env` on vm23.

A registered rule that actually detects a process skipping pledge, a tool
that is not audited, or a credential that never expires is still the gap.
Do not point `rule_ids` at a neighbour.

### Inert law and config

The dominant defect class in this tree: a declaration with no reader. Both named
instances are closed and both closures are worth copying rather than the fixes
themselves.

- `data/limits.yml` — **closed.** 29 of 38 keys had no reader and the generic
  accessors made them look reachable. The file is now split into enforced keys and
  a `guidance:` block, with `test/test_limits_split.rb` failing in both
  directions: an enforced key that loses its reader, and a guidance key that grows
  one. `/orient limits` still serves the file whole, so the split relabels rather
  than hides.
- `data/security.yml` (then `data/security/defaults.yml`) — **closed** the same way, by
  `test/test_security_defaults.rb`. Its worst case was worse than inert: the
  ingress rate limit was *also* hardcoded in `IngressController`, so file and code
  could disagree in silence.
- `data/patterns.yml` — **closed** for three keys. `gh`, `sweep_techniques` and
  `vocabulary` had no reader and are gone; `violation_priors` and
  `stale_namespaces` had one and were in the wrong file, so they sit in
  `rules.yml` beside the rules that read them. `data_reach` drops 49 to 46 and
  holds there. A first pass by grep called six keys dead: `prompt_archaeology`,
  `repo_topics` and `refusal_templates` have readers that the pattern missed,
  which is why `data_reach` is the instrument and grep is not.

- `data/tts.yml` and the whole Transcendent path — **the web half stands; the
  "1,500 unreached lines" does not, re-measured 2026-09-05.** What is still true
  is the web: `Voice::Speech`'s three web consumers — `health_controller`,
  `tts_controller`, `TtsJob` — all enter through `synthesize_streaming_to_file`,
  which goes socket → oneshot → espeak and never reaches `Transcendent`. And the
  tell that opened this is still the best example in the file: `data/tts.yml`
  claimed `OPENBSD/etc/rc.d/master` sets `MASTER_TTS_MODE=classic`, and that
  variable is set nowhere, in the repo or in `/etc/master.env` on vm23 — a
  control that does not exist, described over a path nothing web-side reaches.
  `DECISIONS.md` records why it is not simply wired to the streaming path.

  What has changed is the conclusion. `Speech.synthesize`'s only caller is no
  longer `synthesize_audio`: `Voice::Playback.synthesize` calls it with
  `Policy.default_rate` and `default_pitch`, and `Playback.speak` is how
  `Cli::Session::ResultDisplay` speaks every reply. `Transcendent.synthesize`
  is `bin/tts-speak`'s only line. So the CLI's voice runs through exactly the
  code this entry called unreached, and deleting "the Transcendent path" on the
  strength of this paragraph would take MASTER's spoken reply with it.

  `synthesize_bytes` is the part that survives the correction: tests call it,
  nothing else does. One method, not a subsystem.

  **Do not use this entry as a source for the `lib/voice` budget.** A name-based
  census over `lib/voice` reports seven files with no `Voice::`-qualified
  reference outside the directory — `Enrich`, `ProductionDna`, `StrunkPass` and
  the four `Renderer::` mixins, 601 lines — and every one of them is reached
  from inside it, three of them by `include`. The instrument was the prefix.

What is open is the class, not an instance. When you find one: find the reader
before trusting a config key, and **add the gate, not just the fix** — a
two-direction test is what stops the two halves blurring back together.

The `data/tts.yml` instance is also a warning about *when* to trace: it was found
after three fixes had already been written against that subsystem, not before.
Trace the caller first — the fixes were real, and their reach was not what the
config implied.

#### A general "every data key has a reader" gate does not work here — tried 2026-08-12

It is the obvious next gate and it is not buildable statically. Measured before
building, which is the only reason it was not built:

- **At the key level: 607 of 1173 second-level keys** across `data/**/*.yml` have
  no literal mention in first-party code. 52% — a checker wrong more often than
  right, which is what the veto audit spent the same day deleting.
- **At the section level: 49 of 238 top-level sections.** Better, and legible,
  but still holding whole classes of false positive: `personas.yml`'s persona
  names and `models.yml`'s model rows are registry entries selected by a config
  value at runtime, and `doc_paths_baseline.yml` is keyed by the very document
  paths it exists to list.

The reason is that this tree reaches its data four ways a grep cannot follow:
interpolated filenames (`review/modes.rb` opens `data/prompts/mode_#{mode}.yml`),
directory globs, the `DATA_ALIASES` table, and generic section loaders like
`RuntimeCatalog.load(section)`. All four are legitimate.

Two things worth keeping from the attempt:

- **`loc_budgets` looked dead and is not.** It is read by the `loc_budget` task
  in the Rakefile, which a `lib/`-only search misses. Any search for readers has
  to include `Rakefile` and `bin/`.
- **The top remaining candidate, `limits.yml` `guidance` (29 keys), is the
  closure above working exactly as designed** — the deliberately unread half of
  the split, pinned in both directions by `test/test_limits_split.rb`. An
  unread-key gate would have reported the fix as the defect.

So the honest scope is per-file and by hand, with a two-direction test, the way
`limits.yml` and `security.yml` were each closed. A repo-wide gate would
need a baseline carrying a written reason for all 49, which is a decision about
49 sections rather than a mechanical step.

### The shape of the tree

`sprawl_census` counts three things over every tracked file in all four trees,
and `bin/pub4 measure` carries them: a directory holding one file, a name that
repeats its parent, and a name that says nothing on its own. `FILE_SPRAWL` in
the scan registry measures the first two for MASTER's `.rb` files and skips
`law/`, `core/`, `test/` and `spec/`, so it reports zero here and means only
that.

Priced rather than fixed, because a ceiling that prices a known cost is what
makes the next arrival a `+1`:

- **20 one-file directories**, against a ceiling of 20, after the 2026-09-05
  hoist of one-file spec, data, test and support dirs. What remains is mandated:
  OS install paths, Zeitwerk, Rails `test/system`, ports fixtures, OmniAuth,
  PWA, and dilla vocal/render takes. Read the live figure from
  `MASTER/bin/pub4 measure`, not from here — the number in this paragraph is
  the kind that goes stale in a day. The map is `TREE.md`.
- **3 uninformative names**, all Zeitwerk: `lib/io/base.rb` is named after the
  constant it defines, so the finding is that the *concept* is called `Base`,
  which is a design decision and not a rename. The three that were actionable —
  `STUDIO/test/helper.rb`, `STUDIO/test/dilla/helper.rb` and
  `STUDIO/test/tools/helper.rb` — were flattened to `studio_helper.rb`,
  `dilla_helper.rb` and `tools_helper.rb`. Checked 2026-08-29:
  `Dir["STUDIO/**/helper.rb"]` is empty and the three new names are in place.

Calibrate a new kind against a real file before adding it. The first pass
called 130 RAILS paths too deep and 26 names vague, and every one was the rule
misreading a path Zeitwerk requires — the same way 596 of 981 design findings
died. Stutter took three attempts before it separated `dilla/dilla.rb`, which
reads correctly at a command line, from `lib/cli/cli.rb`, which held
`Master::CLI::CLI`. What tells them apart is whether the file declares the name
twice.

### Top-level ROOT

**25 files across the repo define a bare top-level `ROOT`**, each pointing at a
different tree — `MASTER/tools/*` at the repo root, `OPENBSD/*.rb` at `OPENBSD/`,
`STUDIO/dilla/dilla.rb` at the dilla directory, `RAILS/tools/*` at `RAILS/`.

In their own processes that is harmless, which is why it has stood. It stops
being harmless the moment two of them are loaded together: Ruby warns
`already initialized constant ROOT`, lets the **second assignment win**, and the
loser then reads the wrong tree with no further complaint.

That happened in `rake test`, where `test_security_sweep.rb` requires
`tools/security_sweep.rb` and `test_dilla.rb` loads `STUDIO/dilla/dilla.rb`.
Depending on load order, the security sweep would have run `git ls-files` against
`STUDIO/dilla` and reported the repo clean having scanned a music directory. The
warning in `bin/check`'s output was the only thing standing between that and a
silent pass, and it read as cosmetic noise.

Closed for that pair on 2026-08-12 by renaming MASTER's to `SWEEP_ROOT`, and the
class is closed with it: **`rake lint:constant_collisions`** asserts that no two
files reachable by a `require_relative` define the same top-level constant. 362
requirable files of 2,094 first-party Ruby, currently 0 collisions — the gate
lands green because the one live instance was fixed, and it flags the pair again
if either file goes back to a bare `ROOT`.

The remaining 24 bare `ROOT` definitions stay, deliberately. A standalone script
run as `ruby thing.rb` never shares an interpreter with another, so the constant
is only a hazard once something requires the file. Only `require_relative` is
followed: a plain `require` resolves against `$LOAD_PATH`, which depends on how
the process was started, and guessing at it would produce a gate that is wrong
in both directions.

**The cross-tree test is closed — 2026-09-05.** `MASTER/test/test_radio_bergen_study.rb`
required `../../STUDIO/dilla/dilla` and through it read
`RAILS/brgen/config/radio_bergen/tracks.yml` — one test file reaching into two
other trees. It had already broken the way this entry predicted: it asserted
`assert_equal 9, local_count` while the manifest had grown to 30 rows when radio
bergen started serving its own catalogue, so `rake test` in MASTER was red for a
change made in RAILS, naming the growth as the regression. That half was fixed
by asserting the invariant instead of the instance — the study covers every row
the manifest holds, counted from the manifest.

The coupling is now fixed too. The file is
`STUDIO/test/test_dilla_radio_bergen_study.rb`, beside the module it exercises,
loading the engine through `dilla_helper` like its neighbours and named so the
`test/test_dilla_*.rb` glob reaches it. `RadioBergenStudy` reading RAILS's
manifest is the engine's own coupling and is unchanged; what has gone is a
MASTER test that broke when any of three trees moved.

Found on the way: **`Pub4::Runs` never looked at STUDIO at all** — 23 test files
outside every question the "a test nothing runs" gate asks, which is why moving
a file out of MASTER would have quietly removed it from that gate. STUDIO is in
the census now, and the extractor reads a runner's exact path literals as well as
its globs, because `STUDIO/Rakefile` names `test_studio_gate.rb` outright and a
glob-only reader called it an orphan. 743 test files across four trees, 0
orphans.

### Test coverage

**163 of 445 `lib/` files have no test or spec naming their innermost class or
module** (measured 2026-08-11; the earlier record of 188 of ~400 used the same
method against a smaller tree).

The argument for closing the gap is what happened when eight named constants got
their first tests on 2026-08-01: four live defects fell out, all in code that
looked fine.

- `io/ssrf_guard.rb` never required `uri`. `safe_uri?` does `uri.is_a?(URI::HTTP)`
  inside a blanket rescue, so in any process that had not already loaded `uri` the
  NameError was swallowed and the guard answered false for every URL — web_fetch
  silently disabled, one `Swallow.log` line, no other symptom.
- `Permissions.blocked?` matched its blocklist with bare `include?`, so "sudo"
  inside "pseudo" and "halt" inside "shalt" made `grep -rn pseudocode lib` refuse
  as dangerous.
- `PatchApplier` kept only stderr, but `patch(1)` reports a failed hunk on stdout,
  so the most common real failure produced an empty reason.
- `GitOperations#dirty_count` counts status *lines*, not files — git collapses a
  wholly-untracked directory to one `?? lib/` line.

`rake test:subsystems` runs in the `operator` and `contributor` profiles, so
`test/{cli,io,fix,lib}/` is no longer skipped by the gate `START_HERE.md` sends
contributors to.

### Web Face Verification

**operator-priority.** Voice Mode and boot contracts are covered by
`web/test/face_boot.test.mjs` (static assertions on `face.runtime.js`), and the
WebGL primer guard has the same pattern. **Manual iOS Safari tap-testing remains
operator work when boot assets change materially** — nothing in CI drives a real
touch event.

### Host TTS Binaries

**operator-priority.** End-to-end TTS audio depends on host binaries
(`edge-tts`, `espeak`, `ffmpeg`). Web wiring can be correct while synthesis is
unavailable, and `pkg_add` succeeding at install time is not evidence a binary is
on the box now. Check `GET /health` `deploy.tts_socket` and
`test -S .master/tts.sock` on vm23.

`lib/voice/engines.rb`'s two ffmpeg fallbacks used to return quietly, so a host
without ffmpeg served un-concatenated audio with nothing logged. They now report
through `Swallow.log(..., severity: :load_bearing)` naming the consequence. **Any
future post-synthesis DSP must call `report_missing_ffmpeg` on its own fallback
path** rather than returning silently.

Measured on vm23 2026-08-17: ffmpeg 6.1.3 and ffprobe are both in
`/usr/local/bin`, and `Engines.ffmpeg?` evaluates true inside MASTER's own bundle
there — so the PATH the daemon actually runs with resolves it, which the cron
PATH lesson elsewhere in this file says not to assume.

#### One-shot Edge worker on vm23 — code path matched, box not re-probed

**operator-priority.** Production TTS is the daemon; the fallback is
`synthesize_edge_oneshot`. The one-shot path used to call `synth()` in-process
while the daemon used `synth_forked`, and it did not set `SSL_CERT_FILE` the
way `worker_env` does for a subprocess. Both of those are now the daemon's
path. That does not prove the box writes a non-empty MP3: `/health` is still a
capability check. Re-probe on vm23 with a real oneshot before calling the
fallback healthy.

### Live gotchas

Three facts with no home of their own, kept because each was expensive to find.

- **A council pass looks exactly like a hang.** On a dev Mac the provider is the
  `claude` CLI (`send_claude_cli`), not an HTTP API, so a run with no
  `*_API_KEY` in the environment still reaches a model and `Master.any_api_key_present?`
  is not the question. `CLAUDE_CLI_TIMEOUT_S` is 300 and the council runs 26
  personas four at a time, capped by `TOTAL_BUDGET_S` at 600. Add four scans of
  ~90s each and `/through master` needs roughly sixteen minutes. It spends most
  of that at 0% CPU with an empty pipe, because the CLI buffers when stdout is
  not a TTY and every persona thread is blocked on `IO#read`. Two sessions have
  now killed it believing it was stuck. `ps` shows the truth: count the
  `claude --print` subprocesses before concluding anything.

- **Constructing a `CLI` object flips a process-wide flag.** `CLI#initialize`
  calls `set_visitor_mode_if_unauthenticated`, which sets
  `Fiber[:master_visitor] = true` whenever the config carries no `web_token`, and
  fiber storage outlives the test that set it. That was the "known flake" in
  `TurnRouterTest` (see `test/test_cli.rb`): a later test reaching `TurnRouter.call`
  took the visitor branch and errored inside a test about the Fold. Both CLI test
  files clear it in `teardown` now. Not a product defect — a real CLI reads a
  64-char `web_token` — but the web path sets and clears this per request while the
  CLI sets it for the life of the process.
- **An orphan sweep must include the repo-root `bin/` and must not filter by
  extension.** A 2026-08-03 sweep deleted `lib/pub4/status_report.rb` as an orphan
  and broke `MASTER/bin/pub4` for six days: the grep matched only `*.rb`/`*.yml`/`*.md`
  and `MASTER/bin/pub4` has no extension, and it ran from `MASTER/`, where `bin/` does not
  mean the repo-root `bin/` that holds the caller. Pinned by
  `test/test_entrypoint_requires.rb`, which checks requires rather than constants —
  a constant sweep can be fooled by an extension filter; a missing file cannot.

### Scanner Conventions

Seven shapes of one defect: **each converts the absence of a property into
evidence of it.** A gate, a test or a reader accepts something that merely looks
like the thing it was checking for, and the result is a defect that arrives
carrying its own certificate of compliance. Six were found in one week of
2026-08, in different subsystems, by different sessions; the seventh in RAILS on
2026-09-05, and it had been costing a thousand assertions a run.

#### 1. A comment outlives the rule it explains

Any check that greps source for a string must strip comments first. A rule and the
paragraph explaining the rule contain the same words, so a raw `include?` /
`refute_includes` matches the prose about a thing as readily as the thing. This
fired four times on 2026-08-10 alone: a test refused a partial for containing
`popover` where the match was the comment recording the popover's removal; a
weight test counted three Stimulus controllers in a partial rendering two, having
read the comment quoting the markup it replaced; and the `nbsp_entity` and
pagy-helper rules each flagged the comment explaining themselves. A fifth, one
layer out: a CSS pass "confirmed" a rule had been deleted from three bundles when
sass had preserved the `/* */` comment naming it.

The fix is one line at the read site, and it differs per language:

```ruby
source.gsub(/<%#.*?%>/m, "")          # ERB
source.gsub(%r{/\*.*?\*/}m, "")       # CSS/SCSS block comments
source.lines.reject { |l| l.strip.start_with?("#") }.join   # Ruby, YAML
```

The failure mode is asymmetric, which is why it matters: a `refute_includes` that
reads comments produces a *false alarm* the next author "fixes" by deleting the
explanation. That is how a codebase loses the reasons for its own decisions.

#### 2. An exemption outlives its subject

When a gate carries an allow-list — exempt paths, baseline numbers, known
offenders — the entries must be **checked against reality, not merely consulted.**
An exemption whose subject no longer exists is a hole in the gate that nobody can
see, precisely because the thing it excuses is invisible.

When `RAILS/FINAL_TODO.md` was deleted it surfaced two immediately, because both
tests named the file the moment it went: `doc_numbers` was still granting it dimension
exemptions and `doc_paths` was still excusing a generated schema path on its
behalf. Neither had had a subject for as long as it took to notice.

`rake lint:autoload` is the shape to copy: it does not merely read its ignores, it
asserts each one is still necessary and fails naming any that is not. Cheap check
when adding one: every path in an allow-list should resolve, and every numeric
exemption should name the file it was granted for. Note that "resolve" needs the
right base directory — a probe that assumed repo root reported 89 phantom stale
entries in `data/autoload.yml`, whose paths are relative to `MASTER/lib/`. Verify
the instrument before believing the finding.

#### 3. A build artifact outlives the source it was built from

The one that hides best, because while the source stays correct every reader who
checks the source concludes the tree is fine. Found in amber: `public/assets` held
a precompile from before a rename, and in development Rack::Static serves
`public/` *ahead of* propshaft, so the stale bundle won its own route — the
browser got July's JavaScript while the repo held August's. It was noticed only
because that copy happened to be *corrupt* and took every Stimulus controller down
with it.

That detail is the warning, not the incident. A corrupt stale artifact announces
itself; a merely outdated one serves last month's behaviour in silence,
indefinitely.

- When behaviour contradicts source, check what is being served before re-reading
  the source. `curl` the asset path and diff it against the file it claims to be.
- `public/assets` is gitignored, so this never ships — it is a local-only trap,
  which also means CI cannot catch it for you.
- The same shape reaches production by a different road: `web/face.runtime.js` is
  generated from `face.part*.txt`, and a commit that edits a part without
  regenerating leaves a stale artifact tracked in git. That is why
  `rake assets:precompile` belongs in the same commit as any face-source edit.

#### 4. A staleness alarm silenced by regenerating the artifact

Corollary to 3, and it cost four broken JavaScript call sites in `e7e48eed1`.
`AstFixer`'s `template_literals` transform converted a `+`-chain ending in a
*call* by taking only the callee, producing a template literal invoked as a
function: a `TypeError` on every execution, and **valid syntax**, so
`node --check` and the commit's own "All parse" claim were both satisfied.

Two of the four were caught only indirectly, by
`test_public_asset_manifest_matches_source_files`, whose message reads "generated
asset drifted" — a *staleness* message. Running `assets:precompile` to clear it
copies the broken source over the good digested asset and turns the alarm off
without fixing anything, which is exactly what happened first.

Closed three ways: the call sites restored; the transform now declines any chain
followed by `(`; and `test_public_js_has_no_template_literal_called_as_a_function`
fails on the *shape*, in the tree, rather than through a drift message. When a
test reports drift, ask what the drift is evidence of before regenerating.

#### 5. A test that punishes the improvement it exists to detect

A gate that watches for a finding must be written so that fixing the finding is
not a failure. `RAILS/test/gate_live_and_css_budget_test.rb` asserted that one
specific colour pair measured *below* the AA contrast threshold, with the message
"the finding this pairing exists to surface has gone". Anyone who improved that
accent would have been met with a red test naming their fix as the regression.
Nobody was, because it was already failing for an unrelated reason, so the trap
sat armed and invisible behind another red.

1. **Assert the invariant, not the instance.** `refute_empty findings` survives
   every legitimate fix; `assert specific_pair.ratio < threshold` survives none.
2. **Read a name from the constant that owns it.** A test that spells out a value
   the code already names cannot tell a rename from a regression.

The tell is a test whose failure message describes something good happening.
Invert it and ask what a successful fix looks like in CI; if the answer is "red",
the assertion points the wrong way.

#### 6. A writer that reports an edit it did not make

`rake lint:spine RATCHET=1` printed "raise log cleared" and cleared nothing. Its
substitution matched continuation lines only (`    .*`), deliberately, after an
earlier version matched dashed lines only and left the file unparseable — the
fix for a loud failure introduced a silent one, and the comment above it
explained the reasoning for a pattern that had stopped matching anything. The
allowance was therefore a countdown to permanent failure rather than the budget
`spine.yml` describes, and nothing could show it: a cleared log and a log that
was never touched look identical from outside.

The fix is not the regex. It is that the task now **reads back what it wrote**
and aborts if `raised` is not empty. A writer that can claim an edit it did not
make belongs to the same family as the four above — the absence of a property
reported as evidence of it — and the remedy is the same: assert the outcome, not
the attempt.

#### 7. A root constant that resolves one level too high

`RAILS/brgen/test/source_reader.rb` computed the tree as
`File.expand_path("../../..", __dir__)`. The file is at `RAILS/brgen/test/`, so
that is the repo root and not `RAILS/`. Two guards in the same expression were
supposed to catch it — the chain only accepts a candidate holding `shared/app`,
then one holding `shared` — and both missed, so it fell through to
`candidates.last`, which is the wrong path it had just rejected. A fallback that
ends in "use the last one anyway" is not a fallback.

The cost was 39 errors and one failure in brgen's suite, and the number that
matters is the other one: **974 runs carrying 3,486 assertions became 974 runs
carrying 4,529**. A thousand assertions had never run on any checkout that is
not `/home/dev/pub4`, which is the first candidate and why the box never saw it.
The suite is green now, and the two verticals it re-armed —
`InfiniteScrollWiringTest` and `DeployBacklogTest` — are the ones that read
source rather than exercise it.

Same family as `Pub4::OperatorDocs::ROOT`, recorded above at four levels instead
of three, and the remedy is the one that entry named: **assert the resolution,
not the reads.** `test_root_resolves_to_the_rails_tree` checks that ROOT holds
`shared/app` and `brgen/app` and is called `RAILS`, because a wrong root fails as
a missing file and reads as a missing file.

#### What follows from all seven

- **A new gate's first run must be against a known-bad input, not a clean tree.**
  A green first run is the least informative outcome available: it is equally
  consistent with "nothing is wrong" and "nothing is measured". Every check added
  on 2026-08-10 was mutated six ways and watched to fail before being believed —
  and two of them did not fail, and were wrong.
- **Registration is not execution.** `rendered_invariants` shipped with an
  instance `run` and no class-level `.run`, which is how `runner.rb` invokes a
  gate: it was a row in `gates.yml`, listed by `--list`, counted as coverage, and
  never once executed. It is the gate written to catch declarations with no reader.
- **A gate must read the source of truth, not restate it.** `domain_alignment` —
  whose whole purpose is proving the fleet's domains and ports agree — held its own
  literal table of the three domain/port pairs. Edit `apps.yml` and it keeps
  asserting the old numbers, and passes.
- **When writing a check that recognises a pattern, name the cases you already
  know and pin them through it first.** An ownership-guard sweep found its own
  regex matching the *fixed* branch, because after `user` comes a dot rather than
  `_id`.

### Not Debt

- The fold spine living inside `lib/`. Merged 2026-08-12 on operator
  instruction; `DECISIONS.md` records the reversal and what was kept (the
  no-backedges test, and the `core_files` invariant). Not a regression to undo.
- One rule registry. The four `data/rules/*.yml` shards were folded into
  `data/rules.yml` on the same instruction. Their single consumer was
  `load_rules`, which merged them back before any scanner saw them.
- Local `knowledge/` corpus and generated `output/` artifacts.
- Deferred WebGL boot.
- **The gap between the registry classes and the declared rules.** Checked
  2026-08-12 on the theory that the difference was inert law — declared rules
  nothing implements, which would be this file's dominant defect class at the
  constitutional layer. It is not: every declared rule has a detection path, in
  the corpus, in `law/`, or by `folded_into` naming the rule that reports for it.
  `RuleRegistryAudit` measures the split, `SelfTest` reads it, and
  `test_rule_registry_audit.rb` pins it. Re-measured 2026-09-04 at 228 declared
  and 145 built, with the split now 141 semantic, 15 structural, 78 carrying no
  detector field and resolving through `law/` or a fold. **The "7 lexical-only
  through the YAML bridge" in the original wording is 0** — see the audit section
  above; that half is a live question, the no-inert-law conclusion is not.
- Media-generation severance: re-severed 2026-07-14 (`76b11fec4`), confirmed
  permanent 2026-07-15. `docs/SEVERANCE.md` is the source of truth. If the LoRA
  training loop needs generation capability again, express it as
  `lib/core/world.rb` handlers per the original absorption plan — do not restore
  the deleted `io/lora_pipeline.rb` / `video_chain.rb`.

### From the 2026-09-04 MASTER audit

Opened by reading `data/rules.yml` end to end and asking, for each declaration,
which line of Ruby consults it. Everything below was measured against this tree
rather than inferred, and the command that measured it is named so the next
reader can re-run it instead of re-deriving it. The cleanup that came out of the
same sitting is `72a8cfae8`; what is here is what that commit did **not** close.

#### `self_findings.registry`: 52 findings the tree owns

The row was opened 2026-09-06, when `self_findings` turned out to count the 122
laws and call itself "what our own rules find in our own trees" — the 145 rules
the registry builds were counted by nothing. It measures through
`InfraHelpers.build_scanner` and `Scanner#findings` at error severity, over the
same corpus as the law row, dropping ids that reach the scanner through
`LawBridgeRule` so one fix moves one ratchet. `data/self_findings.yml` carries
every finding with its file and line.

It opened at 108 and three passes took it to 52, and almost all of what fell
was the instrument rather than the tree — `SQL_INJECTION` flagging the
`quote_table_name` that is its own fix, `COMPLETION_THEATER` reading `/etc` as
an abbreviation thirty times, `DEBUG_OUTPUT` reading dilla's `p < 0.5` phase
local as a debug print. Each rule carries its own evidence now; the lesson is
the one this file opens with.

**What is left is real, and it is two rules.** `SILENT_RESCUE` 26, every one in
STUDIO and nineteen in dilla, where a `rescue StandardError` around an optional
gem call is load-bearing for a render — narrowing one on my own judgement is
the change this repo's own rules say not to make, so that half wants dilla's
owner. `NO_GOD_CLASS` 26: more than ten public methods or more than three
hundred code lines, led by `Conversation` 28, `User` 27, `Takeaway::Order` 26
and `BergenDemoSeeder` at 834 lines. Nothing there is instrument; it is
twenty-six decompositions in three trees, most of them live Rails models.

#### The constitution's seven hooks — closed 2026-09-06

`soul.yml` had declared seven hooks since it was written and none had ever
fired. `Trace::Hooks` turns five bus events the tree already publishes into the
`on_*` names the constitution uses and runs what `soul.yml` declared for each;
nothing called `attach`, while its three `Trace::Ledger` siblings are each
attached in the same boot phase.

Deleting it was the alternative and it was the wrong call — the shape is worth
keeping, because a constant-name census and a file count both said delete.
All three halves were built: the declarations, the class, and the events.
`scan:complete` comes from `file_processor` at two sites,
`rule_loop:fix_applied` from `rule_loop`, `llm:cost` from `ruby_llm_sender`,
`phase:advanced` from `phase_gates`, `fix_loop:clean` from `pass_runner`. What
was missing was one line. **A subsystem three-quarters wired reads exactly like
a dead one from the outside, and the difference is whether the events it wants
are already on the bus.** Ask that before deleting.

`.constitutional_violations.jsonl` — the file `soul.yml` has always said a
violation is appended to — is written now, proved by a real scan rather than
asserted. It is gitignored.

`test_trace_hooks.rb` boots `TraceBoot` for real rather than grepping
`boot_phases.rb` for the word `attach`, which would pass against a method body
of `raise`. Its last test walks `soul.yml` and fails if any declared hook
produces no effect, so the state this record described cannot return quietly.

#### The tier2 ordering guarantee — closed 2026-09-05

`TIER2_QUALITY_RULE_IDS` is now `%w[NO_GOD_CLASS FEATURE_ENVY FEW_ARGUMENTS]`,
the scanner ids that actually exist. The test asserts those ids are on the live
scanner, not on a Struct it constructed.

#### The YAML lexical bridge now compiles nothing — closed 2026-09-05

`YamlDeclarativeRule` remains the escape hatch for a `detect_lexical` with no
Ruby class, and `rake lint:rule_reach` still counts on the category. The
corpus carries 0 such rows. `RuleRegistryAudit` now prints `lexical hatch
empty` when both wired and unwired are 0, so the idle hatch is a named
finding rather than two zeros a reader has to add up. The hatch stays; what
was missing was saying it is idle.

#### A `languages:` scope on a semantic rule was inert — closed 2026-09-05

`SemanticRule` builds a prompt frame per language now and `parse_findings` reads
the scope the file was asked about, so a reply naming a rule outside it is
discarded rather than accepted. Empty still means every language, as it does for
`Law::Rule#applies?`.

One thing came out of wiring it that is worth keeping. Thirteen rows declared a
language `FILE_LANGUAGE_MAP` never produces — `rails` on four, `prose` on eight,
`erb` on one — which aims a rule at no file at all. `Law::Rule#prove!` has
refused that on the law population since `NEVER_BATCH_DELETE` declared `shell`
and could read no script; `test_semantic_rule_scope` now asks the same of this
one. `rails` became `ruby`, which is what those four detectors already declare;
`prose` and `erb` went, each beside a real sibling that covers the same files.

#### Rule-corpus debt the ratchets already price, listed so it is one place

Each is the current output of a gate that passes because its ceiling accommodates
the number. None is new; what is new is that they are together.

**Half of it was the instrument, closed 2026-09-05.** The two gates that report
this debt were each asking a question their own data could not answer, and the
corrections are worth more than the counts were.

`autofix_reach` decided whether a rule can be *found* by counting the three
`detect_*` columns in `rules.yml`, so it named twelve autofix claims
undetectable and was wrong about all twelve: ten have a live detector in `law/`
or the RuleDSL registry, and `WHITESPACE_PUNCTUATION` and `MESSAGE_CHAIN` carry
`folded_into:`. It asks `RuleReach.mechanical` now, which knows all three
populations and loads the laws rather than grepping for `Law.define(:ID)`.
Corrected, it found six the old count could not see — `PRECOMPUTE_MATH`,
`ANALOG_WARMTH`, `PURE_FUNCTIONS`, `SPECULATIVE_GENERALITY`, `SYSTEM_STATUS`,
`CACHE_LLM` — each a semantic-only detector at info severity, which
`SemanticRule`'s info filter drops, so nothing ever reported them and no fix
could ever be reached. All six are `autofix: false` now and `bare_true` is 25.

`rule_hygiene` walked every hash in the file carrying an `"id"`, so the eight
check names inside `AUTOMATED_CSS_ANALYSIS`'s `config:` counted as eight rules
with no metadata and one of them, `eight_px_rhythm`, collided by case with the
real `EIGHT_PX_RHYTHM`. It reads the two declared populations now. What was left
after that was real and is closed: the `bare_rescue` smell went (see **Scanner
noise**), the five surviving smells declare a severity, and DRY's
`duplicate_code` alias went rather than the live rule it named. All three
counters read 0, and 0 is the recorded floor.

Still open, and each is a decision rather than a sweep:

- **`autofix: true` naming no transform — closed 2026-09-06, 25 to 0.** Three
  kinds, and the kinds are the reason the tool asked for. Four name the
  transform that already fixes them (`HTML_LANG` `add_html_lang`,
  `LAZY_IMAGES` `add_lazy_loading`, `TRAILING_COMMAS` `add_trailing_commas`,
  `DEAD_CODE` `remove_immediate_dead_code`), so `named` is 4 where the corpus
  named none at all. Sixteen are design judgements where no single edit is
  correct and `false` is what they always meant. Five are mechanical in
  principle and unwritten in fact — `EN_DASH_RANGE`, `NO_UPDATE_ATTRIBUTE`,
  `QUOTE_VARIABLES`, `DOUBLE_BRACKET`, `WHITESPACE_PUNCTUATION` — and those
  five are the forward work: **the transforms are worth writing, and naming one
  before writing it is how the dangling counter filled up last time.**

  One behavioural consequence, named rather than discovered. `MechanicalAutofix`
  selects a file when any finding carries a truthy `autofix`, so a file whose
  only findings are judgement rules no longer gets `AstFixer`'s universal
  cosmetic passes as a side effect — a scan should not rewrite a file because
  of a finding it cannot fix.
- **24 rules fire on nothing in this corpus** (ceiling 24, so the gate is at its
  limit). The header in `rule_ratchets.audit` is right that silence is usually a
  property of the sample — but `FROZEN_STRING_LITERAL`, `MEANINGFUL_NAMES` and
  `WHY_NOT_WHAT` are in the list *and* in the 78 rules that carry no detector
  field at all, which is a different reason for silence and worth separating.
- **20 cross-population duplicates** — one id defined in two places in two
  wordings, with no way for a reader to tell which governs. Resolving one means
  keeping the wording where the detector is, which is a judgement per pair.
  Ratcheted at 20 now, where it had a ceiling of 21 and no row in
  `bin/pub4 measure`.
- **133 registry rules sit outside `rule_deps`.** No longer ungated: it is a
  ratchet row, `rule_deps.ungraphed`, floor 133 and down only. A rule outside
  the graph is one `RuleOrder` cannot sequence.

#### `zsh` reference tables — closed 2026-09-05

`zsh_style_lines` now reaches `forbidden_commands`, `native_patterns`,
`ssh_reading` and `token_economics` as well as `banned_commands`.
`banned_commands` is still the only list `Io::Shell` warns on.

#### Nine of sixteen line budgets are over, and `law/` is nearly double

`rake loc_budget`, re-measured 2026-09-05 after the antigravity collapse: `law`
1609/852, `lib/pub4` 692/470, `lib/ground` 6112/5899, `lib/core` 769/682,
`lib/boot` 268/227, `lib/trace` 2055/1999, `lib/voice` 3408/3181, `lib/review`
10387/9765, `lib/fix` 2670/2643. `limits.yml` says a breach is paid by
extraction or deletion and never by a bigger number.

One of the nine has been paid down and it is the largest single fold this file
records. `lib/ground` fell 730 — 6842 to 6112, from 943 over to 213 — when the
seven unreached antigravity subsystems and the Coordinator that eagerly built
them went, which is the whole of what that directory's overage had been.
`lib/review` moved the other way: 36 back when ten byte-identical copies of a
five-line `visit` moved onto `Rule#walk`, then 59 out again on the twenty-nine
rule fixtures below. That is the trade the fixture ratchet asks for, and it is
named here rather than buried.

`law/` at 89% over is the one to open next: the twin census closed in 2026-08
retired 42 duplicated rules and the file set has grown back past where the
budget was set.

#### `rake selfcheck` locations and three silent rescues — closed 2026-09-05

`SelfCheck::Report` now carries `findings` with path and line, and the task
prints that summary once (the `selfcheck: selfcheck:` prefix is gone).
`Scanner#findings(paths)` is the flat API; `tools/example_scan.rb` uses it.

Three of the four `SILENT_RESCUE` sites now report through
`Swallow.log(..., severity: :load_bearing)`: `PathPurposeRule#owned`,
`antigravity/skills.rb#load_usage`, `Session#quarantine_corrupt_session!`. The
fourth, `voice/renderer/system_info.rb`, no longer reports at all — re-scanned
2026-09-05, the rule finds nothing there. Do not re-open it from this line.

**`rake selfcheck` is 1 finding, 2026-09-05.** Two of the three went:

- `COMPLETION_THEATER` on `ast_fixer.rb:75` was the rule reading its own subject.
  `PLACEHOLDER_ETC` already excluded a path segment; it excludes a regex
  alternation now, so `%r{/OPENBSD/(?:etc|usr|var)/}` — the verbatim-mirror
  guard, at error severity, so the fast gate was red on the rule that protects
  `/etc` — reads as the pattern it is. Measured over all four trees: two lines
  retire, 57 findings stay, and `(etc.)` in prose still fires, which is why `(`
  and `)` stay out of the exclusion.
- `NO_GOD_CLASS` on `LlmDispatcher` was the count measuring an idiom, the way it
  read `Core::Constitution` at 16. Three of its eleven public methods —
  `redact_secrets`, `forced_model`, `vision_capable?` — have no caller anywhere
  in the repo and sat above `private`. Moved below it: 11 public → 8. The eight
  model-shape predicates that do have callers stay public.

`NO_GOD_CLASS` on `EventStore` closed with `lib/autonomy` on 2026-09-05, and
what it took to close is the part worth keeping. The record read it as a
decomposition question — fourteen public methods over four tables, each one
somebody's door — and privatising a repository's API to satisfy a counter is
what "driving the count to zero by re-exempting" means, so it sat. The question
was never how to split it. Nobody was at any of those doors, the subsystem was
reached by nothing but its own tests, and the counter was right in a way its own
message could not say. **`rake selfcheck` is clean and `rake selftest` is 0**,
both for the first time since 2026-08-19.

The fourth `SILENT_RESCUE` came back and is closed. `ProgressReporter`'s
`append_scan_hits_jsonl` swallowed every failure writing `.master/scan_hits.jsonl`
— the one record a sixteen-hour walk leaves behind, where an empty log and a
clean run look alike. It reports at `:load_bearing` now. `rake selfcheck` is 1.

`rake selfcheck` also printed its whole located summary twice on a failing run:
once to stdout and once as the abort message. `Report#line` is the headline on
its own and the task fails with that.

#### `edge_tts_available?` and the Mac `say` fallback — closed 2026-09-05

The cheap probe stays two preconditions (`worker_executable?` and
EventMachine SSL) because it gates a per-utterance path. `/health` asks
`edge_tts_ready?`, which spawns `tts-worker --selftest` and reports
`tts_blocker` when it is not. Classic `Speech.synthesize` now falls through
Edge, then espeak, then `Engines.synth_say`, so a Mac without a live Edge
socket still speaks.

#### Three test files have been erroring, and `rake test` cannot see them

Found 2026-09-05 by running every test file individually, which is not what
`rake test` does. **277 of 283 files pass; six fail, and all six fail identically
on an unmodified `origin/main`.** Three of the six share one cause and it is
worth a fix:

    test/test_ast_omission_rule.rb        3 errors
    test/test_co_change_coupling_rule.rb  3 errors
    test/test_veto_pattern_rule.rb        1 error

Each is `NameError: uninitialized constant …Rules::AstOmissionRule`, and the
class is not missing — `AstOmissionRule` is in `lib/review/scan/rules/meta_rules.rb:9`,
`CoChangeCouplingRule` in `graph_rules.rb:128`, `VetoPatternRule` in
`yaml_bridge_rules.rb:8`. Zeitwerk maps one file to one constant, so a class in
a multi-class rule file is only defined once something loads that file, and the
tests name the constant cold. Proved both directions:

```ruby
Master::Review::Scan::Rules::AstOmissionRule   # NameError
Master::Review::Scan::RuleDSL                  # what InfraHelpers touches
Master::Review::Scan::Rules::AstOmissionRule   # resolves
```

**Fixed 2026-09-05.** The load is one line per file, `require
"review/scan/rule_dsl"`, which is what `test_smell_detectors.rb` already does.
That is where the interesting part started rather than ended: two of the three
then passed while asserting only that the rule responds to `check` and returns
an Array, which every `Rule` subclass does by inheritance. Erroring files that
become green files measuring nothing are worse than erroring files, because they
now read as coverage.

So both were rewritten against what the rules actually decide, with the
collaborator injected so neither needs repository history:

- **`co_change_coupling`** — its judgement is three filters, and each is asserted
  in both directions: a cross-module peer at the threshold is reported with its
  weight, one below it is not, a same-module peer is never reported however
  heavy (that is cohesion, the thing it must not flag), and only the heaviest
  three are named. Any ecology answering `co_change_graph` will do.
- **`ast_omission`** — a fake guard supplies the omissions, so the mapping, the
  two guard clauses and the rescue are all pinned. One assertion is that a
  non-Ruby path does not cost a git call at all, because a guard clause that
  returns empty and one that never runs look identical from outside.

Both were mutation-checked before being believed, per "a green first run is the
least informative outcome available". Inverting the module filter, lowering the
weight threshold, taking four peers instead of three, reversing the sort,
dropping the `.rb` guard, passing the absolute path instead of the relative one,
reporting only the first omission, dropping the last-seen date, and making the
rescue re-raise — nine mutations, nine caught. The veto test was already real
and catches a neutered `secrets` pattern.

#### `rule_coverage` examines one of sixteen rule files and is wrong about it

Found while checking whether that gate had been reading the three broken files
as covered. It had not, because it never looked at them.

`RuleCoverageRule` exists so that "every Rule subclass has a matching test file;
gaps mean untested enforcement". Two lines decide what it sees
(`lib/review/scan/rules/meta_rules.rb:66,69`), and each is wrong for this tree:

- It returns early unless the path ends `_rule.rb`. **One file in
  `lib/review/scan/rules/` does**, `law_bridge_rule.rb`. The other fifteen are
  `*_rules.rb`, plural — `meta_rules.rb`, `graph_rules.rb`, `ruby_rules.rb` and
  the rest — and are never examined. They hold nearly every rule class there is.
- For the one file it does examine, it globs `test/**/<base>_test.rb`. MASTER's
  convention is `test_<base>.rb`: **283 files match `test_*.rb` and 1 matches
  `*_test.rb`.** So it looks for a name this tree does not use.

Run over all sixteen, it reports exactly one finding —
`rule_coverage: no test file found for law_bridge_rule` — and
`test/test_law_bridge_rule.rb` is right there. Fifteen skipped, one false
positive, nothing correct.

**Fixed 2026-09-05.** It examines every `.rb` under `lib/review/scan/rules/`,
finds each `class XxxRule < Rule` in it, and asks whether any file in `test/`
mentions that class or its rule id.

Coverage is a mention rather than a file named after the class, and that is the
load-bearing choice. The tests that exercise these rules mostly do it in bulk —
`test_smell_detectors.rb` and `test_scan_rule_false_positives.rb` reach rules by
id through the scanner — so demanding a file per class would report those as
uncovered and rebuild the same false-positive machine pointing the other way.
The matcher is deliberately loose for the same reason: class name, id, and the
id in either case all count, so what it still reports is a real gap.

Cross-checked before it was believed. A hand census written separately from the
rule agreed on the same 14 classes, and six mutations are caught by
`test/test_rule_coverage_rule.rb` — including the exact regression to
`_rule.rb`, which was the old behaviour.

#### Every rule class now has a test — `rule_coverage` reads 0

Closed 2026-09-05, from fourteen. `RuleCoverageRule` came with the gate fix, the
four SOLID proxies with `test_solid_rules.rb`, and the last nine in one pass:

    test_structural_shape_rules.rb  FileLayout, CyclomaticComplexity, DataClass, MiddleMan
    test_feature_envy_rule.rb       FeatureEnvy
    test_path_purpose_rule.rb       PathPurpose
    test_interconnect_rule.rb       Interconnect
    test_comment_drift_rule.rb      CommentDrift
    test_yaml_declarative_rule.rb   YamlDeclarative

All in the house shape — a source the rule must flag and a source it must not —
and every threshold pinned from both sides, because a boundary is where a rule
is most likely to be off by one.

**Three tests passed for the wrong reason and were caught by mutating the rule
they cover.** That is the entire value of the practice and it is worth keeping
the examples:

- `FEATURE_ENVY`'s counterweight test used four neighbour calls, which is below
  the rule's floor of five — so the floor exempted it and the counterweight was
  never consulted. Deleting `count > local` from the rule left the test green.
- `CYCLOMATIC_COMPLEXITY`'s boolean-operator test used ten terms, which is nine
  operators and lands exactly on the limit rather than over it. The rule was
  right and the test was wrong.
- `CommentDrift`'s invented-index test asserted that a bad index yields nothing,
  which is true either way: with the bounds check because the pair is nil,
  without it because the resulting `NoMethodError` is swallowed by the rule's own
  rescue and takes every finding in the file with it. Asserted now with a real
  index beside the invented one, which is what separates a guard from a crash.

**One mutation is knowingly uncaught.** Turning
`return [] if note_model_failure(e)` into a bare `return []` changes only a
quota trip and a log severity; both paths return no findings, and the difference
is invisible from outside. Asserting it would mean reaching into the rule's
internals. Recorded rather than faked.

`YamlDeclarativeRule` got the treatment its special case needed rather than a
test that passes because there is nothing to do. The mechanism is proved against
a rules corpus written for the purpose, and the live corpus's emptiness is a
separate, dated assertion: **the day somebody declares a `detect_lexical` again,
that test fails and asks whether the bridge is still wanted**, instead of the
rule staying a path nothing takes.

#### The four SOLID proxies fire on almost nothing, and one half of one could not fire at all

Measured 2026-09-05 over **2,470 Ruby files across all four trees**, which is a
wider corpus than `rule_audit`'s 713:

    OPEN_CLOSED            3     RAILS/brgen/app/helpers/application_helper.rb:400 and two others
    LISKOV                 0
    DEPENDENCY_INVERSION   0
    INTERFACE_SEGREGATION  0

Three of four silent, and until `test/test_solid_rules.rb` nothing could tell
which of the two readings was true — the tree has none of these shapes, or the
detectors cannot see them. A rule that cannot see its subject is indistinguishable
from a rule with nothing to report, which is the whole reason `rule_audit`
carries a `silent` ceiling. **Settled: all four fire on a source built to violate
them**, so the silence is the sample. `LISKOV`'s zero is largely structural — it
only sees a parent declared in the same file, and almost every subclass here
inherits across files. That limit is pinned as a test of its own so the silence
is never read as a clean bill of health.

**`OPEN_CLOSED`'s `is_a?` clause had never fired**, and could not. `TYPE_CHECK`
was `/\b(is_a\?|instance_of\?)\b/`, and a trailing `\b` needs a word character
beside it while `?` is not one — so it required a word character immediately
after the question mark, which no call site has. `is_a?(Header)` and `is_a? Header`
both continue with a non-word character and both failed. So half of what the
description promises, "case/when **or is_a? chains**", was dead from the start.

Fixed by dropping the trailing boundary, and the fix is free: repo-wide findings
go 3 → 3, because no `case` anywhere dispatches on `is_a?` across three or more
branches. The leading `\b` stays and does real work, keeping `foo_is_a?` out.

This is the same trap already recorded twice in this file — `TODO.md` read as a
work marker because `\b` holds between the `O` and the dot. **Any `\b` next to
punctuation is worth re-reading**; it is the third time it has cost something
here.

**`rake test` cannot complete on a dev Mac at all**, which is why three dead
test files went unnoticed. Its loader aborts on `cannot load such file --
rack/test` from `test/test_web_ui.rb` before running anything, because the web
Rails bundle is not installable here — `Could not find rails-8.1.3.1 …` in both
checkouts. So the local signal for "do the tests pass" has been a task that
stops before it starts. Run the files individually until that is fixed:

```zsh
for f in test/**/test_*.rb; do ruby -Ilib -Itest $f; done
```

The other three failures are separate and pre-existing: `test_reach_exec.rb`
(1 error), `test_security_sweep.rb` (1 failure), and `test_ratchets.rb`, which
is the record below.

**All but `test_ratchets.rb` are closed, 2026-09-05.** `test_reach_exec` was
`Io::Exec` calling `Swallow` without requiring it, so the timeout path raised
NameError instead of killing the process group it exists to kill — the same
defect `ground/swallow.rb`'s own header records for `replicate_client.rb`, on
the file next to it. `test_security_sweep` was the sweep reading
`$FLOW_AMBER_PASSWORD` in `RAILS/gates/data/flows.yml` as a leaked credential; a
value that is nothing but an indirection names where the secret lives. Two more
went red in the meantime and both were the test rather than the code —
`test_scanner`'s doubles spelled a `scan_one` signature that had gained three
keyword arguments, and `test_source_assertions` counted two additions its
pattern cannot tell from the thing it hunts. The suite reads 290 of 291 files —
three fewer than the morning because `lib/autonomy`'s three tests went with it.

One red file sits outside that glob and is not counted by it.
`spec/smoke/static_syntax_spec.rb` fails on
`data/radio_bergen_track_dossiers.yml`: it carries bare Ruby symbols
(`drum_preset: :madlib_dusty`), and `Boot::Data.load_yaml` permits only Date and
Time, so MASTER's own loader cannot read a file in MASTER's own data directory —
`Master.validate_data!` warns about it on every boot. Nothing in MASTER reads
it; the same table lives in `STUDIO/dilla/dilla.rb` as Ruby. Not edited here on
purpose: quoting the values is a lossy change to dilla's data made by somebody
who does not own it, and the file may be regenerated from that table.

#### The over-ratchet list is not stable, and that is the finding

`test/test_ratchets.rb` names them. It read three on 2026-09-04, five later the
same day, and six on 2026-09-05. The current list is in **Still open after this
session** above; do not read a count from any of them — read it from
`MASTER/bin/pub4 measure`, which prints every row with its ceiling and names the
slack ones too.

What is stable is the shape: `spine.lib_body_ceiling` and the four `growth.*`
rows move with every session in a shared checkout, and each needs a fold rather
than a raise.

Two ceilings were slack rather than over and are now at their number.
`autofix_reach.dangling` sat at 7 above a real 0 — room the next change grows
into silently — and was lowered when `efc96832f` emptied it. `reader_singularity`
carried `agent_taxonomy.yml: 2` after that file's three readers became one.

Two more rows joined the ratchets on 2026-09-05, both of them numbers that
already existed and gated nothing: `rule_hygiene.cross_population_duplicates`
(20) and `rule_deps.ungraphed` (133).

#### Three rules say one thing in `rules.yml` and another in `law/`

`rule_hygiene.statement_conflicts`, opened 2026-09-06 when
`cross_population_duplicates` turned out to be counting the architecture: an id
lives in the catalogue and in its implementation by construction, and thirteen
of the twenty it reported were a `detect_semantic` prompt beside a lexical
detector, which is one rule at two depths. Eleven of the fourteen conflicts it
found were a catalogue `fix` carrying an older draft of what its law enforces,
and those now carry the law's wording; three severities moved the other way,
to what the catalogue declares.

**The three left are the constitution's wording, which is the owner's.**
`BE_CONCISE`, `PRESERVE_FIRST` and `SIMPLEST_WORKS` each have a soul-derived
`practice` in `law/practice.rb` saying something other than the kernel rule of
the same name: `BE_CONCISE`'s practice is "minimal response", about the voice,
against "omit needless words, omit needless code", about the source;
`SIMPLEST_WORKS`' practice is "refuse to create god classes", which is
`NO_GOD_CLASS`' subject and severity. Resolving one deletes or renames a
statement that reaches the system prompt.

#### The three `growth.*` overages, itemised — 2026-09-06

`spine.yml` says a raise must name each file it makes room for, and the rows
have been red for days with nobody naming anything. Each tree is diffed
against the commit that last set its ceiling, so the overage arrives as a list
instead of a number:

    ruby -e 'EXCLUDE = %r{/(\.git|node_modules|tmp|log|renders|[\w.-]*stems|samples|scratch|project|crate|venv|\.venv|site-packages|vendor|storage|\.cache|builds|coverage|\.master|knowledge|output)/|/public/assets/|\.wav\.quality\.json\z}
      EXT = %w[.rb .rake .erb .scss .css .js .mjs .yml .yaml .md .sh .ksh .exp .html .json]
      now = Dir.glob("STUDIO/**/*").select { |p| File.file?(p) && !p.match?(EXCLUDE) && EXT.include?(File.extname(p)) }
      was = `git ls-tree -r --name-only 9ea74b3d7 STUDIO`.split("\n").select { |p| !p.match?(EXCLUDE) && EXT.include?(File.extname(p)) }
      puts (now.sort - was.sort)'

**`growth.studio` 150/138, twelve over.** Fifteen files arrived and three
left. Ten of the fifteen are `dilla/live/` — `rack.rb`, `recall.rb`,
`dig_crate.rb` and `dig_crate.sh`, `broadcast.sh`, three `*.als.rb` Ableton
writers, plus `lib/sample_worth.rb` and `scripts/generate_tts.rb`. Three are
tests (`test_dilla_crate_dig.rb`, `test_dilla_radio_bergen_study.rb`,
`test_dilla_take_write.rb`), one is `STUDIO/isolation.rb` moved up from
`tools/`, and one is `lora/_toolkit/toolkit.sh` replacing `lib.sh`. A live
performance surface is a coherent thing to have grown; it wants one named
raise from whoever built it, not twelve arguments.

**`growth.rails` 2371/2358, thirteen over.** Thirty-three arrived and twenty
left, and most of both sides are the same files: the test trees were flattened
(`test/helpers/x_test.rb` to `test/x_test.rb`) across amber, brgen, bsdports
and shared. What is genuinely new is thirteen — `authorization_matrix_test` in
two apps, `deal_test`, `city_seed_test`, `mention_test`, four
`RAILS/test/*_lint_test.rb` gate tests, `gates/lib/source/scale_ratchet.rb`,
`gates/support/css_spacing_scans.rb` and `css_weight.rb`, and
`shared/lib/pub4/master_design.rb`. Every one of them is a test or a gate
support file, which is the shape `spine.yml` has raised for before.

**`growth.master` 1050/1047, three over.** Twenty-four arrived against thirty
gone since `a931c5f0f`, so the tree is six files smaller than when the ceiling
was set and still three over the number — the ceiling was lowered below the
measurement on purpose, and the note in `spine.yml` says so.

One instrument fix landed with this: `TREE_EXCLUDE` matched a directory named
exactly `stems` and dilla names them after the render, so `demo_stems/` and
`loop_stems/` put five `session.json` and `motifs.json` sidecars into
`growth.studio` — a stems render raised a source-file ceiling, and 155 was
really 150. The same five files are now ignored where they are written, beside
the sidecar rule `dilla/.gitignore` already states and had not generalised.

#### The TTS probe fix is paid for out of two budgets that were already over

Named rather than buried, because `limits.yml` says a breach is paid by
extraction or deletion and this one is not. `edge_tts_ready?`, the memo and the
worker probe add **35 body lines to `lib/voice`** (3330 → 3365 against 3181) and
the same 35 to `spine.lib_body_ceiling`. No ceiling was raised.

The honest reason it is not paid, corrected 2026-09-05: it is not a Transcendent
deletion waiting for an owner. That reading came from the **Inert law and config**
entry, which has been re-measured and no longer supports it — `Playback` calls
`Speech.synthesize` for every spoken CLI reply and `bin/tts-speak` calls
`Transcendent.synthesize`, so the "1,500 unreached lines" are the code MASTER
speaks with. `synthesize_bytes` is the one method tests reach and nothing else
does.

So `lib/voice` is over its budget with no dead weight in it, which makes this an
extraction rather than a deletion, and a real sitting rather than a decision
somebody can make in a sentence. `speech.rb` at 475 and
`personality_prompt_builder.rb` at 390 are where to open it. Taking 35 lines out
of somewhere unrelated to make the number look right would be the accounting the
budget exists to prevent.

#### The 2026-09-05 pass costs `growth.master` two files and `growth.studio` one

Same accounting, named for the same reason. Five gates gained the tests this
file kept asking for — `rule_hygiene`, `autofix_reach`, `SemanticRule`'s
language scope, the registry audit's shipped-rule filter, and `Consensus`'s
model pool — and the two tool tests were written as one file rather than two,
because they read one subject. `test_semantic_rule_scope.rb` and
`test_consensus.rb` are the net additions to MASTER. STUDIO's is
`test_dilla_radio_bergen_study.rb`, which MASTER lost in the same move, so the
repo total is unchanged and the two trees traded a file.

`lib/` came out level: the `visit` extraction returned 33 lines and the fifteen
rule fixtures, the `three_mirror_pool` accessor and the language scope spent 35,
so `spine.lib_body_ceiling` reads 2 above where the session opened and
`lib/review` 5 below.

#### Instrument notes

- **There is no `edge-tts` binary to look for, and the gem is spelled with
  hyphens.** MASTER never shells out to an `edge-tts` executable — it runs
  `bin/tts-worker` under its own bundle, and the dependency is the Ruby gem
  `rb-edge-tts`, pinned to a git source in the root `Gemfile` at 1.0.1. Two
  checks said TTS was unavailable here and both were the instrument: `command -v
  edge-tts` looks for something that never existed, and a grep for
  `rb_edge_tts` misses `gem "rb-edge-tts"` because the require spells it with
  underscores and the Gemfile with hyphens. The ground truth is one command —
  `echo hi | ruby bin/tts-worker en-GB-RyanNeural +0% +0Hz /tmp/x.mp3` — and it
  writes a real MP3.
- **A lint that checks a basename cannot see a namespace.** `rake autoload` was
  red and `rake lint:autoload` called the same file clean. The three files under
  `lib/review/scan/engines/` declare `Master::Review::Scan::PathFilter` and the
  directory implies `Scan::Engines::PathFilter`, so eager loading raised on a
  name the lint approved: it matched `module <Basename>` anywhere in the file
  and never asked at what nesting. It compares the whole path-implied constant
  now. All 45 ignores still measure as necessary under the stricter reading,
  which is the check that the fix did not just widen the hole.
- **`rake mutate` chose its candidates with a regex over the file text**, so it
  read a numbered list in a comment and the 8 in `"UTF-8"` as integers, and
  `sub` then rewrote the first match anywhere rather than the one in the code.
  Three well-documented files reported eight survivors for mutations no test
  could see. It walks Prism's token stream now and names the line each mutation
  is on. Same shape as every other entry here: the instrument, not the finding.
- **`rake selfcheck` reports a count with no locations.** `SelfCheck::Report`
  exposes `total`, `by_rule`, `by_severity` and `error` and no findings list, so
  the gate can say "7 violations across 3 rules" and cannot say where. Acting on
  it means re-running the scanner by hand. `ERROR_CONTEXT` is the rule it fails:
  an error must carry enough context to locate its origin. The task also prints
  its own label twice — `selfcheck: selfcheck: 7 violation(s)`.
- **Getting the locations by hand needs two unwraps and a Hash.** `Scanner#scan_dir`
  returns `Result::Ok([[path, Result::Ok([...])], ...])` and the findings inside
  are plain Hashes with symbol keys, not `Finding` objects — `f.rule` raises,
  `h[:rule]` works. Three attempts died on that before the count matched the
  gate's. Anyone writing a one-off census over the scanner should start from:

  ```ruby
  pairs = sc.scan_dir(File.join(Master::ROOT, "lib")).value
  all = pairs.flat_map { |path, res| Array(res.value).map { |h| h.merge(path:) } }
  ```

- **`tools/data_reach.rb` cannot tell which file a reader opened.** Its test is
  whether the key name appears anywhere in first-party code, so `success_criteria`
  counted as reached for as long as it existed — `lib/ground/phase_gates.rb:133`
  names it, reading session state rather than `rules.yml`. The 35 at the ceiling
  is a floor on the real number, not the number. The 2026-08-12 entry above
  already explains why a stricter version is not buildable; this is the direction
  of its error, which that entry does not state.
- **Two sweeps for the bug shapes `style.ruby.bugs_to_avoid` names found
  nothing, and one instrument was wrong.** No `@bus&.publish(...) || value` in
  `lib`, `bin`, `web` or `tools`. The only `Dir.chdir` is `bin/master:74`, which
  is the documented cause of the `/scan RAILS` path trap already recorded above.
  Four `next if` inside a `flat_map` turned out to be four `filter_map`s
  (`graph_retriever.rb:37`, `repo_ecology.rb:373`, `command_guard.rb:25`,
  `snapshot/collector.rb:99`) — `filter_map` drops the nil correctly, and a
  proximity-based grep cannot tell the two apart. Do not re-list them.
- **"A test that never names a `Master::` constant" is not a hollow-test
  detector.** It flags 38 files, and the bulk are gates that legitimately read
  files rather than constants — `doc_paths`, `doc_numbers`,
  `constant_collisions`, `security_sweep`. Same false-positive rate as the dead
  file census. The one hollow test found this session was found by reading the
  subject, not by a pattern: `test_fix_loop_priorities.rb` above.
- **The rule-id census is settled, and the earlier three answers are all
  explainable.** Build the scanner and read `@rules` — that is the collection
  `RuleOrder` receives from `ai_boot.rb:122`, and `r.id` is a `String`. It holds
  145 ids. A `Rule.registry` walk gives 142 because bridge classes are rejected;
  a regex over `law/*.rb` and `lib/review/scan/rules/*.rb` for `Law.define(:X)`
  and `RuleDSL.rule :x` gives 215 with mixed case, which is what
  `tools/rule_hygiene.rb` uses and why its numbers differ. All three are correct
  for their own question. For "does this key weight anything", only the first is.
- **Five rules carry no detector and no obvious class, and all five are
  accounted for** — do not re-list them. `WHITESPACE_PUNCTUATION`,
  `KEYWORD_ARGS`, `BARE_RESCUE` and `MESSAGE_CHAIN` each carry `folded_into:`
  naming the rule that reports for them, and `PROSE_OMIT_QUALIFIERS` is generated
  by `law/prose.rb` from the `prose.en.ids` mapping rather than declared.
- **`success_criteria` looked live and was not.** `lib/ground/phase_gates.rb:133`
  reads `@state["success_criteria"]`, and `@state` is loaded session state, not
  `rules.yml`. A grep for the key name finds the file and says nothing about
  which document it came from.

### MASTER cannot be asked to read a file — closed 2026-09-05

Two causes, both closed. `IntentRouter` classifies `read CLAUDE.md` as
`inspect_repo`, so it is not casual. Local CLI is the operator surface and no
longer sets `Fiber[:master_visitor]` for a missing `web_token` — that flag is
web-request only. Pipe mode honors ARGV. `Tool::Profile` reads
`agent_taxonomy.yml#toolset_groups`. Visitors on ai.brgen.no still cannot reach
the Fold.

### Tooling I wanted while doing the work above — 2026-09-05

Written from one long session spent inside the rule system: the rules file, the
fix loop's ordering, the coverage gate, the TTS probe, and tests for fifteen rule
classes. Every item is something that cost time in that session rather than
something that sounds good, and each says what it cost. Two candidates were cut
on checking, which is the point of checking: `bin/pub4 measure` already prints
every ratchet with its ceiling **and** names slack beneath one, so both wishes I
had about ratchets were already built. Read that command before wishing for
anything in its neighbourhood.

They are ordered by how much time each would have saved.

**1. A mutation harness — done.** `rake mutate[lib/foo.rb,test/test_foo.rb]`
flips comparators, nudges integers, inverts reject/select, runs the test,
restores. Survivors fail the task.

**2. One documented way to get findings out of the scanner — done.**
`Scanner#findings(paths)` returns a flat array of hashes with `:path`.
`tools/example_scan.rb` is the worked example. `scan`/`scan_dir` still return
the nested Result shape.

**3. `rake test` that runs on a dev Mac — done.** `test_web_ui.rb` sits with
`test_browser.rb` and `test_web_http.rb` behind `rake test:web_ui`. The default
glob no longer aborts on `rack/test`.

**4. Locations in every gate's output — done for selfcheck.** The report carries
findings with path and line, and the task prints that summary once.

**5. `bin/pub4 rule <ID>` — done.** `--corpus MASTER|all` and optional paths.

**6. A lint over the rule corpus's own regexes — done.** `rake lint:word_boundary`
flags `\b` glued to escaped punctuation. Currently clean.

**7. Every registry rule proves it can fire — closed 2026-09-06, 91 to 0.**
`law/` has always refused to load a rule without worked fixtures and the
registry accepted one without; `rule_fixture_debt` is the row that closed the
gap, and `test_rule_fixtures.rb` fails when the count rises, so a new RuleDSL
rule must carry `fires:`/`does_not_fire:`.

Two lessons are worth keeping, and both are in the rules themselves. A fixture
that passes for the wrong reason is what this ratchet exists to stop —
`TYPOGRAPHIC_EXCELLENCE`'s first draft, `warn "loading..."`, did not fire,
because the rule reads a bare quoted ellipsis and that is prose containing
dots. And a rule whose subject is a forbidden shape can still hold its own
example: `SILENT_RESCUE` reads a line that *starts* with `rescue`, so an
escaped one-line string is a worked example everywhere and a finding nowhere.
This file twice recorded that as impossible.

**8. One class per rule file — documented.** `AGENTS.md` now says
`require "review/scan/rule_dsl"` is the load that defines a class in a
multi-class rule file. Zeitwerk still maps one file to one constant.

**9. A finish-the-worktree command — done.** `bin/pub4 worktree finish` rebases
onto origin/main and pushes the branch. It does not merge to local main and
does not push main.

**10. A gate on the test-naming convention — done.** `rake lint:test_naming`
asserts MASTER/test is `test_*.rb`, not `*_test.rb`.

**11. Progress on the long gates — done for the two long runners.**
`RAILS/gates/runner.rb --all` prints `N/M name`. `bin/pub4 gate` prints
`gate: N/M stage`. Individual suites inside a stage are still silent.

**12. `data_reach` same-file check — done.** It reports keys named in code that
never mentions their yaml file, separately from the unnamed ceiling.

**13. Facts that are not rules — done.** They live in `MASTER/AGENTS.md` under
Working alone: scanner findings hashes, bundler/setup rewriting the lock,
Zeitwerk multi-class.

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

### Tier 1 — built and inert

The schema and the model exist. Nothing reads or writes them. These are the
cheapest items here and they gate most of Tier 2, because ranking and
notification both need a signal that is currently never recorded.

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

#### 1.1 Repost was a decorative button — **done, built**

The call was build rather than drop, because brgen is aiming at x.com and
Mastodon parity and `Announce` is repost (2.1 depends on it).

A repost is a `Repost` row, not a `Post`: `Post` includes `Shared::Sluggable`,
whose slug is derived from the title and unique per city, so a repost-as-post
would have collided with the thing it reposted. It carries no content, boosts
into followers' timelines via `User#timeline_posts`, notifies the author (but
not for reposting yourself), and toggles off on a second press.

The button is a `button_to`, not the `action` Stimulus controller the vote
button uses. Two reasons: that controller's optimistic toggle is exactly what
made the broken version look like it worked, and a third Stimulus instance per
card breaks `FrontPageWeightTest`'s five-per-post budget.

Three things the repo's own gates caught, all of them real:

- `reposted_by?` as an `exists?` per card is a 25-query N+1 on the feed;
  `QueryBudgetTest` failed on it. It is now one pluck per request memoised on
  `Current`.
- the card is fragment-cached and `reposted_by?` is per-viewer output, so the
  flag had to go into the cache key or one viewer's repost state renders for
  everyone.
- `FrontPageWeightTest` had a test asserting *no repost backend exists* and the
  button stays inert. It is inverted now: the button must reach the endpoint.

**Found while wiring it, and fixed:** `post_vote_path(post)` carries the slug
(`Sluggable#to_param`), and `VotesController#find_votable` called `Post.find` on
it — a 404 that the `action` controller rolls back silently, so **every vote
cast from a feed card was discarded**. Fixing that exposed a second layer:
`Vote#update_author_karma` lazily read `votable.user` on a strict-loading record
and raised after the vote had been written. Both pinned by tests.

**Check:** `brgen/test/models/repost_test.rb` (counter cache, uniqueness, undo,
timeline inclusion, author notification, cascade) and
`brgen/test/controllers/reposts_controller_test.rb` (POST toggle, guest
behaviour, removed posts, cache-key leakage, and voting by slug).

**Quote-post is built.** A `reposts.comment` column (max 280) turns the same
row into a quote; empty comment stays a boost; a second boost press still
destroys. The write surface is a form in the more-actions dropdown (no extra
Stimulus — FrontPageWeightTest still holds) and on the post page, which lists
quotes. It is not a `Post`, for the same Sluggable reason as a boost.

**Check:** `brgen/test/models/repost_test.rb` (quote is not a Post, length,
notification body) and `brgen/test/controllers/reposts_controller_test.rb`
(comment creates, updates a boost, second POST without comment destroys).

**Closed 2026-08-18.** The dead-partial note was stale: `shared/_feed_card`
renders `shared/action_bar` when it is given a `record:` and no `actions:`, so
the partial is reached by every app that draws a feed card.

#### 1.2 `Tv::ViewEvent` recorded that a page opened, not that anything was watched — **done**

The first version of this entry said no row was ever created. That was wrong,
and wrong for an instructive reason: the grep behind it searched for the class
name, and the only writer reaches the table through the association
(`@video.view_events.create!` in `videos#show`). Searching for the noun missed
the verb.

What was true: the row was created with `watch_time_seconds` and `completed`
both nil and nothing ever filled them in, and `Tv::Video.trending` sorted
`views_count` — incremented on that same page load. So a viewer who bounced
after four seconds moved a video up the trending page exactly as far as one who
watched it through, and the two columns that could tell them apart were never
written by anything.

Now: `videos#show` keeps the row in an ivar and hands the player its URL; the
player reports the furthest point reached on pause, on `ended`, on tab hide and
on disconnect. `record_progress!` takes the max (beacons arrive out of order),
clamps to the video's own `duration_seconds` (the number comes from the client,
and unclamped the ranking is forgeable), and marks `completed` at 90% because
the last `timeupdate` rarely reaches duration. `trending` now ranks by summed
watch time with `views_count` as the tiebreak, via a correlated subquery rather
than `left_joins + group` — the home page passes the scope to pagy, and pagy
counts a grouped relation with `.count(:all)`, which returns a hash.

Two things fell out of doing it:

- `data-tv-player-target="video"` was declared on no page in the tree, so the
  player's whole `#bindVideoEvents` body — including the wake lock on play —
  had never run. Watch-time reporting needs that target, so it runs now.
- `videos#show` preloaded `:channel` but not `channel: :user`, and the subscribe
  control reads `Current.user != @video.channel.user` only when authenticated.
  The page rendered for guests and raised for every signed-in viewer, which is
  why a guest-only smoke test never caught it.

**Check:** `engines/tv/test/models/tv/view_event_test.rb` (monotonicity, clamp,
90% threshold, no-duration case, strict loading, and that trending puts one
watched-through view above 500 page opens) and
`test/controllers/tv_watch_time_test.rb` (a viewer can only write their own
event; the page carries the progress URL).

**Closed.** The vertical feed this ranking exists for is 2.5, and it is built:
`tv_feed_test.rb` asserts one viewer who watched a clip through outranks 500
page opens, which is this entry's watch-time columns doing the work.

#### 1.3 `Marketplace::SavedSearch` never ran itself — **done**

Worse than a bookmark, as it turned out. The table carries a `notify` boolean,
the create form permits it, and the saved-searches page renders an "alerts on"
chip from it — while nothing in the tree ever ran a saved search on anyone's
behalf. Ticking "notify me" changed a label. The only other reader was a manual
"run search" link.

Now `SavedSearchAlertJob` runs every 30 minutes over searches with `notify` on,
matching new listings through `Shared::LiveSearch` on the same columns the
listings page searches, so an alert cannot disagree with what that row's own
"run search" link would show. Three things it deliberately does:

- a new `last_notified_at` column, anchored to `created_at` on first run, so
  switching alerts on does not mail you the entire back catalogue;
- a 6-hour floor per search, independent of the schedule, so the cadence of the
  job is not the cadence of the interruption;
- a quiet run leaves `last_notified_at` alone, so the next run still measures
  from the last thing the user was actually told about rather than silently
  stepping over listings posted in between.

**Check:** `brgen/test/jobs/saved_search_alert_job_test.rb` — eight tests
covering first alert, back-catalogue suppression, alerts-off, the interval floor
and its expiry, category scoping, the untouched watermark, and one broken search
not stopping everyone else's.

**Closed.** Price drops are `SavedSearch#price_drop_matches`, preferred over
plain new listings so a reduction on an existing match is not hidden behind "N
new listings", and `alert` is in `PUSHABLE_KINDS`, so the alert reaches a lock
screen.

#### 1.4 `takeaway_orders.delivery_driver_id` had no writer — **done**

The column had shipped with the table, carrying two indexes including a
composite `["delivery_driver_id", "status"]`, and
`Takeaway::DeliveryDriver has_many :orders` had always resolved through it.
There was no `belongs_to` on `Takeaway::Order` and nothing ever wrote the
column, so every order reached `out_for_delivery` with no courier attached.

Now: `belongs_to :delivery_driver`, and `transition_to!` dispatches the nearest
free courier on the same write as the status change, so an order is never
observable as out for delivery with nobody on it.
`DeliveryDriver.nearest_free` post-sorts the `nearby` bounding box by real
haversine distance — the box alone would take a courier in the corner over one
on the doorstep — and excludes anyone already mid-delivery. No free courier in
range is left as a real state rather than a failed transition: the order still
leaves the kitchen and the page says nobody is assigned yet.

**Check:** `engines/takeaway/test/models/takeaway/order_test.rb` — four tests
covering nearest-not-merely-in-box, no double-booking, dispatch with no courier
available, and dispatch on an order loaded without preloads.

**Closed.** `Maps::HomeController#courier_layer` draws the courier — the
viewer's own, and only while that order is out for delivery. A live position is
the courier's, not the city's: publishing every rider's would be tracking people
who never agreed to it, and the person waiting for the food is the only one who
needs it.

#### 1.5 Mention had a table and no writer — **done**

`Post has_many :mentions` resolved and stayed empty, while
`Notification::KINDS` already carried `mention` and the inbox ranked it first.
`Shared::Mentionable` now writes the join from `@username` in title and content
— the same `after_save` shape as `Shared::Taggable#sync_hashtags` — skips self
and unknown handles, and notifies only for new rows. An email address is not a
mention.

**Check:** `brgen/test/models/mention_test.rb`.

**Closed 2026-09-05.** `Stream` still has no writer. Live streaming is blocked
and that table stays.

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

Also open: outbound *following* (a brgen user following a remote account),
instance-level blocklists, and `Update` on edit.

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
`test/controllers/communities/wiki_controller_test.rb` (5).

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
`brgen/test/controllers/dating_likes_test.rb` (5).

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

**Check:** `brgen/test/models/listing_expiry_test.rb` (5).

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

### Six files over their length ceilings

`RAILS/test/file_length_ratchet_test.rb`, the one red file in the standalone
suite. `limits.yml`'s rule holds here too: a breach is paid by extraction or
deletion, never by a bigger number.

    gates/support/cdp_session.rb              374 / 339  (+35)
    shared/app/assets/stylesheets/_zen_shell.scss  502 / 477  (+25)
    gates/lib/research/design_metrics.rb      462 / 442  (+20)
    brgen/test/services/deploy_backlog_test.rb 631 / 618  (+13)
    gates/lib/live/user_flow.rb               320 / 313  (+7)
    gates/lib/rendered/rendered_geometry.rb   450 / 449  (+1)

101 lines between them. Four of the six are gate code that drives Chrome over
CDP, so an extraction there is only provable against a booted fleet —
`RAILS/bin/triangle up` first, or the split lands unmeasured. The counterpart
half of that test is green: no ceiling is slack any more.

Two left the list on 2026-09-06, and only one of them by extraction.
`page_inventory.rb` went 444 -> 288 by **deletion**, which is the note worth
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

**The remaining six carry nothing dead, measured 2026-09-06.** A Prism census
over every method in the five Ruby files finds zero with no caller. So they are
long files doing long work, and the only payment left is extraction.

Which is where the two ratchets meet head on. `file_length` is per file and
wants a split; `growth.rails` counts files and is 13 over, so every split costs
it one. Extraction cannot satisfy both, a raise is forbidden by both, and there
is nothing left to delete — the same structure `spine.lib_body_ceiling` has in
MASTER and the reason this list has survived several sittings. Closing it needs
either 13 genuinely dead RAILS files to pay `growth.rails` first, or an owner
raising one ceiling in a commit that says what the lines buy.

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

- **`Stream`** (`brgen/app/models/stream.rb`) has a table with `url`,
  `content_type` and `duration`, a `belongs_to :user` and `:post`, and no reader
  or writer anywhere in the app or its seeds. `Tv::LiveStream` is the
  live-video model and is a different class.

It is the shape the Tier 1 entries above closed one at a time: schema and model
present, nothing at either end. The question is whether to wire the writer or
drop the table.

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

---

## OPENBSD

### Operator debt — still open

The former `OPENBSD/data/debt.yml` `open:` register. Each item below
carries a hidden HTML-comment marker on its own line just under its
heading; `MASTER/lib/pub4/operator_docs.rb` counts those marker lines for
the `MASTER/bin/pub4 status` debt line, so keep exactly one per open item.

#### `libvips_local_build`  — tag: operator-priority

<!-- open-debt -->

vm23 runs a locally built libvips, and `pkg_add -u` will replace it with the stock package. The port graphics/libvips carries `-Drsvg=disabled` among the loaders OpenBSD turns off, so the packaged build has no svgload at all — librsvg-2.61.1 is installed beside it and is never reached. amber's garment cut-outs need it: Amber::GarmentSilhouette rasterises SVG it generates itself.
 Rebuilt 2026-08-23 from a signify-verified 7.8 ports tree with `-Drsvg=enabled` and `x11/gnome/librsvg` added to LIB_DEPENDS (the port path is x11/gnome, not graphics — `graphics/librsvg` fails as a broken dependency). Package kept at /usr/ports/packages/amd64/all/libvips-8.14.5.tgz, so a re-install after an update is `make reinstall` in /usr/ports/graphics/libvips rather than a fresh build.
 What makes this quiet: GarmentSilhouette#png returns nil and logs one line when vips cannot read SVG, and the seeder then keeps whatever photos the items already had. A stock-package upgrade therefore does not break the site, it just stops the cut-outs regenerating — nothing announces it. Re-check with `vips -l | grep svgload` after any pkg_add -u touching graphics.
UPDATE 2026-08-25: the detection this entry asks for exists. daily.local now
checks `vips -l` for svgload and logs loudly when it is gone, naming the
recovery (make reinstall in /usr/ports/graphics/libvips). Verified in both
directions — it passes against the live loader list and fails against a string
without svgload. Currently healthy: 4 svgload operators, vips 8.14.5. What is
left is the rebuild itself after a pkg_add -u, which is operator work.

#### `off_host_dr`  — tag: operator-priority

<!-- open-debt -->

Litestream has never replicated anything, and not for the reason this entry gave. Measured on the box 2026-08-12: the binary is not installed. `which litestream` finds nothing, pkg_info has no entry, and /etc/rc.d/litestream points at /usr/local/bin/litestream, which does not exist. rcctl has been reporting litestream(failed) in daily.out under "Services that should be running but aren't", next to httpd, for months. /etc/litestream.yml was also the pre-2026-07 version, with `path: <dir>` plus `pattern:` — a form litestream rejects — so even installed it would not have started. The repo's corrected copy (one entry per database file, three apps, hjerterom's stanza gone) is deployed, so the config is right whenever the package lands. Two things, in order: `doas pkg_add litestream`, then an off-host replica. The file:// replicas are on the same disk as the source, which covers an accidental delete and nothing else. Until then Shared::DatabaseSnapshotJob is the only thing backing up production.sqlite3, and it writes to that same disk.
 STOPGAP LANDED 2026-08-22: OPENBSD/bin/dr-pull pulls VACUUM INTO snapshots of every primary nightly to the operator Mac via launchd, integrity-checked and restore-drilled (brgen opens with 81,911 readable users). Litestream-with-a-bucket remains the endgame and needs an account.
RE-SCOPED 2026-08-25. This row reads as "there are no off-host backups", which
is false and has been for a while. dr-pull runs nightly from the operator Mac
under launchd, snapshots every production*.sqlite3 with VACUUM INTO, verifies
PRAGMA integrity_check on arrival and keeps 14 — verified by an actual restore
drill on 2026-08-25, posts and listings matching live exactly. The row is about
LITESTREAM, which is not in OpenBSD ports and so cannot be pkg_add'ed at all.
It is now rcctl-disabled and out of pkg_scripts, because a service that can
never start kept `rcctl ls failed` permanently non-empty and taught everyone to
skim the one list that announces a real outage. See OPENBSD/DECISIONS.md.

#### `multi_app_ram`  — tag: operator-priority

<!-- open-debt -->

vm23 ~1GB cannot keep master + brgen + amber resident, and bsdports is a fourth app that does not fit at all. UVM out-of-swap kills ruby34 when they all boot. Raise RAM (≥2GB) or run amber on-demand. Restart order: master → brgen → amber → relayd. Smoke: sh OPENBSD/bin/deploy-smoke.sh (ALLOW_AMBER_DOWN=1 if amber policy is optional). It also shows up as a STARTUP RACE rather than an OOM kill, and that form looks like a broken app. amber needs ~20s to signal ready; Falcon SIGKILLs the worker if that misses its health-check window, so while another app's CI has the box at load 5+, amber restarts, gets killed, and rcctl reports amber(failed) with port 61352 closed. It is not broken — `bin/rails runner` boots it (BOOT_OK) and on a quiet box it logs "Finished startup" then ready:true within ~20s and stays. Wait for the deploy to finish and restart. Do NOT reproduce this by hand without --health-check-timeout 300: the rc.d passes it, a bare `falcon serve` defaults to 30s, and the worker then dies at exactly +30s, which reads as confirmation of a timeout theory that is wrong.
 DECIDED 2026-08-22 (operator delegation): stay at 1GB with exactly one resident worker (brgen_jobs, ~380M measured, 131M free after). The resize question reopens only if amber earns its own worker.
UPDATE 2026-08-25: operator has scheduled the 2 GB upgrade for Friday. Until
then the shape is unchanged and the measurements stand — swap reached 96%
with no deploy running. vps-deploy already stands the app's job worker down
for the CI run (line 156, since the 2026-08-23 OOM); doing it by hand first is
unnecessary and makes that stand-down silently skip.

#### `internet_app_runs_as_passwordless_root_user`  — tag: operator-priority

<!-- open-debt -->

etc/rc.d/master:22 sets daemon_user="dev", and dev's doas rule is nopass with no command scoping, so ANY code execution as dev on the internet-facing app (ai.brgen.no) is root without a password. brgen/amber/bsdports correctly run as their own users; only master does not. The fix is a dedicated master user + chown. It is NOT doas command scoping — see DECISIONS.md, "/etc/doas.conf installs only on a deliberate root run", for why cmd rules cannot work here. REDUCED 2026-08-03: the `keepenv` half is gone (dev now has a five-variable setenv allowlist), so the environment-injection route to root no longer exists. The chat entry point into exec was closed 2026-07-27. The escalation primitive itself is unchanged.
 DECIDED 2026-08-22 (operator delegation): the dedicated master user migration is approved and scheduled as its own sitting — NOT improvised on a live box: create _master, chown MASTER runtime state (.master/, knowledge/, web/tmp, web/public/assets), rc.d daemon_user=_master, drop dev from doas or scope it, then a full restart drill. Until then dev's unscoped nopass doas stands measured (permit nopass ... dev as root, read from /etc/doas.conf on 2026-08-22).
NARROWED 2026-08-25. rc.d/master ran the internet-facing daemon as dev; it
now runs as master:1005, built to the same shape as brgen/amber/bsdports —
own group, _pub4ci for traverse, /bin/ksh because rc.subr needs a login shell.
It reads code and gems from /home/dev/pub4 (0755, read-only to it) and writes
only .master, web/tmp and web/log (dev:master 2775, setgid). Verified as master
before the switch: writing repo code refused, doas refused. /home/dev went
drwx--x--- to drwxr-x--- because getcwd needs read on every ancestor and
bundler calls Dir.pwd first; .ssh and priv keep drwx------.
STILL OPEN: `MASTER/bin/master` from a terminal is dev, and dev is still nopass root.
The remote path is closed; the local one is the remaining half.
COST, recorded 2026-08-25 because the next app to be moved will pay it too:
the first deploy that carried daemon_user="master" to the box did not bring
ai.brgen.no back, and vps-deploy halted the whole pass at master. Bundler.setup
ends in Definition#write_lock, which touches Gemfile.lock on every boot even
when the resolution is unchanged; the lock is dev's, so as dev that write had
always succeeded silently and as master it is EACCES and falcon never binds.
The trace names File.utime and says nothing about users or permissions.
BUNDLE_FROZEN=true in the daemon's env is the fix and is now load-bearing —
it also makes the structural Mac-vs-BSD lock drift a startup error naming the
gem rather than a silent rewrite. Before moving brgen/amber/bsdports off any
daemon_user, check the same assumption: the daemon had write access to its own
source tree and something was quietly using it.

#### `home_partition_full_from_git_history`  — tag: operator-priority

<!-- open-debt -->

Re-measured on the box 2026-08-12, as this entry asked. /home is at 89% (1.9G free of 17G), up from 99% that morning — the three retired apps (baibl, blognet, hjerterom) still had home directories worth 1.6G between them, for products removed from the repo in July. The git figure moved too: /home/dev/pub4 is 8.0G and .git is 3.3G of it, not the 7.7G recorded on 2026-08-02, so someone has run a gc. The claim underneath stands. The ten largest objects in history are 80–87 MB WAV renders under DEPLOY/dilla/renders/beats/, a path that no longer exists and never will again; every `git pull` deploy carries them, so this does not improve by itself and more RAM does not touch it. Operator-owned: the fix is a history rewrite, i.e. a force-push to a public repo. Strip these blobs in the same pass as the key purge above.
 RE-MEASURED 2026-08-22: /home is 67% (5.4G free) and the three retired app homes are gone. What remains is exactly the history rewrite, and it is SCHEDULED, not casual: it needs every session quiescent (STUDIO carries live uncommitted work), a coordinated force-push, and a vm23 re-clone in the same hour. Strip the WAV blobs and the key purge in one pass.
RE-MEASURED 2026-08-25: /home is 68% (5.3G free of 17G), not the 89% above.
The three retired app homes this entry names — baibl, blognet, hjerterom — are
gone, and /home/dev/pub4 is 4.9G against the 8.0G recorded, so the weekly
`git gc` in weekly.local is doing its job. .git is still 3.6G of the 4.9G,
which is the remaining shape of the problem, but it is not pressure: /var is
16% and / is 18%. Nothing here is urgent; the entry stays only so the .git
figure has somewhere to be re-read.

#### `amber_moving_to_its_own_apex`  — tag: operator-priority

<!-- open-debt -->

amber is intended to move from amber.brgen.no to amberapp.com (operator, 2026-08-11, not yet bought). Filed before the move because one coupling is easy to miss and expensive: the session cookie is `domain: :all` (shared/config/initializers/session_store.rb), which scopes it to the REGISTRABLE domain. Today that is brgen.no, so a visitor who signs in on brgen.no is signed in on amber.brgen.no. On a separate apex the cookie stops crossing, and the replacement — Shared::SsoToken — is consume-only here: nothing in this repository mints one (the minting side is MASTER's and is not in this tree). So cross-app identity would go from working-by-cookie to unimplemented, silently, for anyone who expects it. The fleet plumbing mostly follows apps.yml now and does not need hand edits: port_inventory, domain_alignment's live_apexes, health_check --public-only and therefore uptime-check.sh all derive from it. What does need hand work: an acme cert and a relayd keypair for the new apex, ALL_DOMAINS in OPERATOR.sh, DNS (own zone in nsd or external), deploy_inventory.json's mirror, canonical/sitemap hosts, the PWA manifest start_url and scope, and any CSP or embed allowlist that names brgen.no. Worth doing for revenue reasons as well as branding: TradeDoubler publisher approval and AdSense site review both go easier for an apex that is the product than for a subdomain of something else.
 CORRECTED 2026-08-22 (later): amberapp.com is a REDIRECT SHELL — every path returns the same 114-byte JS-redirect page (verified: /fonts/* serve text/html there and font/woff2 on amber.brgen.no). The apex is bought and certified but the app does not live there yet; the move itself, with the entry's coupling list, is still ahead. DECIDED: amber keeps its own identity space (no cross-apex SSO — separate product, separate accounts); remaining hand work is the canonical/redirect choice for amber.brgen.no and the sitemap/manifest host sweep the entry lists.

#### `rails_audit_backlog_2026_08_10`  — tag: agent-workable

<!-- open-debt -->

The tail of the 2026-08-10 UI/UX audit, grouped because these were 12 separate one-line entries that shared a tag, a provenance and a shape. Each needs reading per site rather than a sweep, which is why they are still here. 104 associations with no inverse_of (changes in-memory identity and interacts with strict_loading_by_default — a decision per association). 102 CSS selectors with no literal match in ERB/JS/Ruby (class names are also composed at runtime, so a literal search cannot prove death). 64 controllers with a create and no rate_limit — DONE 2026-08-13, and the subset was right: of 98 controllers with a write action, 84 had no rate_limit and 6 of those were write actions a request with no session can reach. All six now carry one, and the guest-reachable question is asserted rather than recounted by RAILS/test/guest_write_rate_limit_test.rb, which also asserts its own detector still finds guest writes at all — a source-text checker that stops matching reports zero gaps and reads exactly like a clean tree. The one that mattered was Fediverse::InboxesController#create: unauthenticated by protocol, and it calls ActorFetcher.for_key_id BEFORE verifying the signature, which is an outbound HTTPS GET to a URL taken from the sender's own Signature header. Verifying first is not available as a fix — the key needed to verify is what the fetch goes to get. The others were amber's signup (brgen's equivalent had carried 10/10min all along) and brgen's email-subscription create, which queues mail to an arbitrary address over brgen.no's SPF and DKIM. Found on the way and worth more than the entry: FOUR controllers declared two rate_limits and named neither. ActionController::RateLimiting builds its key as ["rate-limit", scope, name, by] with name defaulting to nil, so two unnamed limits in one controller share a counter — Rails documents this on the method itself. MessagesController's 30/minute and 40/3-minutes on :create therefore shared a key for every signed-out sender, incremented it twice per request, and blocked at 15; the 3-minute limit never existed, because whichever call created the key set its TTL. Two correct-looking lines, no code change needed to introduce it, and the same defect class as everything else in this file. RAILS/test/rate_limit_naming_test.rb holds it, and also re-reads actionpack's rate_limiting.rb to check the upstream behaviour the rule depends on is still true rather than enforcing a rule about nothing. 56 raw hex values in stylesheets (var() fallbacks and dialect token definitions are correct by design). 29 destructive links with no confirmation interstitial. 11 models with no validations at all. 9 inline style attributes bypassing the token system. 9 numeric z-index values above 10 not from a token — the ladder itself is the finding; two disagreeing sources already made the brgen logo invisible once. 6 `display: none !important` hiding chrome the shell renders on every page (auth, print, immersive verticals, dating splash); deleting the render is not available while the layout is shared. 5 hardcoded placeholders and 3 hardcoded submit labels — same chrome_i18n rule as rails_flash_strings_untranslated, on the highest-traffic strings on a form. 5 image_tag calls with no width/height (layout shift), 1 more without lazy. 3 div/span elements carrying a click action — not focusable, not keyboard-activatable, not announced as a control. Small CSS groups left as judgement: 3 css_blur, 2 css_line_height_tight, 2 css_radius_large, 1 value_no_declaration. READ THIS FIRST: no committed tool reproduces these counts, and two of the rows are already covered by tools that count something else. The rule names above (css_blur, value_no_declaration) exist nowhere in the tree; a plain grep answers 24 for the z-index row and 287 for the hex row, because it cannot make the exclusions the audit made by hand; and css_constitution ALREADY measures and ratchets magic_hex — at 151 against a ceiling of 150, over stylesheets excluding vendor, node_modules and builds — which is neither this row's 56 nor the grep's 287. Same for the !important and file-size rows, which frontend_auditor reports as non-blocking warnings. So the first move on any of these is to name the instrument, not to fix a count: an unfalsifiable number is how a register row outlives its subject. rails_flash_strings_untranslated is the worked example — writing the lint moved a hand-counted 144 to a measured, ratcheted 169.
 TRIMMED 2026-08-22, rows that got their instrument: raw hex -> css_budget magic_hex (140, ratcheted); !important and file-size -> frontend_auditor warnings; dead selectors -> css_coverage_lint (174, DYNAMIC_SEEDS-aware); the 3 div/span click rows examined — two were @window listener HOSTS (correct pattern, audit misread) and the sheet backdrop gained keydown.esc@window so keyboard users can leave. Still uninstrumented and open: inverse_of 104, destructive-link interstitials 29, validation-less models 11, inline styles 9, the z-index ladder, image dims, and the small CSS judgment rows.
TRIMMED 2026-08-25, the three uninstrumented rows got their instrument.
RAILS/shared/lib/pub4/model_contract_lint.rb ratchets uninferrable_inverse
(54) and no_validations (10); destructive_action_lint.rb ratchets
unconfirmed_destroy (30). Both are wired into MASTER/tools/ratchets.rb and
appear in `MASTER/bin/pub4 measure`. The inverse_of number is 54 rather than the 104
counted by eye because half of what a grep calls a missing inverse_of is an
association ActiveRecord infers by itself, and reporting those is reporting
Rails working; the detector encodes the cases automatic_inverse_of documents
itself as giving up on. no_validations lands at 10 against 11 and
unconfirmed_destroy at 30 against 29 — reproducing a hand count is the reason
to trust a detector. What remains under this row is the per-site judgement it
always described, now with numbers that cannot drift while nobody looks.
CLOSED 2026-09-05: the per-site judgement was done and all three read 0 against
a floor of 0. 55 associations name their inverse and two say in a marker that
the other side does not exist; four models gained a validation mirroring a
unique index that was otherwise reached as a 500 and five say in a marker why
they promise nothing; 25 destructive controls say why they are reversible and
four gained a prompt. Two instruments were wrong on the way and both are fixed
— model_contract read one line of a multi-line association, which called four
declared inverse_of options missing and never saw eight wrapped foreign keys,
and chrome_i18n read "the line above is a comment" as "this line is a comment",
so the new markers silently excused two live findings. The RAILS rows of this
register are done; what is left in this file's OPENBSD section is registrar and
operator work.

#### `bsdports_org_delegated_to_parking`  — tag: operator-priority

<!-- open-debt -->

open 2026-08-25, registrar-side. bsdports.org does not resolve: the .org registry delegates it to ns1/2/3.expireddomain.hyp.net — Domeneshop's parking servers — which publish no A record. Confirmed against b0.org.afilias-nst.org, not a cached resolver. The registration is ours and paid to 2027-08-08, and whois shows autoRenewPeriod, so the shape is: it lapsed on 2026-08-08, Domeneshop moved the nameservers to parking, the registration auto-renewed, and the nameservers were never put back. Everything downstream still believes in it — relayd holds a keypair and a Host match, a valid certificate sits at /etc/ssl/bsdports.org.fullchain.pem to Nov 10 2026, RUNBOOK.md names https://bsdports.org as the URL, OPERATOR.sh probes it, rcctl says ok and the app answers 200 on 47312. It has simply been dark. Fix is one registrar change: set the nameservers at Domeneshop to ns.hyp.net and ns.brgen.no, which is what brgen.no uses. Do it before Nov 10 or the certificate renewal fails too — acme-client needs the name to resolve here for HTTP-01. Nothing we had could have caught this: domain_watch takes its population from nsd.conf and bsdports.org is not a zone we serve, and the expiry watch reads expiry, which is paid. dns_zones now asks a public resolver whether each app domain points at 46.23.89.226, and fails on this one.
STILL OPEN 2026-08-29, and this row owns it — `WISHLIST.md` 104 names the same
registrar change and points here rather than restating it. `dns_zones` also
fails on nine domains that are past expiry, which is `WISHLIST.md` 103: money at
a registrar, not code, and not a finding to re-open under a second name here.

### Debt — resolved records

Closed records are deleted when they close, and `git log` holds them. A finding
that is fixed is not a backlog item, and a file that keeps every one it ever had
teaches the reader to skim. What stays here is forward work and the false
positives worth not re-discovering — those are guards, not history.

## STUDIO

No standing backlog file exists for STUDIO, and none is invented here. dilla,
postpro, repligen and lora carry their working decisions in their own
`README`/`AMBITION`/`ENV_AND_RENDER` docs and in operator memory, not a debt
register. Two standing constraints belong on the record because they bound any
agent work in this tree:

- **Renders are irreplaceable.** dilla and postpro write real output with
  rotating seeds; never render over a take that matters, and never change a
  rendered-sound or graded-look default on your own judgement.
- **dilla is production tooling**, aimed at being genre-agnostic (Detroit lean,
  but techno/soul/jazz must blend as parameters). That direction is a design
  goal, not a backlog item to close unprompted.

### The crate — what 2026-09-02 established about it

Measured while answering a question about disk, and the numbers are worse than
the question was.

- **160 of the crate's 161 sources no longer exist.** Every rack's sidecar
  names the file it was chopped from; exactly one, `samples/dug/arat_swost_wolet.mp3`,
  is still on disk. `samples/dug/` was gitignored, so the 2026-08-31 tree loss
  took it and the reclone could not bring it back. The 2-second loops in
  `samples/chopped/` are now the only surviving audio from those records.
- **The crate is in no backup.** `STUDIO/dilla/.gitignore:11` ignores
  `samples/` wholesale — zero racks are tracked — and `OPENBSD/bin/dr-pull`
  copies the three production databases and nothing else. So 12 minutes of
  irreplaceable audio lives on exactly one disk, which is the state
  `samples/dug/` was in the day before it went. **This is the open item**: pull
  `samples/` to the same rotated off-box location dr-pull already uses, or
  somewhere the operator names.
- **37 duplicate racks were deleted 2026-09-02, on the operator's instruction.**
  `radio_chop.rb:664` records the cause: one shared work directory keyed cuts on
  the window's offset alone, so record B was handed the cut record A made at the
  same decisecond. 161 racks carried 123 unique loops; Barney Kessel, Gorillaz
  and "Gimme the Flu" were one wav under four names. The fix (a directory per
  source) was already in; the damage was not, and none of it could be re-chopped
  because all 66 affected sources are gone.
  The rule was: keep every rack the liveset names, then the earliest
  `rendered_at` in each group — the rack whose own chop run made the audio,
  since the later ones only reused its cached cut. A dry run caught the rule
  deleting `andrzej_koszinski_eurocr_01`, a live bed, because a *second* rack in
  its group was also a bed and won on age; keeping every named rack is why one
  duplicate pair deliberately survives. 124 racks now, 123 unique, all 22
  liveset beds resolve.
- **`scratch/chop_work` was deleted with them** — 2,144 files, 5.4 GB, the
  Henryk Debich windows and their six-stem separations. It was never wired into
  the liveset (the rig globs `samples/chopped/*/`), and its one consumer, the
  chop cache, is unreachable because `RadioChop.chop` scans the source before it
  consults the cache and that source is gone. It was still 67 minutes of audio
  against the crate's 12, and it is not recoverable.

### The engine is one file

dilla.rb carries the 81 parts that were under `lib/engine/`, in the order they
were required, because that order was load-bearing. 129 ruby files to 48.
`DillaSources` still defines the corpus and it is now the entry plus the 41
support modules; `STUDIO/gate.rb` fails if `lib/engine/` reappears, and
`DILLA_SUPPORT_CEILING` caps the modules that could grow in its place.

Not done: the 41 `lib/*.rb` are still separate. Fourteen of them use `__dir__`
or `__FILE__`, which shift a directory level when a file moves — the bug that
broke three tests during the first fold, and the reason to do the second one
deliberately rather than as a tail-end.


### The crate — opened 2026-09-01

The chop cache was keyed on a window's offset and not on the record, fixed in
`003e0a9f9`. What follows is what that fix does not repair and what looking for
it turned up. The preset half of this subject is `WISHLIST.md` 100–101 and is
not restated here.

- **Forty-one of the crate's forty-two sources are gone.** `samples/dug/` holds
  one file. They were gitignored on the reasoning that dug audio is
  "re-fetchable from the network", and nothing recorded a URL — not
  `provenance.json`, not one of the 161 loop sidecars, which carry only the
  reproduce command and so name a path that no longer exists. Only the titles
  survive, in the slugs. Re-fetching by title returns *a* upload, not the one
  that was cut, so offsets and mastering will not match and no loop is
  reproducible from its sidecar. One record is the exception:
  `henrik_debich`, whose separated stems outlived its source in
  `scratch/chop_work/` and were moved under their slug rather than orphaned.
  New fetches record the HTTP URL: `CrateDig.archive_entry` / `ccmixter_entry`
  store `url`, `record!` refuses an entry without one, and the chop sidecar
  copies it from crate provenance. The 160 already-missing sources stay gone.
- **Thirty-eight of 161 racks are another record's audio under the wrong name.**
  123 unique wavs, 28 collision groups; Barney Kessel, Gorillaz and "Gimme the
  Flu" share one loop. The cache fix stops it recurring and repairs none of it:
  reattributing a rack needs the source that made it, and the sources are the
  entry above. The registry can be deduplicated to 123 by checksum — that is
  measurement — but which of the names in a group is the true one cannot be
  recovered, so the honest move is to drop the duplicates and keep whichever
  rack the worth table already scored.
- **153 of 161 racks were cut by the seam test that preferred mid-phrase.**
  `28225f2c9` fixed it and re-cut only the OSC eight, saying plainly that the
  rest is re-cut or left alone. Re-cutting is blocked by the missing sources, so
  the only source-free remedy is rotating each loop onto its strongest downbeat,
  which is content-preserving because a rack is one whole period. Measured over
  the crate: current downbeat mean +1.17 dB against +2.86 for the re-cut eight,
  108 of the 153 sitting under 1 dB. **The measure needs a floor before it is
  acted on** — several of the largest apparent gains are a quiet tail scoring as
  a downbeat, not a bar line, and one rack starts at -57 dB.
- **148 registry rows carry only what a wav can be asked for.** The rebuild that
  recovered the crate after the registry was clobbered reconstructed bpm from
  each file's own duration and voicing from its spectrum, and `key` was measured
  back on 2026-09-01. `source`, `source_start_sec`, `self_similarity` and
  `rejoin_db` are gone for those rows and cannot be recomputed without the
  source. `vocal_chop` skips a row that cannot name its record rather than
  guessing, which is why those 148 have no vocal chop available.
- **`DRUM_LOOP` falls back to `~/Downloads`.** `drum_loop_source`
  (`dilla.rb:7215`) resolves to `File.expand_path("~/Downloads/techno_drums.mp3")`
  when the samples copy is absent, and the samples copy is absent. A render
  therefore depends on a file outside the repo, and the one there is industrial
  techno, which the crate rules exclude. Naming the replacement is an operator's
  call because it changes rendered sound.
- **`test_dilla_audio_graph_parity.rb` follows the engine.** Bus routing is
  opt-in (`DILLA_MIX_BUSES=1`); the default path is still a flat amix, and the
  test asserts both.
- **Three engine tests exceed their 90 s timeout under suite load.**
  `test_smoke_two_bar_render`, `test_provenance_separates` and
  `test_dilla_frozen_reads` each pass in about 23 s run alone and time out
  inside `rake test`. Not a defect in what they measure; the budget does not
  survive a loaded machine, and a green subset here proves only that.

## The unified handoff, read against the tree — 2026-08-31

`CLAUDE_OPUS_UNIFIED_HANDOFF.md` arrived at the repo root in `8dfe41309` as an
implementation brief. It is 302 lines and it stops mid-list, at
"pagination/filtering;" under section 7 — the file is truncated, so anything the
author intended after the Rails test matrix is not in this repository at all.
It is also a fourth file at a root that `CLAUDE.md` says holds two, and most of
its asks restate this file or `WISHLIST.md` in different words, which is the
"two backlogs saying the same thing" defect the preamble here names. It is left
in place rather than folded or deleted, because that is an owner's call; what
follows is the audit, so the next reader does not do it again.

Its own first instruction — "reconcile every change against the current tree
before applying it, do not blindly paste historical snippets" — is what this
audit is. Two of its premises did not survive that reconciliation.

**3.2, the circuit-breaker hazard — done, and its premise was already stale.**
The brief asks after a `Stoplight::Light` NameError and says to check the tree
rather than assume. Checked: `Stoplight` appears nowhere — not in `lib/`, not in
the `Gemfile`, not in `Gemfile.lock`. There is no hazard to repair and no stale
reference to remove. The half that was real is the one it names second: test the
replacement's states. `Master::Io::CircuitBreaker` is hand-rolled and its two
existing tests covered the rate limiter and the per-model registry, so the
closed -> open -> half_open -> closed machine, the eight-failure threshold, the
thirty-second cooldown and the recovery had nothing holding them.
`MASTER/test/test_circuit_breaker_states.rb` holds all four now, plus the two
error classes that must *not* open it (a provider rate limit, an absent key) and
the state file that survives the process. Verified by mutation: four separate
breaks in the implementation each turn it red.

**4, multi-agent safety — done.** "Where hooks already exist, test them as
executable behaviour rather than documenting them only" was the sharpest line in
the brief, and it was exactly right. `OPENBSD/dev/githooks/` holds the three
guards that are the whole defence against trap one, and nothing tested any of
them. A hook that stopped firing looks identical to a week in which nobody made
the mistake. `OPENBSD/test/test_githooks.rb` runs all three through real git in
a throwaway repository — real commits, a real bare remote, a real push — because
a hook is installed behaviour and unit-testing its logic would not catch a lost
chmod, a bad shebang, or a `core.hooksPath` pointing somewhere else. It covers
every case the brief lists (cross-tree refusal and its override, multi-commit
push refusal and its override, the clean single-commit path, the diagnostic
output) and three the brief did not: the half-landed move, STUDIO session
ownership, and that an absent session ledger reads as "unknown" rather than
accusing every commit of being foreign.

**3.1, 3.3, 3.4, 3.5, 3.6, 5, 6, 7 — open, and each is a sitting.** These are
programs, not tasks: boundary validation for every data contract, the
require-order graph, snapshot rollback, autoloop fencing, dead-session startup,
routing resilience, and a full Rails audit with a test matrix. Where they touch
something this file already tracks, this file is the record and the brief is a
restatement — do not open a second row for the same work under the brief's
numbering.

## Cross-cutting programs

Larger efforts that span trees or do not belong to any single one. Each is a
program with its own sitting, listed so they are visible in one place rather
than implied across four.

- **Realtime wiring — instrumented and down to one recorded exception, 2026-09-05.**
  `turbo_broadcast_contract_test.rb` already asked whether a broadcast has a
  partial. It now reads every *named* stream from both ends, and two pairs had
  never matched: `brgen:notifications:*`, written on every notification create by
  a synchronous `broadcast_prepend_to` and read nowhere, and `items`, subscribed
  by amber's busiest page against a model that declines `broadcasts_refreshes` on
  purpose. Both removed, each with the reason at the site. The one tolerated
  entry is `NotificationDeliveryJob`, which is enqueued by nothing and kept only
  until vm23 confirms no queued row names it; `UNREAD_STREAMS` carries it and
  fails if it stops being true.

  Literal streams only, and that is the whole of the instrument's honesty:
  `broadcast_refresh_to self` names its stream at runtime, and guessing which
  view subscribes to `@conversation` is how a census reports the shape of the
  tree and calls it a defect. Three false positives died on the way and each is
  worth not re-deriving — the ERB comment recording a dropped subscription read
  as the subscription, `broadcast_refresh_to` was outside the DOM-verb pattern so
  three quarters of amber's streams read as orphans, and
  `Turbo::StreamsChannel.broadcast_append_to(` puts its stream literal on the
  next line, which made `LocationsController` silent and the layout's
  `nearby_alerts` subscription an orphan. Mutation-checked in all three
  directions: a new dead broadcast, a stale `UNREAD_STREAMS` entry, and a
  restored orphan subscription each turn it red.

  What is left is the dynamic half, deliberately: a stream named by an object
  rather than a string needs a runtime instrument, not a wider regex.
- **Seed realism.** Coordinates and timezones for every DomainRegistry city
  live in `CitySeed::COORDINATES` / `TIME_ZONES`. Population is still unset.
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
  and no `claude` CLI are present.
- **PWA banner.** Closed 2026-09-05. The banner waited for a post/play/chat
  after `beforeinstallprompt`, so a first visit that only read never saw it.
  It now shows when Chrome can install, and on iOS (where that event never
  fires) it tells Safari/Chrome how. The three apps already shipped the
  partial, the worker, and the manifest.
- **Aegis, seaborne.** A safety agent for the water, and the first body the
  embryo could plausibly take. It is a program rather than a feature because
  most of it is gated on hardware; the section below says what is buildable now
  and what is not.

## The layout pass — opened 2026-09-02

A study of joi.com, kimi.com and medium.com, read against this tree, produced
roughly 178 proposals. They are worked one category at a time, and about sixty
are closed. The list itself lived in a conversation and was never written down,
so perhaps forty of the closed items are recoverable only from `git log` and
another forty of the open ones are gone. That is the defect this file exists to
prevent, and it is recorded here rather than quietly repaired: what follows is
what survived, not a copy of the original.

What the pass has actually taught, which is worth more than the list:

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
  cannot be moved without changing the render are recorded as baselines with the
  argument written down, never snapped to silence the lint.

### Closed

- **Motion**, 14. Thirty duplicate reduced-motion resets collapsed to the one in
  `_animations.scss`, with `scroll-behavior: auto` promoted into it because
  `animation: none` does not reach it (`4211c4ebb`).
- **Measure**, 10. `--measure-body` was a second name for `--measure`'s 66ch,
  declared three times and used seventeen; collapsed across sixteen files, and
  `rules.yml` corrected from 65ch to 66ch (`e2dc94299`, `a85160ee7`).
  It came back on 2026-09-05 and the route in is worth knowing:
  `layout_contract_test` still asserted the retired spelling in
  `_dialect_tokens.scss`, so the collapse left a red test behind and the obvious
  way to make it green was to re-declare the twin. `design_tokens.yml`'s
  `measure_body` key reads like a token the CSS forgot to emit and is not — it
  is YAML `design_metrics` reads. **A retirement is not finished while a test
  still names the retired thing.** The assertion asks the real question now: the
  measure is declared exactly once, in `_typography.scss`, under one name, and a
  second declaration anywhere in the four stylesheet trees fails (`cd09222b0`).
- **Weight discipline.** `--weight-heavy: 800` is now the top of
  `scale.font_weight` rather than an exception to it: the ramp in use is
  400/600/800, which is the only even ladder meeting `min_weight_delta: 200`,
  and system-ui carries a drawn Heavy. Retired the last 31-finding baseline
  (`1e32bd964`).
- **Grid and tiles**, 14. Nineteen tile grids gave nineteen answers to how
  narrow a column may get, four of them in rem against two different roots;
  six steps now, ten grids moved, none by more than 20px (`b7760ac8c`).
  Thirteen tokens the tree asked for were declared nowhere -- the fallback
  always won, and one had none, so `.tv-feed-title` shipped with no
  font-size. Two lints could not read their own opt-out (`b49b2c82d`).
- **Surface and colour**, 12. Three compat aliases -- --surface2, --text-dim
  and --radius -- were 104 call sites and seven declarations of a second
  name, and the mechanism had already caused a 1.23:1 contrast bug that the
  comment above them documented. The alpha ladder was the one scale nothing
  measured, and its two hand-kept copies had drifted by a step (`67ec62871`).
- **Mobile**, 12. Ten were not problems -- the tree already writes dvh, guards
  touch and reads safe-area everywhere. The two that were: `--tap-min` spent the
  law's 44px from five hand-written copies with nothing comparing them to the
  rule, and eighty-three var() fallbacks named the token they fell back from,
  three of which were hiding an alpha from the ratchet (`21ba3e7ca`).
- **Elevation and hairline**, and **bsdports**. Both finished rather than
  skipped: one `box-shadow` across 106 stylesheets, and zero auditor warnings.

### Open, by category

Counts are what remained when each category was last read; re-measure before
working from one.

- **Controls** — 10 left.
- **brgen** — 9 left.
- **Radius** — 6 left.
- **amber** — 5 left.
- **Instrument** — 4 left.

### Held open deliberately

- **Duration baselines.** 20 off-scale durations in the apps and 33 in the face,
  recorded rather than snapped. Twelve of the twenty are 160ms. The face keeps
  its own timings — `.09s` and `.15s` `steps(4,end)` belong to a terminal
  redrawing in character cells, not to the apps' four-step ladder.
- **Four face transitions exceed `NO_LONG_TRANSITION`.** `face.css:380` at
  1200ms, `:635` at 1800ms, `:867` at 400ms, `:1015` at 600ms, and
  `chat_upload.css:42,48` at 420ms each. Left alone: this is the operator's own
  face timing, and the rule caps UI transitions, not a deliberate slow reveal.


### Grid and tiles, what it left open — 2026-09-04

The tile ladder landed and the undeclared tokens are gone. Three findings from
the same pass are open, each measured and none of them a guess.

- **The generated-asset gate cannot see a stale committed build.** Closed
  2026-09-05. It now compares simple custom-property literals in the committed
  `application.css` against the SCSS (and mixin defaults, the same source
  `fallback_drift_lint.collect_from_scss` already reads). `--bg: #{$bg}` is not
  a literal, so it does not report every dialect as drift. `--radius-card:
  16px` in a build whose sources say 12px does. The checksum rebuild is still
  the exact check and is not this.

- **The remaining `layout_rules` keys are now read.** `design_metrics` already
  read `gap_over_margin`, `card_padding_px`, and `target_recommended_px` (must
  be ≥ `target_min_px`). It now also refuses a missing `grid.columns`,
  `paragraph_margin_em`, `section_padding_min_rem`/`_max_rem`,
  `split_sidebar_ratio` (must sum with `split_main_ratio` to 1), and
  `visible_grid_optional`. `prefer_monochrome_with_one_accent` is read next to
  `max_palette_roles`. The CSS scans for children-with-margin and card padding
  other than 24px landed 2026-09-05 as `css_constitution` tallies
  `child_margin` (floor 0, pens skipped) and `card_padding` (1:
  `_minimal.scss` `.card { padding: 1rem }`, a look decision).

- **`--border-strong` is declared only in `MASTER/web/public/face.css`.**
  brgen's composer asked for it twice and got its `var(--border)` fallback both
  times, which is now written directly. The intent — a border stronger than the
  default one — has no token in RAILS. Naming one is a design decision, not a
  lint fix.

Two more dead indirections sit in the face, outside this lint's reach:
`face.css:372` asks for `--x-font` (the `x_` prefix was retired from the design
system) and `:399` for `--c-mic-off`. Both resolve to their fallbacks. The face
is one-theme by design and its colour lines are the operator's, so they are
named here rather than edited.

### Surface and colour, what it left open — 2026-09-05

- **Sixty-four off-scale alphas, now measured.** apps 26, face 38, recorded as
  baselines rather than snapped. Eleven of the apps' twenty-six are chrome and
  card washes between 6% and 45% and could go on the ladder for a small visible
  change each; the rest are the three engines that paint glass — playlist at
  94%, maps at 92%, tv at 78% — where the number is that pane's own opacity and
  moving it is a decision about the surface.
- **Twenty-two color-mix blends are a separate axis and deliberately unmeasured.**
  `color-mix(in srgb, X 22%, var(--surface))` mixes two opaque colours; 22% is a
  ratio between them, not a transparency. Fourteen distinct ratios. A tint ladder
  would be a real design decision, not a lint.
- **`large_text_contrast` is read.** `visual_contract_lint` takes its text floor
  from that key (AA 4.5). `design_metrics` still enforces `normal_text_contrast`
  (AAA 7.0) on every token pair, large text included — a stricter bar than WCAG
  asks, and a choice, not an unread key.
- **`visual_contract_lint` hardcodes 3.0** for UI/accent pairs. Text now reads
  `large_text_contrast`. Raising the CI floor to AAA 7.0 would flood the
  compiled bundles; `design_metrics` is the gate that enforces
  AAA. Both currently pass, so nothing is broken — but the CI lint would not
  notice a pair falling from 7.0 to 4.6.
- **`prefer_monochrome_with_one_accent` is read** next to `max_palette_roles`
  in `design_metrics`. The numeric cap is the check.

### Mobile, what it found and what it did not — 2026-09-05

Ten of the twelve proposals were not problems, which is the pattern by now and
worth recording so nobody re-derives it. The tree writes `100dvh` twenty-six
times against one `100vh` (now none), guards touch with `touch-action` fifteen
times and `overscroll-behavior` twelve, reads `safe-area-inset` in eighty-nine
places, and has no `text-align: justify` anywhere. The mobile hygiene is done.

- **Sticky hover is not a defect here, and this is why.** 122 `:hover`
  declarations across 52 files, and only four `@media (hover: ...)` guards —
  which reads alarming until the hovers are classified. Eighty-two only repaint,
  thirty declare nothing that matters on touch, and the ten that move or reveal
  are all opacity or transform nudges. `.edge-grip` even carries a
  `@media (hover: none)` permanent affordance beside its hover. No menu, no
  reveal, nothing that strands a tap. Re-classify before re-opening this.
- **`justify_never_on_mobile` has no reader and nothing to catch.** The rule is
  satisfied by a tree that never writes justify; a check would measure zero
  forever. Left as doctrine.
- **`target_recommended_px` is read.** `design_metrics` requires it ≥
  `target_min_px`.
- **`width: min(360px, 100%)` in `_nearby_chat_widget.scss`.** Was 100vw, which
  includes the scrollbar gutter. 100% of the positioned containing block.
### Where the ratchet stands, 2026-09-04

Every kind sits exactly on its baseline, which is what a ratchet with no slack
looks like: `off_scale_opacity` 67 (apps 29, face 38), `off_scale_duration` 53
(apps 20, face 33), `off_scale_space` 48 (apps 16, face 32),
`off_scale_tracking` 14 (all face). Radius, line-height and font-weight are at
zero on both surfaces. `RAILS/shared/design_tokens.yml` holds
the baselines and the argument for each; the contract is that none is ever
raised to silence a new finding, and a staleness test forces a lowering when one
is beaten.

## The wish list, read against the tree — 2026-08-31

`uplift_summary.txt` sat untracked at the root: the owner's own words, six
numbered layers. It is folded here and the file removed, because a wish list at
a root that holds two files is the same "second backlog" this file's preamble
names. Each layer below is what the tree actually holds against it, so the next
reader does not re-audit.

One word about the word. That file called the whole thing an "uplift", and the
six layers are not one job: making the tree legible (1 and 6), making a stated
rule enforceable (2 and 5), and collapsing duplication (3). An umbrella that
vague is how three of the six came to be already built without anyone checking —
so the umbrella is dropped here rather than renamed, and the layers are read one
at a time. Where this tree needs a word for the third of those it already has
two. `collapse` is a rule id — `COLLAPSE_BEFORE_ADDING`, declared and with no
detector, which is its own entry below. `fold` is what `lib/core/` and
`rake lint:spine` mean, and it is enforced.

**1 · Orientation — a map and a glossary. Done.** The map already existed and
is reached from `AGENTS.md`: `data/agent_map.yml` routes by topic,
`START_HERE.md` is the contract, `OPENBSD/tools/tree.rb` draws the layout. The
glossary did not. One arrived during the Codex cluster and was removed with it —
five entries, three of them terms this repo does not use ("Gravity Debt", "The
Bridge"), which is what a glossary written from outside a tree looks like.

The replacement is a section of `AGENTS.md` rather than a file, because
`COLLAPSE_BEFORE_ADDING` applies to documents too and its reader is the agent
already reading that file. It defines the words that mean one thing here and
something else everywhere else — law versus rule, conduct, twin, intentional
marker, fold and spine, ratchet and census, inconclusive, verdict, tier, the
triangle, vertical, the face — and every entry names the file behind it, so a
claim about one can be checked. Three of them were wrong on the first pass and
the tree said so: `face.part4.txt` does not exist, brgen has six engines and not
five, and the intentional marker is honoured by `Rule#scan_lines` as well as by
the law engine. Related: **`tree.rb` on entry** and **Onboarding** above.

**2 · Guardrail — traps out of documentation and into hooks.** Done, and before
the wish list was written. `OPENBSD/dev/githooks/` holds all three guards, they
are installed through `core.hooksPath` by `bin/pub4 hooks`, and
`OPENBSD/test/test_githooks.rb` runs them through real git in a throwaway
repository. The cluster's `bin/pre-commit-hook.sh` and `bin/trap_check` were a
second copy of the first two thirds of that, using `wc` and `grep`, which the
house rules ban in committed scripts.

**3 · Technical debt — decompose the God Classes in Scanner and Dispatcher.**
Scanner is done: 466 lines to 139, with `PathFilter`, `ProgressReporter` and
`Transport` beside it in `engines/`. The record of how that went is above and it
is the cautionary half of this layer — an extraction that carries a method out
and puts a stub back is worse than the class it replaced. Dispatcher was already
done: `llm_dispatcher.rb` is 410 lines over `react_loop`, `ruby_llm_sender` and
`tool_registry`. What is actually large now is `structural_rules.rb` at 814 and
`surface_rules.rb` at 635, and both are registries of independent rules rather
than classes with gravity, so neither is the same problem.

**4 · Face and body — normalise the deploy pipeline between Rails and
OpenBSD.** Open, and the sharpest piece of it is already recorded: every deploy
sheds amber and bsdports while relayd keeps answering TLS on their closed ports,
so the outage reads as a hang. `OPENBSD/deploy_smoke_gate.rb` now checks the
named-table-plus-forward shape `relayd.conf` actually uses rather than a backend
block that never existed, which is a start on the same surface.

**5 · Studio — asset versioning to protect irreplaceable renders.** The write
site refuses an existing named take unless `DILLA_OVERWRITE=1`; scratch and
stream demo.wav still overwrite. `render_seed` now honors `RENDER_SEED` when
GEN_SEED and SEED_TEXT are unset. About 0.012 dB of run-to-run spread remains,
so a bit-identical re-render is still not available.

**6 · Future agent — optimise the repo for LLM-native navigation.** This is
layer 1 plus the standing complaint that the gap here is discoverability rather
than features. The concrete moves already named: the glossary, `tree.rb` on
entry, the profile matrix published in one place, and one name for one job — the
entry-point ratchet in `spine.yml` is what keeps the last of those honest.

## From the 2026-08-31 session

Raised while building the audio-driven README loop and the file-discipline
rules. Each was found by measurement, and each is left with what it would take
to finish rather than a bare title.

- **`rules.yml` refactor.** Aggressively DRYing the law wants a measured pass.
  It was held while the gate was down and the scanner mis-scanned; both of
  those closed on 2026-09-01, so the block is gone and only the work remains.
- **Three outboard units are in no rack.** `freq_shift`, `phase_rotate` and
  `hedd_triode` are built and dispatchable in `Outboard.chain` — the `when`
  arms exist — but no rack names them, so those arms are dead. They are also
  the most advanced processing in the tree, which is what makes it worth
  either wiring them into a rack or deleting the arms.
- **Six Sonitex knobs have no reader.** Docs now say so: `ENV_AND_RENDER.md`,
  the README, and `dilla.rb`'s ENV help. Wiring them still changes rendered
  sound. Use `SONITEX` / `SONITEX_PRESET`.
- **`Policy.default_volume` has no reader.** `+40%` in `data/voice.yml`,
  hardcoded again at `lib/voice/policy.rb:20`, exposed at `:65`, consumed
  nowhere — not by `browser_payload`, not by the worker. Left inert
  deliberately: wiring it changes how MASTER sounds, which is an operator's
  call. That file's own header is a long account of a voice value living in
  more places than the one that changed; this would be the third entry.
- **Merge the three techno renderers.** `render_industrial`,
  `render_hate_techno` and `render_techno` share `techno_harmony_roots` and the
  schedule builders but hold genuinely different arrangements, and
  `dilla.rb:815` records that giving industrial its own target was "a sound
  decision, not a gap." Read all three before cutting; merging on surface
  similarity flattens the arrangements into one sound.
- **`dilla.rb` is 34,545 lines.** `GLOSSARY.md` defines gravity debt as a file
  over 300 lines; this exceeds it by 115x and holds 71% of the engine against
  `lib/`'s 41 files and 14,263 lines. Split along the seams it already has —
  the renderers, the ENV default tables, the SMF writers, the patch registries.
  The direction is out of the monolith, not into it.
- **RAILS token discipline, from the joi.com study.** Three patterns worth
  taking, none of them ornament: colours composed from a named opacity scale
  rather than hardcoded alpha, line-height bound to a semantic role rather than
  a size, and one spacing primitive with `calc` multiples instead of ten
  hardcoded steps. Do not take the 8-step radius scale, the rounded cards or a
  webfont — `--font-brand` is a deliberate zero-byte stack. Line-height landed:
  both surfaces read zero off-scale. The other two are open, and belong to the
  layout pass rather than to this entry — check there before starting either.
- **Flatten `STUDIO/dilla/renders/` into the dilla root.** Operator's
  instruction. It needs `.gitignore` rules to follow the files, since
  `renders/` is currently ignored wholesale, and `dilla.rb`'s hardcoded
  `File.join(ROOT, "renders", ...)` defaults move with them.

## From the 2026-09-01 audit

- **Live RAILS gates still measure too little.** `user_flow`, `first_screen`,
  `payment_honesty`, `content_honesty` and several rendered gates skip when the
  app ports are closed. Run the suite once with `GATE_REQUIRE_LIVE=1`,
  `GATE_STRICT_INCONCLUSIVE=1` and `GATE_STRICT_ERRORS=1` on a host where brgen,
  amber and bsdports are listening, then record any findings that only appear live.
- **Nine domains are expired.** Renew `brmingham.uk`, `cardff.uk`, `denvr.us`,
  `dnver.us`, `edinbrgh.uk`, `glasgw.uk`, `lverpool.uk`, `mnchester.uk` and
  `wshingtondc.com`, then refresh the expiry snapshot with
  `OPENBSD/bin/domain_watch.rb --update`.
- **The yep search pen still owns a magic hex.** `#ccc` is currently banked at
  139 because it is the pen's own divider. If/when the pen is re-tokenised, use
  an existing border token or a named pen token and ratchet `magic_hex` down
  with `GATE_CSS_RATCHET=1`.

### From the 2026-09-01 session sweep

Fifty-seven session transcripts read back against the tree, asking of each
whether its work is present here. Almost all of it is: the 2026-08-31 tree loss
was made good by the `pub4-rescue` snapshot, and a file-level diff of that
snapshot against this checkout leaves nothing of substance behind. These are
what the sweep found still open, each verified against the tree rather than
taken from the transcript that raised it.

- **The three journey-gate follow-ons are done and the journeys have run.**
  `brgen` and `bsdports` carry `test/integration/authorization_matrix_test.rb`
  beside amber's, mutation-checked. `requires_data` is `inconclusive!` rather
  than `warn`. And `flows.yml` has three signed-in writing journeys where it
  had none — 55 steps, all GET, no flow declaring an actor. Driven live on
  2026-09-02 against a booted triangle with an account seeded per app:
  **`flow_journey PASSED`, 25 checks ran, 1 skipped**, and a deliberately wrong
  password fails it with `landed back on /session/new — refused, not signed in`.
- **`flow_journey` could never have reported PASSED.** Found by running it: the
  gate never called `GateResult#checked!`, so `measured_nothing?` saw
  `checks_ran == 0` and one skipped precondition spoke for the whole run — 25
  journeys green under a verdict line reading "checked nothing". Fixed, and it
  is the same defect `checked!` was written for in `human_walkthrough`, which
  suggests looking at the other gates that never call it.
- **A skipped writing journey does not block, and the earlier note here said it
  did.** `GATE_STRICT_INCONCLUSIVE` promotes only `measured_nothing?`, so a run
  that exercises 25 journeys and skips one passes in strict mode too —
  `gate_result.rb` explains that this is deliberate, because promoting at
  record time once made a gate that ran fifty checks and skipped one hard-fail
  on the deploy host. What unchecked buys is that the journey is named in
  "Not checked" every run and never counted among the passes; noticing it is
  still a person's job. If that is not enough, the missing piece is a
  per-journey severity, not a stricter reading of the existing flag.
- **`bin/sine_stream.rb:967` is the last un-oversampled `asoftclip`.** Every
  other saturation site in dilla runs `oversample=4` or `8`; this one runs the
  ffmpeg default and aliases above Nyquist. It is left alone deliberately —
  changing it changes how the stream sounds, which is the operator's ear and not
  a gate's. Worth an A/B before it moves.
- **brgen's `Gemfile.lock` was written by a different bundler major than the
  box resolves with.** vm23 runs ruby 3.4.9 with bundler **4.0.17**; amber and
  bsdports record `BUNDLED WITH 4.0.7`, brgen records `2.7.2`. brgen also
  writes its `RUBY VERSION` as `3.4.9p82` where the others write `3.4.9`,
  which is the older bundler's format — so the whole lockfile, not just the
  footer, came from 2.x. Not fixed here on purpose: the body was resolved by
  the bundler that wrote it, `vps-deploy` installs from it on a 1 GB box, and
  `vps_gemfile_lock_drift` already records that a Mac-written lock against
  BSD-only gems is how this breaks. Re-resolving is a deploy-day change with
  a rollback plan, not a footer edit.
- **The 61-track crate fetch was abandoned at 2.** `~/dilla-crate-incoming`
  holds two FLACs and three fetch scripts from the 2026-08-31 rebuild, which
  finished by another route — `samples/chopped/` has 162 entries. Either resume
  that fetch deliberately or delete the staging directory; a half-finished
  download beside a finished crate reads as the crate.

---

---

## Session record — 2026-09-02, Big Pickle

The dead-route cleanup on RAILS (`e33df9923`) and the three OPENBSD fixes
(`118f38835`) were signed by me. The five OPENBSD findings were verified against
the file source and the live box before any of them was touched, and that
verification changed the plan twice, which is the record to keep:

**Verified, then fixed.** `setup_litestream` installed a `etc/rc.d/litestream`
template that e511ccba1 had retired and neither the tree nor vm23 carries;
`install_template` exits 1 on a missing source, so every `--stage-2` and
`--first-install` aborted there. The fix keeps the config install for the day a
replica exists and drops the rc.d install, matching the comment that was already
there. `--first-install` reached `stage_1` (the DNS-material wipe) without the
`I_UNDERSTAND_DNS_WIPE=1` guard `--stage-1` requires; the guard now gates both
entry points. `brgen_jobs` has been in `pkg_scripts` since e511ccba1 and
confirmed live; the rc.d footer and `operator.yml` still said no `_jobs` service
was enabled, and both now say brgen_jobs is and the others are not.

**Verified, then left alone.** The `chmod 555 /etc/rc.d/master` in OPERATOR.sh
is immediately overwritten by the `chmod 755` loop over every `/etc/rc.d/*`, yet
the box runs every app rc.d at 555. Both lines came from the same original
split, so the intended mode is ambiguous, and neither reading is contradicted by
a comment or a RUNBOOK line — changing the mode of a live service file on my own
judgement is exactly the render-default trap in different clothing. Left for the
operator, reported, not touched. The duplicate `ruby "$REPO_ROOT/RAILS/...` and
`$m3dir/../RAILS/...` fallback in the last-clock check resolves to the same path
under `/home/dev/pub4`; redundant but harmless, same call as the chmod.

**Re-confirmed, already owned.** `dns_zones` still fails on bsdports.org
(resolves to `185.134.245.114, 2a01:5b40:0:bc04::1`, not `46.23.89.226`). That
is `bsdports_org_delegated_to_parking` above, open since 2026-08-25 with a "do
it before Nov 10" deadline; no second entry was opened because the first one
still owns it.
