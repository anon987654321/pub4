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

The Transcendent engine chain is not on the streaming path — see "An Unread-Key
Gate Is Not Buildable Here" below for the config it does read. The obvious repair
is to call it from
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

## The Public Face Is The Product, So Its Endpoints Stay Open (2026-09-13)

`GET /chat/enhance`, `/chat/research`, `/chat/skills` and `POST /chat/photo`
stay reachable by visitors. The face at ai.brgen.no is a public chatbot, and a
visitor already spends more through `POST /chat/message` than any of these
cost. They are fetched by script and linked from nowhere, so no prefetcher or
crawler finds them, and each sits under a per-IP rate limit. Moving them to
POST or behind auth would change the face's JavaScript for no measured abuse.

`require_same_origin!` accepting a request with neither Origin nor
`Sec-Fetch-Site: cross-site` is not a CSRF hole. Every browser that carries a
victim's cookies sends one or the other on a POST; a request with neither is
curl, and curl has no victim session to ride.

The TTS job id is a hash of voice and text on purpose: identical lines share
one synthesis and one cache entry. Guessing an id requires knowing the
utterance, and the mp3 holds nothing beyond it. Pending jobs still check
ownership, which is where a random id would matter.

`production.rb` accepting any Host is sound here. Falcon binds loopback only,
and relayd forwards only `Host: ai.brgen.no` to it; unmatched hosts go to
brgen. The allow-list already exists, one hop earlier.

## What The Runtime Keeps Process-Wide, And Why (2026-09-13)

`/mode` writes `.master/mode` and sets `MASTER_MODE` for the process. Posture
is the operator's, not a visitor's, and the file is shared by every process
anyway, so a per-request posture would be a second, weaker source.

`SqliteStore` falling back to `:memory:` is right for its one user,
`KnowledgeStore`, which is a rebuildable index over gitignored files. Pairing
and memory are YAML under `.master/`, not SQLite, and never reach that
fallback.

An SSE MCP server is not passed through `SsrfGuard`. `mcp_servers.yml` is
operator configuration that can already name a stdio command, which is more
than a URL can do, and the ordinary SSE server is on loopback, which the guard
would refuse.

`Timeout.timeout` around a socket read is kept. A blocked read is
interruptible and the socket's block closes it as the error unwinds; what does
not survive `Timeout` is a child process, and `Io::Exec` and `Core::World`
already handle those by process group. `read_timeout` alone cannot bound a
server that drips one byte inside every window.

## Agent Harnesses Are Read, Not Wired (2026-09-13)

OpenClaw, OpenCrabs, Hermes, OpenCode, Aider, Cline, Goose, OpenHands, Warp
and Continue were read against source in September 2026. MASTER takes ideas
from them and speaks none of their protocols. No ACP stdio mode, no A2A or
OpenAI-compatible `/v1`, no `opencode run` or `codex` behind `Io::Exec`, no
models.dev scrape, no npm SDK, no editor extension, no desktop app, no hosted
eval farm, no registry of skills. Each would make MASTER a backend to someone
else's policy, which the constitution forbids, or add a second surface beside
`bin/master` and the face.

The same pass rejected, by name: Docker, Modal and Daytona terminal backends
(isolation is `operator worktree`); ClawHub and any unsigned or
VirusTotal-admitted skill; native companion apps, screenshots and VNC workers
(the face is the companion); paid tiers and prompt collection; advisory counts
as a safety score; and any learning loop that writes `soul.yml`, which is
immutable. Continue is read-only since Cursor absorbed it, so it is not a peer
to follow.

What was worth taking is either built or open in `TODO.md`: bounded SSE
queues, prefix compaction under the session lock, per-path scan locks, tool
output compression, clamped reads, read-only subagent profiles and a
no-phone-home test are in the tree.

## Local Knowledge Stays Local

`knowledge/` is gitignored and skipped by scanners/snapshots, but it still
powers `Master::Io::SearchKnowledge`. Do not move it unless the search tool
learns the new location first.

## Deferred WebGL Boot Is Sacred

The face runtime must not create a WebGL context before the primer tap. The
guard in `web/app/views/chat/index.html.erb` protects the tap-to-start path from
eager or stale assets.

## The Face Intake Was A Design Brief, And The Design Is The Operator's (2026-09-13)

A 404-item ChatGPT intake asked for a far-future-human face. Most of its
engineering half already exists under other names: `attention_model.js`
drives gaze, dwell, saccades and blinks from conversational state at
physiological rates; `boot_fsm.js` is the boot state machine; the face
handles `webglcontextlost`, falls back to 2D, honours reduced motion and
forced colours, and pauses when the tab is hidden; `face_brutalist.js` and
`face_minimal_ui.js` are the terminal and minimal modes; visemes read
`audio.currentTime`, so speech and mouth share one clock by construction;
`ttsSkipHard` flushes every lane; TTS fetches carry a timeout, a watchdog
and a backoff; `Voice::TtsSupervisor` replaces a worker that stops
answering; `Speech#clean_text` drops code blocks and links before
synthesis; `test_face_runtime_matches_its_sources` holds the generated
runtime byte for byte; and `browser_payload` now carries the voice names, so
the face and the server cannot resolve a voice differently.

**Refused, because the tree already answers them another way.** A formal TTS
state enum, a unified timestamped event stream, a synchronisation budget with
golden traces, and gates matching browser state names against server ones
all measure a gap the audio clock closes. The event bus forwards every topic
to the browser through the `cable_bridge` wildcard, so a state "with no
browser representation" cannot be found by comparing names. Pause-length and
phrase-length distributions, GPU frame-time telemetry, thermal detection and
an hour-long soak test have no reader, on a face whose one operator sees it
every day on a one-core box.

**Left to the operator, because they are the look and the voice.** Morphology,
cranial and orbital proportion, asymmetry, generational variants, expression
and motion grammar, layout hierarchy and every visual state, how paths and
figures are spoken, and every blind test of perceived intelligence. The
speculative-evolution research the intake asked for serves those decisions
and has no other consumer.

## dilla Measures From Kept Takes, Not From An Intake (2026-09-13)

A 280-item ChatGPT intake asked the engine to gate its mixes against
engineering folklore attributed to Dilla, Madlib, Cooley, Power, Fairall,
Daddy Kev and Flying Lotus. The measuring half already exists:
`<track>.quality.json` reads integrated loudness, true peak, loudness range,
phase correlation, mono RMS and a spectral delta against a baseline on the
delivered file; `SpectralAudit` reads shape, crest, DC offset, stereo
correlation and now mono-fold loss and low-end side energy; `MixScore` and
`Taste` read the rest; `VerifyFx` proves each stage moves its own
measurement; `DillaProvenance` records the seed, the pins, the commit, the
toolchain versions and every warning; `DillaKnobs` derives every knob from
the code; `console_strip.rb` saturates per channel before the sum;
`tape_hysteresis.rb` carries Ornstein-Uhlenbeck wow and flutter; per-role
microtiming and its drift are tested; `reference_sonic.yml` stores derived
measurements only; and `dilla_principles.yml` already separates documented
evidence from hypothesis.

**Refused: scores and gates nobody has measured.** `TIMBRAL_FIT`,
`TIMING_ENTROPY`, `REFERENCE_DISTANCE`, `CHARACTER_PRESERVATION`,
`MASTER_SAFE` and their kin would each need a threshold, and `mix_score.rb`
states the engine's rule: a threshold picked in advance measures the person
who picked it, so targets come from takes that were kept after listening. A
metric with no reader is inert config, which is this tree's dominant defect.
Harmonic-order tables, oversampling cost tables, per-stage CPU and memory in
the quality JSON fall under the same rule; dmesg already prints each tool's
seconds.

**Refused: artist-named comparison suites, golden renders and A/B/X
fixtures.** Renders are not deterministic to the byte and are irreplaceable,
so a golden file either fails on noise or overwrites a take. A/B here is
`DILLA_FROZEN` and interleaved listening.

**Refused: a research ledger.** `research_status`, contradiction fields,
per-engineer history notes and a quarterly review have no reader in the
engine; `dilla_principles.yml` carries evidence levels where a reader exists.

**Refused: NaN, infinity and denormal detection on the file.** A delivered
take is integer PCM or MP3, where none can exist; a NaN in the float graph
arrives as silence or clipping, which crest, band and clip readings already
see. And generated tables in `ENV_AND_RENDER.md` would be a second source
beside `dilla knobs`, which prints the registry from the code.

What stays open is sound: new processing profiles, a separate mastering
stage, stem routing, widening, channel variance and sample-start offsets
change how a take sounds and are the operator's.

## Self-Test Is A Loud Gate

`rake selftest` runs `rules.yml.self_test` against MASTER itself. It is allowed
to fail while known debt remains; the point is to make debt visible and
triageable. Nothing gates on the `selftest` count; read it from the task, never
from prose, because it has read 0 through 7 in one fortnight.

`selfcheck` is different, and a note once had it backwards. `SelfCheck#gate!`
runs from `builder/ai_boot.rb` and publishes `self_violation`, which the same
file subscribes to `fix_loop.halt!` — so a red `selfcheck` halts background
autofix for every session. Triage a new finding as a true violation, a false
positive, an exemption, a threshold, or known debt. Never drive the count to
zero by re-exempting the fold: it sits inside `lib/` so the law it applies
measures it too.

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

## The Rakefile Stays One File, And The Docs Stay At The Root (2026-09-13)

A tree-grammar intake asked for `MASTER/Rakefile` (977 lines) to become
`tasks/*.rake`, and for `AEGIS.md`, `COGNITION.md`, `EXAMPLES.md` and this file
to move under a new `docs/`. Both are refused.

The Rakefile is a corpus, not only a task list. `tools/runs.rb`,
`tools/data_reach.rb`, `tools/method_graph.rb`, `test_readme_env_names.rb` and
`test_limits_split.rb` each name the file to find who runs a test, who reads a
data key or which ENV name is live. A split would leave every one of them green
and blind, which is the engines-migration defect this repo already paid for
once. A long file every instrument can see costs less than short ones that five
instruments cannot.

The documents are named by path in `AGENTS.md`, `START_HERE.md`,
`PATH_OWNERSHIP.yml`, `data/doc_baselines.yml`, `lib/cognition/` and
`test_doc_paths.rb`. Moving them buys a tidier listing and
costs a sweep of every pointer, for no reader who cannot already find them.

## lib/'s Small Files Stay Where They Sit (2026-09-13)

`FILE_SPRAWL` names 23 files in `lib/`: 21 under 25 code lines and two lone
files in their own directory. Read one by one, each is a single subject with a
reader, and several must sit exactly where they are. `boot/hash_dig_compat.rb`
is required by path from dilla, and merging it once silently changed what dilla
renders. `io/bedrock_stub.rb` must define its constants before ruby_llm loads.
Zeitwerk looks for `Master::SecurityError` at `security_error.rb` and nowhere
else. `cli/propose/candidate_sources.rb` and `review/repo_ecology/co_change_graph.rb`
are mixins drawn out to keep their parents under `NO_GOD_CLASS`, and
`data/spine.yml` records why.

A merge is not free. `lib/` sits under `push_dir(lib, namespace: Master)`, so
every merge moves a constant, and `body_lines` excuses a module holding exactly
one class, so a merged file's scaffold starts counting against
`spine.lib_body_ceiling`. Merge one only when a reader asks for it, with the
constant rename in the same commit. The near-limit directories —
`ground/policy`, `voice/renderer`, `cli/routing/model_router` — would each land
over 300 lines, and the last two `include` their children above where merged
bodies would sit, so a naive fold passes `ruby -c` and raises `NameError`.
Derive a merged scaffold from the path, never from a file's leading `module`
lines, and prove it by loading the constants. `lib/io` and `lib/ground` are not
namespace directories; merging there is a rename campaign with no subject.

Declined on the same reading: `gate_chain`'s helpers stay public because
`test_gate_chain` drives five of them; a constant with one use far below its
declaration stays when a sibling file reads it or it shares a paragraph with its
neighbours; the rules files are registries, and splitting one moves lines rather
than removing them; `sprawl.vague_names` (`boot/data.rb`, `io/base.rb`) and
`repo_inventory`'s `low_density_slug` rows are names Zeitwerk or a design chose;
absorbing single-reader files would fold five of them into `boot_phases.rb`,
whose job is to read everything. No method in `lib/` exceeds 20 code lines.

`voice/emotion.rb#analyze` carries the one `ABC_SIZE` finding left, at 74.7.
Its size is five weighted sums, and moving the coefficients into a folded table
reorders float addition in `exaggeration`, `cfg_weight` and `warmth` — the
controls MASTER's speech is synthesised with. That is a change to how MASTER
sounds, and it waits for somebody who can A/B the audio.

## An Unread-Key Gate Is Not Buildable Here (2026-09-13)

"Every data key has a reader" is the obvious gate, and it was measured before
anyone built it. 607 of 1,173 second-level keys under `data/**/*.yml` have no
literal mention in code, and 49 of 238 top-level sections — wrong more often
than right. The tree reaches data four ways a grep cannot follow: interpolated
filenames (`data/prompts/mode_#{mode}.yml`), directory globs, `DATA_ALIASES`,
and section loaders such as `RuntimeCatalog.load(section)`. `loc_budgets` looked
dead and is read by the Rakefile; `limits.yml` `guidance` is unread on purpose.

`data_reach`'s remaining misattributions are four families and no defect:
registry rows chosen by a config value (`personas.yml`, `providers.yml`,
`prompts.yml`), `schema` and `meta` version keys, archive manifests, and keys
that are paths rather than identifiers. A ceiling over them needs a written
reason per row. So an unread key is found by hand, per file, and closed with a
two-direction test — `test_limits_split.rb` is the shape.

Trace the caller to the end before calling config inert. `data/tts.yml` once
told its reader that nothing read it while `Playback.speak` →
`Speech.synthesize` → `Transcendent.load_config` read every key, and a census
of `Voice::`-prefixed references reported seven `lib/voice` files unreached
that are reached from inside the directory, three by `include`.

## Seven Ways A Check Certifies What It Did Not Measure (2026-09-13)

Each converts the absence of a property into evidence of it, and each has
happened here.

1. **A comment outlives its rule.** A check that greps source must strip
   comments first, with the pattern chosen by extension — a `/*` stripper run
   over Ruby ate `"etc/rc.d/*"`. A `refute_includes` that reads comments teaches
   the next author to delete the explanation.
2. **An exemption outlives its subject.** Check each allow-list entry against
   the tree, as `rake lint:autoload` does. `NO_PUTS` exempted
   `gate_chain` at its old directory for months after it moved to `lib/operator/`.
3. **A build artifact outlives its source.** When behaviour contradicts source,
   diff what is served against the file it claims to be; Rack::Static serves
   a stale `public/assets` ahead of propshaft.
4. **A staleness alarm is silenced by regenerating.** Before running
   `assets:precompile` to clear a drift message, ask what the drift is evidence
   of — it once copied broken JavaScript over the good bundle.
5. **A test punishes the improvement it watches for.** Assert the invariant
   (`refute_empty findings`), never the instance (`ratio < threshold`); a
   failure message that describes something good happening points the wrong way.
6. **A writer reports an edit it did not make.** Read back what was written.
   In YAML the indentation is the syntax, and a census that cannot parse a file
   reports it clean.
7. **A root constant resolves one level too high.** A fallback that ends in
   "use the last candidate anyway" is not a fallback; assert what the root
   holds, as `test_root_resolves_to_the_rails_tree` does.

What follows. A new gate's first run is against a known-bad input, because a
green first run is equally consistent with nothing measured. Registration is not
execution: a gate listed in `gates.yml` with no class-level `.run` never ran. A
gate reads the source of truth rather than restating it. And a test that turns
green while asserting only what every subclass inherits is worse than one that
errors, because it reads as coverage.

`AstFixer`'s transforms earn a test each for the same reason. `WriteGuard`
refuses a candidate that introduces a finding, but a template-literal rewrite
that indexes the wrong string introduces none and passes `node --check`.

## Media Generation Stays Severed

Generation left MASTER in `76b11fec4` and the severance was confirmed permanent
the next day. If the LoRA loop needs generation again, express it as
`lib/core/world.rb` handlers; do not restore the deleted LoRA pipeline and
video chain from history. STUDIO's repligen and lora keep the capability.

## The Execution Roadmap Was Already Built (2026-09-13)

An external roadmap of about ninety items proposed intent → plan → change →
test → review as MASTER's model. Every claim was checked, and these exist:
rule applicability (`Rule#applies?`, `languages` in `law/law.rb`), rule
provenance enforced at `Law.define`, render-before-claim
(`GateResult#measured_nothing?`), a risk classifier (`cli/fold_risk.rb`), an
evidence ledger (`trace/ledger.rb`), no false completion (`anti_simulation`),
provider failover and quota parking (`ModelRouter`, `io/quota_gate`), a
deterministic boot receipt with offline as a capability
(`Ground::BootReceipt`), a web-vitals budget, the swarm stage in
`cli/pipeline/pass.rb`, and the local model tier.

Its one open claim, that intent has several doors, is false today. Every
surface — the CLI session, the web chat, the gateway and standing orders —
calls `TurnRouter.call`, and `Stages::Intake` runs only inside it. The branches
in `call` are an ordered table of one door. What the roadmap underrates is that
MASTER's gap is discoverability and detector reach, not features: an acceptance
suite that proves the detectors right is worth more than one that proves the
features exist.

## Performance Work Starts From A Measured Cost (2026-09-13)

Two ChatGPT intakes of 2026-09-11 proposed 980 performance items across all four
trees: a `performance_budget.yml` registry, a ledger under `.master/performance/`,
`bin/operator benchmark`, `profile` and `hotpaths` commands, gate verdicts cached
by tree SHA, concurrent gates, a fast/forensic profile ladder, per-rule and
per-DSP-primitive benchmarks, and inventories of every `Dir.glob`, `Open3` and
`File.read`. Not one item carried a measurement. Declined as a class. A
measurement subsystem built ahead of a measured slowness is accretion, and the
tree already holds the instruments that earned their place: the `operator measure`
ratchets, `QueryBudgetTest`, `Bullet.raise`, strict loading, `css_budget.yml`, the
face watchdog, and `bin/gate`'s stage timeouts.

The rule instead. An optimization lands with its instrument in the commit — the
number before, the number after — and a check that the output did not change.
Cache facts keyed by what invalidates them, never verdicts: a gate is not skipped
because it passed last time, and a suite is not made cheaper by running less of
it. Subprocess nesting in `bin/operator gate` stays, because a separate process is
what gives each stage its timeout and its attribution of changed files.

Applying that rule to the intakes found six real costs, each fixed with its
number: `load_yaml` parsed `rules.yml` forty times in one boot and scan (724ms, now
three parses); `bin/cli --help` built the whole runtime before printing usage;
brgen was the one app without bootsnap (warm test boot 4.0–4.6s, 2.4–2.5s with it);
the face cloned its particle pool twice per frame on the way to the worker;
`MASTER_SCAN_ONLY` had no reader, so deploy scans ran the model-backed rules; and
marketplace and maps had no per-row query guard. It refuted as many: Falcon
already gzips HTML (brgen.no answers `content-encoding: gzip`), the watchdog's
fallback pump already stops when rAF resumes, gems already load `require: false`,
and dig_crate.rb's per-slug glob costs microseconds beside the demucs run it
guards.

So the next intake of this shape closes the same way: find the reader and the
measurement first, and a proposal that names neither is not yet an item.

## What The Gem Audit Left Hand-Rolled, And Why (2026-09-13)

The 2026-09-11 audit asked what MASTER hand-rolls that a gem provides. These
answers are no, each for a stated reason, so the next audit starts past them.

`RAILS/gates/support/cdp_framing.rb` implements RFC 6455 because gates run under
bare `ruby` with no bundle, ferrum lives only in the app bundles, and the gates
need `host-resolver-rules`, which ferrum does not expose. `lib/trace/event_bus.rb`
is not wisper: it does glob topic matching, redaction, Fiber-scoped conversation
stamping and telemetry spans, where wisper broadcasts to listeners.
`estimate_tokens` stays `bytesize / 4`, because the accurate answer is
`tiktoken_ruby`, a Rust extension, and this repo deploys to OpenBSD.

`Route#closest_command` keeps its Levenshtein matrix. The audit said
`DidYouMean::SpellChecker` returns the same answers; measured over 709 one-edit
typos of the command list, it disagrees on 40, catching transpositions the matrix
misses and missing first-letter slips and short commands the matrix catches. That
is a trade, not a fold. `lexical_rules.rb` keeps its fifteen RuboCop-shaped rules:
each id is a name the law addresses, so delegating to RuboCop renames the law.

Three ruby_llm features stay unused. `Model::Info#function_calling?` and
`#supports_vision?` cannot replace `TOOL_CAPABLE_RE` and `VISION_RE`: the registry
carries none of the `:free` ids MASTER routes to most, and `ruby_llm_patch.rb`
answers an unknown id with a capability-less stand-in, so every free model would
read as unable to call tools. `with_schema` cannot retire the `/\{.*\}/m`
extractors in `consensus.rb`, `swarm/worker.rb`, `core/model.rb` and
`stages/enhance.rb`, because free models ignore `response_format` often enough
that the extractor is the path that works. `lib/review/embeddings.rb` keeps its
Net::HTTP for the reason `OllamaSender` gives: a local daemon has no price or
capability row, the gem's Ollama provider speaks the OpenAI-compatible `/v1`
surface rather than `/api/embeddings`, and the client is two small methods.

The ruby_llm satellite gems are not adopted. `ruby_llm-schema` is deprecated in
favour of passing a Hash. `-resilience`, `-top_secret`, `-agents`, `-team` and
`-template` are thinner than what MASTER owns; its circuit breaker is
dollar-budget-aware and survives a restart. `-test`, `-evaluations` and
`-tribunal` would mock providers and grade the council, but each is a new lock
entry, which this repo changes only on the box; evaluate them there, one at a
time, against a named test they would replace.

## Two Formats And One Parser Wait For A Consumer (2026-09-13)

**SARIF output is not built.** `Scan::Finding` carries everything SARIF needs, and
about sixty lines would emit it, but nothing outside pub4 reads the corpus. A
writer for a reader that does not exist is the inert-config defect this repo
records most often. Build it the day a consumer is named.

**Herb is not adopted.** It parses HTML and ERB into one tree and would replace
`law/html.rb`'s regexes, but it is a C extension, and the argument that refused
tree-sitter refuses it. Revisit when Rails merges Herb as its ERB implementation,
because then it lands on vm23 anyway and the question becomes whether the regexes
still earn their keep.

## Onboarding Is The Contract Chain, Not A New Program (2026-09-13)

A first-contact path from clone to green check exists as documents:
`CLAUDE.md` and its generated siblings point at `START_HERE.md`, and
`bin/operator gate --explain` prints the ladder without running it.
`bin/onboard` writes `.master/config.yml` and runs no check, and that is its job.
A third onboarding surface would restate the first two and drift from them, which
is how the previous root `CLAUDE.md` died.

## Autofix Tiers By Transform, And That Is Per Rule Today (2026-09-13)

The horizon scan asked autofix to read each finding's `reversibility` and
`blast_radius`, the way RuboCop splits `--fix` from `--fix-unsafely`. It already
does what that split is for. Four registry rules name a transform, and
`AstFixer::DELETING_TRANSFORMS` puts the one that deletes behind
`MASTER_AUTOFIX=1` while the three that add run unattended; a rule with no
transform cannot autofix at all. The two fields are filled only by the semantic
and meta rules, whose findings carry `fix: nil` and so never reach `lib/fix`, and
`rules.yml` declares the vocabulary (`free | cheap | surgical | impossible`) on no
rule. Reading the fields would gate nothing. Reopen this when a fifth transform
lands whose risk the add-or-delete split cannot state, and classify that rule in
`rules.yml` by hand then.

## The Outside Intake's Scanner And Test Proposals, Refused Where Built (2026-09-13)

An external session proposed 478 items across the four trees. Its MASTER half
asked for machinery this tree already has under other names, and a grep for the
proposal's own words reports every one of them missing. The rescue taxonomy is
`SILENT_RESCUE`, `MODIFIER_SILENT_RESCUE`, `BARE_RESCUE`, the `Ground::Swallow`
ledger read by `tools/swallowed_errors.rb`, and the `scan: intentional — reason`
marker; typed failure is `Master::Result`. Registry audits are
`test_rule_ids_unique`, `test_rule_registry_audit`, `test_rule_catalogue` and
`test_rule_fixtures`. Ratchet integrity is the `unreadable` state in
`tools/ratchets.rb`, ceilings read back out of history, and `lint:spine`'s raise
counter. Mutation testing is `tools/mutate.rb`. Backlog hygiene is
`tools/backlog_claims.rb` and `tools/backlog_triage.rb`. What was missing and
cheap was written: one test holding all 148 rules stable across runs, CRLF and
duplicate findings; every `bin/` script executable with a shebang; workflow
steps that cannot swallow their exit. The rest is refused, for these reasons.

**No per-detector timing, budget or timeout.** All 148 rules were timed over a
planted file carrying every shape that fools a line scanner, and none took half
a second. A full scan of `lib/` is 13 seconds, and `Rakefile` already bounds
each file with `SCAN_TIMEOUT`. A budget without a slow rule is a ceiling nobody
can breach.

**No visibility, metaprogramming or Liskov corpora beyond what exists.**
`test_visibility_semantics` covers the scopes that matter, `LiskovRule` has its
fixtures, and a rule for `private :missing` would restate Ruby, which raises
`NameError` when the class body runs — a census of the tree's 22 such
declarations found none dangling. `define_method`, `method_missing`,
refinements and `prepend` coverage fall under the rule this file already states
for AST projects: reopen only with a finding in hand.

**No architecture graph with annotated, expiring, owned exceptions.**
`test_constant_collisions`, `rake lint:autoload` (which proves each ignore still
necessary), `PATH_PURPOSE` and `test_core_no_lib_backedges` hold the boundaries
that have broken. An expiry date written beside an exception is a changelog in
code, which this tree removes on sight.

**No mutation campaigns over whole directories, capability matrices or
skip-count dashboards.** `tools/mutate.rb` exists for the file a finding names,
and the habit that caught the retracted report — revert the fix, watch the test
fail — is the same check at the cost of one run. A campaign over a whole
directory spends a shared machine's CPU on a question no finding has asked.

**No rules about the shape of backlog entries.** Requiring a path, a metric or a
screenshot criterion of every item would put law about prose in `rules.yml`,
which is immutable to effects and read by the runtime. The two tools above check
what an item cites, and `TODO.md`'s preamble carries the habit.

## What The Catalogs, Papers And Books Do Not License (2026-09-13)

Four intake passes on 2026-09-11 read awesome lists, agent harnesses, arXiv
papers and design books against the tree. What they proposed that contradicts
the tree is refused here once, so the next pass does not reopen it.

MASTER takes no Docker worker fleet, no agent process table in the manner of
Hermes, no MCTS or debate-of-three around FixLoop, no computer-use driver and no
Python compressor. The box is one OpenBSD host, isolation is `operator worktree`,
the council is already the value agent, and MASTER is pure Ruby with no external
agent integrations. What those projects teach is an interface — compressed tool
output, span context, hypothesis versus measured — and it is taken as that.

RAILS takes no Kamal, Thruster, Dockerfile, Inertia, Vite, ViewComponent,
Lookbook, Cucumber, Percy, Chromatic, Playwright or capybara-screenshot-diff.
Deploy is rc.d and relayd; the frontend is importmaps, ERB, Stimulus and Turbo;
`visual_contract` and `layout_snapshot` are the one paint and one layout
baseline. It takes no Chart.js, Google Places, glow, Pickr, scroll-to, timeago
or content-loader either: each is a third renderer, a third party on a
Norwegian city app, or an effect FLAT_UI forbids, and the last three were
dropped with a measurement. No two-tower feed, neural outfit model or pgvector
ranking runs on a 1 GB SQLite box; the portable result of those papers is a SQL
union, filed under `RAILS/apps.horizon.yml`. The shared snippet library
`shared/frontend/examples.html.erb` stays: it is documentation, and
`deploy_backlog_test.rb` holds it to registered controllers.

Books are read for detectors, never for a look. Parametricism, an Itten palette,
a second type scale, Pallasmaa as texture or fog, and a swing retune "because
Charnas" all change a rendered value, which is the operator's; Venturi is not
codified because it argues against Rams and Ando, which already are law. A book
imported as YAML needs a reader the same day, or it becomes `dilla_principles.yml`.

## The CLI Is Already A dmesg (2026-09-13)

A 160-item ChatGPT intake asked MASTER's terminal output to read like OpenBSD's
dmesg. It does. `Trace::Dmesg` writes `unit at parent: detail` and
`unit: key=value`, append-only and one line per fact, and `cli/pipeline/pass.rb`
drives it with numbered units such as `fix0` attached at `mainbus0`. Boot prints
nothing unless `MASTER_BOOT_STATUS=1`, and then only `master: boot safe=` and
`master: ready`, which `test_boot_banner` pins. `NO_ASCII_DECORATION` forbids
banners and box drawing. Colour goes through Pastel, whose tty-color backend
turns it off when stdout is not a terminal or `NO_COLOR` is set. The one line
that repaints, the thinking indicator, runs only on a TTY and stands for the
sparse liveness fact the intake itself allows during a model call that takes
tens of seconds. The machine form already exists: the event bus carries every
topic, and the ledgers write JSONL under `runtime/`. `test_bin_master_core`
holds an exit status.

**Refused.** A second presenter behind `--dmesg`, a JSON mode for the session,
and a canonical subsystem registry would each give one event stream a second
spelling to drift from. Golden traces of a run cannot hold, because a model
call's output and timing are not deterministic, so a golden file either fails
on noise or proves nothing. The rest of the intake is a style guide, and
`Trace::Dmesg`'s shape already is one.

## An Audit Prompt With No Path Is Not An Item (2026-09-13)

A 254-item ChatGPT intake titled "pub4 subtraction and entropy" asked for
repo-wide audits: dead code, duplicate registries, dependencies, rescue
clauses, security scans, boot benchmarks, OpenBSD rebuilds, git archaeology and
topology graphs. None named a file. The tree already holds the instruments
those audits would build: `bin/operator gate` and its ratchets, `FILE_SPRAWL`,
`tools/code_reach.rb`, `dup_census.rb`, `method_graph.rb`, `cohesion.rb` and
`sprawl_census.rb`, the swallow ledger, Brakeman and bundler-audit in each app's
CI, `outbound_http_test` for SSRF, and the rule that performance work starts
from a measured cost. Declined as a class.

The half that did carry paths became a list of fifty measured candidates. About
half were real, and they were fixed one commit each: the seven unreached slash
tables, the Rails audits only their own tests reached, a second path guard and a second atomic write, the
ChatController's own dmesg, the vote reflexes, the offline memory scaffold, a
second smoke script, the rc.d template, brgen's local notifications
controller, a LIKE search beside `LiveSearchable`, a web push loop that
unsubscribed a whole city on one bad VAPID key, and MixScore's shell strings.
The other half died on measurement. `futurism` has three readers, `bin/crate`
writes a directory that is ignored by design, the two uptime checks differ
because root's cron must not execute the checkout, the four deploy verbs each
cover a case `vps-deploy` does not, `bin/master` already hands over to
`bin/cli`, and the three face stores have a boot order in `face_assets.yml`.
The face tests in `spec/`, `test/` and `web/test/` stay where they are: the
first two read files, the third needs the web bundle or node, and `bin/check`
runs all three, so a move would buy tidiness and measure nothing new.

So the next intake of this shape closes the same way: a subtraction lands with
the second caller found and the test that keeps the survivor honest, and a
question with no path is not yet an item.
