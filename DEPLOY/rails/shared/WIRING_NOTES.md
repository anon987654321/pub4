# Shared Rails wiring notes

**Current model (engine-ize 2026):** `shared/` is a real Rails engine gem (pub4-shared) loaded via local path in each app Gemfile.
`bundle install` + `gem 'pub4-shared', path: '../../shared'` (relative from rails/<app>) wires everything.
Engine (shared/lib/shared/engine.rb, 10 terse lines): isolate_namespace, autoloads concerns/services, provides `Shared.concern(n)` helper for lazy require+const.
No more per-app copies for core concerns; install_*.sh deprecated (kept only for legacy bootstrap).

See engine.rb for autoload + concern(n). All 6 apps (brgen+5) wired. Root snapshots capture state for eval.

## Engine wiring (preferred)

All apps declare in Gemfile (bottom):
```ruby
gem 'pub4-shared', path: '../../shared'
```
Then `bundle install` (from app dir). Engine boots concerns/services automatically.

Usage in models/controllers:
```ruby
include Shared.concern(:Reactable)
# or
include Shared::Followable
```

Legacy copy scripts deprecated; openbsd.sh / deploy sh updated to favor bundle. Prune stray nested dirs done.

## Social endpoints to mount in each app

Add app-local routes that point to the copied shared controllers:

- one endpoint that calls `Shared::ReactionsController#create`
- one notifications index endpoint
- one notification update/read endpoint
- one notifications read-all endpoint
- one review-case create endpoint
- one review-case update endpoint

Keep the path names product-specific where needed:

- Brgen: reaction, notifications, review cases
- Amber: item/outfit reactions, notifications, review cases
- Blognet: article reactions, notifications, review cases
- Baibl: annotation reactions, notifications, review cases

## Model inclusion

Include shared concerns in app models deliberately:

```ruby
class Post < ApplicationRecord
  include Shared::Reactable
end

class Outfit < ApplicationRecord
  include Shared::Reactable
end
```

Only include `Shared::Followable` on models that users should be able to subscribe to.

## Signed target IDs

Shared controllers expect signed global IDs for targets. Views should use:

```ruby
record.to_sgid.to_s
```

This keeps polymorphic user-facing action targets tamper-resistant.

## Next hardening

- Add app-local authorization before review updates.
- Add tests for every mounted route.
- Replace copy/install with a Rails engine once app structure stabilizes.

## Visual System & Component Inheritance (Brgen as Base)

Brgen's `app/assets/stylesheets/application.css` is the canonical visual source of truth for the entire city app family:
- X.com 3-column layout (275px sidebar / 600px feed / 350px widgets)
- Dark cinema palette (--bg #000, --surface2 #16181c, --accent #1d9bf0, etc.)
- NNG-compliant spacing, typography, and interaction tokens

All other apps should:
1. Import or copy the `:root` custom properties from Brgen.
2. Gradually align their components (cards, nav, forms, modals) to Brgen patterns.
3. Prefer components from `shared/frontend/` + Brgen's Stimulus controllers where possible.

This ensures a single coherent "watch from afar" aesthetic across Brgen, Amber, Blognet, etc. while allowing product-specific branding on top.

**Quick rollout checklist for new apps**:
1. Copy `:root` custom properties from Brgen's `application.css`.
2. Import `shared/frontend/stimulus_components.js` baseline.
3. Align major components (cards, nav, forms) to Brgen tokens.
4. Test reduced-motion + coarse pointer profiles.

## Stimulus Components Baseline

`shared/frontend/stimulus_components.js` + Brgen's controller set (clipboard, lightbox, media_picker, geolocation, notification, timeago, typing, etc.) is the shared component library. New apps and verticals should start from these rather than duplicating. See `shared/STIMULUS_COMPONENTS_BASELINE.md` (and Brgen's `app/javascript/controllers/`).

## LLM / AI Readiness

apps.yml is the canonical structured surface for MASTER scans (`/scan`, `/sweep`, council). Future LLM features (recommendations, ranking, moderation assistance, content generation) should be added as new rows there first, then wired via small shared concerns or services. Brgen's "ai" vertical is the primary experimentation surface. All apps should emit consistent activity events so AI ranking can work across the unified graph (see brgen_CORE.md).

## Unified Activity Graph + Modern Hotwire Reactivity (2025-2026 Patterns)

Brgen (and by extension the whole family) should treat every vertical action as an event in one city activity graph (actor, vertical, event_type, locality, target, visibility, timestamp, metadata). This single source powers feeds, discovery, notifications, moderation, and recommendations.

Inspiration from current best practice (Hotwire + StimulusReflex production apps + LBSN/graph recsys research):
- Use Turbo Streams + Action Cable (or StimulusReflex/CableReady) for live "something just happened near you" updates across marketplace, dating, tv, playlist, takeaway, etc.
- All subapps must emit to the shared Activity stream instead of building private feeds.
- Graph-powered recs (collab filtering + location + social signals) become possible once the unified event stream exists.
- See popular patterns in current Hotwire social/community apps and location-based recommendation papers.

Implementation rule: New features in any app must add an Activity emission + a Turbo Stream consumer before building custom real-time UI.

**Practical starter**: 
- From services: `Shared::EventEmitter.call("Vertical::ActionHappened", actor_id: ..., vertical: "marketplace", ...)`
- From controllers: `include Shared::StructuredEvents` then `emit_event("Vertical::ActionHappened", ...)`

See `shared/app/services/shared/event_emitter.rb` and `shared/app/controllers/concerns/shared/structured_events.rb`. This feeds the unified graph + Hotwire.

## Shared Concerns & Mixins

The `shared/app/models/concerns/shared/` and `shared/app/controllers/concerns/shared/` provide reusable behavior:

- **Reactable** (models): `include Shared::Reactable` → adds `reactions`, `reacted_by?`, `reaction_count`.
- **Followable** (models): `include Shared::Followable` → adds `follows_received`, `followed_by?`, `followers_count`.
- **LiveSearchable** (controllers): `include Shared::LiveSearchable` → provides `live_search_query`, `live_search_scope`, `render_live_search` for Turbo Streams.
- **ActorIdentity**, **MediaGuard**, **StructuredEvents**: Supporting mixins for current user, upload guards, and event emission.

**Usage pattern** (in your app models/controllers):

```ruby
class Post < ApplicationRecord
  include Shared::Reactable
  include Shared::Followable   # if posts can be followed
end

class PostsController < ApplicationController
  include Shared::LiveSearchable

  def index
    @posts = live_search_scope(Post.all, columns: %w[title content])
    render_live_search(collection: @posts, partial: "posts/post")
  end
end
```

See the files in `shared/app/{models,controllers}/concerns/shared/` for full implementations and `shared/WIRING_NOTES.md` for family-wide guidance. Wire these early when adding social or search features.

## Photo / Multimodal Upload Inheritance

Photo creation (upload + processing) is intentionally allowed for unauthenticated visitors on the public surface (`https://ai.brgen.no` without token). This enables multimodal chat experiences for everyone while keeping deeper agent filesystem tools (`ReadFile`, `WriteFile`, `ListDir`, arbitrary `Shell`, etc.) restricted to token-authenticated users.

- The `/photo` endpoint and `image_token` resolution in chat are open to visitors.
- Uploaded images are stored in a scoped tmp directory per app and referenced via short-lived image tokens.
- When wiring a new app (amber, hjerterom, etc.), mount the photo upload route and ensure the `ActiveStorage` + postpro pipeline is present if you want vision features.
- Agent-side tools that touch the real filesystem remain gated by the tool registry (`data/tools.yml` + `LLMDispatcher` visitor filtering). Never grant `Reach::ReadFile` / `WriteFile` etc. to visitors.

See `chat_controller.rb` (photo + uploaded_image_payload) and recent security carve-outs for the exact boundaries.

**Standardization tip**: When adding photo support to a new app, mount the upload route and ensure `ActiveStorage` + post-processing is wired (use Brgen as reference). Keep the visitor-allowed carve-out for public multimodal chat.

## OpenBSD Provisioning & Service Wiring (reference patterns)
rc.d services (falcon/puma per-app on distinct ports), relayd tables/healthchecks, and per-vertical feature scripts (auth, voting, styles, social, models) provide a repeatable template. All family apps should converge on the same rc.d + relayd + Solid stack baseline for doas rcctl consistency. Shared functions for gem groups, db setup, and layout/CSS baselines reduce drift across brgen, amber, blognet, hjerterom.

**Pure Zsh preference**: New provisioning logic should favor zsh parameter expansion and builtins over external tools (grep, sed, awk, etc.) where practical, per the broader pub4 conventions. See current thin deploy scripts (e.g. `brgen/brgen.sh`) as the model rather than the heavier legacy @*.sh helpers.
