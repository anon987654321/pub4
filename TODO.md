# pub4 TODO

Status: BACKLOG_REOPENED  
Updated: 2026-10-12  
Authority: `MASTER/data/soul.yml` > `MASTER/data/laws.yml` > executable laws and gates > tree contracts > git history.

This is the cross-tree coordination queue. Each top-level tree owns its detailed backlog in its own `TODO.md`; avoid duplicating those items here. A task is closed only by landing a verified change or recording the real-world evidence it requires.

## Cross-tree priorities

- [ ] **Delete 5 remote branches whose patches are already on `main`** (`git cherry origin/main <branch>` prints no `+` line): `codex/grounded-engineering-loop`, `feat/snapshot-map-language-extractors-20261012`, `fix/deepseek-proof-guards-followup`, `fix/termux-existing-checkout-expansion-20261011`, `fix/termux-existing-checkout-guard-20261011`. The agent session that audited them was refused `git push origin --delete`; the operator runs `git push origin --delete <each>`. Proof: `git branch -r` no longer lists them. Left alone on purpose: `grok-hear-drums-dillatime` (also patch-equivalent, but a LoRA/audio session writes to it) and `master/fix-pid*` (a live /fix worktree).
- [ ] **Decide the remaining non-`main` remote branches; none is safe to merge and none was verified patch-by-patch.** Each is 13 to 3,028 commits behind `main` and carries unique commits (`git cherry` `+` lines), so all are kept for now. Families and their disposition: dry-run and convergence (`fix-dryrun-*`, `fix-dry-run-structural-safety-*`, `fix-convergence-loop-*`, `bughunt/*`, `fix/constitutional-hardening-*`) refer to retired `web/public` paths and lack the current Git-inventory failure coverage; law convergence (`master/final-*`, `master/finalize-*`, `master/convergence-*`, `restore/intelligence-*`, `sweep/todo-wishlist-*`) overlap each other and `main`'s newer `CoreBridge`, `Mission` and `Skills`; cognition and memory (`feat/cognition-*`, `implement/cognitive-*`, `recover/cognition-*`) are superseded by `main`'s `OutcomeModel`, and the memory-review branches (`feat/operator-memory-review-*`, `recover/memory-governance-*`) are refused in `MASTER/AGENTS.md`; `fix/brgen-termux-readiness` omits `main`'s malformed-PATH migration; `debugging/object-centric-probe` differs from the current `ObjectProbe`; `fix/ephemeral-fix-worktrees` is superseded by the worktree session; the single-commit branches (`fix-dilla-showcase-path`, `fix-live-play-bach`, `fix-vps-deploy-contract-regex`, `archaeology/micro-restoration-*`, `restore/pre-parallel-tree`, `session/rails-final-*`, `fix/snapshot-pack-integrity-*`, `master/openclaw-synthesis-*`) are 35 to 2,685 commits behind. Operator decision: delete every family above after one last look at its `+` commits, or name the commit worth porting. Proof: `git branch -r` lists only `main` plus live work.
- [ ] **The design blocks lost with `rules.yml` are only half restored.** `342239dd7` (2026-09-30) cut `rules.yml` by 4,427 lines; the ULTRAMINIMALISM block is back in `MASTER/data/tokens.yml` (minus its serif entries), but TYPOGRAPHY, LAYOUT_RULES, KINETIC_DEPTH, VISUAL_DESIGN, MOTION_AND_SOUND, DATA_VISUALIZATION, AUTOMATED_CSS_ANALYSIS, UX_LAWS, WORN_TYPE, PIXEL_PERFECTION, RAMS_CHECKLIST, UI_POLISH and PWA are still gone, which is why `ruby MASTER/gates/runner.rb design_metrics` fails with `touch.target_min_px missing`. They live in `git show 342239dd7^:MASTER/data/rules.yml` (rules with `tier: design`, the section under `config`). Restoring them re-arms `design_metrics`, `surface_laws` and the typography checks against RAILS CSS, and TYPOGRAPHY predates the Swiss-sans and monospace-chat directive, so the operator reviews its values first. Proof: `ruby MASTER/gates/runner.rb design_metrics` passes or lists real RAILS findings.
- [ ] Reported to the operator, not restored: the ULTRAMINIMALISM block named three serif typefaces (`house_promo_serif` = Instrument Serif, `ibm_plex_serif`, `source_serif_4`) and two pairings (`ibm_plex_editorial`, `source_editorial`). They were left out under the no-serif directive. Say so if any should return as a documented exception.
- [ ] **Acceptance sweep, partly run on 2026-10-12.** Run: `MASTER/tools/boot_smoke.rb` ok; `OPENBSD/bin/rehearse` ok (16 checks); `rake test:core` ok (21 files); `bin/operator measure` finished with 16 ratchet rows OVER (`spine.lib_body_ceiling`, `self_findings.law` and `.registry`, `sprawl.lone_dirs`, `growth.master`/`rails`/`openbsd`, `entrypoints.*`, `command_surface`, `css_coverage.*`, `visual_contract.*`, `breakpoint.unknown_edge`), none caused by that day's edits and none to be raised; the whole MASTER suite has about 185 red files (see `MASTER/TODO.md`). Not run on this loaded 8 GB Mac while another session's /fix was live: `bin/operator gate`, `ruby RAILS/test/run_all.rb`, each Rails app's `bin/ci`, `ruby OPENBSD/bin/check --profile=full`, `cd STUDIO/test && rake`. Run them on an idle machine and report skipped browser, hardware, provider, DNS, backup and VPS checks explicitly.

## Tree queues

- [MASTER/TODO.md](MASTER/TODO.md) — law enforcement, /fix proof, debugging, intelligence and Termux.
- [RAILS/TODO.md](RAILS/TODO.md) — Rails contract suite, multi-city isolation, payment proof, rendered UX and PWA.
- [OPENBSD/TODO.md](OPENBSD/TODO.md) — domain/DNS facts, deploy-lock correctness, vm23 health and restore drills.
- [STUDIO/TODO.md](STUDIO/TODO.md) — Dilla rendering/listening, failing media tests, postpro performance and private-media hygiene.
- [STUDIO/replicate/lora/TODO.md](STUDIO/replicate/lora/TODO.md) — likeness data, reference-image route, video, postpro and paid-provider safeguards.

## Evidence discipline

Repository text cannot prove a live deployment, registrar renewal, DNS delegation, valid TLS, a successful restore, real Android microphone/TTS behavior, provider-side payment configuration, rendered browser layout or that a musical take sounds good. The tree queues track these as acceptance work; none may be marked complete without observed evidence. Preserve explicit PASS, FAIL, INCONCLUSIVE, BLOCKED and delivery-failure outcomes.

## Reopen and close

Reopen a queue when current source, test output or a live measurement identifies a reproducible seam. Write requirements and acceptance conditions, not speculative implementation diaries. Once the fix and its proof are landed, remove the item rather than keeping a second changelog.

## Canonical proof surfaces

- MASTER: `MASTER/bin/operator measure`, `MASTER/bin/operator gate`, `cd MASTER && rake test`, relevant focused tests and the real /fix terminal report.
- RAILS: `MASTER/gates/runner.rb`, `ruby RAILS/test/run_all.rb`, each app's `bin/ci`, and browser/device tests for rendered behavior.
- OPENBSD: `OPENBSD/bin/rehearse`, `OPENBSD/bin/check`, `OPENBSD/test/run_all.rb`, `OPENBSD/bin/vps-deploy` and watched vm23 state.
- STUDIO: `cd STUDIO/test && rake`, isolated subject suites, source/provenance checks, actual renders and operator listening evidence.
