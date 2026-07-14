# frozen_string_literal: true

require "brgen/domain_registry"

Rails.application.routes.draw do
  get "offline" => "rails/pwa#offline", as: :pwa_offline
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  post "share" => "posts#share", as: :share_post
  # Loopback-only in practice (see InternalController's shared-secret gate);
  # not subdomain-constrained since MASTER calls it directly by IP:port.
  get "internal/status" => "internal#status", as: :internal_status

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

  resource  :session
  resources :passwords, param: :token
  instance_eval(File.read(File.expand_path("../../shared/config/routes/auth.rb", __dir__)))
  instance_eval(File.read(File.expand_path("../../shared/config/routes/fleet.rb", __dir__)))
  resources :activity_events, only: :index
  resources :notifications, only: %i[index update] do
    collection do
      patch :read_all
      get :badge
    end
  end
  resources :reactions, only: :create
  resources :reports, only: :create

  namespace :admin do
    resources :reports, only: %i[index update]
  end

  resources :communities do
    resources :posts, shallow: true do
      resources :comments, shallow: true do
        resources :comments, shallow: true, as: :replies
      end
      resource :vote, only: [ :create ], controller: "votes"
    end
  end

  resources :posts do
    resources :comments, shallow: true
    resource :vote, only: [ :create ], controller: "votes"
  end
  patch "drafts/:id", to: "drafts#update", as: :draft

  resources :comments do
    resource :vote, only: [ :create ], controller: "votes"
    resources :comments, only: [ :create ], as: :replies
    member do
      post :generate_summary
    end
  end

  resources :users, only: [ :show ] do
    member do
      post :follow, to: "follows#create"
      delete :unfollow, to: "follows#destroy"
    end
    resources :conversations, only: [ :create ]
  end

  resources :conversations, only: %i[index show update] do
    resources :messages, only: [ :create ]
    resources :typing_indicators, only: [ :create ]
  end

  constraints(subdomain: TV_SUBDOMAINS) do
    scope module: "tv", as: "tv" do
      root "home#index"
      resources :channels, param: :slug do
        member do
          post :subscribe
          delete :unsubscribe
        end
        resources :videos, only: %i[new create]
        resources :live_streams, only: %i[new create]
        resources :shows, param: :slug, only: %i[index show] do
          get "episodes/:number", to: "episodes#show", as: :episode, on: :member
        end
      end
      resources :videos, only: %i[show destroy] do
        resources :video_notes, only: :create
        resources :comments, only: :create
      end
      resources :live_streams, only: %i[index show update destroy] do
        resources :stream_chats, only: :create
        member do
          patch :go_live
          patch :end_live
        end
      end
    end
  end

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
        resources :dilla_sketches, only: %i[create update destroy]
      end
      resources :sets do
        resources :tracks, only: %i[create destroy]
        resources :collaborations, only: %i[create destroy]
        resources :dilla_sketches, only: %i[create update destroy]
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
      root "listings#index", as: :marketplace_root
      resources :shops, controller: "stores"
      resources :deals, only: %i[index show]
      resources :listings do
        resource :favorite, only: %i[create destroy]
        resources :orders, only: %i[create update]
        resources :reviews, only: %i[create]
      end
      resources :orders, only: %i[show update]

      # Amazon-like cart (pending orders act as cart items for the buyer)
      resource :cart, only: :show, controller: "carts"
      resources :categories, only: :show, param: :id
      resources :saved_searches, only: %i[index create destroy]
    end
  end

  constraints(subdomain: MAPS_SUBDOMAINS) do
    scope module: "maps", as: "maps" do
      root "home#index", as: :maps_root
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
    end
  end

  resources :email_subscriptions, only: %i[create destroy], param: :token
  get "confirm_email/:token" => "email_subscriptions#confirm", as: :confirm_email_subscription

  constraints(jobs_constraint) do
    mount SolidQueue::Engine, at: "/admin/jobs"
  end
  patch "location" => "locations#update", as: :location
  resources :push_subscriptions, only: %i[create destroy]
  get "nearby" => "nearby#index", as: :nearby
  post "nearby" => "nearby#create"
  get "search" => "search#index", as: :global_search
  get "sitemap.xml" => "sitemaps#index", as: :sitemap
  get "robots.txt" => "robots#show", as: :robots

  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
