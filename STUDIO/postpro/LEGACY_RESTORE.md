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

## dilla analog bridge

Dilla's analog processing was also mined for mechanisms that make sense in a still-image domain.

`dilla_head_bump` translates the tape chain's low-frequency head bump into broad luminance density.

`dilla_tape_saturation` translates the liveset's tanh tape drive into a restrained image soft-clip/shoulder, preserving the current film stock as the colour authority.

`dilla_vinyl_bandlimit` translates vinyl/tape bandwidth loss into a very shallow spatial high-frequency roll rather than a generic blur.

`dilla_phasy` translates the NastyVCS phase-offset sum (`[0, 13, 29, 47]` audio samples) into tiny deterministic chromatic/spatial registration offsets. It is an image analogue, not a literal sample-to-pixel conversion.

`dilla_console_sum` translates several gently voiced parallel console passes into a small spatially offset sum.

Named looks now expose the useful Dilla chain vocabulary: `dilla_vinyl_hot`, `dilla_summing_phasy`, `dilla_tape`, and `dilla_acetate`.

Temporal audio phenomena such as real capstan wow/flutter cannot be truthfully reproduced in one still frame; those belong in the video/frame-sequence path, where the deformation can evolve over time.