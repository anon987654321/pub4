Rails.application.routes.draw do
  root "chat#index"
  post "chat/message",  to: "chat#message"
  post "chat/tts",      to: "chat#tts"
  post "chat/speak",    to: "chat#speak"
  get  "chat/metrics",  to: "chat#metrics"
  get  "chat/dmesg",    to: "chat#dmesg"
  get  "events/stream", to: "events#stream"
get  "canvas",         to: "canvas#show"
get  "canvas/stream",  to: "canvas#stream"
post "canvas/event",   to: "canvas#post_event"
  get  "up" => "rails/health#show", as: :rails_health_check
  get  "health" => "health#show"
end
