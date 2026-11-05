# frozen_string_literal: true

# APP_SPEC §3 — final, no deviations — plus the single extra route mandated by
# APP_SPEC §8: `get "checkout/zone"` feeds the zone_check Stimulus controller.
# Operator addition (2026-11-02): the three stripe/* routes wire the second
# payment lane (Stripe Checkout) mandated for Mr. Damascy — mock stand-in and
# real webhook, mirroring the vipps/* pair. Everything else is §3 verbatim.
Rails.application.routes.draw do
  # Liveness for rc.d/mrdamascy and relayd's backend check on vm23.
  get "up", to: "rails/health#show", as: :rails_health_check

  root "menu#show"
  get "menu", to: "menu#show"
  get "menu/:id", to: "menu#item", as: :menu_item
  get "about", to: "pages#about"

  resource :session, only: [ :new, :create, :destroy ]
  post "session/request_code", to: "sessions#request_code"
  get "session/vipps", to: "sessions#vipps_auth", as: :session_vipps
  get "session/vipps/callback", to: "sessions#vipps_callback", as: :session_vipps_callback

  resource :cart, only: [ :show ] do
    post :add_item, controller: "carts"
    post :reorder, controller: "carts"
    patch "items/:line_id", action: :update_item, controller: "carts", as: :update_item
    delete "items/:line_id", action: :remove_item, controller: "carts", as: :remove_item
  end

  resource :checkout, only: [ :show, :create ], controller: "checkout"
  get "checkout/zone", to: "checkout#zone"

  resources :orders, only: [ :index, :show ]
  get "track/:token", to: "orders#track", as: :track
  get "track/:token/status", to: "orders#status", as: :track_status
  post "track/:token/tip", to: "orders#tip", as: :order_tip
  post "orders/:id/review", to: "reviews#create", as: :order_review

  get "loyalty", to: "loyalty#show"

  namespace :staff do
    get "board", to: "board#show", as: :board
    patch "orders/:id/advance", to: "board#advance", as: :advance_order
    patch "orders/:id/wolt", to: "board#wolt_dispatch", as: :wolt_order
    patch "orders/:id/cancel", to: "board#cancel", as: :cancel_order
    patch "orders/:id/refunded", to: "board#refunded", as: :refunded_order
  end

  namespace :courier do
    resource :runs, only: [ :show ]
    patch "orders/:id/pickup", to: "runs#pickup", as: :pickup_order
    patch "orders/:id/deliver", to: "runs#deliver", as: :deliver_order
  end

  get "vipps/mock", to: "vipps#mock"          # dev/test Vipps-app stand-in
  patch "vipps/mock/approve", to: "vipps#approve"
  get "vipps/login_mock", to: "vipps#login_mock" # dev/test Vipps-login stand-in

  # Real Vipps webhook (ePayment events): Authorization header carries the
  # webhook secret; body is [{reference:, state:, …}]. CSRF-exempt in the
  # controller — see VippsController#callback.
  post "vipps/callback", to: "vipps#callback"

  # Second payment lane (operator-mandated): Stripe Checkout. Same shape as
  # the vipps routes — mock approval page + real webhook. The webhook is
  # HMAC-signed via the Stripe-Signature header (StripeController#callback).
  get "stripe/mock", to: "stripe#mock"             # dev/test Checkout stand-in
  patch "stripe/mock/approve", to: "stripe#approve"
  post "stripe/callback", to: "stripe#callback"    # real Stripe webhook

  # Content-Security-Policy violation reports (the policy's report-uri).
  post "csp-reports", to: "csp_reports#create", as: :csp_reports

  # PWA
  get "manifest.json", to: "pwa#manifest", as: :pwa_manifest
  get "service-worker.js", to: "pwa#service_worker", as: :pwa_service_worker
  get "offline", to: "pwa#offline"
end
