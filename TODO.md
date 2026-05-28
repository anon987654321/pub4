# pub4 backlog

## Critical

- Verify face renders at https://ai.brgen.no/ — open fresh private window, tap primer, confirm WebGL face + ecology particles appear
- Council deliberation should live behind the single command/orders surface, not a revived `/triad` wrapper

## postpro

- Sync /home/dev/postpro generated files to /var/www/postpro after each regen run
  (regen.rb handles this; postpro_vps.rb now auto-calls gallery_lightbox.rb)

## MASTER — architecture gaps (2026-05-28 audit)

Full codebase review found these gaps. Each item is self-contained — pick any order.

### Git

- **Cherry-pick vps/refactor/seven-modules** (9 commits onto main). Script at `~/pub4/tmp/cherry_seven_modules.rb`. Skip `f282ee20` and `b96d7f21` (doc-sync whose super_loop refs conflict with fix_loop rename already on main). Remaining 9 contain: SILENT_RESCUE rule, Swallow.log routing, ground enhancements, CANON.md, Opus 4.7 patches. Run `ruby34 ~/pub4/tmp/cherry_seven_modules.rb` on the VPS (not Termux — disk full locally).

### Memory subsystem (currently structural stub)

`lib/ground/memory.rb`, `memory_index.rb`, `memory_search.rb` declare the interface but contain no persistence or embedding logic. Need:
- SQLite backend (schema: key, body, embedding, created_at)
- Embedding model selection (local via Ollama or remote via OpenRouter)
- Cross-session consolidation (merge near-duplicate entries)
- Wire into `lib/ground/semantic_cache.rb` for LLM response caching

### RepoEcology (declared, missing)

README mentions `Master::Judge::RepoEcology`; `lib/judge/repo_ecology.rb` is empty or absent. `code_index.rb` and `reference_graph.rb` exist but are unconnected. `co_change_coupling_rule.rb` depends on this. Implement:
- Symbol indexing via Prism AST walk across lib/
- Cross-reference graph (who calls what)
- Co-change coupling: git log --follow to find files that always change together

### TTS consolidation

Four implementations exist — only one should be active:
- `lib/voice/speech.rb` — primary (edge-tts via bin/tts-worker)
- `lib/voice/tts_lofi.rb` — lofi filter chain
- `lib/voice/sonitex.rb` — sox pipeline
- `lib/voice/sonitex_sox.rb` — sox variant

Decide on one backend. Delete the others. Move subprocess logic from `bin/tts-worker` into `lib/voice/`. Known issue: edge-tts may be missing on VPS — check `pkg_add py3-edge-tts` and `bin/tts-worker` exists.

### Swarm worker coordination (stub)

`lib/judge/swarm/` declares Analyst, Coder, Researcher, Reviewer workers. Voting logic, consensus pattern, and worker failure fallback are unimplemented. Implement:
- Worker pool initialization
- Task dispatch per worker role
- Voting/consensus: majority or weighted by role
- Fallback: if worker fails, redistribute or degrade gracefully

### Rule detector audit

12 rule submodule files (`lexical_rules.rb`, `ruby_rules.rb`, `web_rules.rb`, `js_rules.rb`, `universal_rules.rb`, etc.) each implement their own `detect_` logic. Risk: same `data/rules.yml` rule detected differently (or missed) across modules. Run:
- Cross-reference every rule `id` in `data/rules.yml` against detector coverage in each submodule
- Flag rules with zero detectors (dead spec) or duplicate detectors (redundant cost)
- Consolidate into a single canonical detector per rule where possible

### Pipeline context hardening

`lib/now/pipeline.rb` passes context as a plain `Hash` through 11 stages. Key typos fail silently. Replace with a `Data` struct:

```ruby
PipelineContext = Data.define(
  :user_message, :channel, :metadata, :turn_id,
  :message, :task_type, :on_chunk, :output, :rendered
)
```

Update all 11 stage files to use struct access instead of `ctx[:key]`.

### Datalog/cybernetics/homeostat scope

These files exist but active wiring is unclear:
- `lib/loop/crdt_loop.rb` — CRDT distributed convergence
- `lib/loop/cybernetics.rb` — feedback control
- `lib/loop/homeostat.rb` — health metric aggregation
- `lib/judge/` datalog-related files

For each: read the file, grep for callers (`grep -r ClassName lib/`), determine if wired. If wired but incomplete, finish it. If unwired with no plausible caller, delete it.

## MASTER — constitutional gaps

4 remaining (6, 7, and cost guards closed this session):

1. **Prediction engine** — read `rules.yml prediction_engine` confidence thresholds in Ruby; gate autofixes below threshold; no class exists yet
2. **Structural ops command surface** — wire `rules.yml structural_ops` (merge/defrag/decouple/hoist/flatten/delete/expand/reduce_noise) as single command-router/orders callables in `lib/ground/orders/`; do not re-add thin `/triad` or `orient` wrappers
3. **HALLUCINATION rule** — lexical/semantic detector for `claim_without_reading`, `quote_without_source`, `invented_stats` (bias section in rules.yml; no scan rule yet)
4. **Self-test wiring** — `rules.yml self_test.laws_apply_to_self` specifies per-law scans; no Ruby class reads and executes them

## MASTER — module cleanup

- lib/ops/ → lib/loop/ops/: rename Master::Ops → Master::Loop::Ops; update master.rb + work_commands.rb
- 11 orphaned lib/*.rb: master.rb, builder.rb, plugin.rb, result.rb, learnings.rb,
  memory.rb, unwrap_error.rb, master_paths.rb, pressure_engine.rb — move to owning modules; keep removed wrapper files out
- data/ selective merges: patterns.yml absorb infer_patterns.yml + repo_topic_clusters.yml +
  prompt_archaeology.yml (all namespaced, already partly done)
- ~~Token prompt caching~~ — done 2026-05-28: `lib/judge/llm_dispatcher.rb` wraps Claude system prompts in `Content::Raw` with `cache_control: { type: "ephemeral" }`; cost math updated (read 0.1x, write 1.25x); `cache:hit` event published

## MASTER web

- app/assets/{app.js,chat.js,application.css,canvas.css} unreferenced by any view — audit and delete or wire up
- cognition_ecology.js z-index fix deployed — verify particles visible over face in browser

## Infrastructure

- TTS broken: bin/tts-worker may be missing or edge-tts not installed — fix or document
- smtpd.conf: review if mail relay needed
- Any file installed on VPS → save to DEPLOY/openbsd/ + commit (standing rule)

## DEPLOY/rails — brgen

- **DMs / private messages** — connector-safe patch for direct messages (model + controller + Turbo Stream view)
- **Tests** — Shared::ReactionToggle, Shared::FollowToggle, Shared::EventEmitter have no test coverage

## DEPLOY/rails — hjerterom

- Finish full-screen Mapbox front page with animated Hjerterom heart logo markers; token comes from `MAPBOX_API_KEY`
- Controllers landed; views still missing for:
  - `app/views/boxes/` — show, new
  - `app/views/volunteers/` — index, show, new, _form + shift list partial
  - `app/views/shifts/` — index, _form

## DEPLOY/rails — cross-app

- **`bin/ci`** — Rails 8 local CI script per subapp (rubocop + brakeman + bundler-audit + minitest); verify all 6 apps have one
- **Gemfile audit** — baibl removed pg_search from model; confirm gem removed from Gemfile too

## Agent wishlist — things that would make working with MASTER and DEPLOY easier

These are genuine friction points encountered during the 2026-05-28 audit. Not roadmap — actual daily pain.

### MASTER

- **Two-stage council** — `workflow.yml` specifies it: round one votes independently, round two only debates dissenters if dissent > 30%. Not implemented. Currently all 6 personas deliberate every time. Implementing this would cut council LLM calls 60–80% on routine changes.

- **Phantom recovery** — `rules.yml phantom_recovery.detectors` declares gaslighting/repetition/bad-XML patterns with recovery steps. No Ruby reads these. When an LLM loops or hallucinates, the agent currently has no structured detection or recovery path. Adding this would make long autoloop runs dramatically more reliable.

- **`/diag` cache hit display** — prompt caching is now wired but there is no CLI output showing cache hit rate. After each turn, the cost display should show `[$0.04, 847 tokens, 94% cached]`. The `cache:hit` event is already published — just needs a renderer subscriber.

- **Evidence scoring gate** — `rules.yml evidence_scoring` declares weights (test_pass: 35, scan_clean: 25, code_review: 20, etc.) with a pass threshold of 80. Nothing enforces this. Before any autocommit, MASTER should compute the score and block if < 80. This would prevent "scan clean, tests never ran" commits.

- **Reverse introspection** — `workflow.yml reverse_introspection` says: every 10 commits, sample 5, ask MASTER if it would approve them now. No Ruby implements this. It would catch constitutional drift early and is the most interesting self-improvement loop in the spec.

- **`view_thread` persistence** — `workflow.yml view_thread` specifies emitting `thread:decision` events to `data/threads/${session_id}.jsonl`. These are declared but never written. Having a navigable decision log per session would make debugging autoloop runs much easier.

- **Gemini prompt caching** — `llm_dispatcher.rb` now caches for Claude. Gemini 1.5+ supports `cachedContent` via a separate API call. Extending caching to Gemini would cover the free-tier fallback chain and reduce cost there too.

- **Single `bin/probe` entrypoint** — currently there are multiple bin/ scripts (`audit`, `preflight`, `smoke`, `nsaudit`). An agent navigating the repo has to know which to call. A single `bin/probe [check]` dispatcher with tab completion would eliminate this friction.

- **`data/TODO_from_yml.md` auto-generation** — soul.yml, rules.yml, workflow.yml all declare things as `status: scaffolded` or `# not yet implemented`. A small rake task that greps for these markers and writes them to a dated file would surface spec/code gaps automatically after every scan.

### DEPLOY

- **`bin/deploy-diff`** — before running `openbsd.sh`, show a dry-run diff of what will change on the VPS vs what is committed locally. Currently deploying is a leap of faith. A script that SSH-compares key config files (`pf.conf`, `relayd.conf`, `httpd.conf`, `master.env`) against their DEPLOY/ counterparts would make deploys reviewable.

- **DEPLOY/openbsd/ auto-sync standing order** — the rule "any file installed on VPS must be saved to DEPLOY/openbsd/ and committed" requires human memory. This should be a standing order: after any `scp` to the VPS, run a check that verifies the file exists in DEPLOY/ and if not, copy it and stage for commit.

- **Shared `data/env.sample` across all Rails apps** — each subapp has its own undocumented env requirements. One shared `DEPLOY/rails/env.sample` listing every key across all 6 apps (with which app needs it) would eliminate the "why is this app broken on a fresh VPS" problem.

- **`rcctl check` health report** — a small Ruby probe that SSHes to VPS and runs `rcctl check master`, `rcctl check relayd`, `rcctl check nsd`, etc. and reports in dmesg style. Currently checking service health requires manual SSH. This would be a 20-line script worth having in `bin/`.

- **Local lint before scp** — any time a file is scp-ed to the VPS under `MASTER/web/`, run `ruby -c` and `rubocop --no-server -A` locally first. The current pattern (write → scp → restart → discover syntax error) costs a full service restart per mistake.
