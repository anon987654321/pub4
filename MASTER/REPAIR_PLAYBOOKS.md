# Repair Playbooks

## Self-Test Failure

Symptom: `rake selftest` exits non-zero.

First command: `rake selftest`.

Read the law buckets first. Fix `SINGULARITY` and `KERNEL_ADHERENCE` before broad style debt. For ROBUSTNESS, LINEARITY, ABSTRACTION, and DENSITY, classify findings before editing.

## Asset Drift

Symptom: `test_public_asset_manifest_matches_source_files` fails.

First command: `ruby -Ilib:test test/test_web_ui.rb --name test_public_asset_manifest_matches_source_files`.

Regenerate Rails assets, then verify the digested file contents match source files in the boot manifest, `particle_kernel.js`, and `face.part*.txt`.

## Web Boot Or Tap Failure

Symptom: primer tap does nothing, prompt never appears, or face blocks the main thread.

First command: `bin/check --profile=web`.

Then inspect `web/CLAUDE.md`. Confirm WebGL is blocked before `_primerFired` and allowed after the tap. Do not move THREE.js or face import back into initial page load.

## Provider Or Key Failure

Symptom: model routing fails, provider unavailable, or keyless route misbehaves.

First command: `ruby -Ilib:test test/test_provider_config.rb`.

Check `data/providers.yml`, `data/models.yml`, and `lib/cli/routing/model_router.rb`. Preserve fallback order and do not print secrets.

## Namespace Audit Failure

Symptom: `bin/nsaudit` or `bin/probe all` reports stale constants or duplicate namespace shape.

First command: `bin/nsaudit`.

Check whether the finding crosses the known `lib/` and `core/` spine boundary. If yes, document or refine the skip. If no, fix stale references.

## YAML Singularity Failure

Symptom: `rake lint:data_singularity` fails.

First command: `rake lint:data_singularity`.

Do not rename keys blindly. Identify whether the files are registries, scoped records, or intentional parallel vocabulary. Merge true duplicates; otherwise add a narrow documented allowance in `SelfTest`.
