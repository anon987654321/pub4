# MASTER2 Architecture

## Boot Sequence

```
bin/master → SingleInstance lock
           → AutoInstall.setup (gem check)
           → require "master" (loads all modules)
           → DB.setup → Session.install_crash_handlers
           → Commands.init_instructions
           → Server thread (Falcon HTTP + WebSocket)
           → Pipeline.repl (interactive loop)
```

## Core Pipeline

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

## Module Map

| Layer         | Modules                                              |
|---------------|------------------------------------------------------|
| Entry         | `bin/master`, `Server`, `Pipeline.repl`              |
| Commands      | `Commands`, `CommandRegistry`, `WorkflowCommands`, `MiscCommands` |
| Pipeline      | `Pipeline`, `Stages::Guard`, `Stages::Strunk`        |
| Executor      | `Executor`, `ToolDispatch`, `React`, `PreAct`, `ReWOO`, `Reflexion` |
| Tools         | `file_read`, `file_write`, `file_edit`, `shell_command`, `analyze_code`, `fix_code`, `council_review`, `self_test` |
| LLM           | `LLM` (OpenRouter primary → Replicate fallback)      |
| Adversarial   | `AdversarialPass` (universal), `Refinement` (prose), `Chamber::Review` (council), `Introspection::Adversarial` (self) |
| Quality       | `CodeReview`, `QualityGates`, `Constitution`, `AxiomResolver` |
| Safety        | `AgentFirewall`, `Capabilities`, `Security::Permissions`, `Pledge` |
| Persistence   | `DB` (JSONL), `Session`, `ProjectMemory`, `SemanticCache` |
| Self-Improve  | `SelfRefactor`, `MultiRefactor`, `Introspection`, `BugHunting` |

## Key Data Files

- `data/constitution.yml` — axioms, principles, policies
- `data/axioms.yml` — 80 axiom definitions with IDs
- `data/questions.yml` — adversarial question banks (10 clusters)
- `data/models.yml` — LLM model tiers and routing
- `data/system_prompt.yml` — system prompt template

## Key Patterns

- **Result monad**: `Result.ok(value)` / `Result.err(message)` everywhere
- **Thread-local state**: `Thread.current[:master_*]` for Falcon fiber safety
- **ONE_SOURCE**: constants like `Paths::SKIP_DIRS` defined once, referenced everywhere
- **Adversarial layering**: heuristics (free) → LLM probes → MART iteration → challenge (multi-solution cherry-pick)
