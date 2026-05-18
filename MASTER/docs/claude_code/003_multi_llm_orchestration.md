# Claude Code Handoff: Multi-LLM Orchestration Runtime

## Goal

Turn `MASTER/data/prompt_archaeology_patterns.yml` from a research/design registry into a concrete orchestration improvement for MASTER.

Use prompt archives only as behavioral archaeology. Do not copy leaked prompt text into runtime prompts.

## Existing source files

Read first:

- `MASTER/data/prompt_archaeology_patterns.yml`
- `MASTER/data/models.yml`
- `MASTER/data/council.yml`
- `MASTER/data/attention_context.yml`
- `MASTER/docs/provider_economy.md`
- `MASTER/docs/cognitive_runtime.md`
- `MASTER/lib/now/routing/model_router.rb`
- `MASTER/lib/reach/circuit_breaker.rb`
- `MASTER/lib/judge/agent.rb`
- `MASTER/lib/judge/llm_dispatcher.rb`

## Implementation tasks

### 1. Add a first-party orchestration policy object

Create a small runtime object that reads `prompt_archaeology_patterns.yml` and exposes the orchestration blueprint as a policy.

It should know:

- stage names
- risk tiers
- allowed model tiers per risk
- council requirements
- no-copy prompt archaeology safety rule

### 2. Connect risk tiers to model routing

Map task kinds to risk tiers:

- low: classification, summarization, cluster labels, UI copy
- medium: docs, config, preview-gated browser modules
- high: file mutation, auth, production runtime, tool execution
- critical: destructive commands, secret handling, public deployment, permission changes

Routing expectations:

- low -> cheap/fast/local/browser_local where available
- medium -> default/fast/strong with targeted council
- high -> strong only + council
- critical -> strong only + Security/Reliability/Maintainer veto

### 3. Add a browser/local tier placeholder

`mobile_web_opportunities.yml` asks for browser-local AI. Add a placeholder tier in routing policy if not already present, but do not require WebLLM implementation in this PR.

### 4. Council role routing

Use `council.yml` as role review, not redundant multi-model answer generation.

Suggested mapping:

- Security: tool/action/auth/secrets
- Reliability: network/provider/runtime/fallback
- Maintainer: code mutation/refactor
- Architect: system shape/migration
- User Advocate + Accessibility: UI/mobile changes
- Music/Hip-Hop Producer: sonic/visual rhythm and pacing work

### 5. Add evidence-first output contract

For high-risk work, require internal output sections:

- observed facts
- inferred plan
- uncertainty
- rollback path
- verification path

User-facing output should stay concise and only surface what matters.

### 6. Tests

Add unit tests for:

- low-risk task routes to cheap/fast/local
- high-risk mutation requires strong tier
- critical risk requires Security/Reliability/Maintainer veto path
- leaked prompt text is not copied into runtime prompt assembly
- attention_context can be passed into orchestration metadata

## Acceptance criteria

- Prompt archaeology registry is read by code or represented by a runtime policy.
- Risk tier routing exists and is testable.
- Strong models/council are required for high/critical tasks.
- No leaked prompt text is imported into runtime prompt strings.
- Council is role-based critique, not duplicate answer spam.
- Existing `models.yml` behavior is preserved unless explicitly extended.

## Non-goals

- Do not implement browser WebLLM runtime here.
- Do not rewrite all prompt building.
- Do not copy vendor/leaked prompts.
- Do not add verbose self-critique to user-facing output.
- Do not change security policy to be weaker.

## Suggested PR title after implementation

`Implement risk-tiered multi-LLM orchestration policy`
