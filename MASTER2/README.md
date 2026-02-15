MASTER2

Constitutional AI code quality system. Reads your code. Runs it through twelve adversarial personas. Enforces thirty-two axioms. Writes the fix. Rolls back on failure. Stops on loops.

Built in Ruby. OpenBSD first.

Setup: export OPENROUTER_API_KEY="sk-..." then ./bin/master refactor lib/session.rb

Seven stages. Your code goes through Intake, Guard, Route, Debate, Ask, Lint, Render. Each returns Result.ok or Result.err. First error stops everything. No exceptions.

Three personas can veto: Security Officer, The Attacker, The Maintainer. Consensus requires seventy percent weighted agreement from all twelve.

Four thinking modes. ReAct for exploring. PreAct for planning. ReWOO for saving money. Reflexion for fixing bugs. MASTER2 picks the mode automatically.

Guardrails. Ten dollar session cap. Circuit breaker opens after three failures with five minute cooldown. Self modifications go to var/staging, validated with ruby -c, promoted or rolled back. Pledge two for system call restrictions. Convergence detector stops oscillation.

Commands: refactor, fix, ideate, hunt, critique, scan, health, selftest. Run ./bin/master for interactive REPL.

Model tiers. Premium for high quality. Strong for balance. Fast for iteration. Cheap for bulk. Four tiers balanced by cost and quality.

The council has twelve personas. Architect, Security Officer, The Attacker, Optimizer, The Minimalist, Accessibility Advocate, Documentation Specialist, Test Engineer, Ops Engineer, The Maintainer, Product Manager, End User.

Thirty-two axioms from authoritative sources. Enforced at six layers: Literal, Lexical, Conceptual, Semantic, Cognitive, Language Axiom. Four scopes: Line, Unit, File, Framework. Sources include The Pragmatic Programmer, SOLID Principles, Clean Code, Strunk and White, Bringhurst, Nielsen.

Installation: git clone, cd pub4/MASTER2, bundle install, export OPENROUTER_API_KEY. Requires Ruby three point three or newer. OpenBSD seven point six or newer recommended.

Budget and rate limiting. Session cap is ten dollars. Rate limit is thirty requests per minute. Circuit breaker trips after three failures with five minute cooldown. Auto-retry uses exponential backoff.

Safe autonomy. All self-edits write to var/staging first. Syntax validation with ruby -c before promotion. Rollback support if tests fail. OpenBSD pledge restricts system calls.

Self test. Run selftest to validate zero violations, zero issues. If MASTER fails its own review, it has failed.

Architecture. Core modules consolidated. workflow.rb, session.rb, review.rb, ui.rb, bridges.rb, analysis.rb, executor.rb. Result monad flows through everything. No exceptions. Explicit error handling.

Dependencies. ruby_llm for OpenRouter, Falcon for async web server, TTY toolkit for terminal UI, Stoplight for circuit breaker, Pastel for colors, Rouge for syntax highlighting, Nokogiri for HTML and XML. OpenBSD first design with doas, pledge, rcctl. Portable to macOS, Linux, Unix.

Optional web UI on port nine thousand. Run ./bin/master --web then open localhost:9000

Speech synthesis. Three engines: Piper for local, Edge TTS for cloud, Replicate for premium voices. Auto-selects based on availability and budget.

Version one point zero point zero. Stable release. Frozen API. Architectural consolidation complete. File sprawl eliminated. Regex removed from axioms. Ruby tree walker. Single README documentation.

MIT License
