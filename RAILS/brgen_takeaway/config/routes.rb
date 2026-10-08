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
      # The host opens their own ticket to the link.
      resource :group, only: :create, controller: "group_orders"
    end
    # The shared ticket, addressed by its token rather than its id: an order id
    # in a link pasted into a group chat lets somebody read the next lunch by
    # counting.
    resources :group_orders, only: %i[show update destroy], param: :id, path: "group"
end
