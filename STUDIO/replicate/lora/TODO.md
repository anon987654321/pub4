# lora TODO

Written 2026-10-11. Delete an entry when it is done.

## Likeness (the main problem)

The faces do not look like Johann or Ragnhild. The cause is the data. Johann's dataset is 5 images from 8 sources, Ragnhild's is 3 from 3, and both trainings were forced past the 10-image minimum in Replicate's fine-tuning guide. Prompts and `lora_scale` will not fix that.

- Collect 15 to 25 photos per subject: sharp, 1024 px or more on the short edge, frontal and three-quarter faces, varied light and expression. No caps, hoods, sunglasses or face paint. Drop the black-and-white teen portrait from Johann's sources.
- Ragnhild has no frontal source at all; the three she has are profile or blurred crops with face paint. Check whether any of the photos behind her 09-15 LoRA are still on disk.
- Retrain each from the new set with `--force` removed (about $10 each, Johann's last run billed 792 s). Write captions that leave out face shape, eye colour, hair colour and age, as the caption law says.
- Johann's beanie frames come from the adapter, not the prompt. Retrain without the hat photos before judging him again.
- Test a lower `lora_scale` (0.85) for Ragnhild, whose frames look older and gaunt at 1.0.

## Reference-photo route (no training)

2026-10-11 test: `zsxkib/flux-pulid` on one photo each, 4 renders, 54.7 s billed (about $0.08). The likeness looked better than the LoRA frames, but the references carry their pose and clothing (Johann's hood became a beanie in both frames; Ragnhild's tilt and expression came through). Frames are in `out/<subject>/reference_test/`.

- Wire it in as `lora --reference`: one photo in, prose prompt, the same cost-before and cost-after lines, ledger rows, and a postpro grade on top.
- Its output format is `webp` or `png`; `jpg` fails with `'JPG'`.
- Try `black-forest-labs/flux-kontext-pro` the same way and compare.
- Once there are frontal photos, rerun the test from the best one.

## Video

- The Wan 2.2 draft cut exists (`out/ragnhild/video/ragnhild_draft_cut.mp4`, graded with 13-point LUTs plus grain via ffmpeg).
- Veo 3.1 Fast final: one clip first with a printed cost and a ceiling of about $5. Check that Veo accepts a real person's photo from this region; Kling is the fallback. Clip prices are not in the API, so read the bill.
- Make the video grade a tool: LUT export at 13 points takes about 3 minutes, 33 points about 35. Cache LUTs by preset name.

## Postpro

- The `fx` preset does not exist (`Unknown preset: fx`), and without `--output` the same command spins for over 2 minutes at full CPU. Find the hang.
- Four tests in `test_tools_postpro.rb` fail before and after the 2026-10-11 work: `the_tools_own_self_check_passes`, `the_default_posture_is_subtle`, `a_graded_frame_records_its_version...`, `every_step_co_occurs_with_every_other...`.
- Grades are liked but can improve: measure each preset against a reference stock's curve, not by eye.

## Cleanup

- Seventeen tracked Ragnhild `retouched/` portraits still violate the private-media test.
- Pre-existing failing suites: `test_tools_lora`, `test_tools_replicate`, `test_gate_chain`, `test_review_inference`, `test_fix_convergence`, `test_tree_contract`.
- MASTER's "make a video with the lora of me" ran `make` as a shell command; find the interception. Review `d91e67941`'s edit to `lora_intent.rb`.
