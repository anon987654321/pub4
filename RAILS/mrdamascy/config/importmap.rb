# frozen_string_literal: true

# Pin the Hotwire stack and the application's own modules. Local files win —
# the app has no CDN-hosted third-party JavaScript.

pin "application"
pin "money"

pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

pin_all_from "app/javascript/controllers", under: "controllers"
