# Free compute in MASTER — implementation status

Updated 2026-10-28 against the live routing code. This document separates
implemented paths from proposals: a configured provider is not proof that it is
reachable, free at the point of use, or unlimited.

## The practical answer

There is no unlimited free inference switch. Reliable free capacity comes from
independent, provider-permitted free tiers plus transparent quota accounting,
fallback, and locally owned compute. Limits, latency, privacy terms, and
availability still apply.

## Already implemented in MASTER

- **OpenRouter free catalog.** `data/models.yml` enables live `:free` model
  discovery through the SQLite provider catalog and configures a daily
  per-model guard. The router's key rotator supports the explicitly configured
  OpenRouter key variables and rotates after rate-limit/quota outcomes.
- **Hosted OpenAI-compatible providers.** `ModelRouter::HostedEndpoints`
  discovers models from the `openai_compatible` section. The current config
  includes LLM7 (with a keyless catalogue filter), Groq, Cerebras, and NVIDIA
  NIM. Groq, Cerebras, and NVIDIA only become available when the operator
  configures the relevant API key; quota and availability depend on each
  provider's current terms and account.
- **A user-owned OpenAI-compatible gateway.** Setting
  `MASTER_LLM_GATEWAY_URL` opts a local gateway into the same model discovery,
  health, and fallback route. Remote plaintext HTTP is refused; loopback HTTP
  is accepted.
- **Browser chat.** Existing `web-chat:` lanes are an explicitly gated,
  best-effort browser fallback. They are fragile, may have provider-specific
  terms, and are not treated as an API entitlement.
- **Local inference.** The configured Ollama lane is restricted to the
  explicitly allowlisted local Gemma model. This uses the operator's hardware
  and has no API token charge, but is bounded by available RAM, CPU/GPU,
  throughput, and power.
- **Cooldown and health.** The existing lane quota, model skip, provider health,
  and fallback components record failures and stop repeatedly asking a lane
  that just refused or exhausted its quota. These are finite safeguards, not a
  promise that every fallback is always online.

## Quota accounting contract

`openrouter.daily_quota_per_model` is configured as **50** in
`data/models.yml`. The executable fallback in `Io::ModelQuota` now uses the
same value when that setting is absent or invalid, rather than silently falling
back to 200. The configuration remains authoritative when it contains a
positive override. Regression tests cover both the conservative fallback and
the configured override.

The local counter is deliberately conservative: it does not multiply its
per-model allowance by the number of configured keys. A provider may impose
shared limits at account, organization, IP, model, or endpoint level; rotating
credentials does not erase those boundaries. Provider-issued 429 responses,
reset headers, and account policy remain authoritative.

## Task-aware selection versus failover

MASTER already has a task-selection layer in addition to its resilience chain:

- `ModelRouter::IntentClassification` classifies natural-language work into
  chitchat, code generation, refactoring, architecture, review, explanation,
  or exploration using deterministic patterns.
- `Review::Agent::ModelSelector` uses that classification when no explicit
  task type was supplied, then asks the existing router for the matching chain.
- `data/models.yml#routes` chooses the tier for each task. The existing
  `operation_constraints` declare hard quality floors for operations such as
  file writes, sweeps, architecture, and destructive work.
- `ComputePool` ranks eligible models using configured quality, speed, cost,
  context window, tool support, and measured success/latency/capability signals.
  Its `task_strengths` hook existed but had no declarative entries; the
  configuration now activates modest, explainable capability nudges for common
  task types. The preference is bounded to 4% per matching capability and at
  most three matches; it does not override availability, health, hard quality
  floors, quotas, or the fallback order.
- If the first model fails, the established fallback and cooldown machinery
  remains responsible for retrying another eligible lane. Selection and
  resilience are complementary layers, not competing routers.

This is deterministic task-aware routing, not an LLM judge. A separate model
judge is deliberately not inserted before every request: it would add another
provider call, latency, and an additional failure mode, and has not yet shown
that its expected savings outweigh those costs. If a later benchmark justifies
a judge, it should be opt-in and measured against this deterministic baseline.

## Local provider concurrency

A small in-process gate can enforce an operator-declared simultaneous-request
limit for an explicitly configured hosted endpoint. It shares a bucket across
models when those models consume the same provider/account concurrency budget,
rejects conflicting limits for the same bucket, and returns a typed saturation
failure after a bounded wait so existing fallback can continue. This is a
local scheduling limit, not a claim about the provider's token quota or remote
rate-limit policy. The current LLM7 keyless entry is conservatively limited to
one in-flight request; remote 429 responses and provider terms remain
authoritative. Additional endpoints should receive such a cap only when a
documented or deliberately conservative operator limit is available.

## How the newer suggestions fit

| Proposal | Status in MASTER | Decision |
| --- | --- | --- |
| Pool free models from multiple providers | Existing provider/model fallback already does this | Prefer independent supported providers and measured availability over a second router |
| OpenRouter multi-key rotation | Implemented for configured OpenRouter keys | Keep quota accounting conservative; do not infer multiplied capacity |
| Generic local key-pool proxy | Can be reached through `MASTER_LLM_GATEWAY_URL` | Optional and operator-owned; inspect its credential, quota, and logging behavior |
| Puter.js browser bridge | Not implemented | Verify the supported interface, account terms, and user-pays behavior before adding an adapter |
| Fingerprint-rotated browser sessions | Not implemented | Do not impersonate browser identities or add jitter to defeat rate limits |
| Private GLM/mobile API proxies and token harvesting | Not implemented | Do not capture or replay browser/app credentials or depend on undocumented private APIs |
| GitHub Actions as an inference server | Not implemented | Actions minutes and platform policies are finite. Do not turn public CI into an unbounded prompt-serving endpoint; use runners for bounded repository CI/tasks instead |
| Prompt-injection-driven CI execution | Out of scope | Never pass untrusted model output into shell commands or broaden workflow permissions to obtain compute |

The seven-layer sketch is a useful way to classify possible resources, but it
is not seven independent entitlements. A local proxy may funnel several keys
into one shared quota, browser sessions may share IP/account limits, and public
CI is subject to usage rules and concurrency limits. Adding layers without
tracking the actual quota boundary would make the pool look larger without
making it more reliable.

## Future admission gates

A new provider adapter belongs in MASTER only after these questions have
deterministic answers: Is the endpoint supported and documented? Which exact
quota boundary applies? How are 429, 401/403, retry-after, and reset windows
classified? What happens when local quota state is unreadable? Does the adapter
log prompts or credentials? Is it opt-in when the provider's terms require it?
Is it covered by routing, cooldown, privacy, and failure tests?

A provider catalog entry alone is not a successful runtime probe. Any change to
the pool should preserve the existing route policy, budget limits, operation
quality floors, and evidence requirements.
