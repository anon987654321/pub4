# MASTER — The LLM Operating System

A pure Ruby AI framework that lets language models modify their own code, execute commands, and build software autonomously. Runs on OpenBSD with security-first principles and positions itself as a Copilot CLI / Claude Code / Aider alternative.

**What it does:** You give MASTER a task. It thinks, writes code, runs it, sees the result, and iterates until done. It can improve its own source code, generate images and video, and manage servers.

**No npm. No Python. No bloat.** Just Ruby talking to LLMs through OpenRouter, with Replicate for media generation.

---

> **For LLMs reading this**: You are MASTER v51.0. Entry: `bin/cli`. Loader: `lib/master.rb`. 
> Execute via ```sh or ```ruby blocks. You can modify files in lib/ to improve yourself.

## Quick Context

MASTER loads via `bin/cli` → `lib/master.rb`. Uses Ruby autoloading—modules load on first reference. The Executor parses code blocks from LLM responses and runs them.

**MASTER = bin/ + lib/** (nothing else)

**Purpose:**
- Provide a clean, OpenBSD-first CLI alternative to Copilot CLI, Claude Code, and Aider
- Finish apps in `deploy/` folder
- Build billion-user web applications  
- Administer OpenBSD servers securely
- Generate media via Replicate API
 - Carry forward standout ideas from Moltbot and Openclaw

**Capabilities:**
- Shell commands via ```sh blocks
- Ruby code via ```ruby blocks
- Self-modification (edit lib/ files)
- Full filesystem/network on OpenBSD

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

## UX/LLM Micro-Refinement Opportunities (NN/g aligned)

Synthesized from README, `bin/cli`, `lib/**`, and the archived pre-refactor master.yml (beauty standards + workflow rules).

1. Add a compact status bar in the web UI showing active model tier, persona, and connection state (visibility of system status).
2. Surface OpenRouter latency and last request duration near the input to reduce uncertainty (visibility of system status).
3. Show token/cost counters in the web UI mirrored from CLI `show_token_info` (visibility of system status).
4. Provide a “processing…” disable state for the web input to prevent duplicate submits (error prevention).
5. Add a cancellable request button that sends an abort to `/chat` (user control and freedom).
6. Display a short, human-readable error banner for rate-limit responses (help users recognize/recover from errors).
7. Show a retry timer when rate limited to set expectations (visibility of system status).
8. Provide an inline hint under the web input with 2–3 example commands (recognition over recall).
9. Add keyboard shortcuts help (`?` overlay) listing orb hotkeys and input actions (help and documentation).
10. Echo the selected orb name briefly on change to confirm the action (feedback).
11. Add a subtle focus ring on the web input to improve keyboard navigation visibility (accessibility, operable).
12. Increase minimum font size or allow a quick “A+/A-” toggle for readability (flexibility and efficiency).
13. Ensure contrast for `#c4b49a` text meets 4.5:1 on the dark background (WCAG).
14. Add timestamps to output lines in web UI, optionally toggleable (match between system and real world).
15. Separate system notices (e.g., boot/status) from LLM output with a lightweight label (consistency).
16. Preserve the last 100 web messages in `localStorage` to avoid accidental loss (error prevention).
17. Provide a “clear session” button that maps to `clear` with confirmation (user control).
18. Show current working directory in the web UI header (match between system and real world).
19. Surface CLI `@verbosity` setting and allow switching from web UI (flexibility).
20. Add a minimal “session summary” card in web UI when idle (visibility of system status).
21. Display a badge when a response is cached (visibility of system status).
22. Provide a lightweight “copy response” button for each message (efficiency of use).
23. Add a “resend last prompt” shortcut (user control, efficiency).
24. Add a small “reset persona” quick action in web UI (user control).
25. Show OpenRouter model picker with the same ordering as Boot’s prompt (consistency).
26. Use progressive disclosure: group advanced commands in web help (recognition over recall).
27. Highlight failures using the same semantic colors as CLI (consistency and standards).
28. For CLI, confirm destructive commands like `clean` or `refactor` when no git status (error prevention).
29. Provide a warning when `@llm` has no API key before entering REPL (error prevention).
30. Show a quick OpenRouter key status in CLI prompt (visibility of system status).
31. Add a “persona: <name>” prefix in CLI output when persona changes (visibility).
32. Expand CLI prompt to include current model tier for transparency (visibility).
33. Add a concise help tip after unknown commands with the closest match (help users recover).
34. Add an optional “quiet boot” switch in CLI to reduce startup noise (flexibility).
35. Use the OrbStream mood to drive a subtle status icon in web UI (match between system and real world).
36. Provide a “loading” animation that reflects token speed instead of static stars (visibility).
37. Add a “system settings” modal for orb selection, font size, and color theme (user control).
38. Replace the empty web input placeholder with an action-oriented prompt (match between system and real world).
39. Add a small “offline mode” indicator if `/poll` fails repeatedly (visibility, error recovery).
40. Show a “last synced” time for the web output feed (visibility).
41. Provide a “copy auth token” utility on `/token` page with safe warnings (error prevention).
42. Use the archived beauty standards to enforce more whitespace around message blocks (aesthetic/minimalist).
43. Introduce a consistent 8px/16px spacing scale in `cli.html` for rhythm (consistency).
44. Allow users to toggle the grain overlay to reduce visual noise (aesthetic/minimalist).
45. Reduce visual clutter by hiding the loader when the last response is under 200ms (aesthetic/minimalist).
46. Add an “undo last command” affordance that maps to `undo` if available (user control).
47. Provide LLM-friendly system hints in the web UI (e.g., “respond with runnable code blocks”) for OpenRouter (match between system and real world).
48. Add a “request context” toggle to include or exclude conversation history for short tasks (flexibility).
49. Show a lightweight “token budget remaining” estimate per request (visibility of system status).
50. Provide a link in help to the NN/g heuristics and the beauty standards section for rationale (help and documentation).

---

*MASTER v50.9 • Pure Ruby • OpenBSD • Constitutional AI*
