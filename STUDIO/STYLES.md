# STUDIO style contracts

The shared style contract lives in `styles/registry.yml`; its validator is `style_registry.rb`. Image, prompt and audio entries are separate modality artifacts under one style identity. Released entries are versioned rather than silently edited.

`postpro/lib/quality_analyzer.rb` accepts sampled luminance values and optionally RGB samples, and returns measured diagnostics. It intentionally does not claim to judge composition, focus or semantics. `correction_proposer.rb` returns bounded, reviewable proposals rather than changing pixels.

`replicate/scene_compiler.rb` deterministically compiles structured scene fields against a declared vocabulary and character map. Unknown concepts are reported instead of invented. `replicate/replay_manifest.rb` hashes prompts without storing their private text and verifies output hashes.

`dilla/style_adapter.rb` validates ABC score headers and delegates full grammar and theory checks to an explicitly supplied engine validator. It validates human-readable mix parameters; it does not claim to run a learned model or render audio.

The initial implementation adds the contract boundaries and unit tests. The photo diagnostic is not yet wired into pixel-level image correction, and learned LUT, neural grain, external ABC generation, and differentiable mixing remain unavailable until their concrete dependencies and measured behavior are integrated. Those capabilities must not be advertised as ready merely because an adapter interface exists.

## Current entry points

- `ruby postpro/postpro.rb --quality PHOTO.jpg` emits a bounded sampled-pixel report and writes no render.
- `ruby postpro/postpro.rb --input IN.jpg --output OUT.jpg --preset house --stabilize` opts into the existing bounded source-balancing pass before the style grade. This path records measured before/after diagnostics and the proposed corrections; the proposals are advisory and are not misreported as the exact operations applied.
- `--style-contract blue_hour` validates and records an image-modality contract in postpro output metadata. The record explicitly says `mapping_applied: false`: the current registry has no executable parameter mapping, so this flag does not claim to apply that style.
- `ruby replicate/replicate.rb generate --scene-json scene.json --dry-run` compiles a JSON document with a required `prompt` string and optional `fields` map. Field names and values must resolve in the existing Replicate vocabularies; unknown keys and values are rejected before generation.
- `--style-contract blue_hour` on Replicate validates the prompt-modality entry and records the registry digest and version in provenance. The contract is provenance/validation, not an automatic prompt rewrite.
- `ruby dilla/score_check.rb --abc score.abc --style-contract blue_hour` validates ABC headers and invokes `abc2midi` as a standard parser. Exit status 3 with an `unavailable` report means the parser is absent; it never reports a score as valid without the external parse. This is not an audio render and does not claim that the truncated Dilla DSP source has validated or rendered the score.

These entry points make registry lookup, provenance, deterministic prompt compilation, and pre-grade diagnostics operational. They do not yet provide an executable image-style parameter map, neural LUT, neural grain, external music generation, or full score-to-Dilla-render pipeline. Those stay unavailable until they are implemented and tested.
