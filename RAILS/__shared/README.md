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
source modules in `RAILS/master/styles/face/` by
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
ruby RAILS/test/design_contract_test.rb
ruby MASTER/tools/rails/build_all_css.rb --check
ruby MASTER/tools/rails/build_face_css.rb --check
ruby MASTER/checks/runner.rb stimulus_components
ruby MASTER/checks/runner.rb frontend_auditor
```
