# Shared Rails engine

**One engine carries the grammar every surface speaks, so that brgen, amber,
bsdports and the MASTER face feel like one family in four dialects, and so that a
rule written once holds on every screen.** It is the `pub4-shared` gem: layout
chrome, accessibility defaults, social primitives, a service worker and a
vendored set of Stimulus components. The apps mount it by local path.

The design values do not start here. They are declared in `MASTER/data/tokens.yml`,
and the `design_tokens.yml` beside this README is a file generated from it by
`MASTER/tools/rails/sync_dialect_tokens.rb`. Edit the source and regenerate, and
never hand-edit the projection. MASTER's browser face is assembled from ordered
source modules in `MASTER/web/styles/face/` by
`MASTER/tools/rails/build_face_css.rb`; edit those modules rather than the public
bundle. Its `:root` block is still generated from the canonical tokens.

Every HTML document in every surface shares one chrome contract. The viewport
covers the safe area, the first focusable element is a skip link to the main
content, the `main` element has an id and its role, and primary controls are at
least as tall as the tap minimum. Dialects restyle colour, type and radius. They do
not invent a second z-scale, a second skip link or a second tap floor. The
interface is flat: no shadows, blurs or hairline rules, and separation is space.
The one exception left is the outline of a form field, because an input with no
outline gives no target.

The dialects are deliberate. brgen and its verticals wear a grayscale called
brgen_old, with a per-vertical accent. Amber wears warm paper and its own editorial
faces. BSDPorts is an ultra-minimal white search surface inspired by the classic
Google front page: Arial, blue result links, neutral grey metadata, and compact,
flat geometry. Its `wscons` body class remains a compatibility hook for flat and
square shared-component rules; it does not define a dark palette. The face is black
with lavender, square, in a monospace. The theme is one mechanism everywhere:
shared `theme_toggle` and `theme_bootstrap` partials write the theme onto the
document element, and the stylesheets read it from there. Declared is not worn, so
read the built bundle before you describe what an app paints. The typeface is the
same family in every app, and a fifth face is a decision and not an accident.

Three of those decisions have been taken, on the operator's word (2026-10-29 and,
delegated, 2026-10-31), and are recorded so that no one reopens them as drift:

- The commerce surfaces, markedsplass and takeaway, wear the store dialect measured
  from bol.com and Kaufland.de, because the marketplace competes at that class. It
  keeps their 1px field and tile rules, their corner radii and the commerce sans
  (`--font-commerce-sans`, a Helvetica Neue stack). That is the named exception to
  "flat, no hairline rules" and to the one family, scoped under
  `body.vertical-marketplace`. It does not travel to any other surface.
- That dialect is two layers in brgen's stylesheet, the Kaufland `--store-*` rules
  and the later bol `--bol-*` rules. Where both set one property the later layer
  wins, so a rule meant to hold in both is written in the bol layer. The category
  grid showed five tiles beside a column sized for four for exactly that reason.
- Motion that is the operator's own design ships as designed, with its library
  vendored and a still state for reduced motion and for no script: dating's first
  screen (a css-doodle heart over a red bloom, the one gradient on a dark ground),
  the marketplace's animated logo (anime.js) and brgen's in-feed collage ad.
  Amber's affiliate rail stays the calm catalogue.

Each app compiles one stylesheet, `application.scss`, into one built
`application.css`, and a layout links that file and nothing else. The brgen
verticals style themselves inside brgen's, scoped under their vertical class. The
app begins by loading the engine's `stack`, which forwards the minimal base, the
tokens, the animations, the buttons and the components, and then writes its own
rules below. The button partial's position is a cascade contract and not an
ordering convenience.

On the Ruby side the engine holds the concerns that models and controllers share:
reactions, votes, comments, notifications, activity tracking, geolocation, strict
safe associations, live search and attachment limits. Strict loading is on in every
environment, so a method that writes first and then reads a lazy association can
commit the write and then raise. The safe-association helpers exist for paths where
a lost notification is worse than an extra query, and they are not a licence to
skip preloading. The engine also owns the password mailer, the mailer layout and
the fingerprints controller. Framework-required host constants stay in each app as
thin wrappers, because routing and the autoloader resolve them by bare name.

On the JavaScript side, `frontend/hotwire.js` and `frontend/stimulus_boot.js` are
the entry points. The Stimulus components are vendored, never fetched from a CDN,
and the stimulus components check holds that line. Plain HTML must work without
scripts, so every live search ships server-rendered content and its loading, empty
and error states. Toggles answer with a redirect, and Turbo's morphing refresh makes
that cheap.

Some decisions are recorded so that no one reopens them. An agent may not choose or
change a rendered value: a colour, a radius, a breakpoint or a layout belongs to
the operator. The agent may add a token that holds an existing value, add a check, or
repair an ambiguity, and then must say so in the commit. Pages that carry
per-viewer chrome are never cached for everyone. Nothing is preloaded or
pre-connected beyond what is there, because the box has one core and 1 GB. Findings
against the design system are often findings against the instrument, so check what a
number measured before you believe it.

The surveys of past UI work sit beside this file: the layout and surface refinement
matrices, the social front page and the two archaeology notes. They are records, not
contracts. The three `*_micro_refinements*.scss` sheets are intentionally excluded
from both production stacks until each proposed change has rendered before/after
evidence and explicit operator approval. A count of CSS declarations is not a quality measure.

## Vipps brand assets

The shared engine carries two official Vipps wordmarks for the apps that use
its payment and login surfaces:

- `app/assets/images/vipps/vipps-wordmark.svg`: orange wordmark for light
  backgrounds, sourced from the
  [Vipps WooCommerce merchant plugin](https://github.com/vippsas/vipps-woocommerce/blob/052b7fd57365ec9c68e91a7b60df7af210bb61d2/payment/img/vipps-rgb-orange-pos.svg).
- `app/assets/images/vipps/vipps-wordmark-on-orange.svg`: white wordmark on
  the Vipps-orange block, sourced from the
  [negative merchant wordmark](https://github.com/vippsas/vipps-woocommerce/blob/052b7fd57365ec9c68e91a7b60df7af210bb61d2/payment/img/vipps-rgb-orange-neg.svg).

Both are retained unmodified. Do not recolour or stretch them; replace them
with the restaurant or merchant's supplied brand-kit files when the applicable
merchant agreement provides them. Mr. Damascy is not on this shared engine and
keeps its own wordmark copy.

## External page extraction

`Shared::Scrape` is an outbound-network boundary, not just a browser helper. It accepts
public HTTP(S) entry URLs only, refuses local/private/reserved address ranges and hostnames,
and rechecks every browser request so redirects and embedded resources cannot point at
loopback or cloud metadata. DNS answers containing even one blocked address are refused.
This application guard complements host-level egress/firewall policy; it is not a substitute
for it. The public/private target contract is tested in
`RAILS/brgen/test/services/shared_scrape_test.rb`.

## Checking it

```zsh
ruby RAILS/test/layout_contract_test.rb
ruby RAILS/test/layout_contract_surfaces_test.rb
ruby RAILS/test/design_contract_test.rb
ruby RAILS/test/design_contract_components_test.rb
ruby MASTER/tools/rails/build_all_css.rb --check
ruby MASTER/tools/rails/build_face_css.rb --check
ruby MASTER/checks/runner.rb stimulus_components
ruby MASTER/checks/runner.rb frontend_auditor
```
