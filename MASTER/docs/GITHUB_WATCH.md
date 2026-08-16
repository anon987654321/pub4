# GitHub Projects to Monitor

This file tracks public GitHub projects relevant to MASTER's architecture, constitutional AI, code governance, and Ruby agent development.

## Constitutional AI & LLM Frameworks

### Priority 1: Official Anthropic
- **anthropic-ai/constitution-ai** — Official Constitutional AI framework and research
  - Watch for: Principle updates, alignment techniques, prompt patterns
  - URL: https://github.com/anthropic-ai/constitution-ai

- **anthropic-ai/prompt-library** — Governance prompts and principle templates
  - Watch for: New rule patterns, safety frameworks
  - URL: https://github.com/anthropic-ai/prompt-library

### Priority 2: LLM Agent Frameworks
- **langchain-ai/langchain** (Python, but architecture is language-agnostic)
  - Watch for: Multi-agent patterns, tool orchestration, state management
  - Relevant to: MASTER's cli/review/io pipeline

- **huggingface/transformers** — Model loading and inference patterns
  - Watch for: Token budgeting, streaming, provider integration

## Code Governance & Linting

### Priority 3: Rule Composition & Linting
- **google/styleguide** — Language-agnostic style enforcement
  - Watch for: Style rule composition patterns, violation categorization

- **golangci/golangci-lint** — Linter composition framework
  - Watch for: How they organize scanner rules, priority hierarchy, exceptions
  - Relevant to: MASTER's review/scan architecture (rule composition similar)

- **github/super-linter** — Multi-language governance enforcement
  - Watch for: Cross-language consistency patterns, custom rule extensions

- **rubocop/rubocop** — Ruby linter (most similar to MASTER's Review::Scan)
  - Watch for: Ruby-specific governance patterns, exception handling

### Priority 4: Code Quality Metrics
- **google/yapf** — Code formatter with style rules
  - Watch for: AST-based transformation patterns

- **rust-lang/rustlings** — Learning + automated assessment
  - Watch for: Self-checking patterns, violation categories

## Workflow Orchestration

### Priority 5: Durable Workflows & Checkpointing
- **PrefectHQ/prefect** — Flow orchestration with state management
  - Watch for: Checkpoint/rollback strategies (relevant to Master::Core::Fold)
  - URL: https://github.com/PrefectHQ/prefect

- **dagster-io/dagster** — DAG scheduling with error recovery
  - Watch for: Turn-based state tracking, observer patterns

- **temporalio/temporal** — Durable workflow engine
  - Watch for: Exactly-once semantics, state machines

## Ruby & Rails Governance

### Priority 6: Ruby Language Governance
- **ruby-on-rails/rails** — Rails framework (large-scale Ruby governance)
  - Watch for: Architectural constraints, contribution guidelines

- **sorbet/sorbet** — Ruby type system and governance
  - Watch for: Violation categorization, type rule patterns

- **thoughtbot/factory_bot** — Test fixture pattern (governance through structure)
  - Watch for: Design patterns that enforce intent

### Priority 7: Ruby Agent Projects (THIN ECOSYSTEM)
**NOTE**: Ruby lacks a major agent framework. MASTER may be a reference implementation.
- Monitor Python equivalents (LangChain, AutoGPT) for patterns
- Track any new Ruby agent projects that emerge
- Consider pub4/MASTER as a potential "Ruby Agent Reference" publication

## Research Papers (arXiv/ar5iv)

### Constitutional AI & Alignment
- Constitutional AI (Bai et al.) — https://ar5iv.labs.arxiv.org/html/2212.06719
- Scaling Constitutional AI — https://ar5iv.labs.arxiv.org/html/2310.06692

### Code Quality & Metrics
- McCabe Cyclomatic Complexity (1976) — https://en.wikipedia.org/wiki/Cyclomatic_complexity
- Code Review Best Practices — https://ar5iv.labs.arxiv.org/html/2104.07896
- Cognitive Load in Programming — https://ar5iv.labs.arxiv.org/html/2107.03127

### LLM Code Generation
- Signal-to-Noise in Generated Code — https://ar5iv.labs.arxiv.org/html/2310.19102
- Token Efficiency in LLM Calls — https://ar5iv.labs.arxiv.org/html/2305.15092

## Contribution Guidelines

When tracking these projects:

1. **Weekly pulse check** — Star/fork counts, recent major releases
2. **Rule pattern extraction** — New governance patterns applicable to MASTER
3. **Documentation link** — Add relevant links to data/soul.yml or DECISIONS.md
4. **Integration assessment** — Decide if pattern should be imported or referenced

## Quick Search Tips

- GitHub: Use `org:anthropic-ai` or `topic:constitutional-ai` for discovery
- arXiv: Search "constitutional AI", "code governance", "LLM alignment"
- Trending: GitHub Trending by language (Ruby, Python, Go)

---

Last updated: 2026-07-14
