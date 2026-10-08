# frozen_string_literal: true

Maps::Engine.routes.draw do
  root "home#index"
  resources :places, only: %i[index show] do
    member do
      post :check_in
    end
  end
end
