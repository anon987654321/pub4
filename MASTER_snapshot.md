# MASTER Snapshot (Critical Gaps + Progress 2026-06-21)
Generated: 2026-06-21T00:00:00Z

## This pass
- Shared `ApplicationRecord` now includes `Shared::ActivityTrackable`, so app controllers can call `record_activity!` without repeating concern plumbing.
- Deploy sync moved from legacy `cp -R` tree copies to `openrsync` in every app deploy script plus the shared initializer overlay.
- `rails_runtime_gate` now enforces the MASTER scan gate, `bundle check`, `db:prepare`, and `bin/ci` before restart.
- MASTER's piped slash-command path now dispatches `/self` directly and all CLI startup/self-scan dependencies use the canonical container refs.
- The Rails chat view is the single face entrypoint; dead `public/index.html.erb` is removed and late `face.css` overrides are folded into their owning selectors.
- SINGULARITY checks duplicate rule IDs only in `data/rules.yml`, avoiding false positives from repeated model catalog IDs.

## Evidence
- `DEPLOY/rails/shared/app/models/application_record.rb`
- `DEPLOY/rails/shared/deploy/@shared_functions.sh`
- `DEPLOY/rails/{amber,baibl,blognet,brgen,bsdports,hjerterom}/*.sh`
- `MASTER/web/app/views/chat/index.html.erb`
- `MASTER/web/public/face.css`
- `MASTER/lib/now/cli.rb`
- `MASTER/lib/judge/scan/self_test.rb`
- `DEPLOY/openbsd/health_check.rb`
- `MASTER/bin/smoke`

## Activity wiring added this pass
- Amber: items, outfits, posts, follows, planned outfits, wardrobe items.
- Baibl: bookmarks, highlights, scripture book/chapter/verse study views.
- Blognet: blogs, posts, comments.
- BSDPorts: ports, comments, maintainers, categories.
- Hjerterom: donations, food listings, food requests, shifts, volunteers, resources, community posts, boxes.

## Local completion evidence
- `MASTER/bin/smoke`: clean.
- Focused CLI/self-test suites: green.
- Piped `/self`: `judge: lib/ 101 rules, 0 violations`.

## Note
- Final VPS self-scan and web restart evidence is recorded after the release sync.
