# frozen_string_literal: true

# Shared fleet routes — instance_eval from each app's config/routes.rb

get "health", to: "fleet_health#show"
post "web_vitals", to: "web_vitals#create"
post "csp-reports", to: "csp_reports#create"
