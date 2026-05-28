# pub4 backlog

## Critical

- Verify face renders at https://ai.brgen.no/ — open fresh private window, tap primer, confirm WebGL face + ecology particles appear
- /triad 3rd step is a buggy on/off toggle, not deliberation — fix council turn to emit actual multi-persona verdict

## postpro

- Sync /home/dev/postpro generated files to /var/www/postpro after each regen run
  (regen.rb handles this; postpro_vps.rb now auto-calls gallery_lightbox.rb)

## MASTER — master.yml/master.json gap closure

9 remaining gaps, priority order:

1. Six Universal Laws ladder — rules.yml defines them; verify scanner emits law: tag on findings
2. Strunk & White safeguards — rules.yml has apply_to/never_apply_to; verify personality.rb honours them
3. Biases section — hallucination/simulation/completion_theater need lexical regex detectors, not just semantic
4. structural_ops taxonomy — merge/defrag/decouple/hoist/flatten need to be invokable rewriter operations
5. 8-phase workflow learn phase — verify the pipeline actually runs learn after deliver
6. Veto patterns: UNFINISHED severity info → error; add RACE_CONDITIONS and UNSAFE_CALLS detectors
7. Adversarial — 5 targeted questions per violation (currently 1 steelman+challenge per file)
8. Prediction engine — per-detector autofix confidence thresholds from rules.yml wired to scanner
9. Cost guards — per-file budget check in LLMDispatcher (budget.yml warn_at/max_per_file already parse)

## MASTER — module cleanup

- lib/ops/ → lib/loop/ops/: rename Master::Ops → Master::Loop::Ops; update master.rb + work_commands.rb
- 11 orphaned lib/*.rb: master.rb, builder.rb, plugin.rb, orient.rb, result.rb, learnings.rb,
  memory.rb, unwrap_error.rb, master_paths.rb, pressure_engine.rb — move to owning modules
- data/ selective merges: patterns.yml absorb infer_patterns.yml + repo_topic_clusters.yml +
  prompt_archaeology.yml (all namespaced, already partly done)
- Prompt caching: verify cache hits on non-Claude models (OpenRouter/auto) — build_final_system
  currently only wraps Claude; other providers lack equivalent cache_control

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

## DEPLOY/rails

- brgen (flagship) + subapps: bsdports, hjerterom, baibl, amber, blognet
  Read Rails 8 / StimulusReflex / stimulus-components docs before touching
