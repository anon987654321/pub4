# Postpro archaeological recovery record

Scope: source and history in `anon987654321/pub`, `pub2`, `pub3`, and `pub4`, searched under `postpro`, `Postpro`, and nearby Repligen/Replicate integration names. This is a preservation map, not a claim that old code can be pasted into the current engine unchanged.

## Decisions

- Preserve historic creative language and workflows as design provenance.
- Keep the current measured film model, recipe dispatcher, seeded random-chain engine, provenance sidecars, and vocabulary checks as the runtime source of truth.
- Restore the legacy effect vocabulary through the compatibility layer, not through a second effect engine.
- Do not re-add the old video implementation. It was removed for measured performance and test failures; its functional intent remains a concrete future requirement below.
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

The present implementation lives under `STUDIO/postpro/`, with `lib/` holding the effect dispatch, presets, stocks, grain, random chains, recipe handling, pipeline, sidecars, audits and CLI; `MASTER/tools/postpro` is a compatibility symlink.

Current recovery anchors:
- [LEGACY_RESTORE.md](./LEGACY_RESTORE.md)
- [legacy_effects.rb](./legacy_effects.rb)
- [recipe.rb](./lib/recipe.rb)
- [random_chain.rb](./lib/random_chain.rb)
- [grade_step.rb](./lib/grade_step.rb)
- [vocab_check.rb](./lib/vocab_check.rb)

The new engine preserves the original user intent but intentionally changes the mechanics: effects go through one dispatcher; source headroom and look-specific intensity are respected; calculations remain floating-point until a single final cast; random recipes must survive measured source-preservation checks; every output can carry the seed, chain and provenance; and AST-based vocabulary checks establish that recipe/preset options reach executable effect calls. Historical claims of “true randomization” do not substitute for those current proofs.

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
| Video/frame-sequence grading | Not present on main. The previous implementation was removed after measurement showed it launched a new Ruby interpreter for every frame (about 0.46 seconds of boot per frame), making one minute of 1080p roughly an hour despite its six-minute estimate; two of eight tests timed out. Do not re-add that path. |
| The old `apply_effects` / `apply_effects_from_recipe` internals | Not restored: the shared recipe and grade dispatchers replace them. Keeping both would create two sources of truth. |

## The video experiment and why it remains a requirement, not resurrected code

The implementation commit [9ac4b113](https://github.com/anon987654321/pub4/commit/9ac4b11332762333da58f8ec4358eec7cbbcb1d4) introduced `Postpro::Motion`, CLI `--video`, and eight tests. It captured the right product rules:

- inspect actual streams with ffprobe; do not trust extensions;
- preserve the original dimensions, the true rational frame rate (for example, 24000/1001), and audio without re-encoding;
- run the same Postpro grade so stills and moving frames do not diverge into two looks;
- distinguish deterministic moving grain (base seed plus frame index) from deliberately held grain;
- print frame count and a runtime estimate before expensive work; test the estimate, audio preservation, reproducibility, and the fact that the grain modes actually produce different output.

The removal commit [ec2cdf45](https://github.com/anon987654321/pub4/commit/ec2cdf458f6f571692fea1ea97e8335881b56135) explains why that implementation is not to be restored verbatim: it launched a fresh Ruby process per frame; measured render time was about an hour per minute of 1080p rather than the promised six minutes, and two tests timed out. Its own estimate was therefore not trustworthy.

A replacement is eligible only when it grades frames in-process (or amortises one interpreter across the frame sequence), enforces a measured per-minute/frame budget, bounds temporary storage, preserves/validates audio and frame timing, uses deterministic temporal state, writes atomically without clobbering the input, and has end-to-end tests that do real work and visibly skip when ffmpeg/ffprobe are unavailable. Until those conditions are met, the honest supported contract is stills only.

## Verification boundary

This document is a historical map, not a test receipt. Current effect reachability, pixel behaviour and CLI behaviour are established by the live `--vocab-check`, focused Postpro tests and `cd STUDIO && rake check test`. A historical commit message saying “green” is evidence about that past revision only.
