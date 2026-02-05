# MASTER — The LLM Operating System

> **For LLMs reading this**: You are MASTER v50.9, a constitutional AI framework in pure Ruby.
> Entry point: `bin/cli`. Core loader: `lib/master.rb`. You can modify your own code.

## Quick Context

MASTER is loaded via `bin/cli` which requires `lib/master.rb`. The framework uses Ruby autoloading—modules are loaded on first reference. You have filesystem access through the Executor module which parses code blocks from your responses and runs them.

**MASTER consists of:**
- `bin/` — CLI entry points and tools
- `lib/` — Core framework modules

**MASTER's purpose:**
- Finish and deploy the apps in `deploy/` folder
- Build billion-user scale web applications
- Administer OpenBSD servers with security-first principles
- Generate images, video, audio via Replicate API

**Your capabilities:**
- Execute shell commands via ```sh blocks
- Execute Ruby code via ```ruby blocks  
- Modify files in lib/ to improve yourself
- Full filesystem and network access on OpenBSD

## File Tree

```
bin/
├── cli                      # Entry point - starts MASTER REPL
├── check_ports              # Port consistency checker
├── install-hooks            # Git pre-commit hook installer
└── validate_principles      # Principle validation tool

lib/
├── master.rb                # Module loader with autoloads
├── boot.rb                  # OpenBSD-style dmesg boot sequence
├── cli.rb                   # REPL, commands, braille spinner
├── llm.rb                   # 9-tier model routing (DeepSeek→Claude)
├── chamber.rb               # Multi-model deliberation
├── creative_chamber.rb      # Visual deliberation with Replicate
├── replicate.rb             # Image/video/audio/TTS generation
├── postpro.rb               # Analog film emulation (Portra, Cinestill, etc.)
├── audio.rb                 # Cross-platform audio playback
├── swarm.rb                 # Generate 64, curate to 8
├── queue.rb                 # Directory processing with checkpoints
├── evolve.rb                # Convergence loop
├── converge.rb              # Iterative refinement
├── introspection.rb         # Self-analysis
├── violations.rb            # Conceptual violation detection
├── smells.rb                # Code smell patterns (108 patterns)
├── safety.rb                # Guardrails and sanity checks
├── memory.rb                # Session persistence
├── persona.rb               # Character system
├── principle.rb             # YAML principle loader with caching
├── engine.rb                # Core orchestration
├── result.rb                # Monadic Result type
├── paths.rb                 # Directory constants
├── server.rb                # Falcon/WEBrick web server
├── web.rb                   # URL fetching
└── openbsd.rb               # Platform-specific helpers
│
├── core/
│   ├── context.rb           # System awareness for LLM prompts
│   ├── executor.rb          # Agentic command execution from LLM output
│   ├── session_recovery.rb  # Checkpoint system
│   ├── session_persistence.rb
│   ├── semantic_cache.rb    # Embeddings-based response cache
│   ├── principle_autoloader.rb
│   ├── token_streamer.rb    # Token-by-token streaming
│   ├── sse_endpoint.rb      # Server-sent events
│   ├── orb_stream.rb        # Orb animation streaming
│   ├── image_comparison.rb  # LLaVA multimodal comparison
│   └── openbsd_pledge.rb    # pledge/unveil security
│
├── framework/
│   ├── behavioral_rules.rb  # Agent behavior enforcement
│   ├── universal_standards.rb
│   ├── workflow_engine.rb   # 7-phase development workflow
│   ├── quality_gates.rb     # Quality checkpoints
│   └── copilot_optimization.rb
│
├── plugins/
│   ├── ai_enhancement.rb
│   ├── business_strategy.rb
│   ├── design_system.rb
│   └── web_development.rb
│
├── agents/
│   ├── base_agent.rb
│   ├── review_crew.rb       # 8 adversarial reviewers
│   └── security_agent.rb
│
├── cli/commands/
│   └── openbsd.rb           # rcctl, pfctl, pkg_add wrappers
│
├── config/
│   ├── phases.yml           # 7 development phases
│   ├── generation.yml       # Swarm settings
│   ├── safety.yml           # Guardrails
│   ├── openbsd.yml
│   ├── principle_enforcement.yml
│   ├── session_recovery.yml
│   ├── adversarial_personas.yml
│   ├── temperature_synthesis.yml
│   ├── quality_limits.yml   # 20KB file limit, complexity ≤10
│   ├── deployment.yml
│   ├── framework/*.yml
│   └── plugins/*.yml
│
├── principles/              # 43 constitutional principles
│   ├── 01-kiss.yml          
│   ├── 02-dry.yml           
│   ├── ...                  
│   ├── 43-audio-smoothing.yml
│   └── meta-principles.yml
│
├── personas/
│   ├── generic.md           # Default: stoic, minimal
│   ├── hacker.md            # OpenBSD security
│   ├── sysadmin.md          # Server administration
│   ├── architect.md         # Parametric design
│   ├── lawyer.md            # Norwegian law
│   ├── trader.md            # Crypto/DeFi
│   └── medic.md             # Medical research
│
└── views/
    ├── cli.html             # Main web UI with orb iframe
    ├── orb_blob.html        # Morphing blobs (4-bit retro)
    ├── orb_particle.html    # Particle system
    ├── orb_3d.html          # 3D rotating sphere
    ├── orb_backlight.html   # Backlit glow
    ├── orb_warp.html        # Warp tunnel
    ├── orb_retro.html       # Retro style
    ├── orb_connected.html   # Connected nodes
    └── orb_loader.html      # Loading animation

var/
└── replicate/               # Generated audio/video cache (gitignored)

docs/
├── PRINCIPLES.md            # All 43 principles explained
├── SESSION_RECOVERY.md      # Checkpoint system
├── FRAMEWORK_INTEGRATION.md # Framework & plugins
└── ENFORCEMENT.md           # Enforcement system
```

## Target Projects (deploy/)

MASTER exists to finish and deploy these apps:

```
deploy/
├── openbsd/
│   └── openbsd.sh           # Full OpenBSD server setup
│
└── rails/
    ├── amber/               # Dating app
    ├── baibl/               # Book platform  
    ├── blognet/             # Blog network
    ├── brgen/               # Bergen apps
    │   ├── brgen.sh         # Main Bergen app
    │   ├── brgen_playlist.sh
    │   ├── brgen_takeaway.sh
    │   ├── brgen_tv.sh
    │   ├── brgen_dating.sh
    │   └── brgen_marketplace.sh
    ├── bsdports/            # OpenBSD ports browser
    ├── hjerterom/           # Heart room
    └── privcam/             # Privacy camera
```

## Architecture

```
┌─────────────┐
│   bin/cli   │  Entry point
└──────┬──────┘
       │
┌──────▼──────┐
│  Boot.run   │  dmesg-style startup, model selection
└──────┬──────┘
       │
┌──────▼──────┐
│   CLI.new   │  REPL loop, command dispatch
└──────┬──────┘
       │
┌──────▼──────┐     ┌─────────────┐
│    LLM      │────▶│  OpenRouter │  9 model tiers
└──────┬──────┘     └─────────────┘
       │
┌──────▼──────┐     ┌─────────────┐
│  Executor   │────▶│   Safety    │  Blocks dangerous patterns
└──────┬──────┘     └─────────────┘
       │
       ▼
   [Filesystem]     Actual command execution
```

## Model Tiers

| Tier | Model | Use Case |
|------|-------|----------|
| cheap | DeepSeek | Simple queries |
| fast | Grok | Quick responses |
| strong | Claude Sonnet | Complex reasoning |
| frontier | Claude Opus | Hardest problems |
| code | Codestral | Code generation |
| diverse | Gemini/GLM/Kimi | Chamber deliberation |

## Environment

```sh
OPENROUTER_API_KEY=sk-or-...     # Required
REPLICATE_API_TOKEN=r8_...       # For images/video/audio
```

## Commands

```
ask <query>      Chat with LLM
scan             Analyze current directory  
refactor         Improve code quality
chamber <query>  Multi-model deliberation
replicate        Generate images/video/audio
queue <dir>      Process directory with checkpoints
evolve           Convergence loop until <2% improvement
help             Show all commands
```

---

*MASTER v50.9 • Pure Ruby • OpenBSD • Constitutional AI*
