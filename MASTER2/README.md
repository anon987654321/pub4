# MASTER v4.0.0

An autonomous agent system with 5 specialized engines for quality-driven software development.

## Architecture

MASTER v4 processes input through a pipeline of specialized stages:

1. **Input Tank** (Pressure Tank): Compresses and refines user input through 8-phase discovery including intent identification, entity extraction, and Strunk & White compression.

2. **Council Debate**: Adversarial council of 12 personas debates every decision. Three veto-capable personas (Security Officer, The Attacker, The Maintainer) can block proposals. Requires 70% weighted consensus to proceed.

3. **Refactor Engine**: Enforces timeless axioms from `axioms.yml`. ABSOLUTE axioms (like "The Tool Applies to Itself") trigger errors on violation. PROTECTED axioms trigger warnings.

4. **OpenBSD Admin**: Generates declarative OpenBSD configurations (pf, httpd, relayd) when admin tasks are detected.

5. **Output Tank** (Depressure Tank): Multi-model refinement with typographic rules (smart quotes, em dashes, ellipses), Zsh-pure validation for shell code, and cost/token summaries.

## The Five Engines

### 1. Pressure Tank (Input)
Compresses verbose user requests into precise, axiom-aligned prompts. Applies Strunk & White's "omit needless words" principle. Extracts entities, identifies intent, and loads relevant context.

### 2. Adversarial Council
12 distinct personas debate every proposal:
- 3 veto-capable: Security Officer, The Attacker, The Maintainer
- 9 advisory: Performance Analyst, System Architect, Minimalist, User Advocate, Skeptic, Chaos Engineer, Accessibility Advocate, Realist, Ethicist

### 3. Universal Refactor
Enforces engineering axioms (DRY, KISS, SOLID), communication axioms (omit needless words, active voice), and meta axioms (self-application, usability heuristics).

### 4. OpenBSD Admin
Generates secure, minimal OpenBSD configurations. Validates syntax. Uses pledge/unveil for security boundaries.

### 5. Depressure Tank (Output)
Refines and polishes output. Applies typography rules. Validates shell code for Zsh compatibility. Preserves code blocks byte-for-byte.

## Installation

```sh
cd MASTER2
bundle install
```

## Configuration

Copy `.env.example` to `.env` and add your API keys:

```sh
cp .env.example .env
# Edit .env with your keys
```

Required environment variables:
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `DEEPSEEK_API_KEY`
- `OPENROUTER_API_KEY`

## Usage

### Interactive REPL

```sh
./bin/master
```

Uses `tty-prompt` and `tty-spinner` for rich terminal UI. Gracefully falls back to basic I/O if TTY gems are unavailable.

### Pipe Mode (JSON)

```sh
echo '{"text":"What is the meaning of code?"}' | ./bin/master --pipe
```

Input: JSON object with `text` field.
Output: JSON object with full pipeline result or `error` field.

### Daemon Mode

Long-running agent that watches for task files:

```sh
./sbin/agentd
```

- Watches: `tmp/inbox/` (configurable via `MASTER_INBOX`)
- Outputs: `tmp/outbox/` (configurable via `MASTER_OUTBOX`)
- Poll interval: 5s (configurable via `MASTER_POLL_INTERVAL`)

Place `.json` files in inbox, retrieve results from outbox.

## Testing

```sh
bundle exec rake test
```

All tests use in-memory SQLite (`:memory:`) and mock LLM calls. The pipeline can run end-to-end without API keys for testing.

## Axioms

13 timeless axioms from authoritative sources:
- Engineering: DRY, KISS, SOLID (SRP, OCP), POLA, Scout Rule, YAGNI
- Communication: Omit Needless Words, Active Voice, Hierarchy, Rhythm
- Meta: Self-Application (ABSOLUTE), Usability Heuristics

See `data/axioms.yml` for full definitions.

## Council

12 personas with distinct directives and weights:
- Veto power: Security Officer (0.30), The Attacker (0.20), The Maintainer (0.20)
- High influence: Performance Analyst (0.20), System Architect (0.15), Minimalist (0.15)
- Specialists: User Advocate, Skeptic, Chaos Engineer, Accessibility Advocate, Realist, Ethicist (0.10-0.15 each)

Consensus threshold: 70%
Max iterations: 25
Oscillation detection: enabled

See `data/council.yml` for full directives.

## Circuit Breaker & Budget

- Circuit trips after 3 consecutive failures (300s cooldown)
- Budget limit: $10 per session
- 3-tier model selection: strong (deepseek-r1, claude-sonnet-4), fast (deepseek-v3, gpt-4.1-mini), cheap (gpt-4.1-nano)
- Automatically selects most powerful tier within remaining budget

## Result Monad

All stages return `Result.ok(value)` or `Result.err(error)`. Pipeline uses `flat_map` to chain stages, short-circuiting on first error.

```ruby
Result.ok(5)
  .flat_map { |x| Result.ok(x * 2) }
  .flat_map { |x| Result.ok(x + 3) }
# => Result.ok(13)
```

## Security

OpenBSD `pledge(2)` and `unveil(2)` support via Fiddle when running on OpenBSD. Automatically detected at runtime.

## License

See repository root for license information.
