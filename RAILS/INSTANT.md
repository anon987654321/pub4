# 134 ways to feel instant

Proposals for making brgen, amber and bsdports read as fast, 2026-08-29.

Speed and the feeling of speed are different problems and only one of them is
about milliseconds. A page that paints in 400 ms and moves under your thumb
feels quicker than one that paints in 200 ms and sits still while it thinks.
Both are worth having; they are not the same work, and confusing them is why
most performance passes make a site measurably faster and subjectively the same.

Marked **[built]** when the tree already does it — audit reach before proposing
is this repo's own rule, and thirteen of the items below were already here.
**[cheap]** is an afternoon, **[deep]** is a project, **[yours]** is a decision
rather than work.

Grounded in what these three apps actually run today: Turbo 8 with
`turbo_refreshes_with :morph`, 30 Stimulus controllers across the three apps,
Solid Cache/Cable/Queue, Pagy in 13 controllers, importmap with no CDN pins,
and — the number that shapes half this list — **zero fragment caches in any
view** and **two conditional-GET responses in the whole of brgen**.

---

## A · Measure first, because the instrument is usually wrong (1–13)

This tree's stated dominant defect is that measurement code is wrong more often
than the code it measures. Everything below this section is guessing until
something here is running.

1. **Server-Timing headers on every response**, so the browser's own network
   panel shows view / db / cache split without a profiler. **[cheap]**
2. Emit `Server-Timing: miss` vs `hit` for the fragment cache, so a cache that
   never hits is visible rather than assumed.
3. A `RAILS/gates/` check that fails when p95 server time on the route manifest
   crosses a ceiling — a ratchet, like every other gate here. **[deep]**
4. Real User Monitoring for the three Core Web Vitals via `PerformanceObserver`,
   posted to a `web_vitals` table. Lab numbers on a Mac are not vm23 on a phone.
5. Record **INP**, not FID. FID measured how fast the first tap was acknowledged;
   INP measures every interaction, which is the thing being complained about.
6. Log the **slowest 1% of interactions with their target element**, so "the app
   feels slow" becomes "the compose button takes 340 ms".
7. `rack-mini-profiler` is already in the Gemfile — confirm it is mounted in
   development, since a profiler nobody can open is inert config. **[cheap]**
8. Bullet for N+1 detection in development and test, failing the suite rather
   than logging. There are 50 `includes` calls; nothing proves they are enough.
9. A boot-time query counter per controller action, asserted in a test. Query
   count is the metric that regresses silently.
10. Track **payload bytes per route** in the same manifest the probe uses, so a
    view that doubles is caught by a number and not by a reader.
11. Measure on the box, not the Mac. vm23 is 1 GB and 1 vCPU; a 12 ms local
    render is not a 12 ms production render. **[yours]**
12. Keep a **before/after pair for every change in this document**. A filter can
    be wired correctly, run without error, and be transparent.
13. Screenshot-diff the first 300 ms of a navigation, not just the settled page.
    Perceived speed lives entirely in frames nobody currently looks at.

## B · Navigation — the single biggest lever here (14–37)

14. **`data-turbo-prefetch` on hover/touchstart** for the nav bar's eight
    destinations and every feed link. Turbo 8 ships this; it is off by default
    on nothing, but the app sets it to `false` in one place and never on. A
    65 ms hover before a click is 65 ms of free head start. **[cheap]**
15. Prefetch on `mousedown` rather than `click` — worth ~80 ms and costs nothing.
16. **`data-turbo-preload` on the top ten destinations**, so they are in the
    Turbo cache before the first click. **[cheap]**
17. Cap preload to what a 1 GB box can serve; preloading everything is a
    self-inflicted DDoS on vm23. **[yours]**
18. `turbo_refreshes_with :morph, scroll: :preserve` is set in
    `ApplicationController`. **[built]**
19. Extend morphing to the feed so a new post arrives without losing scroll
    position or an open composer. **[cheap]**
20. `data-turbo-permanent` on the nav bar, the theme toggle and the player, so
    they survive a navigation without re-initialising. Three exist already;
    the nav bar is not one of them.
21. **Instant back/forward** via Turbo's restoration cache — verify it is not
    being defeated by a `data-turbo-cache="false"` somewhere broad.
22. Render a **cached preview frame** on navigation start, then replace it. Turbo
    does this; make sure the preview is not visually identical to a blank page.
23. Frame-level navigation for the feed's sort tabs, so Hot/New/Following swap a
    list rather than a document. **[cheap]**
24. `turbo_frame_tag` with `loading: "lazy"` for below-fold panels — sidebar
    widgets, related listings, comment threads past the first ten. **[cheap]**
25. Eager frames for above-fold content, lazy for everything else, decided by a
    single helper rather than per view.
26. **Cross-document View Transitions** for same-origin navigations. Zero today.
    Two CSS rules give the feed→post navigation a shared-element morph. **[cheap]**
27. Name the post's image and title as view-transition targets so they animate
    into the detail page instead of cutting.
28. View transitions on the theme toggle, so light↔dark crossfades instead of
    snapping. **[cheap]**
29. Guard every transition behind `prefers-reduced-motion` — 37 such blocks
    already exist, so the convention is set. **[built]**
30. **Turbo Drive progress bar** styled once in `shared/_shell.scss`. **[built]**
31. Delay the progress bar to 500 ms. Shown immediately it advertises slowness
    on requests that would have felt instant.
32. Restore scroll position per-frame, not per-document, on the messenger and
    channel logs.
33. Make the eight verticals cross-host `target="_blank"` navigations *feel*
    like same-app moves by pre-warming DNS: `<link rel="dns-prefetch">` and
    `preconnect` for the seven subdomains. **[cheap]**
34. `preconnect` costs a socket each — measure before shipping all seven on a
    1 GB box.
35. Speculation Rules API as a progressive enhancement over Turbo's prefetch,
    for browsers that have it.
36. A **back-navigation cache warm**: when a reader opens a post, keep the feed's
    DOM rather than re-fetching on return.
37. Kill any full-page reload that Turbo could have handled — audit every
    `data: { turbo: false }`; each is a document load, and there are several.

## C · The waiting problem — optimistic UI (38–60)

The cheapest millisecond is the one the reader never waits through.

38. **Optimistic vote counts.** The arrow flips and the number increments on tap;
    the request reconciles. Voting is the most-repeated interaction in the app.
39. Optimistic follow/unfollow, with a rollback on failure.
40. Optimistic reactions on messages and comments.
41. Optimistic post submission — the post appears in the feed greyed, then
    settles. **[deep]**
42. A shared `optimistic_controller.js` so the pattern is written once rather
    than five times, which is how the aecho bug in dilla happened.
43. **Rollback must be visible.** A silently reverted optimistic update teaches
    readers not to trust the UI.
44. Queue optimistic actions offline and replay on reconnect. **[deep]**
45. **Skeleton screens** for the feed, matched to the real card's geometry.
    Shimmer that does not match the content it replaces reads as a bug.
46. Skeletons only past ~200 ms — below that they flash and make things worse.
47. Reserve space for every async region so nothing shifts when it lands (CLS is
    a felt problem, not just a metric).
48. `aria-busy` on regions that are loading, so the experience is the same for a
    screen-reader user.
49. **Blurhash placeholders** — the job, the helper and a Stimulus controller all
    exist. **[built]**
50. Verify blurhash actually reaches the feed card. Built and unreached is this
    repo's most common finding.
51. Lazy-load images below the fold — only 8 usages across brgen and shared for
    107 views. **[cheap]**
52. `fetchpriority="high"` on the LCP image, `low` on everything below it.
53. `decoding="async"` on every non-critical image.
54. Explicit `width`/`height` on every image so layout is stable before bytes.
55. **Disable the submit button on submit** and say what is happening, rather
    than letting a reader tap twice.
56. Inline validation on blur instead of a round trip on submit.
57. Debounce search input at 150 ms, not 300 — 300 is perceptible.
58. Show cached/local results while the network result is in flight.
59. Never block a UI update on an analytics call.
60. Local echo in the messenger: the message appears in the thread the instant
    it is sent, before the broadcast returns.

## D · Server latency (61–86)

61. **Fragment-cache the feed card.** Zero views cache anything today and Solid
    Cache is installed and running. This is the single largest server-side win
    available. **[cheap]**
62. Russian-doll caching: post → comments → comment.
63. Cache the nav bar and footer, which are identical on every page of a host.
64. **Watch `update_column`** — it skips `updated_at`, so `[record, …]` cache
    keys do not bust and the page shows a stale value while the console shows
    the new one. This has bitten this tree before.
65. `touch: true` on the associations that participate in cache keys.
66. Collection caching with `cached: true` on the feed's render call — one
    multi-read instead of N reads. **[cheap]**
67. **Conditional GET**: `fresh_when`/`stale?` on show actions. Two in the whole
    app. A 304 is the cheapest response there is. **[cheap]**
68. `expires_in` with `public: true` on genuinely public pages so relayd can
    serve them without touching Falcon.
69. Cache the expensive count queries; a "1.2k members" that costs a full count
    on every page load is a common shape.
70. Counter caches instead of `COUNT(*)` on association reads.
71. Audit the 50 `includes` calls against the actual N+1s — some are almost
    certainly loading associations the view no longer renders.
72. `select` only the columns the view uses on wide tables.
73. Cursor pagination instead of offset for the infinite feed; `OFFSET 10000`
    is a table scan. Pagy supports it. **[deep]**
74. Index every column the feed's ordering and filtering touches, verified with
    `EXPLAIN` rather than assumed.
75. Move blurhash, image variants, notifications and federation delivery off the
    request into Solid Queue — most already are. **[built]**
76. Never render a view that performs a write.
77. Set a hard timeout on any external call in a request path; an unbounded
    fetch is an unbounded page.
78. Cache the geolocation lookup, which is per-request today and per-city by
    nature.
79. HTTP/2 is presumably on at relayd — verify rather than assume.
80. Brotli for text responses; gzip as the fallback.
81. Stream the response with `render stream: true` for the slowest page, so the
    head reaches the browser while the body is still being built. **[deep]**
82. Send `<head>` early via 103 Early Hints so CSS starts downloading during
    server think-time. **[deep]**
83. Cache warm after deploy — the first reader should not pay for the cold
    cache. The keep-warm script exists for the boot storm; extend it.
84. Keep the cold-start problem in view: vm23 measured 12.19 s cold against
    0.40 s warm on an idle box. No front-end work survives that.
85. Consider a read replica or a materialised view for the city trending feed.
    **[deep]** **[yours]**
86. Rate-limit expensive endpoints so one reader cannot make the app slow for
    everyone on a 1 vCPU box.

## E · Assets and first paint (87–104)

87. importmap carries no CDN pins and vendors tiptap locally. **[built]**
88. Seven CDN pins once cost brgen 537 requests per load; keep a gate that fails
    if a CDN pin reappears. **[cheap]**
89. `pin` defaults to `preload: true`, so a modulepreload fetches every pin
    eagerly and any dynamic `import()` is decorative. Audit which of the current
    pins genuinely need preloading.
90. Lazy-register Stimulus controllers that are used on one surface — the map,
    the voice recorder, the lightbox, the radio tunnel.
91. Split the stylesheet per app surface so a marketplace reader does not parse
    the messenger's rules. The built CSS is ~370 KB. **[deep]**
92. Inline the critical above-fold CSS and defer the rest. **[deep]**
93. `content-visibility: auto` on below-fold feed cards — one CSS property,
    large paint saving on long feeds. **[cheap]**
94. `contain: layout style paint` on cards so one card's change cannot reflow
    the list.
95. Self-hosted fonts are already vendored rather than fetched. **[built]**
96. `font-display: swap` so text paints before the face arrives.
97. Subset the fonts to the glyphs Norwegian and English actually use.
98. Preload only the one font weight above the fold.
99. `--font-brand` ships as a zero-byte system stack by design — do not "fix"
    this into a webfont. **[built]** **[yours]**
100. Serve AVIF with WebP and JPEG fallbacks through the existing variant
     pipeline.
101. Generate responsive `srcset` widths rather than shipping one large image.
102. A service worker for the app shell, so a repeat visit paints from disk.
     **[deep]**
103. Offline page already exists — extend it to a cached shell rather than a
     message. **[deep]**
104. Version and precache the built CSS/JS so a repeat visitor fetches neither.

## F · Input and touch (105–118)

105. `touch-action: manipulation` to remove the 300 ms tap delay on anything
     that is not a scroll surface. **[cheap]**
106. Respond to `pointerdown`, not `click`, for state that is purely local.
107. Every tap target at 44 px — already the convention here. **[built]**
108. `:active` states on every interactive element. A control that does not
     acknowledge the finger reads as broken regardless of how fast it is.
109. Haptics via the Vibration API on primary actions, where supported.
110. `passive: true` on scroll and touch listeners so they cannot block
     scrolling.
111. `content-visibility` plus windowing for lists past a few hundred rows.
     **[deep]**
112. `scroll-behavior: smooth` only where it helps; on a long feed it is slower
     than a jump.
113. Overscroll containment on modals and drawers so a scroll gesture does not
     leak to the page behind.
114. Keyboard: `/` to search and ⌘K for the palette already exist. **[built]**
115. `j`/`k` feed traversal, `.` to refresh — the shortcuts a heavy reader
     expects from this class of app.
116. Focus the first field on any surface whose purpose is typing.
117. Optimistic focus: keep the caret in the composer after posting.
118. Never steal focus during an async update.

## G · Real time (119–128)

119. Solid Cable is installed and 15 models broadcast. **[built]**
120. Broadcast `later` rather than inline, so a write is not slowed by delivery.
121. Broadcast a fragment, not a re-render of the page region.
122. Typing indicators exist in the messenger. **[built]**
123. Presence dots on the channel list, driven by the same cable.
124. Live vote and comment counts without a refresh.
125. Debounce broadcast storms — a hundred votes a second is one update.
126. Reconnect with backoff and tell the reader when the socket is down.
127. Replay missed messages on reconnect rather than leaving a hole. **[deep]**
128. Server-Sent Events instead of a socket for the feeds that are read-only —
     cheaper on a 1 GB box. **[yours]**

## H · Motion that reads as speed (129–134)

129. Nothing over 200 ms. A 300 ms transition is a slow app with an animation.
130. Ease-out for entrances, ease-in for exits — the reverse feels sluggish.
131. Animate `transform` and `opacity` only; every other property costs layout.
132. Stagger list entrances by 20–30 ms, no more; a long stagger is a queue.
133. Cut the animation, never the acknowledgement, under
     `prefers-reduced-motion`.
134. One motion vocabulary across the three apps, in the shared tokens, so a
     reader crossing hosts does not cross timing curves.

---

## What not to do

**Do not add a spinner where a skeleton belongs.** A spinner says "wait"; a
skeleton says "here is the shape of what is coming". Only one of them makes the
wait shorter.

**Do not preload everything.** Production is one box with 1 GB of RAM and one
vCPU, and every prefetch is a real request against it. Prefetching the whole nav
bar on hover is a good idea for a reader and a bad one for forty readers.

**Do not ship an optimistic update you cannot roll back.** A UI that lies and
then quietly corrects itself is worse than one that waits.

**Do not tune animations before caching the feed card.** Zero fragment caches
against 54 declared transitions is the wrong ratio, and no easing curve
compensates for a view that rebuilds itself on every request.

**Do not trust an item on this list because it is written down.** Thirteen were
already built, and the ones that most look like wins — prefetch, preload,
streaming — are the ones most likely to be already on, inert, or actively
harmful on this hardware. Find the reader before trusting the setting.
