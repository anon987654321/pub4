# pub4 TODO

Status: BACKLOG_REOPENED  
Updated: 2026-10-12  
Authority: `MASTER/data/soul.yml` > `MASTER/data/laws.yml` > executable laws and gates > tree contracts > git history.

This is the cross-tree coordination queue. Each top-level tree owns its detailed backlog in its own `TODO.md`; avoid duplicating those items here. A task is closed only by landing a verified change or recording the real-world evidence it requires.

## Cross-tree priorities

- [ ] **Delete the remaining known-redundant remote branch** `codex/grounded-engineering-loop`; the previous audit found no `+` commits relative to `main`. The other four names from that cleanup and `grok-hear-drums-dillatime` are absent from the live remote-branch inventory observed at `1c1093368c250ffc2715ef2eadf6eb2d6abb18f3`. Delete the remaining branch from an authorized git checkout and prove `git branch -r` no longer lists it. Preserve `master/fix-pid*`, which are live /fix worktrees.
- [ ] **Disposition the six `work/universal-four-stream-*` branches.** Live refs observed at `1c1093368c250ffc2715ef2eadf6eb2d6abb18f3` also include `master/fix-pid65885-3f67bdc9cb` and `master/fix-pid90716-acefdac2fe`; preserve those because they are live /fix worktrees. Review each universal branch against current `main`, inspect unique commits and decide which deserve a port before deleting. Do not merge or delete by family name alone. Proof: every retained ref has an active owner or a named commit disposition.
- [ ] Reported to the operator, not restored: the ULTRAMINIMALISM block named three serif typefaces (`house_promo_serif` = Instrument Serif, `ibm_plex_serif`, `source_serif_4`) and two pairings (`ibm_plex_editorial`, `source_editorial`). They were left out under the no-serif directive. Say so if any should return as a documented exception.
- [ ] **Run the full acceptance sweep on current main.** The previous measurements (boot smoke, 16 OpenBSD rehearsal checks, 21 core test files, 16 over-limit ratchets and about 185 failing MASTER test files) were recorded at `f9a5a3083` on 2026-10-12 and are not evidence for current `main` (`1c1093368c250ffc2715ef2eadf6eb2d6abb18f3`). That head had no attached status/check runs when checked. On an idle authorized checkout, run `MASTER/tools/boot_smoke.rb`, `bin/operator measure`, `bin/operator gate`, `cd MASTER && rake test`, `ruby RAILS/test/run_all.rb`, each app's `bin/ci`, `ruby OPENBSD/bin/check --profile=full`, and `cd STUDIO/test && rake`; record real exits, counts and skipped browser/hardware/provider/DNS/backup/VPS checks. Never raise a ratchet merely to fit existing code.

## Tree queues

- [MASTER/TODO.md](MASTER/TODO.md) — law enforcement, /fix proof, debugging, intelligence and Termux.
- [RAILS/TODO.md](RAILS/TODO.md) — Rails contract suite, multi-city isolation, payment proof, rendered UX and PWA.
- [OPENBSD/TODO.md](OPENBSD/TODO.md) — domain/DNS facts, deploy-lock correctness, vm23 health and restore drills.
- [STUDIO/TODO.md](STUDIO/TODO.md) — Dilla rendering/listening, failing media tests, postpro performance and private-media hygiene.

## Evidence discipline

Repository text cannot prove a live deployment, registrar renewal, DNS delegation, valid TLS, a successful restore, real Android microphone/TTS behavior, provider-side payment configuration, rendered browser layout or that a musical take sounds good. The tree queues track these as acceptance work; none may be marked complete without observed evidence. Preserve explicit PASS, FAIL, INCONCLUSIVE, BLOCKED and delivery-failure outcomes.

## Reopen and close

Reopen a queue when current source, test output or a live measurement identifies a reproducible seam. Write requirements and acceptance conditions, not speculative implementation diaries. Once the fix and its proof are landed, remove the item rather than keeping a second changelog.

## Canonical proof surfaces

- MASTER: `MASTER/bin/operator measure`, `MASTER/bin/operator gate`, `cd MASTER && rake test`, relevant focused tests and the real /fix terminal report.
- RAILS: `MASTER/gates/runner.rb`, `ruby RAILS/test/run_all.rb`, each app's `bin/ci`, and browser/device tests for rendered behavior.
- OPENBSD: `OPENBSD/bin/rehearse`, `OPENBSD/bin/check`, `OPENBSD/test/run_all.rb`, `OPENBSD/bin/vps-deploy` and watched vm23 state.
- STUDIO: `cd STUDIO/test && rake`, isolated subject suites, source/provenance checks, actual renders and operator listening evidence.
