# MASTER2 restoration opportunities for MASTER

This inventory compares `MASTER2/` to `MASTER/` and lists artifacts that exist in MASTER2 but are absent in MASTER. These absences are potential restoration opportunities if MASTER intends feature parity with MASTER2.

## Snapshot

- MASTER2 files scanned: **388**
- MASTER files scanned: **107**
- Missing in MASTER (restoration opportunities): **382**

## Opportunities by area

1. **Core runtime and capabilities (`lib/`)** — 235 files.
   - Largest gap: agent subsystems (`lib/agent`, `lib/analysis`, `lib/review`, `lib/executor`, `lib/workflow`, `lib/ui`, `lib/session`).
   - Notable high-impact restorations: `lib/master.rb`, `lib/commands.rb`, `lib/analysis.rb`, `lib/review.rb`, `lib/workflow.rb`, `lib/llm.rb`, `lib/server.rb`.

2. **CLI and operator workflows (`bin/`, `completions/`)** — 6 files.
   - Missing CLIs and utilities: `bin/master`, `bin/mcp_server`, `bin/weekly`, validation/simulation tooling, and zsh completion.

3. **Policy/config intelligence (`data/`)** — 30 files.
   - Missing policy catalogs for models, personas, pipelines, quality gates, hooks, and prompts.

4. **Quality/safety regression net (`test/`, `.rubocop.yml`)** — 93 files.
   - Missing end-to-end and unit tests covering core orchestration, security gates, LLM flows, and pipeline behaviors.

5. **Operational docs and automation (`docs/`, `scripts/`, `.github/`)** — 5 files.
   - Missing deployment/testing docs and CI workflow automation.

## Full restoration inventory

### .env.example (1)

- `.env.example`

### .github (2)

- `.github/copilot-instructions.md`
- `.github/workflows/test.yml`

### .gitignore (1)

- `.gitignore`

### .rubocop.yml (1)

- `.rubocop.yml`

### .session_recovery.template (1)

- `.session_recovery.template`

### AGENTS.md (1)

- `AGENTS.md`

### CLAUDE.md (1)

- `CLAUDE.md`

### LLM.md (1)

- `LLM.md`

### README.md (1)

- `README.md`

### Rakefile (1)

- `Rakefile`

### bin (5)

- `bin/master`
- `bin/mcp_server`
- `bin/simulate`
- `bin/validate`
- `bin/weekly`

### completions (1)

- `completions/_master`

### data (30)

- `data/axiom_resolution.yml`
- `data/compression.yml`
- `data/design.yml`
- `data/detectors.yml`
- `data/exemplars.yml`
- `data/friction_patterns.yml`
- `data/hooks.yml`
- `data/integrations.yml`
- `data/language_detection.yml`
- `data/learned_smells.json`
- `data/models.yml`
- `data/personas.yml`
- `data/phases.yml`
- `data/pipelines/blade-runner-2049.yml`
- `data/pipelines/film-noir-classic.yml`
- `data/pipelines/wes-anderson-aesthetic.yml`
- `data/principles.yml`
- `data/prompts/preact.yml`
- `data/prompts/react.yml`
- `data/prompts/reflexion.yml`
- `data/prompts/rewoo.yml`
- `data/quality_thresholds.yml`
- `data/replicate_models.yml`
- `data/scheduled_jobs.yml`
- `data/session_template.yml`
- `data/stack.yml`
- `data/strunk.yml`
- `data/style_guides.yml`
- `data/system_prompt.yml`
- `data/ui_ux_seo.yml`

### docs (2)

- `docs/openbsd_execution.md`
- `docs/video_narration.md`

### examples (2)

- `examples/.keep`
- `examples/cinematic_demo.rb`

### instructions.txt (1)

- `instructions.txt`

### lib (235)

- `lib/agent.rb`
- `lib/agent/autonomy.rb`
- `lib/agent/behavior_monitor.rb`
- `lib/agent/credential_store.rb`
- `lib/agent/firewall.rb`
- `lib/agent/policy.rb`
- `lib/agent/pool.rb`
- `lib/analysis.rb`
- `lib/analysis/introspection.rb`
- `lib/analysis/introspection/self_critique.rb`
- `lib/analysis/introspection/self_repair.rb`
- `lib/analysis/openbsd_config_validator.rb`
- `lib/analysis/prescan.rb`
- `lib/auto_install.rb`
- `lib/axiom_resolver.rb`
- `lib/boot.rb`
- `lib/boot/modes.rb`
- `lib/bridges.rb`
- `lib/bridges/postpro.rb`
- `lib/bridges/postpro/vips_effects.rb`
- `lib/bridges/repligen.rb`
- `lib/bridges/repligen/pipelines.rb`
- `lib/capabilities.rb`
- `lib/chamber.rb`
- `lib/chamber/creative.rb`
- `lib/chamber/deliberation.rb`
- `lib/chamber/ideation.rb`
- `lib/chamber/review.rb`
- `lib/chamber/swarm.rb`
- `lib/cinematic.rb`
- `lib/cinematic/templates.rb`
- `lib/circuit_breaker.rb`
- `lib/code_review/analyzers.rb`
- `lib/code_review/audit.rb`
- `lib/code_review/bug_hunting.rb`
- `lib/code_review/bug_hunting/phases.rb`
- `lib/code_review/cross_ref.rb`
- `lib/code_review/engine.rb`
- `lib/code_review/llm_friendly.rb`
- `lib/code_review/prism_analyzer.rb`
- `lib/code_review/smells.rb`
- `lib/code_review/violations.rb`
- `lib/command_registry.rb`
- `lib/commands.rb`
- `lib/commands/budget_commands.rb`
- `lib/commands/chat_commands.rb`
- `lib/commands/code_commands.rb`
- `lib/commands/init_commands.rb`
- `lib/commands/misc_commands.rb`
- `lib/commands/misc_commands/cinematic_persona.rb`
- `lib/commands/misc_commands/self_run.rb`
- `lib/commands/misc_commands/selftest_full.rb`
- `lib/commands/model_commands.rb`
- `lib/commands/refactor_helpers.rb`
- `lib/commands/session_commands.rb`
- `lib/commands/system_commands.rb`
- `lib/commands/workflow_commands.rb`
- `lib/conflict_resolver.rb`
- `lib/constants.rb`
- `lib/convergence_tracker.rb`
- `lib/conversation.rb`
- `lib/cross_file_analyzer.rb`
- `lib/db_jsonl.rb`
- `lib/db_jsonl/tables.rb`
- `lib/decision_engine.rb`
- `lib/dependency_map.rb`
- `lib/enforcement/layers.rb`
- `lib/enforcement/scopes.rb`
- `lib/env_loader.rb`
- `lib/event_bus.rb`
- `lib/evolve.rb`
- `lib/executor.rb`
- `lib/executor/context.rb`
- `lib/executor/convention_extractor.rb`
- `lib/executor/grounded_context.rb`
- `lib/executor/momentum.rb`
- `lib/executor/plan.rb`
- `lib/executor/preact.rb`
- `lib/executor/prompts.rb`
- `lib/executor/react.rb`
- `lib/executor/reflexion.rb`
- `lib/executor/rewoo.rb`
- `lib/executor/step_loop.rb`
- `lib/executor/strategy.rb`
- `lib/executor/tool_protocol.rb`
- `lib/executor/tool_result.rb`
- `lib/executor/tools.rb`
- `lib/file_collector.rb`
- `lib/file_processor.rb`
- `lib/harvester.rb`
- `lib/heartbeat.rb`
- `lib/hooks.rb`
- `lib/html_generator.rb`
- `lib/introspection/adversarial.rb`
- `lib/introspection/architect.rb`
- `lib/introspection/friction_recorder.rb`
- `lib/introspection/reporting.rb`
- `lib/introspection/self_map.rb`
- `lib/introspection/session_retrospective.rb`
- `lib/lane.rb`
- `lib/learned_smells.rb`
- `lib/learnings.rb`
- `lib/learnings/feedback.rb`
- `lib/learnings/quality.rb`
- `lib/learnings/reflection.rb`
- `lib/llm.rb`
- `lib/llm/budget.rb`
- `lib/llm/context_window.rb`
- `lib/llm/hesitation_detector.rb`
- `lib/llm/models.rb`
- `lib/llm/request.rb`
- `lib/llm/tools.rb`
- `lib/logging.rb`
- `lib/logging/dmesg.rb`
- `lib/logging/structured.rb`
- `lib/master.rb`
- `lib/mcp_server.rb`
- `lib/mode.rb`
- `lib/multi_refactor.rb`
- `lib/nlu.rb`
- `lib/openbsd_validator.rb`
- `lib/output.rb`
- `lib/parser/multi_language.rb`
- `lib/paths.rb`
- `lib/personas.rb`
- `lib/phase_gates.rb`
- `lib/pipeline.rb`
- `lib/pipeline/context.rb`
- `lib/pipeline/repl.rb`
- `lib/platform_check.rb`
- `lib/pledge.rb`
- `lib/policy/enforcer.rb`
- `lib/policy/profile.rb`
- `lib/policy/rule.rb`
- `lib/pressure_pass.rb`
- `lib/problem_solver.rb`
- `lib/project_memory.rb`
- `lib/quality_gates.rb`
- `lib/queue.rb`
- `lib/reflow.rb`
- `lib/replicate.rb`
- `lib/replicate/client.rb`
- `lib/replicate/generators.rb`
- `lib/replicate/llm.rb`
- `lib/replicate/media.rb`
- `lib/replicate/models.rb`
- `lib/replicate/narration.rb`
- `lib/result.rb`
- `lib/review.rb`
- `lib/review/axiom_stats.rb`
- `lib/review/beauty.rb`
- `lib/review/constitution.rb`
- `lib/review/design_codex.rb`
- `lib/review/enforcer.rb`
- `lib/review/enforcer/language_axioms.rb`
- `lib/review/enforcer/quality_standards.rb`
- `lib/review/fixer.rb`
- `lib/review/reflow.rb`
- `lib/review/scanner.rb`
- `lib/review/tool_scanner.rb`
- `lib/rubocop_detector.rb`
- `lib/scan.rb`
- `lib/scan/rules/code_style.rb`
- `lib/scan/rules/encoding.rb`
- `lib/scan/rules/rescue_hygiene.rb`
- `lib/scan/rules/silent_rescue.rb`
- `lib/scheduler.rb`
- `lib/security/injection_guard.rb`
- `lib/security/permissions.rb`
- `lib/security/sanitizer.rb`
- `lib/self_refactor.rb`
- `lib/semantic_cache.rb`
- `lib/server.rb`
- `lib/server/handlers.rb`
- `lib/server/websocket.rb`
- `lib/session.rb`
- `lib/session/capture.rb`
- `lib/session/language.rb`
- `lib/session/memory.rb`
- `lib/session/per_step_reflection.rb`
- `lib/session/persona.rb`
- `lib/session/reminders.rb`
- `lib/session/replay.rb`
- `lib/shell.rb`
- `lib/shell/session.rb`
- `lib/single_instance.rb`
- `lib/speech.rb`
- `lib/speech/backends.rb`
- `lib/speech/playback.rb`
- `lib/speech/streaming.rb`
- `lib/speech/utils.rb`
- `lib/stages.rb`
- `lib/stages/ask.rb`
- `lib/stages/compress.rb`
- `lib/stages/council.rb`
- `lib/stages/execute.rb`
- `lib/stages/guard.rb`
- `lib/stages/intake.rb`
- `lib/stages/lint.rb`
- `lib/stages/render.rb`
- `lib/stages/route.rb`
- `lib/stages/strunk.rb`
- `lib/staging.rb`
- `lib/syntax_validator.rb`
- `lib/text_hygiene.rb`
- `lib/triggers.rb`
- `lib/ui.rb`
- `lib/ui/autocomplete.rb`
- `lib/ui/components.rb`
- `lib/ui/confirmations.rb`
- `lib/ui/convenience.rb`
- `lib/ui/dashboard.rb`
- `lib/ui/diff.rb`
- `lib/ui/errors.rb`
- `lib/ui/formatting.rb`
- `lib/ui/help.rb`
- `lib/ui/keybindings.rb`
- `lib/ui/nng.rb`
- `lib/ui/output.rb`
- `lib/ui/progress.rb`
- `lib/ui/spinner.rb`
- `lib/ui/table.rb`
- `lib/ui/utilities.rb`
- `lib/undo.rb`
- `lib/utils.rb`
- `lib/views/cli.html`
- `lib/views/ws_test.html`
- `lib/violation_hooks.rb`
- `lib/weaviate.rb`
- `lib/web.rb`
- `lib/workflow.rb`
- `lib/workflow/convergence.rb`
- `lib/workflow/engine.rb`
- `lib/workflow/planner.rb`
- `lib/zsh_pattern_injector.rb`

### master2.gemspec (1)

- `master2.gemspec`

### sbin (1)

- `sbin/agentd`

### scripts (1)

- `scripts/openbsd_preflight.zsh`

### test (92)

- `test/cli_basic_test.sh`
- `test/cli_integration_test.zsh`
- `test/support/llm_stubs.rb`
- `test/test_agent.rb`
- `test/test_agent_firewall.rb`
- `test/test_ask.rb`
- `test/test_audit.rb`
- `test/test_autocomplete.rb`
- `test/test_axiom_stats.rb`
- `test/test_bin_master_refactor.rb`
- `test/test_boot_manual.rb`
- `test/test_bridges_postpro.rb`
- `test/test_bridges_repligen.rb`
- `test/test_bug_hunting_escalation.rb`
- `test/test_chat_commands.rb`
- `test/test_circuit_breaker.rb`
- `test/test_command_routing.rb`
- `test/test_confirmation_gate.rb`
- `test/test_constitution.rb`
- `test/test_cross_ref.rb`
- `test/test_db.rb`
- `test/test_design_codex.rb`
- `test/test_diff_view.rb`
- `test/test_dry_fixes.rb`
- `test/test_event_bus.rb`
- `test/test_evolve_staged.rb`
- `test/test_executor.rb`
- `test/test_executor_patterns.rb`
- `test/test_executor_timeout.rb`
- `test/test_gemspec.rb`
- `test/test_guard.rb`
- `test/test_hardening.rb`
- `test/test_help.rb`
- `test/test_helper.rb`
- `test/test_hooks_convergence.rb`
- `test/test_html_generator.rb`
- `test/test_integration.rb`
- `test/test_integrations_command.rb`
- `test/test_introspection.rb`
- `test/test_language_axioms.rb`
- `test/test_language_detection.rb`
- `test/test_learning_feedback.rb`
- `test/test_learning_quality.rb`
- `test/test_llm.rb`
- `test/test_llm_flow.rb`
- `test/test_llm_media_policy.rb`
- `test/test_llm_model_info.rb`
- `test/test_llm_ruby_llm.rb`
- `test/test_logging.rb`
- `test/test_master2_boot.rb`
- `test/test_memory.rb`
- `test/test_momentum.rb`
- `test/test_multi_intent_dispatch.rb`
- `test/test_multi_refactor.rb`
- `test/test_permission_gate.rb`
- `test/test_persona_activation.rb`
- `test/test_personas.rb`
- `test/test_pipeline.rb`
- `test/test_pipeline_coverage.rb`
- `test/test_pipeline_modes.rb`
- `test/test_planner_helper.rb`
- `test/test_platform_check.rb`
- `test/test_prescan.rb`
- `test/test_preservation_rules.rb`
- `test/test_refactor.rb`
- `test/test_replicate.rb`
- `test/test_replicate_narration.rb`
- `test/test_result.rb`
- `test/test_result_categories.rb`
- `test/test_sanitizer.rb`
- `test/test_scan_profiles.rb`
- `test/test_self_apply.rb`
- `test/test_self_refactor_safety.rb`
- `test/test_self_repair.rb`
- `test/test_semantic_cache.rb`
- `test/test_server.rb`
- `test/test_server_handlers.rb`
- `test/test_session_capture.rb`
- `test/test_session_replay.rb`
- `test/test_shell.rb`
- `test/test_simulated_execution.rb`
- `test/test_single_instance.rb`
- `test/test_speech.rb`
- `test/test_stages.rb`
- `test/test_staging.rb`
- `test/test_starship_prompt.rb`
- `test/test_tool_firewall.rb`
- `test/test_ui_colors.rb`
- `test/test_undo.rb`
- `test/test_web_search_prioritization.rb`
- `test/test_web_ui_template.rb`
- `test/test_workflow_commands.rb`

