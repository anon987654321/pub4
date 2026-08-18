# frozen_string_literal: true

require "brgen/domain_registry"

Rails.application.routes.draw do
  get "offline" => "rails/pwa#offline", as: :pwa_offline
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "manifest.json" => "rails/pwa#manifest"
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  # Browsers often request the .js suffix; 422/HTML here breaks SW registration.
  get "service-worker.js" => "rails/pwa#service_worker"
  post "share" => "posts#share", as: :share_post
  # Loopback-only in practice (see InternalController's shared-secret gate);
  # not subdomain-constrained since MASTER calls it directly by IP:port.
  get "internal/status" => "internal#status", as: :internal_status
  post "internal/dilla_publish" => "internal#dilla_publish", as: :internal_dilla_publish
  get "sso/from_master" => "sso#from_master", as: :sso_from_master

  get  "verify/:token" => "email_verifications#show",   as: :verify_email
  post "verify/resend" => "email_verifications#create", as: :resend_verification

  post   "users/:user_id/block" => "blocks#create",  as: :block_user
  delete "users/:user_id/block" => "blocks#destroy", as: :unblock_user

  post   "communities/:community_id/join" => "community_memberships#create",  as: :join_community
  delete "communities/:community_id/join" => "community_memberships#destroy", as: :leave_community

  get "tags/:name" => "hashtags#show", as: :hashtag, constraints: { name: /[A-Za-z0-9_]+/ }

  get    "saved" => "bookmarks#index", as: :saved
  post   "posts/:post_id/bookmark" => "bookmarks#create",  as: :bookmark_post
  delete "posts/:post_id/bookmark" => "bookmarks#destroy", as: :unbookmark_post

  instance_eval(File.read(File.expand_path("../../shared/config/routes/legal.rb", __dir__)))

  jobs_constraint = lambda { |request|
    session_id = request.cookie_jar.signed[:session_id]
    session_id.present? && ::Session.exists?(id: session_id)
  }

  TV_SUBDOMAINS          = Brgen::DomainRegistry::TV_SUBDOMAINS
  DATING_SUBDOMAINS      = Brgen::DomainRegistry::DATING_SUBDOMAINS
  PLAYLIST_SUBDOMAINS    = Brgen::DomainRegistry::PLAYLIST_SUBDOMAINS
  TAKEAWAY_SUBDOMAINS    = Brgen::DomainRegistry::TAKEAWAY_SUBDOMAINS
  MARKETPLACE_SUBDOMAINS = Brgen::DomainRegistry::MARKETPLACE_SUBDOMAINS
  MAPS_SUBDOMAINS        = Brgen::DomainRegistry::MAPS_SUBDOMAINS
  MESSENGER_SUBDOMAINS   = Brgen::DomainRegistry::MESSENGER_SUBDOMAINS

  resource  :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  instance_eval(File.read(File.expand_path("../../shared/config/routes/auth.rb", __dir__)))
  instance_eval(File.read(File.expand_path("../../shared/config/routes/verification.rb", __dir__)))
  post "fingerprint" => "fingerprints#create"
  instance_eval(File.read(File.expand_path("../../shared/config/routes/fleet.rb", __dir__)))
  resources :activity_events, only: :index
  instance_eval(File.read(File.expand_path("../../shared/config/routes/social.rb", __dir__)))

  namespace :admin do
    resources :reports, only: %i[index update]
  end

  # Declared before the shallow nesting below, which yields GET /posts/:id. That
  # route matched /posts/new first and sent "new" through as an id, so the
  # standalone new-post page answered 404 ("Couldn't find Post with id=new")
  # while new_post_path happily generated the link to it.
  resources :posts do
    resources :comments, shallow: true, only: %i[create destroy]
    resource :vote, only: [ :create ], controller: "votes"
    # POST toggles: the action Stimulus controller only ever sends POST.
    resource :repost, only: [ :create ], controller: "reposts"
  end

  # ActivityPub. Each city is a separate origin with its own population, which
  # is the same shape as two Mastodon instances — so an actor is resolved
  # against the requested host, not globally.
  get ".well-known/webfinger" => "well_known#webfinger", as: :webfinger
  get ".well-known/nodeinfo"  => "well_known#nodeinfo_index"
  get "nodeinfo/2.1"          => "well_known#nodeinfo", as: :nodeinfo
  # The shared inbox: one POST per instance instead of one per follower.
  post "inbox" => "fediverse/inboxes#create", as: :shared_inbox
  get  "users/:username/outbox"    => "fediverse/actors#outbox",    as: :actor_outbox
  get  "users/:username/followers" => "fediverse/actors#followers", as: :actor_followers
  post "users/:username/inbox"     => "fediverse/inboxes#create",   as: :actor_inbox
  # The actor document shares its URL with the HTML profile, told apart by
  # Accept. A path constraint would not do: /users/5 is the existing profile
  # route and a username is not guaranteed to be non-numeric, so the header is
  # the only thing that actually distinguishes the two requests.
  activitypub_request = lambda do |request|
    request.headers["Accept"].to_s.match?(%r{application/(activity|ld)\+json})
  end
  get "users/:username" => "fediverse/actors#show", as: :actor, constraints: activitypub_request


  # Stories delete themselves after 24h; `alive` hides an expired one from every
  # surface whether or not the sweep has run yet.
  resources :stories, only: %i[index show new create destroy]

  # Cancelling is a member-facing state change, not a delete: people have it in
  # their calendar. RSVP is nested because it only exists against an event.
  resources :events do
    member do
      post :rsvp, to: "event_rsvps#create"
      patch :cancel
    end
    resources :comments, shallow: true, only: %i[create destroy]
  end

  resources :communities do
    # A community's own moderators work this queue. Admin::Reports is every
    # report in the app behind a single BRGEN_ADMIN_EMAIL check; this is the
    # per-community one, derived from the posts that belong here.
    resources :moderation, only: %i[index update], controller: "communities/moderation"
    resources :moderators, only: %i[index create destroy], controller: "communities/moderators"
    # Scoped to this community, never site-wide: one community's moderator
    # silencing someone everywhere is not a lever that should exist.
    resources :bans, only: %i[index create destroy], controller: "communities/bans"
    resources :posts, shallow: true do
      resources :comments, shallow: true, only: %i[create destroy] do
        resources :comments, shallow: true, only: %i[create destroy], as: :replies
      end
      resource :vote, only: [ :create ], controller: "votes"
      resource :repost, only: [ :create ], controller: "reposts"
    end
  end
  patch "drafts/:id", to: "drafts#update", as: :draft

  resources :comments, only: %i[create destroy] do
    resource :vote, only: [ :create ], controller: "votes"
    resources :comments, only: [ :create ], as: :replies
    member do
      post :generate_summary
    end
  end

  resources :users, only: %i[show new create edit update] do
    member do
      post :follow, to: "follows#create"
      delete :unfollow, to: "follows#destroy"
      get :avatar, to: "avatars#show"
    end
    resources :conversations, only: [ :create ]
  end

  resources :conversations, only: %i[index show update] do
    # Search over the reader's own threads; ?conversation_id= narrows it to one.
    collection { get :search }
    # update is a bounded edit; destroy is an unsend, which keeps the row so a
    # threaded reply is not orphaned. forward writes a copy into another thread.
    resources :messages, only: %i[create update destroy] do
      member { post :forward }
    end
    resources :typing_indicators, only: [ :create ]
    resource :presence, only: %i[create destroy]
    resource :pin, only: %i[create destroy], controller: "conversation_pins"
  end

  # TV vertical, extracted to a mountable engine (engines/tv). Routes now live in
  # the engine's config/routes.rb; the host mounts it under the same subdomain
  # constraint. Host references to its helpers are tv.* (see application_helper,
  # sitemaps_controller). The pilot for the vertical-as-engine split — see ENGINES.md.
  # Mount at the top level with constraints: as a keyword — NOT inside a
  # `constraints(subdomain:) do … end` block. A mount nested in a constraints
  # block still routes, but Rails only registers the `as:` mounted-helper proxy
  # (tv.channel_url, used by application_helper and sitemaps_controller) for a
  # top-level mount. Nesting it silently drops the helper. See ENGINES.md.
  mount Tv::Engine, at: "/", as: "tv", constraints: { subdomain: TV_SUBDOMAINS }

  # dating vertical extracted to engines/dating (mountable engine). Top-level mount with
  # constraints: keyword — NOT a constraints(subdomain:) block, which would drop the
  # dating.* mounted helper. See brgen/ENGINES.md.
  mount Dating::Engine, at: "/", as: "dating", constraints: { subdomain: DATING_SUBDOMAINS }

  # playlist vertical extracted to engines/playlist (mountable engine). Top-level mount with
  # constraints: keyword — NOT a constraints(subdomain:) block, which would drop the
  # playlist.* mounted helper. See brgen/ENGINES.md.
  mount Playlist::Engine, at: "/", as: "playlist", constraints: { subdomain: PLAYLIST_SUBDOMAINS }

  # takeaway vertical extracted to engines/takeaway (mountable engine). Top-level mount with
  # constraints: keyword — NOT a constraints(subdomain:) block, which would drop the
  # takeaway.* mounted helper. See brgen/ENGINES.md.
  mount Takeaway::Engine, at: "/", as: "takeaway", constraints: { subdomain: TAKEAWAY_SUBDOMAINS }

  # marketplace vertical extracted to engines/marketplace (mountable engine). Top-level mount with
  # constraints: keyword — NOT a constraints(subdomain:) block, which would drop the
  # marketplace.* mounted helper. See brgen/ENGINES.md.
  mount Marketplace::Engine, at: "/", as: "marketplace", constraints: { subdomain: MARKETPLACE_SUBDOMAINS }

  # maps vertical extracted to engines/maps. Place stays a host model.
  # Top-level mount with constraints: keyword — NOT a constraints(subdomain:)
  # block, which would drop the maps.* mounted helper. See brgen/ENGINES.md.
  mount Maps::Engine, at: "/", as: "maps", constraints: { subdomain: MAPS_SUBDOMAINS }

  constraints(subdomain: MESSENGER_SUBDOMAINS) do
    root "conversations#index", as: :messenger_root
    resources :conversations, only: %i[show update create] do
      resources :messages, only: %i[create]
      resources :typing_indicators, only: %i[create]
      resource :presence, only: %i[create destroy]
      resource :pin, only: %i[create destroy], controller: "conversation_pins"
    end
  end

  # TradeDoubler Conversions API postback (not marketplace-scoped).
  post "webhooks/tradedoubler" => "webhooks/tradedoubler#create", as: :webhooks_tradedoubler
  post "webhooks/stripe" => "webhooks/stripe#create", as: :webhooks_stripe
  post "webhooks/vipps" => "webhooks/vipps#create", as: :webhooks_vipps

  # Partner click redirect (last-click attribution for local programs).
  get "p/:token" => "partner/clicks#show", as: :partner_click

  # Partner program index also available on main city domain (not only markedsplass).
  namespace :partner do
    resources :programs, only: %i[index show new create edit update] do
      resources :memberships, only: :create
    end
    resources :memberships, only: :show
  end

  resources :email_subscriptions, only: %i[create destroy], param: :token
  get "confirm_email/:token" => "email_subscriptions#confirm", as: :confirm_email_subscription

  constraints(jobs_constraint) do
    mount SolidQueue::Engine, at: "/admin/jobs"
  end
  patch "location" => "locations#update", as: :location
  resources :push_subscriptions, only: %i[create destroy]
  get "nearby" => "nearby#index", as: :nearby
  get "nearby/room" => "nearby#room", as: :nearby_room
  get "nearby/widget" => "nearby#widget", as: :nearby_widget
  post "nearby" => "nearby#create"
  # /live was a Jodel-shaped feed of short anonymous posts ranked by local
  # votes. It is the ambient chat room now, per operator 2026-08-17: brgen had
  # two hyperlocal surfaces that cross-linked to each other and competed for the
  # same visitor, and the room is the one the operator means by "live".
  #
  # A redirect rather than a deletion because the path is public and was linked
  # from /nearby and the city home. #room handles the unlocated case already —
  # it sends you back to /nearby with a "turn on location" alert.
  get "live" => redirect("/nearby/room"), as: :live
  resources :channels, only: %i[index show], param: :slug
  get "search" => "search#index", as: :global_search
  get "sitemap.xml" => "sitemaps#index", as: :sitemap
  get "robots.txt" => "robots#show", as: :robots

  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
