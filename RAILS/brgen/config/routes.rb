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
  end

  resources :communities do
    resources :posts, shallow: true do
      resources :comments, shallow: true, only: %i[create destroy] do
        resources :comments, shallow: true, only: %i[create destroy], as: :replies
      end
      resource :vote, only: [ :create ], controller: "votes"
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

  resources :users, only: %i[show new create] do
    member do
      post :follow, to: "follows#create"
      delete :unfollow, to: "follows#destroy"
      get :avatar, to: "avatars#show"
    end
    resources :conversations, only: [ :create ]
  end

  resources :conversations, only: %i[index show update] do
    resources :messages, only: [ :create ]
    resources :typing_indicators, only: [ :create ]
    resource :presence, only: %i[create destroy]
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

  constraints(subdomain: DATING_SUBDOMAINS) do
    scope module: "dating", as: "dating" do
      root "home#index"
      get "next" => "home#next", as: :next
      resource :profile, only: %i[new create edit update show]
      resources :likes, only: :create
      resources :dislikes, only: :create
      resources :matches, only: :index
    end
  end

  constraints(subdomain: PLAYLIST_SUBDOMAINS) do
    scope module: "playlist", as: "playlist" do
      root "playlists#index"
      resources :playlists do
        member { get :embed }
        resources :imports, only: :create
        resources :tracks, only: %i[create destroy]
        resources :collaborations, only: %i[create destroy]
        resources :dilla_sketches, only: %i[create update destroy] do
          member { post :render_audio }
        end
      end
      resources :sets do
        resources :tracks, only: %i[create destroy]
        resources :collaborations, only: %i[create destroy]
        resources :dilla_sketches, only: %i[create update destroy] do
          member { post :render_audio }
        end
        resource :like, only: %i[create destroy]
        resource :listening_party, only: %i[create show update destroy], controller: "listening_parties" do
          resources :party_messages, only: :create
        end
      end
      resources :listens, only: :create
      resources :hosted_tracks
    end
  end

  constraints(subdomain: TAKEAWAY_SUBDOMAINS) do
    scope module: "takeaway", as: "takeaway" do
      root "restaurants#index"
      resources :restaurants do
        resource :favorite_restaurant, only: %i[create destroy]
        resources :menu_items, only: %i[create destroy]
        resources :orders, only: %i[new create]
        resources :reviews, only: %i[create]
      end
      resources :delivery_drivers, only: %i[index show update]
      resources :orders, only: %i[index show update]
    end
  end

  constraints(subdomain: MARKETPLACE_SUBDOMAINS) do
    scope module: "marketplace", as: "marketplace" do
      root "listings#index"
      resources :shops, controller: "stores"
      resources :deals, only: %i[index show]
      resources :listings do
        resource :favorite, only: %i[create destroy]
        resources :orders, only: %i[create update]
        resources :reviews, only: %i[create]
      end
      resources :orders, only: %i[show update]

      # Amazon-like cart (pending orders act as cart items for the buyer)
      resource :cart, only: :show, controller: "carts" do
        post :send_offers
      end
      resource :checkout, only: %i[create show], controller: "checkouts"
      # Not `namespace :webhooks` — inside `scope module: "marketplace"` that
      # resolves to Marketplace::Webhooks::WebhooksController, which does not
      # exist, so PSP callbacks never reached mark_paid! and orders stayed
      # unpaid. Explicit paths keep the URLs and helper names unchanged.
      post "webhooks/stripe", to: "webhooks#stripe", as: :webhooks_stripe
      post "webhooks/vipps", to: "webhooks#vipps", as: :webhooks_vipps
      resources :categories, only: :show, param: :id
      resources :saved_searches, only: %i[index create destroy]
    end

    # Solidus engines mount only when gems are loaded (SOLIDUS_MARKETPLACE=1 + install).
    # Native Marketplace::* stays the public storefront until explicit cutover.
    if defined?(Brgen::SolidusMarketplace) && Brgen::SolidusMarketplace.mountable?
      mount Spree::Core::Engine, at: "/solidus"
    end
  end

  constraints(subdomain: MAPS_SUBDOMAINS) do
    scope module: "maps", as: "maps" do
      root "home#index"
      resources :places, only: %i[index show] do
        member do
          post :check_in
        end
      end
    end
  end

  constraints(subdomain: MESSENGER_SUBDOMAINS) do
    root "conversations#index", as: :messenger_root
    resources :conversations, only: %i[show update create] do
      resources :messages, only: %i[create]
      resources :typing_indicators, only: %i[create]
      resource :presence, only: %i[create destroy]
    end
  end

  # TradeDoubler Conversions API postback (not marketplace-scoped).
  post "webhooks/tradedoubler" => "webhooks/tradedoubler#create", as: :webhooks_tradedoubler

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
  # Jodel-shaped hyperlocal Live feed (short, anonymous, radius-ranked).
  get "live" => "live#index", as: :live
  post "live" => "live#create"
  resources :channels, only: %i[index show], param: :slug
  get "search" => "search#index", as: :global_search
  get "sitemap.xml" => "sitemaps#index", as: :sitemap
  get "robots.txt" => "robots#show", as: :robots

  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
