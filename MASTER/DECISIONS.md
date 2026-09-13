# Decisions

Agent and runtime policy. Deploy and VPS policy lives in `OPENBSD/DECISIONS.md`.

This file records intentional shapes that may otherwise look like bugs.

## Portfolio Freeze Aligns With OPENBSD (2026-07)

See `OPENBSD/DECISIONS.md` — **No Fourth Public App Until brgen Boundaries
Hold**. MASTER work should prefer subtraction (one generated agent context,
structural vs cosmetic scan severity) over new portfolio apps. Do not invent a
seventh product surface from agent sessions without that ADR being revisited.

## Enforcement Is On The Write, Not On The Command (2026-08-15)

`/scan` and `/fix` are diagnostics now, not the enforcement path. Every write
goes through `Review::Scan::WriteGuard` on both lanes — `Io::Base#commit_write`
for the tools, an injected `:write` rule in `Core::Constitution` for the Fold —
and a write that introduces an error-, critical- or veto-severity finding is
refused with the findings as the reason.

Three shapes here look wrong from outside and are not:

- **It judges the delta, not the file.** A file already carrying a violation
  stays writable; only a new one blocks. Blocking on file state would refuse the
  first repair of every file that needs repairing, which is the opposite of the
  ratchet intended.
- **Semantic rules are excluded.** 126 of the 225 need an LLM, at one call per
  file, and a before-and-after gate pays that twice per write. They belong to a
  per-turn pass over the files a turn touched. Until that exists, the semantic
  half of the law still waits for `/scan`.
- **The Constitution takes the scanner as a parameter.** `Constitution.load`
  accepts `verify:` and `lib/cli/core_bridge.rb` supplies it. A `require` would
  have been shorter and would have put `lib/review/` inside the fold spine,
  which `test/test_core_no_lib_backedges.rb` exists to prevent.

Six stages were deleted to pay for it, and every one was constructed nowhere or
only by another of the six. `Stages::Guard` scanned messages for prompt
injection — `Builder::AiBoot` still runs `InjectionGuard`. This sentence named
`Ground::Tool::Contract` as a second runner until 2026-08-25, and it never was
one: nothing called that module, its gate fired only on tool names no live tool
has, and its `:strict` mode is default-deny, which would have refused `ls -la`.
It is deleted; the guard that runs is `:permissive`, in AiBoot, alone.
`Stages::Deliberate` wrapped a coding message with "list four approaches first"
— `Proof#ideation_satisfied?` enforces that at the gate now. `Stages::Review`
orchestrated the other three and was built by nothing. `Stages::Lint` scanned
written paths after the fact, which is `WriteGuard`'s job and now happens before
the write. `Stages::Prune` duplicated `Voice::StrunkPass` constant for constant,
both loading `voice.strunk` from `data/voice.yml`; the one thing it had that
StrunkPass does not is a prose-level evidence nag, and `evidence_for_done_rule`
blocks the effect rather than annotating the sentence. `Stages::Council` existed
so `/review on|off` could toggle a flag on it; the deliberation subsystem it
wrapped is live and reached three other ways — `Stages::DestructiveReview`,
`CouncilCrit` behind the Fold's `critique` verb, and `/critique`. `/review
<path>` still runs the reviewer personas, which is the only thing that command
ever did that ran.

`lib/` fell 392 code lines, from 39222 to 38830.

## One Spine, With The Dependency Rule Kept (2026-08-12)

**This reverses "Two Master Spines", which stood from 2026-07-30 to 2026-08-12
and is superseded by operator instruction.** The prior text is below the line,
because a decision that was reversed is more useful than a decision that was
quietly deleted.

`core/` is now `lib/core.rb` + `lib/core/`, autoloaded by the same Zeitwerk
loader as the rest of `lib/`. The path-to-constant mapping already wanted
exactly this: `push_dir(lib, namespace: Master)` makes `lib/core.rb` →
`Master::Core` and `lib/core/fold.rb` → `Master::Core::Fold`. The merge needed
no new entries in `data/autoload.yml` — `rake lint:autoload` still reports 44
ignores, all necessary.

Two things the old split was carrying, and where each went:

- **The dependency direction survives, as a test.** The fold must not reach into
  the application spine. A directory boundary used to hold that; today
  `test/test_core_no_lib_backedges.rb` holds it, naming the fold's files
  explicitly and fails if any of them requires a sibling under `lib/`. It also
  asserts it found the files at all, since a glob that matches nothing passes
  silently.
- **`core_files` survives, counted differently.** `lib/{core.rb,core/*.rb}` —
  the directory plus the entrypoint beside it. Globbing only `lib/core/` would
  have read one under the ceiling and handed out a free concept. It stood at 6
  through the merge and was raised to 7 <!-- cite:
  data/spine.yml#spine.core_files --> on 2026-08-12 for `Proof`.

What the merge removed, beyond a directory: `MASTER/bin/master-core` put `core/`
on `$LOAD_PATH` and called `require "master"`, so which of the two `master.rb`
files won was decided by load-path order. `bin/nsaudit` had to hand-require the
second spine so the first one's constants would resolve. The two files survive
but as nothing special: the dangerous half of each — the `unshift "../core"`
that made the load-path order decide the winner — is gone, and both are now the
ordinary `lib/core.rb` entrypoint.

`lib_code_ceiling` was rebaselined 38285 → 38811 and **not** recorded as a
raise: 554 code lines moved in, `lib/` reports +526, so excluding the moved
files `lib/` fell 28. The arithmetic is in `data/spine.yml` so the claim is
checkable rather than asserted. It was raised three times after that: once for
`Review::Scan::CodeMetrics` — one line counter where there had been three — once
to close the fold-spine findings the merge exposed, and once for `d35b40ec0`'s
`worn_type` accessors, which took an operator decision to clear the raise log
because nothing was left to absorb.

The figure that used to sit in that sentence is deliberately gone. It carried a
`cite:` marker, so `rake lint:doc_citations` held it to the value `data/`
currently holds — and the sentence is about a past sequence, so every subsequent
raise made a true statement about history read as a false claim about now. It
drifted within two days and failed the gate. `data/spine.yml` has the number and
the whole log; this paragraph has the story.

---

*Superseded 2026-08-12 — retained for the reasoning, not as current policy:*

> `lib/` and `core/` are intentionally separate load paths. `lib/` is the gem, CLI, loop, judge, reach, trace, voice, and web-facing runtime. `core/` is a small isolated constitutional fold loaded on its own path by the core tests and `MASTER/bin/master-core`.
>
> Core types live under `Master::Core::` (not top-level `Master::`) so they coexist with lib constants in one process — the runtime cutover loads `core/` into the CLI via the bridge. `bin/nsaudit` loads the core entrypoint explicitly; the two-spine design is deliberate, not accidental duplication. (The module was named `Master::Kernel` until it was renamed to `Master::Core` to stop shadowing Ruby's built-in `::Kernel`.)
>
> Namespace tooling should treat `MASTER/bin/master-core` as the core load entrypoint.

## The Spine Ratchet Replaces An Unmeasured Invariant

`core/ABSORPTION.md` asserted "the spine never grows" and nothing checked it.
In the three weeks after `core/` landed, `lib/` gained 8,022 lines and `core/`
gained none. It was renamed `docs/SEVERANCE.md` and then deleted with the rest of
`docs/` in `3e2f32f76`, so this document is the standing policy on the spine and
there is no second one to consult.

What is enforced instead: `rake lint:spine` reads `data/spine.yml` and fails
when `lib/` grows past its recorded ceiling or the fold spine gains a file. The
ceiling only ratchets down (`RATCHET=1` records a new low); raising it is a
deliberate edit with a reason in the commit. Part of `rake audit`.

### The invariant, settled 2026-08-11

The ceiling has now been raised three times (2026-07-31, 2026-08-01, 2026-08-11)
and its unit changed once. `data/spine.yml`'s own note said that if it were
raised again without `lib/` ever falling back, "the honest conclusion is that
'the spine never grows' is not the invariant anyone is holding". `lib/` did fall
back twice, by deletion — and on the third raise there was nothing dead left to
pay with: a sweep of all 445 files returned one candidate and it was a false
positive.

So the sentence is retired and replaced by the two things that are actually
true:

- **`core_files` is the invariant.** A new top-level concept in the fold is a
  design change and must be argued for. It is what "the spine" means.

  *Amended 2026-08-12.* This bullet used to end "This has never been raised and
  should not be." It has now been raised once, 6 → 7, for `Master::Core::Proof`
  — and the raise is the mechanism working rather than failing. `Memory`
  measured 16 public methods against ABSTRACTION's 10 and could not be brought
  under it by declaring visibility the way `Constitution` could, because every
  method had a caller. The count was telling the truth: Memory was a transcript,
  an evidence ledger, and the risk gates wearing one name, and the Constitution
  reached past the first to ask the other two. The invariant did not stop the
  seventh concept; it made the seventh concept get argued for, which is all it
  was ever able to do. What it must keep refusing is a file added because
  something felt long.
- **`lib_code_ceiling` is a budget with a sponsor, not a promise.** It exists so
  growth is visible and has to be asked for. A raise needs a named sponsor and
  the per-commit accounting in `spine.yml`; `consecutive_raises_allowed: 2`
  refuses the third until `lib/` genuinely falls.

  *Amended 2026-08-13.* That refusal fired for the first time, and what it
  caught was somebody else's 9 unaccounted lines with nothing left to absorb —
  three sweeps for dead code came back empty. The operator cleared the raise log
  by decision rather than by a fall, which is a turn of the mechanism taken by
  hand and is recorded as a single dated event in `spine.yml`.
  `consecutive_raises_allowed` stays 2 and nothing about the mechanism is
  weaker. The refusal worked exactly as intended: it converted a silent bump
  into an argument.

Nothing about the mechanism changes — this only stops the file claiming an
invariant that three raises have already disproved. A number nobody believes is
worse than a budget everybody reads.

## Worn Type Is What The Visitor Sees (2026-08-12)

`design_rules.yml` already stated Bringhurst's 66ch, a modular scale, a golden
split, and Vignelli's one-accent budget. `design_metrics` grepped stylesheets
for those numbers. A 600px feed — `feed_max`, in `shared_chrome` and `social` —
is at brgen's 18px root a short measure (~45ch), not 66ch, and the two sources
disagreed in silence.

The law is now `worn_type:` in the same file.
`RAILS/gates/support/geometry_type.rb` is the reader: it takes the probe's worn
characters, computed sizes, baselines, tabular figures, accent hues, empty
ratio, and main/aside split, and judges each surface under a named profile
(`feed`, `catalog`, `chat`, `immersive`, `map`, `legal`, `auth`). `--feed-max:
600px` stays the feed column. `measure_body: 66ch` stays the legal/prose column.
They are different jobs.

`Master::Design::Thresholds.worn_profile` is the Ruby face.
`MASTER/test/test_design_rules_worn_type.rb` fails if a profile has no reader.

## Rule Data Folded Into One File (2026-08-12)

**This reverses "Rule Data Stays Split", by the same operator instruction as the
spine merge.**

`data/rules.yml` is the whole scanner law: all 225 rules under one `rules:` key,
in the four scopes the scanners already asked for by name (`codebase` 52, `file`
21, `line` 80, `unit` 72). The four `data/rules/*.yml` shards are gone, and so
is `merge_rule_shards` in `lib/boot/data.rb` — the loader now reads one file.

The fold was textual rather than a Psych round-trip, so every comment in the
shards survived; a YAML load-and-dump would have stripped the lot, and those
comments are where the rules explain themselves. `Master.load_rules` was proved
deep-equal to its pre-fold output before the shards were deleted.

The old entry's argument was proximity to consumers. It did not hold up: the
shards had **one** consumer between them — `load_rules`, which concatenated all
four back into a single hash before any scanner saw them. The split was
proximity for readers, not for code, and it cost a directory plus a merge step
that could disagree with itself.

`data/llm_output_rules.yml`, `data/rule_deps.yml` and `data/biases.yml` were
kept out on that argument -- each has its own consumer. They folded anyway, on
2026-09-04, for the reason the next paragraph already gave.

`data/design_rules.yml` had one too, and folded anyway: proximity to a consumer
is worth less than a single definition. Split from `style.yml`, it defined
`typography` twice with different numbers, under a `SelfTest` exemption that
named the duplication and allowed it.

## MASTER Is Shaped After Synthesis, In dilla's Vocabulary (2026-09-13)

Edge returns a bare neural voice at roughly broadcast level and no shaping of
its own, so every decision about how MASTER sounds past the choice of mouth
is post-processing. `data/voice.yml` `tts.post_chain` is that decision, read
by `Voice::Policy.post_chain`, applied by `Speech#shaped`, and carried in
`browser_payload` so the face shapes the same way the server does.

**The chain is dilla's, borrowed rather than invented.**
`STUDIO/dilla/dilla.rb:2719` carries a vocoder wash built as three resonant
peaks near the vowel formants — 520, 1480 and 2520 Hz — and its own comment
says it is only the formant *half* of a vocoder, "because a real vocoder
needs a modulator the renderer does not have". A speaking voice is that
modulator. Those peaks were tuned for a synth pad and land on speech for the
first time here: they sit where a voice already puts its energy and lift it.

**Order is the load-bearing part.** `loudnorm` before the gain, gain before
the limiter. Normalising first brings quiet sentences up to meet loud ones
rather than only lifting peaks; gain after a limiter is distortion rather
than loudness. `test_the_post_chain_is_read_and_applied` asserts both
orderings, because a later tidy-up would reorder them without hearing it.

**A missing effect costs the effect, never the sentence.** `shaped` returns
the unprocessed file on any failure — no ffmpeg, a bad filter, a zero-byte
result — and `Policy::FALLBACK` carries a nil chain, so an unreadable
voice.yml speaks dry instead of crashing.

**`tts.bed` is a musical bed under the speech**, so a pause is not silence:
dilla's own `maj7_minor_cycle` (Dbmaj9, Cm9, Fm9, Bbm9) from
`CHORD_PROGRESSIONS`, which the engine lists under
`ARTIST_VERIFIED_PROGRESSIONS`. Borrowing a verified progression rather than
inventing one is the difference between a bed and a drone. It is declared
here and **rendered by whoever plays it** — the web face and a terminal
narrator mix audio in entirely different ways, and a renderer in this file
would serve neither. `-14dB` and not lower: at `-26` it mixed correctly and
was inaudible, which is the same as not running.

Nothing in `STUDIO/dilla` was touched. dilla writes real takes with rotating
seeds and its renders are irreplaceable; what is borrowed is its vocabulary,
never its renderer.

## Two Voices, Declared (2026-09-13)

MASTER speaks as Jenny or Christopher, chosen at random for each utterance,
on the operator's ask. `data/voice.yml` `tts.rotation` is the list and the
only place it is decided.

**`single_voice` is not retired, and that is the point.** It stays `jenny`,
every reader still agrees with it, and a `rotation` of fewer than two entries
leaves `voice_for_utterance` returning exactly that one name — so the whole
change reverts by deleting four lines of YAML, and nothing downstream has to
know it happened. `test_voice_rotation_is_additive` holds that clause
specifically, because it is the half a later cleanup would drop.

**It is not a persona list.** `persona_affects_text_only` is still true:
personas change what is said, a rotation changes which mouth says it. The two
were kept separate deliberately when the single-voice policy was written and
they stay separate now.

**Random, not round-robin.** A session is not a sequence anybody counts, and
strict alternation makes the pattern audible — which draws attention to the
mechanism rather than the words. `MASTER_TTS_VOICE` still wins outright: an
operator naming a voice by hand is asking for that voice, not for a lottery.

`browser_payload` carries the list, so the face rotates with the server
instead of drifting from it — the failure mode the previous record describes,
where a name lived in more places than the value.

## The Voice Is Data, And No Test Asserts Its Name (2026-09-12)

MASTER speaks `en-US-JennyNeural` — US English, female — on the operator's ask.
It spoke `en-NG-EzinneNeural` before that and `ms-MY-OsmanNeural` before that,
and each change cost fourteen files because the name was written in fourteen
places rather than read from one.

`data/voice.yml` `tts.single_voice` and `tts.neural` are the decision. Everything
else cites them: `Voice::Policy::FALLBACK` is the unreadable-file case and has to
be kept in step by hand, the browser reads `Policy.browser_payload`, and
`soul.yml` carries `voice`, `tts_voice` and `language.dialect` because the
constitution describes the speaker.

Two things changed shape with the name this time. `test_yaml_registries.rb` no
longer asserts any voice name; it had shipped the suite red on `origin/main`
twice by measuring a spelling, and what it holds now is that every reader agrees
with `voice.yml` — which is what actually broke each time. And `default_rate`
went back to `+0%`: `-4%` was measured by ear on Ezinne, and rate and pitch
tuning does not survive a voice change, so carrying it forward would repeat the
`-20Hz` that was picked for en-GB Ryan and ended up on a Norwegian voice.

`VOICE_IDLE_SIGNATURES` has no `jenny` row in either `lib/voice/expression.rb`
or `face.part1.txt`, on purpose. Nobody has heard the voice yet, and the two
fallbacks are identical, so both sides idle alike. Add a row to both or neither.

## Phrase Rhythm Ships On, Phrase Language Ships Off (2026-08-17)

`Melody` plans phrase segmentation, inter-phrase rests, a pentatonic pitch
contour, and — since this date — a per-phrase voice. Three switches, not one,
and the asymmetry between them is deliberate:

- **`phrase_rhythm_enabled: true`.** Segmentation and rests are rhythm, which
  every utterance wants. They used to sit behind `melodic_threshold` with the
  contour, so ordinary speech was one Edge call at one rate and one pitch.
- **`melodic_threshold`** still gates the pentatonic contour alone. That is a
  stylistic mode and belongs to lyrical text only.
- **`phrase_language_switching: false`.** `data/voice.yml` sets `single_voice:
  jenny` and `persona_affects_text_only: true`. Reading a Norwegian clause with
  `nb-NO-FinnNeural` means two voices in one utterance, which is the one thing
  that contradicts that policy. The mechanism is built so the choice is a flag
  rather than a rewrite; flipping it is an operator decision about identity, not
  a bug fix.

Do not "fix" the asymmetry by aligning the three defaults.

## Transcendent Is Not Wired To The Streaming Path (2026-08-17)

The Transcendent engine chain is unreached — see `TODO.md`, the MASTER debt
records, "Inert law and config". The obvious repair is to call it from
`synthesize_streaming_to_file`, and that is wrong as stated:
`Transcendent.synthesize` returns a finished file, while the streaming path
exists to hand `TtsJob` progressive chunks through `on_chunk` so audio starts
before synthesis ends. Wiring one to the other means buffering the whole
utterance first, which trades the thing the streaming path was built for.

So the choice is a real one — progressive playback, or
emotion/melody/multi-engine — and not a missing line. Whoever makes it should
measure phrase fan-out first (one Edge round trip per phrase, on one vCPU); that
measurement is still owed.

## Pronunciation Is Respelling, Not Phonemes (2026-08-17)

`data/lexicon.yml` maps written forms to spoken ones — `relayd` to `relay D` —
rather than to IPA or SSML `<phoneme>`. That is not a shortcut. `rb_edge_tts`
takes plain text and exposes no SSML, so there is no phoneme element and no
engine-side lexicon to address; substituting a word the voice already says
correctly is the only pronunciation control that exists on this path.

The table is therefore narrow on purpose, and `test_lexicon.rb` refuses any
entry that respells a word as itself. Before extending it, check whether the
word is actually wrong when read aloud — "Falcon" and "Rails" are ordinary
English words and do not belong there.

## Names State The Assertion, Directories State The Precondition (2026-08-17)

Two rules, meant for the whole tree and not only for `RAILS/gates/`.

**A name says what the thing asserts, not what it is near.** `geometry` and
`layout_geometry` were one gate that measures boxes in a browser and one that
greps SCSS for a string, and the pair invited the reading that touch targets
were covered. They were not: the grep matched the literal `44px` while the tree
writes `var(--tap-min)`, so it passed on every app while checking no app. They
are `rendered_geometry` and `first_screen` now.

**Each gate owns one assertion.** Two gates asserting the same property is two
places to change it and two places for it to rot. `RAILS/gates/lib/` was sliced by
mode — first screen, phone width, width sweep, keyboard, baseline — and every
mode then re-asserted whatever it happened to see: touch targets in three gates,
landmarks in four, overflow in four. Slice by assertion and the mode becomes a
parameter.

**MASTER names the law; RAILS names the measurement.** The Rails gate called
`reflow` measured horizontal overflow and restated 320px as "the WCAG 1.4.10
floor" — while `MASTER/lib/ground/axioms.rb` already declares that
criterion and `REFLOW_WIDTH_PX = 320`. `soul.yml` uses "reflow" for a third
thing, a refactoring verb beside "rename". A gate named after a criterion
invites the criterion to be re-declared inside it, which is this tree's dominant
defect wearing a new hat. Name the gate for what it measures and have it read
the number from MASTER.

**A directory says what the thing needs before it can run.** `RAILS/gates/lib/` is
`source/ live/ rendered/ host/ research/ meta/`: files only, a booted app, a
browser, the machine, scores rather than verdicts, and gates about gates. The
precondition was previously a comment, and a gate with a missing precondition
reported a clean pass — see the exit-3 work in the same day's commits.

**A directory tree and a declared hierarchy must not be two sources.**
`gates.yml`'s `covered_by` and the directory both classify a gate. If they can
disagree they eventually will, so `covered_by` is derived from the path, never
maintained beside it.

## Local Knowledge Stays Local

`knowledge/` is gitignored and skipped by scanners/snapshots, but it still
powers `Master::Io::SearchKnowledge`. Do not move it unless the search tool
learns the new location first.

## Deferred WebGL Boot Is Sacred

The face runtime must not create a WebGL context before the primer tap. The
guard in `web/app/views/chat/index.html.erb` protects the tap-to-start path from
eager or stale assets.

## Self-Test Is A Loud Gate

`rake selftest` runs `rules.yml.self_test` against MASTER itself. It is allowed
to fail while known debt remains; the point is to make debt visible and
triageable.

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
  `PATTERN_CACHE_MAX = 512`, `BINARY_SAMPLE_BYTES = 512`, `rag_chunk_tokens:
  512` and the phrase "512-token" in a comment — four meanings, three of them
  already named. The rule fires on the definitions of the constants it
  recommends extracting.

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

## The Pixel Field Was Law Nobody Read

`design_rules.pixel_field` — 150 lines, ten subkeys — is deleted, not
deprecated. It mandated ordered dithering, limited palettes, 320x180 internal
resolutions, and a thirteen-entry table mapping semantic states to visual cell
forms (checker-dither means uncertainty, pixel-spray means entropy).

Two facts decided it. Nothing read it: `pixel_field`, `semantic_cell_fields`,
`cell_grammar`, `systemic_emotion_mapping`, `bitmap_not_retro`, `runtime_modes`
and `explainability` return zero hits across MASTER, RAILS and STUDIO outside
the YAML itself, so no scanner, gate or prompt has ever applied it to brgen,
amber or bsdports. And it contradicts the direction the operator chose on
2026-07-18, when the IRIX/8-bit/pixel-field aesthetic was dropped for flat
brutalism — the section was still instructing anything that read it to build the
aesthetic that had been abandoned.

Its only live agreement with current direction, no blur or bloom or glow, is
already stated four other ways: `pixel_perfection.forbidden_css`,
`ui_polish.flat_ui`, `soul.yml FLAT_UI`, and the executable `NO_DECORATIVE_FX`.
Deleting it removes no enforcement.

The wider finding it came from stands as debt: five of thirteen `design_rules`
subkeys were wholly inert, and the same value is legal at two different paths in
three places (touch minimum at `ux_laws.fitts` and `layout_rules.touch`; the
spacing scale at `pixel_perfection.eight_px_rhythm` and `layout_rules.grid`),
which is why `Design::Thresholds` reads them as fallback chains. Deduplicating
those requires editing every reader and is not this commit.

## The Law Reads Whole Where It Sits — 2026-09-10

**Status:** accepted. This closes "aggressively DRYing the law wants a measured
pass", which sat in `TODO.md` from the 2026-08-31 session with nothing measured
behind it.

Measured: `data/rules.yml` declares 242 rules and **zero** of them share a body.
Compare every rule with its `id`, `name` and `description` removed and there are
242 distinct bodies — so the repetition a reader notices is field names and
scalars (`severity: error`, a `source:` string, a `tier:`), not rules that could
collapse into one another.

Folding those behind YAML anchors would buy line count and cost the property the
file exists for. `CLAUDE.md` tells every agent to read the law **one rule at a
time**, id by id, holding each before moving to the next, and the exemption is
the half that gets skipped. A rule whose severity, tier and exemption live at an
anchor three hundred lines away does not read whole where it sits, and the reader
who skips the jump has skipped exactly the half the instruction is about. The
file has three anchors and sixteen aliases today, all outside `rules`; that is
the right amount.

**Consequences:** a rule stays spelled out. Reopen this only with a duplicate
*body* to point at, not with a line count.

## LAYER_CAKE And DEAD_ABSTRACTION Are Not Built (2026-09-10)

Both were drafted, run over the tree and left blocked on a cross-file symbol
index. Neither waits on the index. Both were measured again on 2026-09-10 and
the measurement decides them.

`LAYER_CAKE` looks for a chain of sibling methods each of which only forwards.
At three links, the honest threshold, this tree has none. At two it finds nine,
and reading the nine says why two is the wrong number: three are
`rescue_handlers.rb` naming one exception each before forwarding to
`render_http_error`, which is the shape `rescue_from` requires, and the rest —
`ok? -> ok`, `unwrap -> value!` — are aliases. A two-link forward is an alias.
A real layer cake spans files, so the cross-file index would be a prerequisite
rather than the obstacle; nothing in the per-file reading suggests the index
would find one. A rule that fires on nothing lands in `rule_audit.silent`, which
is a ratchet at its ceiling, so building it costs a ceiling point and buys no
finding.

`DEAD_ABSTRACTION`'s module half is a false-positive machine and must not ship
as written: 367 of 419 modules that define methods are included at most once,
because nearly every module here is a `module_function` namespace rather than a
mixin, so the census measures Zeitwerk's file-to-constant mapping.

**Its class half was recorded as one finding and there are none.** A Prism walk
for classes whose every method body raises `NotImplementedError`, proved first
against a planted file carrying one implemented and one abandoned base, finds
zero over `lib/`. The tree holds three abstract method declarations in all —
`Ground::Orders::Base#call`, `ReviewCrew::BaseAgent#analyze` and
`Scan::Rule#check` — and the first two carry six implementers each. The refused
bequest in the other direction, a subclass raising `NotImplementedError` over a
parent that implements, already has a detector in `LiskovRule`.

Reopen either only with a finding in hand. The bar is a subject in the tree, not
a design.

## The Five Larger AST Projects Are Four Refusals And One Duplicate (2026-09-10)

They stood in `TODO.md` as multi-session projects, each a design with no
measurement under it. The measurements decide four and reveal the fifth.

**A cross-file AST / symbol index.** Its named consumers were
`DEAD_ABSTRACTION` and `LAYER_CAKE`, both refused above, and the rest of its
case is "who implements this" and "who calls this". `tools/method_graph.rb`
already answers the second across every file in `lib/` — every method a node,
every identifier in a body an edge, rooted in the names used outside `lib/` —
and thirty lines of Prism answered the first while refusing
`DEAD_ABSTRACTION`. Building an index for consumers that no longer exist is
the speculative generality the rule catalogue names.

**An incremental scan cache keyed on file SHA.** No bottleneck. A full scan of
`lib/` is 13.0 seconds over 410 files, about 32 milliseconds each; the minutes a
`/through` pass spends are the council reaching a provider, which no file digest
shortens. A cache carries an invalidation surface, and this one would buy
seconds off a task nobody waits on. `biases.premature_optimization` asks for a
measured bottleneck first, and the measurement says there is none.

**tree-sitter for real JS and SCSS ASTs.** The gain is real: those rules are
lexical because no parse tree exists for them here, and a tree retires whole
classes of false positive. The price is a native extension in the tree whose
first sentence is that it is a constitutional AI runtime in pure Ruby, deploying
to OpenBSD, where every added build dependency is a deploy hazard. Prism is in
the stdlib and covers the language MASTER is written in. Reopen this only as an
operator decision about what MASTER is, not as a scanner improvement.

**A clone to extract-method autofix.** `DUPLICATE_CODE` detects and nothing
extracts, and there is almost nothing to extract: `COPY_PASTE_BLOCK` finds one
group in all of `lib/` and the structural `DRY` rule three cross-file groups, of
which `repo_ecology#grade_for` against `context_pressure#band_for` is two banding
functions over different domains sharing a `case` shape. Against three subjects,
a transform that rewrites method boundaries is the worst risk this pass could
take: `/scan`'s autofix has damaged one file in three on a trial run, and both
mangles passed a syntax check.

**Prose, CSS and audio detectors.** Already built, twice over. `law/prose.rb`
generates its detectors per natural language from `data/rules.yml`, and
`law/css.rb` judges stylesheets by declaration. The audio half — dilla's render
graph — belongs to dilla's owner, whose renders are irreplaceable.

## A Worktree Is A Checkout (2026-09-10)

Seven readers asked whether a directory is a git checkout by testing whether
`.git` is a directory. A `git worktree` checkout keeps `.git` as a *file*
holding one `gitdir:` line, and `CLAUDE.md`'s first trap tells every agent
working here to take a worktree — so each of the seven answered "not a
repository" in the trees the runtime mostly runs in, and every one of them
failed by going quiet.

- `Fix::Rollback#git_workspace?` — a failed fix was never rolled back.
- `Ground::BootReceipt#capabilities` — `git` read false, so `degraded` listed a
  capability the process had, on every boot in a worktree.
- `Ground::BootReceipt#commit` — it opened `<root>/../.git/HEAD` by hand, which
  does not resolve when `.git` is a file, and the receipt whose first field is
  the commit reported `unknown`.
- `Trace::Snapshot::Collector#git_repo?` and `Publisher#git_summary` — a
  snapshot lost its tracked-path collection and its branch and sha line.
- `Trace::Snapshot::Publisher#output_dir` — this one was wrong twice. It counted
  three `..` from a file that had since moved a directory deeper, landing on
  `MASTER`, which holds no `.git` at all; and the directory test would have
  failed at the real root anyway. Every snapshot taken inside a checkout was
  written to `~/Downloads`. Both existing tests set `MASTER_SNAPSHOT_DIR`, so
  the branch had never run.
- `RepoEcology::CoChangeGraph#git_head_mtime` — the read raised, the rescue
  answered 0, and one constant key is a cache that never invalidates.

`Master.git_checkout?` is the one predicate now, and it tests existence.
`commit` and `git_head_mtime` ask `git rev-parse`, which answers for both
shapes. The test carries a clone and a worktree side by side, because a fixture
with only one of them is how this stood.

`Io::GitHooks` is deleted rather than fixed. It wrote a `pre-commit` hook into the private git directory
from the boot path, and `bin/operator hooks` — the installer `CLAUDE.md` names —
sets `core.hooksPath` to `OPENBSD/dev/githooks`, which git honours *instead of* the
private hooks directory. So on any tree carrying the documented guard the file it wrote
could never run, and on a tree without one it silently installed a slow audit on
every commit that nobody asked for. Its own comment in `bin/operator` says why: a
copy in the private hooks directory is a second implementation that drifts from
the tracked one.
Its only test asserted that it skips when there is no git directory — a test of
the inert path, which is what let it stand.

## The Fold Keeps Its Own YAML Read (2026-09-11)

`Core::Constitution.load` calls `YAML.safe_load_file` on `data/rules.yml`
directly, and `Master.load_rules` in `lib/boot/data.rb` is the canonical loader
for that file everywhere else. An external review read that as a one-source
violation and proposed replacing the direct read with the loader. Declined.

The fix is backwards. The dependency rule from "One Spine, With The Dependency
Rule Kept" runs one way: the fold must not reach into the application spine.
`Constitution.load` takes `verify` and `sandbox` as arguments rather than
requiring them, and the class comment says why twice — the spine reaches nothing
in `lib/`. `load_rules` lives in `lib/boot/data.rb`, so taking the suggestion
would make the constitution the first file to break the only structural rule the
fold has.

What the loader adds over the direct read, in full: a 10 MB size limit on a
205 KB file, a 20-second timeout on a local read, permitted classes for a file
that holds no `Date`, and a quiet-if-absent branch for foreign roots that has no
meaning here. It performs no shard merge — it is `load_yaml` with a path — so
the two paths return the same object today. The one real divergence is the
permitted classes: a date added to `rules.yml` would load through `load_rules`
and raise through the constitution. That is a reason to keep dates out of
`rules.yml`, where there are none, and not a reason to invert the fold's
dependency direction.

`test/test_core_no_lib_backedges.rb` holds the boundary by inspecting `require`
lines. A Zeitwerk-autoloaded call to `Master.load_rules` needs no `require`, so
the test would not have caught this one — which is why the argument is written
here rather than left to the gate.

## One Word Per Concept (2026-09-11)

Two words for one concept means a reader cannot tell whether they name the same
thing, and a search for one misses the other: `law/` and `rules.yml` held the
same kind of object under two names for months, and `law_bridge_rule.rb` still
uses both in one filename. The winner is the word already dominant in the tree,
because a rename costs less when it moves the minority.

**rule** wins, and `law`, `axiom`, `principle`, `convention`, `guideline`,
`philosophy`, `doctrine`, `heuristic`, `standard` and `norm` lose. Measured
across `MASTER/{lib,law,tools,bin}`: rule has 1,504 mentions over 35 paths, law
356 — and law owns `law/`, which is the one real cost of the choice. `policy`
is deliberately not on the losing list: `Ground::Policy` is runtime
authorisation, a different concept that happens to be an English synonym.

**check** is the unmeasured half, written down so the next person measures it
rather than guesses. `gate` reads as a release gate, `lint` as a source pass and
`probe` as a live request, which may be three real distinctions or three words
for one act; `audit` and `verify` sit with them.

This lived as a `synonyms` block in `data/lexicon.yml`, which `Voice::Lexicon`
opens for `respellings` and nothing else, so a naming policy sat inside a
text-to-speech table with no reader. It is prose about how to name things, and
prose belongs where prose is read.
