# Debt Register

What is open in MASTER, plus the scanner conventions this codebase keeps
relearning. Deploy and RAILS debt is `OPENBSD/data/debt.yml`.

How a closed item leaves this file: it goes, and if it taught a rule the rule
moves to `DECISIONS.md` or to the "Scanner Conventions" section below. The
narrative of *how* something was fixed is what `git log` is for — this file was
660 lines on 2026-08-11 and most of it was fix history for work already done,
which made the open items hard to find and let four of them go stale unnoticed.

## Tag Legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise, horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## Spine Ceiling

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

### Three raises, no ratchet, in one day — 2026-08-14

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

## Self-Test Debt

**agent-ignore** — triage only when the task explicitly targets scan rules.

`rake selftest` reports **0 findings, re-measured 2026-08-13** and unchanged from
the 0 recorded 2026-08-12, after the three the fold-spine merge exposed were
closed — see "The fold spine had never been scanned" below. Unlike the 0 of
2026-08-11, both are measured over a tree that includes the fold. Treat any count here as
true for the commit that carries it and no further: it has been 0, 1, 2, 3, 6 and
7 on different days of the same fortnight, and a "clean since" claim in
`START_HERE.md` was already stale once.

`test/test_heartbeat.rb:44` (`self_test_heartbeat_publishes_clean_scan_metrics`)
fails *because* this count is non-zero — a symptom of this track, not an
independent defect.

Triage each new finding as: true violation to fix / scanner false positive / rule
exemption needed / rule threshold too strict / known debt to leave alone.

## The fold spine had never been scanned — opened 2026-08-12

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

## Constitution Scan Debt

**agent-ignore** — `rake constitution` is broader than `rake selftest` and still
reports thousands of self-scan findings. Do not chase zero. Track the count down
by removing false positives and fixing high-signal violations.

### Two copies found by reading the buckets — 2026-08-12

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

## The post-execution review pass runs on no turn — opened 2026-08-15

**operator-priority** — a design decision, not noise.

`Stages::Review` is constructed nowhere in `lib/`, `bin/` or `web/`. It is the
stage that runs Council feedback, then Lint on written paths, then Prune, and it
builds `Lint` and `Prune` in its own initializer, so all three go dark with it.
`Stages::Deliberate` and `Stages::Guard` are likewise never constructed;
`Stages::Enhance` runs only from `web/app/controllers/chat_controller.rb`, off
the turn path. `TurnRouter` assembles Intake → Infer → Route → DestructiveReview
→ Execute → Render, and nothing else.

`/review on` still answers "review: enabled in pipeline". It sets
`council_stage.enable!`, a flag on an object no pipeline reads.

Two consequences worth separating. The first is closed: `RuntimeMode::PIPELINE_STAGES`
advertised the ten-stage sequence through `Ground::BootstrapDocs::AGENTS`, which
is the orientation every coding agent boots on, and `test_runtime_mode.rb`
asserted the string contained `"Deliberate"` — so correcting it would have failed
the test that existed to protect it (Scanner Conventions #5, in this file, in
the file's own subject matter). The string now names the live sequence and the
test reads `turn_router.rb` instead of a literal.

Two of the orphans are gone. `Stages::Deliberate` wrapped a coding message with
"list four approaches first", which the Fold now enforces constitutionally
through `Proof#ideation_satisfied?` — the same rule, at the gate instead of in
the prompt. `Stages::Guard` scanned incoming messages for prompt injection;
`Ground::ToolContract` and `Builder::AiBoot` still scan through
`Review::Security::InjectionGuard`, so the capability did not go with it, only
the copy that ran on nothing. Both deletions paid for `WriteGuard` (`spine.yml`,
2026-08-15).

What is open is `Stages::Review` and the three it owns — Council, Lint, Prune.
`WriteGuard` has taken Lint's job and gone further, since it runs on every write
rather than at the end of a turn. Council and Prune have no such replacement:
Prune is the Strunk pass over output, which currently reaches speech and the
chat reply but not the command lane, and Council is deliberation, which the Fold
reaches directly through `council_for_done_rule`. Wiring `Stages::Review` into
`run_command_pipeline` is four lines and puts both on every command, at a cost
per turn nobody has chosen. Deleting them is the other honest answer. The
present state — capability toggleable through `/review on`, reporting itself
enabled, running never — is the one that is not defensible.

## Scanner noise

`rake selfcheck` is **20 violations across 3 rules** (re-measured 2026-08-15):
`SILENT_RESCUE` 13, `guard_expensive_ops` 5, `UNBOUNDED_RETRY` 2.

The 13 is not the 11 of 2026-08-13 plus the exemption lifted below. Measured both
ways on one tree: the same 13 sites outside `lib/review/scan/rules/` are reported
by the old predicate and the new one, so the two that arrived since are drift in
`lib/`, and every finding the exemption had been hiding is fixed rather than
counted.

### The rescue rules exempted the scanner from itself — closed 2026-08-15

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

### The veto patterns had never been read — audited 2026-08-12

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

## Inert law and config

The dominant defect class in this tree: a declaration with no reader. Both named
instances are closed and both closures are worth copying rather than the fixes
themselves.

- `data/limits.yml` — **closed.** 29 of 38 keys had no reader and the generic
  accessors made them look reachable. The file is now split into enforced keys and
  a `guidance:` block, with `test/test_limits_split.rb` failing in both
  directions: an enforced key that loses its reader, and a guidance key that grows
  one. `/orient limits` still serves the file whole, so the split relabels rather
  than hides.
- `data/security/defaults.yml` — **closed** the same way, by
  `test/test_security_defaults.rb`. Its worst case was worse than inert: the
  ingress rate limit was *also* hardcoded in `IngressController`, so file and code
  could disagree in silence.

What is open is the class, not an instance. When you find one: find the reader
before trusting a config key, and **add the gate, not just the fix** — a
two-direction test is what stops the two halves blurring back together.

### A general "every data key has a reader" gate does not work here — tried 2026-08-12

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
`limits.yml` and `security/defaults.yml` were each closed. A repo-wide gate would
need a baseline carrying a written reason for all 49, which is a decision about
49 sections rather than a mechanical step.

## Top-level ROOT

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

`test_dilla.rb` is the other half of this and is worth moving regardless: a test
in MASTER that loads STUDIO's entry point breaks whenever STUDIO refactors, which
it did (`engine_source` undefined, 2026-08-12). It should read `ENGINE_SOURCES`
or live in STUDIO.

## Test coverage

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

## Web Face Verification

**operator-priority.** Voice Mode and boot contracts are covered by
`web/test/face_boot.test.mjs` (static assertions on `face.runtime.js`), and the
WebGL primer guard has the same pattern. **Manual iOS Safari tap-testing remains
operator work when boot assets change materially** — nothing in CI drives a real
touch event.

## Host TTS Binaries

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

## Live gotchas

Two facts with no home of their own, kept because both were expensive to find.

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
  and broke `bin/pub4` for six days: the grep matched only `*.rb`/`*.yml`/`*.md`
  and `bin/pub4` has no extension, and it ran from `MASTER/`, where `bin/` does not
  mean the repo-root `bin/` that holds the caller. Pinned by
  `test/test_entrypoint_requires.rb`, which checks requires rather than constants —
  a constant sweep can be fooled by an extension filter; a missing file cannot.

## Scanner Conventions

Six shapes of one defect: **each converts the absence of a property into
evidence of it.** A gate, a test or a reader accepts something that merely looks
like the thing it was checking for, and the result is a defect that arrives
carrying its own certificate of compliance. All five were found in the same week
of 2026-08, in different subsystems, by different sessions.

### 1. A comment outlives the rule it explains

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

### 2. An exemption outlives its subject

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

### 3. A build artifact outlives the source it was built from

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

### 4. A staleness alarm silenced by regenerating the artifact

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

### 5. A test that punishes the improvement it exists to detect

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

### 6. A writer that reports an edit it did not make

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

### What follows from all six

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

## Not Debt

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
