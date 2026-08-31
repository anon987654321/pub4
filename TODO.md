# pub4 backlog

The single backlog for the whole repo. One file, at the root, replacing the
per-tree lists that used to drift out of sight of one another: `MASTER/DEBT.md`,
`RAILS/TODO.md`, `RAILS/BLOCKERS.md`, and the `OPENBSD/data/debt.yml` register.

Authority order is unchanged: `MASTER/data/soul.yml` > `MASTER/data/rules.yml` >
the root `CLAUDE.md` > the per-tree contract. Feature truth is still
`RAILS/apps.yml`; horizon (aspirational, agent: ignore) is still
`RAILS/apps.horizon.yml`. The decision records — `MASTER/DECISIONS.md` and
`OPENBSD/DECISIONS.md` — are rationale, not backlog, and stay where they are.

How to read this file. Each tree has its own top-level section. Within a tree,
**forward work** (parity gaps, blockers, detectors still to write) is separated
from **"Debt — resolved records and what not to chase"**, which is cautionary
and historical: closed items kept for the rule they taught, and false-positive
or already-built findings recorded so nobody spends a week re-discovering them.
Do not read the resolved-records subsections as an action list.

One habit this repo learned the hard way, and it governs every finding below:
**a finding is a hypothesis; re-measure before working from one.** Naive
pattern-matching over this tree produces mostly false positives, and several of
the entries here were themselves stale when written. Verify the instrument
before the finding.

An item leaves this file when a check proves it, not when it stops being
mentioned.

`WISHLIST.md`, beside this file, is the other half and not a second copy of it.
It is forward work from one day's findings, numbered and short. This file is the
standing record with the reasoning, including everything already closed. So a
closed item belongs here and an open, new one belongs there, and where the two
touch the same subject only one of them carries it and points at the other by
number. Two backlogs saying the same thing is the defect this repo keeps writing
down.

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

Re-checked 2026-08-30, and the absence claim holds with one trap in it.
`DATA_CLUMPS`, plural, **is** in `data/rules.yml` — as a `violation_priors`
row and as a node in `data/rule_deps.yml`, where `PRIMITIVE_OBSESSION` is
ordered `after: [DATA_CLUMPS]`. No rule carries that id in either population,
so the prior is never read and the ordering never applies; `RuleOrder#topo_sort`
skips a dependency whose id names no loaded rule. So the detector below is
genuinely unbuilt, and building it as `DATA_CLUMP` singular leaves the existing
prior and dep node pointing at nothing. Name it `DATA_CLUMPS` and both wake up,
or delete those two rows in the same pass.

Both of those tables hold more names than the rule populations do, and how
many is not settled here: three separate attempts at that census gave three
answers, because `Rule.registry` is short until `RuleDSL` is touched and short
again until the rule files are required, and because `violation_priors` mixes
rule ids with principle names like `ABSTRACTION` and `DENSITY` that live in a
different namespace. The count is a sitting of its own with an owner. What is
recorded here is only the part that survived every version of the instrument:
`DATA_CLUMPS` names no rule, in either table.

#### Larger AST work — multi-session projects

These are not single detectors; each is its own sitting, with an owner and a
design, not a sweep.

- **One shared AST-walk helper.** `visit` is copy-pasted across roughly eight
  rule files. Extract the walk once and have the rules declare what they look
  for, so a fix to the traversal lands in one place.
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

### Debt — resolved records and what not to chase

This subsection is cautionary and historical — the former `MASTER/DEBT.md`. It
is not an action list. It carries closed items kept for the rule they taught,
the scanner conventions this codebase keeps relearning, and several standing
"agent-ignore" tracks where chasing the count is the mistake. Read it before
calling a MASTER finding new: it very often is not.


What is open in MASTER, plus the scanner conventions this codebase keeps
relearning. Deploy debt is the OPENBSD section below; RAILS debt is the RAILS
section.

How a closed item leaves this file: it goes, and if it taught a rule the rule
moves to `DECISIONS.md` or to the "Scanner Conventions" section below. The
narrative of *how* something was fixed is what `git log` is for — this file was
660 lines on 2026-08-11 and most of it was fix history for work already done,
which made the open items hard to find and let four of them go stale unnoticed.

### The runtime did not boot at all — closed 2026-08-31

`MASTER/data/providers.yml` gave `agy` a `ruby_llm_key: agy_api_key`. `agy` is
the Antigravity CLI — `command: agy`, reached by executing a binary, and its
`env` names `AGY_BIN`/`ANTIGRAVITY_BIN`, which are paths rather than keys — so
RubyLLM has no `agy_api_key=` and never had. The same row carried
`min_key_length: 0`, and `apply_api_keys` gated on `key.length >= minimum`, so
the unset `AGY_BIN` satisfied `"".length >= 0` and the setter was sent on every
boot. `RubyLLM.configure` raised `NoMethodError` inside `Master::Builder.build`,
so `bin/cli` died before it had done anything, and with it `/scan`, `/critique`
and `/review` — every command the gate's lexical and council tiers run.
`bin/pub4 gate --scan-only` reported `lexical FAILED — err: MASTER command
failed: /scan --no-autofix .` with the stack trace of a scan that had not
started.

The second half was quieter and would have outlived the first. `min_key_length:
0` also made `any_api_key_present?` unfalsifiable: it is `specs.any? { ENV[var]
.to_s.length >= minimum }`, and one row with a zero minimum answers true for
every machine, key or no key. So `keyless_llm_enabled?` could never engage on
its own, `no_api_key` was unreachable, and the council believed it had a
provider. Fixed in `key_present?`, one predicate all three readers share: an
unset env var is not a key, whatever the minimum.

`apply_api_keys` now skips a `ruby_llm_key` the installed gem has no setter for
and names the env var it skipped, so the next provider this tree adds ahead of
its gem support costs a warning instead of the runtime.
`MASTER/test/test_provider_key_wiring.rb` holds it by asking
`RubyLLM::Configuration` rather than restating what it offers, so a ruby_llm
upgrade that renames a setter fails here and names the provider.

The rule: **a config value that makes a check answer the same way every time is
worse than a missing check**, because the check goes on being cited. The other
one: a `>=` against a zero floor is not a test.

### An unreachable CLI led every fallback chain — closed 2026-08-31

Found by the same thread as the boot crash, one table over. `agy` is the only
entry in the routing data that is not an API model: it names the Antigravity
CLI, reached by executing a binary. `models.grok_primary` leads with `agy:auto`,
and both places that hand out ids from that pool did so without asking whether
the binary exists. So on a machine with no agy installed, `Master.default_model`
answered `"agy:auto"` whenever an OpenRouter key was present — reached, note,
only *after* `return "agy:auto" if agy_cli_available?` had already declined —
and `ModelRouter#fallback_chain` led with four agy ids that could only be failed
over one at a time.

What hid it: `MASTER_NO_AGY_CLI` exists and both `agy_cli_available?` methods
honour it, so the guard looked complete. The ids arrived by a different path,
where nothing asked. Fixed in one place rather than four, next to the same
question about web chat — the chain is assembled from every `models.*` tier,
`grok_primary`, the auth lanes and `primary_models`, so a per-table guard leaves
three tables unguarded.

The same fact ran the other way in the test suite, which is how it surfaced.
`test_keyless_routing.rb` cleared eight API keys and `MASTER_NO_CLAUDE_CLI` in
setup but not `MASTER_NO_AGY_CLI`, so four of its nine assertions passed or
failed according to whether the machine running them happened to have the
Antigravity binary on PATH. They failed here and pass in CI, which is the worst
way for a test to be wrong: the suite disagrees with itself by host and neither
result is evidence. `MASTER/test/test_agy_reachability.rb` now pins both
directions with a real executable stub, because a reachability check that is
only ever exercised one way is the half that was already true.

### Four slack ceilings nobody has ever been told about — opened 2026-08-31

`TestRatchets#test_no_ratchet_is_slack` skips when the measured trees are dirty,
and the reasoning in its own comment is right: this checkout is shared, the
advice is "write this transient number down permanently", and on 2026-08-15
following it would have recorded a figure 121 lines below the committed truth
because another session was mid-delete.

The consequence was not noticed. This checkout is *always* dirty — it was dirty
for every run of this suite in living memory — so the assertion has been
skipping rather than passing, and `1 failures, 1 skips` reads at a glance like
one problem. Run from a clean worktree on 2026-08-31 it fails immediately and
names four ceilings that have been slack for an unknown length of time:

    rule_reach          56 / 57    lower it in MASTER/data/rule_reach.yml
    namespace            4 / 77    lower it in MASTER/data/namespace_ceilings.yml
    sprawl.lone_dirs    51 / 53    lower it in MASTER/data/sprawl_census.yml
    growth.studio      138 / 224   lower it in MASTER/data/spine.yml

None of them is this session's: all four measure the same on a clean checkout of
`origin/main`. Two are one- and two-point falls that their own tools can record
(`rule_reach.rb --ratchet`, the sprawl census). Two are not routine and want an
owner: `namespace` has 73 points of room, and `growth.studio` has 86 because
dilla's engine folded from `lib/engine/` into one file — lowering that to 138
means the next STUDIO file fails `measure` on the day it is written, which may
well be the intent and is not an agent's call to make silently.

The general lesson is the one this file keeps writing down in other words: **a
skip is not a pass, and a suite that skips its own invariant under the
condition that always holds has stopped asserting it.** Same shape as the gate's
inconclusive stages. Worth asking of every other skip in the suite whether its
guard condition is the normal state.

### Neither scanning tier can reach a verdict — opened 2026-08-31

With the boot crash above fixed, `bin/pub4 gate --scan-only` gets a running
scanner for the first time and the stage now fails a different way: `/scan
--no-autofix .` over MASTER printed 226 lines and was killed at
`MASTER_GATE_STAGE_TIMEOUT` (1200s) without a verdict. So the ladder's first
rung has still never reported a lexical result — it has only changed which
sentence it says while not reporting one, and raising the timeout is explicitly
not the move until somebody knows where the time goes.

The council tier does the same thing, one stage later: `/critique .` printed 151
lines and was killed at the same 1200s. Before the boot fix it failed instantly
with "Insufficient credits"; it now reaches the runtime and runs out of clock
instead. So the same shape twice, and whatever the answer is below, it is worth
two stages rather than one.

What was measured, so the next attempt does not start from zero. Per-file rule
cost is not the explanation: the whole scanner, 142 rules including the external
linters and the law bridge, costs **0.08s** on a representative Ruby file
(`lib/boot/runtime.rb`), of which `ast_omission` is 0.044s and everything else
rounds to nothing. Markdown and YAML are cheaper still — 0.01s and 0.02s across
all 128 zero-argument rules. At that rate MASTER's 1089 files are about ninety
seconds, not twenty minutes. The scan's own progress line tells the same story
from the other side: it reported `eta=50s` at file 30 and `eta=2843s` at file
55, so the cost is not per-file-uniform and is not in the rules that were timed.
Look next at what runs *between* files — `ScanLive.snapshot!` writes a report to
disk on every hit, and `CrossFileAnalysis` re-reads the whole corpus at the end.

The four detectors added the same day are not the cause, and were measured
before being kept: 0.33s across 200 files for all four, against 2.24s for the
128 zero-argument rules over the same files. That is a larger share than four
rules should hold (14.6% for 3% of the rules) and the reason is architectural
rather than theirs — `Rule#check` calls `Prism.parse` per rule, so a file is
parsed 128 times. The parse cache in "larger AST work" below is the fix, and it
would pay for far more than these four.

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

`rake selftest` reports **0 findings, re-measured 2026-08-19**. The 1 of
2026-08-18 — `god class Constitution is 348 lines` — closed the way the
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

`test/test_heartbeat.rb:44` (`self_test_heartbeat_publishes_clean_scan_metrics`)
fails *because* this count is non-zero — a symptom of this track, not an
independent defect.

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

`rake selfcheck` is **31 violations across 7 rules** (re-measured 2026-08-19
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

Still open, structural (the line-matcher cannot see them):
`operator_principles` (27) vs `principle_map` (272) with zero name overlap —
two principle vocabularies, nothing naming the authoritative one — and
`Consensus::DEFAULT_MODELS` restating models.yml's three_mirror pool
(marked as the copy it is in the source).


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

- `data/tts.yml` and the whole Transcendent path — **open**, and the largest
  instance found so far. `Voice::Speech` has exactly three consumers —
  `health_controller`, `tts_controller`, `TtsJob` — and all three enter through
  `synthesize_streaming_to_file`, which goes socket → oneshot → espeak and never
  reaches `Transcendent`. The only door in is `Speech.synthesize`, whose only
  caller is `synthesize_audio`, whose only caller is `synthesize_bytes`, which
  nothing calls. So `Transcendent`, `Melody`, `Emotion`, the five-engine chain,
  `replicate_kokoro` and `WarmErratic`'s prosody table are all unreached by
  anything running: roughly 1,500 lines that look configured and live.
  The tell was a comment, as usual — `data/tts.yml` claimed
  `OPENBSD/etc/rc.d/master` sets `MASTER_TTS_MODE=classic`, and that variable is
  set nowhere, in the repo or in `/etc/master.env` on vm23. A control that does
  not exist, described over a subsystem nothing reaches.
  `DECISIONS.md` records why it is not simply wired to the streaming path.

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

- **52 one-file directories**, against a ceiling of 53. Most are Rails test
  convention mirroring `app/`, and `MASTER/spec/` has five of its own. Neither
  is wrong; both are countable. Read the live figure from
  `MASTER/bin/pub4 measure`, not from here — the number in this paragraph is
  the kind that goes stale in a day.
- **7 uninformative names, now 4.** Four are Zeitwerk's: `lib/io/base.rb` is
  named after the constant it defines, so the finding is that the *concept* is
  called `Base`, which is a design decision and not a rename. The three that
  were actionable — `STUDIO/test/helper.rb`, `STUDIO/test/dilla/helper.rb` and
  `STUDIO/test/tools/helper.rb`, three different helpers at three depths sharing
  one name, ambiguous in a stack trace — are flattened to `studio_helper.rb`,
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

**The cross-tree test is still here, under a different name — re-measured
2026-08-29.** `test_dilla.rb` is gone, so that half of the entry read as closed;
it is not. `MASTER/test/test_radio_bergen_study.rb:6` requires
`../../STUDIO/dilla/dilla`, and through it reads
`RAILS/brgen/config/radio_bergen/tracks.yml` — one test file reaching into two
other trees. It had already broken the way this entry predicted: it asserted
`assert_equal 9, local_count` while the manifest had grown to 30 rows when radio
bergen started serving its own catalogue, so `rake test` in MASTER was red for a
change made in RAILS, naming the growth as the regression.

Fixed by asserting the invariant instead of the instance — the study covers
every row the manifest holds, counted from the manifest — which is Scanner
Convention 5 below applied to a count rather than a name. Mutation-checked:
truncating `catalog_rows` to five rows fails it.

What is still open is the coupling, not the count. A test in MASTER that loads
STUDIO's entry point to read RAILS's data breaks whenever any of the three moves;
it belongs in STUDIO, beside the module it exercises.

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

### The cost meter — closed 2026-08-27

`Session#record_cost` now accumulates `tokens_billed` next to `cost`. The
tooltip reads that counter, not `token_est` (a conversation-local byte
estimate). A `/through` that spends money and reports `0 tok` was the meter
mixing the two.

### The fix stage skip breakdown — instrumented 2026-08-27

The LLM lane used to publish pass-level `{stuck: N}` as `skip_breakdown`,
which is how 33 minutes of `fixed=0` still did not say whether proposals
never arrived, died in reflexion, or were fingerprint-skipped. `RuleLoop#run_once`
now returns the per-violation tally (`no_proposal`, `skip_fingerprint`,
`reflexion_rejected`, …) and `LlmStage` aggregates it. The acceptance path
is still the bottleneck; the log can now say which door it died at.

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

Six shapes of one defect: **each converts the absence of a property into
evidence of it.** A gate, a test or a reader accepts something that merely looks
like the thing it was checking for, and the result is a defect that arrives
carrying its own certificate of compliance. All five were found in the same week
of 2026-08, in different subsystems, by different sessions.

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

#### What follows from all six

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
- **The gap between 181 registry classes and 225 declared rules.** Checked
  2026-08-12 on the theory that the difference was inert law — declared rules
  nothing implements, which would be this file's dominant defect class at the
  constitutional layer. It is not. **Every one of the 225 has a detection path**:
  118 semantic-only, 69 registry+lexical, 7 lexical-only through the YAML bridge,
  and the rest combinations. Zero with none. `RuleRegistryAudit` already measures
  the split, `SelfTest` reads it, and `test_rule_registry_audit.rb` pins it.
  What the check did produce is the line below.
- Media-generation severance: re-severed 2026-07-14 (`76b11fec4`), confirmed
  permanent 2026-07-15. `docs/SEVERANCE.md` is the source of truth. If the LoRA
  training loop needs generation capability again, express it as
  `lib/core/world.rb` handlers per the original absorption plan — do not restore
  the deleted `io/lora_pipeline.rb` / `video_chain.rb`.

### The two per-site queues, re-measured — 2026-08-21

Both queue numbers from the deep scan were stale instruments, not stale work.
**UNBOUNDED_RETRY "65" closed at 0**: the law's narrowing had already
dissolved the comment/symbol/kwarg findings, and the final four were the
WORD retry inside string literals (a scanner's own finding message, an SSE
body, the SOA field name) — the detector now blanks strings first, because
the keyword can never be inside one. **NO_GOD_CLASS "98" is 22 → 21**: the
code-lines switch had collapsed most of it; one was the instrument counting
a Minitest class's tests as public methods (now excluded), and TtsJob's four
worker-plumbing class methods went private. The 20 that remain are recorded
per-site design work, in castes: ten Rails domain models whose public
methods are their domain API (decomposition is a product decision, and
amber is another session's active turf); four controllers carrying non-REST
action sets; TtsJob's real split (job vs status-handle, fragile TTS
plumbing); ChatService at 417 code lines; and utility APIs (GateResult's 22
methods are its result vocabulary). Ratchet-held; none can grow silently.

---

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

**Still open:** the Temu-flavoured work on top of `Marketplace::Deal`.
`starts_at`/`ends_at` and the `active` scope are there and nothing renders a
countdown from them; coupons, referral credit and bundle pricing have no model
at all.

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

### 4. The gates cannot see a WebGL surface — **done**

`gates/support/cdp_session.rb` launches Chrome with `--disable-gpu`, so
`webglSupported` is `false` in every rendered gate. MapLibre and the MASTER face
both need WebGL, so **both measure as an empty canvas** — a gate asserting "the
map draws" would pass or fail for reasons that have nothing to do with the map.

Found on 2026-08-13 while checking a report that `maps.brgen.no` was broken. It
is not: with `--use-angle=swiftshader` the map renders Bergen, its tiles and its
markers, with zero console errors. The blank screenshot came from the
instrument, and any gate built on that instrument would have inherited it.

`--disable-gpu` is right for the layout and CSS gates it was written for —
software GL is slow and its text rasterisation differs — so the fix is probably
a separate opt-in flag for the WebGL surfaces rather than dropping it globally.

Done that way: `gates/lib/rendered/webgl_surfaces.rb` opts into SwiftShader per
session rather than changing the default, and asserts the context exists, the
drawing buffer has size, and MapLibre's own readiness signal fired. A canvas is
not proof, and neither is a green run over a browser that never started — the
gate reports `inconclusive` rather than passing when Chrome is missing.

**Check:** `RAILS/test/webgl_surfaces_gate_test.rb` (4).

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

### 3. Production seeds are opt-in — under two different names — **closed**

**Status:** closed 2026-08-29. Its own unblock criteria were already met and
the status line had not been re-read; that is the failure this list exists to
prevent, so the entry stays with the rule it taught rather than being deleted.

The defect was that the README named one variable and the deploy path read two
others: `OPERATOR.sh` gates its seeding on `RUN_PRODUCTION_SEEDS=1`, while
`RAILS/_deploy.sh` gates its two seed steps on `SEED_ON_DEPLOY=1` and
`DEMO_SEED_ON_DEPLOY=1`. So the documented name was inert: setting it and
watching the deploy succeed produced no seeds and no complaint.

`RAILS/_deploy.sh:98` now promotes `RUN_PRODUCTION_SEEDS=1` to
`SEED_ON_DEPLOY=1`, so the documented name reaches the gate it claims to open.
The two paths still exist and that split is deliberate: OPERATOR seeds once on
first install, `_deploy.sh` seeds on each deploy that asks for it. The
criteria read "one name, **or** a documented reason the two paths seed
differently" — the alias plus that sentence is the second answer, not a partial
first one.

**Owner:** RAILS.

**Proof:** `grep -n RUN_PRODUCTION_SEEDS RAILS/_deploy.sh` reports the promotion
at line 98, immediately above the `SEED_ON_DEPLOY` gate at 101 it feeds.

The rule, which generalises past this entry: **an alias is a fix only where the
documented name is the one that gets promoted.** Aliasing the other way — making
the internal name accept the documented one's value — leaves the README
describing a variable nothing reads, with the check still green.

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

#### `two_rules_share_one_rescue_regex`  — tag: agent-ignore

<!-- open-debt -->

BARE_RESCUE in the line scope of data/rules.yml and FAIL_VISIBLY in the unit scope carry the identical detect_lexical, the identical severity (error) and the same fix advice in different words, so every bare rescue in this tree is two findings. Both were edited in step on 2026-08-12 when the regex was corrected for symbols and comments, which is the maintenance cost the duplication buys. Not collapsed on my own judgement: FAIL_VISIBLY is a soul.yml `absolute.rules` entry and BARE_RESCUE is a borrowed style-guide rule, so deciding which one keeps the regex — or whether the constitutional principle should be measured by something other than a line-level regex at all — is a constitutional question and needs the operator. It is the same shape as EMPTY_RESCUE, which WAS collapsed the same day because nothing constitutional was attached to it: 37 findings, 0 unique. See "Scanner noise" in the MASTER section.

#### `bsdports_org_delegated_to_parking`  — tag: operator-priority

<!-- open-debt -->

open 2026-08-25, registrar-side. bsdports.org does not resolve: the .org registry delegates it to ns1/2/3.expireddomain.hyp.net — Domeneshop's parking servers — which publish no A record. Confirmed against b0.org.afilias-nst.org, not a cached resolver. The registration is ours and paid to 2027-08-08, and whois shows autoRenewPeriod, so the shape is: it lapsed on 2026-08-08, Domeneshop moved the nameservers to parking, the registration auto-renewed, and the nameservers were never put back. Everything downstream still believes in it — relayd holds a keypair and a Host match, a valid certificate sits at /etc/ssl/bsdports.org.fullchain.pem to Nov 10 2026, RUNBOOK.md names https://bsdports.org as the URL, OPERATOR.sh probes it, rcctl says ok and the app answers 200 on 47312. It has simply been dark. Fix is one registrar change: set the nameservers at Domeneshop to ns.hyp.net and ns.brgen.no, which is what brgen.no uses. Do it before Nov 10 or the certificate renewal fails too — acme-client needs the name to resolve here for HTTP-01. Nothing we had could have caught this: domain_watch takes its population from nsd.conf and bsdports.org is not a zone we serve, and the expiry watch reads expiry, which is paid. dns_zones now asks a public resolver whether each app domain points at 46.23.89.226, and fails on this one.
STILL OPEN 2026-08-29, and this row owns it — `WISHLIST.md` 104 names the same
registrar change and points here rather than restating it. `dns_zones` also
fails on nine domains that are past expiry, which is `WISHLIST.md` 103: money at
a registrar, not code, and not a finding to re-open under a second name here.

### Debt — resolved records and what not to chase

Cautionary and historical. `not_debt` entries are things a repeat audit
keeps re-finding that are correct by design; `closed` entries are kept for
the rule each taught. Do not reopen these as action items.

#### Not debt — correct by design

##### `rails_autofix_scars`

11 `autofix: removed box-shadow (flat UI)` markers in _shell, _shell_widgets and brgen _root. The declarations around them are live focus and hover suppression, and the markers are the documented reason shared/_focus_ring.scss exists — its header cites them by name as the evidence that a flat-UI pass stripped the box-shadow that had been the focus indicator and left `outline: none` beside it. That file restores the ring with an !important rule naming every suppressed element. Measured over CDP with CSS.forcePseudoState on all three apps: .brand, .theme-toggle and .brgen-logo-mark each compute a 2px solid ring. Deleting the markers deletes the explanation for why that !important rule is there.

##### `rails_bounded_index_actions`

2 index actions with no explicit limit, both bounded by construction — channels is one row per vertical, nearby is capped at NEARBY_LIMIT. Recorded so the next audit stops re-finding them.

#### Closed — kept for the rule it taught

##### `affiliate_fk_columns_unindexed`

Closed 2026-08-27. Empty-table indexes are cheap; the wait-for-rows trigger left FK columns unindexed the moment affiliate data arrived. brgen and amber now index affiliate_conversions.event_type_id/program_id/site_id and affiliate_vouchers.voucher_type_id (and program_id). outbound_clicks.user_id was already covered by the 2026-08-25 composite (user_id, created_at) in all three apps, including bsdports.

##### `rails_coverage_contract_is_tautological`

Not debt, and the entry says so itself: both tests now carry headers stating they are apps.yml claim-checks rather than test coverage, and name RAILS/test/coverage_ratchet_test.rb as the real number — which exists and passes (3 runs, 9 assertions, verified 2026-08-25). An external review raised this again the same day as a live defect; it is a documented decision, and re-reading the header is the whole answer. Closed so it stops being re-found.

##### `etc_drift_six_configs`

Closed 2026-08-25, the day it was opened. The drift gate found six configs differing on its first run that compared anything; all six are reconciled and the gate reports "clean (11/11 verbatim configs match live /etc)". httpd.conf was fixed by another session mid-flight. rc.conf.local drifted because live correctly had brgen_jobs in pkg_scripts and the mirror did not — a reboot would have come up without the job worker. newsyslog.conf differed ONLY by a comment header, rotation rules byte-identical, so live simply never received the documentation. All three rc.d files carried the same undeployed change, RUBY_YJIT_ENABLE=0, decided 2026-08-17 and never installed: a no-op today because Ruby 3.4 ships YJIT off, and pinned because Rails generates Dockerfiles that set it to 1 and a future Ruby may default it on. Installing them was therefore safe and changed no behaviour.

##### `gate_result_is_a_shared_kernel_filed_under_deploy`

Closed 2026-08-13 by the second of the two options the entry named: an OPENBSD/DECISIONS.md entry, "OPENBSD/lib/ Owns The Gate Kernel, On Purpose". The deploy tree owns Deploy::GateResult and the types every gate returns; RAILS, MASTER and STUDIO consume them across the boundary and add nothing. Forced rather than chosen at leisure -- gate_ledger.rb landed beside gate_result.rb the same day, so the question was being answered by accretion. A repo-level shared kernel was rejected: it would be a fourth top-level tree holding three files, to remove a dependency RAILS already has and does not suffer from, while eroding the asymmetry that does matter -- MASTER requires nothing from either tree. MASTER reaches STUDIO/gate.rb by subprocess for exactly that reason. Revisit if a fifth consumer appears: three is a convention, five is a library. Measured facts kept: 74 cross-tree requires from RAILS (gate_result 53, deploy_inventory 16, utf8 5), OPENBSD -> MASTER 3.

##### `seven_tables_recorded_as_migrated_and_absent`

Closed 2026-08-13. Ran 20260514120000_create_identity_and_trust_primitives' up against production by hand — it was recorded in schema_migrations as applied and had created nothing — after a full backup. Schema drift is 0: account_merges, external_identities, identity_assurances, identity_providers, moderation_flags, reputation_scores and trust_signals all exist, and a guest user destroys cleanly. amber and bsdports were checked for the same fault and have none. It hid a second bug that mattered more. With account_merges present, destroy still raised FOREIGN KEY constraint failed — from SQLite, not from Rails — because User declared no association for message_receipts or typing_indicators, both of which carry an FK to users. Guests owned 194,295 receipts. So account deletion was impossible for any user with chat history, which is what deletion_scheduled_at and deleted_at exist for. Fixed in User::CoreAssociations with a test that destroys a guest owning a receipt. See DECISIONS.md for the rule this taught: a table with an FK to users and no has_many on User is a row nobody can delete, and db:migrate:status cannot see a migration that ran and did nothing.

##### `playlist_engine_untested`

Closed 2026-08-12. engines/playlist has a test directory: 13 tests over Playlist::Playlist and Playlist::ListeningParty, covering what is not Rails doing Rails — add_track! ordering and idempotence, tracks_count, the city_trending tenancy scope, join-code generation and uniqueness, and the end! transition. The entry's closing ask was already satisfied: coverage_ratchet_test's source_roots has globbed engines/*/app since 2026-08-02, so the engine's zero was visible in the ratchet the whole time. What let it sit was the floor — brgen/models at 11 does not complain about one engine at nothing. Raised to 13, and the ratchet asked for it rather than being told. Writing them found a small schema fact worth keeping: playlist_playlists declares tracks_count, likes_count and plays_count as nullable integers with no default, so a new playlist has nil counters and `popular` orders by a column that starts NULL. increment! copes; anything reading before the first write does not. Asserted as-is, so a migration adding defaults shows up as a deliberate change rather than a surprise.

##### `rails_flash_strings_untranslated`

Closed 2026-08-12 at zero, measured by the instrument rather than by grep. 169 → 48 → 0. The last 48 were all in the five brgen engines, which is what this entry's own note predicted, and they went in one pass: flash.<engine>.* keys in brgen's nb and en locales, nested per engine because that is how the call sites are organised. The eleven copies of "Not allowed" and "Not authorized" became shared.flash.not_authorized rather than an eleventh translation of the same sentence, and "Try again later." became shared.flash.rate_limited. Four needed more than a key. The offers-sent line interpolated a count and called String#pluralize on an English noun, so it became a pluralized entry. The payment line interpolated a machine value into a sentence, so the five PAYMENT_STATUSES got words of their own. And in amber, state.humanize.downcase produced English in every locale by construction — that one had survived precisely because translating the sentence around it would have left the state name in English regardless. The ratchet is 0, which makes it a ban; that is what it should have been from the start, and 169 was only ever a ratchet because it could not be paid off in one pass. One test changed with it: vertical_mutations_test asserted /Sent 1/ and so passed only while the flash was hardcoded English on an nb UI — a test pinning the bug in place, and the second of those found the same day.

##### `committed_rails_master_key_public_repo`

Closed 2026-08-12, by measurement rather than by rotation: the rotation this entry asked for had already happened in /etc, and what was left was the dead half still sitting in git. The seven burned keys are confirmed (all six apps at ffb39dc12/b1882a484 2026-05-06, moved 28bad8208, emptied 4f3780d89/6f81a4d34 2026-05-29 — emptying moved the tip, not the history), and they stay burned; that is not what changed. What changed is that the keys no longer open anything. The three still-tracked credentials.yml.enc (MASTER/web, amber, bsdports) were decrypted with the historical keys: each held exactly one value, secret_key_base, and no API key or database password. The live values differ — compared as SHA256 digests, never as values: amber 9bbeac9f… in git against d14ba067… live, bsdports 6ffd8e80… against c50ceca2… Production takes SECRET_KEY_BASE from /etc/<app>.env (640 root:<app>, absent from git) and each rc.d hard-requires it, `: "${SECRET_KEY_BASE:?missing ...}"`, so the service refuses to boot without one; MASTER/web exports SECRET_KEY_BASE_DUMMY=1 and never needed a real value. So all three .enc files were deleted rather than re-keyed: nothing reads them (every Rails.application.credentials reference in the repo is inside a comment — the commented-out aws block in each storage.yml), and a re-key would have produced a new secret for a file with no reader. Amber was booted with its credentials file moved aside first, to prove the deletion was safe and not merely plausible. RAILS/test/tracked_secrets_test.rb is the gate, and it was confirmed to fail on all three files before they were removed. The optional history purge is NOT done and is deliberately not tracked here twice — it is a force-push to a public repo, cannot be relied on (forks, clones, unreachable-object retention, archivers), and if it happens it goes in one pass with home_partition_full_from_git_history.

##### `rails_no_asset_url_lint`

Closed 2026-08-12. Pub4::AssetUrlLint reads every url() in a stylesheet or an inline <style> block, resolves it against the roots that actually serve that sheet, and ratchets missing_asset at 5. Filed and closed in one pass because the first run found a live bug: amber served shared's lightgallery.css, whose icon font resolved only under brgen/public, so every lightbox control in amber was a missing glyph — verified 404 against amber.brgen.no before and 200 after. The gap existed because the 2026-08-11 asset audit checked image_tag and asset_path, the reference forms that fail loudly, and never read the one that fails silently. Pinned by RAILS/test/asset_url_lint_test.rb.

##### `rails_no_breakpoint_token`

Closed 2026-08-11. design_tokens.yml has a `viewport` scale (480/576/640/768/ 1265/1280, each with the count that justifies it) and Pub4::BreakpointLint enforces it, pinned by RAILS/test/breakpoint_lint_test.rb. It cannot be a CSS custom property — `@media (min-width: var(--x))` is invalid CSS — so the numbers stay in the stylesheets and the lint is what makes them single-sourced. The measurement corrected the entry twice. The real defect was not the 767/768-style pairs, which are a correct exclusive scheme: it was that 640, 768 and 1265 were EACH used as both a floor and a ceiling somewhere in the family, 26 sites in total, so at exactly those three widths two blocks matched and bundle order decided which won. Fixed by moving the six colliding max-bounds down one pixel, keeping the interpretation the min-width author had declared. A seventh apparent site was a comment in shared/_responsive.scss explaining why a rule is no longer wrapped in the query it quotes — the lint now strips comments, which is the convention in "Scanner conventions" it had just walked into. Also fixed: brgen/_root's compose control banded from 769px while the rest of the family treats 768 as the tablet edge, so at exactly 768px it fell through to base styling. Residue is 3 unknown edges (700px in marketplace nav, 400 and 600 in zen shell), which are design decisions rather than typos and live in the lint's baseline as a number that can only fall.

##### `brgen_allow_unauthenticated_access_is_a_noop`

All three halves closed. The no-op is deliberate — guests get a soft Current.user so the product is usable without signup, and require_real_user is the identity gate — and it is no longer silent: Shared::Authentication .allow_unauthenticated_access logs in development and test that it does nothing in a guest-column app, staying quiet in production where it would be boot noise on every controller. That fix had no gate, so an unused-logging cleanup would have removed it; RAILS/test/auth_noop_is_audible_test.rb pins it (mutation-checked: deleting the warning fails 2 assertions). Guest digests are minted at BCrypt::Engine::MIN_COST — production cost 12 measured 1,025ms on vm23's single core, on 38.9% of 275,334 logged requests — and Shared::PruneGuestUsersJob runs daily at 3:45am in brgen and amber with the (guest, created_at) index it scans on.

##### `operator_docs_module_is_unreferenced`

Wired 2026-08-11: Ground::BootstrapDocs#section routes /orient deploy to OperatorDocs.render_deploy, and StatusReport#backlog_open_count now delegates to OperatorDocs.open_debt_count instead of parsing this file a second way — the duplicate reader this entry existed to collapse.

##### `brgen_layout_query_cost_and_page_weight`

Both halves closed. Conversation.unread_counts_for is one grouped query (brgen/test/models/unread_counts_test.rb asserts it agrees with the per-record path), and shared/_icon_sprite emits each shape once as a <symbol> with shared/_icon rendering <use>.

##### `rails_missing_empty_states`

Pub4::EmptyStateLint is at BASELINE 0 and scans clean; deliberate no-CTA sites carry `<%# empty_state: no-action-ok %>`.

##### `rails_silent_wiring_breaks`

Closed 2026-08-01, gate first: stimulus_wiring (326 checks) is what stops the class returning silently. The last open tail — three Shared models broadcasting into streams with no subscriber — is closed too: Reaction, Notification and ReviewCase each carry an explicit no-broadcast decision naming what would have to exist first, pinned by RAILS/test/turbo_broadcast_contract_test.rb.

##### `doas_keepenv_is_a_root_rce`

Fixed 2026-08-02, installed and verified live on vm23 the same day. The rule it taught is DECISIONS.md, "/etc/doas.conf installs only on a deliberate root run".

##### `root_dot_sources_dev_owned_repo_every_5min`

Closed 2026-08-02: heal_doas_conf! removed from relayd-watchdog and config-drift-check, no-heal copies installed to /usr/local/bin, and staging files moved out of predictable /tmp paths in validate_doas.ksh, OPERATOR.sh's install_tracked_crontab and backup_priv.sh. Verified 2026-08-03 — nothing root-run reads or executes from /home/dev/pub4 on a timer.

##### `payment_webhooks_unverified`

HMAC-SHA256 over "<timestamp>.<raw body>", replay window SIGNATURE_TOLERANCE 5 min, multiple v1 signatures for rotation, fail closed when the secret is unset (2026-07-27, 6 tests). Vipps's header/signed-string shape still wants confirming against current MobilePay docs before production use — noted in the controller.

##### `marketplace_order_notifications_raised_under_strict_loading`

Shared::StrictSafeAssociations resolves actors by foreign key rather than a lazy belongs_to read inside after_commit, which was turning successful writes into 500s — worst case a paid Stripe order that notified neither party (2026-07-27).

##### `playlist_missing_tables`

migration 20260726120000 creates playlist_timestamped_comments and playlist_audio_versions

##### `bsdports_missing_social_tables`

Shared::Reactable declares the association only when a Reaction constant exists

##### `bsdports_missing_cable_cache_schema`

cable_schema.rb + cache_schema.rb copied from brgen; both verified to load

##### `amber_style_profile_missing`

/ai/style rewritten onto StylePreference; the table-less StyleProfile model deleted

##### `brgen_pwa_service_worker_stale`

19 sourceless entries filtered out of the precache manifest; `npm run build:pwa` remains the source of truth

##### `solid_queue_worker_proof`

vps-deploy loads queue schema via rails_prepare_secondary_dbs_as_app and runs solid_queue_proof.sh before stamp

##### `tts_host_binary`

pkg_add espeak; master rc.d PATH=/usr/local/bin; tts_proof.sh ok on vm23

##### `macos_ruby_mismatch`

contributor check profiles + MASTER/bin/ruby shim skip runtime gates cleanly

##### `frontend_auditor`

amber items.scss split + timeline BEM removed

##### `web_asset_discipline`

vps-deploy master path runs precompile + master_web_assets_gate

##### `vps_safety_gate_paths`

fixed OPENBSD/ top-level paths; gate passes on clean checkout (2026-07-16)

##### `shadow_deploy_scripts`

deleted .deploy_now.sh and .deploy_manual.sh (2026-07-16)

##### `restore_backups_misname`

split into restore_backups.sh (litestream) + extract_legacy_installers.sh (2026-07-16)

##### `vps_console_collapse`

vps_console.exp modes + thin wrapper .exp files (2026-07-16)

##### `ops_personal_scripts`

moved laptop utilities to OPENBSD/dev/ (2026-07-16)

##### `external_alerting`

OPENBSD/bin/uptime-check.sh curls /up on all apps and exits non-zero on any failure (2026-07-16). Closed as written and it did not catch the 2026-08-03 outage, because nothing schedules it — that half is amber_bsdports_stop_and_stay_down (a), not this entry.

##### `ssh_helper_dry`

OPENBSD/lib/ssh_vm23.sh; deploy_all.sh and vps_deploy_master.sh wired (2026-07-16)

##### `strict_mode_missing_in_three_cron_scripts`

closed 2026-08-22: set -eo pipefail on all three with each deliberate failure named and guarded; verified per-interpreter, installed root:wheel on vm23 (fefcf7228).

##### `secrets_in_process_argv_and_world_readable_home`

closed 2026-08-22: /home/dev is 710 dev:_pub4ci (app users traverse by group, proven both directions), .zshrc 600, the two chmod o+x sites and OPERATOR.sh updated (5889e1a8a). REOPENED and closed again 2026-08-25: that pass tightened the checkout and left the live data. /home/brgen, /home/brgen/app and .../app/storage were all 755 with production.sqlite3 at 644 brgen:brgen, so as dev — not brgen, not in group brgen — sqlite3 returned 17756 rows from the users table, which carries password_digest, otp_secret, remember_token, magic_link_token and email_verification_token. amber and bsdports the same. Readable by dev, amber, bsdports, johann, www, sshd, build, bin and operator; www and sshd are where a relayd or sshd compromise lands. Now 750 on /home/<app>/app/storage for all three, applied one app at a time with each verified serving between: dev is refused on all three, each app still reads its own DB and brgen still writes, and brgen, brgen_jobs, amber, bsdports and master all answer 200. Re-asserted from vps_ci.sh beside the /home/dev line so a later edit to sync_from_repo cannot put it back. CORRECTED 2026-08-27: /home/dev is 750, not 710. "Traverse by group, proven both directions" proved traversal, and master is the one service whose working directory is under /home/dev, where getcwd(3) names each ancestor by reading it. With --x it chdir'd and then failed Dir.pwd with EACCES inside rubygems, before Bundler loaded, so the daemon died at bundle34 writing no log of its own and ai.brgen.no answered an empty reply for two days. Group read restores it; other still gets nothing, which is the half this entry was ever about.

##### `amber_bsdports_stop_and_stay_down`

closed 2026-08-22: every sub-item done; both apps survived three full deploy chains on 2026-08-21/22 and the armed uptime-check watches every 5 minutes.

##### `rails_gates_not_wired`

closed 2026-08-22: the deploy host now sets GATE_REQUIRE_LIVE=1 for the deep tier (check-rails detects /etc/rc.d/brgen), so a closed port fails instead of reading green; dns_zones was already in check-openbsd.

##### `scanner_overlaps_two_installed_linters`

closed 2026-08-22: ABC_SIZE landed bespoke per this entry's measured conclusion (fixture-proven, calibrated 85.5-vs-85.91 against rubocop, ratchet threshold 40 -> 17); TooManyMethods' concept is NO_GOD_CLASS. Bridge stays off.

##### `rails_duplicate_vendor_css`

closed 2026-08-22: brgen's lightgallery.css deleted, PWA rebuilt, live service-worker manifest clean — and brgen/public/pwa/workbox-sw.js turned out to be a dead artifact of the hand-rolled era, deleted with it.

##### `solid_queue_worker_never_ran`

closed 2026-08-22 with the decision: brgen_jobs runs resident (four processes registered, 21 recurring tasks, ~380M measured); amber and bsdports stay on the drain because the box cannot hold three worker trees. Revert is one rcctl line. History in git (a530c1a99).

##### `gates_have_no_precision_ledger`

closed 2026-08-22: outcome ledger + fail-open landed earlier; the known-bad-fixture ask becomes doctrine in OPENBSD/DECISIONS.md — every NEW gate carries its fixture pair, existing gates get one when touched (tap_target_probe and focus_walk_probe are the exemplars).

---

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

### A conflict resolved by deleting both sides — closed 2026-08-31

`3e2f32f76` committed live merge-conflict markers into three files, and
`5378ae21a` — "Fix syntax errors in dilla engine and outboard lib" — cleared two
of them by deleting the whole conflict block. In `outboard.rb` that block
contained the `def neve_80(...)` line itself, so the method's body was left
loose in the module and the method's `end` closed `module Outboard`. dilla could
not be parsed at all after that, which took `MASTER/test/test_radio_bergen_study.rb`
with it, which took `rake test` with it: the entire MASTER suite could not load,
and `bin/pub4 gate` reported it as "suites: 2/7 green" without naming a cause.

Restored with the operator choosing the drive, because the two sides were
different rendered-sound defaults (3.2 dB against 4, and neither matched the 8
that `fc9b13651` last committed cleanly) and picking one is exactly the
judgement the standing constraint above reserves. `dilla.rb`'s conflict had
resolved coherently on its own — the deleted side defined a `drive` local the
surviving filter chain never reads — so only its orphaned comment marker needed
restoring, with the reason from the side that won. `dilla_principles.yml` still
carried its markers unresolved, and both sides of that one were header comments.

The rule: **deleting a conflict block is not resolving it.** A conflict spans
whole lines, and the line above `=======` is as often a `def` as a comment.
`ruby -c` on every file the diff touches is the check that would have caught
this in the same minute; nothing in the ladder ran it, because the ladder's own
first stage was down for a different reason the same day.

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

### `SEED_TEXT` names a seed that changes every run — closed

`lib/seed_providers.rb` derived it as `text.hash.abs % 1_000_000`, and Ruby
randomises `String#hash` per process. Three runs of the same text: 479615,
227034, 205911. So the one knob whose whole purpose is a repeatable seed never
produced one, and `apply_text_seed!` derives `SWING` and `BPM` from the same
value, so the groove and the tempo drifted with it.

`DillaSeeds.stable_seed` is a SHA-256 digest now, which is stable across
processes where `String#hash` is not, and the code says why at the definition.
The fix landed without a check, which is how it goes back: nothing about
`String#hash` looks wrong, and a wrong pin renders as a plausible take.

**Check:** `STUDIO/test/test_dilla_render_seed.rb` —
`test_seed_text_names_the_same_seed_in_every_process` reproduces the digest
from its own definition rather than from a run, and
`test_seed_text_pins_swing_and_bpm_with_it` asserts the two derived knobs land
on the same values twice. Mutation-checked: restoring `text.to_s.hash.abs %
1_000_000` fails the first.

**Re-measured 2026-08-29 and not a defect:** the unpinned fallbacks. With
nothing pinned, `render_seed` draws from the global RNG on purpose — a fresh
take is the point, and the house rule is that speakers never get a rerun.
The census over `STUDIO/dilla/**/*.rb` with tests excluded stands at 112
`Random.new(seed)` and 136 `obj.rand` against three bare `Kernel#rand`, with
`srand` never called; determinism is what a pin buys, not the default. The
earlier 62/91 was the same census before the engine folded into `dilla.rb`, so
compare the ratio and not the count.

### A load-time default read as an operator pin — closed

`test_provenance_separates_what_the_operator_pinned_from_what_the_engine_filled`
passed alone and failed in the suite, which looked like a test leaking ENV. It
was not: every ENV helper in the dilla tests restores in an `ensure`. The
engine writes eleven `COPY_MACHINE`/`LPG`/`VOICE_STACK` keys into ENV at load,
and has done since the ringtone layer defaulted on. A process that has loaded
the engine therefore carries them, and the render child inherits them, where
`USER_PINNED_ENV` — the whole environment unless `DILLA_USER_PINNED_KEYS`
narrows it — counts them as things the caller typed.

The narrowing is the mechanism dilla.rb already offers for an environment that
is not a clean shell, so the test declares its pin set the way a restart does.
Worth knowing generally: anything that loads the engine and then spawns a
render inherits the engine's own defaults as pins.

The six `sonmi451_probe_*` loops with no preset are local crate state: the slugs
appear only in gitignored `scratch/`, so that test may be measuring one machine
rather than the repo.

---

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

- **Realtime wiring.** Dead brgen / bsdports / amber Turbo broadcasts — streams
  written to with no subscriber on the other end. Wire the consumers or record
  the explicit no-broadcast decision per stream.
- **Seed realism.** 39 of 43 cities seed at coordinates `0,0`; the demo data
  reads as empty or wrong on the map. Give each city real coordinates and a
  plausible population.
- **Bringhurst typography codification.** Turn the typographic rules the design
  system already half-follows into enforced tokens and a gate, rather than
  convention.
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
- **PWA banner.** The install-prompt / add-to-home-screen affordance across the
  three Rails apps.
