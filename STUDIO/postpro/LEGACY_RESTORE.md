# legacy postpro restore

The archived `anon987654321/pub/postpro` v13.3.14 line exposed 29 user-facing creative effects.

Five of those already had current equivalents in STUDIO/postpro:

`light_leaks`
`lens_distortion`
`bleach_bypass`
`day_for_night`
`chromatic_aberration`

The remaining 24 archive names have been restored through `STUDIO/postpro/legacy_effects.rb` and wired into the current dispatcher and recipe vocabulary:

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

The compatibility implementations are deliberately improved rather than byte-for-byte copies of the archive. Film-stock emulation delegates to the current measured H&D curve and stock matrix. VHS, halation, bloom, cross-process, anamorphic and grading aliases delegate to current implementations where those are more physically grounded. The remaining effects preserve the old creative affordance with bounded parameters.

Named `legacy_*` presets restore the useful archival looks without changing the current `house` grade.

The old internal `apply_effects`, `apply_effects_from_recipe` and random driver functions are not restored because current postpro already has a safer recipe engine, measured random-chain generator, provenance, and validation.

This restore does not resurrect the old frame-by-frame video path. Current postpro still needs an in-process ffmpeg video pipeline with a frame-stable grain seed, stable halation, shutter-angle treatment, bounded work, and still/video parity checks.
