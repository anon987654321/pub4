# UI refinements — applied

Implementations for the 2026-07-18 proposal list plus the 2026-07-19 visual
opportunity pass. Canonical tokens: `RAILS/shared/design_tokens.yml`.
Ship verification: visual_contract + deploy.

_Last applied: 2026-07-20 (polish wave: flat hotkey toast, tokenized hex, hello_controller removed, idb-keyval shared)._

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
- `luxury-light-tokens` / `luxury-dark-tokens` wired in `_variables.scss`
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

## 2026-07-20 polish wave (landed)

| Item | Status |
|------|--------|
| Flat hotkey toast (`_x_shell` `.hotkey-help`, no box-shadow) | Landed |
| Tokenized hex / no Twitter `#1d9bf0` in app SCSS | Landed |
| `hello_controller` removed from apps | Landed |
| `idb-keyval` shared only (hostname DB name) | Landed |
| Local `bottom_sheet_controller` removed; gate forbids reintroduction | Landed |
| Visualizer tap-ripple `filter:blur` removed | Landed |
| Dressing-room 3D = intentional FLAT_UI exception + reduced-motion | Landed |
| `*Service` POROs renamed (Zeitwerk-safe; AccountMerger / IdentityAssurer / TrustScore) | Landed |
| Shared wiring gate forbids hello/idb/bottom_sheet local copies | Landed |
| Domain alignment + crawl/seeds FAIL_VISIBLY logging | Landed |
| Vertical accent CSS vars exported (`--vertical-*-accent`) | Landed |
| Amber item wear/cost tests + bsdports dependency cycle tests | Landed |

## 2026-07-31 onboarding / auth polish (landed)

| Item | Status |
|------|--------|
| Auth chrome-light (`body.auth-surface`) — hide tab bar, nearby, edge grips, nav swiper | Landed |
| Auth form CSS — password grid, OAuth empty-nav guard, footer row, lead copy | Landed |
| brgen guest home — city intro first; AI demoted to chip (`?master=1` full embed) | Landed |
| Empty-state space-not-lines + CTAs (home search, ports, amber items); baseline 48→44 | Landed |
| Amber guest CTA hierarchy + wardrobe “More tools” progressive disclosure | Landed |
| Dating intro CSS `filter` removed (flat UI) | Landed |
| Password + 2FA views on shared `.auth-form` shell (all apps) | Landed |
| Guest-truth: communities post CTA, takeaway order copy | Landed |
| Search/empty CTAs batch (communities, posts, deals, shops, places, restaurants, live, nearby, conversations, notifications, amber outfits/connections/capsule, bsdports categories/maintainers) | Landed |
| empty_state_lint baseline 48 → 0 (all empties have CTA or no-action-ok) | Landed |
| Deep pass: ad-hoc empties→shared partial (amber + cart + TV channels) | Landed |
| Dating guest discover truth + progressive profile form | Landed |
| Product install prompts (brgen / amber / bsdports) | Landed |
| Vertical purpose intros (takeaway, TV home) | Landed |
| Family layout contract (MASTER + RAILS shared chrome vars, skip-link, landmarks) | Landed |
| Ambient chat dock: #brgen lobby without GPS, #nearby when located | Landed |
| Playlist minimal now-playing + auto-start | Landed |
| Amber btn--primary normalize (+ btn-primary alias) | Landed |
| Dating discover/matches nb chrome | Landed |
| Install prompt after value only (no visit count) | Landed |
| Location denied sticky + guest merge flash | Landed |
| Ambient chat NN/g (lobby without GPS, Enter-send, i18n status) | Landed |
| Footer tab bar progressive (closed by default; peel + scroll-up) | Landed |
| Nearby page i18n + lobby path without GPS | Landed |
| Install prompt action i18n; quieter edge grips | Landed |
| Channel/DM composer parity (Enter-send, i18n) | Landed |
| Nearby + Live explicit Use location + page reload | Landed |
| First-visit footer menu coach (dismissible) | Landed |
| Live page full i18n (nb/en) | Landed |
| Ambient chat flush bottom-right corner | Landed |
| Empty-send disabled on chat composers | Landed |
| Peel flush bottom-center; alerts clear chat tab | Landed |
| Residual chat EN (messages/new, marketplace order, playlist party) | Landed |
| Social chrome i18n (comments, channel/DM chrome, theme, push, unread pill) | Landed |
| Install-value on full-page channel/DM send | Landed |
| Shared social.en/nb locales in pub4-shared engine | Landed |
| Shared comments/_form partial (brgen + amber) | Landed |
| Shared comments/_comment row (threaded + flat) | Landed |
| Amber social + product chrome i18n | Landed |

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
| Per-app PWA monochrome icons | Landed (brgen/amber/bsdports + manifests) |
| Full ERB class-soup → bare semantic HTML | Multi-PR product surface; partial via shared primitives |
| Full i18n of brgen chrome strings | Core home/auth/nav/empty + full primary nav landed; residual vertical product copy remaining |
| Amber/bsdports chrome i18n (auth, layout, guest home, ports search) | Landed 2026-07-31 |
| Space-not-lines TV/nearby/empty/amber dash | Landed 2026-07-31 |
| design_rules pixel_perfection alignment (no ornamental box-shadow in polish wave) | Landed 2026-07-31 — floating chrome uses border/surface contrast |
| Vertical empty + search i18n (marketplace, TV, playlist, takeaway, maps, amber, bsdports) | Landed 2026-07-31 |
| Type/pixel alignment: --text-title token, page-header 48px rhythm, font var(--font) | Landed 2026-07-31 |
| MASTER autonomy: design_rules.ui_polish + chrome_i18n_lint + surface rules | Landed 2026-07-31 — see MASTER/docs/UI_POLISH_PLAYBOOK.md |
| Exhaustive model/request coverage | Expand when touching domains (Boy Scout) |
| In-process `release` / `rails_runtime` / `visual_contract` | Still subprocess by design |
| SCSS `_ui_refinements*` merge into domain partials | Next touch Boy Scout |
| Horizon features (pgvector, live video, Solidus full) | `apps.horizon.yml` agent-ignore |

These are tracked in `MASTER/DEBT.md` / `apps.horizon.yml` when they grow past polish.

## How to re-verify

```zsh
ruby RAILS/test/marketplace_cart_contract_test.rb
# After deploy / asset build:
# VISUAL_CAPTURE=1 ruby RAILS/gates/runner.rb visual_contract
```
