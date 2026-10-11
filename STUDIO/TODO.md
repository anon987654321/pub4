# STUDIO TODO

Written 2026-10-11. Delete an entry when it is done. The lora backlog is in `replicate/lora/TODO.md`.

## dilla: listen and decide

Nobody has heard the 2026-10-11 changes. Render one short clip of each and keep or revert each.

- Synth patches (`lib/sound.rb`): velocity-shaped timbre, Rhodes pickup bark and uneven tremolo, Prophet seeded drift and poly-mod, saturating Moog ladder.
- Pocket chords (`lib/harmony.rb`): scored voicing search and the seeded rolled hand. `POCKET_HAND=0` turns the hand off.
- Boom-bap library (`data/boom_bap_patterns.yml`, `lib/beat_library.rb`): `dilla.rb hiphop`.
- Techno profiles (`lib/techno_patterns.rb`): `TECHNO_PATTERN=<name>` with `hate` and `techno`.

## dilla: finish what the agents left out

- The rolled hand's ffmpeg expression (`gte(t,…)`) was syntax-checked and never rendered.
- The Moog `ladder_sat` self-oscillation exists and no patch uses it.
- Hat accent velocities are missing from the boom-bap library.
- Read the sources the agents did not. The hip-hop agent searched nothing; the techno agent had one Dummy article, one Resident Advisor page for Klock and search snippets. Read Hein (ethanhein.com/wp/2022/dilla-time), Frere-Jones (4columns.org) and the Hate podcast artists' own mixes, then revise the patterns and their `_style` names to match.

## dilla: more beauty and authenticity

- Mix glue: tape saturation, a slow bus compressor and one shared room reverb, so the parts sound like one performance.
- Sample character: 12-bit, 26 kHz SP-1200-style conversion on drum hits, and barely audible vinyl noise.
- Check by measurement: compare each render's spectrum and loudness with `data/dilla_reference.yml`.

## Tests that do not pass

- `test_dilla_live_synth` aborts with "no showcase scene opus3_strings".
- `test_dilla_engine_probes` has 6 failures and 2 errors that predate this work. `test_an_assembly_records_its_parts_with_offsets_and_their_recipes` errors alone and passes in the full file.
- `test_dilla_composer_mind` has 1 failure; `test_dilla_musical_grammar` has 1 failure and 2 errors.
- Four postpro tests fail (see the lora TODO).

## Tooling

- Output defaults: `visual/`, `photograph.rb`, `gate.rb` and `isolation.rb` were not checked against the rule that a tool renders beside its own ruby file.
- Add an `operator` command that lands a worktree branch onto origin/main without touching a dirty checkout. This session did it by hand with a temporary worktree and `git reset --keep`.
- Add a Replicate price check that prints dollars before and after, once a source for clip prices exists.
- Redo the READMEs for `dilla`, `postpro` and `replicate` (README_PROSE): they should say renders land beside the ruby file, and name the new pattern files.
- MASTER's "generate me a selfie" works at unit level and has no live test.
