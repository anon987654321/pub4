# frozen_string_literal: true

Rails.application.routes.draw do
  root "welcome#index"
  
  resources :projects do
    member do
      patch :toggle_active
    end
  end

  get "about", to: "pages#about"
  get "contact", to: "pages#contact"
end
