# Claude Code Handoff: Micro-Refinement Opportunities

## Goal

Collect small, low-blast-radius improvements discovered during the Face3D, TTS, cluster-mining, attention-context, mobile-web, and prompt-archaeology work.

These are intentionally micro-refinements: each should be shippable as a small PR with clear acceptance criteria.

## Principles

- Prefer small reversible changes.
- Do not rewrite core systems unless the change is scoped and tested.
- Keep token efficiency: avoid noisy output, verbose logs, or always-on UI.
- Preserve the retro Face3D/particle aesthetic.
- Do not cache private chat logs by default.
- Do not copy leaked prompt text into runtime prompts.

## Opportunities

### 1. Normalize newline endings in touched Ruby files

Some generated diffs show `No newline at end of file` after edits.

Tasks:

- Audit recently touched Ruby/YAML/JS files for missing trailing newlines.
- Add newline if missing.
- Do not reformat unrelated content.

Acceptance:

- No functional changes.
- Minimal diff.

### 2. Add YAML schema smoke tests

Recent work added several YAML registries:

- `MASTER/data/attention_context.yml`
- `MASTER/data/mobile_web_opportunities.yml`
- `MASTER/data/prompt_archaeology_patterns.yml`
- `MASTER/data/visual_clusters.yml`
- `MASTER/data/repo_topic_clusters.yml`

Tasks:

- Add tests that each file parses.
- Assert expected top-level keys exist.
- Assert required arrays are non-empty.

Acceptance:

- Invalid YAML fails fast in tests.
- No runtime behavior changes.

### 3. Add cluster registry consistency checks

Tasks:

- Detect duplicate cluster IDs within each YAML.
- Detect missing `id`, `name`, `status`/`confidence` where expected.
- Detect `next_actions` entries that are empty strings.

Acceptance:

- Tests only; no behavior changes unless a validation helper is trivial.

### 4. Add safer Face3D preview failure reporting

Current preview loading is gated by `?face3d=1` through `visual_bridge.js`.

Tasks:

- Ensure dynamic import errors emit a visible but compact `master:visual` event.
- Avoid console spam.
- Add one small fallback message or debug-only flag if preview fails.

Acceptance:

- `?face3d=1` failure does not break normal chat UI.
- Normal mode unchanged.

### 5. Add reduced-motion check to Face3D preview

Tasks:

- Check `prefers-reduced-motion` in `face3d_preview.js`.
- Reduce mask switching, jaw animation, and high-frequency motion when enabled.

Acceptance:

- Reduced-motion users get calmer preview.
- Default animation unchanged.

### 6. Add battery/thermal comments to QualityController

`QualityController` already adapts some settings. Add clearer extension points.

Tasks:

- Document where battery API / frame-time governor should plug in.
- Keep implementation minimal unless already straightforward.

Acceptance:

- No behavior regression.
- Future Claude Code task is easier.

### 7. Add TTS MIME regression test at controller layer

Speech tests cover `synthesize_audio`; controller should also be protected.

Tasks:

- Stub `Master::Voice::Speech.synthesize_audio` in controller test if test harness exists.
- Assert `/chat/tts` uses `audio/wav` when returned audio metadata says WAV.
- Assert MP3 still uses `audio/mpeg`.

Acceptance:

- Controller MIME behavior cannot regress to always-`audio/mpeg`.

### 8. Add prompt archaeology guardrail test

Tasks:

- Add a test/helper that ensures runtime prompt assembly does not read raw files from `github_repos/system_prompts_leaks` or `MASTER/knowledge/system_prompts` directly.
- Allow references to `prompt_archaeology_patterns.yml` only.

Acceptance:

- Derived patterns are allowed.
- Raw leaked prompt text is not imported into runtime prompt strings.

### 9. Add docs index for Claude Code handoffs

Tasks:

- Create `MASTER/docs/claude_code/README.md`.
- Link existing handoff docs:
  - `001_attention_runtime.md`
  - `002_mobile_web_runtime.md`
  - `003_multi_llm_orchestration.md`
  - `004_ruby_codification_backlog.md`
  - `005_micro_refinement_opportunities.md`

Acceptance:

- Claude Code can find the handoff queue quickly.

### 10. Add PR label suggestions to handoff docs

Tasks:

- Add suggested labels at the top of each handoff doc, e.g. `claude-code`, `handoff`, `runtime`, `mobile`, `orchestration`, `tests`.

Acceptance:

- Docs-only change.

### 11. Clarify privacy boundary in mobile web docs

Tasks:

- Emphasize that service workers must not cache private chat logs by default.
- Add explicit examples of safe static assets versus unsafe private payloads.

Acceptance:

- Mobile handoff is harder to misimplement.

### 12. Add event naming convention doc

Recent systems emit events:

- `master:visual`
- `master:clusters`
- `master:codebase`
- `master:rule_event`
- future `attention:context`

Tasks:

- Add a compact event naming convention doc.
- Define when to use `master:*` versus subsystem-specific events.

Acceptance:

- New JS/Ruby features emit consistent events.

## Suggested batching

Batch 1: pure safety/tests/docs

- YAML schema smoke tests
- cluster ID consistency checks
- Claude Code README
- privacy boundary clarification
- event naming doc

Batch 2: tiny runtime refinements

- reduced-motion Face3D preview
- preview failure reporting
- TTS controller MIME test
- trailing newline cleanup

Batch 3: guardrails

- prompt archaeology raw-source guardrail test
- labels in handoff docs

## Non-goals

- Do not implement the full Ruby codification backlog here.
- Do not implement WebGPU here.
- Do not implement browser-local LLM inference here.
- Do not replace the current live face renderer.
- Do not merge all micro-refinements into one giant code PR unless they remain tests/docs only.

## Suggested PR title after implementation

`Tighten MASTER registry tests and micro-guardrails`
