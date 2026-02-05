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

deploy
  openbsd                       Server deployment scripts
  rails                         Application generators

test
  test_master.rb                Core tests
