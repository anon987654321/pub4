# frozen_string_literal: true

Rails.application.routes.draw do
  get "offline" => "rails/pwa#offline", as: :pwa_offline

  jobs_constraint = ->(request) { request.cookies["session_id"].present? }

  resource :session
  instance_eval(File.read(File.expand_path("../../shared/config/routes/auth.rb", __dir__)))
  resources :passwords, param: :token

  root "scriptures#index"
  constraints(jobs_constraint) do
    mount SolidQueue::Engine, at: "/admin/jobs"
  end

  get "scripture",                to: "scriptures#index",   as: :scripture_index
  get "scripture/:abbreviation",  to: "scriptures#book",    as: :scripture_book
  get "scripture/:book_abbreviation/:number", to: "scriptures#chapter", as: :scripture_chapter
  get "search",                   to: "scriptures#search",    as: :scripture_search
  get "word_study",               to: "scriptures#word_study", as: :scripture_word_study
  get "compare",                  to: "scriptures#compare",    as: :scripture_compare  # multi-tradition: Bible / Quran / Bhagavad Gita etc. + viz

  resources :highlights, only: %i[create destroy]
  resources :bookmarks

  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "up", to: "rails/health#show", as: :rails_health_check
end
