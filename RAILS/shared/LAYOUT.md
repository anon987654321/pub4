# Family layout contract

MASTER face and all RAILS apps share one **layout chrome** contract. Dialects
(social / luxury / wscons / face CRT) restyle color, type, and radius. They must
not invent a second z-scale, skip-link, tap floor, or main landmark pattern.

Source of truth: `shared/design_tokens.yml` → `shared_chrome` +
`face_root.layout`. CSS: `shared/app/assets/stylesheets/_layout_chrome.scss`
(RAILS), face `:root` generated into `MASTER/web/public/face.css`.

## Focus triangle (active product surface)

Primary product work targets these three only (unless explicitly scoped
elsewhere):

| Surface | Role |
|---------|------|
| **brgen** | City social — feed, channels, ambient chat, verticals |
| **amber** | Luxury wardrobe — outfits, feed compose, soft guests |
| **MASTER web** | Face + mission control at `ai.brgen.no` — embeddable AI |

Shared glue: `pub4-shared` (layout chrome, comments form/row, social locales,
`master_embed`, empty states). bsdports / studio remain maintenance-only unless
named in a task.

Bridge contract: RAILS hosts embed MASTER via `shared/master_embed` +
`master_web_url(autostart:, embed:)`. Face boot rules stay in
`MASTER/web/CLAUDE.md` (primer before WebGL; no three.js at first paint).

Social primitives (shared engine):
- `shared/post_card` — brgen `variant: :card`, amber `variant: :prose`
- `comments/form` + `comments/comment` — capability-aware form/row
- `social.en.yml` / `social.nb.yml` — actions, comments, post, master keys

## Surfaces

| Surface | Body attributes | Main landmark | Chrome |
|---------|-----------------|---------------|--------|
| MASTER chat | `data-layout="face" data-surface="face"` | `#zin` (prompt) | CRT HUD, radius 0 |
| MASTER dashboard | `data-layout="document" data-surface="face"` | `#main-content` | mono panels |
| brgen | `data-layout="document" data-surface="social"` | `#main-content` | app-shell + tab-bar |
| amber | `data-layout="document" data-surface="luxury"` | `#main-content` | app-shell + tab-bar |
| bsdports | `data-layout="document" data-surface="wscons"` | `#main-content` | top nav, CRT tokens |

## Required on every HTML document

1. `viewport-fit=cover` (safe-area aware)
2. First focusable: `.skip-link` → primary content
3. `main` with `id` + `role="main"`
4. CSS vars present (all defined in `_dialect_tokens.scss`, values from
   `design_tokens.yml`): `--chrome-inset` (0.75rem), `--tap-min` /
   `--bar-height` (44px), `--z-canvas`…`--z-skip` (shared ladder), `--safe-*`
5. Interactive primary controls ≥ 44px tall
6. No second box-shadow elevation language (flat UI); face popover exception
   only

## Shared primitives

- `.skip-link` — hard-hidden until `:focus-visible`, corner at chrome-inset +
  safe-area
- `.page-header` — title + optional actions, measure-capped
- `.app-shell` / `.layout` — document column (RAILS); face uses full-viewport
  canvas
- `main#main-content` — page gutter via `--page-gutter` unless inside `.layout`

## What may diverge

- Color dialect and radius (face/wscons = 0; social soft; luxury warm)
- Presence of tab-bar vs top nav vs face HUD
- Font stack (Inter / mono / Caprasimo / Arial verticals)

## Verify

```zsh
ruby RAILS/test/layout_contract_test.rb
ruby RAILS/tools/generate_face_root_css.rb   # face :root sync
ruby RAILS/tools/build_all_css.rb --check
```
