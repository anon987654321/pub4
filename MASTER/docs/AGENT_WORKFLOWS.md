# Advanced Agent Workflows

Phase 5 implementation: Multi-agent systems with Chamber mode, chains, and parallel execution.

## Overview

The agent system provides sophisticated multi-LLM workflows:

- **BaseAgent**: Foundation with retry logic, fallback models, cost tracking
- **ChamberAgent**: Multi-model deliberation with consensus voting
- **ChainAgent**: Sequential agent pipelines
- **ParallelAgent**: Concurrent execution with multiple strategies
- **CodeReviewAgent**: AI-powered code review
- **RefactorAgent**: Automated refactoring with validation

## Usage Examples

### Chamber Mode: Multi-Model Deliberation

```bash
cd MASTER
bin/cli
> chamber "Should we refactor this module to use microservices?"
```

Multiple AI models debate the question and reach consensus.

### Agent Chains: Sequential Processing

```bash
> chain review refactor validate
```

Creates a pipeline where output of one agent feeds into the next.

### Parallel Execution

```bash
> parallel fastest
```

Runs multiple agents concurrently and returns the fastest result.

### Code Review

```bash
> review lib/cli.rb kiss dry solid
```

Reviews code against specified principles.

### Automated Refactoring

```bash
> refactor lib/agents/base.rb kiss dry
```

Refactors code to comply with principles, validates improvements.

## Key Features

✅ Automatic retries with exponential backoff
✅ Fallback models if primary fails
✅ Automatic cost tracking per agent
✅ Execution metrics and logging
✅ Parallel execution for speed
✅ Chamber mode for critical decisions
✅ Agent chains for complex workflows

## Architecture

All agents inherit from `BaseAgent` which provides:

- `execute_with_retry`: Retry logic with fallbacks
- `call_llm`: LLM calls with cost tracking
- `log_execution`: Automatic execution logging
- `exponential_backoff`: Smart retry delays

## Metrics Tracking

Every agent execution tracks:

- Total cost ($)
- Total tokens used
- Execution time
- Number of retries
- Model switches (fallbacks)

## Next Steps

- Explore Phase 3: Cost tracking dashboard
- Explore Phase 4: Skill marketplace
- Create custom agents for your workflows
