# UI refinements — applied

Implementations for the 2026-07-18 proposal list. Canonical tokens:
`RAILS/shared/design_tokens.yml`. Ship verification: visual_contract + deploy.

_Last applied: 2026-07-18 (full pass)._

## Applied clusters

### A · Design tokens
- Dialect → consumer map documented at top of `design_tokens.yml`
- `shared_chrome` motion/elevation/semantic colors + `space_2xs`
- Social + luxury scales aligned with 2xs / success / warning / info
- Intent named: social soft vs face/bsdports CRT-flat zeros

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
- Vertical accents (marketplace serif/warm, dating warm, TV 16:9/live, takeaway sold-out badge, playlist accent controls)
- Flash/toast flat cards; post measure 66ch; skeleton utility; high-contrast media query
- Content-visibility on cards; form error slot; empty-state class
- Tap highlight accent; safe-area padding

### D · amber luxury
- `_ui_refinements_pass.scss`: relaxed body, Caprasimo display, editorial grid,
  placeholder tiles, edge-swiper focus, look-rail, sustainability grade chip
- Caprasimo self-hosted (prior pass)

### E · bsdports
- `openbsd_wscons` green terminal tokens on `:root`/`body`
- Dense mono rows, advisory tags, secondary green meta-only

### F–O · Shared floor
- Focus floor already in brgen; extended tap-min + contrast + motion gates
- CDN self-host maplibre/css-doodle (prior); fonts Inter/Libre/Caprasimo
- Maps noscript list fallback
- Theme FOUC already fixed; amber/bsdports theme-color present

## Intentionally residual (product/ops, not pure CSS)

| Item | Why residual |
|------|----------------|
| Full visual_contract capture matrix | Needs running apps + Ferrum on Ruby 3.4/VPS |
| True ML rembg/segmentation | Postpro bridge only; models are infra |
| Per-glyph typewriter captions vs fade | Product choice — left as fade-capable CSS |
| Council multi glyph set | Needs face JS state machine work beyond style |
| Token CSS auto-gen test fail-on-drift | Follow-up for `generate_face_root_css.rb` |
| Demo wardrobe seed 6–8 items | Data seed, not layout |
| Global `/` hotkey search chrome | App already has feed-hotkey; UI partial optional |

These are tracked in `MASTER/DEBT.md` / `apps.horizon.yml` when they grow past polish.

## How to re-verify

```zsh
ruby RAILS/test/marketplace_cart_contract_test.rb
# After deploy / asset build:
# VISUAL_CAPTURE=1 ruby RAILS/gates/runner.rb visual_contract
```
