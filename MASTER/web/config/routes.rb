# frozen_string_literal: true

Rails.application.routes.draw do
  root "chat#index"
  get "dashboard", to: "dashboard#index"
  get "dashboard/live", to: "dashboard#live"
  mount ActionCable.server => "/cable"
  get  "chat/message",  to: "chat#message"
  post "chat/photo",    to: "chat#photo"
  get  "chat/tts",        to: "tts#show"
  get  "chat/tts/status", to: "tts#status"
  delete "chat/tts/status", to: "tts#destroy"
  get  "chat/research", to: "chat#research"
  get  "chat/enhance",  to: "chat#enhance"
  get  "chat/history", to: "chat#history"
  post "chat/command", to: "chat#command"
  get  "chat/metrics", to: "chat#metrics"
  get  "chat/skills",  to: "chat#skills"
  get  "chat/dmesg",    to: "chat#dmesg"
  get  "events/stream", to: "events#stream"
  post "canvas/event",  to: "canvas#post_event"
  post "canvas/state",  to: "canvas#state"
  get  "manifest" => "pwa#manifest", as: :pwa_manifest
  get  "up" => "rails/health#show", as: :rails_health_check
  get  "health" => "health#show"
end
