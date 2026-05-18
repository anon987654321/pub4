# Claude Code Handoff: Ruby Codification Backlog

## Goal

Turn the YAML/config/research layers added in recent PRs into executable Ruby runtime policy, routing, evidence, and audit objects.

Principle:

```text
YAML = knowledge layer
Ruby = execution/policy layer
JS = embodiment/visual layer
```

## Source files to read first

- `MASTER/data/attention_context.yml`
- `MASTER/data/prompt_archaeology_patterns.yml`
- `MASTER/data/mobile_web_opportunities.yml`
- `MASTER/data/visual_clusters.yml`
- `MASTER/data/repo_topic_clusters.yml`
- `MASTER/data/models.yml`
- `MASTER/data/council.yml`
- `MASTER/docs/provider_economy.md`
- `MASTER/docs/cognitive_runtime.md`

## Priority implementation order

### 1. `Master::Attention::Context`

Codify `attention_context.yml` into a Ruby value object.

Suggested files:

- `MASTER/lib/master/attention/context.rb`
- `MASTER/lib/master/attention/registry.rb`

Required behavior:

- validate `map`, `zoom`, `act`, `target`, `parent`
- render compact breadcrumb: `⟦map | zoom: zoom | act: act⟧`
- render Hash/YAML for traces and prompt metadata
- emit/consume bus event payloads
- stay silent for trivial responses

### 2. `Master::Policy::Orchestration`

Codify `prompt_archaeology_patterns.yml` into a runtime orchestration policy.

Suggested files:

- `MASTER/lib/master/policy/orchestration.rb`
- `MASTER/lib/master/policy/risk_tier.rb`
- `MASTER/lib/master/policy/prompt_archaeology.rb`

Required behavior:

- expose orchestration stages
- expose risk tiers
- map task risk to model tier and council requirements
- enforce safe prompt archaeology rule: never copy leaked prompt text into runtime prompts

### 3. `Master::Routing::RiskClassifier`

Classify task risk before model selection.

Example behavior:

```ruby
RiskClassifier.call(intent: :repo_mutation, touches: ["lib/voice/speech.rb"])
# => :high
```

Risk levels:

- `low`: classification, summarization, cluster labeling, UI copy
- `medium`: docs, config, preview-gated browser modules
- `high`: file mutation, auth, production runtime, tool execution
- `critical`: destructive commands, secret handling, public deployment, permission changes

### 4. `Master::Council::Selector`

Select relevant council roles instead of invoking the whole council every time.

Examples:

```ruby
Council::Selector.for(task: :mobile_ui)
# => [:user_advocate, :accessibility, :web_designer, :performance]

Council::Selector.for(task: :auth_mutation)
# => [:security, :reliability, :maintainer]
```

Rules:

- Security, Reliability, Maintainer remain veto-capable.
- UI/mobile tasks include User Advocate, Accessibility, Web Designer, Performance.
- Architecture/migration tasks include Architect, Maintainer, Reliability.
- Sonic/visual rhythm tasks may include Music/Hip-Hop Producer personas.

### 5. `Master::Cluster::Registry`

Load all cluster YAMLs into one queryable registry.

Inputs:

- `visual_clusters.yml`
- `repo_topic_clusters.yml`
- `mobile_web_opportunities.yml`
- `prompt_archaeology_patterns.yml`

Example API:

```ruby
Cluster::Registry.find(:mobile_web_opportunities)
Cluster::Registry.related_to("Face3D")
Cluster::Registry.next_actions_for(:browser_local_ai)
```

### 6. `Master::Evidence::Graph`

Create evidence edges from cluster registries.

Example model:

```text
source_file -> supports -> cluster
repo_target -> inspires -> opportunity
paper_id -> informs -> implementation
```

Suggested files:

- `MASTER/lib/master/evidence/graph.rb`
- `MASTER/lib/master/evidence/edge.rb`
- `MASTER/lib/master/evidence/source.rb`

### 7. `Master::ClaudeCode::Handoff`

Generate Claude Code handoff docs/PR bodies from cluster next-actions.

Example API:

```ruby
ClaudeCode::Handoff.generate(
  cluster: :webgpu_face_runtime,
  mode: :implementation
)
```

Required behavior:

- include source files
- include acceptance criteria
- include non-goals
- include suggested PR title
- avoid vague instructions

### 8. `Master::MobileWeb::Audit`

Codify mobile/PWA audit checks.

Example API:

```ruby
MobileWeb::Audit.call(root: "MASTER/web/public")
```

Checks:

- manifest exists and is valid
- service worker exists or is intentionally absent
- icons exist
- offline shell policy is safe
- no private chat caching by default
- viewport/mobile safe area
- reduced motion support
- Face3D preview stays gated

### 9. `Master::Output::Contract`

Codify internal output expectations by `act` and risk.

Example API:

```ruby
Output::Contract.for(act: :verify, risk: :high)
# => requires observed/inferred/unknown/rollback/verification internally
```

User-facing output should remain concise unless details are needed.

### 10. `Master::Research::Radar`

Codify GitHub/arXiv/ar5iv watchlist scanning from topic clusters.

Example API:

```ruby
Research::Radar.scan(:webgpu_browser_runtime)
Research::Radar.scan(:openclaw_like_personal_agents)
Research::Radar.scan(:mobile_web_opportunities)
```

## Acceptance criteria

- At least the first four runtime objects are implemented or scaffolded with tests:
  - `Attention::Context`
  - `Policy::Orchestration`
  - `Routing::RiskClassifier`
  - `Council::Selector`
- YAML remains source of truth.
- Runtime code validates config values instead of trusting raw strings.
- No leaked prompt text is copied into runtime prompts.
- Model routing honors risk tiers.
- Council selection is targeted, not always-on spam.
- Tests cover happy paths, invalid config, and critical-risk escalation.

## Non-goals

- Do not rewrite the whole prompt builder in one pass.
- Do not implement WebGPU/browser-local inference here.
- Do not cache private chat logs.
- Do not replace `face.js`.
- Do not make breadcrumbs always visible.

## Suggested PR title after implementation

`Codify MASTER policy registries into Ruby runtime objects`
