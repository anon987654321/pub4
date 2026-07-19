# UI refinements — applied

Implementations for the 2026-07-18 proposal list plus the 2026-07-19 visual
opportunity pass. Canonical tokens: `RAILS/shared/design_tokens.yml`.
Ship verification: visual_contract + deploy.

_Last applied: 2026-07-19 (full visual opportunity land)._

## Applied clusters

### A · Design tokens
- Dialect → consumer map documented at top of `design_tokens.yml`
- `shared_chrome` motion/elevation/semantic colors + `space_2xs`
- Social + luxury scales aligned with 2xs / success / warning / info
- Intent named: social soft vs face/bsdports CRT-flat zeros
- Light mode indigo/graphite (not Twitter blue)
- `vertical_accents` single source map (marketplace taupe, dating teal, maps cool blue, messenger slate-indigo)

### B · MASTER face (boot contract preserved)
- Primer phosphor title + mono consent styling (`face.css`)
- HUD tier hairlines, caption measure, chat caret mono
- Canvas `role="img"` + `aria-label`; `face-status-live` aria-live region
- 44px bar targets; permission button mono/zero-radius
- `406-unsupported-browser.html` action-first mono copy
- Error pages mono-aligned; reduced-motion primer glow off
- **Not changed:** WebGL/THREE before primer, `startEverything` path

### C · brgen shell
- Nav swiper `tablist`/`tab`/`aria-selected` + arrow-key roving tabindex
- Active underline + scroll-snap; 44px min hit
- City carousel → real `https://{domain}/` links; pause on reduced-motion + hidden tab
- Vertical accents single map in `_vertical_shell` only (no ui_refinements re-write)
- Graphite elevation (`#17161c` / `#211f28`) instead of pure black
- Flash/toast flat cards; post measure 66ch; skeleton utility; high-contrast media query
- Content-visibility with taller intrinsic for media cards
- Form error slot; empty-state partial; tap highlight accent; safe-area padding
- Messenger flat solid bubbles + mono timestamps + 44px send
- Playlist token-backed colors (no magic neon hex / decorative gradients)
- TV: no CSS filter grade / radial glow; solid stage + hairline
- Maps: cool cartography blue-gray, solid accent buttons

### D · amber luxury
- `x-luxury-light-tokens` / `x-luxury-dark-tokens` wired in `_variables.scss`
- Caprasimo display, editorial grid (collapses on small screens)
- Placeholder tiles with flat diagonal hatch; sustainability grade chip
- Empty/skeleton/high-contrast floor

### E · bsdports
- `openbsd_wscons` green terminal tokens on `:root`/`body`
- Dense mono rows, advisory tags, secondary green meta-only
- Empty-state CRT (radius 0), mono skeleton, sticky port meta, tabular nums
- prefers-contrast more

### F–O · Shared floor
- `_empty_state.scss` + `_empty_state.html.erb` across all three apps
- Offline Retry button + Stimulus `retry`
- Error pages graphite/indigo dialect (not Twitter blue)
- Edge grips 44px hit area; forced-colors ported into x_shell
- Search skeleton loading shell
- WIRING_NOTES dialect truth (soft social / CRT face+bsdports / single-column + edge swiper)

## Intentionally residual (product/ops, not pure CSS)

| Item | Why residual |
|------|----------------|
| Full visual_contract capture matrix | Needs running apps + Ferrum/Chrome on Ruby 3.4/VPS |
| True ML rembg/segmentation | Postpro bridge only; models are infra |
| Per-glyph typewriter captions vs fade | Product choice — left as fade-capable CSS |
| Council multi glyph set | Needs face JS state machine work beyond style |
| Token CSS auto-gen test fail-on-drift | Follow-up for `generate_face_root_css.rb` |
| Demo wardrobe seed 6–8 items | Data seed, not layout |
| Global `/` hotkey search chrome | App already has feed-hotkey; UI partial optional |
| Per-app PWA monochrome icons | Asset design pass |

These are tracked in `MASTER/DEBT.md` / `apps.horizon.yml` when they grow past polish.

## How to re-verify

```zsh
ruby RAILS/test/marketplace_cart_contract_test.rb
# After deploy / asset build:
# VISUAL_CAPTURE=1 ruby RAILS/gates/runner.rb visual_contract
```
