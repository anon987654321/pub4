Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "scriptures#index"

  get "scripture",                to: "scriptures#index",   as: :scripture_index
  get "scripture/:abbreviation",  to: "scriptures#book",    as: :scripture_book
  get "scripture/:book_abbreviation/:number", to: "scriptures#chapter", as: :scripture_chapter
  get "search",                   to: "scriptures#search",  as: :scripture_search

  resources :highlights, only: %i[create destroy]
  resources :bookmarks

  get "up", to: "rails/health#show", as: :rails_health_check
end
