# frozen_string_literal: true

# APP_SPEC §3 — final, no deviations — plus the single extra route mandated by
# APP_SPEC §8: `get "checkout/zone"` feeds the zone_check Stimulus controller.
Rails.application.routes.draw do
  root "menu#show"
  get "menu", to: "menu#show"
  get "menu/:id", to: "menu#item", as: :menu_item
  get "about", to: "pages#about"

  resource :session, only: [:new, :create, :destroy]
  post "session/request_code", to: "sessions#request_code"
  get "session/vipps", to: "sessions#vipps_auth", as: :session_vipps
  get "session/vipps/callback", to: "sessions#vipps_callback", as: :session_vipps_callback

  resource :cart, only: [:show] do
    post :add_item, controller: "carts"
    patch "items/:line_id", action: :update_item, controller: "carts", as: :update_item
    delete "items/:line_id", action: :remove_item, controller: "carts", as: :remove_item
  end

  resource :checkout, only: [:show, :create], controller: "checkout"
  get "checkout/zone", to: "checkout#zone"

  resources :orders, only: [:index, :show]
  get "track/:token", to: "orders#track", as: :track
  get "track/:token/status", to: "orders#status", as: :track_status
  post "track/:token/tip", to: "orders#tip", as: :order_tip
  post "orders/:id/review", to: "reviews#create", as: :order_review

  get "loyalty", to: "loyalty#show"

  namespace :staff do
    resource :board, only: [:show]
    patch "orders/:id/advance", to: "board#advance", as: :advance_order
    patch "orders/:id/wolt", to: "board#wolt_dispatch", as: :wolt_order
  end

  namespace :courier do
    resource :runs, only: [:show]
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

  # PWA
  get "manifest.json", to: "pwa#manifest", as: :pwa_manifest
  get "service-worker.js", to: "pwa#service_worker", as: :pwa_service_worker
  get "offline", to: "pwa#offline"
end
