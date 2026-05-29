# pub4 — GROK.md

Bootstrap instructions specific to Grok (xAI) when working in this repository.

**Primary entry point for all agents:** Read `MASTER/QUICKSTART.md` first. It provides the practical mental model and explicit LLM ergonomics guidance (including the new `llm_ergonomics` section in `data/workflow.yml`).

Only after building a working model, dive into the deep constitutional sources:
- `MASTER/data/soul.yml`
- `data/rules.yml`, `ruby_style.yml`, `workflow.yml`, `standing_orders.yml`, `patterns.yml`
- `CLAUDE.md` (for environment, SSH, deploy, and operator patterns)
- `AGENTS.md` (general agent bootstrap)

## How to Work Effectively with Grok Here

Grok is well-suited for this environment because of strong tool use, planning, and code generation capabilities. Leverage these strengths:

- Use me for high-level planning, architectural reasoning, and generating compliant patches.
- I can perform full-file reads, structured searches (via the available grep tool), and precise edits.
- For exploration and reconnaissance, I may use my full available tools while still routing production changes through the project's required mechanisms (full file reads, internal scans where possible, minimal patches).
- When the full MASTER CLI is available on the VPS, prefer routing deep analysis through `/scan deep`, `/sweep`, etc., so the agent improves itself.

**Primary recommended interface (unified ergonomics):**
Use `/run <natural language task description>` inside the CLI. This is the new single preferred entry point for most work — it goes through full intelligent pipeline routing (including enhance, council when appropriate).

**Recommended interaction pattern:**
1. Point me at the specific goal + relevant files (or let me discover via full reads).
2. I will read affected files in full before proposing changes.
3. Expect evidence-based responses: diffs for modifications, command output for verification.
4. For large or structural work, break into small slices that can be reviewed and committed incrementally.

## Grok-Specific Notes

- I handle long, multi-turn reasoning and context well. Use me for sustained refactoring or cleanup campaigns broken into compliant micro-steps.
- I have access to various tools (code execution, web search, image generation, etc.). Use them when they help produce evidence or artifacts for the project.
- When generating code, I default to clear, maintainable style. Cross-check against `data/ruby_style.yml`.
- For self-improvement of MASTER itself, I can help draft richer event emissions, better documentation, or ergonomics enhancements that align with the constitution.

**Voice / TTS**: The agent uses ms-MY-OsmanNeural (Osman) by default (per `data/soul.yml`). Creative vocal styles are available via the STYLES in `lib/voice/speech.rb` (dramatic, intimate, intense, ethereal, robotic, storyteller, energetic, etc.). These combine rate + pitch for expressive delivery on top of the base Osman voice. Post-processing via /postpro or dilla tools can add further layers if needed.

## Environment & Remote Work

Follow the patterns in `CLAUDE.md`:
- Prefer pure Ruby payloads over one SSH for VPS work.
- Use tmux for long operations.
- After any `web/` changes: `doas rcctl restart master`.

Git: Work on feature branches when possible. Small, frequent commits with active voice. Never force-push main.

## Philosophy Alignment

Everything must ultimately serve the constitutional goals in `data/soul.yml` and `data/rules.yml`:
- PRESERVE_THEN_IMPROVE_NEVER_BREAK
- READ_FULL_FILES + READ_BEFORE_WRITE
- ONE_SOURCE / SINGULARITY
- Rich observability (events, the particle face)
- Making the system more pleasant and effective for future agents (including future Groks)

This GROK.md exists to reduce friction for Grok and future xAI agents, in line with the `llm_ergonomics` guidance added to `data/workflow.yml`.

Work here with precision, evidence, and strict adherence to the constitution.