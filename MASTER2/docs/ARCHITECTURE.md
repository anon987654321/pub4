# MASTER2 Architecture

## Overview

MASTER2 is a Ruby-based AI agent framework that combines constitutional AI, safe autonomy, and multi-stage pipeline execution. It provides a sophisticated system for code analysis, refactoring, and automated development tasks with built-in safety guardrails.

## Core Principles

- **Constitutional AI**: All agent actions must pass constitutional checks
- **Progressive Disclosure**: Logging follows OpenBSD dmesg levels (MASTER_TRACE)
- **Safe Autonomy**: Multi-stage approval gates and sandbox execution
- **Metz Quality Gates**: Code quality enforcement at module level

## Module Categories

### Core (Foundation)
- **master.rb** — Main entry point, loads all subsystems
- **boot.rb** — Initialization and environment setup
- **utils.rb** — Shared utility functions
- **paths.rb** — Path resolution and workspace management
- **result.rb** — Monadic Result type for error handling

### Data Layer
- **db_jsonl.rb** — JSONL-based persistent storage
- **memory.rb** — Session memory management
- **session.rb** — Session lifecycle and state

### LLM Integration
- **llm.rb** — OpenRouter API client
- **circuit_breaker.rb** — Failure detection and circuit breaking
- **weaviate.rb** — Vector database integration (optional)
- **replicate.rb** — Replicate API integration (optional)

### Natural Language
- **parser/multi_language.rb** — Multi-language parsing (shell, Ruby, Python)
- **nlu.rb** — Natural language understanding and intent classification
- **conversation.rb** — Conversational context management

### Pipeline & Execution
- **pipeline.rb** — Main execution pipeline orchestration
- **stages.rb** — Pipeline stage definitions (Parse → Analyze → Plan → Execute → Verify)
- **executor.rb** — Hybrid agent with ReAct/PreAct/ReWOO/Reflexion patterns
- **commands.rb** — REPL command dispatcher

### Safe Autonomy
- **constitution.rb** — Constitutional rules engine
- **pledge.rb** — OpenBSD pledge-style capability restrictions
- **staging.rb** — Staging area for safe code modifications
- **confirmation_gate.rb** — User confirmation for high-risk operations
- **agent_firewall.rb** — Security firewall for agent actions

### Quality & Meta
- **framework/quality_gates.rb** — Metz-style quality gate enforcement
- **self_critique.rb** — Self-evaluation and reflection
- **self_repair.rb** — Automatic error recovery
- **self_test.rb** — Self-testing and validation
- **learning_quality.rb** — Quality scoring for learning patterns

### Learning & Adaptation
- **learnings.rb** — Core learning pattern storage and retrieval
- **learning_feedback.rb** — User feedback loop for learning patterns
- **momentum.rb** — Progress tracking and velocity measurement

### Deliberation
- **planner.rb** — Multi-step task planning
- **problem_solver.rb** — Problem decomposition and solving
- **reflection_memory.rb** — Long-term reflection storage
- **convergence.rb** — Multi-round convergence detection engine
- **converge.rb** — Single-pass convergence check utility

### Tools & Agents
- **agent.rb** — Base agent implementation
- **agent_pool.rb** — Agent pool management
- **swarm.rb** — Multi-agent coordination
- **workflow_engine.rb** — Workflow automation

### Hooks & Events
- **hooks.rb** — Hook definitions and registration (data layer)
- **hooks_manager.rb** — Hook lifecycle execution (runtime layer)

### UI & Output
- **ui.rb** — Terminal UI components
- **dashboard.rb** — Dashboard visualization
- **diff_view.rb** — Diff rendering
- **progress.rb** — Progress indicators
- **views/** — HTML visualization templates

### Logging (3-Layer System)
- **log.rb** — Unified logging facade (public API)
- **logging.rb** — Log formatting and rotation
- **dmesg.rb** — OpenBSD dmesg-style kernel/system log output

### Web & Server
- **web.rb** — Web interface
- **server.rb** — HTTP server

### Utilities
- **shell.rb** — Shell command execution
- **file_hygiene.rb** — File cleanup and organization
- **auto_install.rb** — Automatic gem installation
- **gh_helper.rb** — GitHub integration helpers

## Boot Sequence

1. **master.rb** loads and defines module structure
2. **auto_install.rb** checks and installs missing gems
3. Core modules loaded (utils, paths, result, logging)
4. Data layer initialized (db, memory, session)
5. LLM clients configured (llm.rb, optional integrations)
6. NLU and conversation modules loaded
7. Constitution and safety systems engaged
8. UI and command dispatcher initialized
9. Pipeline stages and executor prepared
10. Hooks and event system registered

## Data Flow

```
CLI Input → Commands.dispatch
         ↓
    NLU.classify_intent
         ↓
    Pipeline.run
         ↓
    Stages: Parse → Analyze → Plan → Execute → Verify
         ↓
    Constitution.check (before each stage)
         ↓
    Executor (ReAct/PreAct/ReWOO/Reflexion)
         ↓
    LLM.call (via OpenRouter)
         ↓
    Result (ok/err monad)
         ↓
    Memory.store + Learning.capture
         ↓
    Output (UI rendering)
```

## Configuration Files

All configuration files are stored in `data/`:

- **axioms.yml** — Core axioms and principles
- **budget.yml** — API budget limits and thresholds
- **constitution.yml** — Constitutional rules
- **council.yml** — Multi-agent council configuration
- **hooks.yml** — Event hook definitions
- **language_axioms.yml** — Language-specific patterns and rules
- **models.yml** — LLM model registry and capabilities
- **openbsd_patterns.yml** — OpenBSD-style patterns
- **opportunities.yml** — Improvement opportunities
- **phases.yml** — Project phase definitions
- **quality_gates.yml** — Quality gate configuration
- **quality_limits.yml** — Quality metric thresholds
- **questions.yml** — Clarifying questions templates
- **session_template.yml** — Session initialization template
- **smells.yml** — Code smell detection patterns
- **system_prompt.yml** — System prompt templates
- **zsh_patterns.yml** — Zsh-specific patterns

## External Dependencies

### Required
- **Ruby 3.3+**
- **OpenRouter API** — LLM access via OPENROUTER_API_KEY

### Optional
- **Weaviate** — Vector database for semantic search (WEAVIATE_URL, WEAVIATE_API_KEY)
- **Replicate** — Model hosting platform (REPLICATE_API_TOKEN)

## Environment Variables

See `.env.example` for all configuration options:

```env
# Required
OPENROUTER_API_KEY=your_key_here

# Optional
WEAVIATE_URL=http://localhost:8080
WEAVIATE_API_KEY=
REPLICATE_API_TOKEN=

# Logging (progressive disclosure)
MASTER_TRACE=0  # 0=silent, 1=llm only, 2=events, 3=full debug
```

## Running Tests

```bash
cd MASTER2
bundle install
bundle exec rake test
```

Tests are organized by module in `test/` directory. Each module has a corresponding test file (e.g., `test_pipeline.rb` for `pipeline.rb`).

## Key Design Patterns

### Result Monad
Error handling uses the Result monad pattern (ok/err) instead of exceptions for predictable error flows.

### Constitutional Checks
Every agent action passes through constitutional validation before execution.

### Progressive Disclosure
Logging verbosity controlled via MASTER_TRACE environment variable (0-3).

### Stage-Based Pipeline
All operations flow through a 5-stage pipeline: Parse → Analyze → Plan → Execute → Verify.

### Hybrid Reasoning
Executor auto-selects reasoning pattern (ReAct/PreAct/ReWOO/Reflexion) based on task characteristics.

## Extension Points

- **Hooks** — Register callbacks for lifecycle events
- **Commands** — Add custom REPL commands
- **Stages** — Define new pipeline stages
- **Quality Gates** — Add custom quality checks
- **Learnings** — Store patterns for future use

## Security Model

1. **Pledge** — Capability-based restrictions (OpenBSD pledge-style)
2. **Constitution** — Rule-based action validation
3. **Agent Firewall** — Network and file access controls
4. **Staging** — Safe preview before applying changes
5. **Confirmation Gate** — Human approval for high-risk operations

## Performance Considerations

- Circuit breaker prevents repeated LLM failures
- Convergence detection stops infinite loops
- Memory management with history limits
- JSONL append-only storage for speed
- Lazy loading of optional integrations

## Troubleshooting

- Set `MASTER_TRACE=3` for full debug logging
- Check `memory/*.jsonl` for session history
- Review `data/constitution.yml` for rule conflicts
- Verify API keys in `.env`
- Run `bundle exec rake test` to validate setup
