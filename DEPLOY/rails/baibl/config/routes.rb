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

  resources :verses, only: [] do
    resources :annotations, only: %i[index create]
    resource :cross_reference_graph, only: :show, controller: "cross_references"
  end
  resources :annotations, only: :destroy
  resources :reading_plans do
    member { post :complete_day }
  end
  resource :theological_assistant, only: %i[show create], controller: "theological_assistant"

  resources :highlights, only: %i[create destroy]
  resources :bookmarks

  get "offline" => "offline#show", as: :offline
  get "manifest" => "pwa#manifest", as: :pwa_manifest
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker
  get "up", to: "health#show", as: :rails_health_check
end
