# MASTER

Constitutional AI coding agent. OpenBSD-first. Ruby-only.

## Pipeline

```
Intake -> Infer -> Route -> Guard -> Execute -> [Council | Lint] -> Prune -> Memo -> Render
```

10-stage Result-monadic pipeline. Council and Lint run in parallel (30s timeout).

## Quick Start

```sh
export OPENROUTER_API_KEY=sk-or-...
cd MASTER && bundle exec ruby exe/master
```

## Commands

```
/scan [deep]      Scan lib/ for violations
/sweep [path]     Full-codebase refactor loop
/autoloop [n]     Fix violations until clean (max n cycles)
/council on|off   Multi-persona deliberation
/model [id|list]  Show or set LLM model
/persona <name>   Switch persona (dark_malay, hacker, sysadmin, ...)
/memory           Show cross-session memory
/dreams           Memory consolidation status
/soul             Show identity document
/orders           Standing orders FSM
/heartbeat        Autonomous scheduled tasks
/skills           Loaded skill directories
/gateway          Multi-channel status
/snapshot         Generate codebase snapshot
/undo             Revert last file change
/scan deep        Deep scan (adds LLM rules)
/explain          Architecture self-map
/tokens           Context size estimate
/cost             Session cost
/tts on|off       Text-to-speech toggle
/help             All commands
/exit             Save and quit
```

## Architecture

```
lib/master/
  agent.rb              LLM interface, tool dispatch, fallback chains
  autoloop.rb           Scan-fix loop with Reflexion retries
  axioms.rb             Kernel + philosophy axioms from data/axioms.yml
  circuit_breaker.rb    Per-model failure tracking, cooldown, rate limiting
  cli.rb                REPL, TTS, background scanning
  config.rb             Persistent YAML config with typed helpers
  context_window.rb     Token budget tracking, auto-compaction
  event_bus.rb          Pub/sub with glob patterns
  gateway.rb            Multi-channel message router
  governor.rb           Tool approval tiers (safe/guarded/dangerous)
  heartbeat.rb          Autonomous scheduled tasks
  memory.rb             Cross-session persistent store, TF-IDF search
  personality.rb        Persona system prompts from axioms + constitution
  pipeline.rb           Result-monadic stage chain with rollback
  result.rb             Ok/Err monad with categories
  skills.rb             Composable skill directory discovery
  soul.rb               SOUL.md version-controlled identity
  sweep.rb              Full-codebase refactor with convergence detection

  routing/
    model_router.rb     Weighted scoring, 3-tier fallback chains
    continuity_index.rb Free model availability tracking

  stages/
    intake.rb           Input normalization
    infer.rb            Intent classification
    route.rb            Command dispatch
    guard.rb            Constitutional + injection guards
    execute.rb          LLM call via Agent
    council.rb          Multi-persona deliberation
    lint.rb             Scan + autofix
    prune.rb            Strunk & White prose rules
    memo.rb             Memory persistence
    render.rb           Output formatting

  scan/
    scanner.rb          Rule engine (18 rules, 3 depths)
    rules/*.rb          FrozenString, BareRescue, GodClass, ...

  tools/
    read_file.rb        File reading with line numbers
    write_file.rb       Atomic writes with undo
    str_replace.rb      Unique string replacement
    shell.rb            Sandboxed zsh execution
    web_search.rb       DuckDuckGo instant answers
    ...

  council/
    personas.rb         Multi-advisor personas
    deliberation.rb     Parallel deliberation engine

  swarm/
    coordinator.rb      Multi-worker task dispatch
    workers/*.rb        Analyst, Coder, Researcher, Reviewer
```

## Data Files (Living Spec)

```
data/axioms.yml         Kernel axioms + philosophy principles
data/constitution.yml   Golden rule, banned output, protection levels
data/workflow.yml       READ_BEFORE_WRITE, scan depths, phases
data/models.yml         Model tiers, fallback chains, routing weights
data/heartbeat.yml      Autonomous job schedule
data/strunk.yml         Prose pruning rules
data/council.yml        Deliberation personas
data/standing_orders.yml FSM state machine
data/language_rules.yml  Ruby/Rails/zsh/OpenBSD rules
data/principles.yml     KISS, DRY, YAGNI, SoC, SRP, SOLID
data/fallback_models.yml Model fallback definitions
```

## Web UI

Rails 8 + Falcon on port 10002. SSE streaming. TTS via edge-tts.
CSS orb animations (idle/think/speak). Accessible at ai.brgen.no:3000.

## Deploy

```sh
doas sh DEPLOY/openbsd/openbsd.sh
```

## License

Proprietary. All rights reserved.
