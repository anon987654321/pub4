# MASTER_NEW_PROPOSAL.md

Implementation plan for an external agent (Grok/GPT). Written 2026-07-09 after a full
verbatim read of `MASTER/` at commit `ab91c21b7`. Follow it top to bottom; every item
names its files, its rationale, and its acceptance test.

## Ground rules (non-negotiable)

- **Law files rule the work.** `MASTER/data/soul.yml` (PRESERVE_THEN_IMPROVE_NEVER_BREAK,
  anti-simulation, sacred_paths, RTFM_FIRST, FLAT_HIERARCHY) and `MASTER/data/rules.yml`
  (ROBUSTNESS > SINGULARITY > LINEARITY > PROXIMITY > ABSTRACTION > DENSITY; veto patterns;
  evidence scoring, PASS_THRESHOLD 80). Never edit either file. Never touch `sacred_paths`.
- **Tooling:** pure Ruby (`ruby -e`) or zsh globs. No `find`, `sed`, `awk`, `tr`, `grep -r`
  pipelines for edits. This is both the operator's preference and MASTER's own convention.
- **Every change lands with evidence.** `rake test` green, `MASTER/bin/check --profile=full`
  green, and a deep self-scan clean (`bin/cli /scan MASTER --depth deep`) before "done".
- **Net-negative LOC.** This proposal is a collapse, not an accretion. A PR that adds more
  lines than it deletes needs a written justification in its commit message.

## Where MASTER stands

Two spines coexist after the 2026-07 cutover merge:

1. `lib/` — 367 files, Zeitwerk runtime: `now/` (REPL, command registry), `judge/`,
   `loop/` (homeostat), `ground/` (sandbox policy, fs), `reach/`, `trace/`, `voice/`.
2. `core/` — the fold (`Master::Core::`): `Effect → Constitution → World → Memory`,
   one `Model` with a single LLM method and total parse, a closed verb set
   `%i[read write exec git ask note done]`, seven constitution rules, host-aware memory
   budgets (24k/8k chars, CONSTRAINED_MB 1100), and `core/ABSORPTION.md` mapping every
   `lib/` subsystem to its core destination with kill lists.

The bridge between them is `lib/now/core_bridge.rb` + `/fold` command + `bin/master-core`.
The decided endgame (2026-07-07): absorb `lib/` into `core/`, deleting as absorbed.

## Principles applied (research digest, kept to what changes decisions here)

- **YAGNI (Fowler):** the 367-file spine is carry-cost. Absorption deletes speculative
  breadth; do not port a `lib/` feature into `core/` until a command path actually needs it.
- **DRY vs AHA (Metz):** one authoritative representation per behavior — but "prefer
  duplication over the wrong abstraction." Where `lib/` and `core/` disagree, port the
  *behavior contract* (tests), not the class shapes.
- **KISS / Rams "less but better":** core stays six files plus data. Resist new files.
- **SOLID:** Constitution is the only legality judge (SRP); new capability arrives as
  data/config, never as a new verb or subclass (OCP without class proliferation).
- **Parametricism (Schumacher via Snøhetta):** one parametric artifact, many profiles —
  `bin/check` profiles, memory budgets by host class. Taboo: unrelated juxtaposition,
  i.e. no second runtime idiom living beside the fold.
- **Strunk & White rule 17:** applies to prompts, docs, and error strings. Omit needless words.

## Work items

### M1 — Run the absorption program (the bulk of the work)
Follow `core/ABSORPTION.md` order exactly, one subsystem per commit series. For each
subsystem: port the behavior contract into core (as World methods, Constitution rules
read from `data/rules.yml`, or Memory fold entries — never new verbs), move its tests
under `MASTER/test/core/`, then **delete the absorbed `lib/` files in the same commit**.
Acceptance per phase: `rake test` green; `bin/check --profile=agent` green; the deleted
files' behavior covered by a core test; net LOC negative.

### M2 — Enforce "no back-edges" structurally
Add `MASTER/test/core/test_no_lib_backedges.rb`: pure-Ruby scan asserting no file under
`core/` contains `require`/`require_relative` into `lib/`, and (once M1 completes a
subsystem) no `lib/` file references a deleted constant. This turns the absorption
invariant into a failing test instead of a review convention.

### M3 — Keep the verb set closed
Any request for new capability during M1 must be expressed as data (`data/*.yml`),
a Constitution rule, or a World method behind an existing verb. If an absorption
genuinely cannot fit the seven verbs, stop and write the case into `core/ABSORPTION.md`
under a "verb pressure" heading rather than adding a verb.

### M4 — CoreBridge sunset gate
When `lib/now/command_registry/` routes every command through core (checkable: registry
handlers call `CoreBridge`/`Master::Core` only), delete `lib/now/core_bridge.rb`, the
`/fold` alias, and `bin/cli --fold`, leaving `bin/master-core` as the single entry.
This is the ABSORPTION.md "Bridge vs Replace" decision gate — take Replace only when
the registry condition above is mechanically true.

### M5 — Fold the gate scripts into `bin/check` profiles
`bin/check` already has operator/contributor/agent/web/full profiles. Any standalone
verification script that survives in `MASTER/` outside `bin/check` gets either absorbed
as a profile step or deleted. One gate entrypoint (parametric variation, not repetition).

### M6 — Model stays one method
`core/model.rb` keeps a single LLM call site with total parse (bad JSON → note Effect).
Provider fallback order is data. Reject any patch that introduces per-provider classes
or a second call path (this is the most common way agents re-inflate the design).

### M7 — Docs pass
After each absorbed subsystem, update `core/ABSORPTION.md` (mark absorbed, strike kill
list) and delete any doc that still describes the pre-rename `kernel/` layout or the
absorbed `lib/` subsystem. Strunk & White the survivors: active voice, omit needless words.

### M8 — Style floor for all new code
Ruby style guide specifics that reviewers should enforce mechanically: methods ≤ 10 lines,
≤ 4 parameters (keyword args beyond 2), guard clauses over nested conditionals,
`rescue StandardError` never bare `rescue`/`Exception`, no coreutils shell-outs from Ruby.

## Definition of done

All of: `rake test` green from `MASTER/`; `bin/check --profile=full` green;
`bin/cli /scan MASTER --depth deep` clean; `core/ABSORPTION.md` shows every subsystem
either absorbed or explicitly deferred with a reason; `lib/` file count strictly lower
than 367 and trending to zero; evidence score ≥ 80 per `data/rules.yml` scoring
(test_pass 35 + scan_clean 25 + code_review 20 covers it).
