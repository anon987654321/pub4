```bash
#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

check_command() {
  if ! command -v "$1" &> /dev/null; then
    log "Error: $1 command not found"
    exit 1
  fi
}

check_rails_environment() {
  if [[ -z "${RAILS_ENV:-}" ]]; then
    log "Warning: RAILS_ENV not set, defaulting to development"
    export RAILS_ENV=development
  fi

  if [[ ! -f "bin/rails" ]]; then
    log "Error: Not in a Rails application directory"
    exit 1
  fi
}

run_migration() {
  log "Running database migrations..."
  if bin/rails db:migrate; then
    log "Database migrations completed successfully"
  else
    log "Error: Database migration failed"
    exit 1
  fi
}

setup_messenger_models() {
  log "Setting up Messenger models: Conversation, Message, ConversationParticipant"

  check_command "rails"
  check_rails_environment

  # Generate all required models
  local models=(
    "Conversation conversation_type:string name:string disappearing_messages:boolean user:references last_read_at:datetime notifications_enabled:boolean"
    "Message conversation:references user:references content:text message_type:string encrypted:boolean expires_at:datetime read_at:datetime"
    "ConversationParticipant conversation:references user:references last_read_at:datetime"
  )

  for model_spec in "${models[@]}"; do
    log "Generating ${model_spec%% *} model..."
    if ! bin/rails generate model $model_spec; then
      log "Error: Failed to generate ${model_spec%% *} model"
      log "Rolling back previous migrations..."
      bin/rails db:rollback STEP=3
      exit 1
    fi
    log "${model_spec%% *} model generated successfully"
  done

  run_migration
}

setup_messenger_models
```
