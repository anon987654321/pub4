# Decisions

Agent and runtime policy. Deploy and VPS policy lives in `OPENBSD/DECISIONS.md`.

This file records intentional shapes that may otherwise look like bugs.

## Portfolio Freeze Aligns With OPENBSD (2026-07)

See `OPENBSD/DECISIONS.md` — **No Fourth Public App Until brgen Boundaries Hold**. MASTER work should prefer subtraction (one generated agent context, structural vs cosmetic scan severity) over new portfolio apps. Do not invent a seventh product surface from agent sessions without that ADR being revisited.

## One Spine, With The Dependency Rule Kept (2026-08-12)

**This reverses "Two Master Spines", which stood from 2026-07-30 to 2026-08-12 and is superseded by operator instruction.** The prior text is below the line, because a decision that was reversed is more useful than a decision that was quietly deleted.

`core/` is now `lib/core.rb` + `lib/core/`, autoloaded by the same Zeitwerk loader as the rest of `lib/`. The path-to-constant mapping already wanted exactly this: `push_dir(lib, namespace: Master)` makes `lib/core.rb` → `Master::Core` and `lib/core/fold.rb` → `Master::Core::Fold`. The merge needed no new entries in `data/autoload.yml` — `rake lint:autoload` still reports 44 ignores, all necessary.

Two things the old split was carrying, and where each went:

- **The dependency direction survives, as a test.** The fold must not reach into the application spine. That was enforced by a directory boundary and is now enforced by `test/core/test_no_lib_backedges.rb`, which names the fold's files explicitly and fails if any of them requires a sibling under `lib/`. It also asserts it found the files at all, since a glob that matches nothing passes silently.
- **`core_files: 6` survives, counted differently.** `lib/{core.rb,core/*.rb}` — five in the directory plus the entrypoint beside it. Globbing only `lib/core/` would have read 5 against a ceiling of 6 and handed out a free concept.

What the merge removed, beyond a directory: `bin/master-core` put `core/` on `$LOAD_PATH` and called `require "master"`, so which of the two `master.rb` files won was decided by load-path order. `bin/nsaudit` had to hand-require the second spine so the first one's constants would resolve. Both are gone.

`lib_code_ceiling` was rebaselined 38285 → 38811 and **not** recorded as a raise: 554 code lines moved in, `lib/` reports +526, so excluding the moved files `lib/` fell 28. The arithmetic is in `data/spine.yml` so the claim is checkable rather than asserted.

---

*Superseded 2026-08-12 — retained for the reasoning, not as current policy:*

> `lib/` and `core/` are intentionally separate load paths. `lib/` is the gem, CLI, loop, judge, reach, trace, voice, and web-facing runtime. `core/` is a small isolated constitutional fold loaded on its own path by the core tests and `bin/master-core`.
>
> Core types live under `Master::Core::` (not top-level `Master::`) so they coexist with lib constants in one process — the runtime cutover loads `core/` into the CLI via the bridge. `bin/nsaudit` loads the core entrypoint explicitly; the two-spine design is deliberate, not accidental duplication. (The module was named `Master::Kernel` until it was renamed to `Master::Core` to stop shadowing Ruby's built-in `::Kernel`.)
>
> Namespace tooling should treat `bin/master-core` as the core load entrypoint.

## The Spine Ratchet Replaces An Unmeasured Invariant

`core/ABSORPTION.md` (now `docs/SEVERANCE.md`) asserted "the spine never grows" and nothing checked it.
In the three weeks after `core/` landed, `lib/` gained 8,022 lines and `core/`
gained none. That file is now `docs/SEVERANCE.md`, a record of what was cut
rather than a plan, and this document is the standing policy on the spine.

What is enforced instead: `rake lint:spine` reads `data/spine.yml` and fails
when `lib/` grows past its recorded ceiling or the fold spine gains a file.
The ceiling only ratchets down (`RATCHET=1` records a new low); raising it is a
deliberate edit with a reason in the commit. Part of `rake audit`.

### The invariant, settled 2026-08-11

The ceiling has now been raised three times (2026-07-31, 2026-08-01, 2026-08-11)
and its unit changed once. `data/spine.yml`'s own note said that if it were raised
again without `lib/` ever falling back, "the honest conclusion is that 'the spine
never grows' is not the invariant anyone is holding". `lib/` did fall back twice,
by deletion — and on the third raise there was nothing dead left to pay with: a
sweep of all 445 files returned one candidate and it was a false positive.

So the sentence is retired and replaced by the two things that are actually true:

- **`core_files: 6` is the invariant.** A new top-level concept in the fold is a
  design change and must be argued for. This has never been raised and should not
  be. It is what "the spine" means.
- **`lib_code_ceiling` is a budget with a sponsor, not a promise.** It exists so
  growth is visible and has to be asked for. A raise needs a named sponsor and the
  per-commit accounting in `spine.yml`; `consecutive_raises_allowed: 2` refuses the
  third until `lib/` genuinely falls.

Nothing about the mechanism changes — this only stops the file claiming an
invariant that three raises have already disproved. A number nobody believes is
worse than a budget everybody reads.

## Rule Data Folded Into One File (2026-08-12)

**This reverses "Rule Data Stays Split", by the same operator instruction as the spine merge.**

`data/rules.yml` is the whole scanner law: all 225 rules under one `rules:` key, in the four scopes the scanners already asked for by name (`codebase` 52, `file` 21, `line` 80, `unit` 72). The four `data/rules/*.yml` shards are gone, and so is `merge_rule_shards` in `lib/boot/data.rb` — the loader now reads one file.

The fold was textual rather than a Psych round-trip, so every comment in the shards survived; a YAML load-and-dump would have stripped the lot, and those comments are where the rules explain themselves. `Master.load_rules` was proved deep-equal to its pre-fold output before the shards were deleted.

The old entry's argument was proximity to consumers. It did not hold up: the shards had **one** consumer between them — `load_rules`, which concatenated all four back into a single hash before any scanner saw them. The split was proximity for readers, not for code, and it cost a directory plus a merge step that could disagree with itself.

`data/design_rules.yml`, `data/llm_output_rules.yml`, and `data/rule_deps.yml` **do** each have separate consumers (`Master::Design`, `Master::Review::OutputCheck`, `Master::Fix::FixLoop`) and stay where they are. That part of the old entry was right and is not affected.

## Local Knowledge Stays Local

`knowledge/` is gitignored and skipped by scanners/snapshots, but it still powers `Master::Io::SearchKnowledge`. Do not move it unless the search tool learns the new location first.

## Deferred WebGL Boot Is Sacred

The face runtime must not create a WebGL context before the primer tap. The guard in `web/app/views/chat/index.html.erb` protects the tap-to-start path from eager or stale assets.

## Self-Test Is A Loud Gate

`rake selftest` runs `rules.yml.self_test` against MASTER itself. It is allowed to fail while known debt remains; the point is to make debt visible and triageable.

## The Cross-File Prescan Is Advisory, And Mostly Measures Itself

`/fix` prints `prescan: N cross-file risk(s)` before it runs. On 2026-07-31 that
number was 233. All of them were adjudicated against the code; the count is not
a backlog, and it does not block anything.

**It gates nothing.** `run_fix_and_prescan` calls `anti_sprawl_prescan`, then
calls `fix_loop.run(target)` unconditionally and joins the two strings. The
prescan is text printed above the result. A reader — including an agent — can
easily take "risk(s) — merge/rename before local patch" as a precondition. It is
not one.

Adjudication of all 231 findings the prescan reproduced (2 of the original 233
had been fixed in between):

| rule | n | verdict |
|---|---|---|
| MAGIC_NUMBER_SPREAD | 88 | artefact |
| COPY_PASTE_BLOCK | 57 | artefact |
| PARALLEL_HIERARCHY | 49 | artefact |
| SCATTERED_CONFIG | 19 | checked clean |
| CROSS_FILE_DRY | 11 | 1 real, since fixed |
| SPRAWL | 7 | artefact |

The evidence, so this does not need redoing:

- **MAGIC_NUMBER_SPREAD.** `MAGIC_NUMBER` is `/(?:[2-9]|[1-9]\d{2,})/` — every
  digit 2 through 9 anywhere, plus any number over 99. Hence "literal 8 recurs
  in 141 files" and "literal 2026 recurs in 50 files", which is the year. Of the
  occurrences behind the plausible-looking findings, **32% are already a named
  constant or a named keyword argument**: `512` is flagged across
  `PATTERN_CACHE_MAX = 512`, `BINARY_SAMPLE_BYTES = 512`, `rag_chunk_tokens: 512`
  and the phrase "512-token" in a comment — four meanings, three of them already
  named. The rule fires on the definitions of the constants it recommends
  extracting.

- **COPY_PASTE_BLOCK.** 44 of 57 involve at least one non-Ruby file, and
  **zero** are duplicated first-party Ruby. The top findings are JSON manifests
  in `reports/screenshots/calibration/`, three timestamped runs of the same
  tool, which share keys because they are the same schema. "Extract a module or
  template" is being said about generated test output.

- **PARALLEL_HIERARCHY.** Includes "Master spans 441 class/module hierarchies".
  `Master` is the root namespace of the entire codebase.

- **SPRAWL.** A case-insensitive word grep: `code.match?(/\bpolicy\b/i)` over
  `%w[cost auth policy cache notify search activity provider]`, firing at four
  files. `lib/result.rb` is flagged because error classification talks about
  policy. It cannot distinguish a scattered concern from a common English word.

- **SCATTERED_CONFIG** was the one worth checking properly, and it came back
  clean. All five `MASTER_AUTOFIX` reads use the identical `== "1"` idiom;
  `MASTER_WATCH` likewise; `MASTER_EXEC_TIMEOUT` is read exactly once, into
  `DEFAULT_TIMEOUT`. No drifting defaults, no contradiction.

- **CROSS_FILE_DRY** held the only real finding: `File.read(..., encoding:)`
  spelled `"UTF-8"` 32 times and `"utf-8"` 10 times. Normalised in 7fb8cc3d9.
  The rest are stdlib calls sharing a variable name, and three helpers named
  `read_text`/`read_file` that are three different error policies — nil-and-log,
  raise-but-tolerate-bad-bytes, and Result-with-validation — not three copies.

What actually stopped `/fix` was the clock, not the prescan: `fix_loop.rb:121`
returns `Result.ok("wall-clock timeout (1800s) after N pass(es)")`. Raising
`RUN_BUDGET_SECONDS` is therefore the real lever if `/fix` needs to finish, and
an earlier reading of mine that the risks were blocking it was wrong.

Before treating a prescan number as work: reproduce it with
`CrossFileAnalysis.new(root:).call(paths)` and read the findings. The printed
eight are `findings.first(8)`, never a representative sample.
