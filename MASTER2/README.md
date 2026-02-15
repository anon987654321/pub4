# MASTER2

Constitutional AI code quality system. Twelve adversarial personas review your code against 68 axioms drawn from authoritative sources. The system enforces rules, proposes fixes, validates syntax, and rolls back on failure. Built for OpenBSD in Ruby.

## Architecture

Seven-stage pipeline. Your code enters through Intake, then Guard, Route, Debate, Ask, Lint, Render. Each stage returns `Result.ok` or `Result.err` using a Result monad. First error halts the pipeline. No exceptions thrown. Explicit error handling throughout.

The Result monad flows through `workflow.rb`, `session.rb`, `review.rb`, `ui.rb`, `bridges.rb`, `analysis.rb`, and `executor.rb`. Architectural consolidation eliminated file sprawl. Ruby tree walker replaced regex-based axiom detection.

## Axioms

68 axioms across 11 categories: engineering, structural, process, communication, resilience, aesthetic, meta, governance, functional, performance, verification. Each axiom is actionable and validatable.

Enforcement operates at six layers: Literal, Lexical, Conceptual, Semantic, Cognitive, Language Axiom. Four scopes: Line, Unit, File, Framework. Priority levels—10 (critical), 7 (important), 5 (normal), 3 (deep-only)—control scan depth.

Sources include *The Pragmatic Programmer*, SOLID Principles, *Clean Code*, Strunk & White, Bringhurst's *The Elements of Typographic Style*, and Nielsen's usability guidelines.

## Council

12 personas deliberate. Three hold veto power: Security Officer (weight 0.30), The Attacker (0.20), The Maintainer (0.20). Remaining nine contribute weighted votes. Consensus requires 70% weighted agreement.

Personas include Architect, Performance Analyst, Optimizer, The Minimalist, Accessibility Advocate, Documentation Specialist, Test Engineer, Ops Engineer, Product Manager, and End User. Each operates at a distinct temperature (0.2 to 0.7) reflecting their role.

## Executor Patterns

Four thinking modes. MASTER2 selects automatically based on task context.

**ReAct** (Reason + Act) — Iterative exploration. The executor reasons about the problem, takes an action, observes the result, then reasons again. Best for discovery and debugging.

**PreAct** (Plan + Act) — Upfront planning. Generates a complete plan before execution. If a step fails, replans. Best for tasks with clear structure and dependencies.

**ReWOO** (Reasoning WithOut Observation) — Single LLM call to plan all actions with placeholder references (#E1, #E2, ...). Minimizes LLM costs. Best for budget-constrained batch operations.

**Reflexion** — Self-correction through reflection. Attempts a task, evaluates the outcome, extracts lessons, and retries with augmented context. Maximum 3 attempts. Best for fixing bugs and improving on failure.

## Guardrails

Session cap: $10. Circuit breaker trips after 3 failures with 5-minute cooldown. Rate limit: 30 requests per minute. Auto-retry uses exponential backoff.

All self-modifications write to `var/staging` first. Syntax validation with `ruby -c` before promotion. Rollback support if tests fail. OpenBSD `pledge(2)` restricts system calls to `stdio rpath wpath cpath inet dns proc exec`.

Convergence detector stops oscillation. If the system loops between the same states, execution halts.

## Commands

```
refactor <file>           Refactor file with LLM guidance
multi-refactor [path]     Refactor entire directory with dependency graph
selfrun [--apply]         Full self-run across entire pub4 repository
fix [--all|<path>]        Fix violations in files or directory
scan [directory]          Scan for code smells (default: .)
chamber <file>            Chamber review with multi-model deliberation
ideate <topic>            Generate 15+ alternatives for a topic
evolve [args]             Evolve entire codebase
browse <url>              Browse and extract web content
speak <text>              Text-to-speech output
session <cmd>             Session management (replay|ls|diff|export)
cache [stats|clear]       Semantic cache management
health                    System health check
opportunities [path]      Find improvement opportunities
axioms-stats              Display axiom violation statistics
version                   Show version
help                      Show this help
```

No command starts REPL mode with integrated web server on port 9000.

## Installation

```sh
git clone https://github.com/anon987654321/pub4
cd pub4/MASTER2
bundle install
export OPENROUTER_API_KEY="sk-..."
./bin/master help
```

Requires Ruby 3.4+. OpenBSD 7.8+ recommended. Portable to macOS, Linux, other Unix systems.

## Dependencies

**LLM & Circuit Breaking**: `ruby_llm` (1.11+), `stoplight` (4.0+)

**Web Server**: `falcon` (0.47+), `async-websocket`

**Terminal UI**: `tty-reader`, `tty-spinner`, `tty-table`, `tty-box`, `tty-markdown`, `tty-prompt`, `tty-progressbar`, `tty-cursor`, `tty-tree`, `tty-pie`, `tty-pager`, `tty-link`, `tty-font`, `tty-editor`, `tty-command`, `tty-screen`, `tty-platform`, `tty-which`, `pastel`, `rouge`

**HTML/XML**: `nokogiri` (1.19+)

**Testing**: `minitest`, `rake`, `webmock`

## License

MIT
