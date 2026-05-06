# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@stimulus-components/dialog", to: "@stimulus-components--dialog.js" # @1.0.1
pin "@stimulus-components/auto-submit", to: "@stimulus-components--auto-submit.js" # @6.0.0
pin "@stimulus-components/character-counter", to: "@stimulus-components--character-counter.js" # @5.1.0
pin "@stimulus-components/dropdown", to: "@stimulus-components--dropdown.js" # @3.0.0
pin "stimulus-use" # @0.52.3
pin "@stimulus-components/clipboard", to: "@stimulus-components--clipboard.js" # @5.0.0
pin "@stimulus-components/notification", to: "@stimulus-components--notification.js" # @3.0.0
pin "@stimulus-components/timeago", to: "@stimulus-components--timeago.js" # @5.0.2
pin "date-fns" # @4.1.0
pin "@stimulus-components/animated-number", to: "@stimulus-components--animated-number.js" # @5.0.0
pin "@stimulus-components/sortable", to: "@stimulus-components--sortable.js" # @5.0.3
pin "https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/src/fetch_request", to: "https:----cdn.jsdelivr.net--npm--@rails--request.js@0.0.13--src--fetch_request.js" # @0.0.13
pin "https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/src/fetch_response", to: "https:----cdn.jsdelivr.net--npm--@rails--request.js@0.0.13--src--fetch_response.js" # @0.0.13
pin "https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/src/lib/utils", to: "https:----cdn.jsdelivr.net--npm--@rails--request.js@0.0.13--src--lib--utils.js" # @0.0.13
pin "https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/src/request_interceptor", to: "https:----cdn.jsdelivr.net--npm--@rails--request.js@0.0.13--src--request_interceptor.js" # @0.0.13
pin "https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/src/verbs", to: "https:----cdn.jsdelivr.net--npm--@rails--request.js@0.0.13--src--verbs.js" # @0.0.13
pin "@rails/request.js", to: "@rails--request.js.js" # @0.0.13
pin "sortablejs" # @1.15.7
