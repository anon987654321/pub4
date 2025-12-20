#!/usr/bin/env zsh
set -euo pipefail

# StimulusReflex patterns - InfiniteScroll, Filterable, Template
# Per master.json:modern_stack:stimulus_reflex

setup_stimulus_reflex() {
    log "Setting up StimulusReflex and CableReady for real-time reactivity"

    install_gem "stimulus_reflex"
    install_gem "cable_ready"

    if [ ! -f "app/reflexes/application_reflex.rb" ]; then
        bin/rails generate stimulus_reflex:install
    fi
    
    # Add error handling to ApplicationReflex
    if [ -f "app/reflexes/application_reflex.rb" ]; then
        if ! grep -q "rescue_from" app/reflexes/application_reflex.rb; then
            cat >> app/reflexes/application_reflex.rb << 'APPERROR'

  # Error handling for all reflexes
  rescue_from StandardError do |exception|
    logger.error "Reflex error: #{exception.message}"
    logger.error exception.backtrace.join("\n")
    
    morph :nothing
    cable_ready[stream_name].console_log(
      message: "An error occurred. Please try again."
    ).broadcast
  end
APPERROR
        fi
    fi
    
    setup_infinite_scroll_reflex
    setup_filterable_reflex

    setup_template_reflex
    log "StimulusReflex patterns installed (InfiniteScroll, Filterable, Template)"
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
    morph selector, render(collection)
  end

  def page
    element.dataset.next_page
  end

  def selector
    raise NotImplementedError, "Override selector in subclass"
  end
end
INFINITEOF
    fi
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
    dom_id(${model_class}.new, :list)
  end
end
EOF
}
