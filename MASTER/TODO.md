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
