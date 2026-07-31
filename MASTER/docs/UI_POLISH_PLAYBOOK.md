# UI polish playbook (family + MASTER)

Authority: `MASTER/data/design_rules.yml` → `ui_polish` + `pixel_perfection`.
RAILS CI ratchets under `RAILS/shared/lib/pub4/*_lint.rb`.
Scan rules: `MASTER/lib/review/scan/rules/surface_rules.rb`.

MASTER (council / fix_loop / aesthetic scan) should **run this playbook**, not
re-invent polish. Never raise lint baselines to silence new debt.

## Order

1. **Flat UI** — strip ornamental `box-shadow` / blur (`GATE_AUTOFIX=1` or
   `gate_autofix#strip_flat_violations`). Prefer border + `var(--surface-elevated)`.
2. **Chrome i18n** — empty titles and search placeholders via `t("empty.*")` /
   `t("search.*")` with nb+en keys. Lint: `chrome_i18n_lint.rb`.
3. **Empty CTAs** — `shared/empty_state` with `action:` or
   `<%# empty_state: no-action-ok %>`. Lint: `empty_state_lint.rb`.
4. **Type tokens** — page headers `font-size: var(--text-title, 1.25rem)` and
   `font-family: var(--font)`. Autofix: raw `20px` → title token.
5. **Space-not-lines** — list/grid cards: no hairline box; gap + elevated surface.
   Forms and bsdports CRT hairlines stay.
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
