# DEPLOY_RAILS_NEW_PROPOSAL.md

**Status (2026-07-09):** R1–R9 and R7 are implemented. This file now tracks only the
remaining item.

## R10 — One parametric token source for MASTER face and all Rails apps

Today there are two half-shared design-token sources drifting apart:
`shared/app/assets/stylesheets/_x_base.scss` (hardcoded x.com hex values) and
`MASTER/web/public/face.css` (parametric `oklch` + `color-mix` palette).

Promote the face palette math into the engine:

1. Rewrite `_x_base.scss` as a parametric mixin (`oklch` anchors + `color-mix` tints).
2. Keep per-app vertical overrides on top of the base.
3. Regenerate `face.css` `:root` from the shared source (Ruby generator in `DEPLOY/rails/`).
4. Extend `master_web_assets_gate.rb` to fail on token drift.

Acceptance: `build_all_css.rb` visually identical for four apps; `master_web_assets_gate.rb`
green; `Shared::FrontendAuditor` clean.

Do **not** import kiosk-only face.css rules (fullscreen canvas, `touch-action: none`) into apps.