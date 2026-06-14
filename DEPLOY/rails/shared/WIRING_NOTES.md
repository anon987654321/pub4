# Shared Rails wiring notes

**Current model (as of 2026):** Each product maintains its own `app/` tree. `shared/` is copied in via small install scripts during setup/bootstrap. The long-term goal remains turning this into a proper engine or gem, but the immediate priority is consistency across the family via documentation + conventions.

This file describes how each app should connect the shared layer until `DEPLOY/rails/shared` is packaged as a real Rails engine or gem.

## Copy shared files

Run from `DEPLOY/rails`:

```sh
sh shared/install_frontend_baseline.sh amber
sh shared/install_frontend_baseline.sh brgen
sh shared/install_frontend_baseline.sh baibl
sh shared/install_frontend_baseline.sh blognet
sh shared/install_frontend_baseline.sh bsdports
sh shared/install_frontend_baseline.sh hjerterom
```

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

The `shared/app/models/concerns/shared/` and `shared/app/controllers/concerns/shared/` provide reusable behavior (expanded 2026-06):

**Models:**
- **Reactable**, **Followable**, **Votable** — social primitives (reactions, follows, votes).
- **Notifiable** — `deliver_notification(recipient, title:..., source:...)` or structured kind/notifiable path. Eliminates `defined?(Notification)` + create boilerplate.
- **ActivityTrackable** — `record_activity!("EventName", actor:, source_vertical:...)`. Centralizes ActivityEventRecorder usage.
- **GeoLocatable** — `nearby(lat, lng, km)`, `haversine`, `geo?`, `distance_to`, `geocode!` stub. One portable implementation (replaced 6+ ad-hoc versions).

**Controllers:**
- **LiveSearchable**, **ActorIdentity**, **MediaGuard**, **StructuredEvents**.

Usage: `include Shared::Votable` (or Notifiable/ActivityTrackable/GeoLocatable) in your models. See recent brgen Post/Comment/User/Orders + hjerterom Resource for examples.

**Next:** Turn the whole shared/ tree into a real Rails engine (see long-term goal note at top of this file) so concerns/services auto-load and routes mount cleanly.

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

## Engine Extraction Prep (to reduce current sprawl + duplication)
To move from "copy via install_frontend_baseline.sh" (fragile, per top of this file) to a real engine:
- All shared code must live only under shared/ (concerns, services, models/shared, views/shared, etc.). No app-specific logic.
- Consistent `include Shared::XXX` (no bare includes).
- Remove/deprecate all local copies of concerns in apps (e.g. brgen/app/models/concerns/* now point to or are replaced by shared versions; locals can be git-rm'd after migration).
- Ensure Shared::EventEmitter, LiveSearch, health services etc. are the single source.
- Then introduce shared/lib/shared/engine.rb with `isolate_namespace Shared`, update consuming Gemfiles to path gem, replace copy script with bundle step.
This directly supports the major restructure wins (shared layer as foundation for activity graph, concerns, etc.) while actively reducing file sprawl/duplication today. Prep steps (promotions + cleanups) are being done in small PRs without new .md files.
