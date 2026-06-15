# frozen_string_literal: true

Rails.application.routes.draw do
  get "offline" => "rails/pwa#offline", as: :pwa_offline

  jobs_constraint = ->(request) { request.cookies["session_id"].present? }

  resource  :session
  instance_eval(File.read(File.expand_path("../shared/config/routes/auth.rb", __dir__)))
  resources :passwords, param: :token

  root "ports#index"
  constraints(jobs_constraint) do
    mount SolidQueue::Engine, at: "/admin/jobs"
  end

  resources :categories, only: %i[index show]
  resources :maintainers, only: %i[index show]

  resources :ports, only: %i[index show] do
    member do
      post :watch
      delete :unwatch
      post :crossref_cves
      post :review
    end
    resources :comments, only: %i[create destroy]
  end

  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker
  get "up", to: "rails/health#show", as: :rails_health_check
end
