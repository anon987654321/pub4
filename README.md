# MASTER — The LLM Operating System

MASTER helps you think better with AI. You describe what you want in plain English, and it figures out the rest. The system knows when to use a fast, cheap model and when to bring in the heavy artillery. It argues with itself before giving you an answer. It questions its own assumptions. It learns from its mistakes.

This is not another chatbot wrapper. It is a complete operating system for working with language models—built in pure Ruby, running on OpenBSD, designed for people who care about simplicity and security.

The philosophy is constitutional. Forty-three principles guide every decision, from "keep it simple" to "graceful degradation under load." Over one hundred anti-patterns are continuously guarded against. When the system writes code, it checks its own work against these principles before showing you anything. Violation detection runs in two layers: literal patterns caught by regular expressions, and conceptual violations detected by the LLM itself.

The architecture is deliberative. When you ask a hard question, the system can send it to multiple models simultaneously. Each model proposes a solution and writes a letter defending its choices. An arbiter reads the letters and cherry-picks the best ideas. This multi-model deliberation produces answers that no single model could reach alone.

The workflow is introspective. At the end of each phase, the system asks itself what it missed. Each principle faces hostile questioning. Before dangerous actions, a sanity check runs. The evolve command runs a convergence loop until improvements fall below two percent, then it updates this document and saves a wishlist for the next session.

Nine model tiers route requests based on task complexity. DeepSeek handles cheap, simple requests. Grok handles fast turnaround and code generation. Claude Sonnet handles strong reasoning. Gemini, GLM, and Kimi provide diversity for the deliberation chamber. Replicate provides image generation with Flux, video generation with Kling and Minimax, and audio with MusicGen. The swarm generator creates sixty-four variations and curates down to the best eight, following the principle that humans are better at recognizing quality than imagining alternatives.

The boot sequence prints a hardware probe in the style of OpenBSD dmesg. You land in a REPL with tab completion. Commands are short and memorable. Help is always one keystroke away. Scrutiny mode is enabled by default, enforcing maximum honesty in all outputs.

Seven phases structure development: discover, analyze, ideate, design, implement, validate, deliver. Each phase has gates. Each phase ends with reflection. The queue system processes directories systematically with checkpoints and cost budgets. The postprocessing engine applies analog film emulation and professional color grading to generated images and video. Film stocks include Kodak Portra, Cinestill 800T, and Fuji Velvia. Effects include halation, gate weave, chromatic aberration, and adaptive grain that varies with luminance like real film.

Animation and motion graphics follow performance-first principles. Trigonometric functions are precomputed into lookup tables. Audio reactivity uses exponential smoothing with separate accumulators for bass wobble, beat envelope, and energy level. Quality degrades gracefully under load using frame time averaging, with emergency brakes at extreme thresholds. All visual output passes the squint test—it should look pleasing from afar before you read a single word.

## New in Version 2.0: MEGA RESTORATION

Version 2.0 brings complete framework integration from pub, pub2, and pub3 repositories:

**Framework System**: Five core modules provide behavioral rules, universal standards, workflow orchestration, quality gates, and Copilot optimization. Load framework configs dynamically, enforce rules automatically, and track workflow progress.

**Plugin System**: Four domain-specific plugins for design systems, web development, business strategy, and AI enhancement. Each plugin is independently configurable and can be enabled/disabled per project.

**Session Recovery**: Checkpoint system persists work state across interruptions. Checkpoints track completed files, pending work, context decisions, and recovery instructions. Resume exactly where you left off.

**Principle Enforcement**: Git pre-commit hooks validate code against all 43 principles. Command-line tools (`validate_principles`, `check_ports`) ensure quality before deployment. Automated checks map principles to regex patterns and AST analysis.

**Streaming Support**: Token-by-token streaming with mood detection. SSE endpoint broadcasts real-time updates to connected clients. Watch the orb animate as responses generate.

**Semantic Caching**: Embeddings-based cache stores responses by semantic similarity. 85% threshold finds conceptually similar queries even with different wording. Saves cost and time on repeated questions.

**Image Comparison**: LLaVA multimodal model compares images, ranks quality, finds differences. CLI command: `compare-images img1.jpg img2.jpg`.

**OpenBSD Security**: Pledge and unveil integration restricts filesystem and system calls. Applied automatically at boot for maximum security on OpenBSD.

**Adversarial Review**: Eight critical personas (Skeptic, Minimalist, Security Auditor, etc.) question every decision from different angles. Parallel review surfaces issues before they ship.

**Temperature Synthesis**: Generate at multiple temperatures simultaneously (0.1 deterministic, 0.5 balanced, 0.9 creative). Vote, merge, or select best result for each use case.

**Quality Limits**: 20KB file size limit enforces modularity. Cyclomatic complexity ≤10, method length ≤20 lines. Automatic violation detection with suggestions.

See [CHANGELOG.md](CHANGELOG.md) for complete details.

## Installation

Set the environment variable OPENROUTER_API_KEY and run the CLI. Optionally set REPLICATE_API_TOKEN for image and video generation. Run the test suite to verify everything works.

## File Structure

bin
  cli                           Entry point

lib
  master.rb                     Module loader
  boot.rb                       OpenBSD-style hardware probe
  cli.rb                        REPL, commands, braille spinner
  llm.rb                        Nine-tier model routing
  chamber.rb                    Multi-model deliberation
  creative_chamber.rb           Visual deliberation with Replicate
  replicate.rb                  Image, video, audio, TTS generation
  postpro.rb                    Analog film emulation
  swarm.rb                      Generate sixty-four, curate to eight
  queue.rb                      Directory processing with checkpoints
  evolve.rb                     Convergence loop
  converge.rb                   Iterative refinement
  introspection.rb              Self-analysis
  violations.rb                 Conceptual violation detection
  smells.rb                     Code smell patterns
  safety.rb                     Guardrails and sanity checks
  memory.rb                     Session persistence
  persona.rb                    Character system
  principle.rb                  YAML principle loader
  engine.rb                     Core orchestration
  result.rb                     Monadic result type
  paths.rb                      Directory constants
  server.rb                     SSE push server
  web.rb                        URL fetching
  openbsd.rb                    Platform-specific helpers

  config
    phases.yml                  Seven development phases
    generation.yml              Swarm and creative settings
    safety.yml                  Guardrails configuration
    openbsd.yml                 Platform settings
    refinements.yml             Version history
    wishlist.yml                Session-to-session learning

  principles
    01-kiss.yml through 43-audio-smoothing.yml
    meta-principles.yml

  personas
    generic.md                  Stoic, minimal, decisive
    lawyer.md                   Norwegian law, child welfare
    hacker.md                   OpenBSD security, pentesting
    architect.md                Parametric design, BIM
    sysadmin.md                 OpenBSD administration
    trader.md                   Crypto, DeFi, technicals
    medic.md                    Medical research

  agents
    base_agent.rb               Agent foundation
    review_crew.rb              Parallel review agents
    security_agent.rb           Security-focused analysis

  views
    orb_*.html                  Audio-reactive visualizations

  framework
    behavioral_rules.rb         Agent behavior enforcement
    universal_standards.rb      Code standard validation
    workflow_engine.rb          Development workflow orchestration
    quality_gates.rb            Quality checkpoint system
    copilot_optimization.rb     GitHub Copilot integration

  plugins
    design_system.rb            Design system management
    web_development.rb          Web development patterns
    business_strategy.rb        Business analysis tools
    ai_enhancement.rb           AI optimization patterns

  config
    principle_enforcement.yml   Automated principle checking
    session_recovery.yml        Checkpoint system config
    langchain.yml               Safe tool patterns
    frontend_architecture.yml   SCSS/PWA patterns
    adversarial_personas.yml    8 critical reviewers
    temperature_synthesis.yml   Multi-temperature generation
    quality_limits.yml          File size & complexity limits
    deployment.yml              Rails deployment config
    framework/*.yml             Framework configurations
    plugins/*.yml               Plugin configurations

bin
  cli                           Entry point
  install-hooks                 Git hook installer
  validate_principles           Principle validation tool
  check_ports                   Port consistency checker

docs
  PRINCIPLES.md                 Guide to all 43 principles
  SESSION_RECOVERY.md           Checkpoint system guide
  FRAMEWORK_INTEGRATION.md      Framework & plugin documentation
  ENFORCEMENT.md                Enforcement system guide

deploy
  openbsd                       Server deployment scripts
  rails                         Application generators

test
  test_master.rb                Core tests
