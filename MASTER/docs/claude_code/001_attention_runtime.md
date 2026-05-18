# Claude Code Handoff: Attention Context Runtime

## Goal

Turn `MASTER/data/attention_context.yml` from a design registry into a small runtime feature that helps MASTER keep spatial task context during long, multi-step work.

The user explicitly approved compact cognitive breadcrumbs for complex work, similar to nav breadcrumbs. The implementation must preserve token efficiency: do not emit breadcrumbs on simple answers.

## Existing source files

Read first:

- `MASTER/data/attention_context.yml`
- `MASTER/lib/trace/session.rb`
- `MASTER/docs/cognitive_runtime.md`
- `MASTER/web/public/visual_bridge.js`
- `MASTER/web/public/cognition_ecology.js`
- `MASTER/web/public/face3d_engine.js`

## Implementation tasks

### 1. Add an AttentionContext value object

Create a small Ruby object, likely under one of:

- `MASTER/lib/attention/context.rb`
- `MASTER/lib/master/attention/context.rb`

It should support:

```ruby
Attention::Context.new(
  map: "repo-mining/mobile-web/browser-local-ai",
  zoom: "wide_to_deep",
  act: "scout",
  target: ["repos", "opportunity_clusters"],
  parent: ["repo_topic_clusters"]
)
```

Required behavior:

- validate `zoom` and `act` against `attention_context.yml`
- render compact string: `⟦map | zoom: zoom | act: act⟧`
- render YAML/Hash for traces and prompts
- keep defaults safe if a field is missing

### 2. Add prompt-builder integration

Find the current prompt/session assembly path and add attention context as metadata for long-running or agentic tasks.

Rules:

- Include attention context for multi-step, code mutation, repo mining, research, recovery, and verification tasks.
- Do not inject it into every trivial response.
- Do not let attention context overwrite identity, safety, or tool policy.

### 3. Add bus + trace integration

Emit a bus event when the attention context changes:

```ruby
container[:bus].publish("attention:context", context: context.to_h)
```

Also store it in session/trace records if a trace system is present.

### 4. Add browser visual bridge support

Update `web/public/visual_bridge.js` so `attention:context` events are normalized into `master:visual` with mode `attention`.

Suggested mapping:

- `zoom: deep` or `wide_to_deep` -> higher focus, lower entropy
- `act: repair` or `rollback` -> serpent/error topology
- `act: mine` or `scout` -> neural/topology mode
- `act: land` or `verify` -> codebase/topology mode

### 5. Add tests

Add tests for:

- valid context renders compact breadcrumb
- invalid zoom/act is rejected or normalized
- prompt builder includes context only when triggered
- bus event payload shape

## Acceptance criteria

- `MASTER/data/attention_context.yml` remains source of truth.
- There is a runtime object for attention context.
- Long-running tasks can include compact breadcrumbs in prompts/traces.
- Browser visual bridge can react to attention events.
- Simple responses remain silent/no-breadcrumb.
- Tests pass.

## Non-goals

- Do not add always-on verbose headers.
- Do not add a new LLM prompt blob.
- Do not change user-facing style globally.
- Do not mutate unrelated Face3D or TTS behavior.

## Suggested PR title after implementation

`Implement attention context runtime`
