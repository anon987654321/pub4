# frozen_string_literal: true

Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "ports#index"

  resources :categories, only: %i[index show]
  resources :maintainers, only: %i[index show]

  resources :ports, only: %i[index show] do
    member do
      post :watch
      delete :unwatch
      post :crossref_cves
    end
    resources :comments, only: %i[create destroy]
  end

  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker
  get "up", to: "rails/health#show", as: :rails_health_check
end
