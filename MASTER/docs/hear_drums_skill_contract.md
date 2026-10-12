# hear_drums skill contract

MASTER owns whether a source may be inspected, which user intent it serves, and whether the requested operation is allowed. STUDIO owns audio acquisition, separation, measurement, and musical interpretation. MASTER must not duplicate DSP or infer a successful analysis from missing output.

## Status

Implemented and tested with fake adapters: the STUDIO pipeline in `STUDIO/dilla/lib/hear_drums.rb`, reached as `ruby STUDIO/dilla/dilla.rb hear-drums <source> [--artist NAME] [--style a,b] [--max-seconds N]`, and the MASTER policy and dispatch in `Contracts::Studio.hear_drums` (`MASTER/contracts/studio.rb`). The tests are `STUDIO/test/test_dilla_hear_drums.rb` and `MASTER/test/test_studio_hear_drums_contract.rb`; they inject the process runner, the executable resolver and the analyzer, so they need no network, model or audio tool.

Not yet proven: a real Demucs separation, a real yt-dlp download and a full real-audio dossier have not been run on this Mac. A real run against a garbage file failed closed at ingest with the true ffmpeg error, which shows the dispatch and tool probes work; it does not show the drums stem or the measurements are good. The analyzer is the engine's existing `drum_step_grid_from_wav`, so its accuracy is whatever that measurement already was. The `residuals` field is carried when the analyzer supplies it and is `null` otherwise; no analyzer produces it yet. Blending several labeled profiles at generation time is not built; `HearDrums.learned_records` only selects records by artist or style tag.

## Canonical call

The skill has one canonical STUDIO entrypoint. Call it through the existing tool dispatch; do not construct ad-hoc shell recipes in model output.

Conceptual Ruby interface:

```ruby
hear_drums(source:, artist: nil, style_tags: [], max_seconds: 60)
```

The STUDIO entrypoint takes the same arguments plus injectable adapters; MASTER adds `authorized:` (the operator confirms the right to analyze the source) and `allow_network:` (required for any URL), and limits `max_seconds` to 120 where STUDIO's own ceiling is 600. The implementation validates source and duration before starting external tools, pass process arguments as arrays (never shell-interpolated strings), and report every stage explicitly.

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

The pipeline is validate → ingest → separate → analyze → derive hints → write dossier. Request validation (source, duration, labels) runs first, before any process starts; ingest then checks that the fetched source and the trimmed analysis clip are non-empty. A required tool that is missing is reported before any download or clip is made. A missing executable, nonzero tool exit, absent/empty stem, malformed measurement, timeout, or failed dossier write is a failed stage with its name and reason. It must not return a success-shaped “couldn't hear” result. Failures carry `stage`, `kind` (`invalid_input`, `tool_unavailable`, `tool_failed`, `timeout`, `empty_output`, `malformed_measurement`, `write_failed`), `reason` and a `diagnostics` block (completed stages, tool identities, source hash when known, labels); a failure never contains a `dossier`. MASTER trusts a result only when STUDIO reports `ok` with a dossier holding the required evidence, and reports capability as `available`, `degraded: reason` or `unavailable: reason`.

The source hash identifies the exact input; each stem hash identifies the exact artifact measured. Use atomic writes for the final dossier and dossiers are written to `STUDIO/dilla/project/learnings/hear_drums/<source_hash>/vNNNN.json`, each run adding the next version with a no-clobber link so earlier evidence is never replaced.

## Multi-artist learning

Store observations by source and keep `artist` and `style_tags` on every learned record. The engine selects a named profile or a deliberate blend of labeled profiles; it must not collapse all training material into a single Dilla-only brain. Artist labels are metadata, not a claim that the output reproduces an artist exactly.

## Boundary and tests

- MASTER: policy, consent/authorization, dispatch, limits, and truthful stage status.
- STUDIO: source handling, Demucs/FFmpeg invocation, signal analysis, hashes, and musical hints.
- Test success and each failure stage with fake tool adapters; tests must not require network access or a local Demucs model.
- Test that a missing tool or missing drums stem cannot produce a successful dossier.
- Test deterministic schema, SHA-256 correctness, style-label preservation, and bounded duration.
- No live network, model download, or audio DSP implementation belongs inside MASTER.

This file is the interface contract. The pipeline logic has passed its fake-adapter tests; the end-to-end audio pipeline with real Demucs, yt-dlp and a real recording has not been validated, and the dossier is evidence of measurement, not of musical quality.
