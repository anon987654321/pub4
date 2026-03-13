Rails.application.routes.draw do
  root "chat#index"

  # MASTER3 native endpoints
  post "chat/message",  to: "chat#message"
  post "chat/tts",      to: "chat#tts"
  get  "chat/metrics",  to: "chat#metrics"
  get  "chat/dmesg",    to: "chat#dmesg"

  # MASTER2 compatibility endpoints used by restored cli.html
  post "chat",    to: "chat#chat"
  get  "sse",     to: "chat#sse"
  post "tts",     to: "chat#tts"
  get  "metrics", to: "chat#metrics"

  get  "up" => "rails/health#show", as: :rails_health_check
end
