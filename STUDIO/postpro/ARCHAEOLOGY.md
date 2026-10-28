# Postpro archaeological recovery record

Scope: source and history in `anon987654321/pub`, `pub2`, `pub3`, and `pub4`, searched under `postpro`, `Postpro`, and nearby Repligen/Replicate integration names. This is a preservation map, not a claim that old code can be pasted into the current engine unchanged.

## Decisions

- Preserve historic creative language and workflows as design provenance.
- Keep the current measured film model, recipe dispatcher, seeded random-chain engine, provenance sidecars, and vocabulary checks as the runtime source of truth.
- Restore the legacy effect vocabulary through the compatibility layer, not through a second effect engine.
- Do not re-add the old video implementation verbatim. Its functional intent is now recovered in `motion.rb` using in-process frame grading, raw-frame streaming, atomic output, deterministic grain and explicit budgets.
- Keep external dependency installation opt-in. Older startup bootstraps attempted to install gems and system packages from ordinary execution; the current entrypoint must remain observational when loaded or checked.

## Archaeological trail

### `pub`: v12.9 / v13.3.14 — analog and cinematic post-processing

Sources:
- [postpro.rb](https://github.com/anon987654321/pub/blob/a3185f4ec6e6a27e35eeee6718ae3afa11bf49da/postpro/postpro.rb)
- [README.md](https://github.com/anon987654321/pub/blob/a3185f4ec6e6a27e35eeee6718ae3afa11bf49da/postpro/README.md)
- [README2.md](https://github.com/anon987654321/pub/blob/a3185f4ec6e6a27e35eeee6718ae3afa11bf49da/postpro/README2.md)
- [IMPLEMENTATION_COMPLETE.md](https://github.com/anon987654321/pub/blob/a3185f4ec6e6a27e35eeee6718ae3afa11bf49da/postpro/IMPLEMENTATION_COMPLETE.md)
- [completion commit — 29 effects](https://github.com/anon987654321/pub/commit/512715ac6eddfd3100269019bb361927de371968)

The early interface was an interactive batch tool: select professional or experimental mode, choose random treatments or a JSON recipe, match file patterns (including recursive patterns), choose 1–5 variations and 1–5 effects per variation, and see progress and aggregate statistics. It documented retry-on-failure, rotation/debug logging, RGB/RGBA handling, and finishing/polish steps. Professional mode was deliberately restrained; experimental mode admitted stronger distortion. JSON recipes could set simple intensities or effect-specific parameters such as blend modes and borders.

The v13.3.14 specification enumerated 29 user-facing effects. That vocabulary is preserved in `LEGACY_RESTORE.md` and `legacy_effects.rb`; equivalent present-day implementations are preferred over copying the old pixel math where a measured stock, H&D curve, grain model, or current effect is more truthful.

Historical wording worth retaining as provenance:

> Every pixel carries the weight of photographic history. Every adjustment honors decades of cinematic excellence.

### `pub2`: v14.2.0 and duplicate roots

Sources:
- [postpro/postpro.rb](https://github.com/anon987654321/pub2/blob/ad05242c97fff1b01450434974aad628d7de8628/postpro/postpro.rb)
- [postpro/postpro_README.md](https://github.com/anon987654321/pub2/blob/ad05242c97fff1b01450434974aad628d7de8628/postpro/postpro_README.md)
- [multimedia/postpro.rb](https://github.com/anon987654321/pub2/blob/ad05242c97fff1b01450434974aad628d7de8628/multimedia/postpro.rb)
- [bootstrap commit](https://github.com/anon987654321/pub2/commit/08ce8802f9374ed62e9d1be61c664d2bf6b53bb8)

The code and README existed under both `postpro/` and `multimedia/`. The v14 line emphasised cinematic presets, one-command integration with Repligen, config-driven options, and dmesg-style startup diagnostics. Both copies are archaeological evidence, not a reason to keep duplicate implementations in the current tree.

### `pub3`: multimedia consolidation

Sources:
- [multimedia/postpro.rb](https://github.com/anon987654321/pub3/blob/835f9199d605b6a6ae1f32cd207919c115a06b47/multimedia/postpro.rb)
- [multimedia/postpro/README.md](https://github.com/anon987654321/pub3/blob/835f9199d605b6a6ae1f32cd207919c115a06b47/multimedia/postpro/README.md)
- [move-to-root commit](https://github.com/anon987654321/pub3/commit/b0f76f553de9a6056b07ed4b987acf49407fc11f)

The documented core had Portra, Vision3, Velvia and Tri-X; camera-profile corrections; portrait skin protection; film curves and highlight roll-off; micro-contrast; Portrait, Landscape, Street and Blockbuster presets; random exploration; and an explicit Repligen handoff. The pipeline wording was: generate, save, process, final output. The user-visible presets and concepts survive in the current preset/stock/effect system, even where the old implementation or numbers have been replaced.

### `pub4`: measured house grade and restoration

The present implementation lives under `STUDIO/postpro/`, with `lib/` holding the effect dispatch, presets, stocks, grain, random chains, recipe handling, pipeline, sidecars, audits and CLI. `motion.rb` owns the video grading contract and CLI, while `motion_process.rb` owns bounded frame IO, timestamp checks and subprocess lifecycles; `MASTER/tools/postpro` is a compatibility symlink.

Current recovery anchors:
- [LEGACY_RESTORE.md](./LEGACY_RESTORE.md)
- [legacy_effects.rb](./legacy_effects.rb)
- [recipe.rb](./lib/recipe.rb)
- [random_chain.rb](./lib/random_chain.rb)
- [grade_step.rb](./lib/grade_step.rb)
- [vocab_check.rb](./lib/vocab_check.rb)

The new engine preserves the original user intent but intentionally changes the mechanics: effects go through one dispatcher; source headroom and look-specific intensity are respected; calculations remain floating-point until a single final cast; random recipes must survive measured source-preservation checks; every output can carry the seed, chain and provenance; and AST-based vocabulary checks establish that recipe/preset options reach executable effect calls. Historical claims of “true randomization” do not substitute for those current proofs.

## The deleted 2026 photographic proposal notes

The two documents that were folded into implementation—not lost to an accidental delete—are
still recoverable at their exact historical snapshot:
- [`STUDIO/AMBITION.md` — all 168 proposals](https://github.com/anon987654321/pub4/blob/5c15297107d131eef8881241f6e84190670a2225/STUDIO/AMBITION.md)
- [`STUDIO/PHOTOGRAPHY.md` — the four-layer photography model and refitted visual laws](https://github.com/anon987654321/pub4/blob/5c15297107d131eef8881241f6e84190670a2225/STUDIO/PHOTOGRAPHY.md)
- [The later folding/deletion commit](https://github.com/anon987654321/pub4/commit/80709c0712559031fef10fe486f530ac35b185fc), whose message says those ideas now stand beside the code that uses them.

This record preserves the trail without reintroducing two competing top-level specifications.
The four independent failure layers remain the most important rule: **geometry** is decided
before grading; **light** can be reshaped tonally but its direction cannot be moved; **expression**
is a capture/generation decision; and **optical signature** (skin texture, specular response,
grain, halation and highlight shoulder) is the grade's proper scope.

| Historical visual law or proposal | Current owner / status |
| --- | --- |
| Strong centres, levels of scale, squint test, least astonishment | Prompt/selection principles; `STUDIO/replicate/craft.rb` and current generation prompts. They are not all objectively measurable gates. |
| Define errors out / poka-yoke | `rescue.rb` states geometry, focus, motion blur, expression and clipped source highlights honestly instead of claiming a grade can repair them. |
| Parse, don't validate; refuse unsupported settings | Replicate's model-specific input vocabularies, `Chain.problems`, and Postpro's checked recipe/preset vocabularies. |
| DRY for near-identical frames | `frame_set.rb` fingerprints and near-duplicate detection. |
| One strategy per set | `frame_set.rb` normalises exposure to the set before applying a coherent grade. |
| Magic color / optical emulsion tokens | Postpro's stock tokens bind curve, dye response, speed and calibrated grain instead of independent arbitrary sliders. |
| Reversibility / chesterton's fence | Original source is retained; output guards refuse source overwrite; grades write separate outputs and provenance. |
| Full by default / analog warmth | The house grade defaults to its complete physical chain; camera-profile correction is on by default; blur that would invent new defocus remains intentionally excluded. |
| Uncanny score before and after grade | Preset sidecars already record before/after readings. Chain sidecars now do too, together with input/output hashes and quality warnings. |
| All rendered pathways use the same camera correction | This branch closes the old one-shot/watch/uplift/stock-sheet drift and adds a vocabulary audit that fails if one of those paths stops reaching `camera_corrected`. |
| Golden references with perceptual ΔE and explicit skin/highlight bounds | Still a real gap: current quality warnings and smoke-pixel tests are not a substitute for calibrated reference-image tests. No claim is made that this item is complete. |
| A measured specular-uniformity score and monotonically improving uncanny score | Still open: texture/clipping readings are proxies, not a facial-region/specular-scattering measurement. |
| Video shutter angle, coherent bloom/halation, flicker, weave, gate-hair, telecine and still/video parity | The bounded CFR video pipeline restores the basic grade/audio/timing path. These video-specific optical effects and parity fixtures remain future work, not silently implemented features. |

The 168 numbered ideas were a menu, not a mandate to ship every model name, price, or experimental stage
as a runtime default. The maps above make the old intent findable while distinguishing measured
behavior from proposals.

## Later `pub4` change trail

These commits explain important implementation decisions that a code-only snapshot can
obscure:

- [Split `postpro.rb` into `lib/` under the 300-line cap](https://github.com/anon987654321/pub4/commit/66f2c9527f99165ae6bb35801b4e5d65275c796e): preserve small, readable effect and pipeline modules rather than grow another monolith.
- [Make the vocabulary audit read entrypoint and libraries together](https://github.com/anon987654321/pub4/commit/6d3d06f57daf1d6b379d181dbcfaeffa071f31bd): a declared effect must resolve to the implementation the grade actually calls. This branch adds `motion.rb` to the source inventory too.
- [Give Postpro CLI suites a render budget](https://github.com/anon987654321/pub4/commit/909e55b24765611d4b2be0211a727c3ee4f5549f): tests that can render must have bounded cost and not silently turn into hours-long work.
- [Grade random takes like presets and protect photos](https://github.com/anon987654321/pub4/commit/650827110ed9bee560bdf980bbe03b778c016d18): use the calibrated shared grade dispatcher and measured source-preservation checks rather than raw effect strengths.
- [Balance takes before the look and hold exposure through it](https://github.com/anon987654321/pub4/commit/dd721801be0505c838a2131fa042d2254e85ea46): keep source exposure as an explicit invariant, except where exposure itself is the selected look.
- [Treat reciprocity failure as lost exposure, not a veil](https://github.com/anon987654321/pub4/commit/0c5e2d16d9f51a4f9162dfee193e7b234c3416ef): model analog effects according to the physical process, not a convenient overlay.
- [Keep blur, relief and artefacts out of random takes; preserve monochrome stocks](https://github.com/anon987654321/pub4/commit/da763765392fed477fe303ba19987a6297a77c31): random variation must remain coherent and B&W stocks must render monochrome.
- [Restore real depth maps without native exit aborts](https://github.com/anon987654321/pub4/commit/93b8a65b9eb9f4768762563b4f27333ad4a0f44c): optional model-based depth should degrade intentionally, and native teardown must not report a completed output as failure.
- [Remove the original per-frame video path after measurement](https://github.com/anon987654321/pub4/commit/ec2cdf458f6f571692fea1ea97e8335881b56135): the reason for this branch's bounded in-process replacement, not an obsolete detail to lose.

## Lost or changed behaviour: disposition

| Historical capability or idea | Present disposition |
| --- | --- |
| 29 named creative effects | All 29 names have current equivalents or compatibility implementations; see `LEGACY_RESTORE.md`. |
| Professional vs experimental intensity lanes | Evolved into coherent named random lanes and opt-in `--rough` / `--heavy`; not copied as a second independent effects mode. |
| JSON recipes with effect-specific options | Preserved through `recipe.rb`, `RECIPE_ALLOWED` and the shared grade dispatcher; vocabulary audit tests reachability. |
| Recursive input patterns and multi-variation batches | Present-day batch/prompted entry points are the supported interface; output names, sidecars and family contact sheets are more explicit. |
| Retry/error recovery, logs and statistics | Current per-variation failures and structured startup/output diagnostics avoid hiding a partial batch failure. Do not revive automatic dependency installation as part of retries. |
| Camera profiles and stock-specific grain | Evolved to camera-profile data, measured stock tables, calibrated grain and `--fit-grain`; use those as the authority. |
| Repligen handoff and post-generation film look | Current Replicate calls grade by default (portrait by default); `--no-postpro` is the intentional escape hatch. See [Replicate archaeology](../replicate/ARCHAEOLOGY.md). |
| Video/frame-sequence grading | Recovered as `motion.rb` / `motion_process.rb` and `--video`: one Ruby process, ffmpeg raw-frame streaming, in-process Postpro, atomic final MP4, deterministic moving/held grain, and frame/pixel/time/temp-byte budgets. Constant-rate MP4 only; variable-rate inputs and mismatched frame counts are refused. The old per-frame subprocess path remains retired. |
| The old `apply_effects` / `apply_effects_from_recipe` internals | Not restored: the shared recipe and grade dispatchers replace them. Keeping both would create two sources of truth. |

## The video experiment, its removal, and the recovered in-process path

The implementation commit [9ac4b113](https://github.com/anon987654321/pub4/commit/9ac4b11332762333da58f8ec4358eec7cbbcb1d4) introduced `Postpro::Motion`, CLI `--video`, and eight tests. It captured the right product rules:

- inspect actual streams with ffprobe; do not trust extensions;
- preserve the original dimensions, the true rational frame rate (for example, 24000/1001), and audio without re-encoding;
- run the same Postpro grade so stills and moving frames do not diverge into two looks;
- distinguish deterministic moving grain (base seed plus frame index) from deliberately held grain;
- print frame count and a runtime estimate before expensive work; test the estimate, audio preservation, reproducibility, and the fact that the grain modes actually produce different output.

The removal commit [ec2cdf45](https://github.com/anon987654321/pub4/commit/ec2cdf458f6f571692fea1ea97e8335881b56135) explains why that implementation is not to be restored verbatim: it launched a fresh Ruby process per frame; measured render time was about an hour per minute of 1080p rather than the promised six minutes, and two tests timed out. Its own estimate was therefore not trustworthy.

The replacement on this branch implements the central correction: ffmpeg streams packed RGB frames through one process, each frame is graded by the live Postpro methods in memory, and only compressed graded frames are spooled under a cumulative byte cap. It estimates work before decoding, enforces maximum frames/pixels and a runtime budget checked around every frame operation and subprocess (native libvips processing within a single frame is not forcibly interruptible), refuses frame-rate ambiguity and metadata/decoded-frame count mismatches, copies audio without re-encoding, assembles to a temporary MP4 and publishes the video plus checksum sidecar with same-directory atomic links only after successful grading. Tests cover fractional rates, seed modes, dimensions, audio, repeatability, held-vs-moving output and preservation of a pre-existing output on failure. The GitHub-only edit environment did not execute those tests; `cd STUDIO && rake test:motion` and the full `cd STUDIO && rake check test` remain required evidence before describing this path as verified on a real host.

## Verification boundary

This document is a historical map, not a test receipt. Current effect reachability, pixel behaviour and CLI behaviour are established by the live `--vocab-check`, focused Postpro tests and `cd STUDIO && rake check test`. A historical commit message saying “green” is evidence about that past revision only.
