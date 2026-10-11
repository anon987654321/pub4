# RAILS TODO

Updated: 2026-10-11. Feature truth remains `apps.yml`; the canonical design tokens remain `MASTER/data/tokens.yml`. Cross-tree work is indexed in the repository-root `TODO.md`.

## P0 — release confidence and isolation

- [ ] Run `ruby RAILS/test/run_all.rb` and each app's `bin/ci` against current `main`. Fix every reproducible FAIL, HUNG or FLAKE; keep the per-file process isolation; make the printed test count reflect the files the runner actually selected.
- [ ] Complete a fresh Chrome pass on brgen's front page and messenger at narrow phone, wide phone, tablet and desktop widths, in Norwegian and English and on at least two registered city hosts. Save screenshots and rendered geometry; source-only assertions are not visual proof.
- [ ] Prove tenant isolation across feeds, direct/group conversations, inbox search, attachments, notifications, Turbo streams and background jobs. Unknown or malformed Host headers must fail closed; one city's records must not leak into another city's rendered pages, search results or realtime updates.
- [ ] Verify the messenger's full journey in a browser: switch rooms without replacing the rail, open a conversation directly, send/receive while streaming, preserve the unread divider, follow the tail only when appropriate, use search and advanced settings by keyboard, and recover cleanly after a dropped/reconnected stream. Test the one-pane mobile layout as well as the four-pane desktop contract.
- [ ] Prove payment flows in provider staging for Dintero, Stripe Connect and Vipps: signature validation, duplicate/out-of-order webhooks, idempotent paid-state transitions, minor-unit amounts, refund/failure cases and affiliate attribution boundaries. A source test is not evidence of provider-side configuration.
- [ ] Review the pinned Rails `8.2.0.alpha` ref against the current upstream release/security state. Upgrade only as a deliberate, pinned change with compatible Gemfiles/lockfiles and the full app + contract + browser suite; never float the dependency silently.
- [ ] Reconcile the city registry, public city links, DNS/TLS facts and deploy inventory. The source currently describes 43 registered apexes but only a smaller live-certificate set; a registry entry or footer link must not imply that a host resolves or has a valid certificate.

## P1 — product and interaction polish

- [ ] Refine the brgen first screen from recorded browser evidence: hierarchy of city identity/feed/composer, reading rhythm of post cards, image loading, live-update chip, sort control, guest state and empty/error states. Keep one ranking control and derive city-specific copy from the current host, not Bergen literals.
- [ ] Validate touch and keyboard behavior for every core action, including icon-only controls, close/back, search, message composition, file upload, dialogs and menus. Check focus order, visible focus, accessible names, reduced motion, contrast and genuine 44px-class hit areas in rendered geometry.
- [ ] Test PWA install, service-worker upgrade/rollback, stale-cache recovery, offline shell and media upload on real Android and iOS devices. Rebuild Workbox output from its source and prove deployment ships the newly generated worker.
- [ ] Run representative feed, messenger and marketplace requests with strict loading enabled; fix measured N+1 queries, unbounded message/feed payloads and slow searches without adding speculative caching.
- [ ] Recheck the complete user journeys in brgen, amber and bsdports—including authentication, uploads, search, errors and mobile navigation—rather than using one app's green suite as proxy evidence for the others.
- [ ] Keep shared UI ownership singular: generated design-token files are outputs of `MASTER/data/tokens.yml`; shared engine behavior belongs in `__shared`; verticals should not copy shared models, policies or visual tokens.
- [ ] Audit dead CSS, duplicate event handlers and unused Stimulus/Hotwire code from the built asset graph before deleting anything. Preserve documented boundaries where extracting a one-caller helper or unifying different navigation structures would increase indirection without reducing drift.

## P2 — capability and data correctness

- [ ] Check the feature claims in `apps.yml` against current routes, policies, tests and user-visible behavior. Do not mark a capability done because a model or placeholder view exists.
- [ ] Verify localization for all shipped locales and honest fallback behavior for registered cities whose language is not shipped. All user-facing copy, errors, dates, currency and empty states must follow the active locale.
- [ ] Recheck shared-engine migrations, strict-loading behavior and the sibling copy-tree deploy layout after changes to `__shared` or any `brgen_*` engine.
- [ ] Confirm product structured data and the Merchant Center feed remain in sync for public, priced and photographed goods; keep affiliate inventory excluded where the documented contract requires it.
- [ ] Review the RAILS visual-restoration candidate on `archaeology/micro-restoration-20261007` only against current rendered screenshots and its tests; keep the parts that materially improve hierarchy or readability and discard duplicate/stale CSS.

## Proof surfaces

`MASTER/gates/runner.rb --list`, the relevant gates, `ruby RAILS/test/run_all.rb`, each app's `bin/ci`, and real browser/device/provider evidence. A missing browser must remain inconclusive, not a green visual pass.
