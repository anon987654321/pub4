# LLM-Ruby — The LLM Operating System

LLM-Ruby helps you think better with AI. You describe what you want in plain English, and it figures out the rest. The system knows when to use a fast, cheap model and when to bring in the heavy artillery. It argues with itself before giving you an answer. It questions its own assumptions. It learns from its mistakes.

This is not another chatbot wrapper. It is a complete operating system for working with language models—built in pure Ruby, running on OpenBSD, designed for people who care about simplicity and security.

The philosophy is constitutional. Thirty-three principles guide every decision, from "keep it simple" to "fail fast." Seventy-four anti-patterns are continuously guarded against. When the system writes code, it checks its own work against these principles before showing you anything.

The architecture is deliberative. When you ask a hard question, the system can send it to multiple models simultaneously. Each model proposes a solution and writes a letter defending its choices. An arbiter reads the letters and cherry-picks the best ideas. This multi-model deliberation produces answers that no single model could reach alone.

The workflow is introspective. At the end of each phase, the system asks itself what it missed. Each principle faces hostile questioning. Before dangerous actions, a sanity check runs. The evolve command runs a convergence loop until improvements fall below two percent, then it updates this document and saves a wishlist for the next session.

Nine model tiers route requests based on task complexity. DeepSeek handles cheap, simple requests. Grok handles fast turnaround and code generation. Claude Sonnet handles strong reasoning. Gemini, GLM, and Kimi provide diversity for the deliberation chamber. Replicate provides image generation with Flux, video generation with Kling and Minimax, and audio with MusicGen.

The boot sequence takes under 100 milliseconds and prints a hardware probe in the style of OpenBSD dmesg. You land in a REPL with tab completion. Commands are short and memorable. Help is always one keystroke away.

Seven phases structure development: discover, analyze, ideate, design, implement, validate, deliver. Each phase has gates. Each phase ends with reflection. The queue system processes directories systematically with checkpoints and cost budgets. The postprocessing engine applies analog film emulation and professional color grading to generated images and video.

Set the environment variable OPENROUTER_API_KEY and run the CLI. Optionally set REPLICATE_API_TOKEN for image and video generation. Run the test suite to verify everything works.
