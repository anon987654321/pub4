# frozen_string_literal: true

# Drawn on the isolated engine, so helpers are unprefixed here (channel_path,
# video_path) and reached as tv.channel_path from the host. The host mounts this
# under constraints(subdomain: TV_SUBDOMAINS) — see brgen config/routes.rb.
Tv::Engine.routes.draw do
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
    # The row is created by videos#show; the player PATCHes watch time onto it.
    resources :view_events, only: :update
  end

  resources :live_streams, only: %i[index show update destroy] do
    resources :stream_chats, only: :create
    member do
      patch :go_live
      patch :end_live
    end
  end
end
