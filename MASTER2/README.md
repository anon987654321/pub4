# MASTER

LLM pipeline with adversarial council and axiom enforcement. Ruby. OpenBSD-native.

## Install

```sh
bundle install
cp .env.example .env
# Set OPENROUTER_API_KEY
./bin/master
```

## Pipeline

Seven stages, chained via Result monad:

1. **Intake** — Parse input
2. **Guard** — Block dangerous patterns
3. **Route** — Select model by budget/tier
4. **Debate** — Council deliberation (optional)
5. **Ask** — Query LLM
6. **Lint** — Axiom enforcement
7. **Render** — Typography refinement

First error short-circuits. No exceptions.

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
evolve        Self-improvement cycle
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
lib/             46 modules
data/            Axioms, council, patterns (YAML)
var/db/          JSONL storage
test/            Minitest suite
```

## License

MIT
