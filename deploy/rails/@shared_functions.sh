#!/usr/bin/env zsh
# Shared functions for Rails app generators
# Per master.yml v206 workflow: Extract duplication, DRY, modern zsh

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Generate base application.scss with CSS variables
generate_application_scss() {

  typeset theme_color="${1:-#0066ff}"

  typeset dark_mode="${2:-true}"

  typeset -r target="app/assets/stylesheets/application.scss"

  [[ -d ${target:h} ]] || mkdir -p ${target:h}
  print -r "/* Generated per master.yml v206 */
:root {

  --primary: ${theme_color};

  --bg: #ffffff;

  --surface: #f8f9fa;

  --text: #1a1a1a;

  --border: #dadce0;

  --spacing: 1rem;

}" > $target

  if [[ $dark_mode == true ]]; then
    print -r "

@media (prefers-color-scheme: dark) {

  :root {

    --bg: #1a1a1a;

    --surface: #2a2a2a;

    --text: #ffffff;

    --border: #3a3a3a;

  }

}" >> $target

  fi

  print -r "
* {

  box-sizing: border-box;

  margin: 0;

  padding: 0;

}

body {
  font-family: system-ui, -apple-system, sans-serif;

  background: var(--bg);

  color: var(--text);

  line-height: 1.6;

}

main {
  max-width: 1200px;

  margin: 0 auto;

  padding: var(--spacing);

}" >> $target

}

# Generate secure controller with authentication + authorization
generate_secure_controller() {

  typeset name=$1

  typeset model=${name:l}

  typeset model_class=${(C)name}

  typeset -r target="app/controllers/${model}_controller.rb"

  [[ -d ${target:h} ]] || mkdir -p ${target:h}
  cat > $target << RUBY
class ${model_class}Controller < ApplicationController

  before_action :authenticate_user!, except: [:index, :show]

  before_action :set_${model}, only: [:show, :edit, :update, :destroy]

  before_action :authorize_user!, only: [:edit, :update, :destroy]

  def index
    @pagy, @${model}s = pagy(${model_class}.all.order(created_at: :desc))

  end

  def show
  end

  def new
    @${model} = current_user.${model}s.build

  end

  def create
    @${model} = current_user.${model}s.build(${model}_params)

    if @${model}.save

      respond_to do |format|

        format.html { redirect_to @${model}, notice: t("${model}.created") }

        format.turbo_stream

      end

    else

      render :new, status: :unprocessable_entity

    end

  end

  def edit
  end

  def update
    if @${model}.update(${model}_params)

      respond_to do |format|

        format.html { redirect_to @${model}, notice: t("${model}.updated") }

        format.turbo_stream

      end

    else

      render :edit, status: :unprocessable_entity

    end

  end

  def destroy
    @${model}.destroy

    redirect_to ${model}s_path, notice: t("${model}.destroyed")

  end

  private
  def set_${model}
    @${model} = ${model_class}.find(params[:id])

  end

  def authorize_user!
    unless @${model}.user == current_user || current_user&.admin?

      redirect_to ${model}s_path, alert: t('unauthorized')

    end

  end

  def ${model}_params
    # Override this method in the calling script with actual permitted params

    params.require(:${model}).permit(:title, :content)

  end

end

RUBY

}

# Generate Stimulus controller boilerplate
generate_stimulus_controller() {

  typeset name=$1

  shift

  typeset -a targets=("$@")

  typeset -r target_dir="app/javascript/controllers"

  typeset -r target="${target_dir}/${name}_controller.js"

  [[ -d $target_dir ]] || mkdir -p $target_dir
  # Convert array to comma-separated quoted strings
  typeset targets_str="${(j:, :)${(@qq)targets}}"

  print -r > $target << JS
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [${targets_str}]

  connect() {
    console.log("${name} controller connected")

  }

  // Add your actions here
}

JS

}

# Generate application layout with Stimulus/Turbo
generate_application_layout() {

  typeset app_name="$1"

  typeset description="$2"

  mkdir -p app/views/layouts
  cat > app/views/layouts/application.html.erb << LAYOUT
<!DOCTYPE html>

<html lang="<%= I18n.locale %>">

<head>

  <meta charset="utf-8">

  <meta name="viewport" content="width=device-width,initial-scale=1">

  <title><%= content_for?(:title) ? yield(:title) + " - ${app_name}" : "${app_name}" %></title>

  <meta name="description" content="<%= content_for?(:description) ? yield(:description) : '${description}' %>">

  <%= csrf_meta_tags %>

  <%= csp_meta_tag %>

  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>

  <%= javascript_importmap_tags %>

</head>

<body class="<%= controller_name %> <%= action_name %>">

  <%= yield %>

</body>

</html>

LAYOUT

}

# Setup stimulus-components via importmap (replaces StimulusReflex)
setup_stimulus_components() {
  grep -q "stimulus-components" config/importmap.rb 2>/dev/null && return 0
  cat >> config/importmap.rb << 'PINS'

# stimulus-components drop-in UI controllers
pin "@stimulus-components/notification", to: "https://cdn.jsdelivr.net/npm/@stimulus-components/notification/dist/stimulus-notification.mjs"
pin "@stimulus-components/dialog", to: "https://cdn.jsdelivr.net/npm/@stimulus-components/dialog/dist/stimulus-dialog.mjs"
pin "@stimulus-components/clipboard", to: "https://cdn.jsdelivr.net/npm/@stimulus-components/clipboard/dist/stimulus-clipboard.mjs"
pin "@stimulus-components/sortable", to: "https://cdn.jsdelivr.net/npm/@stimulus-components/sortable/dist/stimulus-sortable.mjs"
pin "@stimulus-components/remote-rails", to: "https://cdn.jsdelivr.net/npm/@stimulus-components/remote-rails/dist/stimulus-remote-rails.mjs"
pin "@stimulus-components/textarea-autogrow", to: "https://cdn.jsdelivr.net/npm/@stimulus-components/textarea-autogrow/dist/stimulus-textarea-autogrow.mjs"
PINS
  log "stimulus-components pinned to importmap"
}

# Add acts_as_votable with proper setup
setup_voting() {

  grep -q "acts_as_votable" Gemfile || cat >> Gemfile << 'GEMS'

gem "acts_as_votable"

GEMS

  bundle install
  bin/rails generate acts_as_votable:migration

  bin/rails db:migrate

}

# Generate voting Stimulus controller
generate_voting_stimulus() {

  cat > app/javascript/controllers/vote_controller.js << 'JS'

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { type: String, id: Number }

  static targets = ["score", "upvote", "downvote"]

  async vote(event) {
    const action = event.params.action

    const response = await fetch(`/${this.typeValue}/${this.idValue}/${action}`, {

      method: action === 'unvote' ? 'DELETE' : 'POST',

      headers: {

        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,

        'Accept': 'application/json'

      }

    })

    if (response.ok) {
      const data = await response.json()

      this.scoreTarget.textContent = data.score

      this.updateButtons(action)

    }

  }

  updateButtons(action) {
    this.upvoteTarget.classList.toggle('active', action === 'upvote')

    this.downvoteTarget.classList.toggle('active', action === 'downvote')

  }

}

JS

}

# Log helper - pure zsh
log() {

  typeset timestamp="${$(strftime '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS)}"

  print -r "[${timestamp}] $*"

}

# Check if app already exists (idempotency)
check_app_exists() {

  typeset app_name=$1

  typeset marker_file=$2

  if [[ -f $marker_file ]]; then
    log "App $app_name already generated (found $marker_file), skipping"

    return 0

  fi

  return 1

}

# Setup Rails 8 authentication
setup_authentication() {

  if [[ -f "app/models/session.rb" ]]; then

    log "Rails 8 authentication already generated"

  else

    bin/rails generate authentication

    bin/rails db:migrate

  fi

}

# ═══════════════════════════════════════════════════════════════════════════════
# ADDITIONAL SHARED FUNCTIONS - Extracted from app generators per master.yml
# ═══════════════════════════════════════════════════════════════════════════════

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1 || { log "ERROR: $1 not found"; exit 1; }
}

# NOTE: For adding gems, prefer install_gem() which checks for duplicates,
# or use `bundle add <gem> --skip-install` which is idempotent.
# Avoid raw `cat >> Gemfile` as it creates duplicates on re-run.

# Install gem idempotently
install_gem() {
  typeset gem_name="$1"
  grep -q "gem ['\"]${gem_name}['\"]" Gemfile 2>/dev/null || {
    print -r -- "gem \"${gem_name}\"" >> Gemfile
    bundle install
  }
}

# Setup full Rails 8 app with Solid Stack
setup_full_app() {
  typeset app_name="$1"
  typeset app_dir="${BASE_DIR:-/home/dev/rails}/${app_name}"

  [[ -d "$app_dir" ]] || mkdir -p "$app_dir"
  cd "$app_dir"

  if [[ ! -f "config/application.rb" ]]; then
    log "Creating Rails 8 application: $app_name"
    rails new . --database=postgresql --skip-git --css=tailwind --javascript=importmap
  fi

  # Add production gem stack (idempotent)
  grep -q "solid_queue" Gemfile || cat >> Gemfile << 'SOLIDGEMS'

# Rails 8 Solid Stack
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# Async production server
gem "falcon"
gem "thruster"

# HTTP middleware
gem "rack-attack"

# Database
gem "pg"
gem "pgvector"

# Utilities
gem "pagy"
gem "image_processing"
SOLIDGEMS

  # Remove legacy gems if present
  sed -i '/gem ["\x27]devise["\x27]/d; /gem ["\x27]devise-guests["\x27]/d; /gem ["\x27]stimulus_reflex["\x27]/d; /gem ["\x27]cable_ready["\x27]/d' Gemfile 2>/dev/null || true

  bundle install
  bin/rails generate solid_queue:install 2>/dev/null || true
  bin/rails generate solid_cache:install 2>/dev/null || true
  bin/rails generate solid_cable:install 2>/dev/null || true
}

# Add Rails 8 rate limiting to ApplicationController
setup_rate_limiting() {
  typeset ctrl="app/controllers/application_controller.rb"
  grep -q "rate_limit" "$ctrl" 2>/dev/null && return 0
  sed -i 's/class ApplicationController < ActionController::Base/class ApplicationController < ActionController::Base\n  rate_limit to: 1000, within: 1.minute, by: -> { request.remote_ip }\n/' "$ctrl" 2>/dev/null || true
  log "Rate limiting added to ApplicationController"
}

# Generate cursor-based infinite scroll controller (Turbo Frames + IntersectionObserver)
# Usage: generate_infinite_scroll_controller_for "Post" "Post.all.order(created_at: :desc)"
generate_infinite_scroll_reflex() {
  typeset model_name="$1"
  typeset query="${2:-${model_name}.all.order(created_at: :desc)}"
  typeset model_lower="${model_name:l}"
  typeset model_plural="${model_lower}s"

  mkdir -p app/controllers
  cat > "app/controllers/${model_plural}_controller.rb" << RUBY
class ${(C)model_name}sController < ApplicationController
  def index
    @pagy, @${model_plural} = pagy(${query})
  end

  def more
    cursor = params[:cursor].to_i
    @pagy, @${model_plural} = pagy(${query}.where("id < ?", cursor))
    render partial: "shared/infinite_items",
           locals: { items: @${model_plural}, pagy: @pagy, resource: :${model_plural} }
  end
end
RUBY

  mkdir -p app/views/shared
  cat > app/views/shared/_infinite_items.html.erb << 'ERB'
<% items.each do |item| %>
  <%= render item %>
<% end %>
<% if pagy.next %>
  <div data-controller="infinite-scroll"
       data-infinite-scroll-url-value="<%= url_for(action: :more, cursor: items.last.id) %>">
    <span data-infinite-scroll-target="sentinel"></span>
  </div>
<% end %>
ERB
}

# Generate base InfiniteScroll concern (Turbo Frames, no StimulusReflex)
generate_base_infinite_scroll_reflex() {
  mkdir -p app/controllers/concerns
  cat > app/controllers/concerns/infinite_scrollable.rb << 'RUBY'
module InfiniteScrollable
  extend ActiveSupport::Concern

  included do
    def more
      cursor = params[:cursor].to_i
      scope = infinite_scroll_scope
      scope = scope.where("id < ?", cursor) if cursor.positive?
      @pagy, @items = pagy(scope)
      render partial: "shared/infinite_items",
             locals: { items: @items, pagy: @pagy, resource: controller_name.to_sym }
    end
  end

  private

  def infinite_scroll_scope
    raise NotImplementedError, "#{self.class}#infinite_scroll_scope must be defined"
  end
end
RUBY
}

# Generate infinite scroll Stimulus controller
generate_infinite_scroll_controller() {
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/infinite_scroll_controller.js << 'JS'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { page: { type: Number, default: 1 }, loading: { type: Boolean, default: false } }

  connect() {
    this.observer = new IntersectionObserver(entries => {
      if (entries[0].isIntersecting && !this.loadingValue) this.loadMore()
    }, { threshold: 0.1 })
    this.observer.observe(this.element.querySelector("[data-sentinel]") || this.element.lastElementChild)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  async loadMore() {
    this.loadingValue = true
    this.pageValue++
    this.stimulate(`${this.element.dataset.reflex}#load_more`, { page: this.pageValue })
    this.loadingValue = false
  }
}
JS
}

# Generate VotesController with Turbo Stream responses (replaces VoteReflex)
generate_vote_reflex() {
  mkdir -p app/controllers
  cat > app/controllers/votes_controller.rb << 'RUBY'
class VotesController < ApplicationController
  ALLOWED_TYPES = %w[Post Comment].freeze

  before_action :set_votable

  def upvote
    @votable.upvote_by(current_user)
    respond_with_turbo_stream
  end

  def downvote
    @votable.downvote_by(current_user)
    respond_with_turbo_stream
  end

  def destroy
    @votable.unvote_by(current_user)
    respond_with_turbo_stream
  end

  private

  def set_votable
    type = params[:votable_type]
    raise ActionController::BadRequest, "Invalid votable type" unless ALLOWED_TYPES.include?(type)

    @votable = type.constantize.find(params[:votable_id])
  end

  def respond_with_turbo_stream
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "vote-#{@votable.class.name.downcase}-#{@votable.id}",
          partial: "shared/vote",
          locals: { votable: @votable }
        )
      end
      format.json { render json: { score: @votable.cached_votes_score }, status: :ok }
    end
  end
end
RUBY
}

# Generate MessagesController with Action Cable broadcast (replaces ChatReflex)
generate_chat_reflex() {
  mkdir -p app/controllers
  cat > app/controllers/messages_controller.rb << 'RUBY'
class MessagesController < ApplicationController
  before_action :authenticate_user!

  def create
    @message = Message.new(message_params)
    @message.user = current_user

    if @message.save
      broadcast_message(@message)
      head :ok
    else
      render partial: "messages/form", locals: { message: @message },
             status: :unprocessable_entity
    end
  end

  private

  def message_params
    params.require(:message).permit(:content, :receiver_id, :anonymous)
  end

  def broadcast_message(message)
    participants = [current_user, message.receiver].compact.sort_by(&:id)
    participants.each do |user|
      Turbo::StreamsChannel.broadcast_append_to(
        "messages_#{user.id}",
        target: "messages",
        partial: "messages/message",
        locals: { message: message }
      )
    end
  end
end
RUBY
}

# Generate shared vote partial
generate_vote_partial() {
  mkdir -p app/views/shared
  cat > app/views/shared/_vote.html.erb << 'ERB'
<div id="vote-<%= votable.class.name.downcase %>-<%= votable.id %>" 
     data-controller="vote" 
     data-vote-type-value="<%= votable.class.name.tableize %>" 
     data-vote-id-value="<%= votable.id %>">
  <button data-action="vote#vote" data-vote-action-param="upvote" data-vote-target="upvote">▲</button>
  <span data-vote-target="score"><%= votable.cached_votes_score %></span>
  <button data-action="vote#vote" data-vote-action-param="downvote" data-vote-target="downvote">▼</button>
</div>
ERB
}

# Generate Turbo Stream templates for a resource
# Usage: generate_turbo_views "posts" "post"
generate_turbo_views() {
  typeset plural="$1"
  typeset singular="$2"
  
  mkdir -p "app/views/${plural}"
  
  cat > "app/views/${plural}/create.turbo_stream.erb" << ERB
<%= turbo_stream.prepend "${plural}", partial: "${plural}/${singular}", locals: { ${singular}: @${singular} } %>
<%= turbo_stream.update "new_${singular}_form", partial: "${plural}/form", locals: { ${singular}: ${(C)singular}.new } %>
ERB

  cat > "app/views/${plural}/update.turbo_stream.erb" << ERB
<%= turbo_stream.replace @${singular} %>
ERB

  cat > "app/views/${plural}/destroy.turbo_stream.erb" << ERB
<%= turbo_stream.remove @${singular} %>
ERB
}

# Generate search controller with live search
generate_search_controller() {
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/search_controller.js << 'JS'
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: String, debounce: { type: Number, default: 300 } }

  connect() {
    this.timeout = null
  }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.performSearch(), this.debounceValue)
  }

  async performSearch() {
    const query = this.inputTarget.value.trim()
    if (query.length < 2) { this.resultsTarget.innerHTML = ""; return }

    const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, {
      headers: { "Accept": "text/vnd.turbo-stream.html" }
    })

    if (response.ok) {
      this.resultsTarget.innerHTML = await response.text()
    }
  }
}
JS
}

# Commit all changes with a message (idempotent — no-ops if nothing to commit)
commit() {
  typeset msg="$1"
  git add -A && git commit -m "$msg" --quiet 2>/dev/null || true
}

# Generate all standard Stimulus controllers in one call
generate_all_stimulus_controllers() {
  generate_infinite_scroll_controller
  generate_search_controller
  generate_voting_stimulus
}

# Alias for generate_application_scss (backwards-compat)
generate_default_css() { generate_application_scss "$@"; }

# Run Rails migrations; exit non-zero on failure
migrate_db() {
  log "Running migrations..."
  bin/rails db:create db:migrate 2>&1 | tail -5 || { log "ERROR: db:migrate failed" >&2; return 1; }
}
