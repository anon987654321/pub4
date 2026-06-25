# MASTER and DEPLOY review

Reviewed against:

- `MASTER/data/soul.yml`
- `MASTER/data/rules.yml`
- `MASTER/data/limits.yml`
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

1. `bin/cli` cannot be executed end-to-end on this host until the MASTER bundle is installed.
2. The greeting path needs a repeatable CLI smoke that does not depend on manual interpretation.
3. `bin/gate` covers command classes, but not a dedicated social/chitchat smoke.
4. The social contract is present in tests, but the behavior is still mostly documented by examples instead of a single executable acceptance harness.
5. `rules.yml` has a rich prediction engine, but the autofix threshold and rule-by-rule enforcement deserve a tighter proof harness.
6. The structural ops surface still wants a single command-router path, not scattered wrappers.
7. The hallucination detector remains a known stub area.
8. The self-test wiring declared in `rules.yml` still needs a reader that executes laws against the runtime itself.
9. Several `MASTER/web` assets are still unreferenced and should either be wired or deleted.
10. `DEPLOY/openbsd` still benefits from a dry-run diff and a service-health report before restart.
11. The Rails production gate is good as a static guard, but target-host runtime verification is still the missing proof of readiness.
12. `baibl`, `blognet`, and `hjerterom` still need the full Ruby 3.4 bundle/test/security pass on the deploy target.

## DEPLOY signal

- The Rails matrix is explicit enough now to make production readiness measurable.
- `brgen` is the closest to production.
- `amber`, `bsdports`, `baibl`, `blognet`, and `hjerterom` remain gated on bundle installation, credentials rotation, and smoke validation.
- `relayd` owns TLS; Rails should stay proxy-aware and avoid HTTPS redirect ownership.

## Working rule

If a future change touches MASTER or DEPLOY, the first question is whether it improves proof, reduces drift, or removes an unforced failure mode. If not, it is probably noise.
