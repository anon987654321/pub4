# frozen_string_literal: true

Rails.application.routes.draw do
  resource  :session
  instance_eval(File.read(File.expand_path("../shared/config/routes/auth.rb", __dir__)))
  resources :passwords, param: :token

  root "home#index"

  get "impact", to: "impact#show", as: :impact
  resource :matching, only: :show, controller: "matching"
  resources :partners
  resources :transfers, only: :create do
    collection { get :optimize_route }
  end

  resources :resources
  resources :food_listings do
    resources :food_requests, only: %i[create update]
  end

  scope :community do
    get  "/",       to: "community#index", as: :community
    get  "/:id",    to: "community#show",  as: :community_show
    get  "/new",    to: "community#new",   as: :new_community_post
    post "/",       to: "community#create"
    resources :comments, only: %i[create destroy]
  end

  resources :donations
  resources :boxes
  resources :volunteers do
    resources :shifts, only: %i[create]
  end
  resources :shifts, only: %i[index update]

  resources :users, only: %i[show]

  get "offline" => "offline#show", as: :offline
  get "manifest" => "pwa#manifest", as: :pwa_manifest
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker
  get "up", to: "health#show", as: :rails_health_check
end
