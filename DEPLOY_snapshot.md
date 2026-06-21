# DEPLOY Snapshot (Critical Gaps + Progress 2026-06-21)
Generated: 2026-06-21T00:00:00Z

## This pass
- Replaced the app deploy tree syncs with `openrsync` and removed the remaining legacy `cp -R` paths from the live app scripts.
- Centralized the shared overlay sync in `DEPLOY/rails/shared/deploy/@shared_functions.sh`.
- Upgraded the shared runtime gate so every app restart path now sees the MASTER scan gate, `bundle check`, `db:prepare`, and `bin/ci`.
- Added activity emission to the remaining non-brgen controllers so the cross-app graph is no longer missing the common create/update/view paths.
- Made `DEPLOY/openbsd/health_check.rb` privilege-aware so it can run under `doas` for PF and `rcctl` checks.
- Added a reproducible Workbox 7.4.1 build for all six PWAs with precaching, bounded runtime caches, offline navigation, POST replay, periodic refresh, and push handling.
- Added a cross-app PWA/design contract covering routes, registration, manifests, generated workers, shared tokens, minimal UI, and navigation accessibility.

## Evidence
- `DEPLOY/rails/shared/deploy/@shared_functions.sh`
- `DEPLOY/rails/{amber,baibl,blognet,brgen,bsdports,hjerterom}/*.sh`
- `DEPLOY/rails/shared/app/models/application_record.rb`
- `DEPLOY/rails/amber/app/controllers/*`
- `DEPLOY/rails/baibl/app/controllers/*`
- `DEPLOY/rails/blognet/app/controllers/*`
- `DEPLOY/rails/bsdports/app/controllers/*`
- `DEPLOY/rails/hjerterom/app/controllers/*`
- `DEPLOY/openbsd/health_check.rb`
- `DEPLOY/rails/shared/pwa/service_worker.js`
- `DEPLOY/rails/scripts/build_workbox.mjs`
- `DEPLOY/rails/test/pwa_design_contract_test.rb`

## Live check
- Reverse DNS for `46.23.89.226` resolves to `powered-by.openbsd.amsterdam.` from the VM.
- The current VM health sweep passes on `/up` after the restart and relayd refresh.
- `PermitRootLogin no`, `PasswordAuthentication no`, and `MaxAuthTries 3` are set on vm23.

## Local completion evidence
- `npm run build:pwa`: six generated workers.
- `npm run test:pwa`: 4 runs, 204 assertions, 0 failures.
