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

## Boot sequence

```
bin/master → SingleInstance lock
           → AutoInstall.setup (gem check)
           → require "master" (loads all modules)
           → DB.setup → Session.install_crash_handlers
           → Commands.init_instructions
           → Server thread (Falcon HTTP + WebSocket)
           → Pipeline.repl (interactive loop)
```

## Core pipeline

```
User Input → Commands.dispatch_one
           → Pipeline.call
             → Stages::Guard (input sanitization)
             → Stages::Strunk (prose cleanup)
             → Executor.call (tool-using agent)
               → Strategy.select_pattern → React | PreAct | ReWOO | Reflexion | Direct
               → ToolDispatch (file_read, file_write, file_edit, shell_command, ...)
               → AdversarialPass.quick_check (pre-write gate)
               → verify_change (syntax + tests + axioms + adversarial)
               → test_and_fix_loop (TDI: test → fail → LLM fix → retest)
             → Refinement.review (adversarial pressure on LLM answers)
             → AdversarialPass (code block scanning in responses)
             → OutputGuard + Policy::Enforcer
           → UI.render
```

## Module map

| Layer         | Modules                                              |
|---------------|------------------------------------------------------|
| Entry         | `bin/master`, `Server`, `Pipeline.repl`              |
| Commands      | `Commands`, `CommandRegistry`, `WorkflowCommands`, `MiscCommands` |
| Pipeline      | `Pipeline`, `Stages::Guard`, `Stages::Strunk`        |
| Executor      | `Executor`, `ToolDispatch`, `React`, `PreAct`, `ReWOO`, `Reflexion` |
| Tools         | `file_read`, `file_write`, `file_edit`, `shell_command`, `analyze_code`, `fix_code`, `council_review`, `self_test` |
| LLM           | `LLM` (OpenRouter primary → free tier fallback)      |
| Adversarial   | `AdversarialPass` (universal), `Refinement` (prose), `Chamber::Review` (council), `Introspection::Adversarial` (self) |
| Quality       | `CodeReview`, `QualityGates`, `Constitution`, `AxiomResolver` |
| Safety        | `AgentFirewall`, `Capabilities`, `Security::Permissions`, `Pledge` |
| Persistence   | `DB` (JSONL), `Session`, `ProjectMemory`, `SemanticCache` |
| Self-Improve  | `SelfRefactor`, `MultiRefactor`, `Introspection`, `BugHunting` |

## Key patterns

- **Result monad**: `Result.ok(value)` / `Result.err(message)` everywhere
- **Thread-local state**: `Thread.current[:master_*]` for Falcon fiber safety
- **ONE_SOURCE**: constants like `Paths::SKIP_DIRS` defined once, referenced everywhere
- **Adversarial layering**: heuristics (free) → LLM probes → MART iteration → challenge (multi-solution cherry-pick)

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

## Policy

### Mode / Intent Rules

| Intent | Allowed output | Blocked output |
|--------|----------------|----------------|
| `:ops` | commands, diffs, tool results, status | narrative, fiction, chapter headings |
| `:refactor` | diffs, code, analysis | ungrounded execution claims |
| `:chat` | anything | — |
| `:doc` | documentation, examples | shell commands with side effects |
| `:creative` | anything | claims about system state |

**Enforcement**: `OutputGuard` + `Policy::Enforcer` run on every LLM response before it reaches the user.

### Hard Policy Rules (block output)

| Rule ID | Scope | Trigger | Action |
|---------|-------|---------|--------|
| `OPS_NO_NARRATIVE` | `:ops` | "Chapter N", "To be continued" | `Result.err` |
| `OPS_NO_UNGROUNDED_EXECUTION_CLAIMS` | `:ops` | "I ran/deployed/installed" without evidence hash | `Result.err` |

### Capability Policy

Default level: **1 (propose)** — read files, generate plans, never write.

```
--apply      → level 2 (write files)
--exec        → level 3 (run shell commands)
DEPLOY=1 + --apply --exec → level 4 (deploy)
```

### Injection Policy

- **Severe patterns**: block immediately (`Result.err`, category `:security`).
- **3+ hits** of any injection pattern: block immediately.
- **1–2 hits** of soft patterns: redact to `[REDACTED:injection_attempt]`, continue.

### Input Length Policy

Inputs exceeding `Pipeline::MAX_INPUT_LENGTH` (100,000 bytes, ~25k tokens) are rejected.

## Style guide

### Core philosophy

Boring behavior with sharp edges only when explicitly requested. (OpenBSD doctrine.)

### POLA (Principle of Least Astonishment)

- **Dry-run default**: anything that writes, edits, or deploys is dry-run unless `--apply`.
- **No implied execution**: in ops mode, never say "I deployed" unless a `ToolResult` with `evidence_hash` exists.
- **Stable flag semantics**: `--verbose` increases observable detail only; never changes behavior.

### Error taxonomy

```ruby
Result.err("message", category: :security)   # injection, capability violation
Result.err("message", category: :policy)     # axiom/mode violation
Result.err("message", category: :input)      # malformed or oversized input
Result.err("message", category: :tool)       # tool dispatch failure
Result.err("message", category: :llm)        # model call failure
```

### Code style

- `# frozen_string_literal: true` on every file.
- Require order: stdlib → gems → relative (each group sorted).
- Keyword args for all public methods.
- No positional args beyond 2 params.
- `Result.ok` / `Result.err` for all expected failures; raise only for programmer bugs.
- No one-line (minified) Ruby. Every method on its own line.

### Directory conventions

```
lib/          core modules
lib/policy/   governance: Rule, Enforcer
lib/executor/ execution engine + tools
lib/security/ injection guard, permissions, sanitizer
lib/ui/       terminal output only
data/         YAML sources of truth (axioms, council, models, routes)
var/          runtime state (sessions, cache, db) — not committed
test/         unit + golden tests
deploy/       OpenBSD deployment scripts
```

### Logging

Use `Logging.dmesg_log(tag, message:)` for structured audit events.
Do not use `puts` for operational output. Use `UI.dim`, `UI.info`, `UI.warn`.

### Naming

If a name sounds clever, rename it. If it sounds literal and slightly boring, keep it.

## Writing standard (Strunk & White + Robert Hurst)

- Omit needless words.
- Prefer active voice.
- Use concrete nouns and verbs.
- Replace vague claims with evidence.
- Keep sentences short and structure explicit.
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
| `REPLICATE_API_TOKEN` | Speech/media generation token |
| `REPLICATE_API_KEY` | Alias for Replicate token |
| `WEAVIATE_API_KEY` | Vector store authentication |
| `MASTER_TOKEN` | Web server auth token |
| `MASTER_TRACE` | Verbosity control (0=silent,1=default,2=all,3=debug) |
| `MASTER_PRESCAN` | Startup pre-scan toggle |
| `MASTER_HEARTBEAT` | Autonomous loop toggle |

## Quick usage

```sh
master scan lib/
master fix file.rb
master refactor file.rb
master chamber file.rb
master
```

## Communication style

dmesg-like: terse, factual, evidence first.

```text
llm0 at tier1: claude-sonnet-4.6 1234->567tok $0.0234 123ms
file0 at executor0: modified lib/logging.rb (fixed visibility)
boot: 45ms
```
