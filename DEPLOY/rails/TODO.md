# DEPLOY/rails — agent execution queue

Scope: `DEPLOY/rails` apps and `MASTER/` runtime.
All items are small, reversible, and additive unless marked `[risky]`.
Prefer code changes over prose. One file, one commit per item.

## Priority 1 — verification (run first)

- [ ] 171 Rebase `brgen-amber-product-pass` onto `main` — 65 ahead, 15 behind
- [ ] 172 Ruby syntax checks: `ruby34 -c` on all changed `.rb` files in `DEPLOY/rails/`
- [ ] 173 Run Brgen migrations dry-run: `RAILS_ENV=development bin/rails db:migrate:status`
- [ ] 174 Check all new controllers have matching routes
- [ ] 175 Check all new routes have actions
- [ ] 176 Boot Brgen: `RAILS_ENV=development bin/rails runner "puts 'ok'"`
- [ ] 177 Boot Amber: same
- [ ] 178 Search for raw `<input` without `form` helpers in ERB
- [ ] 179 Search for raw `<textarea` in ERB
- [ ] 180 Search for inline `style=` in changed ERB
- [ ] 181 Search for `TODO` strings in changed files and implement or remove
- [ ] 182 Search for unguarded `Current.user` — must be guarded by `authenticated?`
- [ ] 183 Search for repeated page headers → extract partials
- [ ] 184 Search for duplicated currency formatting → push to model/helper
- [ ] 185 Search for unused route helpers
- [ ] 186 Check `Tv::Comment` — needs migration, controller, route, view, or removal
- [ ] 187 Check `Shared::FollowToggle` — connector-blocked; retry or remove stub
- [ ] 188 Check `Shared::MediaUploadsController` — connector-blocked; retry or remove stub

## Priority 2 — Takeaway (items 69–90)

- [x] 69 Wire `Takeaway::Order#subtotal_display` in order show view
- [x] 70 Wire `Takeaway::Order#delivery_fee_display` in order show view
- [x] 71 `total_display` consistent with other helpers
- [ ] 72 `advanceable?` predicate on `Takeaway::Order` — ✅ already in model
- [x] 73 Replace `status != "delivered"` with `advanceable?` in order show view
- [ ] 74 Add `owner?(user)` helper on `Takeaway::Restaurant` or policy object
- [ ] 75 Replace owner comparisons in views with helper/policy
- [ ] 76 Add already-saved restaurant state if `FavoriteRestaurant` association exists
- [ ] 77 Add unsave action if route/controller supports it
- [ ] 78 Add favorite count to restaurant header
- [ ] 79 Add menu empty state
- [ ] 80 Add dietary chip display if fields exist
- [ ] 81 Add item quantity labels for every item
- [ ] 82 Add delivery-address label text
- [ ] 83 Extract menu item row partial
- [ ] 84 Extract order totals partial
- [ ] 85 Extract order status timeline partial
- [ ] 86 Add customer order index if route exists
- [ ] 87 Add restaurant owner order dashboard if route exists
- [ ] 88 Guard notification creation in `Takeaway::Order#notify_customer!` ✅ (already guarded)
- [ ] 89 Guard activity recording in `Takeaway::Order#record_status_activity!` ✅ (already guarded)
- [ ] 90 Add transaction around order creation if multi-step writes in controller

## Priority 3 — TV (items 95–110)

- [x] 96 Add `has_many :comments` to `Tv::Video`
- [ ] 95 Finish `Tv::Comment` wiring: migration, controller, route, view — or remove
- [ ] 97 Add comments controller `Tv::CommentsController`
- [ ] 98 Add comments routes inside `scope module: "tv"`
- [ ] 99 Add comment form guarded by `authenticated?`
- [ ] 100 Add empty comment state
- [ ] 101 Add channel subscription state in channel header
- [ ] 102 Add video status chip helper
- [ ] 103 Add duration fallback helper
- [ ] 104 Add thumbnail fallback alt text
- [ ] 105 Add related videos section if scope exists
- [ ] 106 Add owner dashboard link for channel owner
- [ ] 107 Add upload CTA only for channel owner
- [ ] 108 Extract video metadata partial
- [ ] 109 Extract channel header partial

## Priority 4 — Brgen shared systems (items 26–45)

- [ ] 26 Finish activity feed filtering in controller scope
- [ ] 27 Add activity feed pagination
- [ ] 28 Add source-vertical display helper
- [ ] 29 Add activity object title fallback
- [ ] 30 Add activity locality fallback
- [ ] 31 Add notification unread count helper
- [ ] 32 Add notification source link helper
- [ ] 33 Add notification empty-state partial
- [ ] 34 Add shared owner guard helper
- [ ] 35 Add shared display-name helper for users
- [ ] 36 Add shared money display helper or model concern
- [ ] 37 Add shared status-chip partial
- [ ] 38 Add shared media gallery styles safely
- [ ] 39 Add shared media gallery alt-text fallback
- [ ] 40 Reuse shared media gallery in TV and Amber where attachments exist
- [ ] 41 Decide whether moderation reports are kept or removed
- [ ] 42 If kept, add report controller/routes/view
- [ ] 43 Add review queue route only after model surface is complete
- [ ] 44 Add audit trail display only after events are persisted
- [ ] 45 Keep Brgen core docs canonical; collapse fragments into pointers

## Priority 5 — Marketplace (items 46–68)

- [ ] 46 Mark active category filter
- [ ] 47 Mark active query state
- [ ] 48 Add saved-search count to marketplace header
- [ ] 49 Add listing save count helper
- [ ] 50 Add seller display-name helper
- [ ] 51 Guard listing owner actions
- [ ] 52 Guard buyer offer actions
- [ ] 53 Add no-results next action
- [ ] 54 Add listing status chip helper
- [ ] 55 Add listing location fallback
- [ ] 56 Add category fallback
- [ ] 57 Add image fallback alt text
- [ ] 58 Use shared media gallery everywhere listing photos render
- [ ] 59 Extract offer form partial
- [ ] 60 Extract seller dashboard partial
- [ ] 61 Extract listing stats partial
- [ ] 62 Add offer status helper
- [ ] 63 Add accepted/declined copy consistency
- [ ] 64 Add seller notification source links
- [ ] 65 Add `recent` and `visible` scopes where missing
- [ ] 66 Prevent duplicate saved searches for same user/query/category/location
- [ ] 67 Add saved-search delete confirmation if app convention supports it
- [ ] 68 Keep Marketplace docs as Brgen-local commerce

## Priority 6 — MASTER runtime improvements

- [ ] Wire diff guard: block writes with deletion ratio > 50% or file-size collapse
- [ ] Add Rails style verifier rule: raw `<input>`, `<textarea>`, unguarded `Current.user`
- [ ] Add blocked-attempt ledger to `MASTER/.master/blocked_attempts.jsonl`
- [ ] Add prompt cache_control to system prompt (93% cost reduction)
- [ ] Swap Silkscreen font for Roboto Mono in `MASTER/web/app/assets/stylesheets/`
- [ ] Fix 14k DEPLOY violations: re-run fix_loop sweep with fresh circuit breakers
- [ ] Wire `Tv::Comment` migration: `add_reference :tv_comments, :tv_video`
- [ ] Rails completeness check: every new model has migration + route surface or is documented as stub

## Notes

- `brgen-amber-product-pass` has 65 commits ahead of `main`, 15 behind. Rebase before merge.
- `Shared::FollowToggle` and `Shared::MediaUploadsController` were connector-blocked; both exist as stubs.
- `Tv::Comment` model and `Tv::Video#has_many :comments` are wired; no migration or controller yet.
- OpenDNS resolver still serving old IP (185.52.176.18); Google/Cloudflare/Quad9 now correct.
- MASTER circuit breaker recovers within 30s; fix_loop sweeps resume on next turn.
