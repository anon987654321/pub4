# legacy postpro restore

The old `anon987654321/pub/postpro` implementation from the 2025 v13.3.14 line carried 24 user-facing creative effects. The current STUDIO/postpro engine now exposes all 24 names through a compatibility boundary.

Recovered vocabulary:

`film_grain`
`film_halation`
`bloom_effect`
`cross_process`
`golden_hour_glow`
`lomo`
`sepia`
`teal_and_orange`
`anamorphic_simulation`
`vhs_degrade`
`color_fade`
`soft_focus`
`double_exposure`
`polaroid_frame`
`tape_degradation`
`frame_distortion`
`super8_flicker`
`cinemascope_bars`
`halftone_print`
`film_scratches`
`film_stock_emulation`
`sprocket_holes`
`lens_flare`
`glitch`

The compatibility implementations are deliberately improved rather than byte-for-byte copies of the archive. Film-stock emulation delegates to the current measured H&D curve and stock matrix. VHS, halation, bloom, cross-process, anamorphic and grading aliases delegate to current implementations where those are more physically grounded. The remaining effects preserve the old creative affordance with bounded, deterministic parameters.

The old internal `apply_effects`, `apply_effects_from_recipe` and random driver functions are not restored because current postpro already has a safer recipe engine, measured random-chain generator, provenance, and validation.

Named `legacy_*` presets were added for the commonly useful archival looks. The current `house` and other measured presets remain unchanged.

This restore does not resurrect the old frame-by-frame video path. Current postpro still needs an in-process ffmpeg video pipeline with a frame-stable grain seed, stable halation, shutter-angle treatment, bounded work, and still/video parity checks.
