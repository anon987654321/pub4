# UI refinements — applied

Implementations for the 2026-07-18 proposal list plus the 2026-07-19 visual
opportunity pass. Canonical tokens: `RAILS/shared/design_tokens.yml`.
Ship verification: visual_contract + deploy.

_Last applied: 2026-08-01 (dead-wiring pass: install-prompt finally styled, pwa-standalone and offline-feed implemented in the shared engine, global `/` + ⌘K, token drift asserted against the committed tree)._

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
  — landed and **wrong**: 29 of those hosts do not resolve, so this row shipped a
  network that is not there onto every pageview. See `TODO.md`
  `brgen_city_carousel_links_dead`. A landed row and a wrong-but-landed row look
  identical from a checklist, which is why this file cannot be the only record.
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
| Shared post_card (brgen :card / amber :prose) | Landed |
| Focus triangle: brgen · amber · MASTER web | Landed |
| Amber social + product chrome i18n | Landed |

## 2026-08-01 dead-wiring pass (landed)

Everything here rendered, raised nothing, and did nothing — the failure shape this
file's checklists cannot catch, because a landed row and an inert one look identical
from the outside. Full accounting in `TODO.md`, `rails_silent_wiring_breaks`.

| Item | Status |
|------|--------|
| `.install-prompt` styled at all — the shared partial rendered in three apps and none styled it, so revealing it showed unstyled text in document flow | Landed |
| `pwa-standalone` implemented (`[data-pwa-display]` on `<html>`, safe-area inset, install prompt hidden once installed) and `data-pwa-key` given a reader | Landed |
| `offline-feed` moved brgen-local → shared, so amber item cards actually snapshot | Landed |
| `form-submit#lock` written (deferred a tick so the submitter's own value still posts) and attached to the two forms that called it | Landed |
| `content_for :body_attrs` yielded; push badge clears via `data-push-seen` rather than an action `<body>` could never resolve | Landed |
| Tv chat + video notes broadcast with explicit `partial:`/`target:`; videos/show subscribes to its own stream | Landed |
| Three broadcasts into streams with no subscriber removed (Reaction, TimestampedComment, SecurityAdvisory) | Landed |
| `stimulus_wiring` gate: every `data-controller` and `ev->id#method` in ERB resolves, 326 checks | Landed |

## Intentionally residual (product/ops, not pure CSS)

| Item | Why residual |
|------|----------------|
| Full visual_contract capture matrix | Needs running apps + Ferrum/Chrome on Ruby 3.4/VPS |
| True ML rembg/segmentation | Postpro bridge only; models are infra |
| Per-glyph typewriter captions vs fade | Product choice — left as fade-capable CSS |
| Council multi glyph set | Needs face JS state machine work beyond style |
| Token CSS auto-gen test fail-on-drift | Landed 2026-08-01 — `design_tokens_test.rb` now asserts the *committed* `face.css`, `_dialect_tokens.scss` and dialect maps against `design_tokens.yml`. Every drift predicate already existed and every test proved it worked on a tmpdir fixture; nothing checked the real tree, so the generator could go unrun for weeks with a green suite |
| Demo wardrobe seed 6–8 items | Already done and this row was stale — `Amber::AmberDemoSeeder` seeds 17 items and 3 outfits idempotently, covered by `amber/test/lib/amber_demo_seeder_test.rb` |
| Global `/` hotkey search chrome | Landed 2026-08-01 — `/` and `⌘/Ctrl-K` now reach the search on every page of all three apps. bsdports had neither: its `search-hotkey` was a local controller bound to the ports index only, and its layout registered no hotkey controller at all. `feed-hotkey` moved onto the bsdports body (with `hotkeys.*` in en/nb), Cmd/Ctrl-K joined the shared controller, and the local copy is deleted |
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

These are tracked in the repo-root `TODO.md` / `apps.horizon.yml` when they grow past polish.

## How to re-verify

```zsh
ruby RAILS/test/marketplace_cart_contract_test.rb
# After deploy / asset build:
# VISUAL_CAPTURE=1 ruby RAILS/gates/runner.rb visual_contract
```
