#!/usr/bin/env zsh
set -euo pipefail

# Live Search Feature Module
# Pattern from colby.so/posts/live-search-with-rails-and-stimulusreflex
# and stimulusreflexpatterns.com

setup_live_search() {
  local model=$1
  local field=${2:-"name"}
  local controller_name=${model:l}s
  
  log "Setting up live search for ${model} on ${field} field"
  
  cat <<EOF > app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus"
import StimulusReflex from "stimulus_reflex"

export default class extends Controller {
  static targets = ["input", "results"]
  
  connect() {
    StimulusReflex.register(this)
  }
  
  search() {
    this.stimulate("SearchReflex#search", this.inputTarget.value, "${model}", "${field}")
  }
}
EOF

  cat <<EOF > app/reflexes/search_reflex.rb
class SearchReflex < ApplicationReflex
  def search(query = "", model_name = "Post", field = "title")
    return if query.blank?
    
    model = model_name.constantize
    @results = model.where("#{field} ILIKE ?", "%#{query}%").limit(20)
    
    morph "#search-results", ApplicationController.render(
      partial: "#{model_name.underscore.pluralize}/search_results",
      locals: { results: @results, query: query }
    )
  end
end
EOF

  log "Live search installed for ${model}"
  log "Add to view: <div data-controller='search'>"
  log "  <input data-search-target='input' data-action='keyup->search#search'>"
  log "  <div id='search-results' data-search-target='results'></div>"
  log "</div>"
}

generate_search_partial() {
  local model=$1
  local plural=${model:l}s
  
  mkdir -p "app/views/${plural}"
  
  cat <<EOF > "app/views/${plural}/_search_results.html.erb"
<% if results.any? %>
  <%= tag.div class: "search-results" do %>
    <% results.each do |result| %>
      <%= render partial: "${plural}/${model:l}", locals: { ${model:l}: result } %>
    <% end %>
  <% end %>
<% else %>
  <%= tag.p t("search.no_results", query: query), class: "no-results" %>
<% end %>
EOF

  log "Search results partial created for ${model}"
}

# Export functions
setup_live_search "$@"
