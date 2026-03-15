#!/usr/bin/env zsh
set -euo pipefail

log() {
  print -u2 -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

check_rails_environment() {
  if [[ -z "${RAILS_ENV:-}" ]]; then
    export RAILS_ENV=development
    log "RAILS_ENV not set. Defaulting to development"
  fi

  [[ -x "bin/rails" ]] || {
    log "Error: bin/rails not found. Run this inside a Rails application"
    return 1
  }
}

setup_messenger_models() {
  check_rails_environment || return 1

  local -a models=(
    "Conversation conversation_type:string name:string disappearing_messages:boolean user:references last_read_at:datetime notifications_enabled:boolean"
    "Message conversation:references user:references content:text message_type:string encrypted:boolean expires_at:datetime read_at:datetime"
    "ConversationParticipant conversation:references user:references last_read_at:datetime"
  )

  local model_spec model_name
  for model_spec in "${models[@]}"; do
    model_name="${model_spec%% *}"
    log "Generating model ${model_name}..."
    bin/rails generate model ${=model_spec}
  done

  log "Running migrations..."
  bin/rails db:migrate
  log "Messenger models configured successfully"
}
