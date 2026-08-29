# UI polish playbook (family + MASTER)

Authority: `MASTER/data/rules.yml` → `design_rules.ui_polish` +
`design_rules.pixel_perfection`. RAILS CI ratchets under
`RAILS/shared/lib/pub4/*_lint.rb`. Scan rules:
`MASTER/lib/review/scan/rules/surface_rules.rb`.

MASTER (council / fix_loop / aesthetic scan) should **run this playbook**, not
re-invent polish. Never raise lint baselines to silence new debt.

## Focus triangle

Default scope for polish and product UI work:

1. **brgen** — social shell, ambient chat, channels, Live/nearby
2. **amber** — luxury shell, feed compose, wardrobe CTAs
3. **MASTER web** — face chat (`/`) + mission control; embed host in brgen/amber

Do not expand polish into bsdports or studio unless the task names them. Shared
engine changes must keep all three hosts green (layout tokens, social locales,
comments, master_embed).

### Triangle a11y floor

| Requirement | Where |
|-------------|--------|
| First focusable = skip-link | brgen/amber → `#main-content`; face → `#zin` |
| `main` with `role="main"` + aria-label | all three |
| Interactive chrome ≥ 44px (`--tap-min`) | tab bar, peel, chat tab, face photo/spin |
| `:focus-visible` outline | `_focus_ring.scss` + face.css controls |
| Landmarks i18n | `nav.sidebar|widgets|main|…` (nb/en) |

## Order

1. **Flat UI** — strip ornamental `box-shadow` / blur (`GATE_AUTOFIX=1` or
   `gate_autofix#strip_flat_violations`). Prefer border +
   `var(--surface-elevated)`.
2. **Chrome i18n** — empty titles and search placeholders via `t("empty.*")` /
   `t("search.*")` with nb+en keys. Lint: `chrome_i18n_lint.rb`.
3. **Empty CTAs** — `shared/empty_state` with `action:` or `<%# empty_state:
   no-action-ok %>`. Lint: `empty_state_lint.rb`.
4. **Type tokens** — page headers `font-size: var(--text-title, 1.25rem) <!--
   font_size_title -->` and `font-family: var(--font)`. Autofix: raw `20px` →
   `--line-height` token.
5. **Space-not-lines** — list/grid cards: no hairline box; gap + elevated
   surface. Forms and bsdports CRT hairlines stay.
6. **Verify** — `ruby RAILS/shared/lib/pub4/chrome_i18n_lint.rb`, empty/adhoc
   lints, `layout_suite` / `css_constitution`.

## Dialects (do not flatten)

| App | Type identity | Keep |
|-----|---------------|------|
| brgen | social, body 18px legacy | Inter optional; `--font` |
| amber | luxury Caprasimo display | brand surfaces only |
| bsdports | CRT JetBrains mono | 1px row hairlines |
| MASTER face | CRT flat, radius 0 | face.css tokens |

## Opt-outs

| Marker | When |
|--------|------|
| `<%# chrome_i18n: ok %>` | Deliberate EN string (rare) |
| `<%# empty_state: no-action-ok %>` | Empty with no CTA |
| `<%# adhoc_empty: ok %>` | Free-form empty with CTA nearby |
| pixel_perfection exception comment | Named single element needing depth |

## Commands

```zsh
# Ratchets (CI steps under shared/config/ci.rb)
ruby RAILS/shared/lib/pub4/chrome_i18n_lint.rb
ruby RAILS/shared/lib/pub4/empty_state_lint.rb
ruby RAILS/shared/lib/pub4/adhoc_empty_lint.rb

# Layout / flat UI
GATE_AUTOFIX=1 ruby RAILS/gates/runner.rb layout_suite

# MASTER aesthetic scan (surface rules include ERB_HARDCODED_CHROME)
# via normal review/scan path on RAILS + MASTER/web views
```

## Locale key map (family)

| Key prefix | Use for |
|------------|---------|
| `nav.*` | Primary/sidebar/tab chrome |
| `auth.*` | Sign-in/register/password |
| `empty.*` | `shared/empty_state` titles/bodies |
| `search.*` | Live-search placeholders/labels |
| `pages.*` | Page `<h1>` / `content_for :title` |
| `actions.*` | Empty CTAs and shared action labels |
| `install.*` | PWA install prompt |

When adding a vertical empty or search field: add nb+en keys first, then wire
`t()`, then confirm `chrome_i18n_lint` stays at baseline 0.
