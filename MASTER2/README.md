# MASTER2

An AI that reviews its own code, argues with itself, and ships the result.

```sh
export OPENROUTER_API_KEY="sk-..."
./bin/master refactor lib/session.rb
```

MASTER2 reads your code, runs it through twelve adversarial personas, enforces thirty-two axioms from Clean Code and The Pragmatic Programmer, and writes the fix. If the fix breaks tests, it rolls back. If it catches itself in a loop, it stops.

Built in Ruby. Runs on OpenBSD first, everywhere else second.

## What happens when you type refactor

```
Your code → Intake → Guard → Route → Debate → Ask → Lint → Render → Fixed code
```

Seven stages. Each returns Result dot ok or Result dot err. First error stops everything. No exceptions.

Three personas can veto any change: Security Officer, The Attacker, The Maintainer. Consensus requires seventy percent weighted agreement from all twelve.

## The four thinking modes

MASTER2 picks the mode. You can override with: `pattern react`

**ReAct** for exploring. Think, act, observe, repeat. Tight loop for discovery.

**PreAct** for planning. Plan everything first, then execute. Good for multi-step workflows.

**ReWOO** for saving money. One LLM call, batch all reasoning. Uses placeholders.

**Reflexion** for fixing bugs. Try, critique yourself, retry with the lesson learned.

## Guardrails

Ten dollar session cap. Circuit breaker opens after three failures, cools down five minutes.

Staging area. Self modifications go to var slash staging, validated with ruby dash c, promoted or rolled back.

Pledge two. System call restrictions via OpenBSD kernel sandbox.

Convergence detector. Spots oscillation, A to B to A to B, and plateaus. Stops wasting compute.

## Direct CLI Commands

```sh
master refactor <file>      # LLM guided refactoring
master fix --all            # Multi-model deliberation
master ideate              # Creative brainstorming
master hunt <file>         # Eight phase bug analysis
master critique <file>     # Constitutional validation
master scan <dir>          # Detect code sprawl
master health              # System diagnostics
master selftest            # Run MASTER through itself
```

## Interactive REPL

```sh
./bin/master
```

The REPL gives you access to every command. Type `help` for the full list.

Popular commands: refactor, hunt, critique, learn, chamber, ideate, evolve, fix, browse, speak, model, pattern, opportunities, session, budget, health.

## The Seven Stage Pipeline

Every request flows through seven stages. First failure short-circuits.

**Stage One: Intake.** Parse and compress context. Strip noise.

**Stage Two: Guard.** Safety firewall. Block dangerous patterns before they reach the LLM.

**Stage Three: Route.** Classify the task. Pick the right model tier. Select execution pattern.

**Stage Four: Debate.** Optional. Council deliberation with twelve personas voting.

**Stage Five: Ask.** Query the LLM via OpenRouter. Handle retries and rate limits.

**Stage Six: Lint.** Enforce axioms. Validate output quality.

**Stage Seven: Render.** Typography refinement. Format the response.

## Model Tiers

Four tiers balanced by cost and quality.

**Premium** tier. Claude three point five Sonnet, GPT four oh. High quality reasoning.

**Strong** tier. Claude three Haiku, GPT four oh mini. Balanced quality and cost.

**Fast** tier. Qwen QwQ thirty-two B, DeepSeek R one. Quick iteration.

**Cheap** tier. Llama three point one eight B, DeepSeek Coder. Bulk operations.

## The Council

Twelve personas. Three hold veto power.

Security Officer guards the CIA triad. The Attacker finds exploits. The Maintainer ensures three AM debuggability.

Consensus requires seventy percent weighted agreement. Veto holders can block changes alone.

Full roster: Architect, Security Officer, The Attacker, Optimizer, The Minimalist, Accessibility Advocate, Documentation Specialist, Test Engineer, Ops Engineer, The Maintainer, Product Manager, End User.

## Axioms

Thirty-two timeless rules from authoritative sources. Enforced at six layers.

**Layer One: Literal.** Line level. Variable naming, formatting.

**Layer Two: Lexical.** Unit level. Method complexity, size.

**Layer Three: Conceptual.** File level. Single Responsibility, DRY, KISS.

**Layer Four: Semantic.** Framework level. API consistency.

**Layer Five: Cognitive.** System level. Mental model clarity.

**Layer Six: Language Axiom.** Universal truths. Strunk and White, SOLID principles.

Sources include: The Pragmatic Programmer for DRY and KISS, SOLID Principles for OCP and SRP, Clean Code for naming and functions, Strunk and White for omit needless words, Bringhurst for typography, Nielsen for usability heuristics.

ABSOLUTE axioms halt on violation. PROTECTED axioms warn.

## Installation

```sh
git clone https://github.com/anon987654321/pub4
cd pub4/MASTER2
bundle install
export OPENROUTER_API_KEY="your-key-here"
./bin/master
```

Requires Ruby three point three or newer. OpenBSD seven point six or newer recommended.

Dependencies auto-install on first run via auto_install dot rb module.

## Budget and Rate Limiting

Session cap is ten dollars. Prevents runaway costs.

Rate limit is thirty requests per minute. OpenRouter enforces this.

Circuit breaker trips after three failures. Five minute cooldown.

Auto-retry uses exponential backoff. One second, two seconds, four seconds.

Check remaining budget anytime with: `master budget`

## Safe Autonomy

Self modifications are dangerous. MASTER2 sandboxes them.

All self-edits write to var slash staging first.

Syntax validation with ruby dash c before promotion.

Rollback support if tests fail.

OpenBSD pledge restricts system calls. No network, no exec, no file writes outside staging.

## Self Test

A system that asserts quality must achieve its own standards.

```sh
./bin/master
master> selftest
```

Runs: Static analysis, Axiom validation, Pipeline safety checks, Council review with real LLM.

If MASTER fails its own review, it has failed.

Zero violations allowed. Zero issues allowed. The bar is absolute.

## Architecture

Core modules consolidated for DRY and single responsibility.

**workflow dot rb** combines planner, workflow engine, and convergence detection.

**session dot rb** handles session persistence with replay capability.

**review dot rb** consolidates code review, auto fixer, and enforcement.

**ui dot rb** includes help, error suggestions, NN slash g checklist, confirmations.

**bridges dot rb** combines post-processing and replicate integration.

**analysis dot rb** merges prescan and introspection with self-map.

**executor dot rb** flattened from seven pattern files into one module.

Result monad flows through everything. No exceptions. Explicit error handling.

## Dependencies

Core stack: ruby underscore llm for OpenRouter, Falcon for async web server, TTY toolkit for terminal UI, Stoplight for circuit breaker, Pastel for colors, Rouge for syntax highlighting, Nokogiri for HTML and XML.

OpenBSD first design: doas for privilege escalation, pledge for syscall restrictions, rcctl for service management.

Portable to macOS, Linux, and other Unix systems.

## Web Interface

Optional web UI on port nine thousand.

```sh
./bin/master --web
```

Opens at: http://localhost:9000

Same commands as CLI, rendered in browser.

## Speech Synthesis

Text to speech for accessibility and multitasking.

```sh
master> speak "Hello world"
```

Three engines: Piper for local, Edge TTS for cloud, Replicate for premium voices.

Auto-selects based on availability and budget.

## What Makes This Different

Most AI coding tools are black boxes. You prompt, you pray, you get output.

MASTER2 shows its work. Council debates. Axiom violations. Convergence metrics. Cost breakdowns.

Most tools trust the LLM blindly. MASTER2 validates everything. Syntax check. Test run. Axiom enforcement. Rollback on failure.

Most tools run once and forget. MASTER2 learns. Captures patterns. Improves over time.

Most tools ignore cost. MASTER2 budgets aggressively. Session cap. Circuit breaker. Tier selection.

Most tools ignore OpenBSD. MASTER2 embraces pledge, doas, and the security model.

## Contributing

Fork the repo. Make your changes. Run selftest. Open a PR.

All changes must pass: Static analysis, Axiom validation, Council review, Zero violations.

Follow the consolidation principles: One source of truth, Do one thing well, Simplest thing that works.

## License

MIT License. See LICENSE file for details.

## Version

Version two point zero point zero. Stable release. Frozen API.

This is v1.0.0 after architectural consolidation. All file sprawl eliminated. Regex removed. Tree command replaced. Documentation streamlined.
