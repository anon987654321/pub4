# frozen_string_literal: true

Rails.application.routes.draw do
  get "offline" => "rails/pwa#offline", as: :pwa_offline

  jobs_constraint = ->(request) { request.cookies["session_id"].present? }

  resource  :session
  instance_eval(File.read(File.expand_path("../shared/config/routes/auth.rb", __dir__)))
  resources :passwords, param: :token

  root "home#index"
  constraints(jobs_constraint) do
    mount SolidQueue::Engine, at: "/admin/jobs"
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

  resources :beneficiaries, only: %i[index show] do
    member do
      get :match
      post :claim
    end
  end

  resources :donations
  resources :boxes
  resources :volunteers do
    resources :shifts, only: %i[create]
  end
  resources :shifts, only: %i[index update]

  resources :users, only: %i[show]

  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker
  get "up", to: "rails/health#show", as: :rails_health_check
end
