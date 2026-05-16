Rails.application.routes.draw do
  root "chat#index"
  get "dashboard", to: "dashboard#index"
  get "dashboard/live", to: "dashboard#live"
  mount ActionCable.server => "/cable"
  get  "chat/message",  to: "chat#message"
  get  "chat/history", to: "chat#history"
  post "chat/command", to: "chat#command"
  post "chat/tts",      to: "chat#tts"
  post "chat/speak",    to: "chat#speak"
  get  "chat/metrics",  to: "chat#metrics"
  get  "chat/dmesg",    to: "chat#dmesg"
  get  "events/stream", to: "events#stream"
  post "canvas/event",  to: "canvas#post_event"
  post "canvas/state",  to: "canvas#state"
  get  "up" => "rails/health#show", as: :rails_health_check
  get  "health" => "health#show"
end