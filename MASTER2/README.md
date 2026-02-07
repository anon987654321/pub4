# MASTER

LLM pipeline with adversarial council and axiom enforcement. Ruby. OpenBSD-native.

## Install

```sh
bundle install
cp .env.example .env
# Set OPENROUTER_API_KEY
./bin/master
```

## Architecture

MASTER is a hybrid agent system with multiple execution patterns:

### Execution Patterns (auto-selected)

| Pattern | Use Case | Behavior |
|---------|----------|----------|
| **ReAct** | Exploration, unknown tasks | Tight thought→action→observation loop |
| **Pre-Act** | Multi-step workflows | Plan all steps first, then execute (70% better recall) |
| **ReWOO** | Cost-sensitive reasoning | Single LLM call with #E{n} placeholders |
| **Reflexion** | Fix/debug/refactor | Execute → self-critique → retry if needed |

### Pipeline Stages

Seven stages, chained via Result monad:

1. **Intake** — Parse input
2. **Guard** — Block dangerous patterns
3. **Route** — Select model by budget/tier
4. **Debate** — Council deliberation (optional)
5. **Ask** — Query LLM
6. **Lint** — Axiom enforcement
7. **Render** — Typography refinement

First error short-circuits. No exceptions.

## Features

- **Auto-retry** with exponential backoff (3 attempts)
- **Rate limiting** (30 requests/minute, $0.50 per-query cap)
- **Circuit breaker** (3 failures → 5-minute cooldown)
- **Session persistence** with crash recovery (SIGINT/SIGTERM auto-save)
- **Pattern fallback** (if primary fails → react → direct)

## Axioms

Timeless rules from authoritative sources:

| Axiom | Source |
|-------|--------|
| DRY, KISS, POLA | Pragmatic Programmer |
| SRP, OCP | SOLID / Clean Code |
| Omit needless words | Strunk & White |
| Typography hierarchy | Bringhurst |
| Usability heuristics | Nielsen |

**ABSOLUTE** axioms halt on violation. **PROTECTED** axioms warn.

## Council

Twelve personas. Three hold veto:

- **Security Officer** — Guards CIA triad
- **The Attacker** — Finds exploits
- **The Maintainer** — 3 AM debuggability

Consensus requires 70% weighted agreement. Oscillation (25 rounds) halts system.

## Self-Application

> A system that asserts quality must achieve its own standards.

Run `selftest` to pass MASTER through itself:
- Static analysis
- Axiom validation
- Pipeline safety
- Council review (LLM)

If MASTER fails its own review, it has failed.

## Commands

```
help          Show commands
refactor      Multi-model file review
chamber       Council deliberation
ideate        Creative brainstorming (Chamber)
evolve        Self-improvement cycle
fix           Auto-fix code violations
browse        Web browsing (Ferrum)
speak         Text-to-speech (Piper/Edge/Replicate)
model         Switch LLM model
models        List available models
pattern       Switch execution pattern (react/pre_act/rewoo/reflexion)
patterns      List execution patterns
opportunities Analyze codebase for improvements
selftest      Run MASTER through itself
session       Session management
budget        Show remaining budget
health        System health check
```

## Modes

- **REPL**: `./bin/master`
- **Pipe**: `echo '{"text":"..."}' | ./bin/master --pipe`
- **Daemon**: `./sbin/agentd`

## Budget

$10.00 session limit. Three tiers:

| Tier | Models |
|------|--------|
| strong | deepseek-r1, claude-sonnet-4 |
| fast | deepseek-v3, gpt-4.1-mini |
| cheap | gpt-4.1-nano |

Circuit breaker trips after 3 failures. 5-minute cooldown.

## Structure

```
bin/master       Entry point
lib/             60+ modules
data/            Axioms, council, patterns (YAML)
var/db/          JSONL storage
test/            Minitest suite (24 files, 100+ tests)
```

## License

MIT
