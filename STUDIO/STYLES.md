# STUDIO style contracts

The shared style contract lives in `styles/registry.yml`; its validator is `style_registry.rb`. Image, prompt and audio entries are separate modality artifacts under one style identity. Released entries are versioned rather than silently edited.

`postpro/lib/quality_analyzer.rb` accepts sampled luminance values and optionally RGB samples, and returns measured diagnostics. It intentionally does not claim to judge composition, focus or semantics. `correction_proposer.rb` returns bounded, reviewable proposals rather than changing pixels.

`replicate/scene_compiler.rb` deterministically compiles structured scene fields against a declared vocabulary and character map. Unknown concepts are reported instead of invented. `replicate/replay_manifest.rb` hashes prompts without storing their private text and verifies output hashes.

`dilla/style_adapter.rb` validates ABC score headers and delegates full grammar and theory checks to an explicitly supplied engine validator. It validates human-readable mix parameters; it does not claim to run a learned model or render audio.

The initial implementation adds the contract boundaries and unit tests. The photo diagnostic is not yet wired into pixel-level image correction, and learned LUT, neural grain, external ABC generation, and differentiable mixing remain unavailable until their concrete dependencies and measured behavior are integrated. Those capabilities must not be advertised as ready merely because an adapter interface exists.
