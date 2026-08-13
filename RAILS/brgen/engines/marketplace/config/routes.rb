# frozen_string_literal: true

# Drawn on the isolated engine (helpers unprefixed here, marketplace.* from the
# host). Host mounts under constraints(subdomain: MARKETPLACE_SUBDOMAINS) — see
# brgen config/routes.rb. The Amazon-style multi-seller storefront.
Marketplace::Engine.routes.draw do
  root "listings#index"
  resources :shops, controller: "stores"
  resources :deals, only: %i[index show]
  resources :listings do
    resource :favorite, only: %i[create destroy]
    resources :orders, only: %i[create update]
    resources :reviews, only: %i[create]
  end
  resources :orders, only: %i[index show update]

  # Amazon-like cart (pending orders act as cart items for the buyer)
  resource :cart, only: :show, controller: "carts" do
    post :send_offers
  end
  resource :checkout, only: %i[create show], controller: "checkouts"
  # Where the parcel goes. Its own record rather than fields on the checkout, so
  # a second purchase does not mean typing it again and a later edit does not
  # rewrite the address printed on last month's label.
  resources :addresses, only: %i[index create update destroy]
  # Not `namespace :webhooks` — inside the marketplace scope that resolved to
  # Marketplace::Webhooks::WebhooksController, which does not exist, so PSP
  # callbacks never reached mark_paid! and orders stayed unpaid. Explicit paths
  # keep the URLs and helper names unchanged.
  post "webhooks/stripe", to: "webhooks#stripe", as: :webhooks_stripe
  post "webhooks/vipps", to: "webhooks#vipps", as: :webhooks_vipps
  resources :categories, only: :show, param: :id
  resources :saved_searches, only: %i[index create destroy]

  # Solidus engines mount only when the gem is loaded (SOLIDUS_MARKETPLACE=1 +
  # install). Native Marketplace::* stays the public storefront until explicit
  # cutover. Moved into the engine with the rest of marketplace's routing.
  if defined?(Brgen::SolidusMarketplace) && Brgen::SolidusMarketplace.mountable?
    mount Spree::Core::Engine, at: "/solidus"
  end
end
