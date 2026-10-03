# frozen_string_literal: true

resources :notifications, only: %i[index update] do
  collection do
    patch :read_all
    get :badge
  end
end
resources :reactions, only: :create
resources :reports, only: :create

# Outbound affiliate/partner clicks. A beacon, not a redirect: this endpoint never
# receives a URL it will send anyone to, so it cannot become an open redirect, and
# the anchor keeps the merchant URL so the Link Converter script can still rewrite
# it. See Shared::OutboundClicksController.
resources :outbound_clicks, only: :create
