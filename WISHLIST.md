# 112 things one day taught this repo

Written 2026-08-29, from one session's findings. Every item traces to something
that actually happened rather than to general advice — where a claim has a file
and a line, they are named, so a reader can check the reasoning instead of
trusting it.

The session's own record is not flattering, and that is the point. Roughly a
third of these exist because a measurement was wrong, and about half of those
measurements were mine. This tree already says the instrument is wrong more often
than the code; a day of evidence agreed.

**[cheap]** is an afternoon. **[deep]** is a project. **[yours]** is a decision
rather than work. **[done]** landed today and is listed so the pattern is visible.

---

## A · The surfaces have multiplied (1–14)

`MASTER/bin` holds 28 entry points. `CLAUDE.md:50` says "Two surfaces, no third."
Nothing measures the gap, which is how 2 became 28 without a single failure.

1. A ratchet on entry-point count, per tree, in `spine.yml` beside the source-file ceilings. **[cheap]**
2. Break the `check` ↔ `ci` cycle. `bin/check` invokes `bin/ci`; `bin/ci` invokes `bin/check`. Its own comment records the cycle meaning neither could pass for eleven days.
3. Fold the twelve verification commands — check, gate, ci, audit, dogfood, preflight, probe, smoke, smoke-web, test-safety, doctor, nsaudit — into the two sanctioned surfaces. **[deep]**
4. Delete `bin/master`. It is 75 lines, 34 of them comment, and six of behaviour: a `chdir`, one env var, one argument rewrite, `exec bin/cli`.
5. Move that `chdir` into `bin/cli` by resolving its root from `__dir__` rather than `Dir.pwd`, which is the thing the wrapper exists to paper over. **[cheap]**
6. Grep every caller before deleting any entry point — `OPENBSD/`, `RAILS/gates/gates.yml`, rc.d scripts on the box. A command with no callers in this repo may still be in a cron line on vm23.
7. One name for one job: `bin/gate` *is* the scan→fix→critique→review chain and does not say so in its name.
8. A test that fails when a doc's stated invariant stops being true. "Two surfaces, no third" was prose, so it rotted silently. **[deep]**
9. `bin/pub4 test` with no arguments runs **nothing** when STUDIO is dirty — it derives scope from `git status` and aborts on sight of a STUDIO path. In a shared checkout that is most of the time.
10. Make that refusal a skip with a warning, so the other three trees still run.
11. `bin/check --profile=agent` "may fail on known debt" — a profile whose failure carries no information teaches people to ignore it.
12. Publish the profile matrix somewhere a reader can see which profile runs which suite without reading three scripts.
13. Retire `master-core` or say in one line how it differs from `master`.
14. An `--explain` flag on the chain that prints what it will run before running it. `bin/gate` knows it, and refuses a flag it does not know rather than falling through to full-fix. **[done]**

## B · Gates that measure nothing (15–30)

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

## C · Built, documented, and switched off (31–47)

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

## D · The instrument is wrong (48–66)

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

## E · A shared checkout is a hazard (67–79)

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

## F · Documentation that outlived its code (80–92)

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

## G · Sound, and the things that only measure (93–102)

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

## H · Things only money or a person can fix (103–112)

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
