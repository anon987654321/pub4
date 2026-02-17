# MASTER2

Constitutional AI code quality. 12 adversarial personas, 68 axioms, 7-stage pipeline. Proactive autonomy. OpenBSD. Ruby.

## Pipeline

Intake → Guard → Route → Debate → Ask → Lint → Render. Result monad throughout. First error halts.

## Axioms

68 axioms, 11 categories. 6 enforcement layers (Literal → Language Axiom). 4 scopes (Line → Framework).

## Council

12 personas. 3 veto holders: Security Officer, Attacker, Maintainer. 70% weighted consensus.

## Executor

ReAct, PreAct, ReWOO, Reflexion. Auto-selected per task.

## Autonomy

Heartbeat — background timer, exponential backoff. `MASTER_HEARTBEAT=true`
Scheduler — persistent jobs, one-shot or recurring. `master schedule add|list|remove`
Triggers — event-driven auto-fix, error learning, budget switching.
Policy — `readonly` | `analyze` | `refactor` | `full`. Default: `refactor`.

## Guardrails

$10 session cap. Circuit breaker. Rate limiting. Staging + syntax validation + rollback. Agent firewall. Convergence detection. `pledge(2)`.

## Usage

```
master scan [dir]          master fix [--all|file]
master refactor <file>     master chamber <file>
master evolve              master ideate <topic>
master schedule <cmd>      master heartbeat <cmd>
master policy [set ...]    master health
master version             master help
```

No args → REPL + web server on :9000. `-v` verbose, `-q` quiet.

## Install

```sh
git clone https://github.com/anon987654321/pub4
cd pub4/MASTER2 && bundle install
OPENROUTER_API_KEY="sk-..." ./bin/master help
```

## Testing

```sh
rake test:fast            # Offline, no API key needed
rake test                 # Full suite (needs OPENROUTER_API_KEY for some)
ruby -Ilib -Itest test/test_result.rb   # Single file
```

## Debug

`MASTER_TRACE=3` for full debug logging. See LLM.md for gotchas.

Ruby 3.4+. OpenBSD 7.8+ recommended.

## License

MIT
