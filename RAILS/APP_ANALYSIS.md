# RAILS per-app analysis — features, logic, views, reflexes, Hotwire, Stimulus, CSS polish

Static analysis at HEAD `55573746e` (after the `UI_REFINEMENTS` pass landed). MVC
integrity is clean — **0 controllers with a missing RESTful template** in any app.
So this is about *depth, interactivity, and polish*, not absent scaffolding.

> **VERIFIED 2026-07-19 — most items below are already done** (concurrent commits
> closed them; the apps moved under this doc):
> - ✅ **bsdports styling + live-search** — the one scss file is a full 459-line
>   `openbsd_wscons` green-terminal identity; `ports#index` already uses
>   `live_search_index` (`/` + ⌘K). *Done.*
> - ✅ **amber analysis jobs** — `RemoveBackgroundJob`/`SegmentGarmentImageJob` now
>   route through `Shared::PostproProcessor` with terminal `analysis_status`
>   (done/failed/skipped) — real, not the old log-only stubs. *Done.*
> - ✅ **brgen marketplace checkout** — migrated to Solidus (Gemfile), the cart has a
>   real checkout (no disabled "coming soon" button). *Done.*
> - ⭕ **amber "thin edit views"** — NOT a gap: `items/edit`/`outfits/edit` render a
>   shared `_form` partial (standard DRY). Retract this finding.
> - 🔸 **Genuinely still open:** bsdports `semantic_search` is a stub (needs
>   sqlite-vec/pgvector embeddings — infra-gated); scattered hardcoded-English UI
>   strings (i18n); tv/takeaway card micro-polish. The amber stimulus-components
>   adds are *optional* enhancements, not gaps.
>
> Net: little remains that is a clear, safe, un-done win — the flagship work has
> been happening in parallel.

Legend: **[gap]** real missing thing · **[reflex]** Hotwire/Turbo opportunity ·
**[sc]** stimulus-components.com adoption · **[css]** layout/style polish · **[S/M/L]** effort.

Inventory:

| App | ctrl | views | models | Stimulus | scss | turbo views | character |
|-----|-----:|------:|-------:|---------:|-----:|------------:|-----------|
| brgen | 77 | 153 | 91 | 26 | 39 | 33 | flagship, feature-rich |
| amber | 28 | 78 | 33 | 6 | 14 | 17 | wardrobe intelligence, thinner |
| bsdports | 10 | 24 | 13 | 3 | 1 | 8 | ports search, minimal |

Shared engine already provides these stimulus-components via `stimulus_boot.js`:
AutoSubmit, CheckboxSelectAll, Clipboard, ContentLoader, **Dialog, Dropdown,
Hotkey, Lightbox, Notification, Popover, ReadMore, Reveal** (+ Carousel, Sortable,
CharacterCounter, Timeago, Slideover). The opportunity is **using** them where each
app currently has nothing or a bespoke reimplementation.

---

## brgen — feature-rich, mostly polished (26 Stimulus controllers)

Verticals: tv, dating, marketplace, playlist, takeaway, maps, messenger. The
`UI_REFINEMENTS` pass already applied a11y/identity/perf polish here.

**Logic / features**
- **[gap][M]** `marketplace` recently moved to a "Solidus path" (`84de699ab`) — verify
  the cart→offer/checkout flow is actually complete now (the old native flow had a
  disabled "Send all offers" button). If Solidus, confirm orders/line-items/state
  machine are wired, not half-migrated.
- **[gap][S]** `tv/episodes/show` renders "Video coming soon" when `@video` is nil —
  fine as an empty state, but there's no upload/attach path surfaced from the episode
  page; add one (or link to the channel's upload).
- **[S]** `newsletter_mailer/edition` and `playlist/playlists/index` are intentionally
  thin (immersive `radio_tunnel`); leave, but the newsletter edition mailer could
  reuse the SEO/hero kit for richer editions.

**Reflexes / Hotwire**
- **[reflex][M]** Live counters — votes, comment counts, dating match badges — some go
  through `broadcasts_refreshes`; make sure the **feed** vote/comment counts update via
  Turbo Stream rather than a full refresh (cheaper on the 1-CPU VPS).
- **[reflex][S]** `nearby-alerts` / `match-overlays` are `turbo_stream_from` targets —
  good; confirm they use `@stimulus-components/notification` styling for toasts.

**Stimulus / stimulus-components**
- **[sc][S]** `tabs_controller` is bespoke — keep (no official Tabs component), but the
  various modal/overlay bits (splash, bottom-sheet, share sheet) could standardize on
  **Dialog** + **Slideover** instead of three separate mechanisms.
- **[sc][S]** `lightbox` already uses `@stimulus-components/lightbox` ✓. `swipe`,
  `pull_to_refresh`, `bottom_sheet` are legitimately custom (mobile gestures).
- **[sc][S]** Community/vertical filter bars → `@stimulus-components/dropdown` +
  `auto-submit` (shared has both) rather than manual JS.

**CSS polish**
- **[css][S]** Per-vertical identity is in (accent map); extend to the **tv card**
  (16:9 poster + duration chip in tabular-nums + live dot) and **takeaway** sold-out
  state (muted card + text badge, not color-only) — the two §C items not yet done.
- **[css][S]** Confirm the self-hosted fonts + `content-visibility` from the earlier
  pass survived the Solidus marketplace change.

---

## amber — under-built interactivity for its ambition (only 6 Stimulus controllers)

"Wardrobe/outfit intelligence" but the smallest interactive surface relative to its
premise. Biggest upside per effort.

**Logic / features**
- **[gap][L]** The **analysis jobs** (`RemoveBackgroundJob`, `SegmentGarmentImageJob`)
  were log-only stubs advancing `analysis_status` to `*_pending` with no real ML.
  Amber's whole value prop depends on these — route them through the shared media
  service (`Pub4::DeployPaths` → postpro/repligen) or a real segmentation provider,
  and advance `analysis_status` to a terminal state.
- **[gap][S]** `items/edit` and `outfits/edit` are **tiny/thin** edit forms — likely
  missing fields present in `new`/`show` (occasion tags, season, sustainability, photo
  management). Bring them to parity.
- **[gap][M]** Sustainability score (`CalculateSustainabilityJob`) — surface it in the
  UI as a small warm meter/grade; currently computed but under-shown.

**Reflexes / Hotwire**
- **[reflex][M]** Live-search on wardrobe/outfits uses the shared `live_search` — good;
  extend Turbo Streams to the **outfit builder** (add/remove item updates the preview
  frame without reload).
- **[reflex][S]** `analysis_status` transitions should **broadcast** to the item card
  (a spinner → done badge) via Turbo Stream, so background jobs feel live.

**Stimulus / stimulus-components**
- **[sc][S]** `hotkey_controller` duplicates `@stimulus-components/hotkey` (shared) —
  consolidate.
- **[sc][M]** `wardrobe_carousel` is bespoke — swap to `@stimulus-components/carousel`
  (already available) for consistency + a11y.
- **[sc][M]** Amber uses almost none of the available components. High-value adds:
  **Dialog** (item/outfit detail modal), **Popover** (item metadata on hover),
  **Dropdown** (filter/sort), **Reveal** (outfit reveal animation), **read-more**
  (long descriptions), **Sortable** (already used ✓ for wardrobe ordering).

**CSS polish**
- **[css][M]** Luxury tokens exist (`design_tokens.yml luxury`) but the layout is a
  generic grid — move to an **editorial lookbook** (larger hero item, supporting
  tiles), widen line-height/letter-spacing on the display face, let whitespace carry
  the calm. This is where "luxury" is won or lost.
- **[css][S]** Placeholder tiles (category-initial) → warm-neutral small-caps tiles.

---

## bsdports — minimal; most headroom (only 3 Stimulus controllers, 1 scss file)

A utility search app, deliberately lean — but the leanest by far, and a distinct
identity opportunity.

**Logic / features**
- **[gap][M]** `port.rb:30` — `scope :semantic_search, ->(q) { search(q) }` is a **stub**:
  "semantic" search just calls plain search. The pgvector/embedding feature is
  unimplemented. Either wire real embeddings (amber/master have the pieces) or rename
  it so it doesn't imply a capability it lacks.
- **[gap][S]** Advisory surface is thin — a port's security advisories could show
  severity (color + **text** badge), affected versions, and a fix-available flag.

**Reflexes / Hotwire**
- **[reflex][S]** Search-as-you-type via the shared `live_search` + `auto-submit`
  (debounced, in-field spinner) instead of full page loads — bsdports is search-first,
  so this is the highest-impact reflex.
- **[reflex][S]** `@stimulus-components/content-loader` to lazy-load a port's full
  detail/dependencies panel on expand.

**Stimulus / stimulus-components**
- **[sc][S]** Only `search_hotkey` locally. Add: **Popover** (advisory details on
  hover), **Timeago** (advisory/update dates), **Clipboard** (copy `pkg_add` command),
  **Dropdown** (category/arch filter).

**CSS polish**
- **[css][M]** **1 scss file** — bsdports is essentially unstyled beyond the shared
  base. This is the biggest polish opportunity: give it its own identity — a dense,
  monospace, terminal-adjacent look (the `openbsd_wscons` green-on-black dialect fits a
  ports index perfectly and would make it unmistakably *not* brgen/amber). Dense result
  rows: name · version · one-line desc · advisory tag.
- **[css][S]** Verify contrast on any secondary/muted text (the green dialect's
  secondary `#3d7a3d` is ~3:1 — reserve for non-essential meta only).

---

## Cross-cutting (all apps)

- **[sc][S]** Adoption is uneven: brgen leans on the shared components, amber/bsdports
  barely touch them. A quick win is wiring **Dialog/Dropdown/Popover/Timeago/Clipboard**
  into amber + bsdports where they currently have nothing.
- **[reflex][S]** The `stimulus-components adoption gate` exists (`gates/`) — run it per
  app to see which pinned components are unused vs. which bespoke controllers could retire.
- **[css][S]** The empty/error/skeleton states from `UI_REFINEMENTS §M` were only
  partially applied — a card-silhouette skeleton (vs. spinner) for feed/search/wardrobe
  is still worth doing.
- **[gap][S]** i18n: many empty-state/UI strings are hardcoded English while brgen is
  multi-locale — move them into `config/locales`.

### Recommended order
1. **bsdports styling + live-search** (biggest visible delta for least effort — 1 scss file today).
2. **amber analysis jobs + stimulus-components adoption** (unlocks the product's premise).
3. **brgen marketplace-checkout verification** (confirm the Solidus migration is complete, not half-done).
