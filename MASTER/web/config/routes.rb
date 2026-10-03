# frozen_string_literal: true

Rails.application.routes.draw do
  root "chat#index"
  # chat/research, chat/enhance, chat/skills and chat/photo stay open to visitors: the face is a public
  # chatbot, a visitor spends more through chat/message than any of them costs, and each is fetched by
  # script and linked from nowhere, so no crawler finds it. enhance and photo count against the per-IP
  # write limit. chat/tts/phrases is public because the phrases are the face's idle lines.
  get "dashboard", to: "dashboard#index"
  get "dashboard/live", to: "dashboard#live"
  get  "chat/message",  to: "chat#message"
  post "chat/message",  to: "chat#message"
  post "chat/photo",    to: "chat#photo"
  get  "chat/tts",        to: "tts#show"
  get  "chat/tts/phrases", to: "tts#phrases"
  get  "chat/tts/status", to: "tts#status"
  get  "chat/tts/stream", to: "tts#stream"
  delete "chat/tts/status", to: "tts#destroy"
  get  "chat/research", to: "chat#research"
  get  "chat/enhance",  to: "chat#enhance"
  get  "chat/history", to: "chat#history"
  post "chat/command", to: "chat#command"
  get  "chat/metrics", to: "chat#metrics"
  get  "chat/skills",  to: "chat#skills"
  get  "runtime/config", to: "runtime#boot_config"
  get  "runtime/status", to: "runtime#status"
  get  "runtime/topologies", to: "runtime#topologies"
  get  "events/stream", to: "events#stream"
  get  "canvas/topology", to: "canvas#topology"
  post "canvas/event",  to: "canvas#post_event"
  post "canvas/state",  to: "canvas#state"
  get  "manifest" => "pwa#manifest", as: :pwa_manifest
  get  "up" => "rails/health#show", as: :rails_health_check
  get  "health" => "health#show"
  get  "ingress/health", to: "ingress#health"
  get  "pair", to: "pair#show"
  post "pair", to: "pair#create"
  post "pair/issue", to: "pair#issue"
  get  "pair/list", to: "pair#list"
  delete "pair/:subject", to: "pair#destroy"
  post "ingress/cron/:name", to: "ingress#cron"
  post "ingress/webhook/:name", to: "ingress#webhook"
  get  "metrics" => "chat#metrics_prometheus"
  get  "radio_bergen" => "pages#radio_bergen"
end
