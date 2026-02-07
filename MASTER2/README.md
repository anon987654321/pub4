# MASTER

MASTER is an autonomous agent system. It processes input through a five-stage pipeline: compression, adversarial debate, axiom enforcement, OpenBSD administration, and output refinement. It runs on OpenBSD, is written in Ruby, and talks to LLMs through OpenRouter.

The pipeline uses a functional Result monad. Each stage receives input, transforms it, and returns Ok or Err. Stages chain via flat_map. First error short-circuits the pipeline. No exceptions, no nil checks, no imperative error handling.

MASTER is self-aware. It knows its own file tree. It can target any directory including itself for analysis and refactoring. When told to run itself over itself, it maps every file, assigns agents, and applies its own axioms to its own code. The self-application axiom is ABSOLUTE: if MASTER cannot pass its own review, it has failed.

MASTER is a superagent. It spawns child agents for decomposed tasks. Each child gets a hex ID, a user-agent string, a budget slice, and an axiom filter. Children run through the same pipeline as the parent. Their output passes through a pf-inspired firewall before the parent trusts it. Children cannot escalate privileges. They cannot doas, sudo, or write to protected paths. If a child needs elevated access, it returns an escalation request. The parent's adversarial council reviews it. Separation of privilege, same as Unix.

The adversarial council has 12 personas. Three hold veto power: Security Officer, The Attacker, The Maintainer. These three can unilaterally block any proposal. The remaining nine are advisory. Consensus requires 70% weighted agreement. If the council oscillates for 25 iterations without convergence, it halts and demands human intervention.

MASTER enforces 20 axioms. 13 are from engineering and communication literature: DRY, KISS, SOLID, Strunk and White, Bringhurst, Nielsen. 7 are structural transformations: merge, flatten, defragment, decouple, hoist, prune, coalesce. These structural axioms apply to everything. Code, configuration, prose, directory trees. Violations of ABSOLUTE axioms halt the system. Violations of PROTECTED axioms generate warnings.

Axiom enforcement happens at five layers: literal with regex, lexical with token counting, conceptual with intent analysis via LLM, semantic with meaning analysis via LLM, and cognitive with human comprehension assessment via LLM. Literal and lexical are free. Conceptual, semantic, and cognitive cost tokens, escalating from cheap to strong tier models.

The LLM provider is OpenRouter. All model requests route through OpenRouter's API. MASTER uses the ruby_llm gem configured with a single OPENROUTER_API_KEY. Models are organized in three tiers: strong with deepseek/deepseek-r1 and anthropic/claude-sonnet-4, fast with deepseek/deepseek-v3 and openai/gpt-4.1-mini, and cheap with openai/gpt-4.1-nano. The system selects the most powerful affordable tier based on remaining budget. A circuit breaker trips after three consecutive failures per model, with a five-minute cooldown. Session budget is ten dollars.

Before editing any file, MASTER cleans it: CRLF to LF, trailing whitespace, BOM, zero-width characters, final newline. Then it assesses each file for rename and rephrase opportunities, structural transformations, and whether the file should be expanded, contracted, or flagged for research.

MASTER generates OpenBSD-native commands and configurations. It uses rcctl not systemctl, pkg_add not apt, doas not sudo, pf not iptables, httpd not nginx. These patterns are loaded from YAML seed data and injected into the LLM context when admin tasks are detected. Similarly, shell output follows zsh-native patterns with parameter expansion, array operations, globbing, never bash-isms.

MASTER uses GitHub via the gh CLI. Agents generate gh commands, never raw API calls. Patterns for creating PRs, merging, issues, workflows, cloning, and forking are loaded from seed data.

There are three execution modes. Interactive REPL with a prompt showing tier and budget. Pipe mode for JSON in/out scripting. Daemon mode watching an inbox directory for task files.

The system boots with OpenBSD-style dmesg output: platform, Ruby version, database schema, LLM providers, model tiers, budget, circuit status, pledge availability.

Setup: bundle install, copy .env.example to .env, set OPENROUTER_API_KEY. Run ./bin/master for REPL, echo JSON to ./bin/master --pipe for scripting, ./sbin/agentd for daemon.

Tests use minitest with in-memory SQLite. The pipeline runs end-to-end without API keys for testing.
