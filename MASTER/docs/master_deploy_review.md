# MASTER and DEPLOY review

Reviewed against:

- `MASTER/data/soul.yml`
- `MASTER/data/rules.yml`
- `MASTER/data/workflow.yml`
- `MASTER/CONVENTIONS.md`
- `MASTER/data/claude/project_master.md`
- `MASTER/bin/cli`
- `MASTER/bin/gate`
- `MASTER/spec/social/assistant_contract_spec.rb`
- `MASTER/lib/now/stages/enhance.rb`
- `DEPLOY/rails/apps.yml`
- `DEPLOY/rails/PRODUCTION_READINESS.md`

## Rules internalized

- Preserve then improve, never break.
- Read full files before editing them.
- Use explicit evidence, not intent language.
- Keep scans deep.
- Avoid bare rescue and broad swallowing.
- Keep rules in data, not Ruby strings.
- Lead with the fact, then evidence, then implementation.
- Keep command paths separate from prose; no shell noise.
- Treat `relayd` as the TLS terminator on the deploy side.
- Keep Rails proxy-aware with `assume_ssl`, not TLS-owning with `force_ssl`.

## CLI and chitchat proof

- `MASTER/bin/cli` boots MASTER directly, sets safe defaults unless explicitly overridden, and supports both TTY and pipe mode.
- In TTY mode it can also launch the local web UI when enabled.
- `MASTER/bin/gate` exercises the safe command surface through `bin/cli` and then checks the diff stays clean.
- `MASTER/spec/social/assistant_contract_spec.rb` covers casual greeting, confusion repair, frustration, background boundary, and continue behavior.
- `MASTER/lib/now/stages/enhance.rb` skips slash commands, code fences, greetings, and one-word affirmations, which keeps chitchat from being overprocessed.

## Current gaps and opportunities

1. `bin/cli` cannot be executed end-to-end on this host until the MASTER bundle is installed under Ruby 3.4.
2. The greeting path needs a repeatable CLI smoke that does not depend on manual interpretation.
3. `bin/gate` covers command classes, but not a dedicated social/chitchat smoke.
4. The social contract is present in tests, but the behavior is still mostly documented by examples instead of a single executable acceptance harness.
5. The structural ops surface still wants a single command-router path, not scattered wrappers.
6. The hallucination detector remains a known stub area.
7. Several `MASTER/web` assets are still unreferenced and should either be wired or deleted.
8. `DEPLOY/openbsd` still benefits from a dry-run diff and a service-health report before restart.
9. Target-host Ruby 3.4 bundle/test/security/deploy smoke is still the missing proof of readiness for all six Rails apps.

## Landed (2026-06-15)

- Anti-simulation and require_evidence wired into `voice/personality.rb` system prompts.
- `/scan` and `/fix` accept `--dry-run`; scan reports lead with violation totals (inverted pyramid).
- Self-scan idempotency tests added in `test/test_self_scan.rb`.
- `check_production_gate.rb` passes for all six Rails apps.
- Custom `HealthController` on `GET /up` checks Solid Cache and Solid Queue.
- `solid_cable` production adapter on `baibl`, `bsdports`, and `hjerterom`.
- Marketplace FTS5 live search wired via `Shared::LiveSearch`.

## DEPLOY signal

- The Rails matrix is explicit enough now to make production readiness measurable.
- `brgen` is the closest to production.
- `amber`, `bsdports`, `baibl`, `blognet`, and `hjerterom` remain gated on bundle installation, credentials rotation, and smoke validation.
- `relayd` owns TLS; Rails should stay proxy-aware and avoid HTTPS redirect ownership.

## Working rule

If a future change touches MASTER or DEPLOY, the first question is whether it improves proof, reduces drift, or removes an unforced failure mode. If not, it is probably noise.
