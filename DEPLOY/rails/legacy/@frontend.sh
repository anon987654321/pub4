#!/usr/bin/env zsh
# @frontend.sh — sourced via @shared_functions.sh
set -euo pipefail


# Stimulus + Importmap
setup_stimulus() {
  log "Setting up Stimulus"
  bin/importmap pin @hotwired/stimulus --download 2>/dev/null || true
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/application.js << 'JS'
import { Application } from "@hotwired/stimulus"
const application = Application.start()
application.debug = false
window.Stimulus = application
export { application }
JS
  cat > app/javascript/controllers/index.js << 'JS'
import { application } from "./application"
// controllers are auto-imported via eagerLoadControllersFrom in application.js
// or listed here explicitly:
JS
  cat >> app/javascript/application.js << 'JS'

import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
JS
  log_ok "Stimulus ready"
}

write_stimulus_controller() {
  local name=$1
  mkdir -p app/javascript/controllers
  cat > "app/javascript/controllers/${name}_controller.js"
  log_ok "Stimulus ${name}_controller.js written"
}

# Pagy
setup_pagy() {
  add_gem pagy
  # Pagy 9+ (v43+): no initializer needed; Backend is now Pagy::Method
  ruby34 -e "
    src = File.read('app/controllers/application_controller.rb')
    unless src.include?('Pagy::Method')
      src.sub!(/class ApplicationController.*\n/, \"\\\\0  include Pagy::Method\n\")
      File.write('app/controllers/application_controller.rb', src)
    end
  "
  log_ok "Pagy configured"
}
