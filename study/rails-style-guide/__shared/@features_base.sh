#!/usr/bin/env zsh
# __shared/@features_base.sh — Rails 8 resource generation helpers
# Source from app installers. Do not execute directly.
set -euo pipefail

# Generate a model+controller+views (scaffold) if model absent
generate_resource() {
  local name=$1; shift
  local model_file="app/models/${name:l}.rb"
  if [[ -f $model_file ]]; then
    log_ok "resource $name already present"
    return 0
  fi
  log "Generating scaffold: $name $*"
  bin/rails generate scaffold "$name" "$@" --no-test-framework
  bin/rails db:migrate
  log_ok "resource $name done"
}

# Generate a plain model if absent
generate_model() {
  local name=$1; shift
  local model_file="app/models/${name:l}.rb"
  if [[ -f $model_file ]]; then
    log_ok "model $name already present"
    return 0
  fi
  log "Generating model: $name $*"
  bin/rails generate model "$name" "$@" --no-test-framework
  bin/rails db:migrate
  log_ok "model $name done"
}

# Write a Stimulus controller if absent
generate_stimulus() {
  local name=$1  # snake_case, e.g. posts_vote
  local path="app/javascript/controllers/${name}_controller.js"
  [[ -f $path ]] && { log_ok "stimulus $name exists"; return 0; }
  mkdir -p app/javascript/controllers
  cat > "$path" << JS
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {}
}
JS
  log_ok "Stimulus $name written"
}

# Append route block to routes.rb if pattern absent
ensure_route() {
  local pattern=$1
  local block=$2
  grep -q "$pattern" config/routes.rb 2>/dev/null && return 0
  # Insert before final 'end'
  ruby34 -i -e '
    lines = $stdin.readlines
    idx = lines.rindex { |l| l.strip == "end" }
    lines.insert(idx, ARGV[0] + "\n") if idx
    print lines.join
  ' "$block" config/routes.rb
  log_ok "route added: $pattern"
}
