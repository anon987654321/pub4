# Valuable fossils — pub4 / pub3 / pub2 / pub

This is a recovery index, not a restore list. Each entry points to a concrete historical commit that introduced, restored, or deliberately consolidated something potentially worth preserving.

## pub4: recent recovery lineage

- `9cfe80114ec558369ced9aa5178804f907953e83` — repaired MASTER self-corruption; recovered 100+ files; made the tree parseable; added source attribution for 173 rules; disabled background autofix by default; separated `cli.rb`; repaired Rails boot scaffolding.
- `5a5db63e559cdf492893ec88472e61ede36b75d5` — cognitive runtime architecture, provider routing, runtime telemetry/event contracts, append-only runtime event log, event bus integration, migration plan, self-audit and Git-history miner.
- `b95364de8a0b5b68947064544b2d95e990d36128` — persisted interrupted Git delivery and recovery transactions so a `/fix` resume does not lose its transaction boundary.
- `830ec870fef43e087a6caee57c33a9f484432d70` — exposed a blind spot where deleted directories made citations into them invisible to the gate.
- `9a2f56b94ec64065fab9caa8a1f8befa010d0805` and `b06a8f972cc9110022d137ac01db4464245c10a2` — recovered constitution memoization after a bad edit.
- `f34dd7c3f2f3ce9f928bfd0b757955664632ae81` — recovered the larger `master.yml` v71.7.0 lineage and merged later validation/convergence pieces.
- `a436fa789ecaff868c071b25acb279e45d26800b` — recovered x-parity primitives and guard work from deleted execute-plan history.

## pub4: media / UI fossils

- `d3b5107911818b7c51e06e540b68a73d56f36784` — recovered 2019 postpro material; documented that the 1,250 DCP profiles lacked actual ToneCurve/LookTable/HueSatDelta film data, avoiding a false claim of full emulation.
- `0455c8ee9bf8d80476bdb1315900a28041cbe03e` — recovered seven visualisers from a deleted host file.
- `b8b6f4167034a9551c719bb6ed23e5b93e709a` — restored six `lora/guides` files removed during tidying.
- `ee181e4ab1b6284f55caddb74e6f1d311de9fe56` — recovered discarded Dilla vocal stems and built a synthesiser around them.
- `63277c129b36996c74f65eb306dd3b8686524cef` — made the drummer read the historical 62-grid MIDI library instead of guessing.
- `51b205d4050c45e1c2c86425e31e4e425490313d` — repaired the radio playlist startup path and added archaeology logging.
- `3c9e69456b249fb3a34021eb80a87697fb9be993` — folded the one-off Dilla remix driver into the engine with per-stem grade racks.
- `6234f9fcbba958335a175d0e40171eb7dab513c` — ambient-pad system with crossfade, ducking, iOS handling, and Web Audio effects.

## pub3: independent branch worth keeping

- `my-work` tip: `d1f2770fc43fd0e85e9d640d71e9b0748fd9712e`, 156 commits ahead of `main`.
- `d1f2770fc43f` — `master.json` v50 plus audio work.
- `32c1fdf0044d` — `master.json5` v6.0.0 plus Rails apps.
- `cbaa680f3442` — failsafe JSON5 / zero-violation architecture and intelligence modulation.
- `ff5e37c89654` — environment constraints and lessons from an audio playback session.
- `5ace9e686bdd` — moved `postpro.rb` to a consolidated multimedia location.
- `92d9b7abdb12` — consolidated Dilla audio-generation logic.
- `bd03ed1d7796` — completed the zsh rewrite under `master.json` governance.
- `5f7873989ff4` — repaired VIPS compatibility so the new postpro effects actually worked.
- `8ad7da8a52ce` — added ultraminimal professional Rails layouts.

## pub2: concrete restoration fossils

- `818ea0d03770` — restored unique old-backup material: AI3 framework/validation modules, business-plan material, shared Rails utilities, and the J-Dilla carousel.
- `849344fa2796` — restore/upgrade PR carrying the larger `master.json` and Rails documentation work.
- The restored AI3 set included `master_framework_complete.rb` (749 lines), `master_framework_efficient.rb` (580), `master_framework_engine.rb` (697), and `master_validation_suite.rb` (490).

## pub: older consolidation line

- `21598560b57a` — restored 2,878 lines of AI3 code from the old-backup lineage.
- `90d16d085bed` — restored AI3/EGPT backup files and enhanced functionality.
- `6ecbd7b92b95` — split a large `master.json` into modular files for maintainability.
- `fe7081d7796d` — Master Framework v37.1.0 with design-intelligence integration.
- `512715ac6edd` — postpro v13.3.14 with 29 effects and advanced features.
- `55b89773cfca` — AI³ platform consolidation/core implementation.
- `01746ec9542f` — recorded a 16.7% consolidation reduction while preserving functionality.
- `3bfd407493bd` — restored original user comments while retaining JSON improvements.

## What not to resurrect blindly

- Backup files, duplicate assistants, old build scaffolding, and archives themselves remain source material.
- `pub3/sh/restore_backups.sh` only implements the first `egpt_20240806.tgz` restoration priority; it is not a complete archive extractor.
- The old repos contain multiple identical archive blobs under different filenames. The new extractor deduplicates by Git blob SHA.
- Promotion rule: compare recovered material against current `pub4` and its intact history; restore only unique, tested, or explicitly authoritative logic.