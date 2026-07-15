# TODO

Single consolidated backlog, written for handoff to other AI agents working
in this repo. Everything mechanical/safety-critical from `rake selftest` and
the first slice of `rake constitution` is done (see "Completed" below) — what
remains is slower, one-judgment-call-at-a-time work.

**Read `DEBT.md` first.** It has the standing triage categories (true
violation / false positive / rule exemption / threshold too strict / known
debt) and the "do not chase constitution to zero" policy that governs
everything below.

**Read `MASTER/web/CLAUDE.md` before touching face-boot files** (`face.part*.txt`,
`face.js`, `face_*.js`). That path has a documented history of "tap does
nothing" regressions.

## Shared-worktree hazard (read this before your first commit)

Multiple agents commit to this **same physical working tree** concurrently.
`git add <specific files> && git commit` still commits the **whole index**,
not just what you added — if another agent staged their own files in the
gap between your `add` and your `commit`, they ride along into your commit.

Before every commit:
```
git status -sb -- <your files>   # confirm nothing unexpected is staged
```
If `git diff --cached --name-only | wc -l` doesn't match the file count you
expect, do **not** commit. Recover with:
```
git reset HEAD -- .              # unstage everything, working tree untouched
git add <your files again>       # re-stage precisely
```
`git reset` (no `--hard`) never touches the working tree — it's always safe.
Re-fetch and check `git log --oneline -5` before pushing too; another
agent's commit may have landed since you last fetched.

## Completed this session (for context — don't redo)

- `rake selftest`: 618 → **0** findings (DENSITY, ABSTRACTION god-classes,
  JS silent-catch, everything). Many commits, see `git log --oneline` for
  the full trail.
- `rake constitution` actionable findings: 1401 → **988**. Commits:
  - `50c79095a` — SQL_INJECTION/UNBOUNDED_RETRY/KERNEL_COERCION/SAFE_NAVIGATION
    (also tightened 2 rules that were false-positiving on coincidental
    text matches — see commit body for the exact regex bugs)
  - `5cca1fb01` — SILENT_RESCUE (88): bind exception + log before discarding
  - `f5eea93dd` — NARROW_SILENT_RESCUE (32), same pattern
  - `d299cbea6` — fixup for a bug the above autofix script had on a
    semicolon-form one-liner rescue (only 1 file affected, already fixed)
  - `78b3c1359` — tightened EMPTY_RESCUE to check rescue-body content
    (was purely syntax-based, over-firing on fine fallback returns) — 79 → 0
  - `5eeaadfd6` — tightened HASH_FETCH (was matching the string-or-symbol
    dual-key idiom and `||=` memoization, neither a fetch candidate) and
    fixed the 32 genuine findings that remained — 99 → 0

**Pattern used throughout**: before mass-editing a rule's findings, sample
several instances first. Several of these rules were firing on shapes their
own suggested autofix doesn't actually apply to (a false positive at scale,
not 88 individual violations) — tightening the rule was the right fix, not
88 individual edits. Keep doing this rather than blindly automating a
rule's literal suggestion.

**Autofix script gotcha** (cost real time this session, twice): if you write
a Prism-AST-based script to bulk-edit rescue clauses or similar, Prism
`Location` offsets are **byte offsets**. Ruby's `String#[]` is
**character-indexed**. This codebase's comments are full of multi-byte
UTF-8 (em-dashes, arrows, curly quotes) — any file with one of those before
your edit point will silently corrupt the splice. Use `source.b`
(byteslice) throughout, re-tag `"UTF-8"` only after all edits land. Verify
with `ruby -c` on every touched file before staging, and also grep for
duplicate/broken rescue clauses if you touch rescue bodies specifically —
`ruby -c` doesn't catch a rescue clause that's syntactically valid but
semantically broken (e.g. two consecutive `rescue SameClass` clauses,
where the first — possibly referencing an unbound `e` — always wins and
the second is dead code).

## Remaining `rake constitution` true-violation findings (988)

Regenerate the live list any time — counts above will have drifted:
```ruby
# from MASTER/, ruby -Ilib -e '...'
require "master"; require "judge/scan/constitution_triage"
root = Dir.pwd
scanner = Master::Judge::Scan::InfraHelpers.build_scanner(root:)
scanner.rules.reject! { |r| r.id.to_s == "ast_omission" }
paths = Dir.glob(File.join(root, "lib", Master::Judge::Scan::Scanner::SCAN_GLOB))
            .select { |p| File.file?(p) && !Master::Judge::Scan::Scanner.skip_path?(p, root:) }
violations = paths.flat_map { |p| r = scanner.scan(p, depth: :deep); r.ok? ? r.value!.map { |f| f.merge(file: p) } : [] }
tv = Master::Judge::Scan::ConstitutionTriage.new(root:).buckets(violations).find { |b| b.name == :true_violation }
tv.findings.select { |v| v[:rule].to_s == "RULE_NAME_HERE" }.each { |v| puts "#{v[:file]}:#{v[:line]}" }
```

### Group A — method-signature smells (heavily overlapping, fix together)

| Rule | Count | Threshold |
|---|---|---|
| KEYWORD_ARGS | 126 | 3+ positional params → use keywords |
| FEW_ARGUMENTS | 124 | 3+ positional params → ideal is 0–2 |
| LONG_PARAMETER_LIST | 113 | >4 total params (any kind) |

These three rules mostly fire on the **same methods** — KEYWORD_ARGS and
FEW_ARGUMENTS both trigger at 3+ positional args, so fixing one method's
signature typically clears 2–3 findings at once. **The real cost isn't the
`def` line, it's every call site.** Converting `def foo(a, b, c)` to
`def foo(a:, b:, c:)` breaks every positional caller — grep for the method
name across the whole repo (not just `lib/`) before touching a signature,
including `RAILS/` and `OPENBSD/` if the method is used cross-app. Do these
one method at a time, verify with the method's own test file if one exists
(convention in this repo: `test/test_<basename>.rb`), and run
`bundle exec rake test` after each.

### Group B — coupling / SRP smells (architecture judgment, one at a time)

| Rule | Count | What it means |
|---|---|---|
| FEATURE_ENVY | 134 | method calls one collaborator's methods ≥4 times, more than its own `@ivar`/`self.` — move the method to that collaborator |
| PATTERN_EXTRACTION | 95 | code shape close to a named design pattern — see `structural_rules/convention_rules.rb:127` for what it's matching |
| LAZY_CLASS | 27 | class only delegates, owns no behavior of its own |
| LAW_OF_DEMETER | 2 | message chains ≥4 deep (`a.b.c.d.e`) |
| CQS | 16 | a method both mutates state and returns a query result — split into a command + a query |

No mechanical fix here. Read the flagged method, decide whether the
coupling is real (move the code) or the rule mismeasured (e.g. a DSL/config
builder that's *supposed* to talk to one object a lot) — the latter is a
"rule exemption needed" per `DEBT.md`'s triage, not a violation to fix.

### Group C — style/readability (mechanical, lower risk, good starter batch)

| Rule | Count |
|---|---|
| RUBY_TERNARY_NOT_NESTED | 103 |
| FINAL_NEWLINE | 23 |
| TRAILING_COMMENT | 12 |
| RUBY_NUMERIC_UNDERSCORE | 4 |
| RUBY_SYMBOL_TO_PROC | 3 |
| TYPOGRAPHIC_EXCELLENCE | 2 |
| RESCUE_ON_DEF | 2 |
| PERCENT_LITERAL | 1 |
| CONSECUTIVE_BLANK_LINES | 1 |
| SINGLE_PRIVATE_SECTION | 1 |
| TRANSFORM_KEYS | 1 |
| SMALL_FUNCTIONS | 1 |

RUBY_TERNARY_NOT_NESTED (`a ? b ? c : d : e`) is the only sizeable one and
needs per-instance rewriting to if/elsif/else or case — the nesting shape
differs enough that a single mechanical transform risks getting the
condition order wrong. The rest are small counts, safe to knock out fast.

### Group D — prose / doc wording (rewrite comments, preserve meaning)

| Rule | Count |
|---|---|
| prose_active_voice | 53 |
| future_tense | 44 |
| prose_omit_qualifiers | 21 |
| sycophancy | 3 |
| NO_MULTIPLE_LANGUAGES | 1 |

These flag comment/doc text, not code behavior — zero execution risk, but
requires actually reading each comment to reword it without losing the
"why" it was recording. Good task to parallelize across files.

### Group E — mixed leftovers (individual review)

| Rule | Count |
|---|---|
| SIMULATION | 15 |
| CYCLOMATIC_COMPLEXITY | 13 |
| COMPLETION_THEATER | 11 |
| PARAMETERIZED_SLUG | 9 |
| duplicate_code | 6 |
| guard_expensive_ops | 5 |
| SMALL_FILES | 4 |
| MAGIC_COLOR | 4 |
| DEBUG_OUTPUT | 3 |
| EXPLICIT | 3 |

### Known false positives — do not chase

- `bare_rescue` (1) / `fail_visibly` (1), both at `lib/judge/scan/ast_fixer.rb:116`:
  an LLM-based semantic rule misfired on `@transforms << :bare_rescue` — a
  symbol literal named after what the surrounding code *fixes*, not an
  actual bare rescue clause. Investigated and confirmed benign; not worth
  chasing a one-off LLM word-association error.

## `rule_retune` bucket (3653) — tune thresholds, don't mass-edit code

Per `DEBT.md`: these rule IDs are already flagged as needing threshold/rule
changes, not 3653 individual code fixes. Top offenders if you want to work
on tuning: `magic_number` (854), `DEAD_CODE` (592), `debug_output` (285),
`long_line`/`LONG_LINE` (453 combined), `TRAILING_COMMAS` (216),
`FILE_LAYOUT` (211), `veto_patterns` (193), `MEANINGFUL_NAMES` (187),
`NO_ABBREVIATED_IDENTIFIERS` (169), `DOUBLE_QUOTES_RUBY` (168),
`message_chain` (168), `NO_COLUMN_ALIGN` (129), `COUPLER_SMELLS` (28).
Full list in `lib/judge/scan/constitution_triage.rb`'s `RULE_RETUNE_IDS`.

## `scanner_self_reference` bucket (399) — lowest priority

Findings inside `lib/judge/scan/rules/` itself (the scanner scanning its
own implementation). Self-referential noise; only worth touching if a
specific finding there is genuinely embarrassing (e.g. a real DEAD_CODE
match in the scanner's own code).

---

# Beyond the scanner: architecture, coverage, and polish gaps

Everything below this line was found by manually reading the codebase
(2026-07-15 audit), not by `rake selftest`/`rake constitution`. It does not
overlap the buckets above — do not re-run the scanner looking for these.

## `core/` vs `kernel/` vs `lib/`

- **`kernel/` is dead weight, not a blocker on the absorption plan.** Its
  entire contents are one file, `kernel/spec/kernel_smoke.rb` (7 lines), a
  literal placeholder ("intentionally does nothing and exits 0"). The only
  reference to the directory anywhere is `bin/probe:97`, which shells out to
  that placeholder as the `"kernel"` step of `bin/probe all`. Every other
  hit for "kernel" in the tree (`lib/ground/rules.rb`,
  `lib/ground/law_resolver.rb`, `lib/voice/personality_prompt_builder.rb`,
  `lib/judge/scan/self_test.rb`, `lib/judge/scan/rule_registry_audit.rb`,
  `bin/audit`) means the unrelated "kernel-tier rule" concept, not this
  directory. **Delete `kernel/` and its one-line reference in `bin/probe`.**
  There is nothing left to fold into `core/` — the memory note about a
  kernel-fold rebuild plan is already moot.
- `core/ABSORPTION.md`'s own line-count header is stale by ~100 lines
  (claims 662, actual sum across `constitution.rb`/`world.rb`/`memory.rb`/
  `model.rb`/`master.rb`/`core.rb` is 764) — one-line fix in the doc header.
- `core/spec/core_smoke.rb` (89 lines, a real integration smoke test —
  Effect admission, secret redaction, evidence-gated `done`) is **not**
  wired into `Rakefile`, `bin/probe`, or `bin/ci`. It only runs if someone
  manually invokes it per its own header comment. Add a rake task or a
  `bin/probe` step for it — distinct from `test/core/test_*.rb` (13 files),
  which already runs via `rake test:core`.

## CI is currently not running at all — fix before trusting any of this

- `.github/workflows/master-tests.yml` has its `push`/`pull_request`
  triggers commented out (billing lock note in the file itself); only
  `workflow_dispatch` remains. **Nothing runs automatically on push right
  now.** Restore the triggers once billing is fixed — this is the single
  highest-priority item in this whole document, everything else assumes CI
  exists.
- Separately, once restored: `bin/ci` (what the workflow calls) runs
  `rake test`, `rake test:core`, `rake selftest`, `rake lint:data_singularity`,
  conditionally `rake constitution`, `rake test:web`, `rake test:integration_web`
  — but **never `rake spec`**. `rake spec` exists and *is* wired into
  `bin/check`'s default/contributor profiles, so local `bin/check` runs are
  more thorough than what CI would run. Either add `rake spec` to `bin/ci`,
  or reconcile `bin/ci` with the comment inside the workflow file itself
  that says local parity is `bin/check --profile=full` (the actual `run:`
  step doesn't match its own comment).

## Test/spec coverage gaps (not caught by the scanner — it checks style, not coverage)

`test/` = 165 Minitest files, `spec/` = 24 RSpec files. Cross-referencing
`lib/**/*.rb` (424 files) against both by filename found concrete,
high-value gaps (verified by class name, not just filename):

- **`lib/reach/{read_file,write_file,str_replace,shell,tree,list_dir,search_files}.rb`**
  — the ~15 primitives `core/ABSORPTION.md` calls load-bearing for the
  World absorption — have no behavioral test. The only related file,
  `test/test_reach_tool_coverage.rb` (20 lines), only asserts every
  `Master::Reach` class has a `TIER` constant; it never calls `.call` on
  any of them. Given these are slated to become permanent `core/world.rb`
  handlers, this is worth closing before that migration, not after.
- **`lib/judge/scan/rules/{external_linter_rules,graph_rules,js_rules,lexical_rules,meta_rules,naming_rules,ruby_rules,semantic_rules,structural_rules,universal_rules,web_rules,structural_rules/convention_rules}.rb`**
  (12 files — the actual constitution-rule definitions) have zero direct
  unit tests exercising rule behavior against fixture input; they're only
  exercised transitively by `rake constitution` scanning MASTER's own
  source.
- **`lib/master_runtime.rb` (135 lines), `lib/master_boot.rb` (60),
  `lib/master_paths.rb` (17), `lib/master_data.rb` (70),
  `lib/pressure_engine.rb` (140)** — top-level `lib/*.rb` siblings of
  `lib/master.rb` with zero references anywhere in `test/` or `spec/`.
- `lib/judge/swarm/` (coordinator, vote_engine, worker, 4 worker roles) and
  `lib/judge/council/{ideation,selector,quality_framework,deliberation_prompt_builder,deliberation_synthesis}.rb`
  have no dedicated test files (verify whether `test_council_deliberation.rb`/
  `test_swarm.rb` cover them indirectly before assuming a full gap).
- `lib/now/command_registry/*.rb` (10 files) — no per-file tests; only
  generic dispatcher-level coverage via `test/test_script_dispatch.rb`.

**Two parallel test frameworks (Minitest in `test/`, RSpec in `spec/`) is
itself worth a decision** — see "Aggressive restructuring" below.

## `web/` (MASTER/web, the Rails-based face app) — corrections + real findings

Correcting a wrong premise before it spreads: **MASTER/web does not use
Stimulus, CableReady, StimulusReflex, or `design_tokens.yml`/the "IRIX flat
dark theme."** Those belong to `RAILS/shared/`, a different app family.
MASTER/web ships hand-written vanilla JS (compiled from `face.part1-5.txt`
into `face.runtime.js` — edit the parts, not the output, per
`web/CLAUDE.md`) and its own `face.css`/`photo_upload.css`. No
TODO/FIXME/HACK/stub markers exist anywhere in `web/app/**` — clean.

Real findings:

- **`app/views/layouts/application.html.erb` (76 lines) is dead code.**
  Every controller renders JSON or explicitly `render layout: false`
  (confirmed for `chat#index`, `dashboard#index`, `pwa#manifest`) — no route
  lets the default layout apply. It duplicates a near-copy of
  `chat/index.html.erb`'s boot shell (`#primer`, `#chat-shell`,
  `#chat-log`, `#zsh`/`#zin`) with **drifted details that would collide if
  it were ever re-enabled**: `#primer` is `role="dialog" aria-modal="true"`
  in the layout vs `role="button"` in chat/index; `#zin` is an `<input>` in
  the layout vs a `<textarea rows="1">` in chat/index. Delete the layout
  file, or document explicitly why an unused Rails-convention default is
  being kept.
- **`app/views/dashboard/index.html.erb`** doesn't reuse `face.css` — it
  has its own inline `<style>` block (lines 8-16) with hardcoded colors
  (`#000`) duplicating patterns `face.css` already has, and **zero
  `aria-*` attributes** (vs. 26 in chat/index, 10 in the layout). Since it
  polls `/dashboard/live` and rewrites `<pre>` panels every tick, those
  panels (`#status`, `#rtk`, `#plan`) want `aria-live="polite"` the same way
  `#chat-log`/`#tts-live` already have it elsewhere.
- **`public/photo_upload.css` exists with no `photo_upload.js`
  counterpart** — the actual upload logic lives inline in `chat.js`
  (`chat.js:524,563`). Either rename the CSS file to match where its logic
  actually lives, or split the JS out to match the CSS's implied pairing.

## `bin/` discoverability

30 executables in `bin/`, but **26 of 30 aren't mentioned in any top-level
doc** (README/AGENTS/START_HERE/DEBT/DECISIONS/REPAIR_PLAYBOOKS/GITHUB_WATCH)
— most are self-documented via their own header comment, so this is a
"can't discover from the top" gap, not an undocumented-behavior gap. Only
`nsaudit` and `probe` are referenced in REPAIR_PLAYBOOKS.md/DECISIONS.md.
Low-effort fix: one table in README.md or a new `bin/README.md` listing all
30 with a one-line purpose each (most can be lifted straight from the
scripts' own header comments).

`bin/tts_e2e` uses an underscore while its siblings `tts-bootstrap`,
`tts-speak`, `tts-worker` use hyphens — rename to `tts-e2e` for consistency
(update any callers first).

## `data/` folder

Current count: 55 files across 10 subdirs + top level. This is a real
**decrease** from the 78-file count in memory — the defrag has progressed,
not stalled; worth noting so nobody re-starts work already done.

**Naming-collision + likely-orphan finding:** `data/personas.yml`
(top-level — TTS/LLM voice-character presets: malay, british, norwegian,
ronin, lawyer, hacker, architect, sysadmin, trader, medic, anchor) and
`data/personas/` (subdir — `brutalist.yml`, `rachel.yml`) share a name but
are structurally unrelated: the subdir files are deploy/runtime profile
configs (`voice.enabled`, `face.enabled`, `web.port`), not voice presets.
**Grepping all of `lib/` and `web/` for any reference to the `data/personas/`
directory or to `brutalist`/`rachel` as deploy profiles returns nothing** —
these two files look orphaned, possibly leftover from an unbuilt
multi-persona-deploy feature. Either wire them into a real loader or delete
them; rename the subdir regardless (see restructuring section).

## Missing architectural files

- No `CHANGELOG` anywhere in the tree (zero hits, vendor excluded). Given
  `DECISIONS.md`/`DEBT.md` already carry dated entries, this might be
  intentionally redundant — make it a conscious call either way.
- Only 1 of 16 `lib/` subsystems (`lib/loop/README.md`) has a
  subsystem-level README/AGENTS.md. `ground/` (93 files, 7420 lines) and
  `judge/` (82 files, 10851 lines) and `now/` (76 files, 8056 lines) are the
  largest and most complex — they'd benefit most, using `loop/README.md` as
  the template.
- `lib/providers/catalog_index.rb` implements a real, working extension
  point (a frozen `SOURCES` hash: `openrouter`, `replicate`,
  `replicate_github`, each with `url`/`kind`/`normalizer`) with **no doc
  anywhere** explaining "add a provider source here, add a normalizer
  method there." Since `core/ABSORPTION.md` marks `providers/`+`grok/` as
  done/stable, this is likely the final shape of that subsystem and worth
  documenting once.

## Aggressive restructuring (renaming, flattening, decoupling, merging)

- **Delete `kernel/` outright.** One placeholder file, one dangling
  `bin/probe` reference. Zero risk, immediate flattening win — removes an
  entire top-level directory that no longer does anything.
- **Pick one test framework.** Maintaining Minitest (`test/`, 165 files)
  and RSpec (`spec/`, 24 files) side by side means two DSLs, two runners,
  two sets of test-helper conventions to keep in sync — a DRY violation at
  the tooling level, not just the code level. `spec/` is the smaller tree;
  migrating its 24 files into `test/`'s Minitest convention and dropping
  the RSpec dependency is the lower-effort direction, but either direction
  collapses two parallel systems into one. Do this before adding `rake
  spec` to CI (above) — no sense wiring a second framework more tightly
  into CI right before deciding to retire it.
- **Resolve the `data/personas.yml` vs `data/personas/` collision.** Rename
  the subdir to `data/deploy_profiles/` (its actual contents) regardless of
  whether it turns out to be live or orphaned — the name collision with
  the unrelated voice-persona file is a landmine for the next person who
  greps "personas" and gets both. If nothing loads it, delete it instead of
  renaming.
- **Merge `lib/master_runtime.rb`, `lib/master_boot.rb`,
  `lib/master_paths.rb`, `lib/master_data.rb`** — four small top-level
  files (17-140 lines) with overlapping "how MASTER starts up and where
  its stuff lives" responsibility and zero test coverage between them.
  Read them together before deciding, but this shape (several small
  `master_*.rb` files sitting as siblings of `lib/master.rb` rather than
  organized under a `lib/master/` subdirectory the way every other
  subsystem is) is itself an inconsistency worth flattening one way or the
  other: either fold them into one `lib/master_runtime.rb`, or move all
  four under `lib/boot/` alongside a README, matching the rest of `lib/`'s
  one-subsystem-per-directory convention.
- **Delete the unused `application.html.erb` layout** in MASTER/web rather
  than fixing its drifted duplicate markup — it has no live route, so
  fixing the duplication is wasted effort compared to just removing the
  dead file. If a default layout is required by Rails convention, replace
  it with an intentionally minimal one, not a second copy of the chat boot
  shell.
- **Extract `dashboard/index.html.erb`'s inline `<style>` block into
  `face.css`.** One shared stylesheet for the whole face app, not one
  `face.css` plus a per-view inline block — the dashboard is the only view
  that deviates from this.
- **Rename `bin/tts_e2e` → `bin/tts-e2e`** for filename consistency with
  its three siblings — small, mechanical, no behavior change.
- ~~`tools/dilla/`'s checked-in dotfile artifacts~~ **Done 2026-07-15**:
  all Dilla scratch/caches now live in `tools/dilla/.cache/`
  (`SCRATCH_DIR`, overridable via `DILLA_SCRATCH_DIR`), legacy dotfile
  progression logs auto-migrate in, and `.gitignore` covers both the new
  dir and pre-`.cache` strays. See `tools/dilla/README.md`.
- **Write a `lib/providers/README.md`** documenting the `SOURCES` hash
  extension pattern — cheap, high-leverage, and matches what `loop/`
  already does for its own subsystem.
