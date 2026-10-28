# pub3 restoration archaeology — 2026-10-28

Scope: recursive inventory of `anon987654321/pub3` at `835f9199d605b6a6ae1f32cd207919c115a06b47`, with BAIBL, Blognet, Hjerterom and Privcam explicitly excluded as obsolete per the repository owner's instruction. This is a focused restoration audit, not a byte-by-byte review of all source, media or Git objects. No files were copied from pub3.

## Inventory

- Git tree: 513 entries total; 505 entries after the excluded product paths; 451 remaining file blobs; 569,336,626 bytes of remaining blobs (about 569 MB).
- The bulk is multimedia data and historical audio/video/image assets, not missing application source.
- The old tree is a mixture of scripts, saved/generated HTML, installers, platform binaries, cached media and documentation. It is not a coherent snapshot to overlay on pub4.

## Findings and disposition

| Area | Finding against current pub4 | Decision |
|---|---|---|
| Radio Bergen / Playlist | `pub3/index.html` and `rails/VISUALIZER_INTEGRATION.md` document a legacy standalone warp tunnel, dual YouTube/MP3 sources, touch/keyboard behaviours and alternate visualizer modes. The current owner is `RAILS/brgen/app/javascript/radio_brgen_tunnel.js` plus the Playlist Rails engine, waveform, transports, Active Storage and playlist models. The repository owner has explicitly selected this current tunnel as the visualizer to keep. | **Preserve the current tunnel; do not restore the old standalone page or competing modes.** The home view now renders the tunnel through the Playlist engine. Exact archive-list metadata is recorded in the Radio Bergen manifest; audio migration remains a guarded operator action. |
| Dilla progression data | `multimedia/dilla/dilla_data.json` consolidates 42 chord sequences plus synth/effect/drum material. Comparison of its chord sequences against pub4's canonical and recovered Dilla data found a sequence equivalent for all 42 musical progressions (allowing the existing `sus4`/ `sus` notation difference). The remaining flattened legacy sequences were effect lists, not missing progressions. Current owners: `STUDIO/dilla/data/dilla.json`, `music_theory.json`, `recovered_music.json` and the single-file Dilla engine. | **No progression bulk import indicated.** Preserve old labels as research provenance only, not proof that a famous composition was transcribed. Any later addition must be demonstrably distinct and use the current data contract; recovered studies stay out of default rotation unless explicitly selected. |
| Dilla generated media and dependencies | `multimedia/dilla` contains large WAV collections, bundled Windows SoX/FluidSynth binaries, soundfonts, archives and empty/near-empty media files. Much of the tree's 569 MB is this type of asset. | **Do not bulk copy.** Reuse source code/data only after file-level provenance, licence, correctness and platform review. Current Dilla already has a much smaller intentional reference/data contract and records recovery provenance. |
| Postpro | The old multimedia Postpro claims film stocks, profiles, presets and many effects. The current `STUDIO/postpro/ARCHAEOLOGY.md` and `LEGACY_RESTORE.md` already document the older repositories and restore the 24 missing v13 effect names through the current compatibility layer; the old video engine was not copied verbatim. | **No duplicate effect engine.** Compare only a named, tested recipe/profile or effect absent from the current contract. |
| Repligen / Replicate | pub3 has a CLI, wrappers, SQLite/model indexes, chains, old archived monoliths and a LoRA workflow. The current `STUDIO/replicate/ARCHAEOLOGY.md` already records the pub/pub2/pub3 lineage, useful workflow intent, and rejected stale assumptions. Current STUDIO/replicate has the client, schema snapshot, chain/replay manifest and guarded LoRA tooling. | **No bulk import.** Any truly missing workflow concept should be a narrow proposal against the current client/schema, not a duplicate CLI or scraped 48k-model catalogue. Never restore runtime dependency installation, guessed provider parameters, stale pricing or placeholder uploads. |
| TTS | Legacy Ruby scripts bind to Google TTS, hard-coded voices, OS-specific paths, installers, and checked-in audio cache. | **Do not restore as-is.** Compare user-facing behaviour only against current voice contracts/provider availability. Keep voices/credentials out of embedded script defaults and do not import caches. |
| Aight / assistants | `aight/` retains an older general orchestration framework, specialized assistant classes, old provider/memory/RAG paths and social automation modules. | **Do not restore a second assistant framework.** Current MASTER is authoritative after its full-read precondition; use the older tree only as a requirements archive for a gap that is proven absent. Do not revive covert/manipulative social automation or the old offensive operations modules. |
| OpenBSD | `openbsd/openbsd.sh` and its README assume older IPs, ports, packages, domain counts and product names. They describe DNS/NSD/DNSSEC, PF, relayd and a multi-app deployment layout, but those historical statements are not current host evidence. | **No direct restore or status claims.** Retain platform-independent lessons as references; use current `OPENBSD` runbooks and live host evidence for operational changes. |
| Shell utilities | `sh/` includes old backup/restore, cleanup, networking, permission and system utilities; the separate Nmap utility overlaps `pub2/misc/nmap`. Some scripts are privileged or destructive and predate current safety contracts. | **No wholesale import.** Individually review a user-needed utility for command injection, path safety, privilege scope, recovery and tests. No unverified remote workflow should become the test authority. |
| Rails installation scripts and visualizer templates | `rails/brgen*.sh`, vertical scripts, shared shell feature scripts, old `layouts/visualizer.js` and generated HTML describe prior app-installer and visualizer architectures. They include hard-coded paths and duplicated setup logic. | **Keep as archaeology.** Current RAILS/app inventory, engines, shared contracts, layout ownership and Rails-owned tunnel are canonical. No installer or second visualizer should be copied wholesale. |
| Bplans and static pages | HTML pages, generated duplicates, design tokens and images contain business-plan/content/design material, not a live Rails vertical contract. | **Reference only.** Salvage specific copy/design evidence only when a currently owned product has a demonstrable content gap. No unrelated product resurrection. |
| CI workflows | pub3 has GitHub workflow YAML for CI/static/docs. | **Do not port as the verification path.** The owner requires local/manual first-party testing rather than dependence on hosted third-party execution. Tests authored in this GitHub-only session remain unexecuted. |

## Concrete remaining restoration candidates

1. **None of the four excluded obsolete products is in scope.**
2. For Radio Bergen, remaining work is operational: confirm distribution rights for all 35 selected files, run the guarded Active Storage importer from a local pub2 checkout, and verify streaming/playback and the tunnel against the actual Rails runtime. No audio was uploaded by this audit.
3. For Dilla, only individually identified missing metadata/recipes should be considered. The chord-sequence comparison did not identify a missing legacy progression.
4. For host security/network checks, Nmap/VulCheck-like requirements can inform a future narrowly-scoped, read-only assessment tool only after current OPENBSD/MASTER overlap and policy are inspected.
5. For visual design, the old page can inform historical interaction research, but the chosen product is the current Rails tunnel, not the standalone page's multi-mode visualizer.

## Audit status

- **PASS:** recursive tree inventory; excluded-path filtering; focused reads of key README/source/docs and comparison to current Postpro, Replicate and Dilla owners.
- **PASS:** 35-file Radio Bergen archive manifest mapping (separate in `docs/pub2_archaeology_2026-10-28.md`); pub3 music-data comparison found matches for the 42 old chord sequences.
- **NOT_DONE:** full byte-by-byte reading of all 451 remaining blobs, media inspection, full Git-object archaeology, live browser/mobile tests, runtime Ruby/Rails tests and OpenBSD host verification.
- **NOT_RUN:** any test suite. This is GitHub-source inspection and test authoring only.
- **NOT_AUTHORIZED:** bulk copying historical binaries/media or changes to MASTER without first reading MASTER in full.

Sources:
- [pub3 tree at audited revision](https://github.com/anon987654321/pub3/tree/835f9199d605b6a6ae1f32cd207919c115a06b47)
- [legacy visualizer integration guide](https://github.com/anon987654321/pub3/blob/835f9199d605b6a6ae1f32cd207919c115a06b47/rails/VISUALIZER_INTEGRATION.md)
- [historical Dilla data](https://github.com/anon987654321/pub3/blob/835f9199d605b6a6ae1f32cd207919c115a06b47/multimedia/dilla/dilla_data.json)
- [current Postpro archaeology](https://github.com/anon987654321/pub4/blob/main/STUDIO/postpro/ARCHAEOLOGY.md)
- [current Replicate archaeology](https://github.com/anon987654321/pub4/blob/main/STUDIO/replicate/ARCHAEOLOGY.md)
- [current Dilla reference study](https://github.com/anon987654321/pub4/blob/main/STUDIO/dilla/REFERENCE_STUDY.md)
