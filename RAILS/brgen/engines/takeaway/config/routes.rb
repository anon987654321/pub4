# frozen_string_literal: true

# Drawn on the isolated engine (helpers unprefixed here, takeaway.* from the host).
# Host mounts under constraints(subdomain: TAKEAWAY_SUBDOMAINS) — see brgen config/routes.rb.
Takeaway::Engine.routes.draw do
    root "restaurants#index"
    resources :restaurants do
      resource :favorite_restaurant, only: %i[create destroy]
      resources :menu_items, only: %i[create destroy]
      resources :orders, only: %i[new create]
      resources :reviews, only: %i[create]
    end
    resources :delivery_drivers, only: %i[index show update]
    resources :orders, only: %i[index show update] do
      post :again, on: :member
    end
end
