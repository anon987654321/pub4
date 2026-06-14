# frozen_string_literal: true

Rails.application.routes.draw do
  get "offline" => "rails/pwa#offline", as: :pwa_offline
  post "share" => "posts#share", as: :share_post

  jobs_constraint = ->(request) { request.cookies["session_id"].present? }

  resource  :session
  resources :passwords, param: :token

  resources :blogs, path: "b" do
    resources :posts, path: "p" do
      resources :comments, only: %i[create destroy]
    end
  end
  patch "drafts/:id", to: "drafts#update", as: :draft

  root "blogs#index"
  constraints(jobs_constraint) do
    mount SolidQueue::Engine, at: "/admin/jobs"
  end
  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker
  get "up", to: "rails/health#show", as: :rails_health_check
end
