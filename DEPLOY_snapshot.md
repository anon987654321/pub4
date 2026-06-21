# DEPLOY Snapshot (Critical Gaps + Progress 2026-06-21)
Generated: 2026-06-21T12:00:00Z

## This pass
- Activity wiring across all six Rails apps: controllers now call `record_activity!` via shared `ApplicationRecord`.
- Deploy sync standardized on `openrsync` in app scripts and shared initializer overlay.
- `rails_runtime_gate` enforces MASTER scan, `bundle check`, `db:prepare`, and `bin/ci` before restart.
- Workbox 7.4.1 PWA build for all six apps: precaching, bounded runtime caches, offline nav, POST replay, push handling.
- Cross-app PWA/design contract test (`DEPLOY/rails/test/pwa_design_contract_test.rb`).
- **MASTER web deploy fix**: `vps_install_all.sh` and `vps_on_vm_install.sh` now run `rails assets:precompile` + assets gate before `rcctl restart master`.
- `check_production_gate.rb` includes `master_web_assets_gate.rb` (verifies digested `face.css`, `face.js`, `chat.js`, `three.module.js` on disk).

## Evidence
- `DEPLOY/rails/shared/deploy/@shared_functions.sh`
- `DEPLOY/rails/shared/app/models/application_record.rb`
- `DEPLOY/rails/{amber,baibl,blognet,brgen,bsdports,hjerterom}/*.sh`
- `DEPLOY/rails/scripts/build_workbox.mjs`
- `DEPLOY/rails/shared/pwa/service_worker.js`
- `DEPLOY/rails/test/pwa_design_contract_test.rb`
- `DEPLOY/rails/master_web_assets_gate.rb`
- `DEPLOY/sh/vps_install_all.sh`
- `DEPLOY/openbsd/health_check.rb`

## Live check
- `https://ai.brgen.no/` loads HTML but CSS was 404 (`/assets/face-51c068af.css`) — VPS at `77430b434`, behind `12c02f0a6` + assets fix.
- Reverse DNS for `46.23.89.226` → `powered-by.openbsd.amsterdam.`

## Local completion evidence
- `npm run build:pwa`: six generated workers.
- `npm run test:pwa`: pass.
- `ruby DEPLOY/rails/check_production_gate.rb`: pass (6 apps + MASTER/web assets).