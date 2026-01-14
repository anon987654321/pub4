#!/usr/bin/env zsh
# Shared functions for Rails app generators

# Per master.yml v206 workflow: Extract duplication, DRY, modern zsh

# Modern zsh: use parameter expansion, typeset, ((...)), [[...]]
emulate -L zsh

setopt extended_glob warn_create_global

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
  print -r > $target << RUBY
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

  local app_name="$1"

  local description="$2"

  mkdir -p app/views/layouts
  cat > app/views/layouts/application.html.erb << 'LAYOUT'
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

# Setup Stimulus Reflex (if needed)
setup_stimulus_reflex() {

  grep -q "stimulus_reflex" Gemfile || cat >> Gemfile << 'GEMS'

# Real-time with Stimulus Reflex
gem "stimulus_reflex", "~> 3.5"

gem "cable_ready", "~> 5.0"

GEMS

  bundle install
  bin/rails stimulus_reflex:install

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

    const response = await fetch(\`/\${this.typeValue}/\${this.idValue}/\${action}\`, {

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

  if grep -q "devise" Gemfile; then

    log "Devise already in Gemfile"

  else

    cat >> Gemfile << 'GEMS'

gem "devise"

gem "devise-guests"

GEMS

    bundle install

    bin/rails generate devise:install

    bin/rails generate devise User

    bin/rails generate devise_guests:install

    bin/rails db:migrate

  fi

}

