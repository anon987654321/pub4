# STUDIO TODO

Updated: 2026-10-11. Delete an entry when it is done. Cross-tree coordination lives in the repository-root `TODO.md`; runtime-intent defects belong in `MASTER/TODO.md`. The detailed LoRA backlog is `STUDIO/replicate/lora/TODO.md`.

## P0 — privacy and broken paths

- [ ] Re-run the private-media gate after this sweep removes the 17 tracked Ragnhild `retouched/` portraits from the current tree. Prior public commits still contain their historical blobs; history rewriting/force-pushing is intentionally not part of this commit and needs a separately reviewed, coordinated decision.
- [ ] Trace the caller that passes unsupported preset `fx`, replace it with a declared preset or correct its intent, and reproduce why the command consumes over two minutes of CPU without `--output`. Unknown preset names now fail fast with the valid preset list instead of silently returning the input; the caller and hang remain unverified.
- [ ] Run the postpro regression suite after this sweep. Source changes now prevent arbitrary forced analog steps from violating the measured preset co-occurrence graph, split the heavy-default contract from the subtle-lane test (their old assertions conflicted), and add a bounded failure for `--preset` without the required input/output paths. The self-check and sidecar-version tests still need actual suite output; do not claim them fixed by source inspection.
- [ ] Run the Dilla patch-only showcase regression and render `opus3_strings`, `matriarch_stabs`, `grandmother_sweep`, `vox_humana` and `e_piano` through the actual audio/video path. The score dispatcher now routes these declared patches to `Demo`; verify the generated output before closing this item.

## Dilla — correctness before extra polish

- [ ] Reproduce and fix the recorded failures in `test_dilla_engine_probes` (6 failures, 2 errors), `test_dilla_composer_mind` (1 failure), and `test_dilla_musical_grammar` (1 failure, 2 errors). The assembly-offset/recipe test also errors alone while passing in the full file; remove test-order dependence and prove isolated execution.
- [ ] Render—not just syntax-check—the rolled hand's ffmpeg expression containing `gte(t,…)`. Verify timing, audio continuity and video output with a short deterministic fixture.
- [ ] Either use the Moog `ladder_sat` self-oscillation in a deliberate patch with a regression fixture, or remove the dead path. Add the missing hat-accent velocities to the boom-bap library and test velocity-to-audio behavior.
- [ ] Render a short A/B take for each 2026-10-11 change before keeping it: velocity-shaped synth timbre, Rhodes pickup bark and uneven tremolo, seeded Prophet drift/poly-mod, Moog ladder saturation, scored chord voicings/seeded rolled hand, boom-bap patterns and the `hate`/`techno` profiles. Nobody's source-level claim substitutes for listening; keep or revert each change on evidence.
- [ ] Compare reproducible renders with `data/dilla_reference.yml` for loudness and spectrum. Check mix glue (shared room, restrained tape saturation and bus compression) and SP-1200-style drum conversion/noise against the reference, not just by taste; preserve seed, settings and the original take.
- [ ] Read the missing style references before revising the hip-hop and techno patterns: Hein's Dilla-time essay, Frere-Jones's writing, and the relevant artists' own mixes. Record provenance and distinguish historical reference from an unverified imitation claim.
- [ ] Recheck live playback's declared sample rate, latency and interruption behavior on target hardware. Render and live modes must share the same timing/gain contract, without duplicate playback owners or speech overlap.

## Replicate, LoRA and postpro

- [ ] Work through [the LoRA backlog](replicate/lora/TODO.md): improve training data quality before prompt tweaking, test the reference-photo route, fix accepted image output formats, and add a bounded cost-aware video path.
- [ ] Add a repeatable cost preflight/ledger contract for every paid provider call. Print a trustworthy estimate before work and the billed/observed result after it; where the API exposes no clip price, label the estimate as unavailable and verify the actual bill. Enforce the declared cap before a call, not after spend.
- [ ] Cache video-grade LUTs by preset and measured point count. Keep a representative quality test so performance improvements do not silently change the grade.
- [ ] Measure each postpro preset against a documented reference curve and test that the default is subtle. Record tool/version/recipe/input hashes so a grade can be reproduced.

## Tooling, outputs and KISS

- [ ] Check output defaults for `visual/`, `photograph.rb`, `gate.rb` and `isolation.rb` against the rule that tools render beside their own Ruby file, while dated/irreplaceable deliverables remain outside the repository. Add path tests for relative paths and invocation from another working directory.
- [ ] Redo the Dilla, postpro and Replicate READMEs: explain canonical entrypoints, where outputs land, the current pattern files, provider cost behavior and safe reruns.
- [ ] Add a live end-to-end test for MASTER's “generate me a selfie” route once its intent/provider path is fixed; keep command routing and shell-safety work in [MASTER/TODO.md](../MASTER/TODO.md).
- [ ] Keep test isolation by subject because top-level constants collide across tool suites. Fix order-dependent fixtures rather than loading everything into one process or adding permanent global shims.

## Proof surfaces

`cd STUDIO/test && rake`, isolated Dilla/postpro/Replicate subject suites, `STUDIO/test/gate.rb`, source/provenance checks, actual rendered files, provider cost ledger and operator listening evidence.
