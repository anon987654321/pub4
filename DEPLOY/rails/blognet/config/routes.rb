# frozen_string_literal: true

Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  resources :tags, only: :index do
    collection { get :autocomplete }
  end

  resources :recipes, only: %i[show new create edit update]
  resources :newsletter_subscriptions, only: :destroy, param: :token do
    member { get :confirm }
  end

  resources :blogs, path: "b" do
    resource :analytics, only: :show, controller: "analytics"
    post :checkout, to: "paywall#checkout"
    resources :newsletter_subscriptions, only: :create
    resources :posts, path: "p" do
      resources :comments, only: %i[create destroy]
    end
  end

  post "share-target" => "share_targets#create", as: :share_target

  root "blogs#index"
  get "offline" => "offline#show", as: :offline
  get "manifest" => "pwa#manifest", as: :pwa_manifest
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker
  get "up", to: "health#show", as: :rails_health_check
end
