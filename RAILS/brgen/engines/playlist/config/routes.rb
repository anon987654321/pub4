# frozen_string_literal: true

# Drawn on the isolated engine (helpers unprefixed here, playlist.* from the host).
# Host mounts under constraints(subdomain: PLAYLIST_SUBDOMAINS) — see brgen config/routes.rb.
Playlist::Engine.routes.draw do
    root "playlists#index"
    resources :playlists do
      member { get :embed }
      resources :imports, only: :create
      resources :tracks, only: %i[create update destroy]
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
