#!/usr/bin/env sh
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2
}

error() {
  log "ERROR: $*"
  exit 1
}

check_rails_environment() {
  : "${RAILS_ENV:=development}"
  [ -n "${RAILS_ENV}" ] || error "RAILS_ENV is empty after defaulting"
  [ -x "bin/rails" ] || error "bin/rails not found – run inside a Rails application"
  command -v bin/rails >/dev/null || error "bin/rails is not executable"
}

model_exists() {
  # Returns 0 if a model file with the given name exists in app/models
  local name=$1
  [ -f "app/models/${name}.rb" ] || [ -f "app/models/${name.underscore}.rb" ]
}

generate_model() {
  local name=$1
  shift
  log "Generating model ${name}..."
  bin/rails generate model "${name}" "$@" --no-test-framework
}

setup_messenger_models() {
  check_rails_environment

  models="
Conversation conversation_type:string name:string disappearing_messages:boolean user:references last_read_at:datetime notifications_enabled:boolean
Message conversation:references user:references content:text message_type:string encrypted:boolean expires_at:datetime read_at:datetime
ConversationParticipant conversation:references user:references last_read_at:datetime
"

  while IFS= read -r line; do
    [ -z "${line%[[:space:]]*}" ] && continue
    set -- $line
    model_name=$1
    shift
    if model_exists "${model_name}"; then
      log "Model ${model_name} already exists – skipping generation"
      continue
    fi
    generate_model "${model_name}" "$@"
  done <<EOF
$models
EOF

  log "Running migrations..."
  bin/rails db:migrate
  log "Messenger models configured successfully"
}

setup_messenger_models