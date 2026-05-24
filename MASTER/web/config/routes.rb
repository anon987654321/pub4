# frozen_string_literal: true

Rails.application.routes.draw do
  root "chat#index"
  get "dashboard", to: "dashboard#index"
  get "dashboard/live", to: "dashboard#live"
  mount ActionCable.server => "/cable"
  get  "chat/message",  to: "chat#message"
  post "chat/photo",    to: "chat#photo"
  get  "chat/enhance",  to: "chat#enhance"
  get  "chat/history", to: "chat#history"
  post "chat/command", to: "chat#command"
  get  "chat/metrics", to: "chat#metrics"
  get  "chat/dmesg",    to: "chat#dmesg"
  get  "events/stream", to: "events#stream"
  post "canvas/event",  to: "canvas#post_event"
  post "canvas/state",  to: "canvas#state"
  get  "up" => "rails/health#show", as: :rails_health_check
  get  "health" => "health#show"
end