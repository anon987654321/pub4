# frozen_string_literal: true

resources :notifications, only: %i[index update] do
  collection do
    patch :read_all
    get :badge
  end
end
resources :reactions, only: :create
resources :reports, only: :create
