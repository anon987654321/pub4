# frozen_string_literal: true

Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "scriptures#index"

  get "scripture",                to: "scriptures#index",   as: :scripture_index
  get "scripture/:abbreviation",  to: "scriptures#book",    as: :scripture_book
  get "scripture/:book_abbreviation/:number", to: "scriptures#chapter", as: :scripture_chapter
  get "search",                   to: "scriptures#search",    as: :scripture_search
  get "word_study",               to: "scriptures#word_study", as: :scripture_word_study

  resources :highlights, only: %i[create destroy]
  resources :bookmarks

  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker
  get "up", to: "health#show", as: :rails_health_check
end
