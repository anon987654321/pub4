# MASTER2 Contribution Rules

## MANDATORY: No New Files Without Justification
- Before creating a new file, check if the concept fits inside an existing module
- A new file is only justified if it would exceed 200 lines when added to existing code
- Prefer adding methods to existing modules over creating new modules

## File Size Guidelines
- Files under 30 lines should be merged into their parent module
- Target: 15-25 files in lib/, not 60+

## PR Rules
- Never create a PR that overlaps with an existing open PR
- Every PR must list which existing files it modifies (not just new files)
- Bug fixes and new features must be in separate PRs

## Architecture
- `result.rb` — Result monad (do not duplicate)
- `llm.rb` — All LLM/OpenRouter logic including context window management
- `executor.rb` — Tool dispatch, permission gates, safety guards
- `pipeline.rb` + `stages.rb` — Pipeline processing
- `code_review.rb` — All static analysis (smells, violations, bug hunting)
- `introspection.rb` — All self-analysis (critique, reflection)
- `self_test.rb` — All testing and self-repair
- `enforcement.rb` — Axiom enforcement (single entry point)

