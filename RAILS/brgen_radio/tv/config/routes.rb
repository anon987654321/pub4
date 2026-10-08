# frozen_string_literal: true

# Drawn on the isolated engine, so helpers are unprefixed here (channel_path,
# video_path) and reached as tv.channel_path from the host. The host mounts this
# under constraints(subdomain: TV_SUBDOMAINS) — see brgen config/routes.rb.
Tv::Engine.routes.draw do
  root "home#index"

  # home#index is the grid — the YouTube answer to "what is there". This is the
  # other shape: one video per screen, ranked by watch time.
  get "feed", to: "feed#index", as: :feed

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

  # The clips built on one piece of audio — a video had no audio identity, so
  # there was nothing to browse more of.
  resources :sounds, only: %i[index show]

  resources :videos, only: %i[show destroy] do
    resources :video_notes, only: :create
    resources :comments, only: :create
    # videos#show creates its own row; the vertical feed creates one per video
    # as it scrolls into view. Both PATCH watch time onto it.
    resources :view_events, only: %i[create update]
  end

  resources :live_streams, only: %i[index show update destroy] do
    resources :stream_chats, only: :create
    member do
      patch :go_live
      patch :end_live
    end
  end
end
