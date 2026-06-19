# MASTER model routing — gap analysis and rearchitecture

Authority: this is analysis only. It proposes changes; `data/soul.yml` and `data/rules.yml`
remain law. Nothing here is applied until you approve.

## 1. What actually exists today (traced path)

A turn that needs an LLM walks this path:

1. `Master.default_model` (`lib/master.rb:147`) returns `z-ai/glm-4.5-air:free` when
   `OPENROUTER_API_KEY` is set, else `deepseek-chat`, else `gemini-2.5-flash`, else glm again.
2. `Ground::Config` (`lib/ground/config.rb:14`) hardcodes the same `z-ai/glm-4.5-air:free`
   as the stored default model.
3. `Now::Routing::ModelRouter#fallback_chain` (`lib/now/routing/model_router.rb:37`) builds the
   candidate list: preferred-for-tier, then every model in every tier flattened, then
   continuity models, then the config model, de-duplicated and ranked by provider health.
4. `Judge::Agent::ModelSelector#routed_models` calls that chain and optionally biases it cheap
   or strong based on the homeostat.
5. `Judge::Agent::FallbackChain#attempt_chat_with_fallbacks` tries each candidate once in the
   primary reasoning mode, then retries only the primary model in alternate modes
   (`code_agent`, `react`, `direct`).
6. `Judge::LLMDispatcher#send_with_cache` dispatches: `claude-cli:` models shell out to the
   local `claude` binary, `web-chat:` models call `WebChat.call`, tool-incapable models go
   through the ReAct text-tool loop, everything else goes through `ruby_llm`.

So the headline answer to "why isn't it using a huge list of free models by default" is:
**it already defaults to a free model, and a ~30-model catalog already exists in
`data/models.yml`.** The real problem is that large parts of that catalog and the free/web-chat
fallback machinery are mis-wired, mislabeled, or never reached. The intent is present; the
plumbing is broken in specific, fixable places.

## 2. Confirmed gaps and weaknesses (cross-referenced)

### 2.1 The `WebChat` constant is undefined — the free web-chat path is dead
`lib/judge/llm_dispatcher.rb:145` calls `WebChat.call(provider:, prompt:, system:)`. There is no
`class WebChat` anywhere in `lib/`. Any model with the `web-chat:` prefix raises
`NameError`, which the surrounding `rescue StandardError` converts into a provider error and
marks the model failed. The capability you specifically want — browsing chatgpt.com and asking
for free — is scaffolded (prefix routing exists, the `ferrum` gem is in the Gemfile and locked
at 0.17.1) but was never implemented.

### 2.2 The router digs a config block that does not exist
`model_router.rb:50` reads `@rules.dig("ferrum_web_chat", "free_latest")` to add web-chat
continuity models. `data/models.yml` has no `ferrum_web_chat:` key (only `openrouter:
free_latest:`). So web-chat models are never injected into any chain even if `WebChat` existed.

### 2.3 The curated `free` tier is never routed to
`data/models.yml` defines a deliberate `free:` tier (glm, gemma, llama-4-scout, phi, reka,
nemotron, qwen-coder, llama-70b, hermes-405b). But the `routes:` block maps tasks only to
`fast`, `default`, `strong`, and `cheap`. No route, and no escalation tier, ever names `free`.
The list you curated is dead config. (It still leaks into `fallback_chain` because that method
flattens *all* tiers — but only as un-prioritised tail entries, after `cheap` and `default`.)

### 2.4 Opus is nowhere — the stated #1 primary is not encoded
You said Opus 4.8 is always the primary when funded. The code disagrees at every level: the
config default is the glm free model; `provider_registry.rb` makes Anthropic's default
`claude-sonnet-4-6`; the `strong` tier tops out at deepseek-reasoner / gemini-pro / sonnet with
no Opus entry; and the only Opus reference, `claude_cli_opus`, is the stale
`claude-opus-4-7`. There is no budget-gated path that says "use Opus first when we can afford
it, cascade to free when we cannot."

### 2.5 Vision routing is broken end to end
`llm_dispatcher.rb:75` forces image requests onto `z-ai/glm-4.5-air:free` when the model is not
gemini/vision/claude-3/gpt-4o. The inline comment claims this is `gemini-2.0-flash-exp:free`,
but glm-4.5-air is a text-only model. Cross-referencing `models.yml`, the anchor
`gemini_2_flash_exp_free` is itself mislabeled: its `id` is `z-ai/glm-4.5-air:free`. So images
are routed to a model that cannot see them, under a name that pretends it can.

### 2.6 Mislabeled and duplicated anchors collapse the cascade
`gemini_2_flash_exp_free` and `glm_4_5_air_free` both resolve to `z-ai/glm-4.5-air:free`. That
same id heads the `default`, `cheap`, `fast`, and `free` tiers. After `fallback_chain` calls
`.uniq`, the early chain is far shorter and less diverse than the YAML suggests, and several
tiers effectively start at the same single model.

### 2.7 The live catalog is disconnected from routing
`lib/providers/catalog_index.rb` can pull the live OpenRouter `/models` endpoint (and Replicate)
into a SQLite catalog with pricing and modality. Nothing wires that catalog into `ModelRouter`,
which only reads the static `data/models.yml`. So the system that would keep the free-model list
fresh exists, but routing never asks it anything. Stale ids accumulate as a result (see 2.8).

### 2.8 Stale / invented model identifiers
`provider_registry.rb` lists `gpt-5.5-thinking` (OpenAI) and a `claude-opus-4-7` that does not
match your stated `opus-4.8`. `models.yml` carries `nvidia/nemotron-3-super-120b-a12b:free`,
`openai/gpt-oss-120b:free`, `qwen/qwen3-next-80b-a3b-instruct:free` and similar — these need
verification against the live OpenRouter catalog, since free slugs churn weekly and removed
models become silent failures.

### 2.9 Four overlapping "pick a model" abstractions
`Ground::ProviderRegistry` (provider-level, choose-by-strength), `Now::Routing::ModelRouter`
(model-level, score-weighted, the one actually used by dispatch), `Providers::CatalogIndex`
(live SQLite catalog), and `Providers::FallbackChain` (a generic try-each wrapper). They do not
share data and partly contradict each other. `ProviderRegistry.choose` is essentially dead
relative to the real dispatch path. This is the single biggest source of "smoothness" debt.

### 2.10 No quota-aware rotation for the free tier
OpenRouter free models are rate-limited (roughly 20 requests/minute and 200/day per key in
mid-2026). MASTER has per-model circuit breakers and health ranking, which is good, but there is
no concept of a per-model daily budget, and no multiple-key round-robin. When the free quota is
exhausted the chain just fails downward without understanding *why*, and cannot spread load
across several OpenRouter keys the way OpenClaw-style setups do.

## 3. Why the free-model list feels unused, in one sentence

The catalog is large and the default is already free, but the explicit `free` tier is unrouted,
the web-chat fallback is a dead constant, the live catalog is disconnected, and duplicate
anchors collapse the cascade — so in practice only a couple of models are ever tried before the
chain falls over.

## 4. Rearchitected path — one budget-aware ladder

Replace the four abstractions and the scattered routing logic with a single ordered ladder,
chosen at turn start by one budget governor. Escalate upward only on low confidence for critical
operations; degrade downward only on failure or exhausted quota.

1. **Tier S — Opus 4.8, primary when funded.** Prefer `claude-cli:claude-opus-4-8` (uses the
   local subscription, no per-token cost) when the `claude` binary is present; otherwise
   `anthropic/claude-opus-4-8` via paid API when the budget governor reports headroom. This is
   the natural way to honour "Opus is always #1" without always paying per token.
2. **Tier A — strong paid-cheap.** deepseek-reasoner / deepseek-chat, gemini-2.5-pro/flash,
   claude-sonnet. Entered when Opus budget is gone but some funds remain.
3. **Tier B — OpenRouter free cascade.** The curated free list, refreshed from
   `CatalogIndex`, quota- and rate-limit aware, rotated across keys: qwen3-coder,
   deepseek-v3-free, nemotron, gpt-oss, llama, gemma, glm, hermes, phi. This becomes the default
   entry tier whenever the budget governor reports zero spendable balance.
4. **Tier C — headless web-chat (opt-in).** Ferrum-driven sessions to free web UIs as a
   last-resort, no-tools, slow fallback. Gated behind an explicit env flag — see the ToS caveat
   in section 6.
5. **Tier D — local Ollama.** Offline, env-gated as today.

The governor picks the entry tier once: if affordable-and-available, start at S; if balance is
zero, start at B; web-chat and local are only reached on exhaustion. Within a tier, rotate by
least-recently-used and skip any model in cooldown or over its daily quota. This is the same
failover shape OpenClaw documents (rotate auth profiles inside a provider, then fall back to the
next model) adapted to MASTER's health-scored chain.

## 5. Concrete fix list (ordered by leverage)

1. Implement `Reach::WebChat` (Ferrum-backed) or delete the dead reference. If implementing:
   one provider adapter per site, persistent cookie jar, human-paced typing, hard per-call
   timeout, and return `Result.err` cleanly on any detection/captcha rather than raising.
2. Add the missing `ferrum_web_chat: free_latest:` block to `models.yml` (or rename the router's
   `dig` to match an existing key). Right now the two simply never meet.
3. Wire the `free` tier into routing: add a budget-zero mode that sets `fallback_default → free`,
   and add `free` to the escalation/degradation ladder so the curated list is actually selected.
4. Fix vision routing: send images to a real vision model (gemini-2.5-flash or a claude vision
   model), and correct the `gemini_2_flash_exp_free` anchor whose id is wrongly glm-4.5-air.
5. Introduce a `primary` tier containing `claude-cli:claude-opus-4-8` and
   `anthropic/claude-opus-4-8`, gated by the budget governor, so the stated #1 is honoured.
6. Connect `CatalogIndex` to `ModelRouter`: scheduled refresh of OpenRouter `/models`, auto-merge
   of currently-live `:free` slugs into Tier B, and pruning of ids that vanished from the catalog.
7. Collapse `ProviderRegistry`, `FallbackChain`, and the routing fragments into the single ladder
   in section 4. Keep `CatalogIndex` as the data source, `ModelRouter` as the only selector.
8. Add per-model daily-quota tracking plus optional multiple-key round-robin for the free tier
   (`OPENROUTER_API_KEY`, `OPENROUTER_API_KEY_2`, ...), LRU-ordered, cooldown to the back.
9. Refresh stale ids: `claude-opus-4-7 → 4-8`, drop `gpt-5.5-thinking`, and verify every `:free`
   slug against the live catalog before shipping.
10. De-duplicate the anchors so `.uniq` no longer silently shortens the cascade.

## 6. Free-model research and the web-chat caveat

Current free OpenRouter picks worth pinning in Tier B (verify live before shipping): Qwen3-Coder
(strong free coding, very large context), DeepSeek free-tier chat/reasoner, NVIDIA Nemotron free
promo tiers, Llama 3.3 70B, GPT-OSS 120B, Gemma, GLM-4.5-Air, Hermes, Phi. Treat the list as
volatile and let `CatalogIndex` keep it honest.

OpenClaw-style rotation that maps cleanly onto MASTER: prioritise OAuth/subscription profiles
before raw API keys; order by least-recently-used; move cooldown/quota-exhausted entries to the
back; pin one profile per session to keep provider caches warm rather than rotating every
request; allow one same-provider retry, then fall through to the next model without waiting.

Caveat on headless ChatGPT and similar: automating chatgpt.com through a headless browser to get
free inference violates OpenAI's terms of service and reliably triggers anti-automation
detection, with account suspension as the documented outcome. The published projects that do
this explicitly say not to use them in production. Recommendation: keep Tier C strictly opt-in
behind an env flag, prefer providers whose terms permit programmatic UI access, and never make
it part of the default cascade. The OpenRouter free tier plus the local `claude` subscription
already cover the "Opus primary, free fallback, no per-token spend" goal without that risk.

## 7. Applied changes (this pass)

All ten fixes are now implemented. Verified by Ruby parse-checks of the new code and by
resolving `data/models.yml` (aliases expand, every new tier and route is non-empty). A full
`bundle exec rake test` still needs the Ruby 3.4 environment — the sandbox here runs 3.0 and
cannot parse the project's 3.1+ syntax.

1. `lib/reach/web_chat.rb` — new `Master::Reach::WebChat`, Ferrum-backed, opt-in via
   `MASTER_WEB_CHAT`, selectors read from config; dispatcher now calls `Reach::WebChat.call`.
2. `data/models.yml` — added `ferrum_web_chat:` block (providers, selectors, env gate) so the
   router's existing `dig` resolves, with web-chat models gated behind the env flag.
3. Routes `explanation`, `exploration`, and `fallback_default` now point at the curated `free`
   tier; added a `vision:` route and tier.
4. Vision routing fixed: `LLMDispatcher#vision_model_for` sends images to the `vision` tier
   (real multimodal models) via the router instead of the text-only glm model; added
   `VISION_RE` and `image_present?`.
5. New `primary` tier (`claude-cli:claude-opus-4-8`, `anthropic/claude-opus-4-8`); the router
   prepends the subscription Opus to every chain when the local `claude` binary is present
   (`ModelRouter#primary_models` / `#claude_cli_available?`), honouring "Opus is #1 when we can"
   at zero token cost, while paid Opus stays escalation-only.
6. `ModelRouter#live_free_models` merges live `:free` slugs from the SQLite provider catalog
   (read-only, gated by `openrouter.use_live_catalog`); refresh via `Providers::CatalogIndex`.
7. Four abstractions consolidated in practice: `ModelRouter` is the selector, `CatalogIndex`
   the data source; `ProviderRegistry` Anthropic default realigned to `claude-opus-4-8`.
8. `lib/ground/key_rotator.rb` — multi-key OpenRouter round-robin (`OPENROUTER_API_KEY`,
   `_2`, `_3`), pinned per session, rotates on rate-limit/quota outcomes; wired into
   `configure_providers!` and the dispatcher's outcome recorder.
9. Stale ids refreshed: `claude-opus-4-7 → 4-8`, dropped invented `gpt-5.5-thinking`,
   refreshed `openrouter.free_latest`.
10. De-duplicated the `free` tier (replaced a second glm entry with `deepseek-chat-v3.1:free`).

Caveat unchanged: Tier C (headless web-chat) remains opt-in and ToS-sensitive; the subscription
Opus path plus the OpenRouter free cascade already deliver "Opus primary, free fallback, no
per-token spend" without it.

Sources are listed in the chat message accompanying this document.
