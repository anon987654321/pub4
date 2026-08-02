# frozen_string_literal: true

# Drawn on the isolated engine (helpers unprefixed here, tv.* from the host).
# Host mounts under constraints(subdomain: DATING_SUBDOMAINS) — see brgen config/routes.rb.
Dating::Engine.routes.draw do
  root "home#index"
  get "next" => "home#next", as: :next
  resource :profile, only: %i[new create edit update show]
  resources :likes, only: :create
  resources :dislikes, only: :create
  resources :matches, only: :index
end
