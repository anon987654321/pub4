# STUDIO TODO

Updated: 2026-10-12. Delete an entry when it is done. Cross-tree coordination lives in the repository-root `TODO.md`; runtime-intent defects belong in `MASTER/TODO.md`.

## P0 — privacy and broken paths

- [ ] Re-run the private-media gate and confirm the 17 tracked Ragnhild `retouched/` portraits are absent from the current tree. Prior public commits still contain historical blobs; history rewriting/force-pushing is outside this cleanup and needs a separate coordinated decision.
- [ ] Run `test_tools_postpro_dispatch.rb` and reproduce the former `--preset fx` invocation with and without `--output` on the pinned Ruby/libvips stack. Source now exits early when `--preset` is supplied without the required `--input` and `--output`, and reports unknown names; confirm bounded exit and fix any real caller still sending `fx`.
- [ ] Run the postpro regression suite after this sweep. Source changes now prevent arbitrary forced analog steps from violating the measured preset co-occurrence graph, split the heavy-default contract from the subtle-lane test, and add a bounded failure for `--preset` without required input/output paths. Also classify the reported failures in `the_tools_own_self_check_passes`, `the_default_posture_is_subtle`, `a_graded_frame_records_its_version...`, and `every_step_co_occurs_with_every_other...`. No source-level claim substitutes for real suite output.
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

### LoRA likeness

- [ ] Collect 15–25 sharp photographs per subject, at least 1024 px on the short edge, across frontal and three-quarter angles, varied light and expression. Exclude caps, hoods, sunglasses and face paint; drop Johann's black-and-white teen portrait.
- [ ] Find out whether any source photographs behind Ragnhild's 2026-09-15 LoRA remain available. Her recorded set lacks a usable frontal image and consists of profile or blurred crops with face paint.
- [ ] Retrain from the improved datasets without `--force`; caption without describing face shape, eye colour, hair colour or age. Check Johann's beanie artifact by training without hat photos, and compare Ragnhild at `lora_scale 0.85` against the recorded 1.0 result.

### Reference-photo route

- [ ] Wire `lora --reference` to accept one reference photo plus a prose prompt, use the same before/after cost reporting and ledger, and apply the postpro grade. The 2026-10-11 trial of `zsxkib/flux-pulid` used four renders and billed 54.7 seconds; likeness improved, but reference pose and clothing also carried through.
- [ ] Accept the provider's `webp` and `png` outputs; `jpg` failed with `'JPG'`. Compare `black-forest-labs/flux-kontext-pro` and rerun from the best frontal source once one is available.

### Video and paid-provider safeguards

- [ ] Use the existing Wan 2.2 draft cut as the baseline. Try one Veo 3.1 Fast clip only after printing the cost and enforcing a roughly $5 ceiling; verify regional/real-person-photo acceptance first, with Kling as the documented fallback. Clip prices are not exposed in the API, so check the actual bill and label any estimate unavailable when needed.
- [ ] Add a repeatable cost preflight and ledger contract for every paid call: estimate before work, enforce a cap before the call, and record billed/observed cost afterward.
- [ ] Cache video-grade LUTs by preset and measured point count. Preserve a representative quality fixture: 13-point export was recorded at about three minutes and 33-point export at about 35 minutes.

### Postpro quality

- [ ] Measure every postpro preset against a documented reference curve and keep a regression fixture for the subtle default. Record tool version, recipe and input hashes so the grade is reproducible.

### Remaining regression work

- [ ] Run and classify the reported existing failures in `test_tools_lora`, `test_tools_replicate`, `test_gate_chain`, `test_review_inference`, `test_fix_convergence`, and `test_tree_contract`. Fix the source when the test is right; update or remove a test only when its contract is demonstrably obsolete.
- [ ] Run the existing `TurnRouterTest` regression for MASTER's “make a video with the lora of me” route, then verify the intent/provider path end to end.

## Tooling, outputs and KISS

- [ ] Check output defaults for `visual/`, `photograph.rb`, `gate.rb` and `isolation.rb` against the rule that tools render beside their own Ruby file, while dated/irreplaceable deliverables remain outside the repository. Add path tests for relative paths and invocation from another working directory.
- [ ] Redo the Dilla, postpro and Replicate READMEs: explain canonical entrypoints, where outputs land, the current pattern files, provider cost behavior and safe reruns.
- [ ] Verify MASTER's “generate me a selfie” route end to end once its intent/provider path is fixed; keep command routing and shell-safety work in [MASTER/TODO.md](../MASTER/TODO.md).
- [ ] Keep test isolation by subject because top-level constants collide across tool suites. Fix order-dependent fixtures rather than loading everything into one process or adding permanent global shims.

## Proof surfaces

`cd STUDIO/test && rake`, isolated Dilla/postpro/Replicate subject suites, `STUDIO/test/gate.rb`, source/provenance checks, actual rendered files, provider cost ledger and operator listening evidence.
