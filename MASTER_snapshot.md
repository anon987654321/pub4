# MASTER Snapshot (Critical Gaps + Progress 2026-06-21)
Generated: 2026-06-21T12:00:00Z

## This pass
- Landed runtime hardening: `TtsSupervisor` auto-starts Edge TTS daemon; `TtsJob` surfaces failures as 503 instead of endless 202 polling.
- Lazy web boot: `MasterContainerLoader.ensure!` on first non-exempt request; `/up`, `/assets/`, and face public assets skip warming.
- Falcon worker count via `FALCON_COUNT` (default 2) in `web/falcon.rb`.
- Single face entrypoint: `chat/index.html.erb`; removed dead `public/index.html.erb`.
- Fixed RuleDSL `check` wiring, namespace drift, CLI `/help` crash, memory test brain-key isolation.
- Added `bin/probe kernel`, optional `bin/probe_selfscan`, `/kernel` CLI command.
- **Production CSS fix**: Propshaft assets must be precompiled before `rcctl restart master`; `master_web_assets_gate.rb` verifies `face.css`/`face.js` digests exist on disk.

## Evidence
- `MASTER/lib/voice/tts_supervisor.rb`
- `MASTER/web/config/initializers/master_container.rb`
- `MASTER/web/app/controllers/application_controller.rb`
- `MASTER/web/app/services/tts_job.rb`
- `MASTER/web/falcon.rb`
- `MASTER/lib/judge/scan/rule_dsl.rb`
- `MASTER/test/test_web_ui.rb`
- `MASTER/test/test_memory.rb`
- `DEPLOY/rails/master_web_assets_gate.rb`
- `DEPLOY/sh/vps_install_all.sh`

## Local completion evidence
- `MASTER/bin/probe kernel`: ALL GREEN
- `MASTER/bin/probe quick`: smoke + nsaudit + rails clean
- `MASTER/bin/smoke`: clean (chat turn ~11 min locally)
- `test/test_web_ui.rb`: 28/28
- `test/test_memory.rb`: 17/17
- `ruby DEPLOY/rails/master_web_assets_gate.rb`: pass

## Production note (ai.brgen.no)
- Root cause of missing CSS: `/assets/face-*.css` returned 404 — digested Propshaft files absent on VPS.
- Fix path: `git pull` → `RAILS_ENV=production rails assets:precompile` in `MASTER/web` → `doas rcctl restart master`.