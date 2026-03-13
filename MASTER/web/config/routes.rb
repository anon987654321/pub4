Rails.application.routes.draw do
  root "chat#index"
  post "chat/message",  to: "chat#message"
  post "chat/tts",      to: "chat#tts"
  get  "chat/metrics",  to: "chat#metrics"
  get  "chat/dmesg",    to: "chat#dmesg"
  get  "up" => "rails/health#show", as: :rails_health_check
end
