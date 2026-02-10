# MASTER

Autonomous coding agent. Ruby, OpenBSD, OpenRouter.

MASTER reads code, reasons about it, fixes it, and verifies the result. It runs a seven-stage pipeline with an adversarial council, enforces language axioms, and manages its own LLM budget.

## Quick start

```sh
cp .env.example .env   # set OPENROUTER_API_KEY
./bin/master
```

Gems install on first use. No setup command.

## How it works

MASTER selects a reasoning pattern for each task:

| Pattern | When | What it does |
|---------|------|--------------|
| ReAct | Unknown territory | Think → act → observe, repeat |
| Pre-Act | Multi-step tasks | Plan all steps, then execute (70% better recall) |
| ReWOO | Pure reasoning | One LLM call, batch all evidence |
| Reflexion | Fix/debug/refactor | Execute → critique → retry |

Every query passes through seven pipeline stages:

1. **Intake** — parse input
2. **Guard** — block dangerous commands
3. **Route** — pick model by budget
4. **Debate** — adversarial council (optional)
5. **Ask** — call LLM
6. **Lint** — enforce axioms
7. **Render** — format output

## Models

Default: `anthropic/claude-opus-4.6` (premium tier). Falls back through cheaper tiers as budget depletes. All models configured in `data/models.yml`.

| Tier | Default model | Cost (in/out per 1M tokens) |
|------|--------------|----------------------------|
| Premium | Claude Opus 4.6 | $15 / $75 |
| Strong | DeepSeek-R1 | $0.55 / $2.19 |
| Fast | DeepSeek-V3 | $0.27 / $1.10 |
| Cheap | GLM-4.5 Air | free |

## Commands

```
model <name>      Switch to a specific model
models            List available models
pattern <name>    Switch reasoning pattern
patterns          List reasoning patterns
budget            Show remaining budget
selftest          Run MASTER through itself
axioms-stats      Show language axioms statistics
session           Session management
health            System health check
refactor <file>   Multi-model file review
chamber <topic>   Council deliberation
fix <file>        Auto-fix code violations
help              Show all commands
exit              Exit (or Ctrl+C twice)
```

## Axioms

Language axioms enforce timeless principles from authoritative sources:

| Category | Count | Examples |
|----------|-------|----------|
| Engineering | 11 | DRY, KISS, SRP, OCP |
| Structural | 8 | Merge, flatten, decouple |
| Process | 6 | Test-first, one-change |
| Communication | 4 | Concise, self-explaining |
| Meta | 4 | Show-cost-first, depth-on-demand |
| Resilience | 3 | Degrade-gracefully, expect-failure |
| Aesthetic | 5 | Least-power, just-enough |

Protection levels:
- **ABSOLUTE** — halt on violation
- **PROTECTED** — warn only

Use `axioms-stats` command to see full breakdown.

## Council

Twelve personas. Three hold veto:

- **Security Officer** — guards CIA triad
- **The Attacker** — finds exploits
- **The Maintainer** — 3 AM debuggability

Consensus requires 70% weighted agreement. Oscillation (25 rounds) halts.

## Budget

Session limit: $10.00. Tier selection by remaining budget:

| Budget remaining | Tier | Behavior |
|-----------------|------|----------|
| > $8.00 | Premium | Claude Opus 4.6 |
| > $5.00 | Strong | DeepSeek-R1, complex reasoning |
| > $1.00 | Fast | DeepSeek-V3, quick tasks |
| < $1.00 | Cheap | Free models only |

Circuit breaker trips after 3 failures. 5-minute cooldown.

## Structure

```
bin/master       Entry point
lib/             60+ modules
data/            Axioms, council, patterns (YAML)
var/db/          JSONL storage
test/            Minitest suite (24 files, 100+ tests)
```

## CLI

Run commands directly:

```bash
./bin/master refactor path/to/file.rb
./bin/master fix --all
./bin/master fix path/to/file.rb
./bin/master scan deploy/rails/
./bin/master chamber lib/master.rb
./bin/master ideate "authentication system"
./bin/master health
```

## Self-test

MASTER validates itself:

```
./bin/master selftest
```

Runs static analysis, axiom validation, pipeline safety, and council review. If MASTER fails, it has failed.

## License

MIT
