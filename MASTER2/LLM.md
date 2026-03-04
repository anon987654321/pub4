# MASTER2 — Self-Governing AI Development Partner

MASTER2 is a Ruby gem that turns an LLM into a governed development partner.
It enforces constitutional review before output ships.

## Problem

LLMs often generate plausible code with silent failure paths, weak boundaries, and policy drift.
MASTER2 blocks this at generation time with explicit axioms, staged execution, and adversarial review.

## 30-second model

1. User submits a task.
2. `Pipeline` runs deterministic stages.
3. `Executor` chooses an execution pattern.
4. `LLM` calls a provider behind circuit breakers.
5. `Review::Constitution` checks axiom compliance.
6. `QualityGates` enforces thresholds.
7. Return value is always `Result.ok` or `Result.err`.

## Glossary

- **Axiom**: immutable engineering rule.
- **Council**: persona set that reviews output adversarially.
- **Result monad**: explicit `Ok/Err` return; no silent nil flow.
- **ReAct / PreAct / ReWOO / Reflexion**: execution patterns.
- **JSONL DB**: append-only storage for auditability.

## Pipeline

```
intake -> compress -> guard -> route -> council -> ask -> lint -> render
```

The first error halts the flow.

## Request flow

```
Pipeline.call(input)
  -> stage chain
  -> Executor.call(pattern: auto)
  -> LLM.ask(provider routing + fallback)
  -> Constitution review + quality gates
  -> Result.ok(value) | Result.err(reason)
```

## Core files

| File | Responsibility |
|------|----------------|
| `data/axioms.yml` | Constitutional rules |
| `data/constitution.yml` | Enforcement policy and hierarchy |
| `data/models.yml` | Provider and model routing |
| `data/quality_thresholds.yml` | Quality limits |
| `lib/master.rb` | Entry point |
| `lib/boot.rb` | Boot checks and environment wiring |
| `lib/pipeline.rb` | Stage orchestration |
| `lib/executor.rb` | Pattern selection and execution |
| `lib/llm.rb` | Provider calls, fallback, budget guards |
| `lib/circuit_breaker.rb` | Failure isolation and cooldown |
| `lib/result.rb` | `Ok/Err` monad |
| `lib/review/constitution.rb` | Axiom scanner/enforcer entry |
| `lib/quality_gates.rb` | Smell and complexity gates |
| `lib/commands.rb` | REPL dispatch |

## Data sources (single source of truth)

Policy belongs in `data/*.yml`, not hardcoded fallbacks in `lib/`.

| File | Governs |
|------|---------|
| `axioms.yml` | Axiom definitions |
| `constitution.yml` | Rule protection and escalation |
| `council.yml` | Persona roster and veto behavior |
| `language_rules.yml` | Language-specific checks |
| `platform.yml` | OpenBSD command constraints |
| `phases.yml` | Cognitive load allocation |
| `models.yml` | Model tier order and fallback chain |

## Three critical axioms

1. **FAIL_VISIBLY** — log and surface all failures.
2. **ONE_SOURCE** — keep each fact in one place.
3. **SELF_APPLY** — apply rules to MASTER2 itself.

## Golden rule

**PRESERVE_THEN_IMPROVE_NEVER_BREAK**

Preserve working behavior first.
Improve in small, auditable steps.

## Architecture map

```
bin/master -> lib/master.rb -> lib/boot.rb
                                 |
                                 v
                            lib/pipeline.rb
                                 |
                                 v
                            lib/executor.rb
                                 |
                                 v
                               lib/llm.rb
                                 |
                                 v
                        lib/review/constitution.rb
                                 |
                                 v
                          lib/quality_gates.rb
```

## Execution patterns

- **ReAct**: balance reasoning and action.
- **PreAct**: front-load planning for multistep work.
- **ReWOO**: use retrieval for knowledge-heavy tasks.
- **Reflexion**: iterate with explicit self-correction.
- **Momentum**: preserve useful context across iterations.

## Council review

- 12 personas review output against axioms.
- Veto holders can block unsafe consensus.
- Decisions map to named rules for auditability.

## Platform constraints

Target stack: OpenBSD 7.8+, Ruby 3.4, zsh.

Do not assume Linux-only tools or semantics.
No silent fallbacks that bypass platform policy.

## Writing standard (Strunk & White + Robert Hurst)

Apply strict prose discipline:

- Omit needless words.
- Prefer active voice.
- Use concrete nouns and verbs.
- Replace vague claims with evidence.
- Keep sentences short and structure explicit.

Apply Robert Hurst-style engineering rigor:

- Lead with purpose.
- State constraints before recommendations.
- Keep decisions testable and reversible.
- Separate facts, interpretation, and action.

## Common failure modes

- `rescue nil` or broad exception swallowing.
- Hidden fallback paths that bypass policy.
- Long files without clear module boundaries.
- Unbounded retries without breaker state.
- Output that cannot be traced to axioms.

## Validation

Run before merge:

```sh
rake test:fast
ruby -c lib/llm.rb
ruby -c lib/pipeline.rb
```

Guard API-dependent tests with `skip_unless_llm`.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `OPENROUTER_API_KEY` | LLM provider authentication |
| `REPLICATE_API_KEY` | Primary model and media integration |
| `MASTER_TOKEN` | Web server auth token |
| `MASTER_TRACE` | Verbosity control |
| `MASTER_PRESCAN` | Startup pre-scan toggle |
| `MASTER_HEARTBEAT` | Autonomous loop toggle |
| `REPLICATE_API_TOKEN` | Speech/media generation token |

## Quick usage

```sh
master scan .
master fix file.rb
master refactor file.rb
master chamber file.rb
master
```

## Communication style

dmesg-like: terse, factual, evidence first.

```text
llm0 at tier1: claude-opus-4 1234->567tok $0.0234 123ms
file0 at executor0: modified lib/logging.rb (fixed visibility)
boot: 45ms
```
