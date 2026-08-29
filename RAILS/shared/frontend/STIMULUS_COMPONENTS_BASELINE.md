# Shared Stimulus Components baseline

Recovered from `DEPLOY/rails/shared/frontend/STIMULUS_COMPONENTS_BASELINE.md`,
deleted at `ee3a56e33`. Unlike the amber architecture record, this one did
**not** survive verbatim — the install shape it prescribed is now a gate
failure. What follows is the current contract; the divergences are listed at the
end so the old text is not restored by someone who finds it in history.

Enforced by `Deploy::StimulusComponentsGate`
(`RAILS/gates/lib/source/stimulus_components.rb`), run as `ruby
RAILS/gates/runner.rb stimulus_components`. That class is the source of truth.
This document explains it; it does not redefine it.

## Packages are vendored, not fetched

All 19 `@stimulus-components/*` packages live in `shared/vendor/javascript/` as
`@stimulus-components--<name>.js` and pin to those local files through
`shared/config/importmap_baseline.rb`. The gate fails if the baseline stops
pinning `vendor/javascript`, and fails on any vendored file under 100 bytes — an
empty vendor file pins successfully and breaks only at runtime.

Vendored: `animated-number`, `auto-submit`, `carousel`, `character-counter`,
`checkbox-select-all`, `clipboard`, `content-loader`, `dropdown`, `hotkey`,
`lightbox`, `notification`, `password-visibility`, `popover`,
`rails-nested-form`, `read-more`, `reveal`, `sortable`, `textarea-autogrow`,
`timeago`.

**Do not reintroduce CDN pins for these.** `pin` defaults to `preload: true`, so
every pin emits a `modulepreload` and the browser fetches it eagerly on first
paint — seven CDN pins once cost brgen 537 requests per page load and left Turbo
undefined. Any dynamic `import()` behind a preloaded pin is decorative.

The two CDN pins that remain are deliberate and documented in place:
`@rails/request.js` from jsDelivr (its ESM build uses extensionless relative
imports that a browser cannot resolve; the `dist` bundle can), and brgen's
Tiptap pair from esm.sh at `preload: false`.

## Registration

`shared/frontend/stimulus_boot.js` registers the controllers. The gate requires
these names to appear in it: `password-visibility`, `nested-form`,
`rails-nested-form`, `carousel`, `character-counter`, `checkbox-select-all`,
`dialog`, `read-more`, `textarea-autogrow`.

**The gate fails on two of those today, for different reasons.** It looks for
the quoted string `"rails-nested-form"`; the boot file imports
`@stimulus-components/rails-nested-form` and registers it under the short name
`nested-form` (`stimulus_boot.js:17`, `:66`), so the package is wired and the
check still misses it — an instrument fault, not a wiring gap. `dialog` is a
real gap: nothing is vendored under that name and nothing registers it.
Resolving these means either vendoring `dialog` and matching the gate to the
registered spelling, or narrowing `REQUIRED_BOOT`. Until then this gate is red,
and a red gate that nobody can make green gets ignored.

`shared/frontend/stimulus_components.js` is deprecated and the gate fails if the
file reappears. The old document pointed at it as the ESM bootstrap for
non-importmap apps; there are no such apps.

## Forbidden

The gate scans every `.erb`/`.html` under `RAILS/` outside `vendor/`,
`public/assets/` and `node_modules/`, and fails on the legacy char-counter
markup: `data-controller="char-counter"`, `controller: "char-counter"`,
`char-counter-max-value`, `data-char-counter-target`. Use the vendored
`character-counter` component instead.

Per-app copies of shared controllers are also failures:
`char_counter_controller.js`, `textarea_autogrow_controller.js`,
`stimulus_rails_nested_form_controller.js` under any app's
`app/javascript/controllers/`. Compose, autosave, draft-store, media-picker and
scroll-reveal controllers live in `shared/frontend/` for the same reason; the
per-app copies in amber and brgen were removed.

## Progressive enhancement

Plain HTML must work without JavaScript. Every live search and async interaction
ships server-rendered initial content, plus loading, empty, no-results and error
states, with keyboard-operable controls. `journey_invariant` measures the no-JS
landmark parity in a real browser; `page_simulation` covers the state pages.

## Rails 8 defaults

Turbo Frames for replaceable panels, Turbo Streams for live updates, Solid Queue
for expensive work, Solid Cable for real-time status, Solid Cache for
index/feed/card/search fragments, Active Storage for media, signed IDs for
user-facing action tokens.

## What changed since the deleted version

- **Install shape.** The old text prescribed `esm.sh` pins for eleven packages.
  All are vendored now, and restoring those pins reintroduces the preload
  problem.
- **`stimulus_components.js`.** Named as the bootstrap for "direct module apps";
  now a gate failure if present.
- **Component list.** The old list of 19 packages to standardize on was a wish
  list. The vendored set is the real one, and the nine names in the gate's
  `REQUIRED_BOOT` are the enforced subset. `sound` and `speech-recognition` were
  on the wish list and are not vendored.
- **Rollout order.** It sequenced Blognet, Baibl and Hjerterom after the three
  real apps. Those are horizon entries in `apps.horizon.yml`, `agent: ignore`.
- **Scope.** `DEPLOY/rails` no longer exists; this applies to `RAILS/`.
