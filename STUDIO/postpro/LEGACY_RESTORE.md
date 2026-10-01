# legacy postpro restore

The old `pub/postpro` implementation from the 2025 v13.3.14 line carried a separate creative vocabulary that was later replaced by the measured STUDIO/postpro pipeline.

Recovered into `STUDIO/postpro/legacy_effects.rb`:

- double exposure
- polaroid frame
- tape degradation
- frame distortion
- Super 8 flicker
- CinemaScope bars
- halftone print
- film scratches
- film stock emulation
- sprocket holes
- lens flare
- VHS degrade
- colour fade
- anamorphic simulation
- soft focus

The compatibility layer deliberately does not copy the old film-stock RGB multipliers. `film_stock_emulation` delegates to the current H&D curve and stock matrix, so the old command name now lands on the newer measured model.

The old damage-heavy effects are available as recipe effects. Named `legacy_*` presets restore the creative vocabulary without changing the current house grade.

This restore does not resurrect the old frame-by-frame video path. Current postpro still needs an in-process ffmpeg video pipeline with a frame-stable grain seed, stable halation, shutter-angle treatment, bounded work, and still/video parity checks.
