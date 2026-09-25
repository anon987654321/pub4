# frozen_string_literal: true

Rails.application.routes.draw do
  get "up", to: "health#show", as: :health_check
  get "domains/check", to: "domains#check", as: :domain_check

  namespace :admin do
    resources :orders, only: %i[index show]
    resources :domains, only: %i[index show]
  end

  root "home#show"
end
