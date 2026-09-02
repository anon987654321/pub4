# The forward-work companion

`TODO.md` is the standing backlog: open records, each with the measurement
behind it, deleted when a check closes it. This file is the other half — the
forward work that is not yet a record. Opinions, hypotheses, wish lists, the
shape a tree would take if someone rebuilt it. An item leaves here when the
tree ships it, not when it stops being mentioned.

Every section is dated and says who wrote it, because several are not by the
same hand and disagree in places. That is allowed here, and it is the reason
this material is not in `TODO.md`: a backlog carrying both open work and wishes
teaches its reader to skim, and where the two files touch one subject only one
of them carries it. Two backlogs saying the same thing is the defect this repo
keeps writing down.

---

## 112 things one day taught this repo — 2026-08-29

Every item traces to something that actually happened rather than to general
advice — where a claim has a file and a line, they are named, so a reader can
check the reasoning instead of trusting it.

The session's own record is not flattering, and that is the point. Roughly a
third of these exist because a measurement was wrong, and about half of those
measurements were mine. This tree already says the instrument is wrong more
often than the code; a day of evidence agreed.

**[cheap]** is an afternoon. **[deep]** is a project. **[yours]** is a decision
rather than work. **[done]** landed that day and is listed so the pattern is
visible.

### A · The surfaces have multiplied (1–14)

`MASTER/bin` holds 28 entry points. `CLAUDE.md:50` says "Two surfaces, no third."
Nothing measures the gap, which is how 2 became 28 without a single failure.

1. A ratchet on entry-point count, per tree, in `spine.yml` beside the source-file ceilings. **[done]** `pub4_entrypoint_ceilings` in `spine.yml`, read by `entrypoint_rows` in `tools/ratchets.rb`, which counts *tracked* executables directly under each tree's own `bin/` — so another session's untracked scratch is not mistaken for a surface, and a Rails app's generated `bin/rails` is not either. MASTER 27, OPENBSD 17, RAILS 2, STUDIO 0.
2. Break the `check` ↔ `ci` cycle. **[done]** `bin/ci` is now nineteen lines that `exec` `bin/check --profile=ci`; one registry, and the double payment for selftest and core_smoke is gone. Kept as a script because its callers — a workflow file, `bin/preflight`, an operator's muscle memory — are outside this repo's reach.
3. Fold the twelve verification commands — check, gate, ci, audit, dogfood, preflight, probe, smoke, smoke-web, test-safety, doctor, nsaudit — into the two sanctioned surfaces. **[deep]**
4. Delete `bin/master`. It is 75 lines, 34 of them comment, and six of behaviour: a `chdir`, one env var, one argument rewrite, `exec bin/cli`.
5. Move that `chdir` into `bin/cli` by resolving its root from `__dir__` rather than `Dir.pwd`, which is the thing the wrapper exists to paper over. **[cheap]**
6. Grep every caller before deleting any entry point — `OPENBSD/`, `RAILS/gates/gates.yml`, rc.d scripts on the box. A command with no callers in this repo may still be in a cron line on vm23.
7. One name for one job: `bin/gate` *is* the scan→fix→critique→review chain and does not say so in its name.
8. A test that fails when a doc's stated invariant stops being true. "Two surfaces, no third" was prose, so it rotted silently. **[deep]**
9. `bin/pub4 test` with no arguments runs **nothing** when STUDIO is dirty. **[done]** It partitions STUDIO paths out and warns, rather than aborting on sight of one; the other three trees now run. The abort survives only for the case where STUDIO is the *only* dirty tree, which is a correct report of nothing to do rather than the bug.
10. Make that refusal a skip with a warning, so the other three trees still run. **[done]** With #9.
11. `bin/check --profile=agent` "may fail on known debt" — a profile whose failure carries no information teaches people to ignore it.
12. Publish the profile matrix somewhere a reader can see which profile runs which suite without reading three scripts.
13. Retire `master-core` or say in one line how it differs from `master`.
14. An `--explain` flag on the chain that prints what it will run before running it. `bin/gate` knows it, and refuses a flag it does not know rather than falling through to full-fix. **[done]**

### B · Gates that measure nothing (15–30)

The worst failure here is not a red gate. It is a green one.

15. `GATE_STRICT_INCONCLUSIVE=1` should be the default, not an opt-in. Four gates reported "checked nothing" in today's sweep and the summary line still read as a pass. **[yours]**
16. `rails_runtime` required `lib/production` after that file moved to `lib/host/production`. It failed at *require* time for months, so the composite went red naming no finding. **[done]**
17. `RAILS/test/gate_requires_resolve_test.rb` pins it: every `require_relative` under `gates/` resolves, and every `gates.yml` row names a file on disk. **[done]**
18. Extend that to every tree, not just RAILS.
19. A gate that skips its live half should report the count it skipped in the summary line, not only in its own output.
20. `runner.rb` takes whatever `ruby` is on PATH and prints one warning. Make the version mismatch fatal — app-bundle gates then fail for the interpreter and read as findings. **[cheap]**
21. Boot the triangle automatically for gates that need it, or fail rather than skip.
22. `flow_journey` skipped 23 live checks and `rendered_suite` 32; both reported inconclusive and neither failed.
23. `deploy_drift` "checked nothing — 1 precondition missing" and never says which precondition.
24. Name the missing precondition in every inconclusive line. **[cheap]**
25. A red gate naming no finding should say "this gate could not load" rather than printing an empty failure list.
26. `visual_contract` baselines are gitignored and overwritten on read, so a regression reports once and becomes the baseline.
27. `layout_snapshot` commits reviewable JSON instead — make that the default and retire the self-overwriting one. **[yours]**
28. A gate that can pass on a dirty tree and one that needs a clean one should say which they are, in `gates.yml`.
29. Record per-gate wall time; `rendered_suite` monopolises a Mac for an hour and nothing warns first.
30. A summary line that distinguishes passed / failed / measured-nothing, rather than folding the third into the first.

### C · Built, documented, and switched off (31–47)

The tree's own README names this: "A feature can be fully built, correct, documented — and switched off."

31. dilla had **156 of 405** ENV switches defaulting off. `DILLA_FULL` now turns on the 18 additive ones. **[done]**
32. `MELODIC_LEAD=1` and `SCALE_LEAD=1` both resolve and all four lead lanes still return empty — "lead: none". The switch is on and the feature generates nothing. **[deep]**
33. Audit the other 138 the same way: which are additive, which are exclusive forks, which are operational.
34. A rule that flags an ENV switch read in exactly one place and defaulting off — that shape is either dead or inert.
35. amber shipped **no `config/demo_media/` at all**, so all 17 garments fell through to random picsum stock. **[done]**
36. `DemoMedia::Catalog`'s last fallback was a file named `bergen.yml` under any app's root — amber has no `city_record`, so every lookup there hunted for a city it is not in. **[done]**
37. `FLYLO_DRUM_OVERLAY`, `FLYLO_TOP_DIRT`, `FLYLO_HAT_DUCK` were documented in dilla's README after `lib/` had renamed them to `WONKY_*`. Operators were setting switches nothing read. **[done]**
38. A check that every ENV name in a README is read somewhere in that tree's source. `MASTER/test/test_readme_env_names.rb`, over MASTER, OPENBSD and dilla. **[done]**
39. `FLYLO_QUINT_HATS` is read by nothing under either prefix — a genuinely dead switch, annotated rather than renamed.
40. The assertion under it passes because quint is never scheduled at all. A test that passes for the wrong reason is worse than one that fails.
41. `repligen` is a Replicate client and there is no Replicate access. The whole tool is unreachable. **[yours]**
42. `postpro.rb` takes `--input`/`--output`; called positionally it drops into an interactive picker and, in a script, hangs or silently does nothing. **[done]**
43. Document the headless invocation next to the interactive one.
44. `Shared::PostproProcessor` already had the working call — a second caller reinvented it wrongly. Extract one helper.
45. `system()` returning true is not evidence a file was written. Check the output exists and is non-empty.
46. The seeds' postpro path grades whatever it gets and reports nothing when the grade fails.
47. A failed grade should keep the ungraded frame and say so, because a missing file falls back to stock and looks seeded. **[done]**

### D · The instrument is wrong (48–66)

Half of these were mine, in one day.

48. I read `render_config.rb:104` and quoted it back while calling FLUX's limit a *VRAM* ceiling. It says host RAM at load: 23.8 GB of fp16 materialised before quantisation, against 12.7 GB. Recorded in two files; I had read one of them.
49. My seed-media notebook would have been killed at "Loading checkpoint shards" for 49 of 61 frames.
50. Quantisation cannot help a load-time limit — the model must exist before it can be made smaller. Write that where the next reader will look.
51. My luminance check read "mean grey 0/255" on a face that was plainly visible: a 1×1 downscale rounds a sparse bright field to zero. Max and percent-above-threshold are the right measures.
52. My corpus extractor paired every seed key with the *following* record's title, because I searched a window either side and took the last match. It would have produced 61 confidently wrong prompts.
53. Assert two known pairings before trusting an extractor over 61 unknown ones. **[done]**
54. I confirmed a dilla mix change on an 8-bar render. The arrangement cycle floors at 16 bars, so a short render is intro-main-outro and **the kit never enters** — I was comparing two drumless takes.
55. Record minimum useful render lengths per claim: mix balance needs 48 bars; a switch bisect can use 8.
56. I called a 6 dB sub rise "mud" before the sidecar showed the original was rendered with `DRUMS` unset. There were never any drums.
57. Read the provenance sidecar before comparing two renders. It is there for this.
58. `RENDER_SEED` does not fully pin — ~0.012 dB of run-to-run spread. Fine for an 11 dB bisect, useless for a 0.1 dB claim.
59. A helper that states which comparisons a given spread can and cannot support. **[cheap]**
60. I asserted CDP needed a trusted event for the face's primer. The gate is a plain JS flag and the page exposes `__MASTER_PRIMER_TAP__()`.
61. My first capture probe read `window.face` instead of `window.MASTER_FACE`, got undefined for both fields, and could not tell that apart from the legitimate 2D path. It reported success on a page that had drawn nothing. **[done]**
62. Any probe reading a global should fail loudly when the global is absent, never treat absence as a valid state.
63. Four separate patches failed on heredoc indentation because `<<~` strips the common margin. Line-index edits, or explicit indentation, for anything touching an indented block.
64. `dup_census` records only an integer, so there is no way to diff *which* duplicates are new. The same is true of `data_reach`. All three censuses record members now — `data_reach`, `self_findings` and `dup_census`. **[done]**
65. Record the member list beside the count in every census ratchet. Without it, "over by two" cannot be attributed. **[done]**
66. That gap cost real time today: I could not tell whether two new unread keys were mine. They were `business_plan` and `markdown_style`; both have readers now.

### E · A shared checkout is a hazard (67–79)

67. I read `rules.yml`, another session committed to it, and my write reverted their `business_plan` and `markdown_style` sections. Read-modify-write across three moments.
68. Publish through a worktree off `origin/main`, never by writing the shared tree. Now in `AGENTS.md`. **[done]**
69. A pre-commit check that refuses a write whose base is older than the file on disk. **[deep]**
70. `git checkout -- <path>` restores from HEAD; their commits were safe on origin. Say what you did rather than hope.
71. The pre-commit hook lists what it leaves behind — good — but a 160-path list trains people to skip it.
72. Summarise the leave-behind by tree with a count, and name only paths matching the commit's own tree.
73. `PUB4_UNTRACKED=1` is discoverable only by triggering the refusal. Document it. **[done]**
74. A push publishes every commit beneath yours. `git log --oneline origin/main..HEAD` before every push, and name what went with you.
75. Cherry-picking onto a moving `origin/main` rewrites SHAs, so "is my work pushed?" must be answered by content hash, not by SHA.
76. A helper that answers that: `pub4 pushed? <paths>`. **[cheap]**
77. `self_findings` crashed because a file vanished between listing and reading. In a shared tree that is normal, not a fluke. **[done]**
78. Every census that walks a file list needs the same tolerance.
79. Worktrees left behind are their own hazard — remove and prune in the session that made them.

### F · Documentation that outlived its code (80–92)

80. dilla's README advertised three switches `lib/` had renamed. The operator-facing file was the last to know.
81. The radio tunnel's comment said the visualiser "fills the frame identically at every size". It filled *proportionally*; the sides were never reachable. **[done]**
82. A comment stating a property is a claim. Where the property is measurable, a test should hold it.
83. `MASTER/AGENTS.md` called itself the entry for coding agents and never mentioned the root `CLAUDE.md`, which is the authority above it. **[done]**
84. It also omitted every operational trap: the Ruby pin, `git add -A`, the worktree recipe, Norwegian defaults, irreplaceable renders. **[done]**
85. `TODO.md` said three things twice after `RAILS/TODO.md` was folded in. **[done]**
86. A document that says a thing twice teaches the reader to skim.
87. `web/CLAUDE.md` documents a 2D fallback; it exists (`face.part1.txt:6`), which is worth knowing because I claimed otherwise before checking.
88. `check_hf_flux_access.rb` documents its own bug: it blocked SDXL renders on the licence terms of a model they do not use. My notebook reproduced that bug independently. **[done]**
89. When a tool documents a mistake, check whether the sibling tool makes it too.
90. `domain_watch.rb --update` cannot run on macOS — it shells to `/usr/bin/timeout`. So the snapshot can only be refreshed on the box, and nothing says so.
91. State a tool's host requirements in its usage line, not in a stack trace.
92. `spine.yml` warns that a raise absorbing another change's growth kills the ratchet. Every raise today names its file. Make naming mandatory. **[cheap]**

### G · Sound, and the things that only measure (93–102)

93. dilla's mix balance is a sub-to-body relationship, and five switches inverted it by 20 dB while every loudness number stayed correct.
94. Integrated LUFS, LRA and true peak were all healthy on a render that was hollow in the mids. Loudness metrics cannot see balance.
95. Add a sub/body/presence/air report to `dilla quality` so the four bands are one command. **[cheap]**
96. `MASTER_WIDTH` widens above 300 Hz, taking energy out of the correlated mids while leaving the sub — 7.2 dB of an 11.1 dB swing on its own.
97. Width is not free and should not be a default.
98. The README already says it: a loop with crowded mids cannot be beaten by pushing drums into them.
99. An A/B helper that renders two variants at the same seed and prints the four bands side by side. **[cheap]**
100. `chop` registers loops that `TRACK_PRESETS` has no row for, so using a documented command turns the suite red.
101. Either `chop` writes a preset row, or the reachability test learns about registry-driven loops. **[yours]**
102. Renders are gitignored and seeds rotate; never render over a take that matters, and back up before any destructive probe.

### H · Things only money or a person can fix (103–112)

103. **Nine domains are past expiry.** `cardff.uk` and `edinbrgh.uk` still answer on our nameservers and are recoverable; five have no NS at all. **[yours]**
104. **`bsdports.org` is parked** on `ns1.expireddomain.hyp.net` while `domain_inventory.yml` claims it is registered until 2027. A live product domain, down, invisible to the inventory. **[yours]**
105. Only `dns_zones` caught it, by resolving for real. Trust the live check over the snapshot.
106. **OpenRouter credits are exhausted** — the council personas fail and the entire semantic rule tier cannot run. **[yours]**
107. A chain that skips a whole tier must say so rather than report clean. **[cheap]**
108. Replicate and RunPod are unavailable; Colab plus a HuggingFace token is the render path.
109. Ragnhild's adapter is SDXL (`ss_base_model_version: sdxl_1.0`), so it cannot load into FLUX — the same hardware limit, one step earlier.
110. LoRA weights are gitignored, correctly: 218 MB of a real person's likeness does not belong in a public repo. The notebook searches Drive instead. **[done]**
111. Never hardcode a Drive share ID in a public repo; it discloses exactly what the gitignore prevents. **[done]**
112. The face renders at 0.4% of pixels lit. Whether that is right is a look decision, and not one an agent should make alone. **[yours]**

---

## Hypotheses and proposals — 2026-09-01

Three lists from external sessions, kept as written. None is measured
against the tree; that is what makes them wishes rather than records.

### Architectural Hypotheses
These are structural improvements considered from an external engineering perspective, not yet measured as debts.

- **Standardize CLI Tooling:** Replace `ruby -e` patterns used to avoid GNU tools with a shared internal CLI library to reduce cognitive load.
- **Staging Environment:** Introduce a mirror of `vm23` to validate constitutional gates in a live-like environment before production deploy.
- **Engine Boundaries:** Extend the "Fold Spine" budget concept to `RAILS` engines to enforce strict decoupling between the core and verticals.
- **Worktree Enforcement:** Implement a locking mechanism or `git` wrapper that mandates worktree creation for non-trivial changes.

### Brainstormed Enhancements
Conceptual gaps identified during system analysis.

- **Judge's Dashboard:** A dedicated UI for reviewing and resolving `Request` verdicts, replacing the current CLI-heavy process.
- **Decision Graph:** Transition `DECISIONS.md` from flat text to a structured graph linking `soul.yml` rules $\rightarrow$ Rationale $\rightarrow$ Git Commit.
- **Constitutional Telemetry:** Track "Verdict Frequency" (e.g., how often `Revise` is triggered) to detect prompt drift or overly strict laws.
- **Local Box Simulation:** a Vagrant/Docker OpenBSD-lite environment for safe local testing of `rc.d` and deploy scripts.
- **Soul Amendment Workflow:** A formal "Constitutional Audit" process to test new `soul.yml` rules against historical commits before adoption.

### Global Federation Proposal (The "City-State" Model)
Proposed by Nemotron 3.5 Lightning to evolve pub4 from a single-box fortress to a global network.

- **Constitution-as-a-Service:** Elevate `MASTER` to a Central Control Plane. City-boxes pull `soul.yml` and `rules.yml` via API to ensure global legal synchronization.
- **Sovereign-Cell Architecture:** Deploy the `RAILS` stack as isolated "Cells" (one box per city). Scale by replicating cells rather than expanding a single monolith.
- **Global Passport Identity:** Implement a federated identity layer signed by the Central `MASTER`, allowing users to move between city-networks (e.g., brgen.no $\rightarrow$ lsangeles.com) seamlessly.

---

## Reflections — after walking all four trees

Every tree is a constitution in progress: a place where the rules
govern the authors as much as the code. After reading through all of
them, the same pattern repeats — the trees argue well for *what* should
exist and lazily for *how* to make it findable, runnable, and
changeable by someone who has never read the file before. Below are the
wish lists and the 10/10 vision. They are opinions, not debt; a wish
list item is closed when the tree ships it, not when it stops being
mentioned.

### MASTER — what would make the constitutional runtime a joy to read

1. `bin/master` should print a one-line prompt so the user knows it
   is alive. A runtime that answers nothing looks broken.
2. Every `Law` class should declare its `source:` as a machine-readable
   URI, not a citation string, so `MASTER/bin/pub4 measure --origin` can
   trace any rule back to its origin paper or issue.
3. `data/rules.yml` should carry a `last_measured:` date per rule id so
   a reader knows when a finding count was last verified.
4. The fold spine (`lib/core/`) should own a `spine.yml` reader that
   prints the current line count against the ceiling on every boot,
   instead of only when `rake lint:spine` is run.
5. `rules.yml` `self_test` should be executable as a standalone gate
   (`bin/pub4 selftest`) rather than buried inside a YAML file a human
   has to parse.
6. Every `detect_semantic:` string should be paired with a `detect_lexical:`
   fallback in the registry, so no rule is purely semantic-only by accident.
7. `soul.yml` `version:` should drive a `CHANGELOG.md` at `MASTER/` so
   evolution is a log, not a git diff.
8. The `anti_simulation` forbidden words should be enforced by a
   pre-commit hook on `data/` files, not only at runtime.
9. `lib/review/scan/` should publish a public DSL reference (`scan.md`)
   so a new law writer knows the shape of a rule before opening the
   code.
10. `bin/pub4 gate` should accept `--tree MASTER` and only run MASTER's
    own laws against MASTER's code, not the union of all trees.
11. The `evidence_scoring` weights should be tunable per-tree without
    editing `rules.yml` — a `data/weights.yml` override.
12. `constitution.rb` should expose `Constitution.rules_for_law(name)`
    so a caller can ask "what does ROBUSTNESS require?" without
    re-parsing YAML.
13. `data/soul.yml` `persona:` and `voice:` should be validated at boot
    against a known-voices registry, not silently accepted.
14. The `hooks:` block in `soul.yml` should be wired to a test that
    verifies every listed event has at least one handler.
15. `lib/core/world.rb` `Effect` verbs should be enumerated in a
    `VERBS` constant and any unknown verb should raise at boot, not at
    runtime.
16. The scanner should warn when a rule's `detect_semantic:` contains a
    string longer than 200 characters — a readability guard for the law
    writers themselves.
17. `MASTER/data/project_context.yml` should be read at boot and its
    schema validated, since it is listed in `soul.yml` sacred paths.
18. A `bin/pub4 law --audit` that lists every rule id not carried by
    any principle in `principle_priorities`, exposing the inverse of the
    already-fixed principle-map gap.
19. `lib/review/scan/rules/` should carry a `README.md` that auto-generates
    from the registry so the rule inventory never drifts from the code.
20. `bin/master "<instruction>"` should support a `--dry-run` flag that
    simulates the fold's verdict without touching the world.
21. `data/rules.yml` `beauty:` should be split into its own file
    (`data/beauty.yml`) — aesthetics are not laws and should not live
    next to veto patterns.
22. Every `research:` URL in `rules.yml` should be verified at `bin/pub4
    gate --links` to catch 404s before the next audit cycle.
23. `MASTER` should ship a `CONTRIBUTING.md` that tells a new agent:
    "run `bin/check --profile=agent`, then `bin/check --profile=web`".
24. The `test/` directory should mirror `lib/` one directory deep, so
    every `lib/foo/bar.rb` has a known `test/foo/bar_test.rb` location.
25. `rules.yml` `failure_taxonomy` should be backed by a test that
    asserts every strategy has a `max_retries` and a `checksum`.
26. `lib/core/fold.rb` should log its own verdicts to a structured
    JSONL so the runtime can be reviewed after the fact.
27. The `learned_smells` list should carry a `measure_every:` date so
    a reader knows whether the findings are current or stale.
28. `data/limits.yml` should be enforced by a gate, not just read —
    every key without a reader should be flagged by `bin/pub4 limits`.
29. `MASTER` should declare its own `MASTER_VERSION` constant that
    matches `soul.yml version:` and `lib/core/world.rb` should refuse
    to boot if they disagree.
30. The `veto_patterns:` block should be compiled into a single
    optimized regex at load time and benchmarked — a veto pattern
    that slows the scanner is a veto pattern that gets disabled.
31. `lib/core/proof.rb` should carry a `PRODUCERS` constant that is
    tested against `evidence_scoring.producers:` to guarantee the
    regexes and the producers agree.
32. `rules.yml` `paths:skip_dirs:` should be enforced by `Dir.glob` at
    boot — a skip_dir that names no existing directory should warn.
33. The `self_test:` block should be executable via `bin/pub4 selftest`
    and its pass/fail should gate the `bin/master` boot.
34. `data/rules.yml` should carry a `schema_version:` that `RuleDSL`
    checks before parsing, so a future schema change is caught early.
35. Every `fix:` string in `rules.yml` should be tested against a
    synthetic violation to prove the fix actually resolves it.
36. `lib/core/memory.rb` should serialize its transcript to a file
    so a session can be replayed — a memory that lives only in RAM
    cannot be audited.
37. The `guard_expensive_ops` findings should be triaged by `bin/pub4
    triage --age 30` so stale findings do not accumulate silently.
38. `MASTER` should publish a `status.json` at boot containing the
    spine count, rule count, and verdict histogram for the session.
39. `data/principle_map.yml` should be validated to guarantee every
    `rule_id` exists in `rules.yml` and every `principle` exists in
    `principle_priorities` — a cross-reference that currently has no
    gate.
40. The `recovery:` block in `phantom_recovery` should be wired to
    `lib/core/world.rb` so the recovery steps are executable, not
    descriptive.
41. `MASTER` should ship a `bin/pub4 diagram` that emits a DOT graph
    of the fold spine — `Effect -> Constitution -> World -> Memory`.
42. Every `mode: opportunity` rule should be listed separately in the
    scan output so they do not inflate the error count.
43. `rules.yml` `engineering_fit:` should be tested by a gate that
    asserts every rule carries a `why_required:` answer.
44. `lib/core/constitution.rb` should be covered by a test that mutates
    each public method and verifies the fold still reaches the right
    verdict — a constitutional contract test.
45. `data/soul.yml` `absolute:sacred_paths:` should be verified at boot
    that every path exists and is not writable by the current user.
46. `rules.yml` `discovery` should be renamed — it is not a discovery
    mechanism, it is a `detect_semantic:` alias, and the name misleads
    every reader.
47. `MASTER` should declare a `CLI_PROTOCOL_VERSION` so the operator
    surface and the runtime can negotiate without drift.
48. `lib/review/scan/` should export a `scan_profile` JSON so the web
    face can display live scan metrics without reaching back into Ruby.
49. The `hooks:on_fix_applied` event should publish to a file that
    `bin/pub4 status` reads, so the operator sees how many fixes the
    system applied since last boot.
50. `rules.yml` should carry a `last_edited_by:` and `last_edited:`
    on every top-level section, and `git log` should be the source of
    truth for those stamps — a law without an author is a law without
    accountability.
51. `lib/core/fold.rb` `run` should accept a `timeout:` keyword that
    kills the scan after a configurable duration instead of hanging
    indefinitely on a stuck provider.
52. The `DECISIONS.md` or `NOTES.md` in `MASTER/` should carry a
    `search:` index so `bin/master` can answer "why was this rule
    created?" without reading the whole file.
53. `rules.yml` `auto_fix:` should be restricted to rules that have
    been verified against a snapshot — an unverified autofix is a
    silent corruption waiting for a tree-wide run.
54. `MASTER` should declare a `SUPPORTED_RUBY_VERSIONS` array and
    `bin/check` should verify the running Ruby is inside it before
    anything else loads.
55. Every `violation_priors:` row in `data/rules.yml` should be
    validated to name a rule id that actually exists — the empty-prior
    problem that `DATA_CLUMPS` lived inside for months.

### RAILS — what would make the city-network apps a joy to scale

1. Every engine should ship a `CONTRIBUTING.md` so a new developer
   knows the engine's test command without reading `AGENTS.md`.
2. The Norwegian locale files should carry a `lint:` that asserts
   every `t()` key in `app/` has a matching `nb.yml` entry, not just
   the reverse.
3. `brgen/test/` should mirror `engines/` one directory deep so every
   model test has a known home.
4. The `FrontPageWeightTest` and similar weight tests should be
   executable in isolation (`bin/rails test test/models/front_page_weight_test.rb`)
   without booting the full stack.
5. Every controller should declare `before_action :authenticate_user!`
   explicitly so a security scan can find the gap without guessing.
6. `RAILS/shared/lib/pub4/` should publish a `pub4.md` reference so
   shared helpers are discoverable by name.
7. `brgen/config/routes.rb` should carry a `RAILS_ROUTES_TEST` that
   asserts every named route resolves and no route is unreachable.
8. The `Shared::Sluggable` concern should be tested in isolation — a
   concern that is only tested through its host model hides integration
   bugs.
9. Every `has_many :through` should declare `inverse_of` explicitly —
   the 104 missing inverse_of count proves the default is not enough.
10. `RAILS/gates/` should ship a `README.md` that lists every gate and
    what it checks, so an operator knows which gate to reach for.
11. `RAILS/gates/data/css_budget.yml` should carry a `measured_on:`
    date so the budget is not blindly enforced against yesterday's
    render.
12. Every `accepts_nested_attributes_for` should be audited for the
    `reject_if` and `limit` options — nested attributes without them
    are a mass-assignment hole.
13. `brgen/app/javascript/` should carry a `package.json` audit that
    lists every dependency with its license and last-published date.
14. The `SolidQueue`, `SolidCache`, `SolidCable` stacks should each
    have a `test:_solid_*` job that verifies the connection survives a
    fork.
15. `RAILS/shared/design_tokens.yml` should be validated by a gate that
    asserts every token referenced in CSS/SCSS is declared and every
    declared token is used somewhere.
16. Every `scope` in a model should be tested with `unscope` to prove
    the inverse exists — a scope without an unscope is a chain that
    cannot be reset.
17. `RAILS/test/guest_write_rate_limit_test.rb` should be expanded to
    cover every guest-reachable write path, not just the six that were
    found on the first audit.
18. `brgen/engines/` each should declare their own `Gemfile` and
    `Rakefile` so they can be tested and bundled independently.
19. Every `validates :` should carry a message key in `locale/` —
    hardcoded validation messages are I18n defects by policy.
20. `RAILS` should declare a `RAILS_VERSIONS` matrix and `bin/check`
    should verify the running Rails version is inside it.
21. Every `after_commit` callback should be audited for idempotency — a
    callback that assumes it runs exactly once will misbehave on retry.
22. `app/channels/` broadcasts with no subscriber should be flagged by
    a gate so dead streams are caught before they hit production.
23. Every `default_scope` should be reviewed by a human and either
    justified or removed — default scopes are the silent killers of
    query performance.
24. `RAILS` should ship a `docker-compose.yml` for local development so
    the triangle can be booted without `vps-deploy`.
25. Every `find_by` that returns a single record should be tested for
    the not-found case (`rescue_from` or `handle_exception`) to
    guarantee a 404 and not a 500.
26. `app/mailers/` should be audited for missing `headers` — a mailer
    without explicit `from` and `reply_to` is a phishing vector.
27. Every `before_action` that modifies `Current` should be audited to
    ensure it resets `Current` in an `after_action` — a leaked Current
    is a cross-request data leak.
28. The `SolidQueue` or `SolidCache` queues should declare a
    `max_retry_count` and `dead_queue` so failed jobs are not silently
    dropped.
29. Every `ransack` or `searchkick` query should be audited for SQL
    injection — the user-supplied filter string is the attack surface.
30. `RAILS` should declare a `SESSION_EXPIRY` constant and test that
    sessions expire at that time — a session that never expires is an
    account takeover window.
31. Every `CarrierWave` or `ActiveStorage` upload should be audited for
    file type and size — an unbounded upload is a denial-of-service.
32. The `redis` or `solid_cache` connection should be tested for
    latency — a cache that adds 50ms to every read is worse than no
    cache.
33. Every `counter_cache` should be tested for correctness under
    concurrent creates — a counter that drifts under load is a lie.
34. `RAILS` should ship a `bin/rails audit:sql` that lists every N+1
    query detected by `Bullet` across the full suite.
35. Every `render json:` should declare `only:` or `except:` — a
    serialized model that exposes every attribute is a data leak.
36. The `CORS` configuration should be audited to guarantee every
    origin is explicit — a wildcard `Access-Control-Allow-Origin` is a
    CSRF enabler.
37. Every `sidekiq_options` should declare `retry:` and `dead:` so
    failed jobs are visible and not silently swallowed.
38. `RAILS` should declare a `PAYMENT_GATEWAY_FALLBACK` so the app
    degrades gracefully when Stripe is down — a payment app that
    crashes on a gateway timeout is a revenue killer.
39. Every `link_to` with a `method:` should be tested for the JS
    fallback — a progressive-enhancement link that fails without JS is
    a broken link.
40. `RAILS` should ship a `bin/rails health` that returns a JSON
    status of every engine, queue, and cache connection.
41. Every `strong_parameters` whitelist should be audited against every
    `form_with` to guarantee no field is accepted without explicit
    permission.
42. The `favicon.ico` and `robots.txt` should be declared as routes
    so they are not served by Rails at all — static files through the
    app are a performance tax.
43. Every `counter_cache` or `cache_column` should have a `REBUILD` task
    that can be run to fix drift without a full migration.
44. `RAILS` should declare a `DEPLOYMENT_SCORE` constant — a number
    from 0 to 100 that represents how safe a deploy is — and
    `vps-deploy` should refuse to proceed below 80.
45. Every `enum` should be tested for the invalid-value case — an enum
    that accepts a string it does not declare raises a silent
    `ActiveRecord::EnumNotFound`.
46. `RAILS/shared/` should declare a `SHARED_VERSION` constant so the
    shared code between engines can be versioned and its API
    backwards-compatibility tested.
47. Every `scope` that filters by `current_user` should be audited for
    the tenant isolation — a scope that does not scope is a data leak
    between cities.
48. `RAILS` should ship a `bin/rails security` that runs
    `brakeman`, `bundler-audit`, and the custom rule scanner in one
    command.
49. Every `after_initialize` or `to_prepare` block should be audited for
    thread-safety — a block that mutates global state is a race
    condition waiting to happen.
50. `RAILS` should declare a `PERFORMANCE_BUDGET` file that lists the
    maximum allowed response time, page weight, and query count for
    every page — and `bin/rails benchmark` should fail the deploy if
    any page exceeds it.
51. Every `ActionMailer::Base` subclass should declare `default from:`
    and `default reply_to:` so the framework enforces it, not the
    operator.
52. `RAILS` should ship a `bin/rails i18n:audit` that finds every
    hardcoded English string in a view helper and reports the missing
    locale key.
53. Every `has_and_belongs_to_many` should be reviewed for whether a
    `has_many :through` is more appropriate — HABTM cannot carry
    metadata on the join.
54. The `propshaft` manifest should be audited to guarantee
    every asset is referenced — an orphaned bundle is a waste of bytes.
55. `RAILS` should declare a `CITY_TIMEOUT` constant so every city
    engine can configure its own request timeout — a global timeout
    that fits Bergen does not fit Reykjavik.

### OPENBSD — what would make the deploy pipeline and VPS runbook a joy to operate

1. `OPENBSD/etc/rc.d/master` should print a startup banner that names
   the version, the PID, and the boot time so an operator knows the
   daemon is alive without checking `rcctl`.
2. Every script in `OPENBSD/bin/` should declare its own `VERSION`
   constant that `vps-deploy` reads before running.
3. `OPENBSD/bin/vps-deploy` should accept `--dry-run` that prints the
   full sequence of commands without executing any of them.
4. `OPENBSD/etc/relayd.conf` should be validated at boot by
   `relayd -n` and the result logged — a broken relayd.conf that loads
   is worse than one that refuses to load.
5. Every `rc.d` script should declare its `depends_on:` as a
   machine-readable list so `rcctl` can order them correctly without
   guessing.
6. `OPENBSD` should ship a `RELEASE_NOTES.md` that is updated on every
   deploy — an undeployed box is an undeployed change.
7. The `doas.conf` should be audited by a gate that asserts every
   rule is scoped to a command and a user — an unscoped doas rule is
   root access for everyone.
8. Every `pkg_add` in the install scripts should declare a
   `VERIFY_SIGNATURE` step — a package installed without a signify
   signature is a supply-chain attack.
9. `OPENBSD/bin/deploy-smoke.sh` should test every apex on the box,
   not just the three live apps — amber and bsdports need to hear
   their own smoke test.
10. `OPENBSD/etc/ssh/sshd_config` should be audited against
    `ssh-audit` on every deploy — a silent SSH downgrade is a root
    cause.
11. Every `cron` job should declare a `MAILTO=` so failures are
    emailed to the operator — a cron that fails silently fails forever.
12. `OPENBSD` should ship a `NETWORK_DIAGRAM.md` that maps every
    domain to its port, its relayd section, and its backend IP.
13. The `nsd.conf` zones should be validated by `nsd-check` at boot and
    the result logged — a broken zone file that loads serves stale DNS.
14. Every `acme-client` certificate should be audited for expiry by
    `OPENBSD/bin/domain_watch.rb` at boot, not just once a day.
15. `OPENBSD` should declare a `VPS_HEALTH_CHECK` that runs every
    five minutes and logs CPU, RAM, disk, and swap — a box that runs
    out of memory does not recover silently.
16. The `pf` firewall rules should be validated by `pfctl -nf` before
    loading — a bad rule set that loads blocks the operator's own SSH.
17. `OPENBSD/bin/sync_tree` should log the before-and-after SHA so a
    deploy can be verified without reading the git log.
18. Every `rc.d` script should have a `stop` that guarantees the
    process is dead — a daemon that refuses to stop cannot be upgraded.
19. `OPENBSD` should ship a `BACKUP_VERIFICATION` task that restores
    a random backup to a throwaway directory and runs `PRAGMA
    integrity_check` — a backup that has never been restored is not a
    backup.
20. `OPENBSD/etc/` should be tracked in git with a `git commit` on
    every change so the config has a history — config that lives only
    on the box is config that cannot be audited.
21. The `relayd` backend blocks should be audited to guarantee every
    backend has a health check — a backend with no health check is a
    backend that serves broken traffic.
22. `OPENBSD` should declare a `DEPLOY_ORDER` constant that lists the
    exact sequence of services to start and stop — a deploy that
    starts the app before the database is a failed deploy.
23. Every `pkg_add` should declare a `pkg_delete` fallback so an
    upgrade can be rolled back — a package manager without a rollback
    is a one-way door.
24. `OPENBSD` should ship a `LOG_ROTATION` config that guarantees
    every log file is rotated and compressed — an unrotated log fills
    the disk and takes the box down.
25. The `ntpd` or `openntpd` configuration should be verified to point
    at a reliable time source — a box with wrong time breaks TLS
    certificates and session tokens.
26. Every `rc.d` script should be tested by `OPENBSD/test/test_rc_scripts.rb`
    that starts, stops, and checks the process state in a throwaway
    jail — a script that works on the operator's box but not in a clean
    jail is a script that will fail on deploy.
27. `OPENBSD` should declare a `SECURITY_HARDENING` checklist that is
    verified on boot: SSH key-only, root login disabled, unused
    services stopped, firewall enabled.
28. The `daily.local` script should be audited to guarantee it does not
    run commands as root that could be replaced by a compromised
    binary — a daily script that runs everything as root is a privilege
    escalation script.
29. `OPENBSD/bin/dr-pull` should verify the restore by running a
    `sqlite3 .dump` diff against the source — a backup that restores
    to a different shape is a backup that lies.
30. `OPENBSD` should ship a `CAPACITY_PLAN` that documents the current
    RAM, disk, and connection limits, and the thresholds at which each
    would require an upgrade — a box that runs out of resources without
    warning is a box that runs out of service.
31. Every `ifstated` or `hostname.*` file should be tested to guarantee
    the hostname resolves to the correct IP — a box that answers the
    wrong name serves the wrong city.
32. `OPENBSD` should declare a `RUNBOOK_VERSION` that matches the
    deployed configuration — a runbook that does not match the box is
    a runbook that lies.
33. The `pf` table entries should be audited to guarantee no stale
    entries exist — a table that grows without bound is a table that
    slows the firewall.
34. `OPENBSD/bin/` should declare a `bin/usage` that lists every
    command and its arguments so an operator does not have to read the
    source to know what to run.
35. Every `ssh` key should be audited for its expiration and its
    `command=` restriction — an unrestricted key is a standing root.
36. `OPENBSD` should ship a `FAILURE_MODE.md` that lists the ten most
    likely failure scenarios and the exact command to diagnose each one.
37. The `rc.d` scripts should be tested for the `reload` case — a
    daemon that cannot be reloaded without a full stop/start is a
    downtime-inducing deploy.
38. `OPENBSD` should declare a `MONITORING_CONFIG` that exports
    `rrd` or `snmp` config so the box is watched by an external
    system — a box that monitors itself is a box that lies about itself.
39. Every `acme-client` domain should be audited to guarantee the
    certificate matches the hostname — a certificate for the wrong
    domain is a TLS failure waiting to happen.
40. `OPENBSD` should ship a `DISASTER_RECOVERY` script that can
    rebuild the entire box from a bare `pkg_add` — a recovery that
    requires the operator's manual is a recovery that will not happen
    at 3am.
41. The `smtpd` configuration should be audited to guarantee no
    open relay — an open relay is a spam bot's best friend and the
    operator's worst nightmare.
42. `OPENBSD` should declare a `NETWORK_POLICY` that documents every
    allowed inbound and outbound connection — a network without a
    policy is a network that accepts anything.
43. Every `rc.conf.local` variable should be audited for its default
    value — a variable set to a wrong default is a bug that hides
    until a fresh install.
44. `OPENBSD` should ship a `CHANGES.md` that is appended to on every
    deploy — a deploy without a changelog is a deploy that cannot be
    audited.
45. The `rc.d` scripts should declare their `provides:` so `rcctl` can
    resolve dependencies by capability rather than by script name.
46. `OPENBSD` should declare a `VPS_IMAGE` that can be booted in
    QEMU for testing — a deploy that cannot be tested locally is a
    deploy that can only be tested on the box.
47. Every `rc.d` script should be verified to run as the declared
    `daemon_user` — a script that runs as root when it should run as
    `_pub4ci` is a privilege escalation waiting for its exploit.
48. `OPENBSD/bin/` scripts should declare their `set -euo pipefail`
    at the top and be tested for it — a script without strict mode
    silently continues past every error.
49. `OPENBSD` should ship a `PERF_TUNING` file that documents every
    `sysctl` and `mount` option and the reason for each — a tuned box
    without documentation is a box that cannot be retuned.
50. `OPENBSD` should declare a `SECURITY_AUDIT` schedule — monthly
    `ssh-audit`, `pfctl -s all`, `pkg_info -m`, `daily.check` — and
    `vps-deploy` should refuse to proceed if the last audit was more
    than 30 days ago.
51. Every `relayd` section should be audited to guarantee the `block`
    policy is set on every listen — a relayd section without a block
    policy is a relayd that forwards anything.
52. `OPENBSD` should ship a `TICKET_TEMPLATE` that the operator fills
    out on every deploy — a deploy without a ticket is a deploy that
    cannot be tracked.
53. The `ntp` symmetric keys should be rotated on every deploy — an
    ntp key that never changes is a time-source compromise that never
    gets noticed.
54. `OPENBSD` should declare a `SERVICE_LEVEL_AGREEMENT` that maps
    every apex to its acceptable downtime — a service without a
    guarantee is a service that cannot be measured.
55. Every `rc.d` script should declare its `START_ORDER` so `vps-deploy`
    can start the box in the right sequence — a box that starts its
    app before its database is a box that wastes its first minute
    crashing.

### STUDIO — what would make the media tools a joy to create with

1. `dilla.rb` should ship a `dilla.md` that explains the 81 parts in
   the order they are required, so a new contributor can trace a sound
   without reading the whole file.
2. Every renderer (`render_*.rb`) should declare its `SAMPLE_RATE` and
   `BIT_DEPTH` at the top so the operator knows what the output will be.
3. `STUDIO/dilla/renders/` should be migrated into the dilla root with
   `.gitignore` rules, so the render pipeline is inside the repo where
   it can be audited.
4. Every `lib/*.rb` support module should declare its `__dir__` once at
   the top and use a constant, so moving the file does not break the
   path.
5. `DillaSources` should declare a `SOURCES_VERSION` that matches the
   sample corpus, so a mismatch between code and samples is caught at
   boot.
6. `dilla.rb` should be split along its existing seams — the renderers,
   the ENV tables, the SMF writers, the patch registries — into `lib/`
   files that `require` each other in a declared order.
7. Every `test_dilla_*` should declare its own timeout so a slow test
   does not kill the whole suite — a suite that fails from timeout is a
   suite that lies about what passed.
8. `test_dilla_audio_graph_parity.rb` should be fixed to match the
   current bus-routed graph topology — a test that expects a flat
   `amix` when the engine emits a routed graph is a test that tests
   the wrong thing.
9. `STUDIO/gate.rb` should declare a `GATE_VERSION` and test that
   `lib/engine/` does not reappear — a gate that does not test its own
   condition is a gate that can be silently bypassed.
10. Every `Outboard.chain` arm that names a module should be tested to
    verify the module exists and is dispatchable — dead arms are dead
    code that looks alive.
11. The `samples/dug/` corpus should be documented with a `sources.yml`
    that maps every file to its download URL — a sample without a URL
    is a sample that cannot be re-fetched.
12. Every `rack` in the registry should be deduplicated by checksum so
    the 38 duplicate recordings are collapsed to 123 unique wavs.
13. `dilla.rb` should declare a `LINE_LIMIT` of 300 and `bin/check`
    should enforce it — a file that exceeds the limit is a file that
    cannot be read.
14. Every `key` in the registry should be measured and verified against
    a `KEY_LIBRARY` constant, so a key that is out of tune with the
    rest of the crate is caught before it renders.
15. `STUDIO` should ship a `RENDER_SEED` constant that pins every
    render to a deterministic seed, so a "re-render" actually produces
    the same file.
16. Every `vocal_chop` that skips a row should log the skip reason so
    the operator knows why the vocal is missing — a silent skip is a
    silent defect.
17. `dilla.rb` should declare `DRUM_LOOP_SOURCE` as a constant
    that is tested to exist before any render starts — a drum loop
    that resolves to `~/Downloads` is a render that depends on a file
    outside the repo.
18. Every `techno_harmony_root` should be tested against a
    `HARMONY_VALIDATOR` so the most advanced processing in the tree is
    the most tested.
19. `STUDIO` should declare a `RENDER_BUDGET` that lists the maximum
    render time, the maximum memory, and the maximum disk per render.
20. Every `__FILE__` reference should be replaced with `__dir__` — a
    file path that hardcodes the directory is a path that breaks when
    the file moves.
21. `postpro/` should declare its own `CONTRIBUTING.md` so a colorist
    knows the grading pipeline without reading the source.
22. Every `repligen/` and `lora/` model should declare its `MODEL_VERSION`
    and `CHECKSUM` so a corrupted model is caught at load time.
23. `STUDIO` should ship a `GENERATE.md` that explains how to reproduce
    a specific render — a render without a recipe is a render that
    cannot be repeated.
24. Every `dilla.rb` part that manipulates audio should be tested with
    a known-input known-output file so the transform is verifiable.
25. `STUDIO` should declare a `SEED_REALISM` constant that guarantees
    every city's demo audio sounds like that city — 39 of 43 cities
    seeding at `0,0` is a map that reads as empty.
26. Every `render` should write a `.dilla` provenance sidecar that is
    validated at write time — a provenance that is optional is a
    provenance that is skipped.
27. `STUDIO` should ship a `RENDER_DIFF` tool that compares two
    renders with their seeds and reports the dB difference — a render
    that changes without a seed change is a render that changed by
    accident.
28. Every `sound` in the tree should be tagged with its `GENRE` so a
    genre-agnostic tool is genre-discoverable.
29. `STUDIO` should declare a `RENDER_BACKUP` policy that copies every
    render to an off-tree location before it can be overwritten — a
    render that can be overwritten is a render that can be lost.
30. Every `patch` registry in `dilla.rb` should be tested to guarantee
    the patch applies cleanly to the target version — a patch that
    fails silently is a patch that lies.
31. `STUDIO` should ship a `BENCHMARK` script that measures every
    render's CPU and wall-clock time and fails if it exceeds the budget.
32. Every `effect` in the chain should be auditable — the operator
    should be able to ask "what effect was applied here?" and get the
    exact module and arguments.
33. `STUDIO` should declare a `FORMAT_VERSION` for every output format
    so a format change is a breaking change that is versioned.
34. Every `loops` file should be tested for its `beats_per_minute`
    against the registry — a loop that lies about its BPM is a loop
    that breaks the mix.
35. `STUDIO` should ship a `RENDER_MONITOR` that watches the render
    directory and alerts when a render exceeds the time budget or the
    disk budget.
36. Every `plugin` or `external` call should be wrapped in a
    `with_timeout` so a hung external process does not hang the whole
    render pipeline.
37. `STUDIO` should declare a `QUALITY_GATE` that asserts every render
    passes a spectral analysis before it is considered done — a render
    that passes without analysis is a render that might be silent.
38. Every `sample` should be tested for its `duration` against the
    expected length — a sample that is shorter than expected is a loop
    that drops beats.
39. `STUDIO` should ship a `RENDER_LOG` that records every render
    command, every parameter, and every seed — a render without a log
    is a render that cannot be reproduced.
40. Every `mix` should be tested for its `peak_level` and `rms_level`
    so a clip that exceeds 0dB is caught before it is rendered.
41. `STUDIO` should declare a `MASTER_RENDER` that is the canonical
    reference render for every crate — a crate without a reference is a
    crate that cannot be judged.
42. Every `dilla.rb` constant that appears in `data/voice.yml` should
    be read from `data/voice.yml` — a constant that is also hardcoded is
    a constant that drifts.
43. `STUDIO` should ship a `CORPUS_AUDIT` that verifies every sample
    in the registry exists on disk and is not corrupted — a registry
    that names a file that does not exist is a registry that lies.
44. Every `sfx` bank should be tested for its `sample_rate` and
    `bit_depth` against the project settings — an sfx bank at the wrong
    sample rate is a sound that is pitched wrong.
45. `STUDIO` should declare a `RENDER_PIPELINE_VERSION` that matches
    the `dilla.rb` version — a pipeline that does not match the code
    renders a sound that does not match the spec.
46. Every `filter` should be tested for its `frequency_response` against
    a known target — a filter that does nothing is a filter that lies.
47. `STUDIO` should ship a `GENRE_PROFILE` for each supported genre
    that defines the BPM range, the key range, and the mix rules — a
    genre without a profile is a genre without a standard.
48. Every `envelope` should be tested for its `attack`, `decay`,
    `sustain`, and `release` values against the DAW convention — an
    envelope that is out of phase is a sound that hits at the wrong time.
49. `STUDIO` should declare a `RENDER_QUALITY_TIER` (draft, studio,
    master) so the operator knows what level of processing is applied.
50. `STUDIO` should ship a `RENDER_VALIDATOR` that runs spectral,
    temporal, and loudness analysis on every output and fails if any
    metric is out of range.
51. Every `tempo` change should be tested for its `time_stretch`
    algorithm — a tempo change without time-stretch is a pitch change.
52. `STUDIO` should declare a `MASTER_BUS` standard that every render
    must pass through — a render that bypasses the master bus is a
    render that has no master.
53. Every `bus` should be tested for its `gain` and `pan` against the
    stereo field — a bus that is off-center is a mix that is unbalanced.
54. `STUDIO` should ship a `RENDER_ARCHIVE` that compresses every
    finished render and stores it with its seed — a render without an
    archive is a render that can be lost.
55. `STUDIO` should declare a `CREATE_QUALITY` policy that asserts
    every generated sound passes a human-in-the-loop review before it
    is considered finished — an AI that generates without review is an
    AI that generates garbage.

### The 10/10 MASTER — vision

The perfect MASTER is a runtime where the constitution is not a file
you read but a surface you interact with. A developer clones the repo,
runs `bin/check --profile=agent`, and the first thing they see is not
a sea of red failures but a clean scan and a single sentence: "The
constitution is green. Here is what the fold found."

It is a runtime where every rule carries its own evidence — the finding
count, the last measurement, the false-positive history — and every
measurement is verified against a known-clean snapshot before it is
trusted. A rule that cannot prove itself is a rule that should not exist.

It is a runtime where the fold spine is measured by its own law, where
the scanner is tested by the rules it scans, and where the constitution
is the first thing that gets reviewed in a code audit — not the last.

It is a runtime where `bin/master` answers a question in a sentence,
where `bin/pub4 gate` tells you exactly which law a change broke and
why, and where `bin/pub4 measure` gives you a number you can trust
because it was measured today, not last week.

It is a runtime where the four trees are four citizens of one
constitution, where `MASTER` governs `RAILS` the way `RAILS` governs
`STUDIO`, and where the OpenBSD box is not a deployment target but a
provable artifact — every config file signed, every service
verifiable, every deploy auditable.

The 10/10 MASTER is a constitutional runtime that applies its laws to
itself without exception, where the governor is governed, where every
effect is proved and every verdict is recorded, and where a new
contributor can go from clone to green check without reading a single
contract file — because the runtime itself teaches them what it needs
from them.

---

## Reflections — Muse Spark 1.2 Free (2026-09-01)

Walked all four trees in one session, fixed what was verifiable, left
what needs an owner. The same failure repeats: a file that contains its
own proof of correctness while not being correct — TODO.md with conflict
markers, rules.yml with priors that name no rule, a render at the repo
root that claims to belong under `STUDIO/dilla/renders/`, a design token
ladder that cannot name its most-used rung. Below are the wishes, one
per tree, and the 10/10 vision. Each is an opinion, not debt; it closes
when shipped. Signed: Muse Spark 1.2 Free.

### MASTER — what would make the constitutional runtime a joy for humans and LLMs

1. `TODO.md` should never contain `<<<<<<<` — add a pre-commit hook that fails on conflict markers, verified by a test that asserts the marker string itself is not found.
2. `MASTER/data/rules.yml` `violation_priors` and `rule_deps` should be validated at boot: every id must resolve to a law or a rule, otherwise the constitution is citing a law that does not exist.
3. `MASTER/bin/master` should print a one-line prompt on TTY so `bundle exec ruby bin/cli` does not look dead.
4. Every `Law` class should declare its `source:` as a URI, not a prose citation, so `bin/pub4 measure --origin` can trace any rule to its paper.
5. `data/rules.yml` should carry `last_measured:` per rule id, so a reader knows if a finding count is today's or last month's.
6. The fold spine (`lib/core/`) should publish its line count vs ceiling on every boot, not only when `rake lint:spine` is run.
7. `rules.yml` `self_test` should be a runnable gate (`bin/pub4 selftest`), not a YAML block a human parses.
8. Every `detect_semantic:` should have a `detect_lexical:` fallback, so no rule is purely semantic by accident.
9. `soul.yml` `version:` should drive `CHANGELOG.md`, so evolution is a log, not a diff.
10. `anti_simulation` forbidden words should be enforced by a pre-commit hook on `data/`, not only at runtime.
11. `lib/review/scan/` should publish a DSL reference (`scan.md`) so a new law writer knows the shape before opening code.
12. `bin/pub4 gate` should accept `--tree MASTER` to run only MASTER's laws on MASTER.
13. `evidence_scoring` weights should be tunable per-tree via `data/weights.yml` without editing `rules.yml`.
14. `constitution.rb` should expose `Constitution.rules_for_law(name)` without re-parsing YAML.
15. `data/soul.yml` `persona:` and `voice:` should be validated at boot against a known-voices registry.
16. `hooks:` in `soul.yml` should be wired to a test asserting every event has a handler.
17. `Effect` verbs in `lib/core/world.rb` should be enumerated in `VERBS` and unknown verbs should raise at boot.
18. The scanner should warn when `detect_semantic:` exceeds 200 chars — a readability guard for law writers.
19. `data/project_context.yml` should be validated at boot, since it is listed in `sacred_paths`.
20. Add `bin/pub4 law --audit` listing every rule id not carried by any principle — the inverse of the principle-map gap.
21. `lib/review/scan/rules/` should carry an auto-generated `README.md` from the registry so inventory never drifts.
22. `bin/master "<instruction>"` should support `--dry-run` that simulates the fold's verdict without touching the world.
23. `data/rules.yml` `beauty:` should be split to `data/beauty.yml` — aesthetics are not laws.
24. Every `research:` URL in `rules.yml` should be verified by `bin/pub4 gate --links` to catch 404s.
25. Ship a `CONTRIBUTING.md`: "run `bin/check --profile=agent`, then `bin/check --profile=web`".
26. `test/` should mirror `lib/` one-deep, so every `lib/foo/bar.rb` has a known test home.
27. `failure_taxonomy` should be backed by a test asserting every strategy has `max_retries`.
28. `lib/core/fold.rb` should log verdicts to JSONL so the runtime is auditable after the fact.
29. `learned_smells` should carry `measure_every:` so a reader knows if findings are stale.
30. `data/limits.yml` should be enforced by a gate, not just read — every key without a reader should be flagged.
31. Declare `MASTER_VERSION` matching `soul.yml version:`; `world.rb` should refuse to boot if they disagree.
32. Compile `veto_patterns:` into one optimized regex at load and benchmark it — slow vetoes get disabled.
33. `lib/core/proof.rb` `PRODUCERS` should be tested against `evidence_scoring.producers:` to guarantee they agree.
34. `paths:skip_dirs:` should be enforced by `Dir.glob` at boot — a skip_dir naming no existing dir should warn.
35. `data/rules.yml` should carry `schema_version:` checked by `RuleDSL` before parsing.
36. Every `fix:` string should be tested against a synthetic violation to prove it resolves.
37. `lib/core/memory.rb` should serialize its transcript so a session is replayable — RAM-only memory cannot be audited.
38. Add `bin/pub4 triage --age 30` to prevent stale `guard_expensive_ops` findings accumulating.
39. Publish `status.json` at boot with spine count, rule count, verdict histogram.
40. Validate `data/principle_map.yml` cross-reference: every `rule_id` must exist in `rules.yml`.
41. Wire `phantom_recovery` `recovery:` to `lib/core/world.rb` so steps are executable, not descriptive.
42. Ship `bin/pub4 diagram` emitting DOT graph of `Effect -> Constitution -> World -> Memory`.
43. List `mode: opportunity` rules separately in scan output so they do not inflate error count.
44. Test `engineering_fit:` to assert every rule carries `why_required:`.
45. Cover `constitution.rb` with mutation tests verifying the fold still reaches the right verdict.
46. Verify `absolute:sacred_paths:` at boot: every path exists and is not writable by current user.
47. Rename `discovery` — it is a `detect_semantic:` alias, name misleads every reader.
48. Declare `CLI_PROTOCOL_VERSION` so operator surface and runtime negotiate without drift.
49. Export `scan_profile` JSON so the web face shows live scan metrics without Ruby.
50. Make `hooks:on_fix_applied` publish to a file `bin/pub4 status` reads, so fixes since boot are visible.
51. Carry `last_edited_by:` and `last_edited:` on every top-level section, with `git log` as source — a law without author has no accountability.
52. Accept `timeout:` in `Fold#run` to kill a stuck provider instead of hanging a 1GB host.
53. Carry a `search:` index in `DECISIONS.md` so `bin/master` can answer "why was this rule created?" without reading the whole file.
54. Restrict `auto_fix:` to rules verified against a snapshot — unverified autofix is silent corruption.
55. Declare `SUPPORTED_RUBY_VERSIONS` and verify at `bin/check` before anything loads.

### RAILS — what would make the city-network apps a joy to scale

1. Every engine should ship `CONTRIBUTING.md` so a new dev knows the engine's test command without reading `AGENTS.md`.
2. Add a `lint:` that asserts every `t()` key in `app/` has a matching `nb.yml` entry, not just the reverse.
3. `brgen/test/` should mirror `engines/` one-deep so every model test has a known home.
4. Make `FrontPageWeightTest` runnable in isolation without booting the full stack.
5. Every controller should declare `before_action :authenticate_user!` explicitly so a security scan can find the gap.
6. Publish `RAILS/shared/lib/pub4/pub4.md` reference so shared helpers are discoverable.
7. Carry `RAILS_ROUTES_TEST` asserting every named route resolves and no route is unreachable.
8. Test `Shared::Sluggable` in isolation — a concern only tested through its host hides bugs.
9. Every `has_many :through` should declare `inverse_of` explicitly — 104 missing proves default is not enough.
10. Ship `RAILS/gates/README.md` listing every gate and what it checks.
11. `css_budget.yml` should carry `measured_on:` so the budget is not enforced against yesterday's render.
12. Audit every `accepts_nested_attributes_for` for `reject_if` and `limit` — without them it is mass-assignment.
13. Carry a `package.json` audit listing every dependency with its license and last-published date.
14. Add `test:_solid_*` jobs verifying the connection survives a fork for SolidQueue/Cache/Cable.
15. Gate `shared/design_tokens.yml`: every token referenced in CSS must be declared and every declared token used.
16. Test every `scope` with `unscope` to prove the inverse exists — a scope without unscope cannot be reset.
17. Expand `guest_write_rate_limit_test.rb` to cover every guest-reachable write path, not just six.
18. Each engine should declare its own `Gemfile`/`Rakefile` so it can be tested independently.
19. Every `validates :` should carry a message key in `locale/` — hardcoded messages are I18n defects.
20. Declare `RAILS_VERSIONS` matrix and verify at `bin/check`.
21. Audit every `after_commit` for idempotency — a callback assuming exactly-once misbehaves on retry.
22. Flag `app/channels/` broadcasts with no subscriber so dead streams are caught before production.
23. Review every `default_scope` — default scopes are silent query killers.
24. Ship `docker-compose.yml` so the triangle boots without `vps-deploy`.
25. Test every `find_by` for the not-found case to guarantee 404 not 500.
26. Audit `app/mailers/` for missing `headers` — a mailer without explicit `from`/`reply_to` is phishing.
27. Audit every `before_action` modifying `Current` to ensure it resets in `after_action` — leaked Current is cross-request leak.
28. Declare `max_retry_count` and `dead_queue` for every queue so failed jobs are not dropped.
29. Audit every `ransack`/`searchkick` query for SQL injection — user-supplied filter is the surface.
30. Declare `SESSION_EXPIRY` and test expiry — a session that never expires is account takeover.
31. Audit every `CarrierWave`/`ActiveStorage` upload for type and size — unbounded upload is DoS.
32. Test `redis`/`solid_cache` latency — a cache adding 50ms per read is worse than no cache.
33. Test every `counter_cache` under concurrent creates — a counter that drifts under load is a lie.
34. Ship `bin/rails audit:sql` listing every N+1 query Bullet finds across the suite.
35. Every `render json:` should declare `only:`/`except:` — a model exposing every attribute is a leak.
36. Audit `CORS` to guarantee every origin is explicit — wildcard Allow-Origin is CSRF.
37. Every `sidekiq_options` should declare `retry:` and `dead:`.
38. Declare `PAYMENT_GATEWAY_FALLBACK` so the app degrades when Stripe is down.
39. Test every `link_to` with `method:` for JS fallback — progressive-enhancement link failing without JS is broken.
40. Ship `bin/rails health` returning JSON status of every engine, queue, cache.
41. Audit every `strong_parameters` whitelist against every `form_with` to guarantee no field is accepted without permission.
42. Declare `favicon.ico`/`robots.txt` as routes so they are not served by Rails — static files through app are tax.
43. Every `cache_column`/`counter_cache` should have a `REBUILD` task to fix drift without migration.
44. Declare `DEPLOYMENT_SCORE` 0-100; `vps-deploy` should refuse below 80.
45. Test every `enum` for the invalid-value case — invalid strings raise silent `EnumNotFound`.
46. Declare `SHARED_VERSION` so shared code between engines can be versioned and tested for back-compat.
47. Audit every `scope` filtering by `current_user` for tenant isolation — a scope that does not scope is data leak between cities.
48. Ship `bin/rails security` running `brakeman`, `bundler-audit`, and custom scanner in one command.
49. Audit every `after_initialize`/`to_prepare` for thread-safety — mutating global state is race.
50. Declare `PERFORMANCE_BUDGET` listing max response time, page weight, query count per page — `bin/rails benchmark` should fail deploy if exceeded.
51. Every `ActionMailer` subclass should declare `default from:`/`reply_to:` so framework enforces, not operator.
52. Ship `bin/rails i18n:audit` finding every hardcoded English string in a view helper.
53. Review every `has_and_belongs_to_many` for whether `has_many :through` is more appropriate — HABTM cannot carry metadata.
54. Audit `propshaft` manifest to guarantee every asset is referenced — orphaned bundle is bytes wasted.
55. Declare `CITY_TIMEOUT` so every city engine configures its own request timeout — a global timeout fitting Bergen does not fit Reykjavik.

### OPENBSD — what would make the deploy pipeline and VPS runbook a joy to operate

1. `rc.d/master` should print a startup banner naming version, PID, boot time so operator knows daemon is alive without `rcctl`.
2. Every script in `OPENBSD/bin/` should declare its own `VERSION` read by `vps-deploy` before running.
3. `vps-deploy` should accept `--dry-run` printing the full sequence without executing.
4. `relayd.conf` should be validated at boot by `relayd -n` and result logged — a broken conf that loads is worse than one that refuses.
5. Every `rc.d` script should declare `depends_on:` as machine-readable list so `rcctl` orders correctly without guessing.
6. Ship `RELEASE_NOTES.md` updated on every deploy — an undeployed box is an undeployed change.
7. Audit `doas.conf` via a gate asserting every rule is scoped to a command and user — unscoped doas is root for everyone.
8. Every `pkg_add` should declare `VERIFY_SIGNATURE` — a package without signify is supply-chain attack.
9. `deploy-smoke.sh` should test every apex on the box, not just three live apps — amber and bsdports need their own smoke test.
10. `sshd_config` should be audited via `ssh-audit` on every deploy — silent SSH downgrade is root cause.
11. Every `cron` job should declare `MAILTO=` so failures are emailed — a cron failing silently fails forever.
12. Ship `NETWORK_DIAGRAM.md` mapping every domain to its port, relayd section, backend IP.
13. `nsd.conf` zones should be validated by `nsd-check` at boot and logged — a broken zone serving stale DNS is worse than no DNS.
14. Every `acme-client` cert should be audited for expiry by `domain_watch.rb` at boot, not just once a day.
15. Declare `VPS_HEALTH_CHECK` running every five minutes logging CPU, RAM, disk, swap — a box out of memory does not recover silently.
16. `pf` rules should be validated by `pfctl -nf` before loading — a bad rule loading blocks operator's own SSH.
17. `sync_tree` should log before-and-after SHA so a deploy is verifiable without `git log`.
18. Every `rc.d` script should have a `stop` guaranteeing the process is dead — a daemon refusing to stop cannot be upgraded.
19. Ship `BACKUP_VERIFICATION` restoring a random backup to throwaway dir and running `PRAGMA integrity_check` — a backup never restored is not a backup.
20. `etc/` should be tracked in git with a commit on every change so config has a history — config only on box cannot be audited.
21. `relayd` backends should be audited to guarantee every backend has a health check — a backend without health check serves broken traffic.
22. Declare `DEPLOY_ORDER` listing exact sequence to start/stop — a deploy starting app before database is failed deploy.
23. Every `pkg_add` should declare `pkg_delete` fallback so an upgrade can be rolled back — a manager without rollback is one-way door.
24. Ship `LOG_ROTATION` guaranteeing every log file is rotated and compressed — an unrotated log fills disk and downs box.
25. Verify `ntpd`/`openntpd` points at reliable time source — a box with wrong time breaks TLS and session tokens.
26. Test every `rc.d` script via `test_rc_scripts.rb` starting/stopping in a throwaway jail — a script working on operator's box but not clean jail will fail on deploy.
27. Declare `SECURITY_HARDENING` checklist verified on boot: SSH key-only, root login disabled, unused services stopped, firewall enabled.
28. Audit `daily.local` to guarantee it does not run commands as root that could be replaced by compromised binary — a daily script running everything as root is privilege escalation.
29. `dr-pull` should verify restore by running `sqlite3 .dump` diff against source — a backup restoring to different shape is lying.
30. Ship `CAPACITY_PLAN` documenting current RAM, disk, connection limits and thresholds requiring upgrade — a box running out of resources without warning runs out of service.
31. Test every `ifstated`/`hostname.*` to guarantee hostname resolves to correct IP — a box answering wrong name serves wrong city.
32. Declare `RUNBOOK_VERSION` matching deployed config — a runbook not matching box is lying.
33. Audit `pf` tables to guarantee no stale entries — a table growing without bound slows firewall.
34. Declare `bin/usage` listing every command and args so operator need not read source to know what to run.
35. Audit every `ssh` key for expiration and `command=` restriction — unrestricted key is standing root.
36. Ship `FAILURE_MODE.md` listing ten most likely failures and exact command to diagnose each.
37. Test `rc.d` scripts for `reload` — a daemon that cannot reload without full stop/start is downtime-inducing deploy.
38. Declare `MONITORING_CONFIG` exporting `rrd`/`snmp` config so box is watched externally — a box monitoring itself lies about itself.
39. Audit every `acme-client` domain to guarantee cert matches hostname — a cert for wrong domain is TLS failure waiting.
40. Ship `DISASTER_RECOVERY` rebuilding entire box from bare `pkg_add` — a recovery requiring manual at 3am will not happen.
41. Audit `smtpd` to guarantee no open relay — an open relay is spam bot's best friend.
42. Declare `NETWORK_POLICY` documenting every allowed inbound/outbound connection — a network without policy accepts anything.
43. Audit every `rc.conf.local` variable for its default — a variable set to wrong default is bug hiding until fresh install.
44. Ship `CHANGES.md` appended on every deploy — a deploy without changelog cannot be audited.
45. Declare `provides:` in every `rc.d` script so `rcctl` resolves dependencies by capability not script name.
46. Declare `VPS_IMAGE` bootable in QEMU for testing — a deploy that cannot be tested locally can only be tested on the box.
47. Verify every `rc.d` script runs as declared `daemon_user` — a script running as root when it should run as `_pub4ci` is privilege escalation waiting.
48. Declare `set -euo pipefail` at top of every `OPENBSD/bin/` script and test for it — a script without strict mode silently continues past errors.
49. Ship `PERF_TUNING` documenting every `sysctl`/`mount` option and reason — a tuned box without docs cannot be retuned.
50. Declare `SECURITY_AUDIT` schedule — monthly `ssh-audit`, `pfctl -s all`, `pkg_info -m`, `daily.check` — and `vps-deploy` should refuse if last audit >30 days.
51. Audit every `relayd` section to guarantee `block` policy is set on every listen — a relayd section without block policy forwards anything.
52. Ship `TICKET_TEMPLATE` filled on every deploy — a deploy without ticket cannot be tracked.
53. Rotate `ntp` symmetric keys on every deploy — an ntp key never changing is time-source compromise never noticed.
54. Declare `SERVICE_LEVEL_AGREEMENT` mapping every apex to acceptable downtime — a service without guarantee cannot be measured.
55. Every `rc.d` script should declare `START_ORDER` so `vps-deploy` starts box in right sequence — a box starting app before database wastes first minute crashing.

### STUDIO — what would make the media tools a joy to create with

1. `dilla.rb` should ship `dilla.md` explaining the 81 parts in order required, so a new contributor can trace a sound without reading whole file.
2. Every renderer should declare `SAMPLE_RATE` and `BIT_DEPTH` at top so operator knows output.
3. `STUDIO/dilla/renders/` should be migrated into dilla root with `.gitignore` rules, so render pipeline is inside repo where it can be audited.
4. Every `lib/*.rb` support module should declare `__dir__` once at top and use a constant, so moving file does not break path.
5. `DillaSources` should declare `SOURCES_VERSION` matching sample corpus, so mismatch is caught at boot.
6. `dilla.rb` should be split along existing seams — renderers, ENV tables, SMF writers, patch registries — into `lib/` files that require each other in declared order.
7. Every `test_dilla_*` should declare its own timeout so a slow test does not kill whole suite — a suite failing from timeout lies about what passed.
8. Fix `test_dilla_audio_graph_parity.rb` to match current bus-routed graph topology — a test expecting flat `amix` when engine emits routed graph tests wrong thing.
9. `STUDIO/gate.rb` should declare `GATE_VERSION` and test that `lib/engine/` does not reappear — a gate not testing its own condition can be silently bypassed.
10. Every `Outboard.chain` arm naming a module should be tested to verify module exists and is dispatchable — dead arms are dead code looking alive.
11. `samples/dug/` corpus should be documented with `sources.yml` mapping every file to its download URL — a sample without URL cannot be re-fetched.
12. Every `rack` in registry should be deduplicated by checksum so 38 duplicate recordings collapse to 123 unique wavs.
13. `dilla.rb` should declare `LINE_LIMIT` 300 and `bin/check` should enforce it — a file exceeding limit cannot be read.
14. Every `key` in registry should be measured and verified against `KEY_LIBRARY`, so a key out of tune is caught before it renders.
15. Ship `RENDER_SEED` pinning every render to deterministic seed, so "re-render" actually produces same file.
16. Every `vocal_chop` skipping a row should log skip reason so operator knows why vocal is missing — silent skip is silent defect.
17. Declare `DRUM_LOOP_SOURCE` as constant tested to exist before any render — a drum loop resolving to `~/Downloads` is a render depending on file outside repo.
18. Test every `techno_harmony_root` against `HARMONY_VALIDATOR` so most advanced processing is most tested.
19. Declare `RENDER_BUDGET` listing max render time, memory, disk per render.
20. Replace every `__FILE__` with `__dir__` — a file path hardcoding directory breaks when file moves.
21. `postpro/` should declare its own `CONTRIBUTING.md` so a colorist knows grading pipeline without reading source.
22. Every `repligen/` and `lora/` model should declare `MODEL_VERSION` and `CHECKSUM` so corrupted model is caught at load.
23. Ship `GENERATE.md` explaining how to reproduce a specific render — a render without recipe cannot be repeated.
24. Test every `dilla.rb` part manipulating audio with known-input known-output file so transform is verifiable.
25. Declare `SEED_REALISM` guaranteeing every city's demo audio sounds like that city — 39 of 43 cities seeding at 0,0 is map reading as empty.
26. Every `render` should write a `.dilla` provenance sidecar validated at write time — optional provenance is skipped.
27. Ship `RENDER_DIFF` comparing two renders with seeds and reporting dB difference — a render changing without seed change changed by accident.
28. Tag every `sound` with its `GENRE` so a genre-agnostic tool is genre-discoverable.
29. Declare `RENDER_BACKUP` copying every render to off-tree location before it can be overwritten — a render that can be overwritten can be lost.
30. Test every `patch` registry to guarantee patch applies cleanly to target version — a patch failing silently lies.
31. Ship `BENCHMARK` measuring every render's CPU and wall-clock time and failing if it exceeds budget.
32. Every `effect` in chain should be auditable — operator should be able to ask "what effect was applied here?" and get exact module and args.
33. Declare `FORMAT_VERSION` for every output format so a format change is a breaking change that is versioned.
34. Test every `loops` file for its `beats_per_minute` against registry — a loop lying about BPM breaks mix.
35. Ship `RENDER_MONITOR` watching render directory and alerting when render exceeds time or disk budget.
36. Wrap every `plugin`/`external` call in `with_timeout` so a hung external process does not hang whole pipeline.
37. Declare `QUALITY_GATE` asserting every render passes spectral analysis before it is considered done — a render passing without analysis might be silent.
38. Test every `sample` for its `duration` against expected length — a sample shorter than expected drops beats.
39. Ship `RENDER_LOG` recording every render command, param, seed — a render without log cannot be reproduced.
40. Test every `mix` for its `peak_level` and `rms_level` so a clip exceeding 0dB is caught before rendered.
41. Declare `MASTER_RENDER` as canonical reference render for every crate — a crate without reference cannot be judged.
42. Every `dilla.rb` constant appearing in `data/voice.yml` should be read from `data/voice.yml` — a constant also hardcoded is a constant drifting.
43. Ship `CORPUS_AUDIT` verifying every sample in registry exists on disk and is not corrupted — a registry naming a file that does not exist lies.
44. Test every `sfx` bank for its `sample_rate` and `bit_depth` against project settings — an sfx bank at wrong sample rate is pitched wrong.
45. Declare `RENDER_PIPELINE_VERSION` matching `dilla.rb` version — a pipeline not matching code renders sound not matching spec.
46. Test every `filter` for its `frequency_response` against known target — a filter doing nothing lies.
47. Ship `GENRE_PROFILE` for each supported genre defining BPM range, key range, mix rules — a genre without profile is without standard.
48. Test every `envelope` for `attack`, `decay`, `sustain`, `release` against DAW convention — an envelope out of phase hits at wrong time.
49. Declare `RENDER_QUALITY_TIER` (draft, studio, master) so operator knows what level of processing is applied.
50. Ship `RENDER_VALIDATOR` running spectral, temporal, loudness analysis on every output and failing if any metric out of range.
51. Test every `tempo` change for its `time_stretch` algorithm — a tempo change without time-stretch is pitch change.
52. Declare `MASTER_BUS` standard that every render must pass through — a render bypassing master bus has no master.
53. Test every `bus` for its `gain` and `pan` against stereo field — a bus off-center is unbalanced mix.
54. Ship `RENDER_ARCHIVE` compressing every finished render and storing with seed — a render without archive can be lost.
55. Declare `CREATE_QUALITY` asserting every generated sound passes human-in-loop review before finished — an AI generating without review generates garbage.

### The 10/10 MASTER — Muse Spark 1.2 Free vision

The perfect MASTER is a runtime where the constitution is not a file you read
but a surface you interact with. A developer clones the repo, runs
`bin/check --profile=agent`, and the first thing they see is not a sea of red
failures but a clean scan and a single sentence: "The constitution is green.
Here is what the fold found."

It is a runtime where every rule carries its own evidence — the finding count,
the last measurement, the false-positive history — and every measurement is
verified against a known-clean snapshot before it is trusted. A rule that
cannot prove itself is a rule that should not exist.

It is a runtime where the fold spine is measured by its own law, where the
scanner is tested by the rules it scans, and where the constitution is the
first thing reviewed in a code audit — not the last.

It is a runtime where `bin/master` answers a question in a sentence, where
`bin/pub4 gate` tells you exactly which law a change broke and why, and where
`bin/pub4 measure` gives you a number you can trust because it was measured
today, not last week.

It is a runtime where the four trees are four citizens of one constitution,
where `MASTER` governs `RAILS` the way `RAILS` governs `STUDIO`, and where the
OpenBSD box is not a deployment target but a provable artifact — every config
file signed, every service verifiable, every deploy auditable.

The 10/10 MASTER is a constitutional runtime that applies its laws to itself
without exception, where the governor is governed, where every effect is proved
and every verdict is recorded, and where a new contributor can go from clone to
green check without reading a single contract file — because the runtime itself
teaches them what it needs from them. This vision was refined after fixing the
root-invariant violation (SEVEN at repo root), the TODO.md merge-conflict
markers, and the design-system opacity ladder — three files that contained their
own proof of correctness while not being correct, which is the defect this
constitution exists to prevent.

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
