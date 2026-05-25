# frozen_string_literal: true

Rails.application.routes.draw do
  resources :donations, only: [:index, :show, :create]
  resources :boxes, only: [:index, :show]
  resources :volunteers, only: [:create, :show]
  resources :shifts, only: [:index, :update]
  get "rails/health" => "rails/health#show", as: :rails_health_check
end
