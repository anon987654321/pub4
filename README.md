# MASTER v50.9

Constitutional AI for code quality. Thirty-three principles guide every decision. Modular Ruby architecture runs on OpenBSD, Termux, macOS, Linux, and Windows.

Set `OPENROUTER_API_KEY` and run `ruby bin/cli`. Boot takes 140ms. The REPL provides thirty commands for chat, refactoring, code review, git operations, image generation, and web browsing. Type `help` to see them.

The LLM client uses five tiers. DeepSeek handles fast, code, and medium requests at $0.00014 per thousand tokens. Claude Sonnet handles strong requests. Claude Opus handles premium requests when you need the best reasoning.

The chamber sends code to multiple models for deliberation. Each model proposes a unified diff and writes a letter defending its changes. The arbiter cherry-picks the best ideas. Models include GPT-4o, Gemini, DeepSeek, and Qwen, with Sonnet as arbiter.

The creative chamber extends this to ideas, images, and video. Brainstorm mode has models propose and debate concepts. Image mode generates variations across Flux, SDXL, and Ideogram. Video mode writes storyboards and generates scenes with Kling and Minimax. Conversation mode simulates dialogue between models playing assigned roles.

Introspection forces the system to examine its own reasoning. At the end of each phase, it asks: what did I miss? Each principle faces hostile questioning: what assumption could be wrong? What would a senior engineer critique? The sanity check runs before dangerous actions: is this reversible? What's the worst case?

Seven phases structure development: discover, analyze, ideate, design, implement, validate, deliver. Each phase has gates that must pass before proceeding. Each phase ends with reflection.

The queue system processes directories systematically. Add files, set priorities, checkpoint progress. The system detects binaries and skips them. Cost budgets prevent runaway spending.

Set `REPLICATE_API_TOKEN` for image and video generation. Run `ruby test/test_master.rb` to verify the installation.
