# frozen_string_literal: true

Rails.application.routes.draw do
  get "offline" => "rails/pwa#offline", as: :pwa_offline
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  post "share" => "posts#share", as: :share_post

  jobs_constraint = ->(request) { request.cookies["session_id"].present? }

  TV_SUBDOMAINS          = %w[tv].freeze
  DATING_SUBDOMAINS      = %w[dating].freeze
  PLAYLIST_SUBDOMAINS    = %w[playlist].freeze
  TAKEAWAY_SUBDOMAINS    = %w[takeaway].freeze
  MARKETPLACE_SUBDOMAINS = %w[markedsplass markadur marknadsplats marktplaats marktplatz marche mercato mercado
                              markkinapaikka marketplace].freeze
  MAPS_SUBDOMAINS        = %w[maps].freeze
  MESSENGER_SUBDOMAINS   = %w[messenger].freeze

  resource  :session
  resources :passwords, param: :token
  instance_eval(File.read(File.expand_path("../../shared/config/routes/auth.rb", __dir__)))
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

  resources :conversations, only: %i[index show] do
    resources :messages, only: [ :create ]
    resources :typing_indicators, only: [ :create ]
  end

  constraints(subdomain: TV_SUBDOMAINS) do
    scope module: "tv", as: "tv" do
      root "home#index", as: :tv_root
      resources :channels, param: :slug do
        member do
          post :subscribe
          delete :unsubscribe
        end
        resources :videos, only: %i[new create]
        resources :live_streams, only: %i[new create]
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
      root "home#index", as: :dating_root
      get "next" => "home#next", as: :dating_next
      resource :profile, only: %i[new create edit update show]
      resources :likes, only: :create
      resources :dislikes, only: :create
      resources :matches, only: :index
    end
  end

  constraints(subdomain: PLAYLIST_SUBDOMAINS) do
    scope module: "playlist", as: "playlist" do
      root "playlists#index", as: :playlist_root
      resources :playlists do
        resources :tracks, only: %i[create destroy]
        resources :collaborations, only: %i[create destroy]
        resources :dilla_sketches, only: %i[create update destroy]
      end
      resources :sets do
        resources :tracks, only: %i[create destroy]
        resources :collaborations, only: %i[create destroy]
        resources :dilla_sketches, only: %i[create update destroy]
        resource :like, only: %i[create destroy]
      end
      resources :listens, only: :create
    end
  end

  constraints(subdomain: TAKEAWAY_SUBDOMAINS) do
    scope module: "takeaway", as: "takeaway" do
      root "restaurants#index", as: :takeaway_root
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
      resources :places, only: %i[index show]
    end
  end

  constraints(subdomain: MESSENGER_SUBDOMAINS) do
    root "conversations#index", as: :messenger_root
    resources :conversations, only: %i[index show] do
      resources :messages, only: [:create]
      resources :typing_indicators, only: [:create]
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

  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
