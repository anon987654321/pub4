# pub4 backlog

## Critical

- Verify face renders at https://ai.brgen.no/ — open fresh private window, tap primer, confirm WebGL face + ecology particles appear
- /triad 3rd step is a buggy on/off toggle, not deliberation — fix council turn to emit actual multi-persona verdict

## postpro

- Sync /home/dev/postpro generated files to /var/www/postpro after each regen run
  (regen.rb handles this; postpro_vps.rb now auto-calls gallery_lightbox.rb)

## MASTER — constitutional gaps

4 remaining (6, 7, and cost guards closed this session):

1. **Prediction engine** — read `rules.yml prediction_engine` confidence thresholds in Ruby; gate autofixes below threshold; no class exists yet
2. **Structural ops CLI** — wire `rules.yml structural_ops` (merge/defrag/decouple/hoist/flatten/delete/expand/reduce_noise) as `/orders` callables in `lib/ground/orders/`
3. **HALLUCINATION rule** — lexical/semantic detector for `claim_without_reading`, `quote_without_source`, `invented_stats` (bias section in rules.yml; no scan rule yet)
4. **Self-test wiring** — `rules.yml self_test.laws_apply_to_self` specifies per-law scans; no Ruby class reads and executes them

## MASTER — module cleanup

- lib/ops/ → lib/loop/ops/: rename Master::Ops → Master::Loop::Ops; update master.rb + work_commands.rb
- 11 orphaned lib/*.rb: master.rb, builder.rb, plugin.rb, orient.rb, result.rb, learnings.rb,
  memory.rb, unwrap_error.rb, master_paths.rb, pressure_engine.rb — move to owning modules
- data/ selective merges: patterns.yml absorb infer_patterns.yml + repo_topic_clusters.yml +
  prompt_archaeology.yml (all namespaced, already partly done)
- **Token prompt caching** — add `cache_control` breakpoint to personality system prompt; cuts per-turn cost ~$0.73 → ~$0.07

## MASTER — features

- `master orient` CLI subcommand — currently slash-only (/orient); expose as `bin/cli orient`

## MASTER web

- face.js cleanup: strip "use strict", magic numbers (0.055, 0.025, 4.6), unused const dt,
  redundant scene.add(vertPoints)
- app/assets/{app.js,chat.js,application.css,canvas.css} unreferenced by any view — audit and delete or wire up
- cognition_ecology.js z-index fix deployed — verify particles visible over face in browser

## Infrastructure

- TTS broken: bin/tts-worker may be missing or edge-tts not installed — fix or document
- smtpd.conf: review if mail relay needed
- Any file installed on VPS → save to DEPLOY/openbsd/ + commit (standing rule)

## DEPLOY/rails — brgen

- **Notification index** — add "Mark all read" button (PATCH /notifications/read_all) + unread count badge to `app/views/notifications/index.html.erb`
- **DMs / private messages** — connector-safe patch for direct messages (model + controller + Turbo Stream view)
- **Tests** — Shared::ReactionToggle, Shared::FollowToggle, Shared::EventEmitter have no test coverage

## DEPLOY/rails — hjerterom

Controllers landed; views missing for all four new resources:

- `app/views/donations/` — index, show, new, _form
- `app/views/boxes/` — index, show, new, _form
- `app/views/volunteers/` — index, show, new, _form + shift list partial
- `app/views/shifts/` — index, _form

## DEPLOY/rails — cross-app

- **`bin/ci`** — Rails 8 local CI script per subapp (rubocop + brakeman + bundler-audit + minitest); verify all 6 apps have one
- **Gemfile audit** — baibl removed pg_search from model; confirm gem removed from Gemfile too
