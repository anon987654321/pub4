# frozen_string_literal: true

Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "home#index"

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

  resources :users, only: %i[show]

  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker
  get "up", to: "rails/health#show", as: :rails_health_check
end
