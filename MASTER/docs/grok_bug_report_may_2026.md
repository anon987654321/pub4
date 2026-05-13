# Grok Bug Report — May 2026

Source: live GitHub review, May 2026.

## Bugs

### bundle proxy 403

`bundle install` can fail when Rubygems traffic routes through a blocking proxy.

Remediation:

- keep README debug note
- add boot diagnostic
- distinguish network/proxy failure from application boot failure
- avoid treating dependency install failure as MASTER runtime failure

### hard 30s Council/Lint timeout

The current Council/Lint parallel timeout can abort useful work mid-run.

Remediation:

- replace fixed wall-clock timeout with budget policy
- emit timeout warning event before abort
- degrade to partial council result if lint completes
- preserve partial findings in runtime events
- make timeout configurable by workflow risk

### ruby_llm streaming gap

`ruby_llm` blocks true streaming and progress callbacks in some paths.

Remediation:

- wrap provider calls behind runtime provider adapter
- emit provider progress events when chunks exist
- emit heartbeat/progress events during blocking calls
- avoid direct streaming assumptions in UI
- expose stream capability in provider registry

### missing `/auto` mode

CLI/web lacks a first-class `/auto` mode.

Remediation:

- add `/auto` as workflow policy, not magic mode
- require risk, reversibility, budget, and review constraints
- emit autonomy gate events
- block irreversible/high-complexity work without quorum

### Canvas/TTS not mobile PWA optimized

Canvas visualizer and TTS need mobile-first PWA support.

Remediation:

- add manifest
- add service worker
- cache offline shell and recent traces
- make canvas responsive
- use Turbo/Stimulus for live nodes, edges, and timeline
- add Web Speech API fallback
- keep native `/chat/tts` endpoint for generated speech

## Rails 8 mobile-first PWA enhancement plan

### PWA

- `manifest.json`
- service worker
- offline shell
- trace cache
- installable standalone mode
- reduced-motion support

### Canvas

- Turbo stream runtime events
- Stimulus controllers for nodes, edges, timeline, replay scrubber
- mobile layout with touch targets
- runtime events as source of truth

### TTS

- Web Speech API where available
- native voices selection
- `/chat/tts` endpoint fallback
- mobile audio unlock handling
- cache last synthesized response offline when permitted

### Mobile

- responsive layout
- no hover-only controls
- large touch targets
- offline trace cache
- low-JS fallback

## Governance impact

These bugs reinforce existing runtime rules:

- provider capability detection must be explicit
- UI must not assume streaming
- fixed timeouts should become budgets
- autonomy requires gates
- PWA is not cosmetic; it is runtime reachability
