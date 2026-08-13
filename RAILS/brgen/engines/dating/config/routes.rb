# frozen_string_literal: true

# Drawn on the isolated engine (helpers unprefixed here, tv.* from the host).
# Host mounts under constraints(subdomain: DATING_SUBDOMAINS) — see brgen config/routes.rb.
Dating::Engine.routes.draw do
  root "home#index"
  get "next" => "home#next", as: :next
  resource :profile, only: %i[new create edit update show] do
    # Three answers, because a profile answering eight is a bio in disguise.
    resources :prompts, only: %i[create destroy]
  end
  # index is "who liked you" — a different decision from the deck, so a
  # different page rather than folded into it.
  resources :likes, only: %i[create index]
  resources :dislikes, only: :create
  resource :rewind, only: :create, controller: "rewinds"
  resources :matches, only: %i[index destroy]
end
