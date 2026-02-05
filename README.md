# LLM.rb — The LLM Operating System

Constitutional AI in pure Ruby. Runs on OpenBSD, the most secure Unix.

Set `OPENROUTER_API_KEY` and run `ruby bin/cli`. The system boots in under 100 milliseconds, prints a dmesg-style hardware probe, and drops you into a REPL. Thirty-three principles guide every decision. Seventy-four anti-patterns are continuously guarded against.

The LLM client routes through OpenRouter with nine model tiers. DeepSeek handles cheap requests. Grok handles fast and code tasks. Claude Sonnet handles strong reasoning. Gemini, GLM, and Kimi provide diversity for the chamber. The chamber sends code to multiple models for deliberation. Each model proposes a unified diff and writes a letter defending its changes. The arbiter cherry-picks the best ideas.

The creative chamber extends this to ideas, images, and video. Brainstorm mode has models propose and debate concepts. Image mode generates variations across Flux, SDXL, and Ideogram. Video mode writes storyboards and generates scenes with Kling and Minimax. Prompt enhancement refines your prompts through multi-model deliberation before sending to the main model.

Introspection forces the system to examine its own reasoning. At the end of each phase, it asks what it missed. Each principle faces hostile questioning. The sanity check runs before dangerous actions. The evolve command runs a convergence loop: analyze, prioritize, deliberate, apply, validate, reflect, repeat. It stops when improvement rate drops below two percent for three cycles, then updates the README and saves a wishlist for the next session.

Seven phases structure development: discover, analyze, ideate, design, implement, validate, deliver. Each phase has gates. Each phase ends with reflection. The queue system processes directories systematically with checkpoints and cost budgets.

Set `REPLICATE_API_TOKEN` for image and video generation. Run `ruby test/test_master.rb` to verify.
