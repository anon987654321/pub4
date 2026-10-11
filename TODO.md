# pub4 TODO

Status: BACKLOG_REOPENED  
Updated: 2026-10-11  
Authority: `MASTER/data/soul.yml` > `MASTER/data/laws.yml` > executable laws and gates > tree contracts > git history.

This is the cross-tree coordination queue. Each top-level tree owns its detailed backlog in its own `TODO.md`; avoid duplicating those items here. A task is closed only by landing a verified change or recording the real-world evidence it requires.

## Cross-tree priorities

- [ ] Re-fetch all non-`main` remote branch tips against the current `main` before branch disposition. The previous 2026-10-11 comparison found 35 non-main branches, mostly divergent and overlapping, with some tips thousands of commits behind. Recompute ahead/behind counts, inspect unique patches and tests, selectively port only missing improvements, record each branch's disposition, then archive/delete only when no unique work remains. Never merge a stale history wholesale.
- [ ] After branch disposition and tree-backlog work, run one fresh acceptance sweep from the current checkout: `MASTER/bin/operator measure`, `MASTER/bin/operator gate`, `cd MASTER && rake test`, `ruby RAILS/test/run_all.rb`, each Rails app's `bin/ci`, `ruby OPENBSD/bin/check --profile=full`, and `cd STUDIO/test && rake`. Fix reproducible failures; report skipped/inconclusive browser, hardware, provider, DNS, backup or VPS checks explicitly.

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
