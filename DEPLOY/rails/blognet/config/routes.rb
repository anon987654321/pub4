# frozen_string_literal: true

Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  resources :blogs, path: "b" do
    resources :posts, path: "p" do
      resources :comments, only: %i[create destroy]
    end
  end

  root "blogs#index"
  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker
  get "up", to: "health#show", as: :rails_health_check
end
