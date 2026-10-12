# hear_drums skill contract

MASTER owns whether a source may be inspected, which user intent it serves, and whether the requested operation is allowed. STUDIO owns audio acquisition, separation, measurement, and musical interpretation. MASTER must not duplicate DSP or infer a successful analysis from missing output.

## Canonical call

The skill has one canonical STUDIO entrypoint. Call it through the existing tool dispatch; do not construct ad-hoc shell recipes in model output.

Conceptual Ruby interface:

```ruby
hear_drums(source:, artist: nil, style_tags: [], max_seconds: 60)
```

The implementation must validate source and duration before starting external tools, pass process arguments as arrays (never shell-interpolated strings), and report every stage explicitly.

## Result dossier

A successful result is a structured, machine-readable dossier with:

- `source_hash`: SHA-256 of the exact analyzed source bytes.
- `stem_hashes`: SHA-256 per produced stem, including the drums stem used for analysis.
- `tools`: resolved tool identity/version or an explicit unavailable state for `yt-dlp`, Demucs, and FFmpeg.
- `drum_pattern`: measured BPM, swing hint, step grid, density, and optional residual/error measurements.
- `engine_hints`: bounded, explainable suggestions for Dilla's existing groove engine; hints do not silently mutate presets.
- `style_tags`: normalized labels preserved through analysis.
- `artist`: optional declared artist/profile label, kept separate from style tags.

Do not substitute prose for evidence. Values must be measured or explicitly marked unknown; never fabricate a BPM, hash, stem, tool version, or style label.

## Fail-closed stages

The pipeline is ingest → validate → separate → analyze → derive hints → write dossier. A missing executable, nonzero tool exit, absent/empty stem, malformed measurement, timeout, or failed dossier write is a failed stage with its name and reason. It must not return a success-shaped “couldn't hear” result. Preserve partial diagnostics separately from a successful dossier.

The source hash identifies the exact input; each stem hash identifies the exact artifact measured. Use atomic writes for the final dossier and do not overwrite prior evidence without an explicit versioned destination.

## Multi-artist learning

Store observations by source and keep `artist` and `style_tags` on every learned record. The engine selects a named profile or a deliberate blend of labeled profiles; it must not collapse all training material into a single Dilla-only brain. Artist labels are metadata, not a claim that the output reproduces an artist exactly.

## Boundary and tests

- MASTER: policy, consent/authorization, dispatch, limits, and truthful stage status.
- STUDIO: source handling, Demucs/FFmpeg invocation, signal analysis, hashes, and musical hints.
- Test success and each failure stage with fake tool adapters; tests must not require network access or a local Demucs model.
- Test that a missing tool or missing drums stem cannot produce a successful dossier.
- Test deterministic schema, SHA-256 correctness, style-label preservation, and bounded duration.
- No live network, model download, or audio DSP implementation belongs inside MASTER.

This file is the interface contract, not evidence that the runtime implementation or end-to-end audio pipeline has already passed validation.
