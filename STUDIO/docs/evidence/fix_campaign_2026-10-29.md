# Fix campaign 2026-10-29 — operator-directed pass over RAILS/

Scope: the fix list from `pub4-rails-assessment.md` that can be landed from
static work, shaped by the operator's product calls of the same day:
marketplace competes at the Amazon / Kaufland.de / bol.com class, messenger
must be complete enough to replace Facebook Messenger, playlist positions as
SoundCloud plus whyp.it, and a takeaway-into-marketplace merge is under
consideration. Registry rows for every landed change are in the same commit
(one registry, one truth); the aspirational half of the product calls lives in
`apps.horizon.yml`, which is `agent_policy: ignore` by design.

## Landed

- **Messenger history pagination** — the thread no longer ends at fifty
  messages. `ConversationsController#show` fetches window+1 rows and only then
  hands the log a cursor; `MessagesController#index` (new, routed on the host
  and the messenger subdomain) serves pages of `HISTORY_PAGE` above the cursor
  and names the next one in `X-History-Next`, scoped through `for_user` and
  `visible.unexpired`. `conversation_log_controller` walks it: scroll-anchored
  prepend, IntersectionObserver auto-load plus a real focusable button, no
  unread-pill inflation for lines the reader asked for, day breaks and
  grouping re-derived per page. Pinned by
  `brgen_messenger/test/controllers/message_history_test.rb` (cursor walk to
  the first line, expired/unsent exclusion, stranger refusal).
- **Dating identity gate fails closed** — the old default treated a missing
  `VIPPS_CLIENT_ID` as an open door (the README itself called it the wrong
  default for a dating product). `require_vipps_identity` now admits only
  `vipps_verified` accounts when Vipps is configured and locks the writing
  surfaces when it is not; a server that deliberately runs without Vipps keys
  opens the gate only with `DATING_IDENTITY_BYPASS=demo` in env. README risk
  paragraph rewritten. Pinned by
  `brgen/test/controllers/dating_identity_gate_test.rb` (locked, demo-bypass,
  unknown bypass value, bypass-irrelevant-when-configured).
- **Marketplace: card fragment caching + bounded ranking sweep** — media and
  stars cache on `[listing, "media"]` / `[listing, "stars"]`; viewer-owned
  state (favourite, distance, search-rank reasons, buy box) stays outside the
  fragments. `RankingService#recalculate!` writes only rows whose score moved,
  so the every-2-hours sweep stops rewriting every live row — which had been
  bumping `updated_at` and flushing the very caches the cards just warmed.
  Pinned by `test/services/marketplace/ranking_service_test.rb`.
- **Marketplace: first controller tests** — carts, checkout, listings, orders,
  stores, Dintero webhooks under `brgen_marketplace/test/controllers/`.
  Checkout pins the fail-closed answer for an unconfigured PSP; webhooks pin
  signature rejection with zero deliveries; the others cover the buyer and
  seller request flows plus sign-in and non-owner refusals.
- **Maps: Turbo morph guard + first engine tests** —
  `map_morph_guard_controller` keeps the MapLibre section out of Turbo morphs
  via `turbo:before-morph-element` (the tiptap idiom), wired through the
  importmap vertical pin loop; `MapsHomeControllerTest` and
  `MapsPlacesControllerTest` are the engine's first controller tests. The
  README's "carries no guard" note now describes what exists.
- **Master: stop control** — a per-turn cancellation token reaches TurnRouter;
  a failed stream write (Falcon raises on a closed body, the idiom the
  existing rescue stack already assumed) cancels the turn and unwinds into the
  RubyLLM chunk callback, so the provider request stops at that chunk boundary
  instead of burning tokens to nobody. No new SSE event: the stop travels as a
  cancelled turn, and the pinned event census is held closed by
  `test/sse_contract.test.mjs`. Stop control pinned in the face and degraded
  paths by the mjs suites; service behaviour by
  `test/services/chat_service_stop_test.rb`.
- **Registry** — `apps.yml` carries a `done` row with file evidence for each
  landed change; `apps.horizon.yml` carries the operator's positioning calls
  (marketplace class, takeaway merge consideration, messenger replacement bar,
  playlist positioning).

## What this receipt cannot claim

No Ruby or Chrome runtime exists where this pass was authored, so every claim
above is anchored to source and the suites must be run on the OpenBSD box:
`bin/ci` per app, `RAILS/test/run_all.rb`, and the master mjs suites. The
engine tests run under brgen's suite (`test_roots("brgen")` globs
`RAILS/brgen_*/**/test` and `__shared/test`, and the /fix proof loop maps
`RAILS/brgen_*` changes onto brgen). Still dark by decision or infrastructure,
unchanged by this pass: Dintero awaits staging validation, takeaway has no
charge path (the merge question may settle it), TV live streaming awaits a
media server, amber's pgvector work awaits a Postgres decision.
