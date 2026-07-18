# UI refinement proposals — MASTER web face + Rails app layouts

A grounded backlog of concrete, mostly-small refinements. Scoped to what
already exists: the MASTER particle-face web UI (`MASTER/web`), the brgen social
feed + verticals, amber's luxury wardrobe, and bsdports. Anchored to real tokens
(`RAILS/shared/design_tokens.yml`, `MASTER/web/public/face.css`) and components.

Each item is independently actionable — check them off or discard. They are
proposals, not decisions; some conflict on purpose (pick a direction). Grouped
by surface, then by cross-cutting concern.

Legend: **[S]** small/safe · **[M]** medium · **[L]** larger/needs decision ·
**[a11y]** accessibility · **[perf]** performance · **[copy]** wording.

_Drafted: 2026-07-18._

### Applied so far

**brgen shell — polish pass slice 1 (2026-07-18):** behavior-preserving,
structurally validated (no local boot — Ruby mismatch).

- §C.42 / §N.121 — **theme FOUC fixed:** inline parse-time restore of the
  `#dark-toggle` checkbox in the layout, before `.theme-root` paints; reuses the
  existing `:checked ~ .theme-root` CSS path (no token-mismatch risk).
- §C.32 / §G — **nav swiper a11y:** closed drawer links now leave the tab order
  (delayed `visibility`), grip gets `aria-controls="nav_sections"` + a
  `:focus-visible` ring, active link gets `aria-current="page"` (state no longer
  color-only). _Not yet: full `tablist`/`tab` roles._
- §K.107 — **tabular numerals** on `.x-count` + `.x-time` so feed counts and
  timestamps stop jittering as Turbo updates them.

**brgen — polish pass slices A–E (2026-07-18):** behavior-preserving,
structurally validated (braces/ERB balanced; no local boot — Ruby mismatch).

- **A · a11y floor** — `--focus-ring` token + a specificity-0 `:where(...)
  :focus-visible` floor in `_root.scss` (fills every gap without overriding
  existing focus styles); vote button gained `aria-pressed` (state no longer
  color-only). _Deferred (needs JS+browser): splash/bottom-sheet focus-trap,
  live aria-live toast dedup._
- **B · per-vertical identity** — `_vertical_shell.scss` accent map overrides
  `--x-accent` per `body.vertical-*` (cascades to buttons/votes/links/focus),
  aligned to each vertical's existing brand token (dating teal, maps blue, tv
  red); covers dark + light. (marketplace already had serif + warm-CTA identity.)
- **C · fonts + media perf** — self-hosted Inter (400–800) + Libre Baskerville
  (400/700/400i) as latin-subset woff2 in `public/fonts/` via `_fonts_brand.scss`
  (local→self-host→CDN-fallback pattern, `font-display: optional`); **all Google
  Fonts links removed** (layout + dating home); per-surface `preload`;
  `content-visibility: auto` on off-screen feed cards.
- **D · empty states** — coverage was already strong; added authored + CTA empty
  states for community feed and marketplace category (NO_DEAD_ENDS). _Skeletons
  deferred (Turbo loading-state work)._
- **E · motion** — tactile `:active` press-punch on `.x-act`; kept deliberately
  minimal (restraint per design philosophy — over-animation reads as generated).

Not yet started: broader focus-ring rollout audit of `outline:none` sites,
tv/takeaway per-component treatments, self-host remaining CDNs (maplibre,
css-doodle — `TODO.md §4`).

### Governing principles (from MASTER's constitution)

Every item here is subordinate to MASTER's law (`MASTER/data/soul.yml`), the
design vision, and the conventions. In order of authority:

- **`PRESERVE_THEN_IMPROVE_NEVER_BREAK` / `PRESERVE_FIRST`** — these refine
  working UI; none rewrites a component from scratch or changes behavior. Read
  the component first.
- **Collapse over accretion** — prefer consolidating (one token scale, one field
  style, one avatar) over adding chrome. When two items conflict, the one that
  removes surface wins. Cut one accessory before shipping.
- **Flat, not beveled** (IRIX reskin, `design_tokens.yml`) — elevation is
  borders, never `box-shadow`; radii come from tokens (social soft, MASTER/
  bsdports zero). No item reintroduces bevels or drop-shadows.
- **Snøhetta parametric/timeless** — choices derive from tokens and the subject's
  own material (a city feed, a wardrobe, a ports index), not decoration.
- **MASTER-web invariants win** — the boot contract in `web/CLAUDE.md` and
  `AGENTS.md` "Do not touch" override any §B suggestion (see §B header).
- **Prove completion** (`anti_simulation`) — anything checked off here ships with
  its diff/command output, not a claim.

---

## A. Design-system / tokens (cross-cutting)

1. **[M]** Four token dialects live in `design_tokens.yml` (`social`, `luxury`,
   `light`, `openbsd_wscons`, `face_root`) with overlapping keys (`x_bg`,
   `x_accent`…). Document which app consumes which dialect at the top of the
   file — right now the mapping is implicit.
2. **[S]** `social` and `luxury` both define a spacing scale but with different
   step names (`space_xs…2xl` vs none in `social`). Unify on one scale token
   set so shared components spaced identically across apps.
3. **[S]** Add a `space_2xs` (0.25rem) — several dense UIs (nav swiper, HUD
   tiers) need a sub-`xs` step and currently hardcode `2px`/`4px`.
4. **[M]** Promote the luxury type scale (`font_size_display…meta`) into a
   shared modular scale (e.g. 1.25 ratio) and have brgen/bsdports opt in, rather
   than each app inventing sizes.
5. **[S]** `social` radii go `xs 4 / sm 8 / md 12 / card 16` but `face_root`
   pins every radius to `0`. Name the intent: "social = soft, face = CRT-flat"
   in a comment so nobody "fixes" the zeros.
6. **[M]** Introduce semantic color aliases (`--color-danger`, `--color-success`,
   `--color-warning`, `--color-info`) per dialect; today only `danger` exists,
   so success/warning states are ad-hoc.
7. **[S]** Add a focus-ring token (`--focus-ring: 2px solid var(--x-accent)`)
   and use it everywhere instead of per-component `outline` values — makes the
   a11y floor consistent (see §G).
8. **[S]** Define an elevation scale as **borders**, not shadows, for the flat
   IRIX theme (`--elev-1: 1px solid var(--x-border)` …) so "flat" stays
   enforceable and grep-able.
9. **[M]** Generate the light-mode palette from the dark one via `color-mix`
   deltas where possible, so the two stay in lockstep instead of drifting.
10. **[S]** Ship a token contract test (extend `generate_face_root_css.rb`) that
    fails if `face.css :root` and `design_tokens.yml` `face_root` disagree — the
    file already warns "keep in sync" by hand.
11. **[M]** Add per-vertical accent tokens for brgen (marketplace warm, dating
    warm-red, playlist, tv) so verticals feel distinct without one-off CSS.
12. **[S]** Standardize one motion token set (`--transition-fast/normal`,
    `--ease-*`) — `face_root` has them; `social`/`luxury` don't. Export to all.

## B. MASTER web face (`ai.brgen.no`)

The signature is the WebGL phosphor particle face on black, monospace HUD,
zero-radius. Keep that thesis; refine around it.

> **Hard constraints — read `MASTER/web/CLAUDE.md` before any §B change.**
> The boot contract is load-bearing: **no WebGL context and no THREE.js parse
> before the primer tap** (`AGENTS.md` "Do not touch #4"); the prompt must
> appear even if the face fails; `MASTER_FACE` / `MASTERChat.startChatStream()`
> stay canonical. And the VPS is 1 vCPU / ~1 GB running four apps — every §B
> idea must be cheap, deferred, and reduced-motion aware. Nothing here overrides
> those invariants; anything that appears to, is wrong.

13. **[S]** The primer overlay ("tap to start") is the true first paint — style
    it as the thesis: a faint CSS phosphor glow + the wordmark in mono, so the
    pre-tap screen already reads as MASTER, not a blank black hold.
14. **[S][perf]** Preload **only** the pre-primer-safe assets (the 2D
    `cognition_ecology*.js` ecology layer, `particle_kernel.js`) — never
    `three.face.module.js` or `face.js`, which are forbidden before the tap.
    Keep the heavy path lazy exactly as the boot manifest requires.
15. **[M][a11y]** The particle face carries state (mood/accent). Mirror that
    state in an `aria-live` text region ("thinking", "speaking", "listening")
    so screen-reader users get the same signal sighted users get from color.
16. **[S]** HUD tiers (`hud-tier-status`, `hud-tier-caption`) stack from the
    bottom bar — give each tier a hairline top border (`--border-faint`) so they
    read as distinct strata against the black, not floating text.
17. **[M]** Voice Mode has three states (armed / listening / speaking). Give
    each a distinct, minimal glyph in the bar (not just color) — a filled dot,
    concentric rings, a waveform — so the mode is legible at a glance.
18. **[S][copy]** Audit HUD microcopy for the interface voice: system states
    should be verbs the user recognizes ("Listening", "Muted"), never internal
    names ("tts_socket ok").
19. **[M]** Caption tier: cap line length (~66ch) and animate captions in as a
    single fade, not per-glyph, unless the per-glyph "typewriter" is a
    deliberate signature — pick one and make it consistent.
20. **[S]** The bottom bar is `44px` (`face-bar-height`) — ensure every tap
    target inside it meets 44×44 including padding, not just the icon glyph.
21. **[M]** Add a subtle scanline / phosphor-decay vignette **only** at the
    canvas edges so the face reads as "on a CRT" — reinforces identity without
    touching the particle budget (respect the additive-blend budget note in
    tokens: don't raise size/glow/decay together).
22. **[S][perf]** Gate the WebGL primer behind `prefers-reduced-motion` and
    `save-data`; fall back to `face_2d_fallback.js` (already present) with a
    static glow. Confirm the 2D path is visually intentional, not degraded.
23. **[M]** The chat input on black: give it a single hairline top border and a
    blinking block caret (monospace terminal idiom) instead of the browser
    default caret — commits to the CRT thesis.
24. **[S]** Show token/cost or latency as an ambient, dim right-aligned readout
    in the status tier (the runtime already tracks costs via `reset-costs`) —
    turns a hidden number into part of the aesthetic.
25. **[M]** Council-multi view (`face_council_multi.js`): label each voice with
    a fixed monospace tag + color-mix tint so multiple proposers are
    distinguishable at a glance; avoid relying on position alone.
26. **[S][a11y]** Ensure the black canvas has a `role="img"` + `aria-label`
    describing the face, and that keyboard focus never gets trapped on it.
27. **[M]** Boot FSM (`boot_fsm.js`): expose the boot stages as a thin
    bottom-edge progress hairline that fills left→right, so a slow primer reads
    as progress, not a hang.
28. **[S]** Error pages (`400/404/422/500` in `web/public`) should share the
    face's black+mono identity, not a default Rails look — verify and align.
29. **[M][copy]** The unsupported-browser page (`406-unsupported-browser.html`)
    should say what to do ("Open in Safari or Chrome"), in the interface voice,
    with the one working action — not just "unsupported".
30. **[S]** Give the "Enable notifications" / permission prompts a consistent
    monospace, zero-radius button style matching the bar, not native chrome.

## C. brgen — social feed + shell

x.com-derived three-column shell, IRIX flat dark, horizontal **nav swiper** as
primary nav (per project convention), city carousel, vertical sub-apps.

31. **[M]** The nav swiper is the signature — make the active pane unmistakable:
    a 2px accent underline (`--x-accent`) + weight bump, and a peek of the
    neighbor panes at the edges so swipeability is discoverable without a hint.
32. **[S][a11y]** Nav swiper needs keyboard + screen-reader parity: arrow-key
    navigation, `role="tablist"`/`tab`, `aria-selected`, and a visible focus
    ring on each pane. Swipe alone excludes keyboard users.
33. **[S]** City carousel (`#cityCarousel`) is `aria-hidden` and auto-rotating —
    good, but pause it on `prefers-reduced-motion` and when the tab is hidden
    (Page Visibility) to save cycles.
34. **[M]** Give the city carousel a purpose beyond decoration: make each slide
    a real switch to that city's subdomain (it lists `brgen.no`, `oshlo.no`…) —
    "structure is information", so the list should *do* something.
35. **[S]** Post card: establish one vertical rhythm — avatar, author + meta,
    body, media, action row — with a single `--space-sm` gutter, so cards read
    as one system across verticals.
36. **[M]** Action row (vote/comment/share): align to a 44px touch grid, use
    `currentColor` icons that inherit hover tint (`--x-hover`), and animate the
    vote with a single 180ms scale-punch (respect reduced-motion).
37. **[S][perf]** `reading_time_minutes` is computed and shown — render it as a
    quiet meta chip (`· 3 min`) not a badge; it's context, not a CTA.
38. **[M]** Feed compose (FB-style expand-on-tap): the collapsed state should be
    a single-line "What's happening in {city}?" that expands to the minimal RTE
    on focus — confirm the collapsed height doesn't shift layout on expand
    (reserve space or animate height).
39. **[S][copy]** Compose placeholder should name the city/vertical context
    ("Post to Marketplace", "Share with Bergen") rather than a generic prompt.
40. **[M]** Splash (`yield :splash`) dialog: give it the brgen serif display
    (Libre Baskerville is already loaded for marketplace) for the wordmark, then
    hand off to the sans body — makes the first impression typographic, not a
    logo drop.
41. **[S]** Theme toggle is a checkbox+SVG sun — add a matching moon state and a
    150ms cross-fade; store per-app (`brgen-theme`) — already wired, verify no
    flash-of-wrong-theme on load (inline the theme read in `<head>`).
42. **[M][perf]** Inline a tiny `<script>` in `<head>` that sets
    `data-theme` from `localStorage` before first paint to kill the
    light/dark flash (FOUC) — the toggle persists but initial paint may flash.
43. **[S]** Nearby-alerts + match-overlays are `aria-live` permanents — cap
    their z-index below modals and give toasts a consistent flat card style
    (`--x-surface-elevated`, 1px border, `--x-radius-sm`).
44. **[M]** Marketplace uses Libre Baskerville; give it a distinct accent + card
    treatment (product microdata is already there) so it reads as a storefront,
    not the social feed with products in it.
45. **[M]** Dating home loads `css-doodle` + Inter — lean into a warmer accent
    token and a full-bleed swipe-card stack; ensure the swipe card meets the
    44px action targets and has keyboard like/pass buttons.
46. **[S]** Playlist embed player: give the scrubber and play control the
    accent color and a focus ring; ensure it works in the `playlists#embed`
    iframe context (no reliance on parent CSS).
47. **[M]** TV: channel/video cards want a 16:9 poster with a consistent
    duration chip (bottom-right, `--space-2xs` inset, mono digits) and a live
    dot for broadcasts — small, repeatable, recognizable.
48. **[S]** Takeaway: menu-item availability has a state machine — reflect
    "sold out" with a muted card + a text badge, never color-only (a11y).
49. **[S][a11y]** Maps home loads MapLibre — ensure the map has a text
    fallback/list view for keyboard + no-JS, and that focus can reach the
    Places list without the map trapping it.
50. **[M]** Global `/search` (FTS5) — give it a single prominent search field in
    the shell with a `/`-to-focus hotkey (the app already has `feed-hotkey`);
    results should be typed (posts / listings / people) with clear group labels.
51. **[S][copy]** Empty search: "No results for '{q}' in {city}. Try a broader
    term or switch city." — direction, not a dead end.

## D. amber — luxury wardrobe

Warm-neutral luxury palette (Aesop/Toteme-inspired), edge-swiper sidebar +
widgets, swiper carousels, full-bleed logo banner.

52. **[M]** Commit to the luxury thesis harder: increase the base line-height to
    `line_height_relaxed` (1.6) for body, widen `letter_spacing` on the display
    (Caprasimo), and let whitespace (`space_xl/2xl`) carry the calm — luxury is
    precision in spacing, not more elements.
53. **[S]** The logo banner is `100vw` full-bleed sticky — give it a hairline
    bottom border (`light_border`) so it separates from content when scrolled.
54. **[M]** Wardrobe item cards: shift from a generic grid to an editorial
    layout — larger hero item, smaller supporting items — so the wardrobe reads
    as a curated lookbook, not a CRUD list.
55. **[S]** Item photo placeholders (`item-photo--placeholder` showing the
    category initial) — style them as a warm-neutral tile with the category name
    in small caps, not a bare letter; makes empty states feel intentional.
56. **[M]** The swiper carousels (`wardrobe-swiper`) now use the vendored
    swiper CSS — set `slidesPerView: auto` with a peek + snap, and give slides a
    consistent aspect ratio so the rail reads as designed, not clipped.
57. **[S][a11y]** Edge-swiper sidebar/widgets grips: they're `<button>` with
    `aria-expanded` — good; add a visible focus ring and ensure Escape closes
    the opened panel and returns focus to the grip.
58. **[S]** Give amber a light-mode-first default (tokens say light is preferred
    for "calm product viewing") but keep the dark toggle — verify the default
    matches the stated intent.
59. **[M]** Outfit suggestion + AI search views: present results as a
    horizontal look-rail with the occasion as an eyebrow label, and use the
    warm accent (`light_accent` taupe/gold) only on the primary action.
60. **[S][copy]** amber compose/search placeholders are already good and
    specific ("something warm but not bulky for a meeting") — extend that
    specific, human voice to empty states and button labels ("Plan an outfit",
    not "Submit").
61. **[M]** Sustainability score (there's a `CalculateSustainabilityJob`):
    visualize it as a small warm meter or a single letter grade with a text
    label, consistent with the calm palette — not a loud gauge.
62. **[S]** Demo wardrobe (guest) should feel like a styled sample, not empty
    scaffolding — seed 6–8 real-looking items and let the swiper show motion on
    load so first-time visitors see the product working.

## E. bsdports

Utility search app — different register: fast, dense, terminal-adjacent.

63. **[M]** Lean into the `openbsd_wscons` green-terminal dialect for bsdports
    (it fits ports/advisories) — monospace, green-on-black, zero-radius — so it
    has its own identity distinct from brgen/amber instead of a neutral default.
64. **[S]** Search results: dense monospace rows, port name + version + one-line
    description, with the advisory state as a colored text tag (not a pill).
65. **[S][perf]** Make search-as-you-type debounce and show a subtle inline
    spinner in the field, not a full-page reload feel.
66. **[S][copy]** Advisory empty/clean state: "No open advisories for {port}."
    — reassuring and specific.
67. **[S][a11y]** Ensure the green-on-black meets contrast (`#63c363` on
    `#000` is ~7:1 — good; verify secondary `#3d7a3d` which is ~3:1 and may fail
    for body text — reserve it for non-essential meta only).

## F. Shared layout, navigation, Stimulus

68. **[M]** Define one canonical page frame (skip-link → header → main → nav) in
    the shared engine and have all three apps compose it, so `#main-content`,
    landmarks, and skip-link exist identically everywhere.
69. **[S][a11y]** Every app has a skip-link — verify it's the first focusable
    element and visibly appears on focus (not just present in DOM).
70. **[S]** Standardize the toast/flash component in `shared/frontend/` (flat
    card, 1px border, auto-dismiss with pause-on-hover, `aria-live`) — replace
    per-app flash markup.
71. **[M]** Shared `scroll_reveal_controller` — cap it to one subtle
    translateY+fade, gate on `prefers-reduced-motion`, and never reveal
    above-the-fold content (it should animate in on scroll, not hide the hero).
72. **[S]** `media_picker` / upload controllers: show a real thumbnail preview +
    filename + remove button on select, and a determinate progress bar on
    upload — shared, so all three apps match.
73. **[S]** `autosave` / `draft_store`: surface a quiet "Saved" / "Draft kept"
    micro-status near the compose action, in the interface voice, so users trust
    it. Never a modal.
74. **[M]** Bottom-sheet controller (brgen body uses it): standardize the
    handle, the backdrop scrim opacity, the drag-to-dismiss threshold, and
    focus-trap behavior across any app that adopts it.
75. **[S][a11y]** All icon-only buttons (theme toggle, grips, nav) need
    `aria-label`s and 44px hit areas — audit shared partials once, fix once.

## G. Accessibility floor (applies everywhere)

76. **[S]** One visible focus style, from the `--focus-ring` token (§A.7), on
    every interactive element — audit for `outline: none` with no replacement.
77. **[M][a11y]** Never encode state in color alone: votes, availability,
    advisory severity, online dots, live badges all need a text/glyph companion.
78. **[S]** Verify color contrast for every `*_text_secondary` token against its
    surface — several muted tokens are borderline AA for body text; restrict
    them to large text or non-essential meta.
79. **[S]** Ensure all images (post media, wardrobe items, TV posters) have
    meaningful `alt` or `alt=""` when decorative — and that placeholders aren't
    announced as content.
80. **[S]** Modals/sheets/overlays (splash, bottom-sheet, edge-swiper panels):
    focus-trap while open, Escape to close, focus returns to trigger.
81. **[S]** `aria-live` regions (nearby-alerts, match-overlays, toasts) should
    be `polite` and deduplicated so a burst of events doesn't spam the SR.
82. **[M]** Provide a global "reduce motion" respect audit: particle face, city
    carousel, scroll-reveal, vote punch, swipe animations all honor
    `prefers-reduced-motion` — one checklist, verified per surface.
83. **[S]** Ensure `lang` is set correctly (brgen sets it from `Current.locale`)
    and that RTL is at least not broken for future locales (`dir` is hardcoded
    `ltr` — note it as a known constraint).

## H. Performance & perceived performance

84. **[S][perf]** Self-host fonts (Libre Baskerville, Inter, Caprasimo) to kill
    the Google Fonts round-trip + the render-blocking `@import`; `display:
    optional` is already set — pair with `preload` on the woff2.
85. **[M][perf]** Vendor or documented-exception the remaining CDNs (maplibre,
    css-doodle) per `TODO.md §4`, so the critical path has no third-party host.
86. **[S][perf]** Add `content-visibility: auto` + `contain-intrinsic-size` to
    off-screen feed cards and wardrobe tiles to cut layout/paint on long lists.
87. **[S][perf]** `loading="lazy"` + explicit `width`/`height` (or aspect-ratio)
    on all media so long feeds don't reflow as images arrive (the app already
    has responsive_image_tag + blurhash — confirm dimensions are emitted).
88. **[S][perf]** Use the existing blurhash as the `background` of the image
    frame so the LQIP shows instantly and swaps without a flash.
89. **[M][perf]** Defer non-critical JS (lightgallery, swiper init, css-doodle)
    until interaction/idle; the shell should be usable before they load.
90. **[S][perf]** Ensure `stylesheet_link_tag "application"` isn't shipping every
    vertical's CSS to every page — split by vertical or use
    `content-visibility`-friendly critical CSS inline for the shell.
91. **[S][perf]** Add `fetchpriority="high"` to the LCP image (splash wordmark /
    hero) and `preconnect` only to origins actually used per page.

## I. Motion & micro-interaction

92. **[S]** One shared easing vocabulary (`--ease-spring` for enter,
    `--ease-out` for exit) — apply consistently so motion feels authored.
93. **[S]** Vote/like: a single 180ms scale-punch + color fill, no bounce loop.
94. **[S]** Nav-swiper pane change: momentum snap + a 120ms underline slide to
    the active pane — the underline is the through-line of the whole nav.
95. **[S]** Compose expand: animate height + opacity together (200ms) so the
    RTE grows in place instead of popping.
96. **[S]** Toast enter/exit: slide+fade from the same edge; pause timer on
    hover/focus.
97. **[S]** Avoid ambient/idle animation except the MASTER face (its signature)
    and the paused-on-hidden city carousel — everywhere else, motion responds to
    input. Extra ambient motion reads as AI-generated.

## J. Mobile, touch & PWA

98. **[S]** All three apps set `viewport-fit=cover` — verify `env(safe-area-
    inset-*)` padding on sticky headers, bottom bars, and the MASTER HUD tiers
    (tokens already reference `--safe-bottom`).
99. **[S]** Minimum 44×44 touch targets on every control — nav swiper panes,
    action rows, grips, carousel controls.
100. **[M]** Confirm the offline page (`/offline`, shared partial) carries each
     app's identity and offers the one useful action ("Retry", "Go to saved") —
     not a generic "you're offline".
101. **[S][copy]** PWA install: if you prompt, say what installing gives them
     ("Add Brgen to your home screen for faster access"), and only prompt after
     engagement, never on first paint.
102. **[S]** Themed `theme-color` per app + per light/dark (brgen already sets
     `data-light-color`/`dark-color`) — verify amber/bsdports match their
     surfaces so the OS chrome tints correctly.
103. **[S]** Ensure tap highlight is intentional (`-webkit-tap-highlight-color`)
     — either the accent tint or transparent with a custom `:active` state, not
     the default grey box.
104. **[M]** Pull-to-refresh vs. swipe-nav conflict: the brgen nav swiper is
     horizontal, so vertical PTR should be fine — but verify the edge-swipe
     panels (amber) don't fight the browser back-gesture on iOS.

## K. Typography

105. **[M]** Give each app a deliberate display/body pairing and stop there:
     brgen serif (Libre Baskerville) display + system sans body; amber Caprasimo
     display + a refined humanist sans body; bsdports mono throughout; MASTER
     mono throughout. Document the pairing in each app's AGENTS.md.
106. **[S]** Set a real type scale per app (not ad-hoc px) from the shared
     modular scale (§A.4); cap body measure at ~66ch for reading surfaces
     (post show, articles).
107. **[S]** Tabular/mono numerals (`font-variant-numeric: tabular-nums`) for all
     counts, durations, prices, timestamps so digits don't jitter.
108. **[S]** Truncate with intent: `-webkit-line-clamp` for card bodies, ellipsis
     for single-line meta; never let a title reflow a card's height randomly.
109. **[S]** Consistent smart quotes / dashes in copy (the repo already runs a
     StrunkWhitePass on seed content — extend the same discipline to UI strings).

## L. Forms & compose

110. **[S]** One field style across apps: label above, hairline border, accent
     focus ring, helper/error text below in the same slot (reserve its height so
     errors don't shift layout).
111. **[S][copy]** Buttons name their action and keep the name through the flow:
     "Publish" → toast "Published"; "Save changes" not "Submit".
112. **[S]** Inline validation on blur, not on every keystroke; show success
     quietly, errors specifically ("Add a title" not "Invalid").
113. **[S][a11y]** Associate every input with its label (`for`/`id`), mark
     required fields in text (not color/asterisk alone), and wire `aria-
     describedby` to helper/error text.
114. **[S]** Character counter (amber posts use one) — show remaining, turn the
     count `--x-danger` only in the last 10%, and never block typing silently.
115. **[S]** Live-search fields (amber wardrobe/outfits): debounce, show a
     spinner-in-field, keep focus, and announce result counts to SR
     (`aria-live` on the results frame).

## M. Empty, error & loading states

116. **[M][copy]** Give every list an authored empty state: what it is, why it's
     empty, and the one action to fill it ("No listings in Bergen yet — post the
     first one"). An empty screen is an invitation to act.
117. **[S]** Skeletons that match the real layout (card silhouette) for feed,
     wardrobe grid, search — not spinners — so perceived load is smoother.
118. **[S][copy]** Errors explain and recover in the interface voice, no apology,
     never vague: "Couldn't load the feed. Retry." with a working retry.
119. **[S]** 404/422/500 pages per app (already shipped from `shared/public/`) —
     verify they carry app identity and offer navigation home + search, not a
     dead end.
120. **[S]** Loading a vertical (marketplace→tv) shouldn't blank the shell — keep
     the nav swiper + header, swap only the main region (Turbo frames).

## N. Theming (light / dark / high-contrast)

121. **[S]** Kill theme FOUC everywhere with an inline pre-paint `data-theme`
     read (§C.42) — applies to all three apps' `<head>`.
122. **[M]** Verify every component works in both light and dark for each app
     (amber light-first, brgen/bsdports dark-first) — a per-app screenshot pass
     in both themes using the existing Ferrum/visual_contract tooling.
123. **[S]** Offer `prefers-contrast: more` overrides that bump border tokens to
     `border_strong` and text to full-opacity — cheap, big a11y win.
124. **[S]** Ensure the theme toggle only appears where theming applies
     (`vertical_surface?` already gates it in brgen) and that MASTER's face is
     exempt (it's black by identity).

## O. Consistency & polish sweep

125. **[S]** One icon set, one stroke width, `currentColor` fills — audit for
     mixed icon styles across verticals.
126. **[S]** Consistent corner radius per app from tokens (brgen soft, MASTER/
     bsdports zero) — grep for hardcoded `border-radius` and replace with tokens.
127. **[S]** Consistent avatar component (size scale, fallback initial tile,
     online dot with text companion) shared across social/dating/messenger.
128. **[S]** Consistent timestamp formatting (relative for <7d, absolute after)
     with `<time datetime>` for machines and SR.
129. **[S]** Consistent link affordance: underline-on-hover with a token color,
     never color-only links inside body text (a11y).
130. **[M]** Run the existing `visual_contract_gate` capture across all
     apps/states (happy/empty/error/offline) in desktop/compact/mobile and treat
     the manifest (route, status, SHA, console errors, a11y violations) as the
     acceptance checklist for this whole document.

---

### How to use this list

- These are proposals; several are mutually exclusive (e.g. per-glyph vs. fade
  captions in §B). Choose a direction per surface.
- The cheapest high-impact cluster: §G (a11y floor) + §H.84–88 (fonts/media
  perf) + §M (empty/error states). Start there.
- The identity-defining cluster: §B (face polish), §C.31–34 (nav swiper +
  carousel), §D.52–56 (amber luxury), §E.63 (bsdports terminal).
- Validate with the tooling that already exists: `visual_contract_gate`
  capture + the MASTER command chain (`cd MASTER && ruby bin/gate`).
