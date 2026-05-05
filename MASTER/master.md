# MASTER — Reference

The pipeline runs ten stages. Intake normalizes input and tags the channel — CLI, web, IRC, Matrix, API. Infer routes natural language to a command through `infer_patterns.yml`. Route picks the model tier, the tool, or the pipeline branch. Guard enforces the kernel axioms and aborts on violation. Execute calls the LLM, dispatches a tool, or invokes the command handler. Council and Lint run together under a thirty-second deadline — the council brings adversarial personas; the lint pass scans the output against the rule registry. Prune trims the prose. Memo writes to memory and the audit log. Render emits to the originating channel.

The scan registry holds one hundred and fifty-four named rules across four scopes and twenty-two tiers. The frequent ones — FROZEN_STRING for the literal pragma, EXPLICIT for bare rescue and shadow variables, IMMUTABLE for mutable constants and shared state, CQS for methods that command and query at once, SRP for classes carrying multiple responsibilities, SELF_EXPLAINING for unclear names, LONG_METHOD for anything past ten lines, GOD_CLASS for files past three hundred, DUPLICATE for copy-paste blocks, BARE_RESCUE for naked rescue clauses. Sweep runs rubocop autocorrect first, deterministic and free, then escalates to the LLM rewriter under the corruption guards.

The default model is `nvidia/nemotron-3-super-120b-a12b:free`. The fallback chain — qwen3-coder, minimax-m2.5, gpt-oss-120b, gemini-2.0-flash — kicks in when the circuit breaker trips at eight failures or sixty requests a minute.

The constitution starts at PRESERVE_THEN_IMPROVE_NEVER_BREAK and unfolds through eight kernel axioms — PRESERVE_FIRST, SIMPLEST_WORKS, FAIL_VISIBLY, ONE_SOURCE, DECOUPLE, GUARD_EXPENSIVE, DEGRADE_GRACEFULLY, BE_CONCISE. Violation aborts the pipeline.

Evolution runs through four verbs — `soul propose <rationale>` drafts an amendment, `soul diff` shows it, `soul approve` bumps and tags, `soul reject` discards. The ABSOLUTE sections — anti-simulation, the golden rule — refuse amendment without `/override`.
