#!/bin/zsh
# amber.sh
# Generate Amber as a first-class Rails app scaffold through MASTER.

set -euo pipefail

script_dir=${0:a:h}
source "$script_dir/@master_guard.zsh"

log "Generating Amber Rails scaffold"

rails=$(rails_bin)
run_if_missing amber "$rails" new amber --database=sqlite3 --skip-test
cd amber

mkdir -p app/controllers/amber app/views/amber/examples app/views/shared app/javascript/controllers

run_if_missing app/models/amber/example.rb bin/rails generate model Amber::Example title:string body:text status:string
bin/rails generate controller Amber::Examples index show 2>/dev/null || true
bin/rails generate stimulus live_search 2>/dev/null || true

guarded_write app/controllers/amber/examples_controller.rb <<'EOF'
module Amber
  class ExamplesController < ApplicationController
    def index
      @examples = Example.order(created_at: :desc)

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def show
      @example = Example.find(params[:id])
    end
  end
end
EOF

guarded_write app/views/amber/examples/index.html.erb <<'EOF'
<h1>Amber</h1>

<div
  data-controller="live-search"
  data-live-search-url-value="<%= amber_examples_path %>">
  <input
    data-live-search-target="input"
    placeholder="Search Amber examples...">

  <div data-live-search-target="results">
    <%= render partial: "example", collection: @examples %>
  </div>
</div>
EOF

guarded_write app/views/amber/examples/_example.html.erb <<'EOF'
<article class="amber-example-card">
  <h2><%= link_to example.title, amber_example_path(example) %></h2>
  <p><%= truncate(example.body.to_s, length: 160) %></p>
</article>
EOF

guarded_sweep_generated app/controllers/amber
cd ..
log "Amber scaffold complete"
