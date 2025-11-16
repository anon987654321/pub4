#!/usr/bin/env zsh
set -euo pipefail

# Central module loader for Rails apps per master.json v44.3.0
# Consolidated from 20 files → 8 focused modules

SCRIPT_DIR="${0:a:h}"

# Core infrastructure
source "${SCRIPT_DIR}/@core_setup.sh"
source "${SCRIPT_DIR}/@rails8_stack.sh"

# UI/Frontend
source "${SCRIPT_DIR}/@stimulus_controllers.sh"
source "${SCRIPT_DIR}/@pwa_setup.sh"
source "${SCRIPT_DIR}/@reflex_patterns.sh"
source "${SCRIPT_DIR}/@view_generators.sh"

# Feature domains (consolidated from competitors)
source "${SCRIPT_DIR}/@social_features.sh"      # reddit+twitter+voting
source "${SCRIPT_DIR}/@chat_features.sh"        # messaging+messenger
source "${SCRIPT_DIR}/@marketplace_features.sh" # airbnb+booking+momondo+travel
source "${SCRIPT_DIR}/@ai_features.sh"          # langchain

source "${SCRIPT_DIR}/@route_helpers.sh"

# Additional setup functions
install_stimulus_component() {
    local component_name="$1"

    log "Installing Stimulus component: $component_name"

    yarn add "@stimulus-components/${component_name}"

    log "Stimulus component installed: $component_name"

    log "Register in app/javascript/controllers/index.js"

}

setup_full_app() {
    local app_name="$1"

    log "Setting up full Rails application: $app_name"

    mkdir -p "$BASE_DIR/$app_name"
    cd "$BASE_DIR/$app_name"

    if [ ! -f "config/application.rb" ]; then
        log "Creating new Rails application"

        rails new . --api --database=postgresql --skip-git --skip-bundle

    fi

    setup_core
    setup_postgresql

    setup_redis

    setup_rails

    setup_devise

}

setup_devise() {
    log "Setting up Devise authentication (legacy - use setup_rails8_authentication)"

    install_gem "devise"

    if [ ! -f "config/initializers/devise.rb" ]; then
        bin/rails generate devise:install

        bin/rails generate devise User

    fi

}

setup_stripe() {
    log "Setting up Stripe payment processing"
    install_gem "stripe"
    # Create basic Stripe configuration

    if [ ! -f "config/initializers/stripe.rb" ]; then
        cat > config/initializers/stripe.rb << EOF
Rails.application.configure do

  config.stripe = {
    publishable_key: ENV.fetch('STRIPE_PUBLISHABLE_KEY', ''),
    secret_key: ENV.fetch('STRIPE_SECRET_KEY', '')
  }
end
Stripe.api_key = Rails.application.config.stripe[:secret_key]
EOF
    fi
}

setup_mapbox() {
    log "Setting up Mapbox integration"
    # Add Mapbox configuration
    if [ ! -f "config/initializers/mapbox.rb" ]; then

        cat > config/initializers/mapbox.rb << EOF
Rails.application.configure do

  config.mapbox = {
    access_token: ENV.fetch('MAPBOX_ACCESS_TOKEN', '')
  }
end
EOF
    fi
}
setup_live_search() {
    log "Setting up live search functionality"
    install_gem "stimulus_reflex"
    # Create basic search reflex

    if [ ! -f "app/reflexes/search_reflex.rb" ]; then
        mkdir -p app/reflexes
        cat > app/reflexes/search_reflex.rb << EOF

class SearchReflex < ApplicationReflex
  def search
    @query = element.value
    # Implement search logic based on current model
  end
end
EOF
    fi
}
setup_infinite_scroll_reflex() {
    log "Setting up InfiniteScrollReflex (Julian Rubisch pattern)"
    mkdir -p app/reflexes
    if [ ! -f "app/reflexes/infinite_scroll_reflex.rb" ]; then

        cat > app/reflexes/infinite_scroll_reflex.rb << 'INFINITEOF'
class InfiniteScrollReflex < ApplicationReflex

  include Pagy::Backend
  attr_reader :collection
  def load_more
    cable_ready.insert_adjacent_html(
      selector: selector,
      html: render(collection),

      position: position
    )
    cable_ready.broadcast
  end
  def page
    element.dataset.next_page
  end
  def position

    "beforebegin"
  end
  def selector

    raise NotImplementedError, "Override selector in subclass"
  end
end

INFINITEOF
    fi
}
setup_anon_posting() {
    log "Setting up anonymous posting capabilities"
    # Create anonymous posting service
    if [ ! -f "app/services/anonymous_post_service.rb" ]; then

        mkdir -p app/services
        cat > app/services/anonymous_post_service.rb << EOF

class AnonymousPostService
  def self.create_post(params, session_id)
    # Implementation for anonymous posting
    # Uses session-based identification
  end
end
EOF
    fi
}
setup_anon_chat() {
    log "Setting up anonymous chat"
    install_gem "redis"
    # Create anonymous chat channel

    if [ ! -f "app/channels/anonymous_chat_channel.rb" ]; then
        mkdir -p app/channels
        cat > app/channels/anonymous_chat_channel.rb << EOF

class AnonymousChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "anonymous_chat_\#{params[:room_id]}"
  end
  def speak(data)
    ActionCable.server.broadcast("anonymous_chat_\#{params[:room_id]}", data)
  end
end

EOF
    fi
}
setup_expiry_job() {
    log "Setting up content expiry job"
    if [ ! -f "app/jobs/content_expiry_job.rb" ]; then
        mkdir -p app/jobs

        cat > app/jobs/content_expiry_job.rb << EOF
class ContentExpiryJob < ApplicationJob

  queue_as :default
  def perform
    # Clean up expired anonymous content
    # Implementation varies by application
  end

end
EOF
    fi
}
setup_seeds() {
    log "Setting up database seeds"
    if [ ! -f "db/seeds.rb" ] || [ ! -s "db/seeds.rb" ]; then
        cat > db/seeds.rb << EOF

# Seeds for #{APP_NAME}
# Create sample data for development

if Rails.env.development?
  # Add sample data creation here
  puts "Created sample data for \#{Rails.env} environment"
end

EOF
    fi
}
setup_pwa() {
    log "Setting up Progressive Web App features (Rails 8 + PWA.dev best practices)"
    source "${SCRIPT_DIR}/__shared/@pwa_setup.sh"
    setup_full_pwa "${APP_NAME}"
    log "PWA setup complete. Add meta tags to application layout."
}

setup_i18n() {
    log "Setting up internationalization"
    # Create Norwegian locale file
    mkdir -p config/locales

    if [ ! -f "config/locales/no.yml" ]; then
        cat > config/locales/no.yml << EOF

no:
  app_name: "${APP_NAME}"
  common:
    save: "Lagre"
    cancel: "Avbryt"
    delete: "Slett"
    edit: "Rediger"
EOF
    fi
}
setup_falcon() {
    log "Setting up Falcon web server"
    install_gem "falcon"
    # Create Falcon configuration

    if [ ! -f "falcon.rb" ]; then
        cat > falcon.rb << EOF
#!/usr/bin/env ruby

require_relative 'config/environment'
app = Rails.application
app.load_tasks
run app
EOF

        chmod +x falcon.rb
    fi

}
setup_stimulus_components() {
    log "Setting up Stimulus components"
    # Pure zsh: pattern matching instead of grep
    if [[ -f "package.json" ]]; then

        local pkg_json=$(<package.json)
        if [[ "$pkg_json" != *stimulus* ]]; then

            yarn add stimulus
        fi
    else
        yarn add stimulus
    fi
    # Create basic stimulus application
    if [ ! -f "app/javascript/controllers/application.js" ]; then
        mkdir -p app/javascript/controllers
        cat > app/javascript/controllers/application.js << EOF

import { Application } from "stimulus"
import { definitionsFromContext } from "stimulus/webpack-helpers"
const application = Application.start()
const context = require.context(".", true, /\.js$/)
application.load(definitionsFromContext(context))
EOF

    fi
}
setup_vote_controller() {
    log "Setting up voting controller"
    if [ ! -f "app/controllers/votes_controller.rb" ]; then
        cat > app/controllers/votes_controller.rb << EOF

class VotesController < ApplicationController
  def up

    # Implementation for upvote
    render json: { status: 'success' }
  end
  def down
    # Implementation for downvote
    render json: { status: 'success' }
  end

end
EOF
    fi
}
generate_social_models() {
    log "Generating social models"
    # Generate basic social models if they don't exist
    if ! bin/rails runner "User" 2>/dev/null; then

        bin/rails generate model User email:string username:string
    fi

    if ! bin/rails runner "Post" 2>/dev/null; then
        bin/rails generate model Post title:string content:text user:references
    fi
}

# Pure zsh route adder - replaces head/tail with parameter expansion
# Complies with master.json:608 (never use head/tail/sed/awk)
add_routes_block() {
    local routes_block="$1"

    local routes_file="config/routes.rb"

    # Read all lines, remove last 'end', append routes, add 'end'

    local routes_lines=("${(@f)$(<$routes_file)}")

    {
        print -l "${routes_lines[1,-2]}"

        print -r -- "$routes_block"
        print "end"

    } > "$routes_file"

}

commit()() {

    local message="${1:-Update application setup}"

    log "Committing changes: $message"
    # Only commit if in git repository

    if [ -d ".git" ]; then
        git add -A
        git commit -m "$message" || log "Nothing to commit"

    else
        log "Not a git repository, skipping commit"
    fi
}
migrate_db() {
    log "Migrating database"
    bin/rails db:create db:migrate
}

generate_turbo_views() {
    local model_name="$1"
    local singular_name="$2"
    log "Generating Turbo views for $model_name"

    # Generate basic Turbo-enabled views
    mkdir -p "app/views/$model_name"
    if [ ! -f "app/views/$model_name/index.html.erb" ]; then
        cat > "app/views/$model_name/index.html.erb" << EOF

<%= turbo_frame_tag "$model_name" do %>
  <div data-controller="infinite-scroll">

    <% @${model_name}.each do |${singular_name}| %>
      <%= render ${singular_name} %>
    <% end %>
  </div>
<% end %>
EOF
    fi
}
# Parameterized code generators to reduce duplication
generate_infinite_scroll_reflex() {
    local model_class="$1"
    # Pure zsh: lowercase and pluralize (simple English pluralization)
    local default_plural="${model_class:l}s"
    local model_plural="${2:-$default_plural}"
    log "Generating infinite scroll reflex for $model_class"
    mkdir -p app/reflexes
    cat > "app/reflexes/${model_plural}_infinite_scroll_reflex.rb" << EOF
class ${model_class}sInfiniteScrollReflex < InfiniteScrollReflex
  def load_more

    @pagy, @collection = pagy(${model_class}.where(community: ActsAsTenant.current_tenant).order(created_at: :desc), page: page)
    super
  end
end
EOF
}
generate_mapbox_controller() {
    local controller_name="$1"
    local center_lng="${2:-5.3467}"
    local center_lat="${3:-60.3971}"

    local model_plural="${4:-listings}"
    log "Generating Mapbox controller: $controller_name"
    mkdir -p app/javascript/controllers
    cat > "app/javascript/controllers/${controller_name}_controller.js" << EOF
import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

import MapboxGeocoder from "mapbox-gl-geocoder"
export default class extends Controller {
  static values = { apiKey: String, ${model_plural}: Array }
  connect() {
    mapboxgl.accessToken = this.apiKeyValue

    this.map = new mapboxgl.Map({
      container: this.element,

      style: "mapbox://styles/mapbox/streets-v11",
      center: [${center_lng}, ${center_lat}],
      zoom: 12
    })
    this.map.addControl(new MapboxGeocoder({
      accessToken: this.apiKeyValue,
      mapboxgl: mapboxgl
    }))

    this.map.on("load", () => {
      this.addMarkers()
    })
  }

  addMarkers() {
    this.${model_plural}Value.forEach(item => {
      new mapboxgl.Marker({ color: "#1a73e8" })
        .setLngLat([item.lng, item.lat])

        .setPopup(new mapboxgl.Popup().setHTML(\`<h3>\${item.title}</h3><p>\${item.description}</p>\`))
        .addTo(this.map)
    })
  }
}
EOF
}
generate_insights_controller() {
    local output_target="${1:-insights-output}"
    log "Generating insights Stimulus controller"
    mkdir -p app/javascript/controllers

    cat > app/javascript/controllers/insights_controller.js << EOF
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {

  static targets = ["output"]
  analyze(event) {
    event.preventDefault()

    if (!this.hasOutputTarget) {
      console.error("InsightsController: Output target not found")

      return
    }
    this.outputTarget.innerHTML = "<i class='fas fa-spinner fa-spin' aria-label='Analyzing'></i>"
    this.stimulate("InsightsReflex#analyze")
  }
}
EOF
}
setup_stimulus_reflex() {
    log "Setting up StimulusReflex and CableReady for real-time reactivity"
    install_gem "stimulus_reflex"
    install_gem "cable_ready"

    if [ ! -f "app/reflexes/application_reflex.rb" ]; then
        bin/rails generate stimulus_reflex:install
    fi
    setup_infinite_scroll_reflex
    setup_filterable_reflex
    setup_template_reflex
    log "StimulusReflex patterns installed (InfiniteScroll, Filterable, Template)"
}

setup_filterable_reflex() {
    log "Setting up FilterableReflex (Julian Rubisch pattern)"
    mkdir -p app/reflexes app/controllers/concerns app/filters
    if [ ! -f "app/reflexes/filter_reflex.rb" ]; then

        cat > app/reflexes/filter_reflex.rb << 'FILTEREOF'
class FilterReflex < ApplicationReflex

  include Filterable

  def filter
    resource, param = element.dataset.to_h.fetch_values(:resource, :param)
    value = if element["type"] == "checkbox"
      element.checked

    else
      element.dataset.value || element.value
    end
    set_filter_for!(resource, param, value)
  end
end
FILTEREOF

    fi
    if [ ! -f "app/controllers/concerns/filterable.rb" ]; then
        cat > app/controllers/concerns/filterable.rb << 'CONCERNEOF'
module Filterable
  extend ActiveSupport::Concern

  included do
    if respond_to?(:helper_method)
      helper_method :filter_active_for?
      helper_method :filter_for

    end
  end
  def filter_active_for?(resource, attribute, value = true)
    filter = filter_for(resource)
    filter.active_for?(attribute, value)
  end

  private
  def filter_for(resource)
    "#{resource}Filter".constantize.new(session)
  end

  def set_filter_for!(resource, param, value)

    filter_for(resource).merge!(param, value)
  end
end

CONCERNEOF
    fi
}
setup_template_reflex() {
    log "Setting up TemplateReflex for dynamic UI composition (Julian Rubisch pattern)"
    mkdir -p app/reflexes
    if [ ! -f "app/reflexes/template_reflex.rb" ]; then

        cat > app/reflexes/template_reflex.rb << 'TEMPLATEEOF'
class TemplateReflex < ApplicationReflex

  def insert
    templates << new_template
    morph :nothing
  end
  def remove(uuid = element.dataset.uuid)
    templates.delete_if { |template| template.uuid == uuid }
    morph :nothing
  end

  private
  def templates
    session[:templates] ||= []
  end

  def new_template

    OpenStruct.new(uuid: SecureRandom.urlsafe_base64)
  end
end

TEMPLATEEOF
    fi
}
generate_model_reflex() {
    local model_class="$1"
    # Pure zsh: lowercase and pluralize (simple English pluralization)
    local default_plural="${model_class:l}s"

    local model_plural="${2:-$default_plural}"
    local tenant_scope="${3:-}"
    log "Generating ${model_class} infinite scroll reflex"
    mkdir -p app/reflexes
    local scope_clause=""
    if [ -n "$tenant_scope" ]; then

        scope_clause=".where(${tenant_scope})"

    fi
    cat > "app/reflexes/${model_plural}_infinite_scroll_reflex.rb" << EOF
class ${model_class}sInfiniteScrollReflex < InfiniteScrollReflex
  def load_more
    @pagy, @collection = pagy(

      ${model_class}${scope_clause}.order(created_at: :desc),
      page: page
    )
    super
  end
  def selector
    "#sentinel"
  end
end

EOF
}
install_yarn_package() {
    local package_name="$1"
    # Pure zsh: pattern matching instead of grep
    if [[ -f "package.json" ]]; then

        local pkg_json=$(<package.json)
        if [[ "$pkg_json" != *"\"$package_name\""* ]]; then
            log "Installing yarn package: $package_name"
            yarn add "$package_name"
        else
            log "Yarn package already installed: $package_name"
        fi
    else
        log "Installing yarn package: $package_name"
        yarn add "$package_name"
    fi
}
setup_stimulus_use() {
    log "Setting up stimulus-use for IntersectionObserver and other helpers"
    install_yarn_package "stimulus-use"
}

generate_show_view() {
    local model_singular="$1"
    local model_plural="$2"
    log "Generating show view for $model_singular"

    mkdir -p "app/views/${model_plural}"
    cat > "app/views/${model_plural}/show.html.erb" << 'SHOWEOF'
<%= turbo_frame_tag dom_id(@<%= model_singular %>) do %>
  <%= tag.article class: "detail-view", role: "article" do %>

    <%= tag.header do %>
      <%= tag.h1 @<%= model_singular %>.title %>
      <%= tag.div class: "meta" do %>
        <%= tag.span t("brgen.posted_by", user: @<%= model_singular %>.user.email) %>
        <%= tag.span @<%= model_singular %>.created_at.strftime("%Y-%m-%d %H:%M") %>
      <% end %>
    <% end %>
    <%= tag.section class: "content" do %>
      <% if @<%= model_singular %>.photos.attached? %>
        <%= tag.div class: "photos" do %>
          <% @<%= model_singular %>.photos.each do |photo| %>

            <%= image_tag photo, alt: t("brgen.listing_photo", title: @<%= model_singular %>.title) %>
          <% end %>
        <% end %>
      <% end %>
      <%= tag.div class: "description" do %>
        <%= simple_format @<%= model_singular %>.description %>
      <% end %>
      <%= tag.dl class: "attributes" do %>

        <%= tag.dt t("brgen.price") %>
        <%= tag.dd number_to_currency(@<%= model_singular %>.price) %>
        <%= tag.dt t("brgen.category") %>

        <%= tag.dd @<%= model_singular %>.category %>
        <%= tag.dt t("brgen.location") %>
        <%= tag.dd @<%= model_singular %>.location %>

        <%= tag.dt t("brgen.status") %>
        <%= tag.dd @<%= model_singular %>.status %>

      <% end %>
    <% end %>

    <% if @<%= model_singular %>.lat.present? && @<%= model_singular %>.lng.present? %>
      <%= tag.div id: "map",
                  data: {
                    controller: "mapbox",

                    mapbox_api_key_value: ENV['MAPBOX_TOKEN'],
                    mapbox_<%= model_plural %>_value: [@<%= model_singular %>].to_json
                  },
                  style: "height: 400px; margin: 2rem 0;" %>
    <% end %>
    <%= render partial: "shared/vote", locals: { votable: @<%= model_singular %> } %>
    <%= tag.footer class: "actions" do %>
      <%= link_to t("brgen.back"), <%= model_plural %>_path, class: "button secondary" %>
      <% if @<%= model_singular %>.user == current_user || current_user&.admin? %>

        <%= link_to t("brgen.edit"), edit_<%= model_singular %>_path(@<%= model_singular %>), class: "button" %>

        <%= button_to t("brgen.delete"), <%= model_singular %>_path(@<%= model_singular %>),
                      method: :delete,
                      class: "button danger",
                      data: { turbo_confirm: t("brgen.confirm_delete") } %>
      <% end %>
    <% end %>
  <% end %>
<% end %>
SHOWEOF
    # Pure zsh: replace template variables with parameter expansion (no sed)
    local template=$(<"app/views/${model_plural}/show.html.erb")
    template="${template//<%%= model_singular %>/${model_singular}}"
    template="${template//<%%= model_plural %>/${model_plural}}"

    print -r -- "$template" > "app/views/${model_plural}/show.html.erb"
}
generate_new_view() {
    local model_singular="$1"
    local model_plural="$2"
    log "Generating new view for $model_singular"

    mkdir -p "app/views/${model_plural}"
    cat > "app/views/${model_plural}/new.html.erb" << 'NEWEOF'
<%= turbo_frame_tag "new_<%= model_singular %>" do %>
  <%= tag.article class: "form-container" do %>

    <%= tag.header do %>
      <%= tag.h1 t("brgen.new_<%= model_singular %>") %>
    <% end %>
    <%= render "form", <%= model_singular %>: @<%= model_singular %> %>
    <%= tag.footer do %>
      <%= link_to t("brgen.cancel"), <%= model_plural %>_path, class: "button secondary" %>
    <% end %>

  <% end %>

<% end %>
NEWEOF
    # Pure zsh: replace template variables with parameter expansion (no sed)
    local template=$(<"app/views/${model_plural}/new.html.erb")
    template="${template//<%%= model_singular %>/${model_singular}}"
    template="${template//<%%= model_plural %>/${model_plural}}"

    print -r -- "$template" > "app/views/${model_plural}/new.html.erb"
}
generate_edit_view() {
    local model_singular="$1"
    local model_plural="$2"
    log "Generating edit view for $model_singular"

    mkdir -p "app/views/${model_plural}"
    cat > "app/views/${model_plural}/edit.html.erb" << 'EDITEOF'
<%= turbo_frame_tag dom_id(@<%= model_singular %>) do %>
  <%= tag.article class: "form-container" do %>

    <%= tag.header do %>
      <%= tag.h1 t("brgen.edit_<%= model_singular %>") %>
    <% end %>
    <%= render "form", <%= model_singular %>: @<%= model_singular %> %>
    <%= tag.footer do %>
      <%= link_to t("brgen.cancel"), <%= model_singular %>_path(@<%= model_singular %>), class: "button secondary" %>
    <% end %>

  <% end %>

<% end %>
EDITEOF
    # Pure zsh: replace template variables with parameter expansion (no sed)
    local template=$(<"app/views/${model_plural}/edit.html.erb")
    template="${template//<%%= model_singular %>/${model_singular}}"
    template="${template//<%%= model_plural %>/${model_plural}}"

    print -r -- "$template" > "app/views/${model_plural}/edit.html.erb"
}
generate_crud_views() {
    local model_singular="$1"
    local model_plural="$2"
    log "Generating all CRUD views for ${model_plural}"

    generate_show_view "$model_singular" "$model_plural"
    generate_new_view "$model_singular" "$model_plural"
    generate_edit_view "$model_singular" "$model_plural"
    log "CRUD views generated: show, new, edit"

}
