# frozen_string_literal: true

Rails.application.routes.draw do
  root "home#index"

  get "plans", to: "plans#index"
  get "plans/:slug", to: "plans#show", as: :plan
  get "legats", to: "legats#index"
  get "legats/:id", to: "legats#show", as: :legat
  post "pay/:slug", to: "payments#create", as: :pay
  get "pay/:slug", to: "payments#show", as: :payment

  get "portfolio", to: "portfolio#show"
  get "deadlines.ics", to: "deadlines#ics", as: :deadlines_ics, format: false
  get "deadlines", to: "deadlines#index"

  namespace :api do
    get "plans", to: "plans#index"
    get "legats", to: "legats#index"
  end

  get "sitemap.xml", to: "sitemaps#show", as: :sitemap, defaults: { format: "xml" }
  get "robots.txt", to: "robots#show", as: :robots, defaults: { format: "txt" }

  get "up", to: "rails/health#show", as: :rails_health_check
end