# Restore plan from pub2 and pub3

Date: 2026-06-26

This note records what should be restored from the older public archives into
pub4, and what must stay archived.

## Source repositories

- `anon987654321/pub2`
- `anon987654321/pub3`

## pub2 verdict

`pub2` is an audio/product archive. It should not be copied wholesale into
Rails, because it contains generated MP3 assets and a single large standalone
HTML experiment. The valuable parts are:

1. A repeatable web-mastering chain for AKMD / Radio Bergen audio.
2. A track manifest format for local MP3 and external references.
3. A mobile-first Radio Bergen visual identity.
4. A canvas warp-tunnel visualizer.
5. A unified MP3 + external-player crossfade model.
6. Web Audio analyser patterns for audio-reactive UI.

### Restore from pub2

- `OPERATOR/audio/akmd_mastering_chain.rb`
- `OPERATOR/audio/radio_bergen_tracks.yml`
- `OPERATOR/audio/radio_bergen_visualizer_controller.js`
- `OPERATOR/audio/README.md`

### Do not restore from pub2

- MP3 binaries into git history.
- YouTube iframe autoplay as a production dependency.
- Monolithic single-file HTML as the application architecture.
- External media references without licensing review.

## pub3 verdict

`pub3` is a governance/infrastructure/local-AI archive. It should not replace
pub4 MASTER or OPERATOR. The valuable parts are:

1. Evidence scoring.
2. Convergence detection.
3. Defect catalogs.
4. Local CLI/AIGHT ideas.
5. OpenBSD/Cygwin/Termux platform lessons.
6. Port single-source-of-truth lessons.
7. Domain inventory fragments.
8. OpenBSD Amsterdam PTR notes.

### Restore from pub3

- `MASTER/tools/convergence/evidence_gate.rb`
- `MASTER/tools/convergence/README.md`
- `MASTER/data/lessons/pub_archive_restore.yml`
- `OPERATOR/openbsd/domain_candidates_from_pub3.yml`
- `OPERATOR/openbsd/ptr_openbsd_amsterdam.rb`
- `RAILS/archive_restore_gate.rb`

### Do not restore from pub3

- `master.json` permissions that enable auto-execute or approval bypass.
- Redis as a Rails dependency.
- Broad PF rules exposing app ports on `10000:65535`.
- Random port allocation.
- Bash/sed/grep validator scripts when a Ruby gate can do the same job.
- Dynamic relayd generation that forwards without explicit host matching.

## Restoration policy

Every restored artifact must satisfy these rules:

1. It must be small enough to review.
2. It must have one job.
3. It must run without network access unless explicitly invoked.
4. It must be safe by default.
5. It must fail visibly.
6. It must not reintroduce forbidden production assumptions.

## Mapping

| Archive | Valuable source idea | pub4 target |
|---|---|---|
| pub2 | AKMD lofi mastering chain | `OPERATOR/audio/akmd_mastering_chain.rb` |
| pub2 | Radio Bergen track manifest | `OPERATOR/audio/radio_bergen_tracks.yml` |
| pub2 | Warp tunnel canvas visualizer | `OPERATOR/audio/radio_bergen_visualizer_controller.js` |
| pub3 | Evidence score / convergence | `MASTER/tools/convergence/evidence_gate.rb` |
| pub3 | Port chaos report | `RAILS/archive_restore_gate.rb` |
| pub3 | Domain inventory fragments | `OPERATOR/openbsd/domain_candidates_from_pub3.yml` |
| pub3 | PTR constants | `OPERATOR/openbsd/ptr_openbsd_amsterdam.rb` |
| pub3 | Environment lessons | `MASTER/data/lessons/pub_archive_restore.yml` |

## Operator notes

Run:

```sh
ruby MASTER/tools/convergence/evidence_gate.rb
ruby RAILS/archive_restore_gate.rb
ruby RAILS/check_production_gate.rb
```

Audio batch example:

```sh
ruby OPERATOR/audio/akmd_mastering_chain.rb input.wav public/audio/output.mp3
```

PTR dry run:

```sh
ruby OPERATOR/openbsd/ptr_openbsd_amsterdam.rb --ipv4 185.52.176.18 --hostname ns.brgen.no
```

PTR apply:

```sh
APPLY_PTR=1 ruby OPERATOR/openbsd/ptr_openbsd_amsterdam.rb --ipv4 185.52.176.18 --hostname ns.brgen.no
```